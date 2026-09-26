import Foundation

// MARK: - BrickLibrary — 爵士和声模板库 
// 内置全套经典爵士和声brick: ii-V-I / 替代和弦 / 转调进行 / 长短乐句单元
// 对外提供查询接口: 按和弦家族/调式/小节长度匹配适配和声brick

struct BrickLibrary {

    // ═══════════════════════════════════════════════════════
    // 1. 和声Brick 数据模型
    // ═══════════════════════════════════════════════════════

    /// 单个和声Brick定义
    struct BrickTemplate: Equatable {
        let name: String           // 如 "ii-V-I"
        let chords: [String]       // 和弦名称序列 ["Dm7","G7","Cmaj7"]
        let category: BrickCategory
        let style: [String]        // 适用风格: ["swing","bebop","ballad"]
        let beats: Double          // 总拍数 (用于匹配小节长度)
        let substitutions: [String] // 可替换等价Brick名称

        enum BrickCategory: String, CaseIterable {
            case cadence         // 终止式 (ii-V-I, V-I)
            case turnaround      // 回转 (I-vi-ii-V)
            case passing         // 经过和弦序列
            case substitution    // 替代和弦
            case modal           // 调式互换
            case blues           // 布鲁斯进行
            case extended        // 长乐句单元 (>4小节)
        }
    }

    // ═══════════════════════════════════════════════════════
    // 2. 内置标准爵士和声模板库
    // ═══════════════════════════════════════════════════════

