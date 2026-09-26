import Foundation

// MARK: - TupletSanitizer — 三连音合法性消毒器 (VexFlow 层零侵入阻断)
// 剔除非法孤立 _t3 标记，解决 VexFlow 裸 "3" 显示 + MIDI 短音播放
// 不改动 durationSlots / 音高 / 连音 / 颜色

enum TupletSanitizer {

    /// 主入口
    static func sanitize(_ measures: [GeneratedMeasure]) -> [GeneratedMeasure] {
        measures.map { sanitizeMeasure($0) }
    }

    /// 消毒单小节
    private static func sanitizeMeasure(_ measure: GeneratedMeasure) -> GeneratedMeasure {
        var notes = measure.notes
        var i = 0
        while i < notes.count {
            guard notes[i].duration.contains("_t3") else { i += 1; continue }

            var currentGroup: [Int] = []
            var currentTotal = 0

            while i < notes.count, notes[i].duration.contains("_t3") {
                let noteSlots = slotDuration(notes[i].duration)
                currentGroup.append(i)
                currentTotal += noteSlots

                // 总时值为 120 的整数倍（整拍）→ 合法组收束
                if currentTotal > 0, currentTotal % 120 == 0 {
                    currentGroup = []; currentTotal = 0
                } else if currentTotal > 480 {
                    currentGroup = []; currentTotal = 0   // 超过一小节清空
                }
                i += 1
            }

            // 剩余不足一组的音 → 剥离 _t3
            for idx in currentGroup {
                notes[idx] = GeneratedNote(
                    pitch:      notes[idx].pitch,
                    tag:        notes[idx].tag,
                    isRest:     notes[idx].isRest,
                    duration:   notes[idx].duration.replacingOccurrences(of: "_t3", with: ""),
                    isTriplet:  false,
                    isTieStart: notes[idx].isTieStart,
                    isTieEnd:   notes[idx].isTieEnd,
                    graceNotes: notes[idx].graceNotes
                )
            }
        }

        return GeneratedMeasure(
            chord:            measure.chord,
            notes:            notes,
            chordAnnotations: measure.chordAnnotations,
            sectionName:      measure.sectionName,
            slotsPerMeasure:  measure.slotsPerMeasure
        )
    }

    /// 从 duration 字符串计算实际 slots (含附点/三连音修正)
    private static func slotDuration(_ encoded: String) -> Int {
        let s = encoded
        let parts = s.components(separatedBy: "_t")
        let basePart = parts[0]
        let tuplet = parts.count > 1 ? Int(parts[1]) ?? 0 : 0

        let hasDot = basePart.contains("d")
        let baseDur = basePart
            .replacingOccurrences(of: "r", with: "")
            .replacingOccurrences(of: "d", with: "")

        let baseSlots: Int
        switch baseDur {
        case "w":  baseSlots = 480
        case "h":  baseSlots = 240
        case "q":  baseSlots = 120
        case "8":  baseSlots = 60
        case "16": baseSlots = 30
        case "32": baseSlots = 15
        default:   baseSlots = 60
        }

        var slots = baseSlots
        if hasDot { slots = Int(Double(slots) * 1.5) }
        if tuplet == 3 { slots = slots * 2 / 3 }
        if tuplet == 5 { slots = slots * 4 / 5 }
        return slots
    }
}
