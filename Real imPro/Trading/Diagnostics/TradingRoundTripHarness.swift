import Foundation

#if DEBUG

// MARK: - Trading / RoundTrip / 记谱回环自动测试（M2-6c）
//
// 目的：用"已知答案"考自己。
//   Demo 的和弦 → Grammar 生成 solo（[PhysicalNote]）→ 序列化成 (音高, 起点, 时值)
//   → 喂进真实的 TradingRecorder（与真人输入同一条量化路径）→ PhraseToMeasures 翻谱
//   → 逐音比对：音高 / 起点 / 时值 / 三连标记
//
// 说明：
//   · 这是 **DEBUG-only** 诊断，不参与任何生产路径。
//   · 用 `handleRawSlot` 直喂"精确 slot"，绕开真人抖动与音频链路——本测试要考的是
//     **记谱链路**（量化 + 翻谱），不是手速。时序链路另由 M2-2 回环与真机 session 覆盖。
//   · 单音线：Demo 生成的 solo 是单音线，与录音器语义一致。
//   · 倚音（durationSlots ≤ 15）按 App 的口径并入前一个音（本批不测装饰音，属 M4）。

enum TradingRoundTripHarness {

    /// 统一的"音"表示
    struct N: Equatable {
        let pitch: Int
        let start: Int
        let dur: Int
        let triplet: Bool
        var desc: String { "p\(pitch)@\(start)/\(dur)\(triplet ? "t" : "")" }
    }

    struct Report {
        let grid: String
        let srcNotes: Int
        let outNotes: Int
        let matched: Int
        let maxStartErr: Int
        let samples: [String]
        var rate: Double { srcNotes == 0 ? 0 : Double(matched) / Double(srcNotes) }
    }

    // MARK: - 入口

    /// 跑完整矩阵：Demo+Grammar 的素材 × 五个量化档
    static func run(bars: Int = 8) {
        print("\n========== M2-6c 记谱回环 ==========")
        if let src = demoGrammarSource(bars: bars) {
            report(src, bars: bars, title: "Demo + Grammar（随机生成）")
        } else {
            print("❌ Demo+Grammar 生成失败")
        }
        report(syntheticMixed(), bars: 1, title: "确定性混合：16分 + 八分三连 同小节")
        summary(samples: 3, bars: bars)
        print("=====================================================\n")
    }

    /// 多采样统计（Grammar 每次随机，单次不足以定论）
    static func summary(samples: Int = 3, bars: Int = 8) {
        print("\n———— 多采样统计（\(samples) 次随机生成 × \(bars) 小节）————")
        var acc: [String: [Double]] = [:]
        let grids: [(String, TradingQuantizeGrid, Bool)] = [
            ("20格", .sixteenthTriplet, false), ("30格", .sixteenth, false),
            ("60格", .eighth, false), ("40格", .tripletEighth, false), ("自适应", .eighth, true)]
        for i in 0..<samples {
            guard let src = demoGrammarSource(bars: bars) else { continue }
            var line = "  样本\(i + 1)：\(src.count) 音（16分 \(src.filter { $0.dur == 30 }.count) / 三连 \(src.filter { $0.triplet }.count)）"
            for (name, g, ad) in grids {
                let r = roundTrip(src, grid: g, bars: bars, label: name, adaptive: ad)
                acc[name, default: []].append(r.rate)
                line += String(format: "  %@=%.0f%%", name, r.rate * 100)
                if ad, r.matched < r.srcNotes {
                    line += "\n     自适应差异：" + r.samples.prefix(3).joined(separator: " | ")
                }
            }
            print(line)
        }
        print("  —— 汇总 ——")
        for (name, _, _) in grids {
            let v = acc[name] ?? []
            guard !v.isEmpty else { continue }
            let avg = v.reduce(0, +) / Double(v.count)
            let worst = v.min() ?? 0
            print(String(format: "  %-6@ 平均 %5.1f%%  最差 %5.1f%%", name as NSString, avg * 100, worst * 100))
        }
    }

