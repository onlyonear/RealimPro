import Foundation

// MARK: - 趋势引擎完整套件
// 功能: 7种旋律趋势检测 · 趋势段容器 · 检测器 · outline压缩

extension TransformEngine {

    // MARK: TrendChordChecker
    struct TrendChordChecker {
        let isChordTone: (_ midiPitch: Int, _ chordName: String) -> Bool
        let isColorTone: (_ midiPitch: Int, _ chordName: String) -> Bool
        func isChordOrColorTone(_ midi: Int, _ name: String) -> Bool {
            isChordTone(midi, name) || isColorTone(midi, name)
        }
    }

    // MARK: TrendProtocol
    protocol TrendProtocol {
        func weights() -> (Double, Double, Double)
        func stopCondition(n1: NoteChordPair, n2: NoteChordPair, checker: TrendChordChecker) -> Bool
        func stopCondition(note: NoteChordPair, chord: ChordBlock, checker: TrendChordChecker) -> Bool
        var numberOfSections: Int { get }
        var name: String { get }
    }

    // MARK: 7 Trend structs

    struct ArpeggioTrend: TrendProtocol {
        func weights() -> (Double, Double, Double) { (1, 1, 1) }
        var numberOfSections: Int { 1 }
        var name: String { "ARPEGGIO" }
        func stopCondition(n1: NoteChordPair, n2: NoteChordPair, checker: TrendChordChecker) -> Bool {
            let n = n2.chord.name
            return !checker.isChordTone(n2.note.midiPitch, n)
                || n1.note.midiPitch == n2.note.midiPitch
        }
        func stopCondition(note: NoteChordPair, chord: ChordBlock, checker: TrendChordChecker) -> Bool {
            !checker.isChordTone(note.note.midiPitch, chord.name)
        }
    }

    struct AscendingTrend: TrendProtocol {
        func weights() -> (Double, Double, Double) { (1, 1, 1) }
        var numberOfSections: Int { 2 }
        var name: String { "ASCENDING" }
        private func ascending(_ n1: NoteChordPair, _ n2: NoteChordPair) -> Bool {
            n1.note.midiPitch < n2.note.midiPitch
        }
        func stopCondition(n1: NoteChordPair, n2: NoteChordPair, checker: TrendChordChecker) -> Bool {
            !ascending(n1, n2)
        }
        func stopCondition(note: NoteChordPair, chord: ChordBlock, checker: TrendChordChecker) -> Bool {
            false
        }
    }

    struct ChromaticTrend: TrendProtocol {
        func weights() -> (Double, Double, Double) { (1, 1, 1) }
        var numberOfSections: Int { 2 }
        var name: String { "CHROMATIC" }
        func stopCondition(n1: NoteChordPair, n2: NoteChordPair, checker: TrendChordChecker) -> Bool {
            let d = abs(n1.note.midiPitch - n2.note.midiPitch)
            return d != 1 || n1.note.midiPitch == n2.note.midiPitch
        }
        func stopCondition(note: NoteChordPair, chord: ChordBlock, checker: TrendChordChecker) -> Bool {
            false
        }
    }

    struct DescendingTrend: TrendProtocol {
        func weights() -> (Double, Double, Double) { (1, 1, 1) }
        var numberOfSections: Int { 2 }
        var name: String { "DESCENDING" }
        private func descending(_ n1: NoteChordPair, _ n2: NoteChordPair) -> Bool {
            n1.note.midiPitch > n2.note.midiPitch
        }
        func stopCondition(n1: NoteChordPair, n2: NoteChordPair, checker: TrendChordChecker) -> Bool {
            !descending(n1, n2)
        }
        func stopCondition(note: NoteChordPair, chord: ChordBlock, checker: TrendChordChecker) -> Bool {
            false
        }
    }

