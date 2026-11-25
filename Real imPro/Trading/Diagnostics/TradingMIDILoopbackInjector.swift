#if DEBUG
import Foundation
import CoreMIDI

// MARK: - Trading / Diagnostics / 虚拟 MIDI 键盘（仅 DEBUG 回环测试）
//
// M2-2 · 纯新增 · 整文件 #if DEBUG（Release 不编译）。
//
// 独立的第二个 MIDIClient（与生产 TradingMIDIInput 不是同一个 client）：
//   · MIDISourceCreateWithProtocol(MIDI 1.0) 建虚拟源，出现在系统 MIDIGetSources()，等价插了一个 USB 键盘；
//   · 用「实时线程 + mach_wait_until + MIDIReceived(timeStamp=0)」按真实演奏节奏逐事件投递；
//     timeStamp=0 → 生产 TradingMIDIInput.normalized 会在收到当下打时间戳（与真实键盘一致）。
//
// 为什么不用"未来时间戳一次性回灌"：macOS 实测 CoreMIDI 会对未来事件按时间戳调度（未文档化、iOS 未验证），
// 而真实键盘从不会发未来时间戳。方式 B 最贴近真实链路，且实时线程实测误差 0.05–0.11ms（≈0.026 slot）。
// 实测依据见 audit_harness/trading_audit_20261017/evidence_M2-2/spike_*.swift。
final class TradingMIDILoopbackInjector {

    /// 虚拟源显示名（harness 在 availableDevices() 按 contains 匹配；系统可能加后缀）
    static let virtualName = "RealimPro Loopback"

    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private(set) var isUp = false

    // 发送 buffer 统一保留到整段结束（CoreMIDI 可能延迟引用；不依赖它是否立即内部拷贝）
    private var retained: [UnsafeMutableRawPointer] = []
    private let retainedLock = NSLock()

    private let timebase: mach_timebase_info_data_t = {
        var tb = mach_timebase_info_data_t()
        _ = mach_timebase_info(&tb)
        return tb
    }()

    /// 一条待演奏的 MIDI 消息：原始字节（可含 running status 多字节）+ 相对 anchor 的 slot（已含 swing/jitter）
    struct ScheduledEvent {
        let bytes: [UInt8]
        let atSlot: Int
    }

    // MARK: 建连

