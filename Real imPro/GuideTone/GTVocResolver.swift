//
//  GTVocResolver.swift — 引导音线「和弦词汇表」运行时解析（对应 Java Chord/Advisor 取词路径）
//
//  纯函数、无状态、不抛错。流程：认和弦名 -> 去斜杠低音 -> 别名归一 -> 等音根 ->
//  按根转调 -> 输出「候选音集合 / 优先级序 / 和弦族(family)」。
//  表数据见 GuideToneVocabularyTable.swift（由原版词库经 Java 金标准离线导出，全量 114 型）。
//  设计依据（Java GuideLineGenerator / NoteConverter）：
//   - chordTones() = getSpell()，allowColor 时追加 getColor()；
//   - priorityScore() 单独遍历 getPriority()，与候选集合解耦；
//   - firstNote 按 family 音阶数组取度数偏移，且该音必须属于候选集，否则取 priority 首元素。
//
import Foundation

// MARK: - [Guide Color 圆点 20260914] guide&Transform 整流色彩三态（仅整流用）
// 单线 GuideLineGenerator 仍用其 Bool allowColor（true==.full / false==.off，逐音等价）。
//   off          = spell-only，几乎只和弦音（对齐 Java 出厂 colorBox 不勾）
//   conservative = spell + 保守色彩（自然 9/11/13；与 grammar conservativeColorIntervals 同源，
//                  符号里显式标注的 b9/#9 等构成音按 grammar 定义保留，不另写第二套过滤）
//   full         = spell + 全量 color（对齐 Java 勾选 colorBox）
enum GuideRectifyColorMode { case off, conservative, full }

/// 一次解析的结果（音高类 pitch-class，0-11；调用方按需提升八度）
struct GTResolved {
    let rootPC: Int
    let candidatePCs: [Int]   // spell 序；allowColor 时追加 color 序（对应 Java chordTones()）
    let priorityPCs: [Int]    // priority 序（对应 Java getPriority()，bestNote 平局排序用）
    let family: String
}

enum GTVocResolver {
    // 全量等音根音表（含 #/b 与 B#/Cb/Fb/E# 极端等音）。
    // 旧 parseRootPitchClass 仅 12 键、缺 D#/A#，会漏算 D#m7 这类等音根（已在对拍中定位）。
    static let rootMap: [String: Int] = [
        "C":0,"B#":0,"C#":1,"Db":1,"D":2,"D#":3,"Eb":3,"Fb":3,
        "E":4,"F":5,"E#":5,"F#":6,"Gb":6,"G":7,
        "G#":8,"Ab":8,"A":9,"A#":10,"Bb":10,"Cb":11,"B":11
    ]

    // 各 family「音阶度数 -> 距根半音」（来自 NoteConverter 七个 *ScaleDegrees；引导音只取 1/3/5/7）
    static func degreeOffset(_ degree: String, _ family: String) -> Int? {
        let m: [String: [String: Int]] = [
            "minor":           ["1":0,"3":3,"5":7,"7":11],
            "minor7":          ["1":0,"3":3,"5":7,"7":10],
            "major":           ["1":0,"3":4,"5":7,"7":11],
            "dominant":        ["1":0,"3":4,"5":7,"7":10],
            "sus4":            ["1":0,"3":4,"5":7,"7":10],
            "alt":             ["1":0,"3":4,"5":7,"7":10],
            "half-diminished": ["1":0,"3":3,"5":6,"7":10],
            "diminished":      ["1":0,"3":3,"5":7,"7":9],
            "augmented":       ["1":0,"3":4,"5":8,"7":11]
        ]
        return m[family]?[degree]
    }

    /// 拆分「根 + 质量形」。优先匹配两字符变音根（C#/Db/...），否则取单字母根。
    static func splitRoot(_ name: String) -> (Int, String) {
        let a = Array(name)
        if a.count >= 2 {
            let two = String(a[0...1])
            if let p = rootMap[two] { return (p, String(a[2...])) }
        }
        let one = a.isEmpty ? "C" : String(a[0])
        return (rootMap[one] ?? 0, String(a.dropFirst()))
    }

    /// 别名链：质量形 -> 规范质量形（键值都已去首字母 C，全程在「质量形空间」迭代，带环保护）
    static func canonicalQuality(_ quality: String) -> String {
        var q = quality
        var seen = Set<String>()
        while let t = GuideToneVocabularyTable.alias[q], !seen.contains(q) {
            seen.insert(q)
            q = t
        }
        return q
    }

    // [Guide Color 圆点 20260914] 旧布尔入口【保留为委托，不删】：单线生成器 GuideLineGenerator
    // 三处仍调它；true==.full、false==.off，与改造前逐音等价（18470 音回归保证）。
    static func resolve(name raw: String, allowColor: Bool) -> GTResolved? {
        resolve(name: raw, colorMode: allowColor ? .full : .off)
    }

    /// 三态主入口。
    /// - NC 返回空候选（调用方按整段休止处理）；
    /// - 斜杠低音只取斜杠前的和弦质量（GuideTone 忽略 /bass）；
    /// - 查不到表返回 nil，由调用方回退族级规则并计数，保证不崩、不静默。
    /// - off=spell-only；full=spell+全量 color（等价旧 allowColor=true）；
    ///   conservative=spell+「距根音程 ∩ grammar 同源保守集」的 color 子集。
    static func resolve(name raw: String, colorMode: GuideRectifyColorMode) -> GTResolved? {
        if raw == "NC" {
            return GTResolved(rootPC: 0, candidatePCs: [], priorityPCs: [], family: "NC")
        }
        let noSlash = raw.split(separator: "/", maxSplits: 1).first.map(String.init) ?? raw
        let (root, quality) = splitRoot(noSlash)
        var q = quality
        if GuideToneVocabularyTable.table["C" + q] == nil {
            q = canonicalQuality(q)
        }
        guard let e = GuideToneVocabularyTable.table["C" + q] else { return nil }
        // 以 C 根存储的模板按当前根整体转调（模 12）
        let sp = e.spell.map { ($0 + root) % 12 }
        let pr = e.priority.map { ($0 + root) % 12 }

        // 选哪些 color【音程】：e.color 存的就是距根半音音程(0-11)，在转调前过滤最直接
        var colorIntervals = e.color
        switch colorMode {
        case .off:
            colorIntervals = []
        case .full:
            break // 全量 color，等价旧 allowColor=true
        case .conservative:
            // 复用 grammar 同源判定（不另写第二套）：普通和弦=自然 9/11/13；
            // 符号里显式标注的 b9/#9 等构成音按 grammar conservative 定义保留（用户已拍板推荐口径）
            let keep = Set(ChordQuality(chordName: noSlash).colorIntervals(for: noSlash, palette: .conservative))
            let before = colorIntervals.count
            colorIntervals = colorIntervals.filter { keep.contains($0) }
            #if DEBUG
            if before > 0 && colorIntervals.isEmpty {
                dprint("🎨 [GuideColor] \(noSlash) 保守档过滤后无色彩音（退化为 spell-only），原 color=\(e.color)")
            }
            #endif
        }
        let co = colorIntervals.map { ($0 + root) % 12 }
        let cand = sp + co
        return GTResolved(rootPC: root, candidatePCs: cand, priorityPCs: pr, family: e.family)
    }
}
