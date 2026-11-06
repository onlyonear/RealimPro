import Foundation

// MARK: - Trading / Convert / 记谱转换（M2-4）
//
// 把量化后的 UserPhrase 转成记谱层 [GeneratedMeasure]。
//
// 职责：
//   1) 防重叠：noteList() 返回写入时 rv[i]（不按后音头截断），选错网格时前音会盖住后音；
//      这里用"相邻音头间距"截断每个音的有效时值。
//   2) 边界取整：小节映射到固定 cell 栅格（普通 15 / 三连 40、20），按 cell 起点取音，
//      保证每小节 slot 总和恒 = slotsPerMeasure（.none 档也守恒）。
//   3) 三连按拍：整拍同状态 → 普通 q/h/hd/w；否则拍内三连单位铺满（每拍 1536 ticks），
//      跨拍长音在拍边界切开 + tie，杜绝连音组被普通符劈开。
//   4) 跨小节长音拆 isTieStart/isTieEnd；非标准时值（420 等）贪心分解 + 同小节 tie。
//
// 不做（另批）：乐理色块 tag（M2-7）、倚音 graceNotes（M4）、和弦标签 chordAnnotations、UI 接线（M2-8）。
// 纪律：不修改 TradingQuantizer（M2-1 冻结 md5 8c87da24）；只复用 MelodyTransformAdapter 的
//      tokenSlots（守卫反算）与 pitchName（MIDI→音名），不改其可见性。

enum PhraseToMeasures {

    /// 小节元数据（和弦 / 段落 / 拍号），由 M2-6 会话层从伴奏 roadmap 提供；M2-4 只消费。
    struct BarContext {
        var chord: String
        var chordSlots: [(chord: String, startSlot: Int)]
        var sectionName: String?
        var slotsPerMeasure: Int
    }

    static func convert(phrase: UserPhrase, bars: [BarContext]) -> [GeneratedMeasure] {
        let spb = max(1, phrase.slotsPerBar)
        let total = max(phrase.lengthSlots, phrase.grid.size)
        let barCount = max(bars.count, Int(ceil(Double(total) / Double(spb))))

        // 【越界留证，不夹紧】根因已在 TradingSlotGrid.setUnit 修复；这里只在内容真的溢出
        // 调用方提供的小节数时记录现场（dprint 在 Release 自动剥离），不改变任何数据，
        // 避免把未来未知路径的缺陷静默藏起来。
        let slotCapacity = bars.count * spb
        if total > slotCapacity {
            let overNotes = phrase.grid.noteList()
                .filter { $0.startSlot + $0.durationSlots > slotCapacity }
                .map { "\($0.pitch)@\($0.startSlot)x\($0.durationSlots)" }
            dprint("⚠️ [Trading] convert 越界：total=\(total) grid.size=\(phrase.grid.size) lengthSlots=\(phrase.lengthSlots) bars=\(bars.count) spb=\(spb) barCount=\(barCount) 越界音=\(overNotes)")
        }

        let heads = flatten(phrase: phrase, total: total)

        var out: [GeneratedMeasure] = []
        for bi in 0..<barCount {
            let barStart = bi * spb
            let barEnd = barStart + spb
            let segs = segmentsInBar(heads: heads, barStart: barStart, barEnd: barEnd)
            let cell: Int
            switch phrase.quantizeGrid {
            case .tripletEighth:    cell = 40
            case .sixteenthTriplet: cell = 20
            default:                cell = 15
            }
            // 防御：拍长必须能被 cell 整除（480/360 对 15/40/20 均整除；7/8=420 等将来不整除时 Debug 直接炸）
            assert(spb % cell == 0, "PhraseToMeasures: measure length \(spb) not divisible by cell \(cell)")
            // [M2-1b] 自适应网格：每拍用它自己选的格子（十六分与三连可共存于一小节）
            let notes: [GeneratedNote]
            if !phrase.beatPatterns.isEmpty {
                let beatsPerBar = max(1, spb / 120)
                notes = renderCellsAdaptive(segs: segs, spb: spb, patterns: phrase.beatPatterns,
                                            beatOffset: bi * beatsPerBar)
            } else {
                notes = renderCells(segs: segs, spb: spb, cell: cell)
            }
            let ctx = bi < bars.count
                ? bars[bi]
                : BarContext(chord: "", chordSlots: [], sectionName: nil, slotsPerMeasure: spb)
            out.append(GeneratedMeasure(
                chord: ctx.chord,
                notes: notes,
                chordAnnotations: [],
                sectionName: ctx.sectionName,
                slotsPerMeasure: spb,
                chordSlots: ctx.chordSlots))
        }
        return out
    }

