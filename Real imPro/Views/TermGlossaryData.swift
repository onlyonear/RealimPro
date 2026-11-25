// =====================================================================
// TermGlossaryData.swift
// Key Section 术语词典的唯一数据源（文案与界面代码分离，便于后续本地化）。
// 三层结构：
//   A. familyEntries   —— 19 种功能家族的通俗解释
//   B. specificEntries —— 高频/截图里实际出现的具体砖名专门解释
//   C. lookup(_:)      —— 具体名查不到时，按关键词回退到家族，保证 100% 有解释
// 全英文、面向音乐爱好者，无代码术语。
// 说明：除能从砖块真实和弦构成确认的内容外，其余为基于和声功能的通俗解释，
// 并非 App 官方词条。
// =====================================================================
import Foundation

struct TermEntry: Identifiable, Equatable {
    let id = UUID()
    let term: String            // 匹配键（原始完整砖名，或家族名）
    let title: String           // 显示标题
    let summary: String         // 通俗解释
    let example: String?        // 可选：最简化和弦走向例子
    let isFamily: Bool

    static func == (lhs: TermEntry, rhs: TermEntry) -> Bool { lhs.term == rhs.term }
}

enum TermGlossaryData {

    // MARK: - A. 功能家族条目
    static let familyEntries: [TermEntry] = [
        TermEntry(term: "Cadence", title: "Cadence",
                  summary: "A cadence is a resting point in the harmony, like the punctuation at the end of a sentence. It brings a phrase to a close and gives a clear sense of arrival.",
                  example: nil, isFamily: true),
        TermEntry(term: "Approach", title: "Approach",
                  summary: "An approach is a short run of chords that leads smoothly into a target chord — the way you walk up to a door before opening it. It builds a gentle path into the next harmony.",
                  example: nil, isFamily: true),
        TermEntry(term: "Launcher", title: "Launcher",
                  summary: "A launcher sits at the end of a section and launches the music into the next one. Instead of coming to rest, it builds forward momentum that carries the band across the boundary.",
                  example: nil, isFamily: true),
        TermEntry(term: "Slow Launcher", title: "Slow Launcher",
                  summary: "A slow launcher is a longer, two-step launcher (often built from a two-link dominant cycle). It pushes more gently toward the next section while still keeping the music moving forward.",
                  example: nil, isFamily: true),
        TermEntry(term: "Overrun", title: "Overrun",
                  summary: "An overrun spills past the spot where a section would normally end. The harmony carries across the boundary instead of stopping neatly on it.",
                  example: nil, isFamily: true),
        TermEntry(term: "Turnaround", title: "Turnaround",
                  summary: "A turnaround is a short chord loop at the end of a phrase that turns you back around to start again. It is the familiar little sequence that leads back to the top of the form.",
                  example: nil, isFamily: true),
        TermEntry(term: "Dropback", title: "Dropback",
                  summary: "A dropback steps backward through the harmony, often sliding down chromatically, to set up a fresh arrival — like stepping back in order to take a running start.",
                  example: nil, isFamily: true),
        TermEntry(term: "Pullback", title: "Pullback",
                  summary: "A pullback holds back the expected resolution and keeps the tension a little longer before letting the chord land. It is a form of approach with a delayed payoff.",
                  example: nil, isFamily: true),
        TermEntry(term: "Deceptive-Cadence", title: "Deceptive Cadence",
                  summary: "A deceptive cadence sets up as if it will land on the home chord, then resolves somewhere unexpected. It is a gentle musical surprise that postpones the real ending.",
                  example: nil, isFamily: true),
        TermEntry(term: "CESH", title: "CESH",
                  summary: "CESH keeps the underlying chord the same while the inner lines move through it. The harmony stays put, but the moving voices give it a sense of motion rather than a static hold.",
                  example: nil, isFamily: true),
        TermEntry(term: "On-Off", title: "On-Off",
                  summary: "On-Off starts on the current chord, then moves off it to visit a contrasting chord before the phrase resolves. It is a short excursion away from the home harmony.",
                  example: nil, isFamily: true),
        TermEntry(term: "Off-On", title: "Off-On",
                  summary: "Off-On begins away from the home chord and then returns to it, so the phrase lands back on familiar ground after starting elsewhere.",
                  example: nil, isFamily: true),
        TermEntry(term: "On-Off+", title: "On-Off+",
                  summary: "On-Off+ is a longer on-off excursion: it leaves the home chord, stays away through a slightly extended path, and then comes back.",
                  example: nil, isFamily: true),
        TermEntry(term: "On", title: "On",
                  summary: "An \"On\" brick simply stays resting on one chord — the music stays on that harmony rather than moving away.",
                  example: nil, isFamily: true),
        TermEntry(term: "Dominant-Cycle", title: "Dominant Cycle",
                  summary: "A dominant cycle is a chain of dominant seventh chords, each pulling strongly to the next around the cycle of fifths. The tension keeps rolling forward until it reaches the target.",
                  example: nil, isFamily: true),
        TermEntry(term: "Opening", title: "Opening",
                  summary: "An opening brick sets up the very start of a tune, establishing the key and mood before the main melody gets under way.",
                  example: nil, isFamily: true),
        TermEntry(term: "Ending", title: "Ending",
                  summary: "An ending brick brings the tune to its final close, often with a distinctive last phrase that signals the music is finishing.",
                  example: nil, isFamily: true),
        TermEntry(term: "Invisible", title: "Invisible",
                  summary: "Invisible bricks are internal building blocks used to construct other bricks. They do not normally appear as labels on the analysis.",
                  example: nil, isFamily: true),
        TermEntry(term: "Misc", title: "Misc",
                  summary: "A general family for bricks that do not fit one of the standard functional categories.",
                  example: nil, isFamily: true)
    ]

