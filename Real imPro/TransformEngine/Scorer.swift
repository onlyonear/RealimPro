import Foundation

extension TransformEngine {
    /// 动机片段打分器，移除硬编码0.5占位，内置和弦音分级打分逻辑，不依赖外部ChordPitchLookupProtocol方法
    struct Scorer {
        var minMotifLength: Int = 2
        var maxMotifLength: Int = 4
        var scoreThreshold: Double = 0.4
        var priorityWeight: Double
        var beatWeight: Double
        var durationWeight: Double
        var metre: [Int]

        init(
            priorityWeight: Double = 1.0,
            beatWeight: Double = 1.0,
            durationWeight: Double = 1.0,
            metre: [Int] = [4,4]
        ) {
            self.priorityWeight = priorityWeight
            self.beatWeight = beatWeight
            self.durationWeight = durationWeight
            self.metre = metre
        }

        func score(trend: [NoteChordPair]) -> Double {
            var total = 0.0
            let totalDur = trend.reduce(0) { $0 + $1.getDuration() }
            var iter = NCPIterator(sequence: trend)
            while let ncp = iter.nextNCP() {
                let p = priorityScore(ncp: ncp)
                let s = strongBeatScore(slot: ncp.slot)
                let d = durationScore(ncp: ncp, fullTrend: trend, totalTrendDur: totalDur)
                total += priorityWeight * p
                total += beatWeight * s
                total += durationWeight * d
            }
            return total
        }

        // 内部手写判断逻辑，不再调用外部isChordTone系列静态方法，彻底消除签名匹配报错
        private func priorityScore(ncp: NoteChordPair) -> Double {
            let chord = ncp.chord
            let midi = ncp.note.midiPitch
            guard midi != -1 else { return 0.0 }
            let pc = midi % 12
            let rootPc = getRootPitchClass(chordName: chord.name)

            let chordFamily = chord.getChordFamily()
            let chordTones = getChordTonePitchClasses(root: rootPc, family: chordFamily)
            let colorTones = getColorTonePitchClasses(root: rootPc, family: chordFamily)
            let scaleTones = getScalePitchClasses(root: rootPc, family: chordFamily)

            if chordTones.contains(pc) {
                return 1.0
            } else if colorTones.contains(pc) {
                return 0.6
            } else if scaleTones.contains(pc) {
                return 0.3
            } else {
                return 0.1
            }
        }

        private func strongBeatScore(slot: Int) -> Double {
            let slotsPerBeat = Constants.slotsPerBeat
            let beatsPerBar = metre[0]
            let barSlots = slotsPerBeat * beatsPerBar
            let strongInterval = barSlots / strongBeatsPerMeasure()
            var raw = 0.0
            if slot % barSlots == 0 { raw = 3.0 }
            else if slot % strongInterval == 0 { raw = 2.0 }
            else if slot % slotsPerBeat == 0 { raw = 1.0 }
            return normalize(score: raw, max: 3.0)
        }

        private func durationScore(ncp: NoteChordPair, fullTrend: [NoteChordPair], totalTrendDur: Int) -> Double {
            let targetPitch = ncp.note.midiPitch
            var sum = 0
            var iter = NCPIterator(sequence: fullTrend)
            while let item = iter.nextNCP() {
                if item.note.midiPitch == targetPitch {
                    sum += item.getDuration()
                }
            }
            return normalize(score: Double(sum), max: Double(totalTrendDur))
        }

        private func normalize(score: Double, max: Double) -> Double {
            guard max != 0 else { return 0 }
            return score / max
        }

        private func strongBeatsPerMeasure() -> Int {
            let b = metre[0]
            if b <= 3 { return 1 }
            else if b % 2 == 0 { return 2 }
            else if b % 3 == 0 { return 3 }
            return 1
        }

        // 解析和弦名字提取根音音级 0~11
        private func getRootPitchClass(chordName: String) -> Int {
            let rootStr = chordName.prefix { c in
                c.isUppercase && c.isLetter || c == "#" || c == "b"
            }
            switch String(rootStr) {
            case "C": return 0
            case "C#", "Db": return 1
            case "D": return 2
            case "D#", "Eb": return 3
            case "E": return 4
            case "F": return 5
            case "F#", "Gb": return 6
            case "G": return 7
            case "G#", "Ab": return 8
            case "A": return 9
            case "A#", "Bb": return 10
            case "B": return 11
            default: return 0
            }
        }

        // 获取对应和弦族根音相对和弦内音音级集合
        private func getChordTonePitchClasses(root: Int, family: ChordFamily) -> Set<Int> {
            let intervals: [Int]
            switch family {
            case .major: intervals = [0,4,7,11]
            case .minor: intervals = [0,3,7,10]
            case .dominant: intervals = [0,4,7,10]
            case .halfDiminished: intervals = [0,3,6,10]
            case .diminished: intervals = [0,3,6,9]
            case .augmented: intervals = [0,4,8]
            case .sus: intervals = [0,5,7]
            case .unknown: intervals = [0,4,7]
            }
            return Set(intervals.map { (root + $0) % 12 })
        }

        // 9/11/13 延伸色彩音
        private func getColorTonePitchClasses(root: Int, family: ChordFamily) -> Set<Int> {
            let intervals = [2,5,9]
            return Set(intervals.map { (root + $0) % 12 })
        }

        // 对应调式自然音阶音集合
        private func getScalePitchClasses(root: Int, family: ChordFamily) -> Set<Int> {
            let intervals: [Int]
            switch family {
            case .major: intervals = [0,2,4,5,7,9,11]
            case .minor: intervals = [0,2,3,5,7,8,10]
            case .dominant: intervals = [0,2,4,5,7,9,10]
            default: intervals = [0,2,4,5,7,9,11]
            }
            return Set(intervals.map { (root + $0) % 12 })
        }
    }
}