    /// 建立独立 client 与虚拟源，并等其出现在系统源列表（DeepSeek 要求②：先建源）。
    @discardableResult
    func start() -> Bool {
        guard !isUp else { return true }
        let cs = MIDIClientCreateWithBlock("RealimPro Loopback Sender" as CFString, &client) { _ in }
        guard cs == noErr else {
            print("❌ MIDIClientCreateWithBlock 失败 status=\(cs)"); return false
        }
        let proto = MIDIProtocolID(rawValue: 1)!   // kMIDIProtocol_1_0，与生产输入端口一致
        let ss = MIDISourceCreateWithProtocol(client, Self.virtualName as CFString, proto, &source)
        guard ss == noErr else {
            print("❌ MIDISourceCreateWithProtocol 失败 status=\(ss)（iOS 常见于 App 未在前台/缺少音频后台能力）")
            MIDIClientDispose(client); client = 0
            return false
        }
        print("  虚拟源已创建（status=0），等待出现在 MIDIGetSources…")
        let deadline = Date().addingTimeInterval(2.0)
        var lastCount: Int = -1
        while Date() < deadline {
            let n = MIDIGetNumberOfSources()
            if n != lastCount {
                var names: [String] = []
                for i in 0..<n {
                    var um: Unmanaged<CFString>?
                    if MIDIObjectGetStringProperty(MIDIGetSource(i), kMIDIPropertyName, &um) == noErr,
                       let nm = um?.takeRetainedValue() as String? { names.append(nm) }
                }
                print("  MIDIGetSources count=\(n)：\(names)")
                lastCount = n
            }
            if globalEndpoint() != 0 { isUp = true; print("  ✅ 虚拟源已在系统源列表可见"); return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        print("❌ 2 秒内虚拟源未出现在 MIDIGetSources（最终 count=\(MIDIGetNumberOfSources())）")
        return false
    }

    private func globalEndpoint() -> MIDIEndpointRef {
        for i in 0..<MIDIGetNumberOfSources() {
            let s = MIDIGetSource(i)
            var um: Unmanaged<CFString>?
            if MIDIObjectGetStringProperty(s, kMIDIPropertyName, &um) == noErr,
               let n = um?.takeRetainedValue() as String?,
               n.contains(Self.virtualName) { return s }
        }
        return 0
    }

    // MARK: 实时演奏（方式 B）

    /// 必须在注入器专用后台线程内调用：把当前线程设为实时优先级，然后按 anchor 绝对时间逐事件投递。
    /// - Parameters:
    ///   - events: 已排好序（atSlot 可乱序，内部会排序）的 MIDI 消息
    ///   - bpm: 速度（与 TradingClock 同口径：每拍 120 slot）
    ///   - anchorTicks: 整段 slot 0 对应的 mach absolute ticks（由调用方取 now + lead）
    func performRealtime(events: [ScheduledEvent], bpm: Double, anchorTicks: UInt64) {
        setCurrentThreadRealtime()
        // nsPerSlot 返回纳秒（TradingClock.swift:92-93），直接换算，切勿再乘 1e9（v2.1 勘误）
        let ticksPerSlot = nsToTicks(UInt64(TradingClock.nsPerSlot(bpm: bpm)))
        let ordered = events.sorted { $0.atSlot < $1.atSlot }
        for ev in ordered {
            let target = anchorTicks &+ (UInt64(ev.atSlot) &* ticksPerSlot)
            mach_wait_until(target)                 // 绝对时间锚定：误差不累积（实测 0.05–0.11ms）
            emit(ev.bytes, timeStamp: 0)
        }
    }

    /// 【路径 A · 仅观测，非验收门】立即一次性投递：每个事件单独一次 MIDIReceived、带真实未来时间戳。
    /// 不等待、不设实时线程。macOS 实测 CoreMIDI 会按点调度并保留时间戳；iOS 行为由 loopgoA 钉。
    /// 注意：多个不同时间戳必须「每事件一次 MIDIReceived」，塞进同一 packetList 会被当立即投递并抹掉时间戳。
    func performScheduled(events: [ScheduledEvent], bpm: Double, anchorTicks: UInt64) {
        let ticksPerSlot = nsToTicks(UInt64(TradingClock.nsPerSlot(bpm: bpm)))
        for ev in events.sorted(by: { $0.atSlot < $1.atSlot }) {
            let ts = anchorTicks &+ (UInt64(ev.atSlot) &* ticksPerSlot)
            emit(ev.bytes, timeStamp: ts)
        }
    }

    /// 投递一条消息；timeStamp=0 表示由生产端 normalized 在收到当下打时间戳（方式 B），非 0 用于路径 A 观测。
    /// 单 packetList 内逐字节写入；bytes 可含 running status 下同一时刻的多条消息（解析器逐字节处理）。
    private func emit(_ bytes: [UInt8], timeStamp: UInt64) {
        guard isUp, source != 0, !bytes.isEmpty else { return }
        let capacity = 64
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: capacity, alignment: MemoryLayout<MIDIPacketList>.alignment)
        let pl = raw.bindMemory(to: MIDIPacketList.self, capacity: 1)
        var cur = MIDIPacketListInit(pl)
        bytes.withUnsafeBufferPointer { buf in
            cur = MIDIPacketListAdd(pl, capacity, cur, timeStamp, bytes.count, buf.baseAddress!)
        }
        MIDIReceived(source, pl)
        retainedLock.lock(); retained.append(raw); retainedLock.unlock()
    }

    /// 毫秒 → mach ticks（统一入口：先 ms→ns 再乘 denom/numer，避免整数先除截断；v2.1 勘误）
    func machTicks(fromMs ms: UInt64) -> UInt64 {
        nsToTicks(ms &* 1_000_000)
    }

    /// 纳秒 → mach ticks（注入点已拿到 ns 锚点，直接用这个，避免 ms 截断）
    func machTicks(fromNs ns: UInt64) -> UInt64 {
        nsToTicks(ns)
    }

    func stop() {
        if client != 0 { MIDIClientDispose(client); client = 0 }
        source = 0
        isUp = false
        // 线程已退出、CoreMIDI 不再引用后再释放
        retainedLock.lock()
        for r in retained { r.deallocate() }
        retained.removeAll()
        retainedLock.unlock()
    }

    // MARK: 实时优先级 + 时间换算

    /// 给当前线程设置 TIME_CONSTRAINT（实时优先级），把 mach_wait_until 唤醒抖动压到亚毫秒。
    /// 等价 <sched_policy.h> struct time_constraint_policy { uint32 period, computation, constraint, preemptible }。
    private func setCurrentThreadRealtime() {
        struct TCP { var period: UInt32; var computation: UInt32; var constraint: UInt32; var preemptible: UInt32 }
        let period: UInt32 = 1_000_000   // 1ms
        var tc = TCP(period: period, computation: period, constraint: period, preemptible: 1)
        let count = mach_msg_type_number_t(MemoryLayout<TCP>.size / MemoryLayout<integer_t>.size)
        withUnsafeMutablePointer(to: &tc) { ump in
            ump.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ip in
                _ = thread_policy_set(mach_thread_self(), thread_policy_flavor_t(2), ip, count)
            }
        }
    }

    private func nsToTicks(_ ns: UInt64) -> UInt64 {
        ns &* UInt64(timebase.denom) / UInt64(timebase.numer)
    }
}
#endif
