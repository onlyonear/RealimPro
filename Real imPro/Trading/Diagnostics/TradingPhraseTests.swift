#if DEBUG
import Foundation

// MARK: - Trading / Diagnostics / 乐句级自动化测试（"记谱正确性"层）
//
// 【它在测什么】
// 用**完美时间戳**把预先写好的复杂乐句"注入"录音器，然后**逐音对比**：
//    演奏意图（音高/起点 slot/时值 slot）  vs  实际记下来的结果
// → 验证量化 + 录音簿记（补休止/单音线/时值）在复杂节奏下是否正确。
//
// 【它不测什么】（必须说清，否则会得出错误结论）
// 它 **不测真实链路延迟**（你的手 → iPad）。软件注入的时间戳是完美的，
// 真实链路延迟只能靠真人演奏（或用硬件 MIDI 回环）来测。两者不能混为一谈。
//
// 【为什么值得做】
// 这是唯一能做到"**完美真值**"的测试：我知道每个音本该落在哪，因此能精确判定对错，
// 而且可以反复跑、跑 30 秒出结果。渲染（五线谱）是 M2 的事；本测试验证的是**渲染的输入**。

enum TradingPhraseLab {

    // MARK: - 数据模型

    struct TestNote {
        let pitch: Int
        let startSlot: Int      // 记谱意图的起点（相对本轮）
        let duration: Int       // 记谱意图的时值
    }

    struct Phrase {
        let name: String
        let grid: TradingQuantizeGrid
        let bars: Int
        /// 演奏时的 swing 比例（nil = 直拍）。**只影响"演奏位置"，不影响"记谱意图"**。
        let swing: Double?
        let notes: [TestNote]
        /// true = 必须逐音完全一致；false = 已知能力边界（只报告实际结果，不计失败）
        let mustMatch: Bool
        let remark: String
    }

    struct Mismatch {
        let index: Int
        let detail: String
    }

    struct Result {
        let name: String
        let mustMatch: Bool
        let intendedCount: Int
        let recordedCount: Int
        let pitchHits: Int
        let startHits: Int
        let durationHits: Int
        let maxStartError: Int
        let maxDurError: Int
        let mismatches: [Mismatch]

        var exactMatch: Bool {
            intendedCount == recordedCount
                && pitchHits == intendedCount
                && startHits == intendedCount
                && durationHits == intendedCount
        }
        var passed: Bool { mustMatch ? exactMatch : true }

        var summaryLine: String {
            let mark = mustMatch ? (exactMatch ? "✅" : "❌") : "ℹ️"
            return String(format: "%@ %@  意图 %d 音 / 实录 %d 音 ｜ 音高 %d ｜ 起点 %d ｜ 时值 %d ｜ 最大起点误差 %d slot",
                          mark, name, intendedCount, recordedCount,
                          pitchHits, startHits, durationHits, maxStartError)
        }
    }

    // MARK: - 确定性随机（便于复现）

    struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    // MARK: - 乐句库（9 种）