    static let standardBricks: [BrickTemplate] = [

        // ── 终止式 (Cadence) ──

        BrickTemplate(name: "ii-V-I maj",
                      chords: ["Dm7", "G7", "Cmaj7"],
                      category: .cadence, style: ["swing","bebop","ballad","bossa"],
                      beats: 12.0, substitutions: ["ii-V-I alt"]),

        BrickTemplate(name: "ii-V-I min",
                      chords: ["Dm7b5", "G7b9", "Cm7"],
                      category: .cadence, style: ["swing","bebop","ballad"],
                      beats: 12.0, substitutions: ["minor-ii-V-i alt"]),

        BrickTemplate(name: "V-I authentic",
                      chords: ["G7", "Cmaj7"],
                      category: .cadence, style: ["swing","ballad"],
                      beats: 8.0, substitutions: ["V-I alt"]),

        BrickTemplate(name: "ii-V half",
                      chords: ["Dm7", "G7"],
                      category: .cadence, style: ["bebop","swing"],
                      beats: 8.0, substitutions: []),

        // ── 回转 (Turnaround) ──

        BrickTemplate(name: "I-vi-ii-V",
                      chords: ["Cmaj7", "Am7", "Dm7", "G7"],
                      category: .turnaround, style: ["swing","bebop","ballad"],
                      beats: 16.0, substitutions: ["I-vi-ii-V alt","I-VI7-ii-V"]),

        BrickTemplate(name: "iii-vi-ii-V",
                      chords: ["Em7", "Am7", "Dm7", "G7"],
                      category: .turnaround, style: ["bebop","swing"],
                      beats: 16.0, substitutions: []),

        // ── 替代和弦 (Substitution) ──

        BrickTemplate(name: "tritone-sub ii-V",
                      chords: ["Dm7", "Db7", "Cmaj7"],
                      category: .substitution, style: ["bebop","hardbop"],
                      beats: 12.0, substitutions: ["b5 sub"]),

        BrickTemplate(name: "backdoor ii-V",
                      chords: ["Fm7", "Bb7", "Cmaj7"],
                      category: .substitution, style: ["cool","modal"],
                      beats: 12.0, substitutions: []),

        BrickTemplate(name: "chromatic-ii-V",
                      chords: ["Dm7", "G7", "Dbm7", "Gb7", "Cmaj7"],
                      category: .substitution, style: ["bebop"],
                      beats: 20.0, substitutions: []),

        // ── 调式互换 (Modal Interchange) ──

        BrickTemplate(name: "modal-mixture bVI-bVII-I",
                      chords: ["Abmaj7", "Bbmaj7", "Cmaj7"],
                      category: .modal, style: ["modal","cool"],
                      beats: 12.0, substitutions: []),

        BrickTemplate(name: "iv-bVII-I",
                      chords: ["Fm7", "Bb7", "Cmaj7"],
                      category: .modal, style: ["modal"],
                      beats: 12.0, substitutions: []),

        // ── 布鲁斯 (Blues) ──

        BrickTemplate(name: "blues-12bar maj",
                      chords: ["C7","F7","C7","C7","F7","F7","C7","C7","G7","F7","C7","G7"],
                      category: .blues, style: ["blues","swing"],
                      beats: 48.0, substitutions: ["jazz-blues"]),

        BrickTemplate(name: "jazz-blues",
                      chords: ["C7","F7","C7","Gm7","F7","F#dim7","C7","A7","Dm7","G7","C7","G7"],
                      category: .blues, style: ["bebop","swing"],
                      beats: 48.0, substitutions: []),

        // ── 长乐句单元 ──

        BrickTemplate(name: "rhythm-changes-A",
                      chords: ["Cmaj7","Am7","Dm7","G7","Em7","A7","Dm7","G7"],
                      category: .extended, style: ["bebop","swing"],
                      beats: 32.0, substitutions: []),

        BrickTemplate(name: "coltrane-changes",
                      chords: ["Cmaj7","Ebmaj7","Abmaj7","Bmaj7"],
                      category: .extended, style: ["modal","hardbop"],
                      beats: 16.0, substitutions: []),
    // ── 自动生成: My.dictionary 展开的 BrickTemplate (CharlieParker) ──

        BrickTemplate(name: "Sad-Cadence",
                      chords: ["Dm7b5", "G7", "Cm"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 1.0,
                      substitutions: []),

        BrickTemplate(name: "Straight-Cadence",
                      chords: ["Dm7", "G7", "C"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 1.0,
                      substitutions: []),

        BrickTemplate(name: "Dizzy-Cadence",
                      chords: ["Dm7", "Db7", "C"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 1.0,
                      substitutions: []),

        BrickTemplate(name: "Long-Cadence",
                      chords: ["Em7", "Am7", "Dm7", "G7", "C"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 3.0,
                      substitutions: []),

        BrickTemplate(name: "Tension-Cadence",
                      chords: ["A#m7", "D#7", "G#7"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 1.0,
                      substitutions: []),

        BrickTemplate(name: "Surprise-Major-Cadence",
                      chords: ["Dm7b5", "G7", "C"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 3.0,
                      substitutions: []),

        BrickTemplate(name: "Body-&-Soul-Cadence",
                      chords: ["Dm7", "F7", "Dm7", "G7", "C"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 3.0,
                      substitutions: []),

        BrickTemplate(name: "Starlight-Cadence",
                      chords: ["Dm7", "D#7", "Dm7", "F7", "Dm7", "G7", "C"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 8.0,
                      substitutions: []),

        BrickTemplate(name: "Supertension-Ending",
                      chords: ["Dm7", "G7", "C7#4"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 4.0,
                      substitutions: []),

        BrickTemplate(name: "Suprise-Major-Tension-Cadence",
                      chords: ["Fm7b5", "A#7", "F#7"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 1.0,
                      substitutions: []),

        BrickTemplate(name: "Dominant-Cycle-Cadence",
                      chords: ["D7", "G7", "C"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 3.0,
                      substitutions: []),

        BrickTemplate(name: "Two-Goes-Straight-Cadence",
                      chords: ["Dm7", "G7", "Dm7", "G7", "C"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 3.0,
                      substitutions: []),

        BrickTemplate(name: "Straight-Approach",
                      chords: ["Dm7", "G7"],
                      category: .passing,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0,
                      substitutions: []),

        BrickTemplate(name: "Dizzy-Approach",
                      chords: ["Dm7", "Db7"],
                      category: .passing,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0,
                      substitutions: []),

        BrickTemplate(name: "Straight-Launcher",
                      chords: ["Dm7", "G7"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0,
                      substitutions: []),

        BrickTemplate(name: "Dropback",
                      chords: ["C", "Cm7", "F7"],
                      category: .passing,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 4.0,
                      substitutions: []),

        BrickTemplate(name: "Minor-Chromatic-Walkdown",
                      chords: ["Dm7", "Dbm7"],
                      category: .passing,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0,
                      substitutions: []),

        BrickTemplate(name: "Happenstance-Turnaround",
                      chords: ["C", "Dm7", "D#7"],
                      category: .turnaround,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 1.0,
                      substitutions: []),

        BrickTemplate(name: "POT",
                      chords: ["C", "Gm7", "Dm7", "G7"],
                      category: .turnaround,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 4.0,
                      substitutions: []),

        BrickTemplate(name: "SPOT",
                      chords: ["Cm7", "F7", "Dm7", "G7"],
                      category: .turnaround,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 4.0,
                      substitutions: []),

        BrickTemplate(name: "Dominant-Cycle",
                      chords: ["D7", "G7"],
                      category: .passing,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0,
                      substitutions: []),

        BrickTemplate(name: "Giant-Steps",
                      chords: ["C#", "C7", "F", "E7", "A"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 1.0,
                      substitutions: []),

        BrickTemplate(name: "Donna-Lee-Opening",
                      chords: ["C", "Gm7", "C7", "Dm7", "G7", "C"],
                      category: .extended,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 5.0,
                      substitutions: []),

        BrickTemplate(name: "Rhythm-Bridge",
                      chords: ["A#7", "F7", "C7", "G7"],
                      category: .passing,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 4.0,
                      substitutions: []),

        BrickTemplate(name: "To-IV-n-Yak",
                      chords: ["C", "D7", "G", "E7", "C"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 5.0,
                      substitutions: []),

        BrickTemplate(name: "IV-n-Back",
                      chords: ["G", "F#o", "C"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 3.0,
                      substitutions: []),

        BrickTemplate(name: "IV-n-Bird-SPOT",
                      chords: ["G", "E7", "Cm7", "F7", "Dm7", "G7"],
                      category: .turnaround,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 6.0,
                      substitutions: []),

        BrickTemplate(name: "II-n-Bird-POT",
                      chords: ["Dm7", "E7", "C", "Gm7", "Dm7", "G7"],
                      category: .turnaround,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 7.0,
                      substitutions: []),

        BrickTemplate(name: "Yardbird-Cadence",
                      chords: ["Dm7", "G7", "C"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 1.0,
                      substitutions: []),

        BrickTemplate(name: "Yardbird-Approach",
                      chords: ["Fm7", "Bb7"],
                      category: .passing,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0,
                      substitutions: []),

        BrickTemplate(name: "Major-On",
                      chords: ["C"],
                      category: .passing,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 1.0,
                      substitutions: []),

        BrickTemplate(name: "Minor-On",
                      chords: ["Cm"],
                      category: .passing,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 1.0,
                      substitutions: []),

        BrickTemplate(name: "Surge",
                      chords: ["C", "C#o"],
                      category: .extended,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0,
                      substitutions: []),

        BrickTemplate(name: "On-Off-On-Minor-V",
                      chords: ["Cm", "G7", "Cm"],
                      category: .modal,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 1.0,
                      substitutions: []),

        BrickTemplate(name: "On-Off-On-To-V",
                      chords: ["C", "G7", "C"],
                      category: .modal,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 1.0,
                      substitutions: []),

        // ── 阶段B1: 和弦变体砖 (独特和声序列, 提高CYK命中率) ──

        BrickTemplate(name: "Dizzy-Cadence-with-bIII7",
                      chords: ["Eb7", "Dm7", "Db7", "C"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0,
                      substitutions: []),

        BrickTemplate(name: "Dizzy-Cadence-with-bVIm",
                      chords: ["Abm7", "Dm7", "Db7", "C"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0,
                      substitutions: []),

        BrickTemplate(name: "Extended-Cadence-with-Tritone-Sub",
                      chords: ["D#m", "Dm7", "Db7", "C"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0,
                      substitutions: []),

        BrickTemplate(name: "Dropback(tritone)",
                      chords: ["C", "Bb7", "A7"],
                      category: .passing,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 1.0,
                      substitutions: []),

        BrickTemplate(name: "Cadence+TTFA-Dropback",
                      chords: ["G#m7", "C#7", "F#M7", "B7", "A#m7", "D#7"],
                      category: .turnaround,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 8.0,
                      substitutions: []),

        BrickTemplate(name: "Dizzy-Sub-Turnaround",
                      chords: ["A", "C7", "Bm7", "A#7"],
                      category: .turnaround,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 4.0,
                      substitutions: []),

        BrickTemplate(name: "Chromatic-Major-Walkup",
                      chords: ["D", "C", "B7"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 3.0,
                      substitutions: []),

        BrickTemplate(name: "Diatonic-ii-iii-IV-V",
                      chords: ["Dm7", "Em7", "F", "G7"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 4.0,
                      substitutions: []),

        // ── 阶段B2: 高频砖 (CharlieParker语法引用) ──

        BrickTemplate(name: "Amen-Cadence",
                      chords: ["G", "C"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0,
                      substitutions: []),

        BrickTemplate(name: "Autumnal-Cadence",
                      chords: ["Dm7", "G7", "Dm7", "A#7", "Cm"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 5.0,
                      substitutions: []),

        BrickTemplate(name: "Chromatic-Approach",
                      chords: ["A7", "Ab7", "G7"],
                      category: .passing,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 3.0,
                      substitutions: []),

        BrickTemplate(name: "Dogleg-Cadence",
                      chords: ["D7", "Dm7", "G7", "C"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 3.0,
                      substitutions: []),

        BrickTemplate(name: "Dogleg-Approach",
                      chords: ["D7", "Dm7", "G7"],
                      category: .passing,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 4.0,
                      substitutions: []),

        BrickTemplate(name: "Dominant-Cycle-2-Steps",
                      chords: ["D7", "G7"],
                      category: .passing,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0,
                      substitutions: []),

        BrickTemplate(name: "Happenstance-Cadence",
                      chords: ["Dm7", "D#7", "C"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 1.0,
                      substitutions: []),

        BrickTemplate(name: "II-n-Back",
                      chords: ["Dm7", "D#o", "C/E"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 1.0,
                      substitutions: []),

        BrickTemplate(name: "Minor-Dropback",
                      chords: ["Cm", "Am7b5"],
                      category: .passing,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0,
                      substitutions: []),

        BrickTemplate(name: "Minor-Perfect-Cadence",
                      chords: ["G7", "Cm7"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0,
                      substitutions: []),

        BrickTemplate(name: "Minor-POT",
                      chords: ["Cm", "Am7b5", "Dm7b5", "G7"],
                      category: .turnaround,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 4.0,
                      substitutions: []),

        BrickTemplate(name: "Rainy-Cadence",
                      chords: ["Em", "Ebdim", "Dm7", "G7", "C"],
                      category: .cadence,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 5.0,
                      substitutions: []),

        BrickTemplate(name: "Starlight-Approach",
                      chords: ["Dm7", "D#7", "Dm7", "F7", "Dm7", "G7"],
                      category: .passing,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 6.0,
                      substitutions: []),

        // ── 阶段B3: 中频砖 (On-Off/CESH/Approach) ──

        BrickTemplate(name: "7sus4-to-3",
                      chords: ["C#7sus4","C#7"],
                      category: .passing, style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0, substitutions: []),
        BrickTemplate(name: "Ascending-Descending-Minor-CESH",
                      chords: ["Cm","Cm+","Cm6","Cm+"],
                      category: .modal, style: ["swing","bebop","ballad","bossa"],
                      beats: 4.0, substitutions: []),
        BrickTemplate(name: "Ascending-Minor-CESH",
                      chords: ["Cm","Cm+","Cm6"],
                      category: .modal, style: ["swing","bebop","ballad","bossa"],
                      beats: 3.0, substitutions: []),
        BrickTemplate(name: "Autumn-Leaves-Opening",
                      chords: ["Dm7","G7","C","Dm7b5","G7","D#m"],
                      category: .extended, style: ["swing","bebop","ballad","bossa"],
                      beats: 5.0, substitutions: []),
        BrickTemplate(name: "Descending-Minor-CESH",
                      chords: ["Cm","CmM7","Cm7"],
                      category: .modal, style: ["swing","bebop","ballad","bossa"],
                      beats: 3.0, substitutions: []),
        BrickTemplate(name: "Diatonic-I-ii-iii",
                      chords: ["F","D#m","C#m"],
                      category: .passing, style: ["swing","bebop","ballad","bossa"],
                      beats: 3.0, substitutions: []),
        BrickTemplate(name: "Diatonic-I-ii-iii-ii",
                      chords: ["C","Dm7","Em7","Dm7"],
                      category: .passing, style: ["swing","bebop","ballad","bossa"],
                      beats: 4.0, substitutions: []),
        BrickTemplate(name: "Donna-Lee-Start",
                      chords: ["C","Gm7","C7"],
                      category: .passing, style: ["swing","bebop","ballad","bossa"],
                      beats: 4.0, substitutions: []),
        BrickTemplate(name: "Nowhere-Approach",
                      chords: ["Ab7","G7"],
                      category: .passing, style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0, substitutions: []),
        BrickTemplate(name: "Nowhere-Minor-Cadence",
                      chords: ["Ab7","G7","Cm"],
                      category: .cadence, style: ["swing","bebop","ballad","bossa"],
                      beats: 1.0, substitutions: []),
        BrickTemplate(name: "Nowhere-Turnaround+On",
                      chords: ["C","Cm7","F7","Ab7","G7","C"],
                      category: .cadence, style: ["swing","bebop","ballad","bossa"],
                      beats: 5.0, substitutions: []),
        BrickTemplate(name: "Off-On-Minor-IV",
                      chords: ["G7","Cm"],
                      category: .modal, style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0, substitutions: []),
        BrickTemplate(name: "Off-On-Minor-Somewhere",
                      chords: ["A#7","Cm"],
                      category: .modal, style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0, substitutions: []),
        BrickTemplate(name: "Off-On-Minor-#IV",
                      chords: ["F#7","Cm"],
                      category: .modal, style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0, substitutions: []),
        BrickTemplate(name: "On+Dropback",
                      chords: ["A","C7"],
                      category: .passing, style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0, substitutions: []),
        BrickTemplate(name: "On-Off-Major-#IV",
                      chords: ["C","F#7"],
                      category: .modal, style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0, substitutions: []),
        BrickTemplate(name: "On-Off-Major-III",
                      chords: ["C","G#7"],
                      category: .modal, style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0, substitutions: []),
        BrickTemplate(name: "On-Off-Major-V",
                      chords: ["C","G7"],
                      category: .modal, style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0, substitutions: []),
        BrickTemplate(name: "On-Off-Major-VI",
                      chords: ["C","D#7"],
                      category: .modal, style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0, substitutions: []),
        BrickTemplate(name: "On-Off-Major-VII",
                      chords: ["C","C#7"],
                      category: .modal, style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0, substitutions: []),
        BrickTemplate(name: "On-Off-Major-bIII",
                      chords: ["C","A7"],
                      category: .modal, style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0, substitutions: []),
        BrickTemplate(name: "On-Off-Major-bVII",
                      chords: ["C","D7"],
                      category: .modal, style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0, substitutions: []),
        BrickTemplate(name: "On-Off-Minor-III",
                      chords: ["Cm","G#7"],
                      category: .modal, style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0, substitutions: []),
        BrickTemplate(name: "On-Off-Minor-Somewhere",
                      chords: ["Cm","A#7"],
                      category: .modal, style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0, substitutions: []),
        BrickTemplate(name: "On-Off-Minor-VI",
                      chords: ["Cm","D#7"],
                      category: .modal, style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0, substitutions: []),
        BrickTemplate(name: "On-Off-Minor-bVII",
                      chords: ["Cm","D7"],
                      category: .modal, style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0, substitutions: []),
        BrickTemplate(name: "On-Off-On-Twice-Minor-V",
                      chords: ["Cm","G7","Cm","G7","Cm"],
                      category: .cadence, style: ["swing","bebop","ballad","bossa"],
                      beats: 1.0, substitutions: []),
        BrickTemplate(name: "On-Off-Thrice-Minor-V",
                      chords: ["Cm","G7","Cm","G7","Cm","G7"],
                      category: .modal, style: ["swing","bebop","ballad","bossa"],
                      beats: 0.0, substitutions: []),
        BrickTemplate(name: "On-Off-Twice-Minor-V",
                      chords: ["Cm","G7","Cm","G7"],
                      category: .modal, style: ["swing","bebop","ballad","bossa"],
                      beats: 0.0, substitutions: []),
        BrickTemplate(name: "POT+On",
                      chords: ["C","Gm7","Dm7","G7","C"],
                      category: .cadence, style: ["swing","bebop","ballad","bossa"],
                      beats: 3.0, substitutions: []),
        BrickTemplate(name: "Pullback",
                      chords: ["Dm7","G7","Dm7","F7"],
                      category: .passing, style: ["swing","bebop","ballad","bossa"],
                      beats: 4.0, substitutions: []),
        BrickTemplate(name: "Rainy-Pullback-Extended",
                      chords: ["Dm7","G7","Em7","Ebo","Dm7","G7"],
                      category: .passing, style: ["swing","bebop","ballad","bossa"],
                      beats: 6.0, substitutions: []),
        BrickTemplate(name: "Reverse-Dominant-Cycle-2-Steps",
                      chords: ["D7","A7"],
                      category: .passing, style: ["swing","bebop","ballad","bossa"],
                      beats: 2.0, substitutions: []),
        BrickTemplate(name: "Stablemates-Approach",
                      chords: ["C#m7","F#7","Dm7","G7"],
                      category: .passing, style: ["swing","bebop","ballad","bossa"],
                      beats: 4.0, substitutions: []),
        BrickTemplate(name: "TTFA-Dropback",
                      chords: ["C","G","Dm7","G7"],
                      category: .passing, style: ["swing","bebop","ballad","bossa"],
                      beats: 4.0, substitutions: []),
        BrickTemplate(name: "Tension-SPOT",
                      chords: ["F7","A#7","Gm7","C7"],
                      category: .turnaround, style: ["swing","bebop","ballad","bossa"],
                      beats: 4.0, substitutions: []),
        BrickTemplate(name: "To-IV",
                      chords: ["C","G7","C"],
                      category: .cadence, style: ["swing","bebop","ballad","bossa"],
                      beats: 1.0, substitutions: []),

        BrickTemplate(name: "Two-Goes-Approach",
                      chords: ["Dm7", "D7", "Dm7", "D7"],
                      category: .passing,
                      style: ["swing","bebop","ballad","bossa"],
                      beats: 4.0,
                      substitutions: []),


    ]
}

// MARK: - JazzRoadmap 扩展: Brick解析集成

extension JazzRoadmap {
    /// 对当前和弦序列执行CYK解析+Brick匹配 (阶段4.1: 相对音程标签)
    func parseBricks() -> (tree: TreeNode?, bricks: [(name: String, start: Double, end: Double, key: String)]) {
        let chords = flattenRoadmap()
        let labels = computeRelativeFunctionLabels(chords: chords)
        let chordNames = chords.map { $0.name }
        let parser: CYKParser
        if CYKParser.useDynamicProductions {
            let dynProds = generateProductions(from: BrickLibrary.standardBricks, pocOnly: false)
            parser = CYKParser(binaryProductions: dynProds)
        } else {
            parser = CYKParser()
        }
        let tree = parser.parseWithLabels(labels: labels, chordNames: chordNames)
        let rawBricks = parser.extractAllBricks(chords: chordNames, labels: labels)
        let alignedBricks = PostProcessor.alignBricksWithKeys(bricks: rawBricks, keySpans: keyMap)
        return (tree, alignedBricks)
    }

    /// P0-2: CYK解析后将brickType标注到每个ChordBlock上 (阶段4.1: 标签+砖双源)
    func stampBrickTypes() -> [ChordBlock] {
        let (tree, bricks) = parseBricks()
        var flat = flattenRoadmap()
        let labels = computeRelativeFunctionLabels(chords: flat)

        for b in bricks { print("  Brick: \(b.name) [\(b.start)-\(b.end)]") }
        let brickNames = bricks.map(\.name).joined(separator: ", ")
        let prog = flat.map(\.name).joined(separator: " ")
        #if DEBUG
        print("【BRICK-MATCH】 matched=\(bricks.count) bricks=[\(brickNames)] progression=\(prog)")
        #endif

        // 先盖CYK砖名，再以通用标签兜底 (消灭nil)
        for i in 0..<flat.count {
            flat[i].brickType = labels[i]
            for brick in bricks {
                if Double(i) >= brick.start && Double(i) < brick.end {
                    flat[i].brickType = brick.name
                }
            }
        }
        let typeSummary = flat.map { "\($0.name):\($0.brickType ?? "nil")" }.joined(separator: " ")
        #if DEBUG
        print("【BRICK-STAMP】 \(typeSummary)")
        #endif
        return flat
    }

    // MARK: - 阶段4.1: 相对音程功能标签计算

    /// 为每个和弦计算功能标签 (全曲统一主调推断)
    func computeRelativeFunctionLabels(chords: [ChordBlock]) -> [String] {
        guard !chords.isEmpty else { return [] }
        // 以首和弦推断全曲主调
        let anchor = chords.first!
        let tonicPC = anchor.chordRootPC()
        let mode: JazzMode = anchor.getChordFamily() == .minor ? .minor : .major
        #if DEBUG
        print("[4.1-KEY] tonic=\(tonicPC) mode=\(mode)")
        #endif

        var labels: [String] = []
        var beat: Double = 0
        for chord in chords {
            let label = computeLabel(chord: chord, tonicPC: tonicPC, mode: mode)
            labels.append(label)
            if labels.count <= 6 {
                #if DEBUG
                print("[4.1-LABEL] beat=\(beat) chord=\(chord.name) root=\(chord.chordRootPC()) tonic=\(tonicPC) interval=\((chord.chordRootPC()-tonicPC+12)%12) → \(label)")
                #endif
            }
            beat += chord.duration
        }
        return labels
    }

    /// 单和弦 → 功能标签
    private func computeLabel(chord: ChordBlock, tonicPC: Int, mode: JazzMode) -> String {
        let chordPC = chord.chordRootPC()
        let interval = (chordPC - tonicPC + 12) % 12
        let family = chord.getChordFamily()

        let degree: String
        switch interval {
        case 0:  degree = "I"
        case 1:  degree = "bII"
        case 2:  degree = "ii"
        case 3:  degree = mode == .minor ? "III" : "bIII"
        case 4:  degree = "iii"
        case 5:  degree = mode == .minor ? "iv" : "IV"
        case 6:  degree = "bV"
        case 7:  degree = "V"
        case 8:  degree = "bVI"
        case 9:  degree = mode == .minor ? "VI" : "vi"
        case 10: degree = "bVII"
        case 11: degree = "vii"
        default: degree = "I"
        }

        switch (degree, family) {
        case ("ii", .halfDiminished): return "iiø"
        case ("V", .dominant):   return mode == .minor ? "V7alt" : "V"
        case ("bII", .dominant): return "bII7"    // 三全音替代属七
        case ("bVI", .minor):    return "bvi"     // 降六级小和弦
        case (_, .halfDiminished): return "\(degree)ø"
        default: return degree
        }
    }
    
    /// 阶段3: 反向查表 — 语法砖名是否匹配当前CYK功能名
    static func grammarBrickMatches(cykName: String, grammarName: String) -> Bool {
        if cykName == grammarName { return true }
        if let mapped = cykToGrammarMap[cykName] {
            return mapped.contains(grammarName)
        }
        return false
    }
    
    /// CYK功能名 → 语法砖名 映射表 (阶段3)
    static let cykToGrammarMap: [String: [String]] = [
        "I":            ["Major-On"],
        "I-IV":         ["Surge"],
        "I-vi-ii-V":    ["POT", "Rhythm-Bridge", "SPOT",
                         "Cadence+TTFA-Dropback", "Dizzy-Sub-Turnaround",
                         "TTFA-Dropback", "Tension-SPOT", "POT+On",
                         "On-+-Dropback"],
        "ii-bII-I":     ["Body-&-Soul-Cadence", "Dizzy-Cadence", "Dominant-Cycle-Cadence",
                         "Donna-Lee-Opening", "Dropback", "Happenstance-Turnaround",
                         "Long-Cadence", "Starlight-Cadence", "Straight-Cadence",
                         "Supertension-Ending", "Tension-Cadence", "Two-Goes-Straight-Cadence",
                         "Yardbird-Cadence", "Straight-Cadence-+-Dropback",
                         "Tension-Cadence-+-Overrun",
                         "Happenstance-Cadence"],
        "ii-V":         ["Dizzy-Approach", "Dominant-Cycle", "Minor-Chromatic-Walkdown",
                         "Straight-Approach", "Straight-Launcher", "Yardbird-Approach",
                         "Chromatic-Approach", "Dogleg-Approach",
                         "Dominant-Cycle-2-Steps", "Two-Goes-Approach",
                         "7sus4-to-3", "Nowhere-Approach", "Reverse-Dominant-Cycle-2-Steps"],
        "ii-V-ii-V-I":  ["Two-Goes-Straight-Cadence", "Straight-Cadence",
                         "Long-Cadence", "Starlight-Cadence", "Yardbird-Cadence"],
        "i":            ["Minor-On",
                         "Ascending-Minor-CESH", "Descending-Minor-CESH"],
        "ii-V-I":       ["Body-&-Soul-Cadence", "Dizzy-Cadence", "Dominant-Cycle-Cadence",
                         "Donna-Lee-Opening", "Dropback", "Giant-Steps",
                         "Happenstance-Turnaround", "II-n-Bird-POT", "IV-n-Back",
                         "IV-n-Bird-SPOT", "Long-Cadence", "On-Off-On-Minor-V",
                         "On-Off-On-To-V", "Starlight-Cadence", "Straight-Cadence",
                         "Supertension-Ending", "Tension-Cadence", "To-IV-n-Yak",
                         "Two-Goes-Straight-Cadence", "Yardbird-Cadence",
                         "Straight-Cadence-+-Dropback", "Tension-Cadence-+-Overrun",
                         "Dizzy-Cadence-with-bIII7", "Dizzy-Cadence-with-bVIm",
                         "Extended-Cadence-with-Tritone-Sub",
                         "Chromatic-Major-Walkup", "Diatonic-ii-iii-IV-V",
                         "Autumnal-Cadence", "Dogleg-Cadence", "II-n-Back",
                         "Rainy-Cadence", "Starlight-Approach",
                         "Autumn-Leaves-Opening", "Diatonic-I-ii-iii", "Diatonic-I-ii-iii-ii",
                         "Donna-Lee-Start", "Pullback", "Rainy-Pullback-Extended",
                         "Stablemates-Approach"],
        "minor-ii-V-i": ["Sad-Cadence", "Suprise-Major-Tension-Cadence", "Surprise-Major-Cadence",
                         "Minor-Dropback", "Minor-Perfect-Cadence", "Minor-POT",
                         "Nowhere-Minor-Cadence",
                         "Off-On-Minor-#IV", "Off-On-Minor-IV", "Off-On-Minor-Somewhere",
                         "On-Off-Minor-III", "On-Off-Minor-Somewhere", "On-Off-Minor-VI",
                         "On-Off-Minor-bVII",
                         "On-Off-On-Twice-Minor-V", "On-Off-Thrice-Minor-V",
                         "On-Off-Twice-Minor-V"],
        "V-I":          ["Straight-Cadence", "Long-Cadence", "Starlight-Cadence",
                         "Straight-Cadence-+-Dropback", "Tension-Cadence-+-Overrun",
                         "Body-&-Soul-Cadence", "Dominant-Cycle-Cadence", "Dropback",
                         "Happenstance-Turnaround", "IV-n-Back", "On-Off-On-To-V",
                         "Supertension-Ending", "To-IV-n-Yak",
                         "Two-Goes-Straight-Cadence", "Yardbird-Cadence",
                         "Dropback(tritone)", "Amen-Cadence",
                         "On-Off-Major-#IV", "On-Off-Major-III", "On-Off-Major-V",
                         "On-Off-Major-VI", "On-Off-Major-VII", "On-Off-Major-bIII",
                         "On-Off-Major-bVII", "To-IV"],
        "iii-vi":       ["Dominant-Cycle"],
        "vi-ii":        ["Dizzy-Approach", "Minor-Chromatic-Walkdown"],
        // 阶段4.1: 单级功能key (非砖覆盖段fallback)
        "V":            ["Straight-Cadence", "Long-Cadence", "Starlight-Cadence",
                         "Straight-Cadence-+-Dropback", "Tension-Cadence-+-Overrun",
                         "Body-&-Soul-Cadence", "Dominant-Cycle-Cadence", "Dropback",
                         "Happenstance-Turnaround", "IV-n-Back", "On-Off-On-To-V",
                         "Supertension-Ending", "To-IV-n-Yak",
                         "Two-Goes-Straight-Cadence", "Yardbird-Cadence",
                         "Dropback(tritone)", "Amen-Cadence",
                         "On-Off-Major-#IV", "On-Off-Major-III", "On-Off-Major-V",
                         "On-Off-Major-VI", "On-Off-Major-VII", "On-Off-Major-bIII",
                         "On-Off-Major-bVII", "To-IV"],
        "IV":           ["Surge"],
        "ii":           ["Dizzy-Approach", "Dominant-Cycle", "Minor-Chromatic-Walkdown",
                         "Straight-Approach", "Straight-Launcher", "Yardbird-Approach"],
        "iii":          ["Dominant-Cycle"],
        "vi":           ["Dizzy-Approach", "Minor-Chromatic-Walkdown"],
        "iv":           ["Sad-Cadence", "Suprise-Major-Tension-Cadence", "Surprise-Major-Cadence"],
        "III":          ["Major-On"],
        "bIII":         ["Major-On"],
        "bVI":          ["Surge"],
        "bVII":         ["Straight-Cadence", "Long-Cadence", "Starlight-Cadence",
                         "Straight-Cadence-+-Dropback", "Tension-Cadence-+-Overrun"],
        "bV":           ["Straight-Cadence", "Starlight-Cadence",
                         "Straight-Cadence-+-Dropback", "Tension-Cadence-+-Overrun"],
        "bII":          ["Straight-Cadence", "Starlight-Cadence",
                         "Straight-Cadence-+-Dropback", "Tension-Cadence-+-Overrun"],
        "subV":         ["Straight-Cadence", "Starlight-Cadence",
                         "Straight-Cadence-+-Dropback", "Tension-Cadence-+-Overrun"],
        "bII7":         ["Straight-Cadence", "Starlight-Cadence",
                         "Straight-Cadence-+-Dropback", "Tension-Cadence-+-Overrun"],
        "bvi":          ["Surge"],
        "iiø":          ["Sad-Cadence", "Suprise-Major-Tension-Cadence", "Surprise-Major-Cadence"],
        "V7alt":        ["Sad-Cadence", "Suprise-Major-Tension-Cadence", "Surprise-Major-Cadence",
                         "Straight-Cadence", "Starlight-Cadence",
                         "Straight-Cadence-+-Dropback", "Tension-Cadence-+-Overrun"],
        "viio":         ["Dropback", "Body-&-Soul-Cadence"],
    ]
}

// MARK: - 阶段4.2: 动态产生式生成

extension BrickLibrary.BrickTemplate {
    /// 功能组 → 子块序列
    static let functionGroupBlocks: [String: [String]] = [
        "ii-V-I":       ["ii","V","I"],
        "minor-ii-V-i": ["iiø","V7alt","i"],
        "V-I":          ["V","I"],
        "I-IV":         ["I","IV"],
        "iii-vi":       ["iii","vi"],
        "vi-ii":        ["vi","ii"],
        "I-vi-ii-V":    ["I","vi","ii","V"],
        "iii-vi-ii-V-I":["iii","vi","ii","V","I"],  // Long-Cadence等
        "ii-iii-IV-V":  ["ii","iii","IV","V"],       // Diatonic-ii-iii-IV-V
        "ii-V-ii-V-I":  ["ii","V","ii","V","I"],      // Two-Goes-Straight-Cadence (2400slots)
        "ii-bII-I":     ["ii","subV","I"],           // 三全音替代终止式
        "I-bvi-bII":    ["I","bvi","subV"],          // 三全音回转Turnaround
    ]

    /// 砖名 → 功能组 (特殊映射)
    static let brickGroupOverrides: [String: String] = [
        "Long-Cadence": "iii-vi-ii-V-I",
        "Diatonic-ii-iii-IV-V": "ii-iii-IV-V",
        "Dizzy-Sub-Turnaround": "I-bvi-bII",
        "Cadence+TTFA-Dropback": "I-vi-ii-V",
        "Extended-Cadence-with-Tritone-Sub": "ii-bII-I",
    ]

    /// 砖名 → 功能组
    static func functionGroup(for brickName: String) -> String? {
        if functionGroupBlocks[brickName] != nil { return brickName }
        if let override = brickGroupOverrides[brickName] { return override }
        let keys = JazzRoadmap.cykToGrammarMap.keys.filter { functionGroupBlocks[$0] != nil }.sorted().joined(separator: ",")
        var best: String? = nil
        var bestLen = 0
        for (group, names) in JazzRoadmap.cykToGrammarMap {
            guard let blocks = functionGroupBlocks[group] else { continue }
            if names.contains(brickName) && blocks.count > bestLen {
                best = group
                bestLen = blocks.count
            }
        }
        return best
        return nil
    }

    /// 获取砖的子块序列
    var subBlocks: [String] {
        if let blocks = Self.functionGroupBlocks[name] { return blocks }
        if let group = Self.functionGroup(for: name), let blocks = Self.functionGroupBlocks[group] {
            return blocks
        }
        return []
    }
}

/// 从 BrickLibrary 动态生成 CYK BinaryProduction[] (阶段B: 全量, 功能组去重)
func generateProductions(from bricks: [BrickLibrary.BrickTemplate], pocOnly: Bool = true) -> [BinaryProduction] {
    // 收集所有唯一功能组+子块结构的砖名
    var groupBricks: [String: Set<String>] = [:]  // 功能组 → 砖名集合
    for brick in bricks {
        guard let group = BrickLibrary.BrickTemplate.functionGroup(for: brick.name) else { continue }
        let blocks = brick.subBlocks
        guard blocks.count >= 2 else { continue }
        groupBricks[group, default: []].insert(brick.name)
    }

    var productions: [BinaryProduction] = []
    var seen = Set<String>()  // 去重: "left|right"

    for (group, blocks) in BrickLibrary.BrickTemplate.functionGroupBlocks {
        let n = blocks.count
        guard n >= 2 else { continue }

        let prefix = group.replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: "&", with: "n")

        if n == 2 {
            let key = "\(blocks[0])|\(blocks[1])"
            if !seen.contains(key) {
                seen.insert(key)
                productions.append(BinaryProduction(left: blocks[0], right: blocks[1],
                                                    result: group, weight: 10, keyDiff: nil))
            }
        } else {
            // 泛化中间节点: 用子块内容命名 ← 共享同结构组的中间节点
            var curName = "\(blocks[0])_\(blocks[1])"
            let key0 = "\(blocks[0])|\(blocks[1])"
            if !seen.contains(key0) {
                seen.insert(key0)
                productions.append(BinaryProduction(left: blocks[0], right: blocks[1],
                                                    result: curName, weight: 5, keyDiff: nil))
            }
            for i in 2..<n-1 {
                let prevName = curName
                curName = prevName + "_\(blocks[i])"
                let key = "\(prevName)|\(blocks[i])"
                if !seen.contains(key) {
                    seen.insert(key)
                    productions.append(BinaryProduction(left: prevName, right: blocks[i],
                                                        result: curName, weight: 5, keyDiff: nil))
                }
            }
            // 最终: group ← curName, blocks[n-1]
            let finalKey = "\(curName)|\(blocks[n-1])"
            if !seen.contains(finalKey) {
                seen.insert(finalKey)
                productions.append(BinaryProduction(left: curName, right: blocks[n-1],
                                                    result: group, weight: 10, keyDiff: nil))
            }
        }
    }

    let activeGroups = groupBricks.keys.sorted().joined(separator: ",")
    #if DEBUG
    print("[4.2-PRODUCTIONS] generated \(productions.count) productions for groups=[\(activeGroups)]")
    #endif
    return productions
}


