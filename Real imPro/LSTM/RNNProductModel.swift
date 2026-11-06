//
//  RNNProductModel.swift
//  RealimPro
//
//  LSTM P0 —— 网络主体（GenerativeProductModel 的 Swift 实现）：
//    · 两个 RelativeNoteEncoding：IntervalRelativeNoteEncoding（音程 27 类）、
//      ChordRelativeNoteEncoding（和弦 14 类）
//    · 外部输入部件：beat(9) + Position(2) + Chord(12) + last_output(27/14)
//    · Product-of-Experts：两专家概率相乘；温度幂（保持 artic 总和）；
//      后处理；整体归一化；抽样
//    · 39 维绝对音高映射：index0 休止 / index1 延音 / index(2..) = low+(i-2)
//

import Foundation

// MARK: - 编码基类
class RNNRelativeEncoding {
    var activationWidth: Int { 0 }
    func reset() -> [Float] { [] }
    func encode(midi: Int, chordRoot: Int) -> [Float] { [] }
    func probabilities(activations: [Float], chordRoot: Int, low: Int, high: Int) -> [Float] { [] }
    func relativePosition(chordRoot: Int) -> Int { 0 }
}

// MARK: - 音程编码（IntervalRelativeNoteEncoding.java）
final class RNNIntervalEncoding: RNNRelativeEncoding {
    private var relpos: Int
    private let low: Int
    private let high: Int

    init(initialRelpos: Int, low: Int, high: Int) {
        self.relpos = initialRelpos
        self.low = low
        self.high = high
    }

    override var activationWidth: Int { 27 }

    override func reset() -> [Float] {
        // Java 在 reset 随机 relpos；Swift 用构造时给定的初始值（harness 用 Java 导出值）
        return RNNMath.onehot(index: 0, length: 27)
    }

    override func encode(midi: Int, chordRoot: Int) -> [Float] {
        if midi == -1 { return RNNMath.onehot(index: 0, length: 27) }
        if midi == -2 { return RNNMath.onehot(index: 1, length: 27) }
        var delta = midi - relpos
        if delta > 12 || delta < -12 { delta = delta % 12 }
        relpos = midi
        let index = delta + 12 + 2
        return RNNMath.onehot(index: index, length: 27)
    }

    override func probabilities(activations: [Float], chordRoot: Int, low: Int, high: Int) -> [Float] {
        let probs = RNNMath.softmax(activations)   // 27
        let artic = Array(probs[0..<2])
        let rel = Array(probs[2..<27])              // 25

        let startDiff = low - (relpos - 12)
        let startidx = max(0, startDiff)
        let startpadding = max(0, -startDiff)
        let endidx = min(25, high - (relpos - 12))
        let endpadding = max(0, high - (relpos + 12 + 1))

        var cropLen = endidx - startidx
        if cropLen < 0 { cropLen = 0 }
        let safeStart = min(max(startidx, 0), rel.count)
        let safeEnd = min(safeStart + cropLen, rel.count)
        let cropped = Array(rel[safeStart..<safeEnd])

        var padded = artic
        if startpadding > 0 { padded += RNNMath.zeros(startpadding) }
        padded += cropped
        if endpadding > 0 { padded += RNNMath.zeros(endpadding) }

        let s = RNNMath.sum(padded)
        let denom = s == 0 ? 1 : s
        return RNNMath.scale(padded, 1.0 / denom)   // 重归一化（Java:108-109）
    }

    override func relativePosition(chordRoot: Int) -> Int { relpos }
}

// MARK: - 和弦编码（ChordRelativeNoteEncoding.java）
final class RNNChordEncoding: RNNRelativeEncoding {
    override var activationWidth: Int { 14 }

    override func reset() -> [Float] {
        return RNNMath.onehot(index: 0, length: 14)
    }

    override func encode(midi: Int, chordRoot: Int) -> [Float] {
        if midi == -1 { return RNNMath.onehot(index: 0, length: 14) }
        if midi == -2 { return RNNMath.onehot(index: 1, length: 14) }
        var relidx = (midi - chordRoot) % 12
        if relidx < 0 { relidx += 12 }
        return RNNMath.onehot(index: relidx + 2, length: 14)
    }

    override func probabilities(activations: [Float], chordRoot: Int, low: Int, high: Int) -> [Float] {
        let probs = RNNMath.softmax(activations)    // 14
        let artic = Array(probs[0..<2])
        let rel = Array(probs[2..<14])              // 12

        let rolled = RNNMath.roll(rel, distance: chordRoot - low)
        let joinTimes = (high - low + 11) / 12      // = 4
        var tiled: [Float] = []
        tiled.reserveCapacity(joinTimes * rolled.count)
        for _ in 0..<joinTimes { tiled += rolled }
        let full = Array(tiled[0..<(high - low)])
        return RNNMath.join(artic, full)            // 不重归一化
    }

