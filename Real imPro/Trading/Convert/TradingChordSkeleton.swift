import Foundation

//
//  TradingChordSkeleton.swift
//  M2-8 渲染层：为 Trading 累积谱生成「和弦骨架」。
//
//  五线谱上的和弦字母唯一来自 GeneratedMeasure.chordAnnotations（→ SheetMusicView
//  chordLabelAssignJS / drawChordLabel）。而喂给 Trading 的伴奏和弦谱（roadmap）与
//  PhraseToMeasures.convert 的产物都带 chordAnnotations: []（和弦标签本是视图层产物）。
//  本文件纯函数补齐它，规则与现有正常链路 ContentView 逐行一致：
//    · reset 骨架（开始时只有和弦的谱）：按 chordSlots 分段，每段用标准表贪心切成休止符，
//      每段第一个休止符挂该和弦 —— 复刻 ContentView.generateEmptyRoadmap :1130-1186。
//    · overlay 实音（填入真实旋律后）：按音符小节内 slot 推进，把每个和弦挂到「起点 slot
//      ≥ 该和弦 startSlot」的第一个音符（含休止符）—— 复刻 ContentView :1688-1691。
//
//  纯函数、无副作用、不碰四条链路；标准值 token 与 MusicXMLQuantizer.REST_NAME
//  及 ContentView.getExactVexFlowDuration(isRest:) 的标准档输出一致（贪心后 chunk 必为标准值）。
//

enum TradingChordSkeleton {

    /// 休止符贪心分块标准表（逐字搬 ContentView:1154，降序）。
    static let chunkStandards = [480, 360, 240, 180, 120, 90, 60, 30, 15]

    /// 空 / NC 等不显示和弦字母的占位。
    static func isSilence(_ chord: String) -> Bool {
        let c = chord.trimmingCharacters(in: .whitespacesAndNewlines)
        return c.isEmpty || c == "NC" || c == "N.C."
    }

    /// 一个标准 chunk（slot）→ VexFlow 休止 token。贪心后的 chunk 恒为标准值，
    /// 与 ContentView.getExactVexFlowDuration(isRest:true) 在标准档上的输出逐字相同：
    /// 480=wr、360=hdr、240=hr、180=qdr、120=qr、90=8dr、60=8r、30=16r、15=32r。
    static func restToken(forChunk chunk: Int) -> String {
        if let t = TradingTokens.restTokenForSlot[chunk] { return t }
        // 非标准兜底（理论上 15 的倍数经贪心都能切完，不会到这）；保险取整小节全休止。
        return "wr"
    }

    // MARK: - reset 骨架（开始：只有和弦 + 分段休止的完整谱）

    /// 复刻 ContentView.generateEmptyRoadmap :1130-1186。
    /// 段长 = 相邻 chordSlots.startSlot 之差（末段到小节末）；每段贪心切休止符，
    /// 有效和弦（非空/非 NC）挂在该段第一个休止符的 noteIndex。
    static func skeletonRestMeasure(chord: String,
                                    chordSlots: [(chord: String, startSlot: Int)],
                                    sectionName: String?,
                                    slotsPerMeasure: Int) -> GeneratedMeasure {
        var notes: [GeneratedNote] = []
        var annotations: [(chord: String, noteIndex: Int)] = []
        var cursor = 0

        for (i, cs) in chordSlots.enumerated() {
            // 兜底：首个 chordSlot 若不是从 0 开始，补齐其前的空隙。
            if cs.startSlot > cursor {
                emitRestSegment(slots: cs.startSlot - cursor, notes: &notes,
                                label: nil, annotations: &annotations)
                cursor = cs.startSlot
            }
            let segEnd = (i + 1 < chordSlots.count) ? chordSlots[i + 1].startSlot : slotsPerMeasure
            let take = min(segEnd, slotsPerMeasure) - cs.startSlot
            if take > 0 {
                let label: String? = isSilence(cs.chord) ? nil : cs.chord
                emitRestSegment(slots: take, notes: &notes, label: label, annotations: &annotations)
                cursor = cs.startSlot + take
            }
        }
        // 末尾空隙兜底。
        if cursor < slotsPerMeasure {
            emitRestSegment(slots: slotsPerMeasure - cursor, notes: &notes,
                            label: nil, annotations: &annotations)
        }
        // chordSlots 为空（无任何和弦）：整小节一个休止符。
        if notes.isEmpty {
            emitRestSegment(slots: slotsPerMeasure, notes: &notes,
                            label: nil, annotations: &annotations)
        }

        return GeneratedMeasure(chord: chord, notes: notes, chordAnnotations: annotations,
                                sectionName: sectionName, slotsPerMeasure: slotsPerMeasure,
                                chordSlots: chordSlots)
    }

    /// 一段 takeSlots：先（可选）把和弦挂在当前第一个休止符 index，再按标准表贪心切休止符。
    /// 对应 ContentView :1149（chunk 循环前 append）与 :1153-1177。
    private static func emitRestSegment(slots takeSlots: Int,
                                        notes: inout [GeneratedNote],
                                        label: String?,
                                        annotations: inout [(chord: String, noteIndex: Int)]) {
        guard takeSlots > 0 else { return }
        if let label = label {
            annotations.append((chord: label, noteIndex: notes.count))
        }
        var remaining = takeSlots
        while remaining > 0 {
            var chunk = remaining
            for std in chunkStandards where std <= remaining { chunk = std; break }
            notes.append(GeneratedNote(pitch: "B/4", tag: .chordTone, isRest: true,
                                       duration: restToken(forChunk: chunk), isTriplet: false,
                                       isTieStart: false, isTieEnd: false, graceNotes: []))
            remaining -= chunk
        }
    }

    // MARK: - overlay 实音（旋律填入后，把和弦挂到正确的音符上）

    /// 复刻 ContentView :1688-1691。遍历 notes（含休止符、tieEnd），按小节内 slot 累加，
    /// 当 currentSlots ≥ chordSlot.startSlot 时把该和弦挂到当前 note index（含休止符）；
    /// NC/空不挂（游标仍推进，保证后续和弦位置正确）。
    static func reannotate(notes: [GeneratedNote],
                           chordSlots: [(chord: String, startSlot: Int)])
        -> [(chord: String, noteIndex: Int)] {
        var annotations: [(chord: String, noteIndex: Int)] = []
        var nextChord = 0
        var cursor = 0
        for (idx, note) in notes.enumerated() {
            while nextChord < chordSlots.count && cursor >= chordSlots[nextChord].startSlot {
                let c = chordSlots[nextChord].chord
                if !isSilence(c) {
                    annotations.append((chord: c, noteIndex: idx))
                }
                nextChord += 1
            }
            cursor += TradingTokens.slots(of: note.duration)
        }
        return annotations
    }
}
