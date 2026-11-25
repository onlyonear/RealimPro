import Foundation

// MARK: - 抽象（发声出口 + 输入源），用于解耦与互斥自动化测试

/// 发声出口：把引擎与具体音频采样器解耦。生产由 JazzMonitorSounder 适配 JazzMidiPlayer，
/// 测试注入记录型 fake，以断言闸门是否放行。
protocol MIDIMonitorSounding: AnyObject {
    func noteOn(pitch: UInt8, velocity: UInt8, channel: UInt8)
    func noteOff(pitch: UInt8, channel: UInt8)
    func allNotesOff()
    func ensureReady()
}

/// 输入源抽象：生产用 CoreMIDI 的 TradingMIDIInput，测试用 fake 手动驱动事件。
protocol MIDIPassthroughInput: AnyObject {
    var onEvent: ((TradingMIDIEvent) -> Void)? { get set }
    var onDevicesChanged: (([TradingMIDIDevice]) -> Void)? { get set }
    @discardableResult
    func start() -> Bool
    func stop()
    func disconnectAllSources()
    @discardableResult
    func connect(_ device: TradingMIDIDevice) -> Bool
    func availableDevices() -> [TradingMIDIDevice]
}

// MARK: - Trading / Input / MIDI 键盘直通发声引擎
//
// 核心类：不依赖 JazzMidiPlayer / CoreMIDI 具体实现（具体依赖经协议注入，见生产装配文件
// MIDIPassthroughWiring.swift），因此可在 macOS 本地用 fake 直接做互斥专项测试。
//
// 职责：在非 Trading 会话态，把 MIDI 键盘的音符事件直接转发给发声出口发声。
// 本类不引用 TradingRecorder / TradingDisplay / TradingSession，故五线谱零渲染；
// 调音台 switchSoloInstrument 会自动同步 monitor 音色。
//
// 互斥：与正式 Trading 会话严格互斥。进会话前在主线程同步 suspend()，会话结束 resume()。
// 发声闸门（suspended / hasOnlineDevice）用 NSLock 保护：onEvent 在 CoreMIDI 回调线程
// 读、suspend/resume 在主线程写，消除跨线程 data race，杜绝会话开始瞬间的叠音/双响。
final class MIDIPassthroughEngine {

    // MARK: 内部持有

    private let input: MIDIPassthroughInput
    private let sounder: MIDIMonitorSounding
    private let stateLock = NSLock()

    /// 会话占用闸门（true = 正式 Trading 会话进行中，直通静音）
    private var suspended = false
    /// 当前是否存在在线（非 offline）输入源
    private var hasOnlineDevice = false

    /// 依赖注入入口（生产装配与测试均通过它构造；不自动 start，由调用方决定）。
    init(input: MIDIPassthroughInput, sounder: MIDIMonitorSounding) {
        self.input = input
        self.sounder = sounder
        input.onEvent = { [weak self] event in self?.handleLiveEvent(event) }
        input.onDevicesChanged = { [weak self] devices in self?.handleDevicesChanged(devices) }
    }

    // MARK: 互斥 API（主线程）

    /// 进正式 Trading 会话前调用：先关闸门，再收掉所有延音。
    func suspend() {
        runOnMain {
            self.stateLock.lock()
            self.suspended = true
            self.stateLock.unlock()
            // 先置闸门再收挂音，避免切换边界残留延音
            self.sounder.allNotesOff()
        }
    }

    /// 会话结束后调用：恢复闸门，设备仍在则确保采样器就绪。
    func resume() {
        runOnMain {
            self.stateLock.lock()
            self.suspended = false
            let online = self.hasOnlineDevice
            self.stateLock.unlock()
            if online {
                self.sounder.ensureReady()
            }
        }
    }

    /// 生产装配在 input.start() 后调用：start 时设备已在线不会触发 setup-changed，手动刷一次。
    func refreshInitialDevices() {
        handleDevicesChanged(input.availableDevices())
    }

    // MARK: 实时事件（CoreMIDI 回调线程）

    private func handleLiveEvent(_ event: TradingMIDIEvent) {
        stateLock.lock()
        let allowed = hasOnlineDevice && !suspended
        stateLock.unlock()
        guard allowed else { return }

        let pitch = UInt8(max(0, min(127, event.pitch)))
        let channel = UInt8(event.channel & 0x0F)
        if event.isNoteOn {
            let velocity = UInt8(max(1, min(127, event.velocity)))
            sounder.noteOn(pitch: pitch, velocity: velocity, channel: channel)
        } else {
            sounder.noteOff(pitch: pitch, channel: channel)
        }
    }

    // MARK: 设备变化（主线程）

    private func handleDevicesChanged(_ devices: [TradingMIDIDevice]) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.handleDevicesChanged(devices)
            }
            return
        }

        // 多端口去重：notifyBlock 已自动连全量源，这里只保留第一个在线源（主端口），
        // 其余断开，避免 Yamaha MX 类多端口键盘一次按键重复发声。
        input.disconnectAllSources()
        let onlineDevices = devices.filter { !$0.isOffline }
        if let primary = onlineDevices.first {
            input.connect(primary)
        }

        stateLock.lock()
        hasOnlineDevice = !onlineDevices.isEmpty
        let isSuspended = suspended
        stateLock.unlock()

        if !onlineDevices.isEmpty {
            // 音频图结构变更在主线程；ensureReady 幂等。会话进行中由会话路径保证挂载，此处不重复。
            if !isSuspended {
                sounder.ensureReady()
            }
        } else {
            // 设备全部移除：收掉挂音（节点常驻不 detach）
            sounder.allNotesOff()
        }
    }

    // MARK: 工具

    private func runOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}