    override func relativePosition(chordRoot: Int) -> Int { chordRoot }
}

// MARK: - 逐步记录（对齐用）
struct RNNStepRecord {
    let soft0: [Float]   // 27
    let soft1: [Float]   // 14
    let map0: [Float]    // 39
    let map1: [Float]    // 39
    let final: [Float]   // 39
    let argmax: Int
}

// MARK: - 随机数（splitmix64，仅用于自由生成抽样）
struct RNNRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }

    mutating func nextUInt64() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextUnit() -> Float {
        Float(nextUInt64() >> 11) / Float(1 << 53)
    }
}

private func sampleIndex(_ rng: inout RNNRandom, _ probs: [Float]) -> Int {
    var r = rng.nextUnit()
    for i in 0..<probs.count {
        r -= probs[i]
        if r < 0 { return i }
    }
    return 0
}

// MARK: - Java 兼容随机源（P1：固定种子逐音对拍，复用已移植 JavaLCG）
struct RNNJavaRNG {
    private var lcg: JavaLCG
    init(seed: Int64) { lcg = JavaLCG(seed: seed) }
    mutating func nextUnit() -> Double { lcg.nextDouble() }
}

// Java NNUtilities.sample 口径，Double 精度逐项减（概率仍为 Float32）。
private func sampleIndexDouble(unit: Double, probs: [Float]) -> Int {
    var r = unit
    for i in probs.indices {
        r -= Double(probs[i])
        if r < 0 { return i }
    }
    return 0
}

private func argmaxOf(_ a: [Float]) -> Int {
    var best = 0
    var bv = a[0]
    for i in 1..<a.count {
        if a[i] > bv { bv = a[i]; best = i }
    }
    return best
}

// MARK: - 网络主体
final class RNNProductNetwork {
    let lowBound: Int
    let highBound: Int

    private let experts: [RNNExpert]
    private let encodings: [RNNRelativeEncoding]
    private var lastEncoded: [[Float]]
    private var postprocessors: [RNNPostprocessor]
    private var exponents: [Float]
    private var rng: RNNRandom
    private var javaRNG: RNNJavaRNG?

    let rectify: RNNRectify
    let merger: RNNMergeRepeated
    let force: RNNForcePlay

    init(file: RNNFile, initialRelpos: Int, spellProvider: @escaping RNNSpellProvider, seed: UInt64 = 12345, javaSeed: Int64? = nil) {
        self.lowBound = file.lowBound
        self.highBound = file.highBound
        self.experts = file.experts.map { RNNExpert(weights: $0) }

        let interval = RNNIntervalEncoding(initialRelpos: initialRelpos, low: file.lowBound, high: file.highBound)
        let chord = RNNChordEncoding()
        self.encodings = [interval, chord]

        self.rectify = RNNRectify(lowBound: file.lowBound, provider: spellProvider)
        self.merger = RNNMergeRepeated(lowBound: file.lowBound)
        self.force = RNNForcePlay()
        self.postprocessors = [rectify, merger, force]

        self.exponents = [1.0, 1.0]
        self.rng = RNNRandom(seed: seed)
        self.javaRNG = javaSeed.map { RNNJavaRNG(seed: $0) }
        self.lastEncoded = encodings.map { $0.reset() }
    }

    func reset() {
        experts.forEach { $0.reset() }
        lastEncoded = encodings.map { $0.reset() }
        rectify.start()
        merger.resetState()
        force.resetState()
    }

    /// 外部输入装配（beat + position + chord + last_output）。
    private func assemble(beat: [Float], relpos: Int, chordRoot: Int, chordType: [Float], lastOutput: [Float]) -> [Float] {
        // PositionInputPart（2 维）
        let delta = Float(highBound - lowBound) / Float(2 - 1)   // 37
        var position: [Float] = []
        for i in 0..<2 {
            var v = Float(i) * delta + Float(lowBound)
            v = Float(relpos) - v
            v = v / delta
            v = abs(v)
            v = 1.0 - v
            if v < 0 { v = 0 }
            position.append(v)
        }
        // ChordInputPart：roll(chordType, chordRoot-relpos)
        let chord = RNNMath.roll(chordType, distance: chordRoot - relpos)
        return RNNMath.join(beat, position, chord, lastOutput)
    }

    private struct ForwardResult {
        let soft: [[Float]]
        let mapped: [[Float]]
        let accum: [Float]
    }

