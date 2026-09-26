//
//  MotifSeedGenerator.swift
//  RealimPro
//
//  ThemeWeaver M5：Develop 模式「首小节示例动机」自动生成器（纯函数、确定性、无 UI）。
//  ── 设计约束（用户拍板）────────────────────────────────────────
//  · 只【读取】现成 GrammarNoteConverter.getChordTonesWithDegree 取根/三/五/七音，
//    不修改 GrammarNoteConverter（V-1tap 150 行逐音 identical 不能破）。
//  · 不另写「夹进 60–82」：取音时直接传 minPitch=60/maxPitch=82，返回值本就在域内；
//    摆放期归域仍只由 ThemeWeaverEngine.adjustToFit 负责（全链路唯一归域器）。
//  · 只用已移植的 JavaLCG 做确定性选择，不引入任何新随机源；同 seed/同和弦 → 同一动机。
//  · 每个节奏模板合计严格 = 一小节 slots（4/4=480、3/4=360），含三连/附点模板。
//  · 缺和弦 / NC / N.C. → 用当前调主音大三和弦兜底，保证不崩、时长守恒。
//

import Foundation

enum MotifSeedGenerator {

    /// 主题发展硬音域（与 ThemeWeaverConfig 默认一致）
    static let minPitch = 60
    static let maxPitch = 82
    private static let slotsPerBeat = 120   // 1 拍 = 120 slots（全音符 480）
    /// 选音中心：同一度数有多个八度候选时，取最靠近它的（并列取较低，确定性）
    private static let melodicCenter = 70

    /// 单个节奏步：度数诉求 + 时值 slots；degree=nil 表示休止
    private struct Step {
        let degree: ChordDegree?
        let slots: Int
    }

    // MARK: 节奏×度数骨架模板（合计严格守恒）
    // 度数：.third/.seventh 突出，落音只用 .root/.third/.fifth 稳定音
    private static let templates44: [[Step]] = [
        // T1 摇摆八分：60+60+120+60+60+120 = 480
        [Step(degree:.third,slots:60), Step(degree:.seventh,slots:60), Step(degree:.fifth,slots:120),
         Step(degree:.third,slots:60), Step(degree:.fifth,slots:60), Step(degree:.root,slots:120)],
        // T2 十六分 + 附点四分(180)：30+30+60+180+60+120 = 480
        [Step(degree:.third,slots:30), Step(degree:.seventh,slots:30), Step(degree:.third,slots:60),
         Step(degree:.fifth,slots:180), Step(degree:.seventh,slots:60), Step(degree:.root,slots:120)],
        // T3 三连（八连=40，自动判 tuplet=3）：40*6 +120+120 = 480
        [Step(degree:.third,slots:40), Step(degree:.seventh,slots:40), Step(degree:.fifth,slots:40),
         Step(degree:.third,slots:40), Step(degree:.seventh,slots:40), Step(degree:.fifth,slots:40),
         Step(degree:.fifth,slots:120), Step(degree:.root,slots:120)],
        // T4 含休止：60+60+60+30+30+60(休)+60+120 = 480
        [Step(degree:.third,slots:60), Step(degree:.seventh,slots:60), Step(degree:.fifth,slots:60),
         Step(degree:.third,slots:30), Step(degree:.seventh,slots:30), Step(degree:nil,slots:60),
         Step(degree:.fifth,slots:60), Step(degree:.root,slots:120)]
    ]

    private static let templates34: [[Step]] = [
        // U1：60+60+120+120 = 360
        [Step(degree:.third,slots:60), Step(degree:.seventh,slots:60),
         Step(degree:.fifth,slots:120), Step(degree:.root,slots:120)],
        // U2 三连：40*3 +60+60+120 = 360
        [Step(degree:.third,slots:40), Step(degree:.seventh,slots:40), Step(degree:.fifth,slots:40),
         Step(degree:.seventh,slots:60), Step(degree:.fifth,slots:60), Step(degree:.root,slots:120)],
        // U3 附点：30+30+180+120 = 360
        [Step(degree:.third,slots:30), Step(degree:.seventh,slots:30),
         Step(degree:.fifth,slots:180), Step(degree:.root,slots:120)]
    ]