    struct DiatonicTrend: TrendProtocol {
        func weights() -> (Double, Double, Double) { (1, 1, 1) }
        var numberOfSections: Int { 2 }
        var name: String { "DIATONIC" }
        private func diatonic(_ n1: NoteChordPair, _ n2: NoteChordPair) -> Bool {
            let d = abs(n1.note.midiPitch - n2.note.midiPitch)
            return d != 0 && d <= 2
        }
        func stopCondition(n1: NoteChordPair, n2: NoteChordPair, checker: TrendChordChecker) -> Bool {
            !diatonic(n1, n2)
        }
        func stopCondition(note: NoteChordPair, chord: ChordBlock, checker: TrendChordChecker) -> Bool {
            !checker.isChordOrColorTone(note.note.midiPitch, chord.name)
        }
    }

    struct SkipTrend: TrendProtocol {
        func weights() -> (Double, Double, Double) { (1, 1, 1) }
        var numberOfSections: Int { 2 }
        var name: String { "SKIP" }
        func stopCondition(n1: NoteChordPair, n2: NoteChordPair, checker: TrendChordChecker) -> Bool {
            let d = abs(n1.note.midiPitch - n2.note.midiPitch)
            return d <= 2 || n1.note.midiPitch == n2.note.midiPitch
        }
        func stopCondition(note: NoteChordPair, chord: ChordBlock, checker: TrendChordChecker) -> Bool {
            false
        }
    }

    // MARK: TrendSegment
    struct TrendSegment {
        var ncps: [NoteChordPair]

        init() { self.ncps = [] }
        init(copying list: [NoteChordPair]) { self.ncps = list.map { $0.copy() } }

        mutating func add(_ ncp: NoteChordPair) { ncps.append(ncp) }

        var totalDuration: Int { ncps.reduce(0) { $0 + $1.getDuration() } }
        var count: Int { ncps.count }
        var startSlot: Int { ncps.first?.slot ?? 0 }

        mutating func clear() { ncps.removeAll() }

        /// splitUp — 等时值切割 (使用 getDuration() 保证兼容)
        func splitUp(duration: Int) -> [TrendSegment] {
            var chunks: [TrendSegment] = []
            var cur = TrendSegment()
            var rem = duration
            for i in 0..<ncps.count {
                cur.ncps.append(ncps[i])
                rem -= ncps[i].getDuration()
                if rem <= 0 || i == ncps.count - 1 {
                    rem = duration
                    chunks.append(cur.copy())
                    cur.clear()
                }
            }
            return chunks
        }

        /// makeIterator — 使用工程现有 NCPIterator(sequence:) 签名
        func makeIterator() -> NCPIterator { NCPIterator(sequence: ncps) }

        var firstNCP: NoteChordPair? { ncps.first }
        var lastNCP: NoteChordPair? { ncps.last }

        func copy() -> TrendSegment { TrendSegment(copying: ncps) }

        /// renumber — 使用 setVar mutating (因为 transformVar 是 let)
        mutating func renumber() {
            for i in 0..<ncps.count { ncps[i].setVar(i + 1) }
        }
    }

    // MARK: TrendDetector
    struct TrendDetector {
        static let minTrendLength = 2
        static let maxTrendLength = 4
        static let notAPitch: Int = -2

        let trend: any TrendProtocol
        let chordChecker: TrendChordChecker

        init(trend: any TrendProtocol, chordChecker: TrendChordChecker) {
            self.trend = trend
            self.chordChecker = chordChecker
        }