    private func forwardExperts(beat: [Float], chordRoot: Int, chordType: [Float]) -> ForwardResult {
        var soft: [[Float]] = []
        var mapped: [[Float]] = []
        var accum: [Float]?

        for i in 0..<encodings.count {
            let enc = encodings[i]
            let relpos = enc.relativePosition(chordRoot: chordRoot)
            let input = assemble(beat: beat, relpos: relpos, chordRoot: chordRoot, chordType: chordType, lastOutput: lastEncoded[i])
            let activations = experts[i].process(input)

            let rawSoft = RNNMath.softmax(activations)
            var probs = enc.probabilities(activations: activations, chordRoot: chordRoot, low: lowBound, high: highBound)

            // 温度幂 + artic 总和保持（GenerativeProductModel.java:173-177）
            var artic = Array(probs[2..<probs.count])
            let initSum = RNNMath.sum(artic)
            artic = RNNMath.power(artic, exponent: exponents[i])
            var finalSum = RNNMath.sum(artic)
            if finalSum == 0 { finalSum = 1 }
            artic = RNNMath.scale(artic, initSum / finalSum)
            probs = Array(probs[0..<2]) + artic

            soft.append(rawSoft)
            mapped.append(probs)
            if accum == nil { accum = probs } else { accum = RNNMath.multiply(accum!, probs) }
        }
        return ForwardResult(soft: soft, mapped: mapped, accum: accum!)
    }

    private func applyPostAndNormalize(_ accum: [Float]) -> [Float] {
        var v = accum
        for p in postprocessors { v = p.postprocess(v) }
        let s = RNNMath.sum(v)
        let denom = s == 0 ? 1 : s
        return RNNMath.scale(v, 1.0 / denom)
    }

    // MARK: Teacher forcing 步
    func teacherStep(beat: [Float], chord: [Float], teacherNote: Int) -> RNNStepRecord {
        let chordRoot = Int(chord[0])
        let chordType = Array(chord[1..<13])

        let f = forwardExperts(beat: beat, chordRoot: chordRoot, chordType: chordType)
        let final = applyPostAndNormalize(f.accum)
        let am = argmaxOf(final)

        // 回喂教师音
        for i in 0..<encodings.count {
            lastEncoded[i] = encodings[i].encode(midi: teacherNote, chordRoot: chordRoot)
        }
        return RNNStepRecord(soft0: f.soft[0], soft1: f.soft[1],
                             map0: f.mapped[0], map1: f.mapped[1],
                             final: final, argmax: am)
    }

    // MARK: 自由抽样步
    func sampleStep(beat: [Float], chord: [Float]) -> Int {
        let chordRoot = Int(chord[0])
        let chordType = Array(chord[1..<13])

        let f = forwardExperts(beat: beat, chordRoot: chordRoot, chordType: chordType)
        let final = applyPostAndNormalize(f.accum)
        let idx: Int
        if var j = javaRNG {
            idx = sampleIndexDouble(unit: j.nextUnit(), probs: final)
            javaRNG = j
        } else {
            idx = sampleIndex(&rng, final)
        }

        let midi: Int
        if idx == 0 { midi = -1 }
        else if idx == 1 { midi = -2 }
        else { midi = lowBound + (idx - 2) }

        for i in 0..<encodings.count {
            lastEncoded[i] = encodings[i].encode(midi: midi, chordRoot: chordRoot)
        }
        return midi
    }

    // MARK: 整段自由生成（复刻 runGenerate 的休止记账 / force）
    struct Frame { let beat: [Float]; let chord: [Float] }

    func generateTokens(frames: [Frame], maxConsecutiveRests: Int = 480) -> [Int] {
        reset()
        var consecutiveRests = 0
        var tokens: [Int] = []
        tokens.reserveCapacity(frames.count)

        for fr in frames {
            if consecutiveRests >= maxConsecutiveRests { force.forcePlayNext() }
            let note = sampleStep(beat: fr.beat, chord: fr.chord)
            merger.noteWasPlayed(note)
            if note == -1 || (note == -2 && consecutiveRests > 0) {
                consecutiveRests += 10
            } else {
                consecutiveRests = 0
            }
            tokens.append(note)
        }
        return tokens
    }

    // MARK: Teacher forcing 整段（含与 runGenerate 同口径的 merger/force/休止记账）
    struct TeacherFrame { let beat: [Float]; let chord: [Float]; let teacherNote: Int }

    @discardableResult
    func teacherForce(frames: [TeacherFrame], maxConsecutiveRests: Int = 480) -> [RNNStepRecord] {
        reset()
        var consecutiveRests = 0
        var records: [RNNStepRecord] = []
        records.reserveCapacity(frames.count)

        for fr in frames {
            if consecutiveRests >= maxConsecutiveRests { force.forcePlayNext() }
            let rec = teacherStep(beat: fr.beat, chord: fr.chord, teacherNote: fr.teacherNote)
            records.append(rec)
            merger.noteWasPlayed(fr.teacherNote)
            if fr.teacherNote == -1 || (fr.teacherNote == -2 && consecutiveRests > 0) {
                consecutiveRests += 10
            } else {
                consecutiveRests = 0
            }
        }
        return records
    }
}
