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
        let referenceKey: Int      // 参考调性 PC (0=C, 1=Db, ..., 11=B), 用于转调平移
        let type: String           // 砖类型 (Cadence/Approach/Turnaround/... 16种值), 硬编码砖默认 ""
        let mode: String           // ← P0: 调式 (Major/Minor/Dominant), 来自 defbrick 第3字段, 硬编码砖默认 "Major"

        // 自定义 init, referenceKey 默认 0 (C 大调), type 默认 "", mode 默认 "Major", 避免修改现有 100+ 个 standardBricks
        init(name: String,
             chords: [String],
             category: BrickCategory,
             style: [String],
             beats: Double,
             substitutions: [String],
             referenceKey: Int = 0,
             type: String = "",
             mode: String = "Major") {
            self.name = name
            self.chords = chords
            self.category = category
            self.style = style
            self.beats = beats
            self.substitutions = substitutions
            self.referenceKey = referenceKey
            self.type = type
            self.mode = mode
        }

        /// 转调: 将参考调性的具体和弦整体平移到目标调性
        /// 复用 Transposition.chromatic (Harmony/Transposition.swift:63)
        /// - Parameter targetKey: 目标调性 PC (0=C, 1=Db, ..., 11=B)
        /// - Returns: 转调后的新 BrickTemplate (referenceKey = targetKey)
        func transpose(to targetKey: Int) -> BrickTemplate {
            let semitones = (targetKey - referenceKey + 12) % 12
            guard semitones != 0 else { return self }
            let transposedChords = chords.map { Transposition.chromatic($0, semitones: semitones) }
            return BrickTemplate(
                name: name,
                chords: transposedChords,
                category: category,
                style: style,
                beats: beats,
                substitutions: substitutions,
                referenceKey: targetKey,
                type: type,
                mode: mode
            )
        }

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
    // 2. 内置标准爵士和声模板库 (硬编码 fallback)
    // ═══════════════════════════════════════════════════════

    /// 硬编码砖库 (当 My.dictionary 加载失败时的 fallback)
    private static let hardcodedBricks: [BrickTemplate] = [

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

    // ═══════════════════════════════════════════════════════
    // 3. 砖库访问入口 (优先从 My.dictionary 加载, fallback 到硬编码)
    // ═══════════════════════════════════════════════════════

    /// brick-type 代价表 (16个, 从 My.dictionary 加载)
    /// 键: type 名 (Cadence/Approach/...), 值: 代价 (25/45/...)
    /// 问题5: 用于 generateProductions 中计算产生式 weight, 实现同名结构砖的差异化优先级
    static var brickTypeCosts: [String: Int] = [:]

    /// 砖库访问入口
    /// 优先从 My.dictionary 加载 (556 个原版砖定义), 失败则 fallback 到硬编码砖 (100+)
    static var standardBricks: [BrickTemplate] {
        // 静态缓存, 只加载一次
        struct Cache {
            static var loaded = false
            static var bricks: [BrickTemplate] = []
        }
        if !Cache.loaded {
            if let result = BrickDictionaryParser.loadDefault() {
                Cache.bricks = result.bricks
                brickTypeCosts = result.brickTypeCosts    // 问题5: 保存代价表
                dprint("[BRICK-LIB] 从 My.dictionary 加载 \(result.bricks.count) 个砖, \(brickTypeCosts.count) 个 brick-type 代价")
            } else {
                Cache.bricks = hardcodedBricks
                brickTypeCosts = [:]    // 硬编码砖无 type, 代价表为空
                dprint("[BRICK-LIB] fallback 到硬编码砖 \(hardcodedBricks.count) 个")
            }
            Cache.loaded = true
        }
        return Cache.bricks
    }
}

// MARK: - JazzRoadmap 扩展: Brick解析集成

