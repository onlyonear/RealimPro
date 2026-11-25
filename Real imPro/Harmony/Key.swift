import Foundation

// MARK: - Key — 调性推导引擎 (P0 · 约120行)
// 调号计算 / 大调-关系小调 / 调内各级和弦推导 (I ii iii IV V vi vii°)
// 无缝对接现有 Roadmap.KeySpan 调性链

struct Key: Equatable {

    /// 主调根音
    let tonic: PitchClass
    /// 调式
    let mode: JazzMode

    // MARK: - 初始化

    init(tonic: PitchClass, mode: JazzMode = .major) {
        self.tonic = tonic
        self.mode = mode
    }

    /// 从 KeySpan 构造 (现有数据无缝对接)
    init(keySpan: KeySpan) {
        self.tonic = PitchClass(index: keySpan.rootPC)
        self.mode = keySpan.mode
    }

    /// 默认: C major
    static let defaultKey = Key(tonic: PitchClass(index: 0), mode: .major)

    // MARK: - 调号

    /// 调号升降号数量 (正=#, 负=b)
    var accidentals: Int {
        let base: [Int: Int] = [
            0:0, 1:-5, 2:2, 3:-3, 4:4, 5:-1, 6:6, 7:1, 8:-4, 9:3, 10:-2, 11:5
        ]
        var acc = base[tonic.index] ?? 0
        if mode == .minor { acc -= 3 }  // 关系小调: 相同调号-3
        return acc
    }

    /// 关系大调 (仅小调时有效)
    var relativeMajor: Key {
        guard mode == .minor else { return self }
        return Key(tonic: PitchClass(index: tonic.index + 3), mode: .major)
    }

    /// 关系小调 (仅大调时有效)
    var relativeMinor: Key {
        guard mode == .major else { return self }
        return Key(tonic: PitchClass(index: tonic.index - 3), mode: .minor)
    }

    // MARK: - 调内音阶

    /// 调内音阶半音音程 (相对主调根音, 0-11)
    var scaleIntervals: [Int] {
        switch mode {
        case .major:
            return [0, 2, 4, 5, 7, 9, 11]               // Ionian (Major)
        case .minor:
            return [0, 2, 3, 5, 7, 8, 10]               // Natural minor (Aeolian)
        case .dominant:
            return [0, 2, 4, 5, 7, 9, 10]               // Mixolydian
        case .dorian:
            return [0, 2, 3, 5, 7, 9, 10]               // Dorian (大六度特征)
        case .phrygian:
            return [0, 1, 3, 5, 7, 8, 10]               // Phrygian (小二度特征)
        case .lydian:
            return [0, 2, 4, 6, 7, 9, 11]               // Lydian (增四度#11特征)
        case .locrian:
            return [0, 1, 3, 5, 6, 8, 10]               // Locrian (减五度特征)
        case .unknown:
            return [0, 2, 4, 5, 7, 9, 11]               // default = Major
        }
    }

    /// 调内音高集合 (MIDI 绝对音高, 3个八度)
    func scalePitches(in range: ClosedRange<Int> = 48...84) -> [Int] {
        var result: [Int] = []
        for interval in scaleIntervals {
            let pc = (tonic.index + interval) % 12
            for octave in stride(from: (range.lowerBound/12)*12, through: (range.upperBound/12)*12, by: 12) {
                let pitch = pc + octave
                if range.contains(pitch) { result.append(pitch) }
            }
        }
        return result.sorted()
    }

    // MARK: - 调内和弦推导

    /// 调内各级三和弦: I, ii, iii, IV, V, vi, vii°
    var diatonicTriads: [(degree: String, root: PitchClass, quality: String)] {
        let intervals = scaleIntervals
        let degrees: [String]
        switch mode {
        case .major:    degrees = ["I", "ii", "iii", "IV", "V", "vi", "vii°"]
        case .minor:    degrees = ["i", "ii°", "bIII", "iv", "v", "bVI", "bVII"]
        case .dorian:   degrees = ["i", "ii", "bIII", "IV", "v", "vi°", "bVII"]
        case .phrygian: degrees = ["i", "bII", "bIII", "iv", "v°", "bVI", "bvii"]
        case .lydian:   degrees = ["I", "II", "iii", "#iv°", "V", "vi", "vii"]
        case .locrian:  degrees = ["i°", "bII", "biii", "iv", "bV", "bVI", "bvii"]
        default:        degrees = ["I", "ii", "iii", "IV", "V", "vi", "vii°"]
        }
        var result: [(String, PitchClass, String)] = []
        for (i, degree) in degrees.enumerated() {
            let root = PitchClass(index: tonic.index + intervals[i % 7])
            let q = degree.contains("°") ? "dim" : (degree == degree.uppercased() ? "maj" : "min")
            result.append((degree, root, q))
        }
        return result
    }

    /// 调内各级七和弦: Imaj7, ii7, iii7, IVmaj7, V7, vi7, viiø7
    var diatonicSeventhChords: [(degree: String, root: PitchClass, quality: String)] {
        let triads = diatonicTriads
        let seventhQuals = mode == .major
            ? ["maj7", "min7", "min7", "maj7", "7", "min7", "m7b5"]
            : ["min7", "m7b5", "maj7", "min7", "min7", "maj7", "7"]
        return zip(triads, seventhQuals).map { (triad, sq) in
            (triad.degree, triad.root, sq)
        }
    }

    // MARK: - 延伸音查询 (供 GuideLineGenerator 导音选音)

    /// 调内可用延伸音 (相对主调, 半音)
    var availableColorTones: [Int] {
        let scale = Set(scaleIntervals)
        // 9/11/13 = 音阶中第2/4/6级 (0-based: 2,5,9)
        let colorCandidates = [2, 5, 9]
        return colorCandidates.filter { scale.contains(($0 + tonic.index) % 12) }
    }

    // MARK: - 和弦归属判定

    /// 给定和弦是否属于此调
    func contains(chordName: String) -> Bool {
        let chordBlock = ChordBlock(name: chordName, duration: 0)
        let rootName = String(chordName.prefix { $0.isLetter && $0.isUppercase || $0 == "#" || $0 == "b" })
        let rootPC: PitchClass = PitchClass(noteName: rootName)
        // 检查根音是否在调内
        return scaleIntervals.map { (tonic.index + $0) % 12 }.contains(rootPC.index)
    }
}

// MARK: - JazzRoadmap 扩展: 获取当前小节调性

extension JazzRoadmap {
    /// 按拍数获取当前 Key
    func key(at beat: Double) -> Key {
        if let ks = keyMap.keySpan(at: beat) {
            return Key(keySpan: ks)
        }
        return .defaultKey
    }
}
