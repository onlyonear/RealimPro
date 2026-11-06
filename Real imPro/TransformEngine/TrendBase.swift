import Foundation

// MARK: - TrendBase — 趋势生成抽象基类 + 6种子类 (轻量化移植原版 lickgen/transformations/trends/)
// 与 TrendDetector(检测端) 完全解耦 — 本模块仅负责生成音符池(GENERATION)
// 复用现有 PitchClass/Key/Transposition/ChordBlock 工具链

// ═══════════════════════════════════════════════════════
// 1. 抽象基协议
// ═══════════════════════════════════════════════════════

protocol Trend {
    /// 趋势标识名
    var name: String { get }

    /// 根据当前和弦/调性, 生成可用音符池 (PitchClass 序列, 音高升序)
    func generateNotePool(
        chord: ChordBlock,
        key: Key,
        range: ClosedRange<Int>
    ) -> [Int]

    /// 趋势转调适配
    func transposed(by semitones: Int) -> Self
}

// ═══════════════════════════════════════════════════════
// 2. ArpeggioTrend — 琶音趋势
// ═══════════════════════════════════════════════════════

struct ArpeggioTrend: Trend {
    let name = "Arpeggio"
    var direction: Int       // 1=上行, -1=下行
    var octaves: Int         // 跨八度数量

    init(direction: Int = 1, octaves: Int = 2) {
        self.direction = direction
        self.octaves = octaves
    }

    func generateNotePool(chord: ChordBlock, key: Key, range: ClosedRange<Int>) -> [Int] {
        let rootPC = PitchClass(noteName: String(chord.name.prefix {
            $0.isLetter && $0.isUppercase || $0 == "#" || $0 == "b"
        })).index
        let family = chord.getChordFamily()
        // 和弦音音程 (按 family)
        let chordIntervals: [Int]
        switch family {
        case .major:    chordIntervals = [0, 4, 7, 11]
        case .minor:    chordIntervals = [0, 3, 7, 10]
        case .dominant: chordIntervals = [0, 4, 7, 10]
        case .diminished: chordIntervals = [0, 3, 6, 9]
        case .halfDiminished: chordIntervals = [0, 3, 6, 10]
        case .augmented: chordIntervals = [0, 4, 8]
        case .sus:      chordIntervals = [0, 5, 7]
        case .unknown:  chordIntervals = [0, 4, 7]
        }
        var pool: [Int] = []
        let count = chordIntervals.count
        for o in 0..<octaves {
            for i in 0..<count {
                let idx = direction > 0 ? i : (count - 1 - i)
                let pc = (rootPC + chordIntervals[idx]) % 12
                let pitch = pc + 48 + (o * 12)
                if range.contains(pitch) { pool.append(pitch) }
            }
        }
        return pool
    }

    func transposed(by semitones: Int) -> ArpeggioTrend { self }
}

// ═══════════════════════════════════════════════════════
// 3. AscendingTrend — 上行级进趋势
// ═══════════════════════════════════════════════════════

struct AscendingTrend: Trend {
    let name = "Ascending"
    var stepSize: Int   // 1=半音, 2=全音 (默认)

    init(stepSize: Int = 2) { self.stepSize = stepSize }

    func generateNotePool(chord: ChordBlock, key: Key, range: ClosedRange<Int>) -> [Int] {
        let scale = key.scalePitches(in: range)
        // 上行筛选: 从最低音开始, 按stepSize选取
        var pool: [Int] = []
        for i in 0..<scale.count {
            if i % max(1, stepSize) == 0 { pool.append(scale[i]) }
        }
        return pool
    }

    func transposed(by semitones: Int) -> AscendingTrend { self }
}

// ═══════════════════════════════════════════════════════
// 4. DescendingTrend — 下行级进趋势
// ═══════════════════════════════════════════════════════

struct DescendingTrend: Trend {
    let name = "Descending"
    var stepSize: Int = 2

    init(stepSize: Int = 2) { self.stepSize = stepSize }

