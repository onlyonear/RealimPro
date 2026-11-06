import Foundation

// MARK: - Trading / Input / 事件模型
//
// M1（输入 + 时钟 + 录音）· 纯新增文件 · 不依赖任何现有类型
// 对应 Java: javax.sound.midi.MidiMessage + timeStamp
//           src/imp/midi/MidiRecorder.java:164-208（send） / :210-258（handleNoteOn）

/// 一个实时 MIDI 音符事件。
///
/// `hostTimeNs` 取自 **CoreMIDI 包时间戳**（主机时钟，mach absolute 换算成 ns），
/// 而不是"收到的那一刻" —— 这是复刻 Java 版 `MidiRecorder.getTick()` 用
/// `sequencer.getTickPosition()` 而非 `System.nanoTime()` 的关键点（见可行性报告 §4.2）。
struct TradingMIDIEvent {

    /// MIDI 音高 0...127
    let pitch: Int

    /// 力度 0...127（**0 视为 note-off**，兼容 running status）
    let velocity: Int

    /// true = note-on（且 velocity > 0）
    let isNoteOn: Bool

    /// MIDI 通道 0...15
    let channel: Int

    /// 事件发生的**主机时间**（纳秒，由 mach absolute time 换算）
    let hostTimeNs: UInt64

    /// 来源设备唯一 ID（`kMIDIPropertyUniqueID`），用于多设备区分/调试
    let sourceUniqueID: Int32

    var isNoteOff: Bool { !isNoteOn }

    /// 便于日志阅读
    var debugDescription: String {
        let kind = isNoteOn ? "ON " : "OFF"
        return "\(kind) p=\(pitch) v=\(velocity) ch=\(channel) t=\(hostTimeNs) src=\(sourceUniqueID)"
    }
}

// MARK: - 主机时间换算

/// mach absolute time → 纳秒。
///
/// CoreMIDI 的 `MIDIPacket.timeStamp` 单位是 mach absolute time（与 `mach_absolute_time()` 同源），
/// 在 Apple Silicon 上 timebase 为 125/3（即 1 tick = 24/3 ns ≈ 41.67 ns，**换算不可省**）。
enum TradingHostClock {

    /// 缓存的 timebase（进程内不变）
    private static let timebase: mach_timebase_info_data_t = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return tb
    }()

    /// mach absolute ticks → 纳秒
    static func toNanos(_ ticks: UInt64) -> UInt64 {
        let tb = timebase
        if tb.denom == 0 { return ticks }
        return ticks &* UInt64(tb.numer) / UInt64(tb.denom)
    }

    /// 当前主机时间（纳秒）
    static func nowNanos() -> UInt64 {
        toNanos(mach_absolute_time())
    }

    /// CoreMIDI 时间戳规范化：0 表示"立即"，此时用当前主机时间代替。
    static func normalized(_ timestamp: UInt64) -> UInt64 {
        timestamp == 0 ? nowNanos() : toNanos(timestamp)
    }
}
