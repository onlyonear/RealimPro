import Foundation

// MARK: - Syncopation — 切分音算法 (P1-5)
// 基础反拍切分: 正拍音提前30slots, 前一个音延长补空, 总时值不变

struct Syncopation {

    /// 风格→切分概率
    private static let styleProbabilities: [String: Double] = [
        "swing":  0.40,
        "bebop":  0.60,
        "ballad": 0.10,
    ]

    // MARK: - 主入口

    /// 对生成好的音符列表做切分处理, 返回新数组
    /// - Parameters:
    ///   - notes: 原始音符列表
    ///   - style: 风格名
    /// - Returns: 切分后的新数组, 总时值不变
    static func apply(notes: [PhysicalNote], style: String = "swing") -> [PhysicalNote] {
        let probability = styleProbabilities[style] ?? 0.15
        guard probability > 0, notes.count >= 2 else { return notes }

        var result: [PhysicalNote] = []
        result.reserveCapacity(notes.count)

        for i in 0..<notes.count {
            let note = notes[i]

            // 跳过休止符
            guard note.midiPitch >= 0 else { result.append(note); continue }

            // 只切整拍位置(slot是120倍数)的八分/四分音
            let currentSlot = result.reduce(0) { $0 + $1.durationSlots }
            let isDownbeat = currentSlot % 120 == 0
            let isEligibleDuration = note.durationSlots == 60 || note.durationSlots == 120

            // 跳过第一个音(小节强拍)
            guard i > 0, isDownbeat, isEligibleDuration,
                  Double.random(in: 0...1) < probability else {
                result.append(note); continue
            }

            // 切分: 前一个音延长30slots, 当前音时长不变(但起点推迟30slots, 形成反拍重音)
            // 实际效果: 前音增30, 当前音减30才保持总时值 —
            // 但保持当前音时长不变会产生总时值变化。改为当前音减30。
            let graceShift = 30
            let prevNote = result.removeLast()
            let newPrevDur = prevNote.durationSlots + graceShift
            let newCurDur  = note.durationSlots - graceShift

            guard newCurDur >= 30 else { result.append(prevNote); result.append(note); continue }

            result.append(PhysicalNote(midiPitch: prevNote.midiPitch, durationSlots: newPrevDur))
            result.append(PhysicalNote(midiPitch: note.midiPitch, durationSlots: newCurDur))
        }

        return result
    }
}