    // MARK: ① 防重叠拍平

    fileprivate struct Head { let pitch: Int; let start: Int; let dur: Int }

    fileprivate static func flatten(phrase: UserPhrase, total: Int) -> [Head] {
        let raw = phrase.grid.noteList()
        var heads: [Head] = []
        for (i, n) in raw.enumerated() {
            let nextStart = i + 1 < raw.count ? raw[i + 1].startSlot : total
            let gap = max(1, nextStart - n.startSlot)
            let dur = max(1, min(n.durationSlots, gap))
            heads.append(Head(pitch: n.pitch, start: n.startSlot, dur: dur))
        }
        if let last = heads.last {
            let end = last.start + last.dur
            if end < total {
                heads.append(Head(pitch: TradingSlotGrid.restPitch, start: end, dur: total - end))
            }
        } else if total > 0 {
            heads.append(Head(pitch: TradingSlotGrid.restPitch, start: 0, dur: total))
        }
        return heads
    }

    // MARK: ② 小节切分（跨小节 tie）

    fileprivate struct Segment {
        let pitch: Int
        let startInBar: Int
        let slots: Int
        let tieIn: Bool
        let tieOut: Bool
    }

    fileprivate static func segmentsInBar(heads: [Head], barStart: Int, barEnd: Int) -> [Segment] {
        var segs: [Segment] = []
        for h in heads {
            let s = max(h.start, barStart)
            let e = min(h.start + h.dur, barEnd)
            guard s < e else { continue }
            segs.append(Segment(
                pitch: h.pitch,
                startInBar: s - barStart,
                slots: e - s,
                tieIn: h.start < barStart,
                tieOut: h.start + h.dur > barEnd))
        }
        segs.sort { $0.startInBar < $1.startInBar }
        return segs
    }

    // MARK: ③④ cell 栅格化 + 时值编码

    fileprivate struct Item { let pitch: Int; let seg: Int; let token: String; let triplet: Bool; var startSlot: Int = -1 }
    fileprivate struct Cell { let pitch: Int; let seg: Int }
    fileprivate struct Run { let pitch: Int; let seg: Int; let startCell: Int; let count: Int }

    fileprivate static func renderCells(segs: [Segment], spb: Int, cell: Int) -> [GeneratedNote] {
        let cpb = spb / cell          // 每小节 cell 数（普通 32 / 三连 12、24）
        let cpbBeat = 120 / cell      // 每拍 cell 数（普通 8 / 三连 3、6）
        let isTripletGrid = (cell == 40 || cell == 20)

        // 第一遍：按格点（cell 起点）归属。
        var owner: [Int] = Array(repeating: -1, count: cpb)
        for c in 0..<cpb {
            let t = c * cell
            for (si, s) in segs.enumerated()
            where s.startInBar <= t && t < s.startInBar + s.slots && s.pitch != TradingSlotGrid.restPitch {
                owner[c] = si; break
            }
        }
        // 第二遍兜底：没有任何格点落入的真实音（.none 档夹在两格之间的短音，如 [5,10)
        // 不含格点 0/15），吸附到与它重叠最大的"休止格"。只覆盖休止格、绝不抢占已被
        // 其他真实音占的格 → 已对齐四档、以及含格点的背靠背短音（L 用例）结果零变化。
        // （说明：不采用"逐格 max overlap"——那会把两个挤在同一个 32 分格内的背靠背
        // 短音 L 合并成一个；本方案只救"原本会丢的音"，不动任何已归属的音。）
        var covered = Set<Int>()
        for o in owner where o >= 0 { covered.insert(o) }
        for (si, s) in segs.enumerated()
        where s.pitch != TradingSlotGrid.restPitch && !covered.contains(si) {
            var bestCell = -1, bestOv = 0
            for c in 0..<cpb where owner[c] == -1 {
                let t0 = c * cell, t1 = t0 + cell
                let ov = max(0, min(t1, s.startInBar + s.slots) - max(t0, s.startInBar))
                if ov > bestOv { bestOv = ov; bestCell = c }
            }
            if bestCell >= 0 { owner[bestCell] = si }
        }
        let cells: [Cell] = (0..<cpb).map { c in
            let o = owner[c]
            return Cell(pitch: o >= 0 ? segs[o].pitch : TradingSlotGrid.restPitch, seg: o)
        }

        // 小节级 run-length（同音高/同段连续；休止 seg=-1 统一）
        var runs: [Run] = []
        var i = 0
        while i < cpb {
            var j = i
            while j < cpb && cells[j].pitch == cells[i].pitch && cells[j].seg == cells[i].seg { j += 1 }
            runs.append(Run(pitch: cells[i].pitch, seg: cells[i].seg, startCell: i, count: j - i))
            i = j
        }

        let items = isTripletGrid
            ? buildTripletItems(runs: runs, cpb: cpb, cpbBeat: cpbBeat, cell: cell)
            : buildStraightItems(runs: runs, cpbBeat: cpbBeat, cell: cell)
        return emitItems(items: items, segs: segs)
    }