    func generateNotePool(chord: ChordBlock, key: Key, range: ClosedRange<Int>) -> [Int] {
        let scale = key.scalePitches(in: range)
        // 逆序下行
        let reversed = Array(scale.reversed())
        var pool: [Int] = []
        for i in 0..<reversed.count {
            if i % max(1, stepSize) == 0 { pool.append(reversed[i]) }
        }
        return pool
    }

    func transposed(by semitones: Int) -> DescendingTrend { self }
}

// ═══════════════════════════════════════════════════════
// 5. ChromaticTrend — 半音经过/环绕音趋势
// ═══════════════════════════════════════════════════════

struct ChromaticTrend: Trend {
    let name = "Chromatic"
    var approachDirection: Int  // 1=上行趋近, -1=下行趋近

    init(approachDirection: Int = 1) { self.approachDirection = approachDirection }

    func generateNotePool(chord: ChordBlock, key: Key, range: ClosedRange<Int>) -> [Int] {
        let rootPC = PitchClass(noteName: String(chord.name.prefix {
            $0.isLetter && $0.isUppercase || $0 == "#" || $0 == "b"
        })).index
        // 围绕根音的上/下半音邻音
        let neighborAbove = (rootPC + 1) % 12
        let neighborBelow = (rootPC - 1 + 12) % 12
        var pool: [Int] = []
        // 在两个八度生成
        for octave in [48, 60, 72] {
            let above = neighborAbove + octave
            let below = neighborBelow + octave
            if approachDirection >= 0, range.contains(above) { pool.append(above) }
            if approachDirection <= 0, range.contains(below) { pool.append(below) }
        }
        // 补充全音邻音
        let wholeAbove = (rootPC + 2) % 12
        let wholeBelow = (rootPC - 2 + 12) % 12
        for octave in [48, 60, 72] {
            let a = wholeAbove + octave
            let b = wholeBelow + octave
            if range.contains(a) { pool.append(a) }
            if range.contains(b) { pool.append(b) }
        }
        return pool.sorted()
    }

    func transposed(by semitones: Int) -> ChromaticTrend { self }
}

// ═══════════════════════════════════════════════════════
// 6. DiatonicTrend — 纯调内自然音平稳线条
// ═══════════════════════════════════════════════════════

struct DiatonicTrend: Trend {
    let name = "Diatonic"
    var direction: Int      // 1=上行, -1=下行
    var avoidLeaps: Bool    // true=仅级进

    init(direction: Int = 1, avoidLeaps: Bool = true) {
        self.direction = direction
        self.avoidLeaps = avoidLeaps
    }

    func generateNotePool(chord: ChordBlock, key: Key, range: ClosedRange<Int>) -> [Int] {
        var scale = key.scalePitches(in: range)
        if direction < 0 { scale.reverse() }
        if avoidLeaps {
            // 仅保留级进音 (相邻半音≤2)
            var pool: [Int] = [scale[0]]
            for i in 1..<scale.count {
                if abs(scale[i] - scale[i-1]) <= 2 { pool.append(scale[i]) }
            }
            return pool
        }
        return scale
    }

    func transposed(by semitones: Int) -> DiatonicTrend { self }
}

// ═══════════════════════════════════════════════════════
// 7. SkipTrend — 跳进趋势 (≥三度)
// ═══════════════════════════════════════════════════════

struct SkipTrend: Trend {
    let name = "Skip"
    var minSkip: Int = 3    // 最小跳进半音数 (默认三度=3 or 4)

    init(minSkip: Int = 3) { self.minSkip = minSkip }

    func generateNotePool(chord: ChordBlock, key: Key, range: ClosedRange<Int>) -> [Int] {
        let scale = key.scalePitches(in: range)
        guard scale.count >= 2 else { return scale }
        var pool: [Int] = [scale[0]]
        var last = scale[0]
        for p in scale.dropFirst() {
            if abs(p - last) >= minSkip {
                pool.append(p)
                last = p
            }
        }
        return pool
    }

    func transposed(by semitones: Int) -> SkipTrend { self }
}