    // MARK: - B. 高频具体砖名专门条目
    static let specificEntries: [TermEntry] = [
        TermEntry(term: "Perfect-Cadence", title: "Perfect Cadence",
                  summary: "The most decisive, final-sounding cadence. The dominant seventh chord resolves straight to the home chord, giving a clean sense of completion.",
                  example: "G7 → C", isFamily: false),
        TermEntry(term: "Straight-Cadence", title: "Straight Cadence",
                  summary: "A direct, no-detour close: a two-measure straight approach leads directly into the home chord. On the score it is shortened to Straight-Cad.",
                  example: "Straight approach (2 bars) → C", isFamily: false),
        TermEntry(term: "Extended-Cadence", title: "Extended Cadence",
                  summary: "A longer build-up before the close: a three-measure extended approach paves the way, then the home chord finally arrives.",
                  example: "Extended approach (3 bars) → C", isFamily: false),
        TermEntry(term: "Tension-Cadence", title: "Tension Cadence",
                  summary: "A cadence that keeps the tension high right up to the resolution, so the arrival feels more strongly earned.",
                  example: nil, isFamily: false),
        TermEntry(term: "Straight-Approach", title: "Straight Approach",
                  summary: "A two-measure approach that moves directly into its target chord without taking a detour.",
                  example: nil, isFamily: false),
        TermEntry(term: "Extended-Approach", title: "Extended Approach",
                  summary: "A three-measure approach that takes a longer, more winding path before reaching the target chord. On the score it is shortened to Ext-Approach.",
                  example: nil, isFamily: false),
        TermEntry(term: "Major-On", title: "Major On",
                  summary: "A single major home chord held in place — the music stays resting on that major chord rather than moving away. The word \"On\" means staying on top of that harmony.",
                  example: "C", isFamily: false),
        TermEntry(term: "Dominant-Cycle", title: "Dominant Cycle",
                  summary: "A chain of dominant seventh chords moving around the cycle of fifths, each one pulling to the next. On the score it is shortened to Dom-Cycle.",
                  example: nil, isFamily: false),
        TermEntry(term: "Dominant-Cycle-2-Steps", title: "Dominant Cycle (2 steps)",
                  summary: "A two-link dominant cycle: two dominant seventh chords in a row before the target. On the score it is shortened to Dom-Cyc-2.",
                  example: nil, isFamily: false),
        TermEntry(term: "Reverse-Dominant-Cycle-2-Steps", title: "Reverse Dominant Cycle (2 steps)",
                  summary: "A two-link cycle that runs in the reverse direction. On the score it is shortened to Rev-Dom-Cyc-2.",
                  example: nil, isFamily: false),
        TermEntry(term: "Launcher", title: "Launcher",
                  summary: "Marked at the end of a section to launch the music into the next one. This label is assigned during analysis rather than stored in the dictionary.",
                  example: nil, isFamily: false),
        TermEntry(term: "Slow Launcher", title: "Slow Launcher",
                  summary: "A gentler, two-step launcher built from a two-link dominant cycle, pushing the music forward into the next section.",
                  example: nil, isFamily: false),
        TermEntry(term: "Dogleg Slow Launcher", title: "Dogleg Slow Launcher",
                  summary: "A slow launcher that bends (a \"dogleg\") rather than running straight, adding a little sideways turn before the next section.",
                  example: nil, isFamily: false),
        TermEntry(term: "Rainbow-Overrun", title: "Rainbow Overrun",
                  summary: "An overrun brick: the harmony spills past the normal section boundary instead of stopping on it.",
                  example: nil, isFamily: false),
        TermEntry(term: "Extended-Cadence-+-Overrun", title: "Extended Cadence + Overrun",
                  summary: "Two ideas combined: an extended cadence builds the long close, and the overrun carries it past the expected boundary. The \"+\" means the two functions are joined.",
                  example: nil, isFamily: false),
        TermEntry(term: "Tension-Cadence-+-Overrun", title: "Tension Cadence + Overrun",
                  summary: "A tension-building cadence that also spills across the boundary. On the score it is shortened to Tens-Cad+Ovr.",
                  example: nil, isFamily: false),
        TermEntry(term: "Sad-Cadence-with-Overrun", title: "Sad Cadence with Overrun",
                  summary: "A minor-leaning, softer cadence combined with an overrun that carries the harmony past the boundary.",
                  example: nil, isFamily: false),
        TermEntry(term: "To-IV-n-Bird-SPOT", title: "To IV (Bird)",
                  summary: "A move toward the fourth chord (IV) in the \"Bird\" style — a classic bebob deceptive move. On the score it is shortened to To-IV-Bird.",
                  example: nil, isFamily: false)
    ]