    // MARK: [M2-1b] 自适应：每拍用它自己选的格子

    /// 与 `renderCells` 相同职责，但**逐拍**选择格宽（`beatCells` 由 TradingAdaptiveQuantizer 给出）。
    /// 一拍之内仍只有一种细分（不会自相矛盾），拍与拍之间可以不同（十六分与三连共存）。
    /// 注：`renderCells`（单格宽）保持一字未改，M2-4 的 13 条守卫走原路径。
    // MARK: [M2-1c] 自适应：按拍的"格子组合"渲染（半拍可混用不同细分）

    /// 与 `renderCells` 相同职责，但**逐拍**使用自己的格子组合（由 TradingAdaptiveQuantizer 给出）。
    /// 组合内格宽可以不同（如 [20,20,20,30,30] = 前半拍三连 + 后半拍十六分）；
    /// 同一音跨越格宽变化处时，自动切成两段并加连音线（emitItems 按 seg 连续判定）。
    fileprivate static func renderCellsAdaptive(segs: [Segment], spb: Int, patterns: [[Int]],
                                                beatOffset: Int = 0) -> [GeneratedNote] {
        var items: [Item] = []
        let beats = (spb + 119) / 120
        for b in 0..<beats {
            let lo = b * 120
            let hi = min(lo + 120, spb)
            let beatLen = hi - lo
            guard beatLen > 0 else { continue }
            let gi = beatOffset + b

            // 本拍格宽序列（按拍长截断/补齐；3/4 或非整拍时防越界）
            let raw = gi < patterns.count ? patterns[gi] : [60, 60]
            var widths: [Int] = []
            var acc = 0
            for w in raw where acc + w <= beatLen { widths.append(w); acc += w }
            if acc < beatLen { widths.append(beatLen - acc) }
            guard !widths.isEmpty else { continue }

            var starts: [Int] = []
            var t = lo
            for w in widths { starts.append(t); t += w }
            let cpb = widths.count

            // ① 格点归属（与单格宽版同一规则）
            var owner = [Int](repeating: -1, count: cpb)
            for c in 0..<cpb {
                let s0 = starts[c]
                for (si, s) in segs.enumerated()
                where s.pitch != TradingSlotGrid.restPitch && s.startInBar <= s0 && s0 < s.startInBar + s.slots {
                    owner[c] = si; break
                }
            }
            // ② 兜底：没有格点落入的真实音 → 吸到重叠最大的空格（绝不抢占已占格）
            var covered = Set<Int>()
            for o in owner where o >= 0 { covered.insert(o) }
            for (si, s) in segs.enumerated()
            where s.pitch != TradingSlotGrid.restPitch && !covered.contains(si) {
                var bestCell = -1, bestOv = 0
                for c in 0..<cpb where owner[c] == -1 {
                    let t0 = starts[c], t1 = t0 + widths[c]
                    let ov = max(0, min(t1, s.startInBar + s.slots) - max(t0, s.startInBar))
                    if ov > bestOv { bestOv = ov; bestCell = c }
                }
                if bestCell >= 0 { owner[bestCell] = si }
            }

            // ③ 拍内 run-length（同音同段连续）
            var i = 0
            while i < cpb {
                var j = i
                while j < cpb && owner[j] == owner[i] { j += 1 }
                let si = owner[i]
                let pitch = si >= 0 ? segs[si].pitch : TradingSlotGrid.restPitch

                // ④ 按格宽变化把 run 切段，再分别编码（跨段 tie 由 emitItems 负责）
                var k = i
                while k < j {
                    var m = k
                    while m + 1 < j && widths[m + 1] == widths[k] { m += 1 }
                    let w = widths[k]
                    let count = m - k + 1
                    var span = 0
                    for x in k...m { span += widths[x] }

                    if w == 40 || w == 20 {
                        if count == cpb && span == beatLen {
                            items.append(Item(pitch: pitch, seg: si, token: "q", triplet: false))
                        } else {
                            for (tok, tr) in tripletTokens(count, cell: w) {
                                items.append(Item(pitch: pitch, seg: si, token: tok, triplet: tr))
                            }
                        }
                    } else {
                        var first = true
                        for tok in straightTokens(span) {
                            items.append(Item(pitch: pitch, seg: si, token: tok, triplet: false,
                                              startSlot: first ? starts[k] : -1))
                            first = false
                        }
                    }
                    k = m + 1
                }
                i = j
            }
        }
        return emitItems(items: mergeLongNotes(items), segs: segs)
    }

