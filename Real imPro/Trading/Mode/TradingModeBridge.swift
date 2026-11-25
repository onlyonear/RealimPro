//
//  TradingModeBridge.swift
//  Real imPro
//
//  M2-9: Trading 新模式（Modify / Use Grammar / Use Transform）数据结构转换桥。
//  负责 TradingSlotNote ↔ PhysicalNote / MelodyPart / NoteChordPair，
//  以及 TradingChordBlock → ChordBlock / JazzRoadmap / chordTimeline。
//
//  纯转换（仅 Foundation），不含任何算法；所有转换保证总时值守恒。
//  本文件不 import AVFoundation / UIKit / SwiftUI，可 headless 对拍。
//

import Foundation

enum TradingModeBridge {

    // MARK: - TradingSlotNote → MelodyPart

    /// [TradingSlotNote] → MelodyPart（PhysicalNote 按 durationSlots 自动识别三连/五连）。
    static func melodyPart(from slotNotes: [TradingSlotNote]) -> MelodyPart {
        let phys = slotNotes.map { sn -> PhysicalNote in
            PhysicalNote(midiPitch: sn.isRest ? -1 : sn.pitch,
                         durationSlots: sn.durationSlots)
        }
        return MelodyPart(phys)
    }

    // MARK: - MelodyPart → TradingSlotNote

    /// MelodyPart → [TradingSlotNote]（按 notes 顺序重新累积 startSlot，休止 pitch=-1）。
    static func slotNotes(from melody: MelodyPart) -> [TradingSlotNote] {
        return slotNotes(from: melody.notes)
    }

    /// [PhysicalNote] → [TradingSlotNote]（按顺序重新累积 startSlot）。
    /// - Parameter totalSlots: 非 nil 时，不足补休止、超出截断（Grammar 出口用，保证铺满一轮）。
    static func slotNotes(from physicalNotes: [PhysicalNote], totalSlots: Int? = nil) -> [TradingSlotNote] {
        var result: [TradingSlotNote] = []
        var cursor = 0
        for pn in physicalNotes {
            let start = cursor
            cursor += pn.durationSlots
            // 若已设 totalSlots 且该音超出，截断到 totalSlots
            if let total = totalSlots, start >= total {
                // 音头已在 total 之后，不加入
                continue
            }
            var dur = pn.durationSlots
            if let total = totalSlots, start + dur > total {
                dur = total - start
                assert(false, "PhysicalNote 延音超出 totalSlots，已截断（应在生成时铺满）")
            }
            result.append(TradingSlotNote(
                pitch: pn.isRest ? -1 : pn.midiPitch,
                startSlot: start,
                durationSlots: dur,
                isRest: pn.isRest))
        }
        // 不足 totalSlots 补休止
        if let total = totalSlots, cursor < total {
            result.append(TradingSlotNote(pitch: -1, startSlot: cursor,
                                         durationSlots: total - cursor, isRest: true))
        }
        if let total = totalSlots {
            assert(result.reduce(0) { $0 + $1.durationSlots } == total,
                   "slotNotes 未铺满 totalSlots=\(total)")
        }
        return result
    }

    // MARK: - TradingChordBlock → ChordBlock / Roadmap / Timeline

    /// [TradingChordBlock] → [ChordBlock]（duration 单位换算：slot → 拍，120 slot=1 拍）。
    static func chordBlocks(from tradingBlocks: [TradingChordBlock]) -> [ChordBlock] {
        return tradingBlocks.map { tb in
            ChordBlock(name: tb.name,
                       duration: Double(tb.durationSlots) / Double(JazzGuideToneEngine.slotsPerBeat))
        }
    }

    /// [TradingChordBlock] → JazzRoadmap（4 小节一轮，供 Grammar 生成）。
    static func roadmap(from tradingBlocks: [TradingChordBlock],
                        title: String = "Trading Turn",
                        tempo: Int = 120) -> JazzRoadmap {
        let rm = JazzRoadmap(title: title, tempo: tempo)
        for cb in chordBlocks(from: tradingBlocks) {
            rm.append(block: cb)
        }
        return rm
    }

    /// [TradingChordBlock] → chordTimeline（start 直接用 TradingChordBlock.startSlot，
    /// 精确对齐换和弦边界，供 Transform 内核 chordAt）。
    static func chordTimeline(from tradingBlocks: [TradingChordBlock]) -> [(start: Int, chord: ChordBlock)] {
        let cbs = chordBlocks(from: tradingBlocks)
        return zip(tradingBlocks, cbs).map { (tb, cb) in
            (start: tb.startSlot, chord: cb)
        }
    }

    // MARK: - TradingSlotNote ↔ NoteChordPair（Transform 用）

    /// [TradingSlotNote] → [NoteChordPair]（chord 按 startSlot 从 chordTimeline 精确查找）。
    static func ncps(from slotNotes: [TradingSlotNote],
                     chordTimeline: [(start: Int, chord: ChordBlock)]) -> [TransformEngine.NoteChordPair] {
        return slotNotes.map { sn in
            let chord = chordAt(sn.startSlot, in: chordTimeline)
            let pn = PhysicalNote(midiPitch: sn.isRest ? -1 : sn.pitch,
                                  durationSlots: sn.durationSlots)
            return TransformEngine.NoteChordPair(note: pn, chord: chord, slot: sn.startSlot)
        }
    }

    /// [NoteChordPair] → [TradingSlotNote]（用 NCP 的 slot 作为 startSlot，保留内核产出的位置）。
    static func slotNotes(from ncps: [TransformEngine.NoteChordPair]) -> [TradingSlotNote] {
        return ncps.map { ncp in
            TradingSlotNote(pitch: ncp.note.isRest ? -1 : ncp.note.midiPitch,
                            startSlot: ncp.slot,
                            durationSlots: ncp.note.durationSlots,
                            isRest: ncp.note.isRest)
        }
    }

    // MARK: - chordAt（按 startSlot 查找，线性；和弦数少）

    /// 找包含 slot 的和弦（最后一个 start <= slot 的块）；空 timeline 回退 NC。
    static func chordAt(_ slot: Int,
                        in timeline: [(start: Int, chord: ChordBlock)]) -> ChordBlock {
        guard let first = timeline.first else {
            return ChordBlock(name: "NC", duration: 0)
        }
        var cur = first.chord
        for e in timeline where slot >= e.start {
            cur = e.chord
        }
        return cur
    }
}
