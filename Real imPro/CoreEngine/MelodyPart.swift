import Foundation

// MARK: - MelodyPart — 旋律声部封装 (P1 · 约60行)
// 对接 GrammarLickGlue.LightPostProcessor.mergeTies() 逻辑

struct MelodyPart {

    /// 内部音符序列
    private(set) var notes: [PhysicalNote]

    // MARK: - 初始化

    init(notes: [PhysicalNote] = []) {
        self.notes = notes
    }

    /// 从已有数组构造
    init(_ notes: [PhysicalNote]) {
        self.notes = notes
    }

    // MARK: - 基础属性

    /// 有效音符数量 (不含休止符)
    var noteCount: Int {
        notes.filter { $0.midiPitch != -1 }.count
    }

    /// 总时值 (slots)
    var totalSlots: Int {
        notes.reduce(0) { $0 + $1.durationSlots }
    }

    // MARK: - 切片

    /// 按索引切片 [from..<to)
    func slice(from: Int, to: Int) -> MelodyPart {
        let safeFrom = Swift.max(0, Swift.min(from, notes.count))
        let safeTo   = Swift.max(safeFrom, Swift.min(to, notes.count))
        return MelodyPart(Array(notes[safeFrom..<safeTo]))
    }

    /// 按小节切片 (每小节beatsPerMeasure拍, 120slots/拍)
    func slice(measures: Range<Int>, beatsPerMeasure: Int = 4) -> MelodyPart {
        let slotsPerMeasure = beatsPerMeasure * 120
        let startSlot = measures.lowerBound * slotsPerMeasure
        let endSlot   = measures.upperBound * slotsPerMeasure
        return slice(slotRange: startSlot..<endSlot)
    }

    /// 按时隙范围切片
    func slice(slotRange: Range<Int>) -> MelodyPart {
        var result: [PhysicalNote] = []
        var cursor = 0
        for note in notes {
            let noteEnd = cursor + note.durationSlots
            if noteEnd > slotRange.lowerBound && cursor < slotRange.upperBound {
                let clippedStart = Swift.max(cursor, slotRange.lowerBound)
                let clippedEnd   = Swift.min(noteEnd, slotRange.upperBound)
                let clippedDur   = clippedEnd - clippedStart
                if clippedDur > 0 {
                    result.append(PhysicalNote(midiPitch: note.midiPitch,
                                               durationSlots: clippedDur))
                }
            }
            cursor = noteEnd
            if cursor >= slotRange.upperBound { break }
        }
        return MelodyPart(result)
    }

    // MARK: - 移调 (对接 Transposition)

    /// 半音移调
    func transposed(by semitones: Int) -> MelodyPart {
        MelodyPart(Transposition.chromatic(notes, semitones: semitones))
    }

    /// 八度移调
    func transposed(octaves: Int) -> MelodyPart {
        MelodyPart(notes.map { note in
            guard note.midiPitch != -1 else { return note }
            return PhysicalNote(midiPitch: Transposition.octave(note.midiPitch, octaves: octaves),
                                durationSlots: note.durationSlots)
        })
    }

    /// 按调性移调
    func transposed(from oldKey: Key, to newKey: Key) -> MelodyPart {
        MelodyPart(Transposition.transpose(notes: notes, from: oldKey, to: newKey))
    }

    // MARK: - 延音合并 (对接 LightPostProcessor.mergeTies)

    /// 合并相邻同音延音
    func mergedTies() -> MelodyPart {
        MelodyPart(LightPostProcessor.mergeTies(notes))
    }

    // MARK: - Collection 桥接

    var first: PhysicalNote? { notes.first }
    var last: PhysicalNote?  { notes.last }
    var count: Int           { notes.count }
    var isEmpty: Bool        { notes.isEmpty }

    subscript(index: Int) -> PhysicalNote {
        get { notes[index] }
    }

    mutating func append(_ note: PhysicalNote) { notes.append(note) }
    mutating func append(contentsOf other: MelodyPart) { notes.append(contentsOf: other.notes) }
}

// MARK: - Sequence

extension MelodyPart: Sequence {
    func makeIterator() -> IndexingIterator<[PhysicalNote]> {
        notes.makeIterator()
    }
}