extension JazzRoadmap {
    /// 对当前和弦序列执行CYK解析+Brick匹配 (阶段4: 转调枚举匹配)
    func parseBricks() -> (tree: TreeNode?, bricks: [(name: String, start: Double, end: Double, key: String, referenceKey: Int)]) {
        let chords = flattenRoadmap()
        let labels = computeRelativeFunctionLabels(chords: chords)
        let chordNames = chords.map { $0.name }

        // 🔍 DEBUG: 打印 keyMap、和弦序列、叶子标签
        #if DEBUG
        let keyMapStr = keyMap.map { "(\($0.rootPC)/\($0.mode) [\($0.startBeat)-\($0.endBeat)])" }.joined(separator: ", ")
        dprint("🔍 [DEBUG-KEYMAP] keyMap=[\(keyMapStr)]")
        dprint("🔍 [DEBUG-CHORDS] chords=\(chordNames.joined(separator: " "))")
        dprint("🔍 [DEBUG-LABELS] labels=\(labels.joined(separator: " "))")
        #endif

        // 只枚举调性链中的 key (2-3 个), 不枚举全部 12 个
        let keysFromMap = Array(Set(keyMap.map { $0.rootPC })).sorted()
        // 至少包含 C(0) 作为兜底 (硬编码模板默认 referenceKey=0)
        let allKeys = keysFromMap.contains(0) ? keysFromMap : [0] + keysFromMap

        var allMatchedBricks: [(name: String, start: Double, end: Double, referenceKey: Int)] = []
        var bestTree: TreeNode?

        // 🔍 性能计时
        let totalStart = Date()
        var perKeyTimes: [String] = []

        for key in allKeys {
            let keyStart = Date()
            // 把 standardBricks 转调到当前 key (阶段1 已实现 transpose(to:))
            let transposedBricks = BrickLibrary.standardBricks.map { $0.transpose(to: key) }
            let dynProds = generateProductions(from: transposedBricks, pocOnly: false)

            // 🔍 DEBUG: 打印 V-I 相关产生式
            #if DEBUG
            let viProds = dynProds.filter { $0.left == "V" && $0.right == "I" }
            let viNames = viProds.map { "\($0.result)(w=\($0.weight))" }.joined(separator: ",")
            dprint("🔍 [DEBUG-PRODS] key=\(key) V-I产生式: \(viProds.count)个 [\(viNames)]")
            // 打印所有 result 包含 "-" 的产生式（真正的砖名）
            let realBricks = dynProds.filter { $0.result.contains("-") }
            dprint("🔍 [DEBUG-PRODS] key=\(key) 真正砖产生式: \(realBricks.count)个")
            #endif

            let parser = CYKParser(binaryProductions: dynProds)
            // 性能优化: 一次 CYK 返回 dp, extractAllBricks 复用 dp, 不再重跑
            let (tree, dp, n) = parser.parseWithLabelsReturnDP(labels: labels, chordNames: chordNames)
            let rawBricks = parser.extractAllBricks(from: dp, n: n)

            // 🔍 DEBUG: 打印 dp 表中所有长度=2 的区间（两个和弦的组合）的解析结果 (方案A 多值 dp)
            #if DEBUG
            var dp2Info: [String] = []
            for i in 0..<n {
                let j = i + 2
                guard j <= n else { continue }
                let nodes = dp[i][j].values
                if !nodes.isEmpty {
                    let nodeStr = nodes.map { "\($0.brickName ?? "nil")(cost=\($0.cost))" }.joined(separator: "|")
                    dp2Info.append("[\(i)-\(j)] \(nodeStr)")
                }
            }
            dprint("🔍 [DEBUG-DP2] key=\(key) 长度=2区间: \(dp2Info.joined(separator: ", "))")
            #endif

            let keyElapsed = Date().timeIntervalSince(keyStart)
            perKeyTimes.append("key=\(key): \(String(format: "%.3f", keyElapsed))s (matched=\(rawBricks.count))")

            // 记录 referenceKey
            let bricksWithKey = rawBricks.map {
                (name: $0.name, start: $0.start, end: $0.end, referenceKey: key)
            }
            allMatchedBricks.append(contentsOf: bricksWithKey)
            if tree != nil && bestTree == nil { bestTree = tree }
        }

        let totalElapsed = Date().timeIntervalSince(totalStart)
        #if DEBUG
        dprint("🔍 [PERF] CYK总耗时: \(String(format: "%.3f", totalElapsed))s, key数=\(allKeys.count), 匹配砖=\(allMatchedBricks.count)")
        dprint("🔍 [PERF] 各key耗时: \(perKeyTimes.joined(separator: ", "))")
        #endif

        // 合并去重 + 调试日志记录所有匹配到的 key
        #if DEBUG
        let debugInfo = Dictionary(grouping: allMatchedBricks, by: { "\($0.start)-\($0.end)" })
            .map { interval, bricks in
                let keys = bricks.map { "\($0.referenceKey):\($0.name)" }.joined(separator: ",")
                return "[\(interval)] keys=[\(keys)]"
            }.joined(separator: " ")
        dprint("[BRICK-TRANSPOSE] keysToTry=\(allKeys) matched=\(allMatchedBricks.count) \(debugInfo)")
        #endif

        var uniqueBricks: [(name: String, start: Double, end: Double, referenceKey: Int)] = []
        var coveredIntervals = Set<String>()
        for b in allMatchedBricks {
            let intervalKey = "\(b.start)-\(b.end)"
            if !coveredIntervals.contains(intervalKey) {
                coveredIntervals.insert(intervalKey)
                uniqueBricks.append(b)
            }
        }

        // 直接改现有 alignBricksWithKeys (已加 referenceKey 透传)
        let alignedBricks = PostProcessor.alignBricksWithKeys(bricks: uniqueBricks, keySpans: keyMap)
        return (bestTree, alignedBricks)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - P0: parseBricksV2 (CYK 前置识别 Brick, 不依赖 keyMap)
    // ═══════════════════════════════════════════════════════════

    /// P0: 从砖名查 BrickTemplate (用于获取 type/mode)
    private func brickTemplate(for brickName: String) -> BrickLibrary.BrickTemplate? {
        return BrickLibrary.standardBricks.first { $0.name == brickName }
    }

    /// P0: 从砖名查 BrickTemplate.type
    private func brickType(for brickName: String) -> String {
        return brickTemplate(for: brickName)?.type ?? ""
    }

    /// P0: 从砖名查 BrickTemplate.mode
    private func brickMode(for brickName: String) -> String {
        return brickTemplate(for: brickName)?.mode ?? "Major"
    }

    /// P0: 从 dp 表提取带 cost 的砖 (替代 extractAllBricks, 保留 cost 字段)
    /// 方案A: 遍历多值 dp[i][j].values
    private func extractBricksWithCost(from dp: [[[String: TreeNode]]], n: Int) -> [(name: String, start: Double, end: Double, cost: Int)] {
        var result: [(name: String, start: Double, end: Double, cost: Int)] = []
        for i in 0..<n {
            let minJ = i + 2
            guard minJ <= n else { continue }
            for j in minJ...n {
                for node in dp[i][j].values {
                    guard let bn = node.brickName else { continue }
                    // 过滤中间节点: 长度超3且非最终组名
                    let isIntermediate = bn.count > 3 && bn.contains("_") && !bn.contains("-")
                    if isIntermediate { continue }
                    result.append((name: bn, start: Double(i), end: Double(j), cost: node.cost))
                }
            }
        }
        return result
    }

    /// P0: 区间去重 — 精确区间相等取 cost 更低者; 部分重叠取 cost 更低完整砖 (不拆分)
    private func deduplicateBricks(
        _ bricks: [(name: String, start: Double, end: Double,
                     referenceKey: Int, type: String, mode: String, cost: Int)]
    ) -> [(name: String, start: Double, end: Double,
          referenceKey: Int, type: String, mode: String, cost: Int)] {
        // 按 cost 升序, cost 相同按 start 升序, 再相同按 referenceKey 升序 (确定性 tie-breaker)
        let sorted = bricks.sorted {
            if $0.cost != $1.cost { return $0.cost < $1.cost }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.referenceKey < $1.referenceKey
        }
        var result: [(name: String, start: Double, end: Double,
                       referenceKey: Int, type: String, mode: String, cost: Int)] = []
        var coveredIntervals = Set<String>()

        for b in sorted {
            let intervalKey = "\(b.start)-\(b.end)"
            // 精确区间相等: 已被更低 cost 的砖覆盖, 跳过
            if coveredIntervals.contains(intervalKey) { continue }
            // 部分重叠: 检查是否与已选砖重叠
            let overlaps = result.contains {
                !(b.end <= $0.start || b.start >= $0.end)
            }
            if overlaps {
                // 重叠时: 当前砖 cost 更高(因为 sorted), 跳过; 保留已选的更低 cost 完整砖
                continue
            }
            coveredIntervals.insert(intervalKey)
            result.append(b)
        }
        // 按 start 排序返回
        return result.sorted { $0.start < $1.start }
    }

    /// P0: 将 CYK 识别的 brick 与原始和弦合并成 [PostProcessorFull.AnalysisBlock]
    /// brick 覆盖的和弦打包成 .brick, 未被任何 brick 覆盖的和弦保持 .chord
    private func mergeBricksIntoBlocks(
        chords: [PostProcessorFull.AnalysisChord],
        bricks: [(name: String, start: Double, end: Double,
                  referenceKey: Int, type: String, mode: String, cost: Int)]
    ) -> [PostProcessorFull.AnalysisBlock] {
        var blocks: [PostProcessorFull.AnalysisBlock] = []
        var chordIdx = 0

        for brick in bricks {
            // brick.start/end 是 CYK dp 表索引 (= 和弦序号), 不是拍数
            let s = Int(brick.start)
            let e = min(Int(brick.end), chords.count)
            guard s < e else { continue }

            // 先把 brick 之前未覆盖的和弦加进去
            while chordIdx < s && chordIdx < chords.count {
                blocks.append(.chord(chords[chordIdx]))
                chordIdx += 1
            }

            // 收集 brick 覆盖的和弦
            let startChordIdx = s
            let brickChords = Array(chords[s..<e])
            chordIdx = e

            // 构建 AnalysisBrick (mode 从 brick.mode 取, 不从 type 推断)
            let analysisBrick = PostProcessorFull.AnalysisBrick(
                name: brick.name,
                key: brick.referenceKey,
                mode: brick.mode,
                type: brick.type,
                duration: brick.end - brick.start,
                chords: brickChords,
                isSectionEnd: brickChords.last?.isSectionEnd ?? false,
                startChordIdx: startChordIdx,
                endChordIdx: chordIdx,
                cost: brick.cost
            )
            blocks.append(.brick(analysisBrick))
        }

        // 把剩余未覆盖的和弦加进去
        while chordIdx < chords.count {
            blocks.append(.chord(chords[chordIdx]))
            chordIdx += 1
        }

        return blocks
    }

    /// P0: CYK 前置识别 Brick (枚举 12 个 key, 不依赖 keyMap)
    /// 返回 (TreeNode?, [PostProcessorFull.AnalysisBlock])
    /// 对齐原版单向流程: RoadMap → CYK 识别 Brick → findKeys
    func parseBricksV2() -> (TreeNode?, [PostProcessorFull.AnalysisBlock]) {
        let chords = flattenRoadmap()
        let chordNames = chords.map { $0.name }

        // 枚举全部 12 个 key (不依赖 keyMap, 对齐原版 findSolution)
        let allKeys = Array(0..<12)

        var allMatchedBricks: [(name: String, start: Double, end: Double,
                                 referenceKey: Int, type: String, mode: String, cost: Int)] = []
        var bestTree: TreeNode?

        for key in allKeys {
            // P0-d: 每个 trial key 独立计算 labels (用 computeLabel, 不依赖 keyMap, 打破循环依赖)
            // 之前用 computeRelativeFunctionLabels(chords:) 依赖旧 keyMap, 导致 Bbmaj7 被标成 bVII 而非 I
            let labelsForKey = chords.map { computeLabel(chord: $0, tonicPC: key, mode: .major) }
            let transposedBricks = BrickLibrary.standardBricks.map { $0.transpose(to: key) }
            let dynProds = generateProductions(from: transposedBricks, pocOnly: false)

            // 🔍 DEBUG: 调查 iiø-V-i 为何不匹配 — 只打印 key=7
            #if DEBUG
            if key == 7 {
                let labelStr = zip(chords, labelsForKey).map { "\($0.name)=\($1)" }.joined(separator: " ")
                dprint("🔍 [IIOVI-DEBUG] key=7 labels: \(labelStr)")
                let iiøProds = dynProds.filter { $0.left.contains("iiø") || $0.right.contains("iiø") || $0.result.contains("iiø") }
                dprint("🔍 [IIOVI-DEBUG] key=7 iiø productions (\(iiøProds.count)): \(iiøProds.prefix(10).map { "\($0.left)+\($0.right)→\($0.result)" }.joined(separator: ", "))")
                let autumnal = transposedBricks.filter { $0.name.contains("Autumnal") || $0.name.contains("Sad") }
                dprint("🔍 [IIOVI-DEBUG] key=7 Autumnal/Sad bricks: \(autumnal.map { "\($0.name)(\($0.chords.joined(separator: "-")))" }.joined(separator: ", "))")
            }
            #endif

            // P0-e 已回退: 重新启用 defaultSubstitutions (Cm7→"ii" 区分 ii vs V, 防止 V_I 错误匹配 Cm7→F7)
            // P0-d 的 per-key labels 仅作为 substitution 未命中时的 fallback
            let parser = CYKParser(binaryProductions: dynProds)
            let (tree, dp, n) = parser.parseWithLabelsReturnDP(labels: labelsForKey, chordNames: chordNames)

            // 🔍 DEBUG: key=7 时打印 Sad-Cadence 匹配详情 (方案A 多值 dp)
            #if DEBUG
            if key == 7 {
                let hasIIV = dynProds.contains { $0.left == "iiø" && $0.right == "V" && $0.result == "iiø_V" }
                let hasSad = dynProds.contains { $0.left == "iiø_V" && $0.right == "I" && $0.result.contains("Sad") }
                let dp46str = dp[4][6].values.map { "\($0.brickName ?? "nil") cost=\($0.cost)" }.joined(separator: ", ")
                let dp57str = dp[5][7].values.map { "\($0.brickName ?? "nil") cost=\($0.cost)" }.joined(separator: ", ")
                let dp47str = dp[4][7].values.map { "\($0.brickName ?? "nil") cost=\($0.cost)" }.joined(separator: ", ")
                dprint("🔍 [SAD-DEBUG] key=7 prods: iiø+V→iiø_V=\(hasIIV), iiø_V+I→Sad=\(hasSad)")
                dprint("🔍 [SAD-DEBUG] key=7 dp[4][6](Am7b5+D7b13): \(dp46str.isEmpty ? "nil" : dp46str)")
                dprint("🔍 [SAD-DEBUG] key=7 dp[5][7](D7b13+Gm6): \(dp57str.isEmpty ? "nil" : dp57str)")
                dprint("🔍 [SAD-DEBUG] key=7 dp[4][7](Am7b5+D7b13+Gm6): \(dp47str.isEmpty ? "nil" : dp47str)")
            }
            #endif

            // P0: 用 extractBricksWithCost 替代 extractAllBricks, 保留 cost 字段
            let rawBricks = extractBricksWithCost(from: dp, n: n)

            let bricksWithMeta = rawBricks.map {
                (name: $0.name, start: $0.start, end: $0.end,
                 referenceKey: key,
                 type: brickType(for: $0.name),
                 mode: brickMode(for: $0.name),
                 cost: $0.cost)
            }
            allMatchedBricks.append(contentsOf: bricksWithMeta)
            if tree != nil && bestTree == nil { bestTree = tree }
        }

        // 区间去重: 精确区间相等取 cost 更低者; 部分重叠取 cost 更低完整砖 (不拆分)
        let uniqueBricks = deduplicateBricks(allMatchedBricks)

        // 🔍 DEBUG: 打印 parseBricksV2 匹配到的砖 (含 key)
        #if DEBUG
        let brickStr = uniqueBricks.map { "\($0.name)(key=\($0.referenceKey),\($0.mode))[\($0.start)-\($0.end)]" }.joined(separator: ", ")
        dprint("🔍 [PARSEBRICKS-V2] matched=\(uniqueBricks.count) bricks=[\(brickStr)]")
        #endif

        // P0-c: 用 substitution 标签 (key 无关) 找 "I" 级和弦, 推导砖的实际 key/mode
        // 不用 brick.referenceKey (trial key 0-11 任意值), 因为 substitution 标签固定不变
        // subMap 构建用遍历取最低 cost (defaultSubstitutions 有 Fmaj7/Em7/Bm7/Am7 重复 chordName)
        var subMap: [String: String] = [:]
        var subCost: [String: Int] = [:]
        for sub in CYKParser.defaultSubstitutions {
            if subCost[sub.chordName] == nil || sub.cost < subCost[sub.chordName]! {
                subMap[sub.chordName] = sub.brickName
                subCost[sub.chordName] = sub.cost
            }
        }

        let derivedBricks = uniqueBricks.map { brick -> (name: String, start: Double, end: Double,
                referenceKey: Int, type: String, mode: String, cost: Int) in
            let s = Int(brick.start)
            let e = min(Int(brick.end), chords.count)
            var actualKey = brick.referenceKey
            var actualMode = brick.mode
            if s < e {
                for i in s..<e {
                    // 用 substitution 标签 (key 无关), fallback 用 computeLabel(tonic=0)
                    let label = subMap[chords[i].name] ?? computeLabel(chord: chords[i], tonicPC: 0, mode: .major)
                    if label == "I" {
                        actualKey = chords[i].chordRootPC()
                        actualMode = chords[i].getChordFamily() == .minor ? "Minor" : "Major"
                        break
                    }
                }
            }
            return (name: brick.name, start: brick.start, end: brick.end,
                    referenceKey: actualKey, type: brick.type, mode: actualMode, cost: brick.cost)
        }

        // 构建 [AnalysisBlock] (buildAnalysisChords 已设置 chordIdx)
        let analysisChords = PostProcessorFull.buildAnalysisChords(from: chords)
        let blocks = mergeBricksIntoBlocks(chords: analysisChords, bricks: derivedBricks)

        return (bestTree, blocks)
    }

    /// P0-2: CYK解析后将brickType标注到每个ChordBlock上 (阶段4: 转调枚举匹配)
    func stampBrickTypes() -> [ChordBlock] {
        let (tree, bricks) = parseBricks()
        var flat = flattenRoadmap()
        let labels = computeRelativeFunctionLabels(chords: flat)

        for b in bricks { dprint("  Brick: \(b.name)(key=\(b.referenceKey)) [\(b.start)-\(b.end)]") }
        let brickNames = bricks.map { "\($0.name)(key=\($0.referenceKey))" }.joined(separator: ", ")
        let prog = flat.map(\.name).joined(separator: " ")
        #if DEBUG
        dprint("【BRICK-MATCH】 matched=\(bricks.count) bricks=[\(brickNames)] progression=\(prog)")
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
        dprint("【BRICK-STAMP】 \(typeSummary)")
        #endif
        return flat
    }

    // MARK: - 阶段4.1: 相对音程功能标签计算

    /// 为每个和弦计算功能标签 (按 keyMap 分段, P0-2 已接线 PostProcessorFull.findKeys)
    func computeRelativeFunctionLabels(chords: [ChordBlock]) -> [String] {
        guard !chords.isEmpty else { return [] }
        // 按 keyMap 分段计算标签: 每个和弦用所在 KeySpan 的 rootPC/mode 当 tonic
        var labels: [String] = []
        var beat: Double = 0
        for chord in chords {
            let currentSpan = keyMap.first { $0.contains(beat: beat) }
            let tonicPC = currentSpan?.rootPC ?? chords.first!.chordRootPC()
            let mode = currentSpan?.mode ?? (chord.getChordFamily() == .minor ? JazzMode.minor : .major)
            let label = computeLabel(chord: chord, tonicPC: tonicPC, mode: mode)
            labels.append(label)
            beat += chord.duration
        }
        return labels
    }

    /// 单和弦 → 功能标签
    private func computeLabel(chord: ChordBlock, tonicPC: Int, mode: JazzMode) -> String {
        // P0-问题1前置2: 去掉全部 4 处 mode 分支, 统一为 mode 无关的大调 degree 映射
        // 原因: 叶子标签(computeLabel)与 body 标签(deriveFunctionLabels)必须恒一致,
        //       转调多段曲(如 Autumn Leaves 前段大调后段小调)不能因 mode 分歧导致 CYK 匹配失败.
        // mode 参数保留但不再使用(兼容调用方签名, 阶段3可能重新引入).
        let _ = mode
        let chordPC = chord.chordRootPC()
        let interval = (chordPC - tonicPC + 12) % 12
        let family = chord.getChordFamily()

        let degree: String
        switch interval {
        case 0:  degree = "I"
        case 1:  degree = "bII"
        case 2:  degree = "ii"
        case 3:  degree = "bIII"      // 原 mode==.minor?"III":"bIII", 统一为 bIII
        case 4:  degree = "iii"
        case 5:  degree = "IV"        // 原 mode==.minor?"iv":"IV", 统一为 IV
        case 6:  degree = "bV"
        case 7:  degree = "V"
        case 8:  degree = "bVI"
        case 9:  degree = "vi"        // 原 mode==.minor?"VI":"vi", 统一为 vi
        case 10: degree = "bVII"
        case 11: degree = "vii"
        default: degree = "I"
        }

        switch (degree, family) {
        case ("ii", .halfDiminished): return "iiø"
        case ("V", .dominant):   return "V"   // 原 mode==.minor?"V7alt":"V", 统一为 V
        case ("bII", .dominant): return "bII7"    // 三全音替代属七
        case ("bVI", .minor):    return "bvi"     // 降六级小和弦
        case (_, .halfDiminished): return "\(degree)ø"
        default: return degree
        }
    }

    // MARK: - P0-问题1: 公共功能标签推导已移至 extension BrickLibrary.BrickTemplate

    /// 阶段3: 反向查表 — 语法砖名是否匹配当前CYK功能名
    static func grammarBrickMatches(cykName: String, grammarName: String) -> Bool {
        if cykName == grammarName { return true }
        if let mapped = cykToGrammarMap[cykName] {
            return mapped.contains(grammarName)
        }
        return false
    }
    
    /// CYK功能名 → 语法砖名 映射表 (阶段3)
    /// P0-问题1: 角色降级. 现在 generateProductions 的 result = 砖名, extractAllBricks
    /// 返回的 brickName 已是砖名, grammarBrickMatches 中 cykName==grammarName 直接匹配成功,
    /// 此映射表主要作为 fallback(砖名不完全匹配时的反向查找). 保留为兼容性.
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
        "bII7":         ["Straight-Cadence", "Starlight-Cadence",
                         "Straight-Cadence-+-Dropback", "Tension-Cadence-+-Overrun"],
        "bvi":          ["Surge"],
        "iiø":          ["Sad-Cadence", "Suprise-Major-Tension-Cadence", "Surprise-Major-Cadence"],
        "viio":         ["Dropback", "Body-&-Soul-Cadence"],
    ]
}

