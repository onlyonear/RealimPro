//
//  SoloistMelodyGenerator.swift
//  Real imPro · Soloist 运行时（K2-7 生产接入）
//
//  生成核心（方案 C，连接感知 softmin + 真实音符 + K2-7b 音域围栏）：
//  - 节奏与音高都来自大师真实小节（真实音符的音类天然匹配，音类偏差最小）
//  - 音域围栏（十五/十六审）：每小节先把"八度对齐后整小节落在
//      [语料均值中心 - 11, 中心 + 11] 内"的候选筛成合规集，再在合规集内 softmin 选点
//      （约束前置；先筛后选，因此不会出现"选完越界再整段回退"）
//  - R9 兜底：某小节所有候选都装不进窗口时，半宽 +2 逐级放宽（最多 3 次），仍无解则回退
//  - 越界一律判失败，不再把越界音"洗成合法音"（旧 safePitchClassPitch 已删除）
//  - 休止不推进 running；running 跨 point 连续
//  Python 基准（verify_c.py）：T=3.0、3 个独立种子区间逐 Motif 全部零超阈。
//  无等长 outline（或曲式不在白名单）时回退 grammar；R9 安全网在 SoloistSafeRunner。
//

import Foundation

// MARK: - 可注入随机源

protocol SoloistRNG {
    mutating func nextInt(_ upperExclusive: Int) -> Int
    mutating func nextDouble() -> Double
}

struct SystemSoloistRNG: SoloistRNG {
    func nextInt(_ upperExclusive: Int) -> Int {
        guard upperExclusive > 0 else { return 0 }
        return Int.random(in: 0..<upperExclusive)
    }
    func nextDouble() -> Double { Double.random(in: 0..<1) }
}

/// 确定性 RNG：复刻 java.util.Random，测试/对拍用
struct DeterministicSoloistRNG: SoloistRNG {
    private var seed: Int64
    private let mask: Int64 = (1 << 48) - 1
    private let mult: Int64 = 0x5DEECE66D
    private let add: Int64 = 0xB

    init(seed: Int64) {
        self.seed = (seed ^ mult) & mask
    }

    private mutating func next(_ bits: Int32) -> Int32 {
        seed = (seed &* mult &+ add) & mask
        return Int32(truncatingIfNeeded: UInt64(bitPattern: seed) >> (48 - bits))
    }

    mutating func nextInt(_ bound: Int) -> Int {
        guard bound > 0 else { return 0 }
        if bound & (bound - 1) == 0 {
            return Int((Int64(bound) &* Int64(next(31))) >> 31)
        }
        while true {
            let bits = next(31)
            let val = bits % Int32(bound)
            if Int32(bound) - val + (bits - val) >= 0 {
                return Int(val)
            }
        }
    }

    mutating func nextDouble() -> Double {
        let a = Int64(next(26)) << 27
        let b = Int64(next(27))
        return Double(a + b) / Double(1 << 53)
    }
}

// MARK: - 结果

enum SoloistGenerateOutcome: Equatable {
    case solo([PhysicalNote])
    case fallbackToGrammar(reason: String)
}

// MARK: - 生成器

struct SoloistMelodyGenerator {
    let runtime: SoloistRuntime
    /// softmin 温度；默认取该份 runtime 自带的 softminT（本批 3.0），可显式覆盖用于测试
    let softminTemperature: Double

    /// K2-7b 音域围栏半宽（主路径）：窗口 = [center-11, center+11]，等价原版 60~82 的 23 半音
    static let halfWindow = 11
    /// R9 兜底：该小节所有候选都装不进窗口时，逐级放宽
    static let relaxStep = 2
    static let maxRelaxSteps = 3

    /// 音域围栏中心：该份语料全音符绝对 MIDI 均值四舍五入（十五/十六审裁决）
    let registerCenter: Int

    init(runtime: SoloistRuntime, softminTemperature: Double? = nil,
         registerCenter: Int? = nil) {
        self.runtime = runtime
        self.softminTemperature = softminTemperature ?? runtime.softminT
        self.registerCenter = registerCenter ?? runtime.pitchCenter
    }