    /// 确定性素材：第 1 拍四个十六分、第 2 拍三个八分三连、第 3 拍四分、第 4 拍切分
    static func syntheticMixed() -> [N] {
        var out: [N] = []
        // 第 1 拍：16 分 ×4
        for k in 0..<4 { out.append(N(pitch: 60 + k, start: k * 30, dur: 30, triplet: false)) }
        // 第 2 拍：八分三连 ×3
        for k in 0..<3 { out.append(N(pitch: 67 + k, start: 120 + k * 40, dur: 40, triplet: true)) }
        // 第 3 拍：四分
        out.append(N(pitch: 72, start: 240, dur: 120, triplet: false))
        // 第 4 拍：16 分 + 八分（切分）
        out.append(N(pitch: 74, start: 360, dur: 30, triplet: false))
        out.append(N(pitch: 76, start: 390, dur: 30, triplet: false))
        out.append(N(pitch: 77, start: 420, dur: 60, triplet: false))
        return out
    }

    static func report(_ src: [N], bars: Int, title: String) {
        print("\n———— \(title)：\(src.count) 音 / \(bars) 小节 ————")
        print("含十六分 \(src.filter { $0.dur == 30 }.count) 个、八分三连 \(src.filter { $0.triplet && $0.dur == 40 }.count) 个")
        var reports: [Report] = []
        for g in [TradingQuantizeGrid.sixteenthTriplet, .sixteenth, .eighth, .tripletEighth] {
            reports.append(roundTrip(src, grid: g, bars: bars, label: g.rawValue))
        }
        reports.append(roundTrip(src, grid: .eighth, bars: bars, label: "自适应(M2-1b)", adaptive: true))
        for r in reports {
            print(String(format: "  %-16@ 匹配 %2d/%2d (%5.1f%%) 输出%2d 音 最大起点误差 %d",
                         r.grid as NSString, r.matched, r.srcNotes, r.rate * 100, r.outNotes, r.maxStartErr))
        }
        for r in reports where r.matched < r.srcNotes {
            print("  【\(r.grid)】样本：")
            for s in r.samples.prefix(3) { print("     " + s) }
        }
    }

    // MARK: - 源：Demo + Grammar

    static func demoGrammarSource(bars: Int) -> [N]? {
        let song = JazzPlaylist.demoSong
        let roadmap = JazzRoadmap(title: song.title, tempo: song.tempo)
        for (mi, chords) in song.measures.enumerated() {
            let durs = song.measureDurations[mi]
            for (i, raw) in chords.enumerated() {
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, name != "NC", name != "N.C." else { continue }
                let d = i < durs.count ? durs[i] : 4.0
                roadmap.append(block: ChordBlock(name: name, duration: d,
                                                 isSectionStart: i == 0 && song.sectionMarkers[mi] != nil))
            }
        }
        let phys = GrammarStrategy.color.generateSolo(for: roadmap)
        guard !phys.isEmpty else { return nil }

        // PhysicalNote（只有时值序列，没有起点）→ 累计起点；倚音并入前音（与 App 口径一致）
        var out: [N] = []
        var cursor = 0
        let limit = bars * TradingSettings.slotsPerBar4_4
        for p in phys {
            if cursor >= limit { break }
            if p.midiPitch < 0 {                       // 休止：只推进时间
                cursor += p.durationSlots
                continue
            }
            if p.durationSlots <= 15 {                 // 倚音：并入前音（不单列）
                if let last = out.last {
                    out[out.count - 1] = N(pitch: last.pitch, start: last.start,
                                           dur: last.dur + p.durationSlots, triplet: last.triplet)
                }
                cursor += p.durationSlots
                continue
            }
            let triplet = (p.tuplet == 3)
            out.append(N(pitch: p.midiPitch, start: cursor, dur: p.durationSlots, triplet: triplet))
            cursor += p.durationSlots
        }
        return out
    }