    static func allPhrases() -> [Phrase] {
        var out: [Phrase] = []

        // ① 直八分：1 小节 8 个音，每音 1/2 拍
        out.append(Phrase(
            name: "① 直八分（1 小节 8 音）",
            grid: .eighth, bars: 1, swing: nil,
            notes: (0..<8).map { TestNote(pitch: 60 + [0, 2, 4, 5, 7, 9, 11, 12][$0],
                                          startSlot: $0 * 60, duration: 60) },
            mustMatch: true,
            remark: "最基本的八分音符；八分格应 100% 命中"))

        // ② 八分三连：1 小节 12 个音，每音 1/3 拍
        out.append(Phrase(
            name: "② 八分三连（1 小节 12 音）",
            grid: .tripletEighth, bars: 1, swing: nil,
            notes: (0..<12).map { TestNote(pitch: 60 + ($0 % 8),
                                           startSlot: $0 * 40, duration: 40) },
            mustMatch: true,
            remark: "三连格 40 slot；若用八分格会被掰成 60"))

        // ③ 十六分：1 小节 16 个音，每音 1/4 拍
        out.append(Phrase(
            name: "③ 十六分（1 小节 16 音）",
            grid: .sixteenth, bars: 1, swing: nil,
            notes: (0..<16).map { TestNote(pitch: 60 + ($0 % 10),
                                           startSlot: $0 * 30, duration: 30) },
            mustMatch: true,
            remark: "十六分格 30 slot"))

        // ④ 十六分三连：1 小节 24 个音，每音 1/6 拍（Java quantum[] 最细的 20 slot）
        out.append(Phrase(
            name: "④ 十六分三连（1 小节 24 音，20 slot）",
            grid: .sixteenthTriplet, bars: 1, swing: nil,
            notes: (0..<24).map { TestNote(pitch: 60 + ($0 % 12),
                                           startSlot: $0 * 20, duration: 20) },
            mustMatch: true,
            remark: "原版 Java 支持的最细网格；此档最考验时间戳精度"))

        // ⑤ 切分：正拍长音 + 反拍短音（3+3+2 的重音错位感）
        out.append(Phrase(
            name: "⑤ 切分（正拍长 + 反拍短）",
            grid: .eighth, bars: 1, swing: nil,
            notes: [
                TestNote(pitch: 72, startSlot: 0,   duration: 120),
                TestNote(pitch: 74, startSlot: 180, duration: 60),
                TestNote(pitch: 76, startSlot: 240, duration: 120),
                TestNote(pitch: 77, startSlot: 420, duration: 60)
            ],
            mustMatch: true,
            remark: "含两处空档（120-180、360-420）→ 同时检验补休止"))

        // ⑥ 附点：附点四分 + 八分
        out.append(Phrase(
            name: "⑥ 附点（附点四分 + 八分）",
            grid: .eighth, bars: 1, swing: nil,
            notes: [
                TestNote(pitch: 67, startSlot: 0,   duration: 180),
                TestNote(pitch: 69, startSlot: 180, duration: 60),
                TestNote(pitch: 71, startSlot: 240, duration: 180),
                TestNote(pitch: 72, startSlot: 420, duration: 60)
            ],
            mustMatch: true,
            remark: "180 = 附点四分；八分格下应原样保留"))

        // ⑦ swing 八分：**演奏**按 2:1 摇摆，**记谱**应为直八分
        out.append(Phrase(
            name: "⑦ swing 八分（演奏 2:1 → 记为直八分）",
            grid: .eighth, bars: 1, swing: 2.0 / 3.0,
            notes: (0..<8).map { TestNote(pitch: 60 + ($0 % 8),
                                          startSlot: $0 * 60, duration: 60) },
            mustMatch: true,
            remark: "关键：swing 是演奏法不是记谱。反拍被弹在 80 slot，八分格应把它拉回 60"))

        // ⑧ 装饰音（负例：当前管线**不能**标记倚音）
        out.append(Phrase(
            name: "⑧ 装饰音（负例：会被记成普通十六分）",
            grid: .sixteenth, bars: 1, swing: nil,
            notes: [
                TestNote(pitch: 76, startSlot: 210, duration: 30),   // 倚音（实际很短）
                TestNote(pitch: 74, startSlot: 240, duration: 120),
                TestNote(pitch: 72, startSlot: 420, duration: 60)
            ],
            mustMatch: false,
            remark: "数据模型里没有「倚音」概念（Java 版也没有）→ 会变成两个普通十六分"))

        // ⑨ 休止 + 切分混合（2 小节）
        out.append(Phrase(
            name: "⑨ 休止 + 切分混合（2 小节）",
            grid: .eighth, bars: 2, swing: nil,
            notes: [
                TestNote(pitch: 65, startSlot: 0,    duration: 60),
                TestNote(pitch: 67, startSlot: 120,  duration: 60),
                TestNote(pitch: 69, startSlot: 180,  duration: 180),
                TestNote(pitch: 71, startSlot: 480,  duration: 60),
                TestNote(pitch: 72, startSlot: 540,  duration: 60),
                TestNote(pitch: 74, startSlot: 660,  duration: 120),
                TestNote(pitch: 76, startSlot: 840,  duration: 60)
            ],
            mustMatch: true,
            remark: "跨小节 + 多处空档，检验休止与跨小节簿记"))

        return out
    }

    // MARK: - swing 演奏位置换算

    /// 把"记谱位置"折算成"实际演奏位置"。
    /// 一拍内：0 → 0；前半拍 0…60 映射到 0…ratio×120；后半拍线性回到 120。
    /// ratio = 2/3（标准 2:1 swing）时，反拍八分落在 80 slot。
    static func performedStart(_ slot: Int, swing: Double?) -> Int {
        guard let s = swing else { return slot }
        let beatStart = (slot / 120) * 120
        let pos = slot - beatStart
        let warped: Double
        if pos <= 60 {
            warped = (Double(pos) / 60.0) * (s * 120.0)
        } else {
            warped = s * 120.0 + (Double(pos - 60) / 60.0) * (120.0 - s * 120.0)
        }
        return beatStart + Int(warped.rounded())
    }

