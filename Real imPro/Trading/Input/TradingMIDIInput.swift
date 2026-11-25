import Foundation
import CoreMIDI

// MARK: - Trading / Input / CoreMIDI 实时输入客户端
//
// M1 · 纯新增 · **不依赖也不修改** MidiPlayer / Views / 任何现有代码
//
// 对应 Java:
//   src/imp/midi/MidiManager.java:175 findInstalledDevices / :264-298 getMidiInInfo,getInDeviceInfo
//   src/imp/midi/MidiManager.java:479   in.getTransmitter().setReceiver(publicTransmitter)
//
// 设计要点（见离线设计方案 §3）：
//   · CoreMIDI 回调**不在主线程**：回调里只做"解析 + 打时间戳 + 交给 onEvent"，绝不跑生成/UI；
//   · 设备热插拔通过 MIDIClientCreateWithBlock 的 setup-changed 通知感知；
//   · 支持 USB 类兼容键盘（M1 目标）。**蓝牙 MIDI 需 Info.plist 权限键，属集成点 #5，M1 不做**。

final class TradingMIDIInput {

    // MARK: - 对外回调（都在 CoreMIDI 回调线程上调用）

    /// 收到一个音符事件
    var onEvent: ((TradingMIDIEvent) -> Void)?

    /// 设备列表发生变化（插拔）
    var onDevicesChanged: (([TradingMIDIDevice]) -> Void)?

    /// 出错（连接失败等）
    var onError: ((String) -> Void)?

    // MARK: - 内部状态

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var clientName: String

    /// 已连上的输入源
    private var connectedSources: [MIDIEndpointRef] = []

    /// 每个已连接源对应的 uniqueID（用于事件标注来源）
    private var sourceIDs: [MIDIEndpointRef: Int32] = [:]

    /// 运行状态（running status）**跨包保持**：某些设备会在一个包里只发数据字节，
    /// 沿用上一个包的状态字节（MIDI 线上的合法用法）。CoreMIDI 按包回调，
    /// 因此必须把它提到实例级，否则会漏掉这类事件。
    /// （由集成测试发现并修正：见 M1 报告"回环测试"节）
    private var runningStatus: UInt8 = 0

    private(set) var isRunning = false

    init(clientName: String = "RealimPro Trading Input") {
        self.clientName = clientName
    }

    deinit {
        stop()
    }

    // MARK: - 生命周期