// MARK: - 阶段4.2: 动态产生式生成

extension BrickLibrary.BrickTemplate {
    /// 功能组 → 子块序列
    static let functionGroupBlocks: [String: [String]] = [
        "ii-V-I":       ["ii","V","I"],
        "minor-ii-V-i": ["iiø","V","i"],
        "V-I":          ["V","I"],
        "I-IV":         ["I","IV"],
        "iii-vi":       ["iii","vi"],
        "vi-ii":        ["vi","ii"],
        "I-vi-ii-V":    ["I","vi","ii","V"],
        "iii-vi-ii-V-I":["iii","vi","ii","V","I"],  // Long-Cadence等
        "ii-iii-IV-V":  ["ii","iii","IV","V"],       // Diatonic-ii-iii-IV-V
        "ii-V-ii-V-I":  ["ii","V","ii","V","I"],      // Two-Goes-Straight-Cadence (2400slots)
        "ii-bII-I":     ["ii","bII7","I"],           // 三全音替代终止式
        "I-bvi-bII":    ["I","bvi","bII7"],          // 三全音回转Turnaround
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
    /// P0-问题1: 已降级. generateProductions 和 subBlocks 已改为从 brick.chords 动态推导,
    /// 不再调用此方法. 保留仅为兼容性(可能有其他模块引用), 后续阶段6可清理.
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

    /// 获取砖的子块序列 (P0-问题1: 改为从 brick.chords 动态推导, 不再查硬编码 functionGroupBlocks)
    var subBlocks: [String] {
        return BrickLibrary.BrickTemplate.deriveFunctionLabels(
            from: chords, referenceKey: referenceKey)
    }

    // MARK: - P0-问题1: 公共功能标签推导 (mode无关, 与 computeLabel 恒一致)

    /// 从和弦名推导相对功能标签 (mode无关, 与 computeLabel 恒一致)
    /// 用于 deriveFunctionLabels 和 generateProductions, 确保叶子标签与 body 标签恒一致.
    /// - Parameters:
    ///   - chordName: 和弦名 (如 "Dm7", "G7", "Cmaj7")
    ///   - referenceKey: 参考调性 PC (0=C, 1=Db, ..., 11=B)
    /// - Returns: 功能标签 (如 "ii", "V", "I", "iiø", "bII7", "bvi", "bIII", "IV", "vi")
    static func chordToFunctionLabel(chordName: String, referenceKey: Int) -> String {
        // 复用 ChordBlock 的 chordRootPC() 和 getChordFamily(), 确保与 computeLabel 完全一致
        let chord = ChordBlock(name: chordName, duration: 0)
        let chordPC = chord.chordRootPC()
        let interval = (chordPC - referenceKey + 12) % 12
        let family = chord.getChordFamily()

        let degree: String
        switch interval {
        case 0:  degree = "I"
        case 1:  degree = "bII"
        case 2:  degree = "ii"
        case 3:  degree = "bIII"
        case 4:  degree = "iii"
        case 5:  degree = "IV"
        case 6:  degree = "bV"
        case 7:  degree = "V"
        case 8:  degree = "bVI"
        case 9:  degree = "vi"
        case 10: degree = "bVII"
        case 11: degree = "vii"
        default: degree = "I"
        }

        switch (degree, family) {
        case ("ii", .halfDiminished): return "iiø"
        case ("V", .dominant):   return "V"
        case ("bII", .dominant): return "bII7"
        case ("bVI", .minor):    return "bvi"
        case (_, .halfDiminished): return "\(degree)ø"
        default: return degree
        }
    }

    /// 从和弦名序列推导相对功能标签序列 (mode无关)
    /// - Parameters:
    ///   - chords: 和弦名序列 (如 ["Dm7","G7","Cmaj7"])
    ///   - referenceKey: 参考调性 PC (0=C, 1=Db, ..., 11=B)
    /// - Returns: 功能标签序列 (如 ["ii","V","I"]); 解析失败的和弦返回 "?"
    static func deriveFunctionLabels(from chords: [String], referenceKey: Int) -> [String] {
        return chords.map { chordToFunctionLabel(chordName: $0, referenceKey: referenceKey) }
    }
}

/// 从 BrickLibrary 动态生成 CYK BinaryProduction[] (P0-问题1: 每砖一产生式 + 性能优化按body去重)
/// 修改说明: 原版本遍历 functionGroupBlocks 的 12 个硬编码功能组, 只有 ~70 砖能生成产生式.
/// 新版本遍历所有砖, 用 deriveFunctionLabels 从 brick.chords 动态推导功能标签序列,
/// 每砖生成一组产生式(result=砖名, body=功能标签序列).
/// 性能优化: 按 (left,right) 去重, 取第一个 result. 原因: dp 单值+严格<才更新,
/// 30+ 条 body 相同的产生式(cost 都是 weight=5/10)本就只有第一个遍历到的胜出,
/// 去重是无损等价优化. 预期产生式 1108 → ~100-150.
func generateProductions(from bricks: [BrickLibrary.BrickTemplate], pocOnly: Bool = true) -> [BinaryProduction] {
    var productions: [BinaryProduction] = []
    var successCount = 0
    var skipCount = 0
    // 性能优化: 按 (left,right) 去重, 记录已见过的 body key
    var seenBody = Set<String>()

    // === 问题5: brick-type cost 差异化 weight ===
    /// 根据砖的 type 计算产生式 weight
    /// - Parameters:
    ///   - brickType: 砖类型名 (Cadence/Approach/...)
    ///   - isFinal: 是否最终产生式 (result=砖名) true=最终, false=中间节点
    /// - Returns: weight 值
    /// 缩放: 最终 weight = cost / 5, 中间 weight = cost / 10
    /// brick-type cost 全是 5 的倍数 (10/20/25/30/.../1010), cost/5 整除无精度丢失
    /// 找不到 type 时用默认值 (最终=10, 中间=5), 与修改前一致
    /// 注意: Invisible 砖 (cost=2000) 当前不加入最终库 (阶段2已过滤), 此分支为死代码;
    ///       若未来阶段3重新引入 Invisible, weight=400 会自然排除 (与原版一致)
    func brickWeight(for brickType: String, isFinal: Bool) -> Int {
        if let cost = BrickLibrary.brickTypeCosts[brickType], cost > 0 {
            return isFinal ? max(1, cost / 5) : max(1, cost / 10)
        }
        return isFinal ? 10 : 5  // 默认值 (硬编码砖或 type 为空)
    }

    // === 问题3: keyDiff 计算所需的映射表和辅助函数 ===
    /// 功能标签 → 相对根音 PC（以 I=0 为基准），用于计算产生式 keyDiff
    /// 覆盖 computeLabel 所有可能输出 + defaultSubstitutions 所有 brickName
    let labelToPC: [String: Int] = [
        // 基础 degree（computeLabel default 输出）
        "I": 0, "i": 0,       // i = minor tonic（defaultSubstitutions 特有）
        "bII": 1, "ii": 2, "bIII": 3, "iii": 4,
        "IV": 5, "bV": 6, "V": 7, "bVI": 8, "vi": 9,
        "bVII": 10, "vii": 11,
        // halfDiminished（computeLabel 用 ø 输出，U+00F8）
        "iiø": 2, "iiiø": 4, "ivø": 5, "viø": 9, "viiø": 11,
        // diminished（defaultSubstitutions 用 °/o 输出，保留映射）
        "vii°": 11, "viio": 11,
        // 特殊功能标签
        "bII7": 1,     // 三全音替代属七，根音同 bII
        "bvi": 8,      // 降六级小和弦，根音同 bVI
    ]

    /// 从功能标签名解析相对根音 PC
    /// 优先查 labelToPC 映射表；查不到时，若标签以 ø 结尾则去后缀后再查（自动覆盖所有 Xø 变体）
    /// 无法解析返回 nil（keyDiff=nil，安全降级跳过校验）
    func labelPC(_ name: String) -> Int? {
        if let pc = labelToPC[name] { return pc }
        // 去 ø 后缀后查基础 degree（自动覆盖 iiiø/ivø/viø/viiø/Iø/bIIø 等所有变体）
        if name.hasSuffix("ø") {
            let base = String(name.dropLast())
            return labelToPC[base]
        }
        return nil
    }

    /// 从产生式 left 名（可能是中间节点名如 "ii_V"）解析最后一个功能标签的 PC
    /// 中间节点命名规则: label0_label1_label2...，最后一个 _ 后的部分是最终标签
    /// 注意: 当前标签不含 "_", 若未来标签含 "_" 需改解析方式
    func lastLabelPC(of name: String) -> Int? {
        if let pc = labelPC(name) { return pc }  // 直接是功能标签
        // 中间节点名: 取最后一个 _ 后的部分
        if let lastUnderscore = name.lastIndex(of: "_") {
            let suffix = String(name[name.index(after: lastUnderscore)...])
            return labelPC(suffix)
        }
        return nil
    }

    /// 计算 keyDiff: (rightPC - leftPC + 12) % 12，无法解析则 nil
    func calcKeyDiff(leftName: String, rightName: String) -> Int? {
        guard let lPC = lastLabelPC(of: leftName),
              let rPC = lastLabelPC(of: rightName) else { return nil }
        return (rPC - lPC + 12) % 12
    }

    for brick in bricks {
        // 从 brick.chords 动态推导功能标签序列 (mode无关, 与 computeLabel 恒一致)
        let labels = BrickLibrary.BrickTemplate.deriveFunctionLabels(
            from: brick.chords, referenceKey: brick.referenceKey)
        let n = labels.count
        guard n >= 2 else { skipCount += 1; continue }
        // 解析失败的和弦返回 "?", 跳过该砖
        guard !labels.contains("?") else { skipCount += 1; continue }

        successCount += 1

        if n == 2 {
            // 2 个标签: 直接生成一条产生式, result = 砖名
            let bodyKey = "\(labels[0])|\(labels[1])"
            guard !seenBody.contains(bodyKey) else { continue }
            seenBody.insert(bodyKey)
            let kd = calcKeyDiff(leftName: labels[0], rightName: labels[1])
            let w = brickWeight(for: brick.type, isFinal: true)  // 问题5: brick-type cost 差异化
            productions.append(BinaryProduction(
                left: labels[0], right: labels[1],
                result: brick.name, weight: w, keyDiff: kd))
        } else {
            // n>2 个标签: 生成中间节点链, 最终 result = 砖名
            // 中间节点命名: label0_label1, label0_label1_label2, ...
            // 修复: 中间产生式用 (body, result) 去重而非 body 去重
            //   因为中间节点名(如 iiø_V)是唯一的, 被后续产生式引用, 不能因 body 相同就跳过
            //   n=2 最终产生式仍用 body 去重 (dp 单值取第一个, 性能优化)
            var curName = "\(labels[0])_\(labels[1])"
            let key0 = "\(labels[0])|\(labels[1])|\(curName)"  // 含 result
            if !seenBody.contains(key0) {
                seenBody.insert(key0)
                let kd0 = calcKeyDiff(leftName: labels[0], rightName: labels[1])
                let w0 = brickWeight(for: brick.type, isFinal: false)  // 问题5: 中间产生式
                productions.append(BinaryProduction(
                    left: labels[0], right: labels[1],
                    result: curName, weight: w0, keyDiff: kd0))
            }
            for i in 2..<n-1 {
                let prevName = curName
                curName = prevName + "_\(labels[i])"
                let bodyKey = "\(prevName)|\(labels[i])|\(curName)"  // 含 result
                guard !seenBody.contains(bodyKey) else { continue }
                seenBody.insert(bodyKey)
                let kd = calcKeyDiff(leftName: prevName, rightName: labels[i])
                let w = brickWeight(for: brick.type, isFinal: false)  // 问题5: 中间产生式
                productions.append(BinaryProduction(
                    left: prevName, right: labels[i],
                    result: curName, weight: w, keyDiff: kd))
            }
            // 最终: 砖名 ← curName, labels[n-1]
            let finalKey = "\(curName)|\(labels[n-1])|\(brick.name)"  // 含 result
            guard !seenBody.contains(finalKey) else { continue }
            seenBody.insert(finalKey)
            let kdFinal = calcKeyDiff(leftName: curName, rightName: labels[n-1])
            let wFinal = brickWeight(for: brick.type, isFinal: true)  // 问题5: 最终产生式
            productions.append(BinaryProduction(
                left: curName, right: labels[n-1],
                result: brick.name, weight: wFinal, keyDiff: kdFinal))
        }
    }

    #if DEBUG
    dprint("[4.2-PRODUCTIONS] P0-问题1+性能优化: 遍历 \(bricks.count) 砖, 成功 \(successCount), 跳过 \(skipCount), 去重后生成 \(productions.count) 产生式")
    #endif

    // Fallback: 如果所有砖都推导失败(极端情况), 回退到硬编码 functionGroupBlocks
    if productions.isEmpty {
        #if DEBUG
        dprint("[4.2-PRODUCTIONS] ⚠️ 所有砖推导失败, 回退到硬编码 functionGroupBlocks")
        #endif
        for (group, blocks) in BrickLibrary.BrickTemplate.functionGroupBlocks {
            let n = blocks.count
            guard n >= 2 else { continue }
            if n == 2 {
                productions.append(BinaryProduction(
                    left: blocks[0], right: blocks[1],
                    result: group, weight: 10, keyDiff: nil))
            } else {
                var curName = "\(blocks[0])_\(blocks[1])"
                productions.append(BinaryProduction(
                    left: blocks[0], right: blocks[1],
                    result: curName, weight: 5, keyDiff: nil))
                for i in 2..<n-1 {
                    let prevName = curName
                    curName = prevName + "_\(blocks[i])"
                    productions.append(BinaryProduction(
                        left: prevName, right: blocks[i],
                        result: curName, weight: 5, keyDiff: nil))
                }
                productions.append(BinaryProduction(
                    left: curName, right: blocks[n-1],
                    result: group, weight: 10, keyDiff: nil))
            }
        }
    }

    return productions
}