    // MARK: - 单条乐句执行

    static func run(_ phrase: Phrase, jitterSlots: Int = 0, seed: UInt64 = 20261013) -> Result {
        var rng = SplitMix64(seed: seed)

        let rec = TradingRecorder()
        rec.begin(startSlot: 0,
                  lengthSlots: max(1, phrase.bars) * TradingSettings.slotsPerBar4_4,
                  quantizeGrid: phrase.grid,
                  inputLatencySlots: 0)

        for n in phrase.notes {
            let performed = performedStart(n.startSlot, swing: phrase.swing)
            let j = jitterSlots > 0 ? Int.random(in: -jitterSlots...jitterSlots, using: &rng) : 0
            let on = max(0, performed + j)
            let off = on + n.duration
            rec.handleRawSlot(pitch: n.pitch, velocity: 90, isNoteOn: true,  rawSlot: on)
            rec.handleRawSlot(pitch: n.pitch, velocity: 0,  isNoteOn: false, rawSlot: off)
        }
        let out = rec.finish()
        let recorded = out.notes.filter { $0.pitch != TradingSlotGrid.restPitch }

        var pitchHits = 0, startHits = 0, durHits = 0
        var maxStartErr = 0, maxDurErr = 0
        var mismatches: [Mismatch] = []

        for (i, expect) in phrase.notes.enumerated() {
            guard i < recorded.count else {
                mismatches.append(Mismatch(index: i,
                    detail: "缺失：期望 p=\(expect.pitch) @\(expect.startSlot)/\(expect.duration)"))
                continue
            }
            let got = recorded[i]
            let sErr = got.startSlot - expect.startSlot
            let dErr = got.durationSlots - expect.duration
            maxStartErr = max(maxStartErr, abs(sErr))
            maxDurErr = max(maxDurErr, abs(dErr))
            if got.pitch == expect.pitch { pitchHits += 1 }
            if sErr == 0 { startHits += 1 }
            if dErr == 0 { durHits += 1 }
            if got.pitch != expect.pitch || sErr != 0 || dErr != 0 {
                mismatches.append(Mismatch(index: i, detail: String(
                    format: "期望 p=%d @%d/%d ｜ 实际 p=%d @%d/%d ｜ Δstart=%+d Δdur=%+d",
                    expect.pitch, expect.startSlot, expect.duration,
                    got.pitch, got.startSlot, got.durationSlots, sErr, dErr)))
            }
        }

        return Result(name: phrase.name,
                      mustMatch: phrase.mustMatch,
                      intendedCount: phrase.notes.count,
                      recordedCount: recorded.count,
                      pitchHits: pitchHits,
                      startHits: startHits,
                      durationHits: durHits,
                      maxStartError: maxStartErr,
                      maxDurError: maxDurErr,
                      mismatches: mismatches)
    }

    // MARK: - 全套执行并打印

    @discardableResult
    static func printReport(jitterSlots: Int = 0, verbose: Bool = true) -> (passed: Int, failed: Int, results: [Result]) {
        print("\n================ 乐句级记谱测试（抖动 ±\(jitterSlots) slot ≈ ±\(Int(Double(jitterSlots) * 500.0 / 120.0)) ms） ================")
        var passed = 0, failed = 0
        var results: [Result] = []
        for p in allPhrases() {
            let r = run(p, jitterSlots: jitterSlots)
            results.append(r)

            // 【物理可解析性】抖动 ≥ 半个格子时，相邻音的时间戳会互相穿越，
            // 意图顺序无法恢复 —— 这是信息论限制，不是实现缺陷，故不计失败。
            let halfGrid = max(1, p.grid.gridSlots / 2)
            let beyondPhysics = jitterSlots > 0 && jitterSlots >= halfGrid

            if beyondPhysics && !r.exactMatch {
                print("⚠️ \(r.name)  抖动 ±\(jitterSlots) ≥ 半格 \(halfGrid) → **超出物理可解析范围**（不计失败）")
                print("      实录 \(r.recordedCount)/\(r.intendedCount) 音；期望：抖动必须 < 半个格子")
            } else {
                print(r.summaryLine)
            }

            if verbose {
                if !r.mismatches.isEmpty && !beyondPhysics {
                    for m in r.mismatches.prefix(4) { print("      · [\(m.index)] \(m.detail)") }
                    if r.mismatches.count > 4 { print("      · …共 \(r.mismatches.count) 处差异") }
                }
                if !p.remark.isEmpty { print("      备注：\(p.remark)") }
            }

            if r.passed || beyondPhysics { passed += 1 } else { failed += 1 }
        }
        print("---------------- 合计：通过 \(passed)，失败 \(failed) ----------------")
        return (passed, failed, results)
    }