    /// 建立 MIDI client 与输入端口。`CoreMIDI` 无需任何权限（USB 类兼容设备即插即用）。
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }

        // 1) client（带 setup 变化通知 → 热插拔）
        let notifyBlock: MIDINotifyBlock = { [weak self] notification in
            guard let self = self else { return }
            // kMIDIMsgSetupChanged = 设备增删；其余为对象属性变化
            if notification.pointee.messageID == .msgSetupChanged {
                // 自动重连：设备上线时立刻连接（先开软件后插线 / 省电醒来）
                self.connectAllAvailableSources()
                DispatchQueue.main.async {
                    self.onDevicesChanged?(self.availableDevices())
                }
            }
        }

        var status = MIDIClientCreateWithBlock(clientName as CFString, &client, notifyBlock)
        guard status == noErr else {
            onError?("MIDIClientCreateWithBlock 失败: \(status)")
            return false
        }

        // 2) 输入端口（读回调同样**不在主线程**）
        let readBlock: MIDIReadBlock = { [weak self] packetList, _ in
            self?.handle(packetList: packetList)
        }
        status = MIDIInputPortCreateWithBlock(client, "RealimPro Trading In" as CFString, &inputPort, readBlock)
        guard status == noErr else {
            onError?("MIDIInputPortCreateWithBlock 失败: \(status)")
            MIDIClientDispose(client)
            client = 0
            return false
        }

        isRunning = true

        // 3) 连接当前所有在线输入源
        connectAllAvailableSources()
        return true
    }

    /// 拆掉端口与 client
    func stop() {
        guard isRunning else { return }
        disconnectAll()
        if inputPort != 0 {
            MIDIPortDispose(inputPort)
            inputPort = 0
        }
        if client != 0 {
            MIDIClientDispose(client)
            client = 0
        }
        isRunning = false
    }

    // MARK: - 设备枚举

    /// 当前系统可见的 MIDI 输入源（在线与否都列出，便于 UI 提示"未插入"）
    ///
    /// 对应 Java `MidiManager.findInstalledDevices()` / `getMidiInInfo()`
    func availableDevices() -> [TradingMIDIDevice] {
        let count = MIDIGetNumberOfSources()
        var out: [TradingMIDIDevice] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            guard let endpoint = MIDIGetSource(i).nonZero else { continue }
            let name = TradingMIDIDevice.displayName(of: endpoint)
            let uniqueID = TradingMIDIDevice.intProperty(endpoint, kMIDIPropertyUniqueID)
            let offline = TradingMIDIDevice.intProperty(endpoint, kMIDIPropertyOffline) != 0
            out.append(TradingMIDIDevice(uniqueID: uniqueID, name: name, isOffline: offline, endpoint: endpoint))
        }
        return out
    }

    /// 已连接的源数量（M1 验收：插上 USB 键盘后应 > 0）
    var connectedSourceCount: Int { connectedSources.count }

    /// 已连接设备的描述（调试/验收用）
    func connectedDeviceSummary() -> String {
        let devices = availableDevices().filter { connectedSources.contains($0.endpoint) }
        if devices.isEmpty { return "（未连接任何 MIDI 输入）" }
        return devices.map { "\($0.name)#\($0.uniqueID)\($0.isOffline ? "[离线]" : "")" }.joined(separator: ", ")
    }

    // MARK: - 连接管理

    /// 完全重建所有输入源连接（热插拔安全：先断开所有，再连在线设备）
    func connectAllAvailableSources() {
        guard isRunning else { return }
        disconnectAll()
        for device in availableDevices() where !device.isOffline {
            _ = connect(device)
        }
    }

    /// 取消连接所有源。
    /// 用途：多端口键盘（如 Yamaha MX49/MX61 对外暴露 5 个端口）只保留**主端口**，
    /// 避免同一次按键被多个端口重复记录（一个音被记成多个音）。
    func disconnectAllSources() {
        guard isRunning else { return }
        disconnectAll()
    }

    /// 连接指定输入源
    @discardableResult
    func connect(_ device: TradingMIDIDevice) -> Bool {
        guard isRunning else { return false }
        if connectedSources.contains(device.endpoint) { return true }
        let refCon = UnsafeMutableRawPointer?.none
        let status = MIDIPortConnectSource(inputPort, device.endpoint, refCon)
        guard status == noErr else {
            onError?("连接「\(device.name)」失败: \(status)")
            return false
        }
        connectedSources.append(device.endpoint)
        sourceIDs[device.endpoint] = device.uniqueID
        return true
    }

    /// 断开指定输入源
    func disconnect(_ device: TradingMIDIDevice) {
        guard isRunning, connectedSources.contains(device.endpoint) else { return }
        MIDIPortDisconnectSource(inputPort, device.endpoint)
        connectedSources.removeAll { $0 == device.endpoint }
        sourceIDs[device.endpoint] = nil
    }

    private func disconnectAll() {
        for source in connectedSources {
            MIDIPortDisconnectSource(inputPort, source)
        }
        connectedSources.removeAll()
        sourceIDs.removeAll()
        runningStatus = 0
    }

    // MARK: - 收包与解析（运行在 CoreMIDI 回调线程）

    private func handle(packetList: UnsafePointer<MIDIPacketList>) {
        let numPackets = Int(packetList.pointee.numPackets)
        guard numPackets > 0 else { return }

        var packet = packetList.pointee.packet
        for _ in 0..<numPackets {
            let length = Int(packet.length)
            if length > 0 {
                let timeNs = TradingHostClock.normalized(packet.timeStamp)
                // 该包数据最多 256 字节（MIDIPacket.data 定长元组）
                withUnsafeBytes(of: packet.data) { raw in
                    parse(bytes: raw, length: length, timeNs: timeNs)
                }
            }
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    /// 解析一段原始 MIDI 字节流（支持 running status）。
    private func parse(bytes: UnsafeRawBufferPointer, length: Int, timeNs: UInt64) {
        var i = 0
        let maxLen = min(length, bytes.count)

        while i < maxLen {
            let byte = bytes[i]

            guard byte & 0x80 != 0 else {
                // 数据字节：需要 running status
                guard runningStatus != 0 else { i += 1; continue }
                emit(status: runningStatus, data: [byte], dataIndex: &i, available: maxLen, bytes: bytes, timeNs: timeNs, inProgress: nil)
                continue
            }

            // 状态字节
            if byte >= 0xF8 {
                // 实时消息（时钟/起停），无数据字节，不影响 running status
                i += 1
                continue
            }
            if byte >= 0xF0 {
                // 系统专用/系统公共：M1 不处理（SysEx 长度不定，跳过到下一个状态字节）
                runningStatus = 0
                i += 1
                // 跳过 SysEx 载荷至 0xF7
                if byte == 0xF0 {
                    while i < maxLen, bytes[i] != 0xF7 { i += 1 }
                    if i < maxLen { i += 1 }
                }
                continue
            }

            runningStatus = byte
            i += 1
            let high = byte & 0xF0
            let needData = (high == 0xC0 || high == 0xD0) ? 1 : 2
            guard i + needData <= maxLen else { break }
            let d0 = bytes[i]
            let d1 = needData == 2 ? bytes[i + 1] : 0
            i += needData

            switch high {
            case 0x80, 0x90:
                let channel = Int(byte & 0x0F)
                // 0x80 一定是 off；0x90 且 velocity == 0 也是 off（running status 兼容）
                let isOn = (high == 0x90) && (d1 > 0)
                let sourceID = currentSourceUniqueID()
                let event = TradingMIDIEvent(pitch: Int(d0),
                                             velocity: Int(d1),
                                             isNoteOn: isOn,
                                             channel: channel,
                                             hostTimeNs: timeNs,
                                             sourceUniqueID: sourceID)
                onEvent?(event)
            default:
                break // 其它通道消息（CC/Program/Bend/Aftertouch）M1 不需要
            }
        }
    }

    /// running-status 分支的兜底（当前实现已在上方内联处理，保留以免遗漏）
    private func emit(status: UInt8, data: [UInt8], dataIndex: inout Int, available: Int,
                      bytes: UnsafeRawBufferPointer, timeNs: UInt64, inProgress: Void?) {
        let high = status & 0xF0
        if high == 0x80 || high == 0x90 {
            let needData = 2
            var d: [UInt8] = []
            var k = dataIndex
            while d.count < needData, k < available {
                d.append(bytes[k])
                k += 1
            }
            guard d.count == needData else { dataIndex = available; return }
            let isOn = (high == 0x90) && (d[1] > 0)
            onEvent?(TradingMIDIEvent(pitch: Int(d[0]),
                                      velocity: Int(d[1]),
                                      isNoteOn: isOn,
                                      channel: Int(status & 0x0F),
                                      hostTimeNs: timeNs,
                                      sourceUniqueID: currentSourceUniqueID()))
            dataIndex = k
        } else {
            dataIndex += 1
        }
    }

    /// 当前来源设备 ID：当一个端口连了多个源时，CoreMIDI 的回调不带来源信息，
    /// M1 采取"若只连了一个源则用它，否则标记 0"的策略（多源精确标注留 M4）。
    private func currentSourceUniqueID() -> Int32 {
        if connectedSources.count == 1, let only = connectedSources.first {
            return sourceIDs[only] ?? 0
        }
        return 0
    }
}

private extension MIDIEndpointRef {
    /// MIDIEndpointRef == 0 表示无效端点
    var nonZero: MIDIEndpointRef? { self == 0 ? nil : self }
}