    // MARK: - C. 查找：精确 → 家族关键词回退
    /// 给一个原始完整砖名，返回可展示的词条。具体条目优先，查不到按关键词归家族。
    static func lookup(_ rawName: String) -> TermEntry {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let exact = specificEntries.first(where: { $0.term == name }) {
            return exact
        }

        // 关键词回退（顺序敏感：先特殊组合，再一般家族）
        let familyMap: [(needle: String, key: String)] = [
            ("Dogleg", "Slow Launcher"),
            ("Slow Launcher", "Slow Launcher"),
            ("Launcher", "Launcher"),
            ("Overrun", "Overrun"),
            ("Turnaround", "Turnaround"),
            ("Deceptive", "Deceptive-Cadence"),
            ("Reverse-Dominant-Cycle", "Dominant-Cycle"),
            ("Dominant-Cycle", "Dominant-Cycle"),
            ("Cycle", "Dominant-Cycle"),
            ("Pullback", "Pullback"),
            ("Dropback", "Dropback"),
            ("CESH", "CESH"),
            ("On-Off+", "On-Off+"),
            ("On-Off", "On-Off"),
            ("Off-On", "Off-On"),
            ("Opening", "Opening"),
            ("Ending", "Ending"),
            ("Cadence", "Cadence"),
            ("Cad", "Cadence"),
            ("Approach", "Approach"),
            ("On", "On")
        ]

        for item in familyMap where name.localizedCaseInsensitiveContains(item.needle) {
            if let fam = familyEntries.first(where: { $0.term == item.key }) {
                // 复合词：在家族解释前点出这是按功能归类
                if name.range(of: "+|with|-\\+-", options: .regularExpression) != nil {
                    return TermEntry(term: name, title: name,
                                     summary: "This label combines several harmony functions. At its core: " + fam.summary,
                                     example: fam.example, isFamily: true)
                }
                return fam
            }
        }

        return familyEntries.first(where: { $0.term == "Misc" })!
    }
}
