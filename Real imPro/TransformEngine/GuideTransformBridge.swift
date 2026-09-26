// =====================================================================
// GuideTransformBridge.swift
// [T2] ② Guide Tone & Transform 薄桥：把引导音线（[PhysicalNote] + 和弦块）转成
//   TransformEngine 的 NoteChordPair，复用【同一套】Java 对齐通用内核加花，再转回
//   PhysicalNote 并走 guide 专用 spell-only 整流（GrammarLickGlue.rectifyGuideSpellOnly）。
//
// 设计：本文件只做"模型互转 + 调内核 + 整流"，不含任何替换算法（算法全在 JavaAlignedTransformEngine，
//   与 grammar&Transform 共用，保证两条链路逐音同源）。仅当 UI 点亮 Transform 时由 worker 调用；
//   不点亮时 08 单线原样输出、不经过本桥。
// =====================================================================

import Foundation

enum GuideTransformBridge {

    /// 对一条引导音线施加选定乐手的变换加花。
    /// - Parameters:
    ///   - notes: 引导音线（08 单线产物，含 NC 休止，slot 累计守恒）
    ///   - chordBlocks: 与生成时同一 roadmap 的和弦块（duration 单位=拍）
    ///   - musician: 乐手表 id（TransformTables/<id>.tsv），缺失由 Registry 回退 My
    ///   - mode: 选择策略，生产 .randomized（真洗牌），对拍可传 .deterministic / 固定种子
    ///   - slotsPerBeat: 每拍 slot（120）
    ///   - rectifyColorMode: [Guide Color 圆点 20260914] guide 整流色彩三态。.off（默认）=spell-only，
    ///     对齐 Java 出厂 colorBox 不勾；.conservative=spell+自然9/11/13；.full=spell+全 color，
    ///     对齐 Java colorBox 勾选（已逐音 diff=0）。grammar 不接此档。
    ///   - onTableMiss: G1 整流词表未命中回调（统计用，可空）
    static func apply(_ notes: [PhysicalNote],
                      chordBlocks: [ChordBlock],
                      musician: String = TransformMusicianRegistry.defaultMusician,
                      mode: TransformRandomMode = .randomized(SystemTransformRNG()),
                      slotsPerBeat: Int = 120,
                      rectifyColorMode: GuideRectifyColorMode = .off,
                      onTableMiss: ((String) -> Void)? = nil) -> [PhysicalNote] {
        guard !notes.isEmpty else { return notes }

        // 1) 和弦时间线（起始 slot），用于给每个音找当前和弦
        var timeline: [(start: Int, chord: ChordBlock)] = []
        var cAccum = 0
        for cb in chordBlocks {
            timeline.append((cAccum, cb))
            cAccum += Int(Double(cb.duration) * Double(slotsPerBeat))
        }
        func chordAt(_ slot: Int) -> ChordBlock {
            var cur = timeline.first?.chord ?? ChordBlock(name: "NC", duration: 0)
            for e in timeline where slot >= e.start { cur = e.chord }
            return cur
        }

        // 2) PhysicalNote -> NoteChordPair（累计 slot，休止 pitch=-1 原样保留）
        var ncps: [TransformEngine.NoteChordPair] = []
        var slot = 0
        for n in notes {
            ncps.append(TransformEngine.NoteChordPair(note: n, chord: chordAt(slot), slot: slot))
            slot += n.durationSlots
        }

        // 3) 同一套 Java 对齐内核（与 grammar&Transform 共用），乐手表缺失回退 My
        let table = TransformMusicianRegistry.tableWithFallback(musician) ?? []
        let transformed = TransformEngine.JavaAlignedTransformEngine.apply(to: ncps, table: table, mode: mode)

        // 4) NoteChordPair -> PhysicalNote
        let phys = transformed.map {
            PhysicalNote(midiPitch: $0.note.midiPitch,
                         durationSlots: $0.note.durationSlots,
                         tuplet: $0.note.tuplet,
                         terminalType: $0.note.terminalType)
        }

        // 5) guide 专用整流（grammar 的 rectifyAllBeats 不被调用、不受影响）：
        //    .off→spell-only（出厂默认）；.conservative→spell+保守色；.full→spell+全 color
        return LightPostProcessor.rectifyGuideSpellOnly(phys,
                                                     chordBlocks: chordBlocks,
                                                     slotsPerBeat: slotsPerBeat,
                                                     colorMode: rectifyColorMode,
                                                     onTableMiss: onTableMiss)
    }
}