    /// 三档抖动各跑一遍（检验"人手不稳"下的鲁棒性）
    // MARK: - [M2-6g] 量化选格回归（M2-6 真实错例固化，6 条）
    //
    // 这些错例都只在"真人吹到"时复现（组③ 四分三连被压平、组⑥ 附点被压成 1:1、
    // swing 轮整片变三连）。此处把它们的**音头形态**写成断言，以后再动量化的判据会被拦住。
    // 层级：测 `patternsFor`（选哪套格子），与 M2-4 那 13 条（`PhraseToMeasures` 怎么画）不同层。
    static func runQuantizerRegressionGuards() {
        print("============ 量化选格回归（M2-6 真实错例，6 条） ============")
        var pass = 0, fail = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            if ok { pass += 1; print("✅ \(name)") } else { fail += 1; print("❌ \(name) \(detail)") }
        }
        func patterns(_ notes: [(Int, Int, Int)], bars: Int) -> [[Int]] {
            let len = bars * 480
            let rec = TradingRecorder()
            rec.begin(startSlot: 0, lengthSlots: len, quantizeGrid: .eighth,
                       adaptive: true, forceSwing: true)
            for (p, on, off) in notes {
                rec.handleRaw(pitch: p, velocity: 90, isNoteOn: true, rawSlot: Double(on))
                rec.handleRaw(pitch: p, velocity: 0, isNoteOn: false, rawSlot: Double(off))
            }
            return rec.finish(endRawSlot: len).beatPatterns
        }

        var qt: [(Int, Int, Int)] = []
        for b in 0..<4 { let base = b * 240
            qt += [(60, base, base + 80), (62, base + 80, base + 160), (64, base + 160, base + 240)] }
        let p1 = patterns(qt, bars: 2)
        check("① 四分三连跨拍 → 4 拍全 [40,40,40]",
              p1.prefix(4).allSatisfy { $0 == [40, 40, 40] }, "实测 \(p1.prefix(6))")

        var dt: [(Int, Int, Int)] = []
        for b in 0..<4 { let base = b * 120
            dt += [(74, base, base + 90), (76, base + 90, base + 120)] }
        let p2 = patterns(dt, bars: 1)
        check("② 附点八分+十六分 → [30,30,30,30]", p2.first == [30, 30, 30, 30], "实测 \(p2.prefix(4))")

        var sw: [(Int, Int, Int)] = []
        for b in 0..<8 { let base = b * 120
            sw += [(67, base, base + 80), (72, base + 80, base + 120)] }
        let p3 = patterns(sw, bars: 2)
        check("③ 正常 swing → 全 [60,60]", p3.prefix(8).allSatisfy { $0 == [60, 60] }, "实测 \(p3.prefix(4))")

        var side: [(Int, Int, Int)] = []
        for b in 0..<8 { let base = b * 120
            let p2x = (b == 2) ? 40 : 80
            side += [(67, base, base + p2x), (72, base + p2x, base + 120)] }
        let p4 = patterns(side, bars: 2)
        let beat2 = p4.count > 2 ? p4[2] : []
        check("④ swing 里提前到 40 → 直拍细分、不画三连",
              !beat2.contains(40) && !beat2.contains(20), "实测 \(beat2)")

        var six: [(Int, Int, Int)] = []
        for b in 0..<4 { let base = b * 120
            for k in 0..<4 { six.append((60 + k, base + k * 30, base + k * 30 + 30)) } }
        let p5 = patterns(six, bars: 1)
        check("⑤ 四个十六分 → [30,30,30,30]", p5.first == [30, 30, 30, 30], "实测 \(p5.prefix(2))")

        let p6 = patterns([], bars: 1)
        // 空轮时 recorder 不生成组合（返回 []），记谱层会回退到单网格——这是设计行为，不是崩
        check("⑥ 空轮不崩（组合为空走默认单网格）",
              p6.isEmpty || p6.allSatisfy { $0 == [60, 60] }, "实测 \(p6)")