    // MARK: [M2-6f] 长音合并：连续的整拍四分合成 二分/附点二分/全音符

    /// 自适应渲染是"一拍一拍"出的，长音会被切成 q~ + ~q。
    /// 这里把**连续、同段同音、各占整拍**的分符合并成大符值：
    ///   2 拍 → h；3 拍 → hd（必须从小节首起）；4 拍 → w（必须整小节）。
    fileprivate static func mergeLongNotes(_ items: [Item]) -> [Item] {
        var out: [Item] = []
        var i = 0
        while i < items.count {
            let cur = items[i]
            guard !cur.triplet, cur.token == "q", cur.startSlot >= 0 else {
                out.append(cur); i += 1; continue
            }
            var n = 1
            while i + n < items.count {
                let nx = items[i + n]
                guard !nx.triplet, nx.token == "q", nx.startSlot == cur.startSlot + n * 120,
                      nx.seg == cur.seg, nx.pitch == cur.pitch else { break }
                n += 1
            }
            // 合法上限：全音符必须从小节首（第 1 拍）开始；附点二分同理
            let atBarStart = (cur.startSlot % 480 == 0)
            var take = 1
            if n >= 4 && atBarStart { take = 4 }
            else if n >= 3 && atBarStart { take = 3 }
            else if n >= 2 { take = 2 }

            let tok = take == 4 ? "w" : (take == 3 ? "hd" : (take == 2 ? "h" : "q"))
            out.append(Item(pitch: cur.pitch, seg: cur.seg, token: tok, triplet: false, startSlot: cur.startSlot))
            i += take
        }
        return out
    }

    // MARK: 普通档：大符保留 + 反拍长音拍边界切

    fileprivate static func buildStraightItems(runs: [Run], cpbBeat: Int, cell: Int) -> [Item] {
        var items: [Item] = []
        for r in runs {
            let startCell = r.startCell
            let endCell = startCell + r.count
            var cuts: [(Int, Int)] = []
            if r.pitch == TradingSlotGrid.restPitch || startCell % cpbBeat == 0 {
                // 休止，或起点在拍边界 → 保留大符（w/h/hd/q 等），由贪心分解
                cuts = [(startCell, r.count)]
            } else {
                // 起点在拍中间的长音 → 在拍边界切开，段间 tie
                var cur = startCell
                while cur < endCell {
                    let nextBeat = (cur / cpbBeat + 1) * cpbBeat
                    let cut = min(nextBeat, endCell)
                    cuts.append((cur, cut - cur))
                    cur = cut
                }
            }
            for (_, cnt) in cuts {
                for tok in straightTokens(cnt * cell) {
                    items.append(Item(pitch: r.pitch, seg: r.seg, token: tok, triplet: false))
                }
            }
        }
        return items
    }

    fileprivate static let singleMap: [Int: String] = [
        480: "w", 360: "hd", 240: "h", 180: "qd", 120: "q",
        90: "8d", 60: "8", 45: "16d", 30: "16", 15: "32"
    ]
    fileprivate static let greedyTable: [Int] = [480, 360, 240, 180, 120, 90, 60, 45, 30, 15]

    fileprivate static func straightTokens(_ raw: Int) -> [String] {
        var rem = max(1, raw)
        if let one = singleMap[rem] { return [one] }
        var out: [String] = []
        for v in greedyTable {
            while rem >= v { out.append(singleMap[v]!); rem -= v }
        }
        if out.isEmpty { out.append("32") }
        return out
    }

