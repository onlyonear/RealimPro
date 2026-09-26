import Foundation

// MARK: - PatternElement 基础骨架
// 对应原版 BassPatternElement/ChordPatternElement/DrumRule 的公共基类。
// 表示 Pattern 中的一个可演奏元素（音符或休止）。
// 每个 Pattern 由多个 PatternElement 组成，按时序排列。

struct PatternElement {
    /// 元素开始的拍内偏移 (slots, 相对 Pattern 起始)
    var onsetSlots: Int = 0
    
    /// 元素的持续时长 (slots)
    var durationSlots: Int = 60  // 默认八分音符 = 60slots (半拍)
    
    /// MIDI 力度 (0-127)
    var velocity: UInt8 = 80
    
    /// 是否休止 (rest)
    var isRest: Bool = false
}