    // MARK: - 回环

    static func roundTrip(_ src: [N], grid: TradingQuantizeGrid, bars: Int,
                          label: String? = nil, adaptive: Bool = false) -> Report {
        let spb = TradingSettings.slotsPerBar4_4
        let limit = bars * spb
        let rec = TradingRecorder()
        rec.begin(startSlot: 0, lengthSlots: limit, quantizeGrid: grid,
                  inputLatencySlots: 0, slotsPerBar: spb, adaptive: adaptive)
        for n in src where n.start < limit {
            rec.handleRawSlot(pitch: n.pitch, velocity: 90, isNoteOn: true, rawSlot: n.start)
            rec.handleRawSlot(pitch: n.pitch, velocity: 0, isNoteOn: false,
                              rawSlot: min(n.start + n.dur, limit - 1))
        }
        let phrase = rec.finish(endRawSlot: limit - 1)
        if adaptive {
            print("     beatPatterns(前 6 拍)=\(phrase.beatPatterns.prefix(6))")
        }
        let ctx = (0..<bars).map { _ in
            PhraseToMeasures.BarContext(chord: "C", chordSlots: [("C", 0)],
                                        sectionName: nil, slotsPerMeasure: spb)
        }
        let measures = PhraseToMeasures.convert(phrase: phrase, bars: ctx)
        let out = flatten(measures, spb: spb)

        // 逐音比对（以起点为键，容差 0）
        var byStart: [Int: N] = [:]
        for n in out { byStart[n.start] = n }
        var matched = 0
        var maxErr = 0
        var samples: [String] = []
        for s in src {
            // 找起点最接近的输出音（量化后可能落在相邻格）
            let cand = out.min { abs($0.start - s.start) < abs($1.start - s.start) }
            guard let c = cand else { continue }
            let dStart = abs(c.start - s.start)
            maxErr = max(maxErr, dStart)
            let ok = dStart == 0 && c.pitch == s.pitch && c.dur == s.dur
            if ok { matched += 1 }
            else if samples.count < 8 {
                samples.append("期望 \(s.desc) → 实际 \(c.desc)（起点差 \(dStart)，时值差 \(c.dur - s.dur)）")
            }
        }
        return Report(grid: label ?? grid.rawValue, srcNotes: src.count, outNotes: out.count,
                      matched: matched, maxStartErr: maxErr, samples: samples)
    }

    /// 小节 → 平铺音序列（跨小节/跨拍 tie 合并成一个音）
    static func flatten(_ ms: [GeneratedMeasure], spb: Int) -> [N] {
        var out: [N] = []
        for (bi, m) in ms.enumerated() {
            var cursor = 0
            for n in m.notes {
                let d = slots(n)
                if !n.isRest, let p = midiOf(n.pitch) {
                    if n.isTieEnd, var last = out.last, last.pitch == p {
                        last = N(pitch: last.pitch, start: last.start,
                                 dur: last.dur + d, triplet: last.triplet)
                        out[out.count - 1] = last
                    } else {
                        out.append(N(pitch: p, start: bi * spb + cursor, dur: d, triplet: n.isTriplet))
                    }
                }
                cursor += d
            }
        }
        return out
    }

    static func slots(_ n: GeneratedNote) -> Int {
        let base = n.duration.components(separatedBy: "_t")[0]
        return MelodyTransformAdapter.tokenSlots(base, isTriplet: n.isTriplet)
    }

    static func midiOf(_ s: String) -> Int? {
        let parts = s.split(separator: "/")
        guard parts.count == 2, let oct = Int(parts[1]) else { return nil }
        let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        guard let pc = names.firstIndex(of: String(parts[0])) else { return nil }
        return (oct + 1) * 12 + pc
    }
}

#endif
