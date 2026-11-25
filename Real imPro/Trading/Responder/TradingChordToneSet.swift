//
//  TradingChordToneSet.swift
//  Real imPro
//
//  M2-7 H1: 用生产 ChordQuality 实现 TradingResponder 的 toneSet 闭包。
//  [M2-9] spell 用 chordIntervals，color 用 javaFullColorIntervals（纯 My.voc，对齐 Java getColor）；
//  major7 不含自然11（属七/minor7 不变）。不读全局 activePalette。
//  数据源层已 headless 对拍：A7/D7/E7 的 spell/color 与 Java 逐位一致。
//

import Foundation

enum TradingChordToneSet {

    /// 由和弦名返回其音集合（spell 和弦音 ∪ color 色彩音）。
    static func toneSet(chordName: String) -> TradingToneSet {
        let rootPC = GrammarNoteConverter.getRootPC(chordName)
        let quality = ChordQuality(chordName: chordName)

        let spellIntervals = quality.chordIntervals
        // [M2-9] color 用纯 My.voc（javaFull），对齐 Java getColor；major7 不含自然11（属七/minor7 不变）
        let colorIntervals = quality.javaFullColorIntervals(for: chordName)

        let spellPC = Set(spellIntervals.map { (rootPC + $0) % 12 })
        let colorPC = Set(colorIntervals.map { (rootPC + $0) % 12 })

        return TradingToneSet(rootPC: rootPC, spellPC: spellPC, colorPC: colorPC)
    }
}