    // MARK: 三连档：按拍组织（整拍大符 / 拍内三连铺满）

    fileprivate static func buildTripletItems(runs: [Run], cpb: Int, cpbBeat: Int, cell: Int) -> [Item] {
        // 每拍的局部 run（把小节级 run 按拍边界切）
        var beatRuns: [[Run]] = []
        for b in 0..<(cpb / cpbBeat) {
            let bs = b * cpbBeat
            let be = bs + cpbBeat
            var lr: [Run] = []
            var c = bs
            while c < be {
                if let p = runs.first(where: { $0.startCell <= c && c < $0.startCell + $0.count }) {
                    let end = min(p.startCell + p.count, be)
                    lr.append(Run(pitch: p.pitch, seg: p.seg, startCell: c, count: end - c))
                    c = end
                } else {
                    c += 1
                }
            }
            beatRuns.append(lr)
        }

        // 连续 n 个整拍的大符
        func bigToken(_ n: Int) -> String {
            switch n {
            case 1: return "q"
            case 2: return "h"
            case 3: return "hd"
            default:
                // 4 或极端值：先 w 再补
                return n >= 4 ? "w" : "q"
            }
        }

        var items: [Item] = []
        var b = 0
        while b < beatRuns.count {
            if beatRuns[b].count == 1 {
                // 整拍同一状态 → 合并连续整拍成大符
                let first = beatRuns[b][0]
                var n = 1
                while b + n < beatRuns.count,
                      beatRuns[b + n].count == 1,
                      beatRuns[b + n][0].pitch == first.pitch,
                      beatRuns[b + n][0].seg == first.seg {
                    n += 1
                }
                items.append(Item(pitch: first.pitch, seg: first.seg, token: bigToken(n), triplet: false))
                b += n
            } else {
                // 三连拍：拍内每个 run 用三连单位铺满
                for lr in beatRuns[b] {
                    for (tok, t) in tripletTokens(lr.count, cell: cell) {
                        items.append(Item(pitch: lr.pitch, seg: lr.seg, token: tok, triplet: t))
                    }
                }
                b += 1
            }
        }
        return items
    }

    /// 拍内三连符：cell40 1→8 / 2→q；cell20 4→q / 2→8 / 1→16（贪心）。
    fileprivate static func tripletTokens(_ count: Int, cell: Int) -> [(String, Bool)] {
        var rem = count
        var out: [(String, Bool)] = []
        if cell == 40 {
            if rem >= 2 { out.append(("q", true)); rem -= 2 }
            if rem >= 1 { out.append(("8", true)); rem -= 1 }
        } else {
            if rem >= 4 { out.append(("q", true)); rem -= 4 }
            if rem >= 2 { out.append(("8", true)); rem -= 2 }
            if rem >= 1 { out.append(("16", true)); rem -= 1 }
        }
        return out.isEmpty ? [("q", false)] : out
    }

    // MARK: 组装 GeneratedNote（跨拍/跨小节/内部 tie）

    fileprivate static func emitItems(items: [Item], segs: [Segment]) -> [GeneratedNote] {
        var notes: [GeneratedNote] = []
        for (i, it) in items.enumerated() {
            let isRest = it.pitch == TradingSlotGrid.restPitch
            // 同段同高连续 = 内部/跨拍 tie；小节首末继承 seg 的跨小节 tieIn/tieOut
            let tieEnd = !isRest && (
                (i > 0 && items[i - 1].seg == it.seg && items[i - 1].pitch == it.pitch) ||
                (i == 0 && it.seg >= 0 && segs[it.seg].tieIn))
            let tieStart = !isRest && (
                (i + 1 < items.count && items[i + 1].seg == it.seg && items[i + 1].pitch == it.pitch) ||
                (i + 1 == items.count && it.seg >= 0 && segs[it.seg].tieOut))
            let pitchStr = isRest ? "C/4"
                : MelodyTransformAdapter.pitchName(from: it.pitch, preferSharps: true)
            var dur = it.token
            if isRest { dur += "r" }
            if it.triplet { dur += "_t3" }
            notes.append(GeneratedNote(
                pitch: pitchStr,
                tag: .unknown,
                isRest: isRest,
                duration: dur,
                isTriplet: it.triplet,
                isTieStart: tieStart,
                isTieEnd: tieEnd,
                graceNotes: []))
        }
        return notes
    }
}