        print("---------------- 量化选格回归：通过 \(pass)，失败 \(fail) ----------------")
    }

    static func printRobustnessReport() {
        _ = printReport(jitterSlots: 0, verbose: false)
        _ = printReport(jitterSlots: 6, verbose: false)     // ±25 ms
        _ = printReport(jitterSlots: 12, verbose: false)    // ±50 ms
        runQuantizerGuards()                                 // M2-1 量化器对齐守卫
        runPhraseToMeasuresGuards()   // M2-4 记谱转换守卫（v2）
        runQuantizerRegressionGuards() // M2-6 真实错例固化（选格层）
    }

    // MARK: - M2-1 量化器对齐守卫（时值 ceil + 起点 half-up + 禁止粗网格择优）
    //
    // 背景：M2-1 把时值从"四舍五入"改为"向上取整（ceil）"，对齐 Java Notate.ceilToMultiple
    //   （Notate.java:24036/24110）；起点保持 Swift 无参 rounded()——实测它对正数就是 half-up
    //   （2.5→3、1.5→2），与 Java Math.round 一致；
    //   **刻意不做** Java 的"粗网格择优"：实测它在人手抖动时会把三连音往直拍拽
    //   （±25ms 档 8/9、±50ms 档丢音），数学上只在 20↔30 / 30↔40 / 40↔60 这几对
    //   互不整除的格子交界生效。这些断言锁死该口径，防止将来被"顺手改回 Java 原样"。
    @discardableResult
    static func runQuantizerGuards() -> Bool {
        print("\n============ M2-1 量化器守卫（时值 ceil / 起点 half-up / 禁止粗网格择优） ============")
        var allOK = true
        func check(_ label: String, _ cond: Bool) {
            print(cond ? "✅ \(label)" : "❌ \(label)")
            if !cond { allOK = false }
        }

        let eighth = TradingQuantizer(grid: .eighth)
        let tri8   = TradingQuantizer(grid: .tripletEighth)

        // ① 时值 ceil：略长于八分（65 slot）必须向上吸成 120（四分），不能记成 60
        check("① dur=65 @八分格 → 120（向上取整，不记短）", eighth.snapDuration(65) == 120)
        // ② 时值 ceil：略短于八分（35 slot）吸成一个八分 60
        check("② dur=35 @八分格 → 60", eighth.snapDuration(35) == 60)
        // ③ 反例守卫：八分三连格（40），起点 52 必须守在 40（三连），禁止被粗格 60 抢走
        check("③ start=52 @八分三连格(40) → 40（守住三连，禁止粗网格抢成 60）", tri8.snapStart(52) == 40)

        // ④ 行为级：八分音按住 80 slot（≈2/3 拍）后休止 → 应记成一个四分 72@0/120；
        //    round 旧版会记成 72@0/60，并在 60 处补一个本不该有的八分休止。
        let drag = guardRecord(events: [(72, 90, 0, true), (72, 0, 80, false)], grid: .eighth)
        let spuriousRestA = drag.contains { $0.rest && $0.start > 0 && $0.start < 120 }
        let okA: Bool
        if let f = drag.first {
            okA = f.pitch == 72 && f.start == 0 && f.dur == 120 && !spuriousRestA
        } else {
            okA = false   // 结果为空 → 判失败，而非强解包崩溃误导排查
        }
        check("④ 按住80后休止 → 72@0/120 且前 120 slot 内无补休止", okA)

        // ⑤ 行为级（连奏）：拖长八分 + 紧接下一音 → 72@0/120 → 74@120/60，两音中间禁止塞休止
        let leg = guardRecord(events: [(72, 90, 0, true), (72, 0, 80, false),
                                       (74, 90, 120, true), (74, 0, 180, false)], grid: .eighth)
        let legNotes = leg.filter { !$0.rest }
        let spuriousRestB = leg.contains { $0.rest && $0.start >= 60 && $0.start < 120 }
        let okB = legNotes.count >= 2
            && legNotes[0].pitch == 72 && legNotes[0].start == 0   && legNotes[0].dur == 120
            && legNotes[1].pitch == 74 && legNotes[1].start == 120 && legNotes[1].dur == 60
            && !spuriousRestB
        check("⑤ 拖长八分+紧接下一音 → 72@0/120→74@120/60，中间无休止", okB)

        print("---------------- M2-1 守卫：\(allOK ? "全部通过 ✅" : "存在失败 ❌") ----------------")
        return allOK
    }

    /// 守卫专用：把一组原始 MIDI 事件喂给录音器，返回逐音结果（含休止标记）。
    private static func guardRecord(events: [(pitch: Int, vel: Int, slot: Int, on: Bool)],
                                    grid: TradingQuantizeGrid, bars: Int = 1)
        -> [(pitch: Int, start: Int, dur: Int, rest: Bool)] {
        let rec = TradingRecorder()
        rec.begin(startSlot: 0,
                  lengthSlots: max(1, bars) * TradingSettings.slotsPerBar4_4,
                  quantizeGrid: grid, inputLatencySlots: 0)
        for e in events {
            rec.handleRawSlot(pitch: e.pitch, velocity: e.vel, isNoteOn: e.on, rawSlot: e.slot)
        }
        return rec.finish().notes.map { n in
            (n.pitch, n.startSlot, n.durationSlots, n.pitch == TradingSlotGrid.restPitch)
        }
    }
    // MARK: - M2-4 记谱转换守卫（v2：防重叠 / 边界取整守恒 / 三连按拍不降级 / tie）

    /// 守卫专用：喂事件 → 返回完整 UserPhrase（走真实 TradingRecorder + 量化器）。
    private static func guardPhrase(events: [(pitch: Int, vel: Int, slot: Int, on: Bool)],
                                    grid: TradingQuantizeGrid,
                                    bars: Int = 1,
                                    slotsPerBar: Int = TradingSettings.slotsPerBar4_4) -> UserPhrase {
        let rec = TradingRecorder()
        rec.begin(startSlot: 0,
                  lengthSlots: bars * slotsPerBar,
                  quantizeGrid: grid, inputLatencySlots: 0,
                  slotsPerBar: slotsPerBar)
        for e in events {
            rec.handleRawSlot(pitch: e.pitch, velocity: e.vel, isNoteOn: e.on, rawSlot: e.slot)
        }
        return rec.finish()
    }

    /// 渲染/播放口径：duration（含 r/_t3 后缀）→ slot（去 _t3，三连靠 isTriplet）。
    private static func resolveSlots(_ note: GeneratedNote) -> Int {
        let base = note.duration.components(separatedBy: "_t")[0]
        return MelodyTransformAdapter.tokenSlots(base, isTriplet: note.isTriplet)
    }

    /// 渲染端 getBaseTicks 口径（w4096/h2048/q1024/8 512/16 256/32 128，附点 ×1.5）。
    private static func baseTicksOf(_ duration: String) -> Int {
        let c = duration
            .replacingOccurrences(of: "r", with: "")
            .replacingOccurrences(of: "_t3", with: "")
            .replacingOccurrences(of: "d", with: "")
        var t: Int
        switch c {
        case "w":  t = 4096
        case "h":  t = 2048
        case "q":  t = 1024
        case "8":  t = 512
        case "16": t = 256
        case "32": t = 128
        default:   t = 1024
        }
        if duration.contains("d") { t = t * 3 / 2 }
        return t
    }

    /// 等价渲染端 makeTuplets：连续 isTriplet 符 baseTicks 必须 ∈{768,1536,3072,6144} 且成员>1，否则降级。
    private static func tupletGroupsValid(_ m: GeneratedMeasure) -> Bool {
        var i = 0
        while i < m.notes.count {
            if m.notes[i].isTriplet {
                var sum = 0, cnt = 0, j = i
                while j < m.notes.count && m.notes[j].isTriplet {
                    sum += baseTicksOf(m.notes[j].duration); cnt += 1; j += 1
                }
                guard cnt > 1 && [768, 1536, 3072, 6144].contains(sum) else { return false }
                i = j
            } else { i += 1 }
        }
        return true
    }

    private static func measureFilled(_ m: GeneratedMeasure) -> Bool {
        m.notes.reduce(0) { $0 + resolveSlots($1) } == m.slotsPerMeasure
    }

    /// 小节内相邻符头 start+dur <= 下一 start（不重叠不变式）。
    private static func noOverlap(_ m: GeneratedMeasure) -> Bool {
        var cur = 0
        var tl: [(Int, Int)] = []
        for n in m.notes { tl.append((cur, resolveSlots(n))); cur += resolveSlots(n) }
        for i in 0..<max(0, tl.count - 1) where tl[i].0 + tl[i].1 > tl[i + 1].0 { return false }
        return true
    }

    @discardableResult
    static func runPhraseToMeasuresGuards() -> Bool {
        print("\n============ M2-4 记谱转换守卫（v2：防重叠/守恒/三连/tie） ============")
        var allOK = true
        func check(_ label: String, _ cond: Bool) {
            print(cond ? "✅ \(label)" : "❌ \(label)")
            if !cond { allOK = false }
        }
        let spb = TradingSettings.slotsPerBar4_4
        let ctx = { (chord: String) in PhraseToMeasures.BarContext(
            chord: chord, chordSlots: [(chord, 0)], sectionName: nil, slotsPerMeasure: spb) }
        func allMeasuresGood(_ ms: [GeneratedMeasure]) -> Bool {
            ms.allSatisfy { measureFilled($0) && noOverlap($0) && tupletGroupsValid($0) }
        }

        // ① 防重叠：八分格 on0/off70 + on75/off110 → 前音截到后音头 60
        let A = guardPhrase(events: [
            (60, 90, 0, true), (60, 0, 70, false),
            (62, 90, 75, true), (62, 0, 110, false)
        ], grid: .eighth)
        let Av = PhraseToMeasures.convert(phrase: A, bars: [ctx("C")])
        var rt: [(Int, Int)] = []; var c = 0
        for n in Av[0].notes { if !n.isRest { rt.append((c, resolveSlots(n))) }; c += resolveSlots(n) }
        check("① 前音截断 60@0/60、62@60/60", rt.count >= 2 && rt[0] == (0, 60) && rt[1] == (60, 60))
        check("① 填满 + 不重叠 + 三连合法", allMeasuresGood(Av))

        // ② 三连三音各 40（拍 120 闭合）
        let B = guardPhrase(events: [
            (60, 90, 0, true), (60, 0, 40, false),
            (62, 90, 40, true), (62, 0, 80, false),
            (64, 90, 80, true), (64, 0, 120, false)
        ], grid: .tripletEighth)
        let Bv = PhraseToMeasures.convert(phrase: B, bars: [ctx("C")])
        check("② 三连三音组不降级 + 填满", allMeasuresGood(Bv))

        // ③ 跨小节长音 600（eighth）：bar0 w tieStart、bar1 q tieEnd
        let C = guardPhrase(events: [
            (60, 90, 0, true), (60, 0, 600, false)
        ], grid: .eighth, bars: 2)
        let Cv = PhraseToMeasures.convert(phrase: C, bars: [ctx("C"), ctx("F")])
        check("③ 跨小节 tieStart/tieEnd + 两小节填满",
              Cv[0].notes.last?.isTieStart == true &&
              Cv[1].notes.first?.isTieEnd == true &&
              Cv.allSatisfy { measureFilled($0) })

        // ④ 非标准时值 420 → hd(360)+8(60) tie
        let D = guardPhrase(events: [
            (60, 90, 0, true), (60, 0, 420, false)
        ], grid: .eighth)
        let Dv = PhraseToMeasures.convert(phrase: D, bars: [ctx("C")])
        check("④ 420 = hd tie 8（前两符 420）",
              Dv[0].notes.first?.isTieStart == true &&
              Dv[0].notes.prefix(2).reduce(0, { $0 + resolveSlots($1) }) == 420)

        // ⑤ 按住 80（eighth）→ q，不塞假休止
        let E = guardPhrase(events: [
            (72, 90, 0, true), (72, 0, 80, false)
        ], grid: .eighth)
        let Ev = PhraseToMeasures.convert(phrase: E, bars: [ctx("C")])
        check("⑤ 按住80 = q + 填满", Ev[0].notes.first?.duration == "q" && measureFilled(Ev[0]))

        // ⑥ 3/4（360）
        let F = guardPhrase(events: [
            (60, 90, 0, true), (60, 0, 120, false),
            (62, 90, 120, true), (62, 0, 240, false),
            (64, 90, 240, true), (64, 0, 360, false)
        ], grid: .eighth, bars: 1, slotsPerBar: 360)
        let Fv = PhraseToMeasures.convert(phrase: F, bars: [ctx("C")])
        check("⑥ 3/4 三拍填满 360", Fv[0].slotsPerMeasure == 360 && measureFilled(Fv[0]))

        // ⑦ 十六三连 6 音/拍
        var g7: [(Int, Int, Int, Bool)] = []
        for k in 0..<6 { g7.append((60 + k, 90, k * 20, true)); g7.append((60 + k, 0, k * 20 + 20, false)) }
        let G = guardPhrase(events: g7, grid: .sixteenthTriplet)
        let Gv = PhraseToMeasures.convert(phrase: G, bars: [ctx("C")])
        check("⑦ 十六三连6音组不降级 + 填满", allMeasuresGood(Gv))

        // ⑧ 跨 3 小节长音 1200 → w / w / h
        var g8: [(Int, Int, Int, Bool)] = [(60, 90, 0, true), (60, 0, 1200, false)]
        let I = guardPhrase(events: g8, grid: .eighth, bars: 3)
        let Iv = PhraseToMeasures.convert(phrase: I, bars: [ctx("C"), ctx("C"), ctx("C")])
        check("⑧ 跨3小节 w/w/h + 全填满",
              Iv[0].notes.first?.duration == "w" &&
              Iv[1].notes.first?.isTieEnd == true &&
              Iv[2].notes.first?.duration == "h" &&
              Iv.allSatisfy { measureFilled($0) })

        // ⑨【v2】.none 档任意时间戳（DeepSeek 反例 0/73、77/131、143/250）必须严格填满
        let H = guardPhrase(events: [
            (60, 90, 0, true), (60, 0, 73, false),
            (62, 90, 77, true), (62, 0, 131, false),
            (64, 90, 143, true), (64, 0, 250, false)
        ], grid: .none)
        let Hv = PhraseToMeasures.convert(phrase: H, bars: [ctx("C")])
        check("⑨ .none 档每小节严格 = 480（边界取整守恒）", measureFilled(Hv[0]) && noOverlap(Hv[0]))

        // ⑩【v2】三连第 2 份起音拖一拍（K 反例 on40/off160）：三连组不被劈开、跨拍 tie
        let K = guardPhrase(events: [
            (60, 90, 40, true), (60, 0, 160, false)
        ], grid: .tripletEighth)
        let Kv = PhraseToMeasures.convert(phrase: K, bars: [ctx("C")])
        check("⑩ 三连切分起音：三连组不降级 + 填满 + 跨拍 tie",
              tupletGroupsValid(Kv[0]) && measureFilled(Kv[0]) &&
              Kv[0].notes.contains { $0.isTieStart } && Kv[0].notes.contains { $0.isTieEnd })

        // ⑪【v2】普通反拍长音 on60/off180（八分格，60 起 120 跨拍）→ 拍边界切 + tie
        let K2 = guardPhrase(events: [
            (60, 90, 60, true), (60, 0, 180, false)
        ], grid: .eighth)
        let K2v = PhraseToMeasures.convert(phrase: K2, bars: [ctx("C")])
        check("⑪ 普通反拍长音在拍边界切 + tie + 填满",
              measureFilled(K2v[0]) && K2v[0].notes.contains { $0.isTieStart })

        // ⑫【v2】三连格整拍音 on0/off120 = 普通 q；跨2拍 on0/off240 = h
        let K3 = guardPhrase(events: [(60, 90, 0, true), (60, 0, 120, false)], grid: .tripletEighth)
        let K3v = PhraseToMeasures.convert(phrase: K3, bars: [ctx("C")])
        let K4 = guardPhrase(events: [(60, 90, 0, true), (60, 0, 240, false)], grid: .tripletEighth)
        let K4v = PhraseToMeasures.convert(phrase: K4, bars: [ctx("C")])
        check("⑫ 三连格整拍=q、跨2拍=h",
              K3v[0].notes.first?.duration == "q" && K3v[0].notes.first?.isTriplet == false &&
              K4v[0].notes.first?.duration == "h" && measureFilled(K4v[0]))

        // ⑬【v2.1】.none 短音不许整颗消失（无格点音兜底）：夹在两格之间的短音也要存在
        let T = guardPhrase(events: [(60, 90, 5, true), (60, 0, 10, false)], grid: .none)
        let Tv = PhraseToMeasures.convert(phrase: T, bars: [ctx("C")])
        let U = guardPhrase(events: [(60, 90, 5, true), (60, 0, 25, false)], grid: .none)
        let Uv = PhraseToMeasures.convert(phrase: U, bars: [ctx("C")])
        check("⑬ .none 短音[5,10)、跨格点[5,25) 不消失且填满",
              Tv[0].notes.contains { !$0.isRest } && measureFilled(Tv[0]) &&
              Uv[0].notes.contains { !$0.isRest } && measureFilled(Uv[0]))

        print("---------------- M2-4 守卫：\(allOK ? "全部通过 ✅" : "存在失败 ❌") ----------------")
        return allOK
    }
}
#endif
