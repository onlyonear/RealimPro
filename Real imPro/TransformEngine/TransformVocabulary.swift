// =====================================================================
// TransformVocabulary.swift
// ② Guide Tone & Transform（T1，路线 B）专用「和弦词表/七族分类」权威。
//
// 背景：Java Transform 的 Evaluate/LickGen 在算 relative-pitch / note-category /
//   chord-family / transpose-diatonic 时，用的是 My.voc 词库派生的族(family)与
//   spell/color 音集，以及 NoteConverter 的七族固定拼写表。生产既有的
//   ChordBlock.getChordFamily() 是另一套（被 Roadmap/Grammar/BrickLibrary 等 20 处
//   共享的定稿逻辑，且把 m7 并入 minor、半减拼成 halfDiminished），【不得为 Transform
//   改动它】。因此本文件把 T0 对拍验证过的 GoldAuthority 产品化：
//     - family/spell/color 统一复用 GuideTone 已落地的 G1 全量词表
//       (GuideToneVocabularyTable + GTVocResolver，114 型 C 根 + 120 别名 + 按根转调)；
//     - 七族运行时分类 javaFamily 只在 Transform 新内核路径使用；
//     - 词表未命中时回退族级近似并对 missCount 计数（不崩、不静默）。
// 本文件为新增能力，默认仅在 useJavaAlignedTransform 打开的 Transform 链路可达。
// =====================================================================

import Foundation

enum TransformVocabulary {

    /// 诊断计数：note-category 走词表未命中、回退族级的次数（测试/审计可读，不影响结果）
    static var missCount: Int = 0
    static func noteCategoryMiss() { missCount += 1 }

    struct VSets {
        let family: String
        let spell: Set<Int>
        let color: Set<Int>
    }

    /// 复用 G1 全量词表（114 型 + 别名归一 + 按根转调），返回该【具体和弦】的族与 spell/color 绝对 PC。
    /// NC / N.C. 无词表 → nil（由调用方按休止/无和弦处理）。
    static func vocab(_ chordName: String) -> VSets? {
        let n = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
        if n == "NC" || n == "N.C." { return nil }
        // 斜杠低音只取斜杠前（Transform 忽略 /bass）
        let noSlash = n.split(separator: "/", maxSplits: 1).first.map(String.init) ?? n
        let (root, quality) = GTVocResolver.splitRoot(noSlash)
        var q = quality
        if GuideToneVocabularyTable.table["C" + q] == nil {
            q = GTVocResolver.canonicalQuality(q)
        }
        guard let e = GuideToneVocabularyTable.table["C" + q] else { return nil }
        return VSets(family: e.family,
                     spell: Set(e.spell.map { ($0 + root) % 12 }),
                     color: Set(e.color.map { ($0 + root) % 12 }))
    }

    /// Java NoteConverter/LickGen 口径的【运行时七族分类】，对任意和弦名生效。
    /// 区分 minor（旋律小：m/m6）与 minor7（多利亚：m7/m9/m11/m13）；sus4 单独标记，
    /// 正向拼写→dominant、逆向 makeRelative→major，由调用处决定。
    /// 优先取 G1 词表 family；未命中再按质量字符串启发式兜底。
    static func javaFamily(_ chordName: String) -> String {
        if let v = vocab(chordName) {
            // NoteConverter 只认七族；sus4 保留，由调用处决定 dominant/major
            return v.family
        }
        var q = chordName
        // 去根音（首字母 + 可选 b/#）
        let a = Array(q)
        if a.count >= 2 && (a[1] == "b" || a[1] == "#") {
            q = String(a[2...])
        } else if !a.isEmpty {
            q = String(a[1...])
        }
        q = q.lowercased()
        if q.contains("m7b5") || q.contains("ø") || q.contains("h") { return "half-diminished" }
        if q.contains("dim") || q.contains("o7") { return "diminished" }
        if q.contains("aug") || q.contains("+") { return "augmented" }
        if q.hasPrefix("sus") || q.contains("sus") { return "sus4" }
        if q.contains("maj") || q.contains("^") { return "major" }
        if q.hasPrefix("m") {
            if q.contains("7") || q.contains("9") || q.contains("11") || q.contains("13") { return "minor7" }
            return "minor"
        }
        if q.contains("7") || q.contains("9") || q.contains("11") || q.contains("13") { return "dominant" }
        return "major"
    }

    /// Java NoteConverter 七族「半音偏移 0..11 → 相对拼写」固定正向表（T0 对拍验证）。
    static let scales: [String: [String]] = [
        "minor":           ["1", "b2", "2", "3", "#3", "4", "b5", "5", "b6", "6", "b7", "7"],
        "minor7":          ["1", "b2", "2", "3", "#3", "4", "b5", "5", "b6", "6", "7", "#7"],
        "major":           ["1", "b2", "2", "b3", "3", "4", "#4", "5", "#5", "6", "b7", "7"],
        "dominant":        ["1", "b2", "2", "b3", "3", "4", "#4", "5", "#5", "6", "7", "#7"],
        "half-diminished": ["1", "2", "#2", "3", "#3", "4", "5", "#5", "6", "#6", "7", "#7"],
        "diminished":      ["1", "b2", "2", "3", "#3", "4", "b5", "5", "6", "7", "#7", "b8"],
        "augmented":       ["1", "b2", "2", "b3", "3", "4", "#4", "b5", "5", "6", "b7", "7"]
    ]

    /// Java LickGen.makeRelativeNote 八族「自然级 1..7 → 距根半音偏移」逆向表（deg1=0）。
    /// sus4/未列族 → major（调用处兜底）。
    static let makeRelOffset: [String: [Int]] = [
        "major":           [0, 2, 4, 5, 7, 9, 11],
        "minor":           [0, 2, 3, 5, 7, 9, 11],
        "minor7":          [0, 2, 3, 5, 7, 9, 10],
        "dominant":        [0, 2, 4, 5, 7, 9, 10],
        "half-diminished": [0, 2, 3, 5, 7, 9, 10],
        "diminished":      [0, 2, 3, 5, 6, 8, 9],
        "augmented":       [0, 2, 4, 5, 8, 9, 10]
    ]

    /// 供 LightPostProcessor.rectify* 注入的【G1 词表版可用音集】闭包工厂（guide&Transform 专用）。
    /// 合法集合 = spell（+color），按 [minPitch,maxPitch] 在四个八度展开为实际 MIDI，去重保序排序；
    /// 词表未命中（NC/未知和弦）计数并返回空，由调用方决定是否回退族级，保证不崩、不静默。
    static func guideRectifyUsableToneProvider() -> LightPostProcessor.RectifyUsableToneProvider {
        return { chordName, minPitch, maxPitch, includeColor in
            guard let v = vocab(chordName) else { noteCategoryMiss(); return [] }
            var orderedPC: [Int] = []
            var seen = Set<Int>()
            for pc in v.spell where !seen.contains(pc) { seen.insert(pc); orderedPC.append(pc) }
            if includeColor { for pc in v.color where !seen.contains(pc) { seen.insert(pc); orderedPC.append(pc) } }
            var out: [Int] = []
            for pc in orderedPC {
                for oct in [48, 60, 72, 84] {
                    let p = pc + oct
                    if p >= minPitch && p <= maxPitch { out.append(p) }
                }
            }
            return out.sorted()
        }
    }
}