        /// detect — 滑动窗口趋势检测
        func detect(ncps: [NoteChordPair], chords: [ChordBlock]) -> [TrendSegment] {
            var result: [TrendSegment] = []
            var cur = TrendSegment()
            var prev: NoteChordPair? = nil
            var vn = 1
            var slot = 0

            // 和弦时间轴
            var tl: [(s: Int, c: ChordBlock)] = []
            var cs = 0
            for ch in chords { tl.append((cs, ch)); cs += Int(Double(ch.duration) * Double(Constants.slotsPerBeat)) }
            func chordAt(_ s: Int) -> ChordBlock? {
                for e in tl.reversed() { if s >= e.s { return e.c } }
                return tl.first?.c
            }

            for ncp in ncps {
                let c = chordAt(slot)

                if trend.stopCondition(n1: prev, n2: ncp, chord: c, checker: chordChecker)
                    || cur.count >= TrendDetector.maxTrendLength {

                    if cur.count >= TrendDetector.minTrendLength { result.append(cur) }
                    cur = TrendSegment()
                    prev = nil
                    vn = 1

                    // 当前音符能否开新趋势?
                    if !trend.stopCondition(n1: nil, n2: ncp, chord: c, checker: chordChecker) {
                        var x = ncp.copy(); x.setVar(vn); vn += 1
                        cur.add(x); prev = x
                    }
                } else {
                    var x = ncp.copy(); x.setVar(vn); vn += 1
                    cur.add(x); prev = x
                }
                slot += ncp.getDuration()
            }

            if cur.count >= TrendDetector.minTrendLength { result.append(cur) }
            return result
        }
    }

} // end extension TransformEngine


// ═══════════════════════════════════════════════════════════
// Part 2 — TrendProtocol default implementations
// (must be outside extension TransformEngine)
// ═══════════════════════════════════════════════════════════

extension TransformEngine.TrendProtocol {

    func dist(_ n1: TransformEngine.NoteChordPair,
              _ n2: TransformEngine.NoteChordPair) -> Int {
        n2.note.midiPitch - n1.note.midiPitch
    }

    func absDist(_ n1: TransformEngine.NoteChordPair,
                 _ n2: TransformEngine.NoteChordPair) -> Int {
        abs(dist(n1, n2))
    }

    func stopCondition(n1: TransformEngine.NoteChordPair?,
                       n2: TransformEngine.NoteChordPair,
                       chord: ChordBlock?,
                       checker: TransformEngine.TrendChordChecker) -> Bool {
        guard let c = chord, c.name != "NC",
              n2.note.midiPitch != -1 else { return true }
        if let n1 = n1, n1.note.midiPitch == -1 { return true }

        if n1 == nil || n1!.note.midiPitch == TransformEngine.TrendDetector.notAPitch {
            return stopCondition(note: n2, chord: c, checker: checker)
        }

        return stopCondition(n1: n1!, n2: n2, checker: checker)
            || stopCondition(note: n2, chord: c, checker: checker)
    }

    /// score — 适配工程 Scorer.score(trend: [NoteChordPair]) API
    func score(ncp: TransformEngine.NoteChordPair,
               trend: TransformEngine.TrendSegment,
               metre: [Int]) -> Double {
        let w = weights()
        let s = TransformEngine.Scorer(priorityWeight: w.0, beatWeight: w.1,
                                       durationWeight: w.2, metre: metre)
        return s.score(trend: [ncp])
    }

    func importantNotes(trend: TransformEngine.TrendSegment,
                        metre: [Int]) -> TransformEngine.TrendSegment {
        var flat = numberOfSections
        let total = trend.ncps.count
        if total <= flat { flat = total / 2 }
        guard flat > 0 else { return TransformEngine.TrendSegment() }

        let dur = trend.totalDuration / flat
        let sections = trend.splitUp(duration: dur)
        var result = TransformEngine.TrendSegment()
        for sec in sections {
            result.ncps.append(importantNote(trend: sec, metre: metre))
        }
        result.renumber()
        return result
    }

    func importantNote(trend: TransformEngine.TrendSegment,
                       metre: [Int]) -> TransformEngine.NoteChordPair {
        var best: Double = -1
        var bestNCP = trend.ncps.first!
        for curr in trend.ncps {
            let s = score(ncp: curr, trend: trend, metre: metre)
            if s > best { best = s; bestNCP = curr }
        }
        var r = bestNCP.copy()
        r = r.setDuration(trend.totalDuration)
        r.setSlot(trend.ncps.first?.slot ?? r.slot)
        return r
    }
}