    /// 生成一条满一小节的示例动机
    /// - Parameters:
    ///   - firstChord: 第一小节首个有效和弦；nil / 空 / NC / N.C. 走主音兜底
    ///   - fallbackTonicPC: 当前调主音音级 0-11
    ///   - beatsPerMeasure: 每小节拍数（4→480，3→360，其余按 n*120）
    ///   - seed: 确定性种子（"换一个"递增）
    static func make(firstChord: String?,
                     fallbackTonicPC: Int,
                     beatsPerMeasure: Int,
                     seed: Int64) -> [PhysicalNote] {
        let measureSlots = max(1, beatsPerMeasure) * slotsPerBeat
        let pool = buildDegreePool(firstChord: firstChord, fallbackTonicPC: fallbackTonicPC)

        // 确定性挑模板：3/4 用 34 组，其余（含 4/4、6/8 等）用 44 组
        let templates = beatsPerMeasure == 3 ? templates34 : templates44
        // 注意：JavaLCG.nextInt(2 的幂) 走高位快路径，连续小 seed 第一次抽取会落同一桶；
        // "换一个"是计数 +1，故先用 Knuth 黄金奇数把计数打散（仍是 JavaLCG、确定性、无新随机源）
        let mixedSeed = seed &* 2654435761
        var rng = JavaLCG(seed: mixedSeed)
        let idx = Int(rng.nextInt(bound: Int32(templates.count)))
        let template = templates[max(0, min(idx, templates.count - 1))]

        var out: [PhysicalNote] = []
        out.reserveCapacity(template.count)
        for step in template {
            guard let deg = step.degree else {
                out.append(PhysicalNote(midiPitch: -1, durationSlots: step.slots))  // 休止
                continue
            }
            let pitch = pickPitch(degree: deg, from: pool)
            out.append(PhysicalNote(midiPitch: pitch, durationSlots: step.slots))
        }
        // 守恒断言（Release 也保留为轻量校正：若模板被误改导致不足，用落音补足，超出则截到 measureSlots）
        return normalize(notes: out, toMeasureSlots: measureSlots, pool: pool)
    }

    // MARK: - 取音
    /// 度数→该度数在 60–82 内的全部候选音高
    private static func buildDegreePool(firstChord: String?, fallbackTonicPC: Int) -> [ChordDegree: [Int]] {
        let clean = firstChord?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if clean.isEmpty || clean == "NC" || clean == "N.C." {
            // 主音大三和弦兜底（根/三/五，跨八度铺满 60–82）
            var pool: [ChordDegree: [Int]] = [.root: [], .third: [], .fifth: []]
            for oct in stride(from: (minPitch/12)*12, through: (maxPitch/12)*12, by: 12) {
                let r = (fallbackTonicPC % 12 + 12) % 12 + oct
                let t = ((fallbackTonicPC + 4) % 12) + oct
                let f = ((fallbackTonicPC + 7) % 12) + oct
                if r >= minPitch && r <= maxPitch { pool[.root]!.append(r) }
                if t >= minPitch && t <= maxPitch { pool[.third]!.append(t) }
                if f >= minPitch && f <= maxPitch { pool[.fifth]!.append(f) }
            }
            return pool
        }
        let labeled = GrammarNoteConverter.getChordTonesWithDegree(chordName: clean,
                                                                    minPitch: minPitch, maxPitch: maxPitch)
        var pool: [ChordDegree: [Int]] = [:]
        for item in labeled {
            pool[item.degree, default: []].append(item.pitch)
        }
        return pool
    }

    /// 取指定度数最靠近旋律中心的音；该度数缺失时按爵士优先级回退（七→五→根，三→根，五→根）
    private static func pickPitch(degree: ChordDegree, from pool: [ChordDegree: [Int]]) -> Int {
        let fallbackOrder: [ChordDegree]
        switch degree {
        case .seventh: fallbackOrder = [.seventh, .fifth, .third, .root]
        case .third:   fallbackOrder = [.third, .root, .fifth]
        case .fifth:   fallbackOrder = [.fifth, .root, .third]
        case .root:    fallbackOrder = [.root, .fifth, .third]
        default:       fallbackOrder = [degree, .root, .fifth, .third]
        }
        for d in fallbackOrder {
            if let cands = pool[d], !cands.isEmpty {
                return closestToCenter(cands)
            }
        }
        // 理论不可达：任何和弦至少有根音；再兜底返回域中心
        return melodicCenter
    }

    private static func closestToCenter(_ cands: [Int]) -> Int {
        let sorted = cands.sorted()
        var best = sorted[0]
        var bestDist = abs(best - melodicCenter)
        for p in sorted.dropFirst() {
            let d = abs(p - melodicCenter)
            if d < bestDist { best = p; bestDist = d }   // 严格小于 → 并列保留较低者
        }
        return best
    }

    /// 守恒兜底：模板总时长应恰为一小节；不足用稳定落音(根)补足，超出截断最后一步到边界
    private static func normalize(notes: [PhysicalNote], toMeasureSlots measureSlots: Int,
                                  pool: [ChordDegree: [Int]]) -> [PhysicalNote] {
        var total = notes.reduce(0) { $0 + $1.durationSlots }
        var result = notes
        if total > measureSlots {
            var acc = 0
            var trimmed: [PhysicalNote] = []
            for n in result {
                if acc + n.durationSlots > measureSlots {
                    let remain = measureSlots - acc
                    if remain > 0 { trimmed.append(PhysicalNote(midiPitch: n.midiPitch, durationSlots: remain)) }
                    acc = measureSlots
                    break
                }
                trimmed.append(n); acc += n.durationSlots
            }
            result = trimmed; total = acc
        }
        if total < measureSlots {
            let root = pickPitch(degree: .root, from: pool)
            result.append(PhysicalNote(midiPitch: root, durationSlots: measureSlots - total))
        }
        return result
    }
}