    func generate(targetMeasures: Int, rng: SoloistRNG,
                  harmonicContext: SoloistHarmonicContext? = nil) -> SoloistGenerateOutcome {
        var rng = rng

        // 1) 精确等长轮廓（白名单之外一律为空 → 回退 grammar）
        let matching = runtime.outlines(measuring: targetMeasures)
        guard !matching.isEmpty else {
            return .fallbackToGrammar(
                reason: "无 \(targetMeasures) 小节等长轮廓（本份可用: "
                    + runtime.effectiveSizes.map { String($0) }.joined(separator: "/")
                    + "）")
        }
        let outline = matching.count == 1 ? matching[0]
            : matching[rng.nextInt(matching.count)]

        var notes: [PhysicalNote] = []
        var running: Int?
        let center = registerCenter
        /// 绝对 slot（solo 起点 = 0，与 roadmap 第 0 拍对齐）；休止同样推进
        var absSlot = 0

        for segment in outline.candidates {
            guard !segment.isEmpty else {
                return .fallbackToGrammar(reason: "某小节候选为空")
            }

            // 2) 约束前置：先筛"整小节平移后落在窗口内"的候选，再在合规集内选点
            var half = Self.halfWindow
            var compliant = compliantCandidates(segment, half: half, running: running, center: center)
            var relax = 0
            while compliant.isEmpty && relax < Self.maxRelaxSteps {
                half += Self.relaxStep
                relax += 1
                compliant = compliantCandidates(segment, half: half, running: running, center: center)
            }
            guard !compliant.isEmpty else {
                return .fallbackToGrammar(reason: "半宽 \(half) 内无合规候选")
            }

            // 3) 只在合规集合内选点（首小节均匀随机；后续 softmin 加权）
            var chosen = compliant[compliant.count - 1]
            if running == nil {
                chosen = compliant[rng.nextInt(compliant.count)]
            } else {
                let weights = compliant.map {
                    exp(-Double($0.connDist) / softminTemperature)
                }
                let total = weights.reduce(0.0, +)
                var r = rng.nextDouble() * total
                for (rec, w) in zip(compliant, weights) {
                    r -= w
                    if r <= 0 { chosen = rec; break }
                }
            }

            // 4) 搬真实音符（按 shift 八度对齐）+ K2-7c 和弦适配；越界即判失败，不做"洗成合法音"
            let point = runtime.points[chosen.idx]
            for (i, ev) in point.events.enumerated() {
                switch ev {
                case .rest(let d):
                    notes.append(PhysicalNote(midiPitch: -1, durationSlots: d,
                                             terminalType: "R"))
                    // 休止不推进 running
                    absSlot += d

                case .tone(_, _, _, let realPitch, _, let d):
                    let rawP = realPitch + chosen.shift
                    var p = rawP
                    // 和弦适配：只动"当前和弦上站不住、且不是有功能趋近音"的音，最多挪到最近合法音
                    if let ctx = harmonicContext,
                       let ch = ctx.chordName(atAbsoluteSlot: absSlot),
                       Coloration.classify(midiPitch: p, chordName: ch) == .foreignTone {
                        let functional = isFunctionalApproach(fromIndex: i, pitch: p,
                                                              shift: chosen.shift,
                                                              point: point, chordName: ch)
                        if !functional,
                           let fixed = ctx.nearestLegalPitch(to: p, chordName: ch,
                                                             lo: center - half, hi: center + half) {
                            p = fixed
                        }
                    }
                    guard p >= 0, p <= 127, p >= center - half, p <= center + half else {
                        return .fallbackToGrammar(reason: "音符越出音域围栏")
                    }
                    notes.append(PhysicalNote(midiPitch: p, durationSlots: d,
                                             terminalType: "X"))
                    // running 用"改音前"的对齐音高：保证选点轨迹与关闭和弦适配时完全一致，
                    // 和弦适配只改发声音高，不改变节奏/轮廓/后续候选集合。
                    running = rawP
                    absSlot += d
                }
            }
        }
        return .solo(notes)
    }

    /// 有功能趋近音：本小节（point）内下一个发声音距当前音 1~2 半音，且该音是同一和弦的和弦音
    private func isFunctionalApproach(fromIndex i: Int, pitch p: Int, shift: Int,
                                      point: SoloistPoint, chordName: String) -> Bool {
        var j = i + 1
        while j < point.events.count {
            if case .tone(_, _, _, let nextReal, _, _) = point.events[j] {
                let next = nextReal + shift
                let dist = abs(next - p)
                guard dist == 1 || dist == 2 else { return false }
                return Coloration.classify(midiPitch: next, chordName: chordName) == .chordTone
            }
            j += 1
        }
        return false
    }

    /// 合规候选集：八度对齐后整小节的 [最低, 最高] 必须整个落在窗口内
    private func compliantCandidates(_ segment: [Int], half: Int, running: Int?,
                                     center: Int) -> [(idx: Int, shift: Int, connDist: Int)] {
        var out: [(idx: Int, shift: Int, connDist: Int)] = []
        out.reserveCapacity(segment.count)
        for c in segment {
            guard c >= 0, c < runtime.points.count else { continue }
            let pt = runtime.points[c]
            let shift: Int
            let anchor: Int
            if let r = running {
                anchor = r
                shift = nearestOctave(pt.firstPitch, to: r) - pt.firstPitch
            } else {
                anchor = center
                shift = nearestOctave(pt.firstPitch, to: center) - pt.firstPitch
            }
            guard let span = transposedSpan(pt, shift: shift) else {
                out.append((c, shift, running == nil ? 0 : abs(pt.firstPitch + shift - anchor)))
                continue    // 全休止小节无音高，视为合规
            }
            guard span.lo >= center - half, span.hi <= center + half else { continue }
            out.append((c, shift, running == nil ? 0 : abs(pt.firstPitch + shift - anchor)))
        }
        return out
    }

    /// 整小节按 shift 平移后的音高范围；全休止返回 nil
    private func transposedSpan(_ pt: SoloistPoint, shift: Int) -> (lo: Int, hi: Int)? {
        var lo = Int.max, hi = Int.min
        for ev in pt.events {
            if case .tone(_, _, _, let realPitch, _, _) = ev {
                lo = min(lo, realPitch + shift)
                hi = max(hi, realPitch + shift)
            }
        }
        return lo == Int.max ? nil : (lo, hi)
    }

    /// 把音高调整到最接近 anchor 的八度（保持音级）
    private func nearestOctave(_ pitch: Int, to anchor: Int) -> Int {
        var p = pitch
        while p - anchor > 6 { p -= 12 }
        while anchor - p > 6 { p += 12 }
        return p
    }
}
