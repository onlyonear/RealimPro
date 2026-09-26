import Foundation

// MARK: - 伴奏基础数据结构 (独立模块，不依赖现有代码)

/// 伴奏轨道的统称包
struct BackingTrackData {
    var bassNotes: [CompanionNote] = []
    var pianoNotes: [CompanionNote] = []
    var drumNotes: [CompanionNote] = []
}

/// 伴奏专用音符 (为了与你现有的 EnrichedNote 解耦，我们专门为伴奏建一个极简结构)
struct CompanionNote {
    let startSlot: Int       // 绝对起始 slot (相对伴奏开始)
    let midiPitch: UInt8
    let durationSlots: Int
    let volume: UInt8
    let channel: UInt8      // MIDI 通道：0为钢琴/旋律，1为钢琴伴奏，2为贝斯，9为鼓
}

/// 伴奏用「和弦段」：一个和弦在全曲时间线上持续的区间。
/// 一小节只有一个和弦时 = 一段(整小节)；一小节有 2~3 个和弦时 = 2~3 段(各占其拍数)。
/// 钢琴/贝斯按段生成，从而能在小节内换和弦的拍位正确跟上（对齐原版 per-currentChord 时间线）。
struct ChordSegment {
    let chord: String
    let startSlot: Int       // 相对伴奏起点的绝对 slot
    let durationSlots: Int
}

// MARK: - 伴奏规则枚举 (为日后解析 .sty 预留)

enum BassNoteType: String, Equatable {
    case bass     = "B"    // 和弦根音
    case third    = "3"    // 三度音
    case fifth    = "5"    // 五度音
    case seventh  = "7"    // 七度音
    case pitch    = "X"    // 特定音 / 经过音
    case approach = "A"    // 趋近音
    case rest     = "R"    // 休止符
    case repeatPrev = "="  // 重复前一音
}

enum DrumActionType {
    case strike // 敲击
    case rest   // 休止
}

struct DrumElement {
    var action: DrumActionType
    var durationSlots: Int
    var volume: UInt8
}
