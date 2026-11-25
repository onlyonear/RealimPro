import Foundation

// MARK: - Transposition — 移调工具 (P0 · 约60行)
// 半音偏移 / 八度移调 / 自然音级移调
// 批量音符/和弦数组同步移调, 替代工程内零散手写 +-12 逻辑

struct Transposition {

    // ════════════════════════════════════════════════════
    // 1. 单音移调
    // ════════════════════════════════════════════════════

    /// 半音移调 (正=升, 负=降)
    static func chromatic(_ pitch: Int, semitones: Int) -> Int {
        pitch + semitones
    }

    /// 八度移调 (正=升八度, 负=降八度)
    static func octave(_ pitch: Int, octaves: Int = 1) -> Int {
        pitch + (octaves * 12)
    }

    /// 自然音级移调: 在指定调式音阶内移动指定步数
    /// - Parameters:
    ///   - pitch: 原MIDI音高
    ///   - steps: 移动的音阶级数 (正=上行, 负=下行)
    ///   - key: 参考调性
    static func diatonic(_ pitch: Int, steps: Int, in key: Key) -> Int {
        let scale = key.scalePitches()
        guard !scale.isEmpty, let currentIdx = scale.firstIndex(of: pitch) else {
            return chromatic(pitch, semitones: steps)
        }
        let newIdx = ((currentIdx + steps) % scale.count + scale.count) % scale.count
        let octaveShift = (currentIdx + steps) / scale.count
        return scale[newIdx] + (octaveShift * 12)
    }

    // ════════════════════════════════════════════════════
    // 2. 批量移调
    // ════════════════════════════════════════════════════

    /// 批量半音移调
    static func chromatic(_ pitches: [Int], semitones: Int) -> [Int] {
        pitches.map { $0 + semitones }
    }

    /// 批量 PhysicalNote 半音移调
    static func chromatic(_ notes: [PhysicalNote], semitones: Int) -> [PhysicalNote] {
        notes.map { note in
            guard note.midiPitch != -1 else { return note }
            return PhysicalNote(midiPitch: note.midiPitch + semitones,
                                durationSlots: note.durationSlots,
                                tuplet: note.tuplet, terminalType: note.terminalType)
        }
    }

    /// 批量和弦名移调 (仅偏移根音)
    static func chromatic(_ chordNames: [String], semitones: Int) -> [String] {
        chordNames.map { chromatic($0, semitones: semitones) }
    }

    /// 单个和弦名移调
    static func chromatic(_ chordName: String, semitones: Int) -> String {
        let root = String(chordName.prefix { $0.isLetter && $0.isUppercase || $0 == "#" || $0 == "b" })
        let suffix = String(chordName.dropFirst(root.count))
        let newPC = PitchClass(noteName: root).transposed(by: semitones)
        return newPC.preferredName + suffix
    }

    // ════════════════════════════════════════════════════
    // 3. 调性移调 (整段旋律换调)
    // ════════════════════════════════════════════════════

    /// 将整段旋律从 oldKey 移到 newKey
    static func transpose(notes: [PhysicalNote],
                          from oldKey: Key,
                          to newKey: Key) -> [PhysicalNote] {
        let semitones = newKey.tonic.index - oldKey.tonic.index
        return chromatic(notes, semitones: semitones)
    }
}
