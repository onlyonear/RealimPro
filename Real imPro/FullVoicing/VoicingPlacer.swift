import Foundation

// MARK: - 规则 voicing 摆放/声部连接（逐方法对齐 Java ChordPattern.placeVoicing/Above/Below + averageLeap/smallestLeap + chooseVoicings）
// 纯 [Int](绝对 MIDI) 运算, 不依赖 UI / 和弦模型, 可独立单测。

enum VoicingPlacer {

    /// 对齐 NoteSymbol.getSemitonesAbove: this(last) -> other 向上的音级距离 1..12（按 mod12, 与八度无关）
    static func semitonesAbove(lastMidi: Int, voicingMidi: Int) -> Int {
        var d = (voicingMidi % 12) - (lastMidi % 12)
        while d <= 0 { d += 12 }
        return d
    }

    static func transpose(_ notes: [Int], _ rise: Int) -> [Int] { notes.map { $0 + rise } }

    /// placeVoicingAbove L1160
    static func placeAbove(lastChord: [Int], voicing: [Int]) -> [Int] {
        let difference = lastChord[0] - voicing[0]
        if difference > 0 {
            return transpose(voicing, 12 * ((difference / 12) + 1))
        } else if difference <= -12 {
            return transpose(voicing, 12 * (difference / 12))
        }
        return voicing
    }

    /// placeVoicingBelow L1193
    static func placeBelow(lastChord: [Int], voicing: [Int]) -> [Int] {
        let difference = lastChord[0] - voicing[0]
        if difference < 0 {
            return transpose(voicing, 12 * ((difference / 12) - 1))
        } else if difference >= 12 {
            return transpose(voicing, 12 * (difference / 12))
        }
        return voicing
    }

    /// placeVoicing L1256。返回 nil 表示无法夹进 [low,high] 音域。
    static func place(lastChord: [Int], voicing: [Int], low: Int, high: Int) -> [Int]? {
        let last = lastChord.isEmpty ? [low, high] : lastChord
        let semis = semitonesAbove(lastMidi: last[0], voicingMidi: voicing[0])
        var v = semis >= 6 ? placeBelow(lastChord: last, voicing: voicing)
                           : placeAbove(lastChord: last, voicing: voicing)
        var lo = v.min()!, hi = v.max()!
        while lo < low {
            v = transpose(v, 12); lo = v.min()!; hi = v.max()!
            if hi > high { return nil }
        }
        while hi > high {
            v = transpose(v, -12); lo = v.min()!; hi = v.max()!
            if lo < low { return nil }
        }
        return v
    }

    static func smallestLeap(chord: [Int], note: Int) -> Int {
        var best = 127
        for cn in chord { best = min(best, abs(cn - note)) }
        return best
    }

    /// averageLeap L1318: c2 每个音到 c1 最近距离的平均（整除, 对齐 Java (int)((double)sum/num)）
    static func averageLeap(_ c1: [Int], _ c2: [Int]) -> Int {
        guard !c2.isEmpty else { return 0 }
        var sum = 0
        for n in c2 { sum += smallestLeap(chord: c1, note: n) }
        return Int((Double(sum) / Double(c2.count)))
    }

    struct Candidate: Equatable { let notes: [Int]; let ext: [Int] }

    /// chooseVoicings L1103: 每个候选先 place, 保留与上一和弦平均跳跃最小的并列候选。
    /// 注意 Java 用 good.cons(...)【头插】累积并列项、首次命中用单元素 list,
    /// 因此 good.first() 取到的是【最后一个】达到最优的候选。这里 insert(at:0) 逐字复刻,
    /// FixedVoicingRNG 取 [0] 才等价于 Java good.first()。
    static func choose(lastChord: [Int], candidates: [Candidate], low: Int, high: Int) -> [Candidate] {
        var good: [Candidate] = []
        var best = 127
        for cand in candidates {
            guard let placed = place(lastChord: lastChord, voicing: cand.notes, low: low, high: high) else { continue }
            let leap = averageLeap(placed + cand.ext, lastChord)
            if leap < best {
                best = leap
                good = [Candidate(notes: placed, ext: cand.ext)]
            } else if leap == best {
                good.insert(Candidate(notes: placed, ext: cand.ext), at: 0)   // cons 头插
            }
        }
        return good
    }
}
