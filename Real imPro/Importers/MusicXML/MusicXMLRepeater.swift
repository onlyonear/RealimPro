import Foundation

// MARK: - 反复展开器（M2）
// 只支持线性可表达的反复：简单成对反复（可带 times）+ volta 房子（1..N）。
// 展开顺序严格对齐 music21 repeat.Expander.measureMap()；任何结构异常
// （编号含 0、不连续、重叠、缺终止线、forward 无配对、真嵌套等）一律抛错拦截，
// 绝不硬展。D.S./D.C./Coda/Fine 在 Parser 置 hasNav，由 Importer 拦截。

enum MusicXMLRepeatError: Error, CustomStringConvertible {
    case malformed(String)
    var description: String { "V8 反复结构无法可靠展开: \(caseMsg)" }
    private var caseMsg: String {
        switch self { case .malformed(let s): return s }
    }
}

struct MXBracket {
    let nums: [Int]          // 该房子覆盖的遍次编号，如 [1] 或 [1,2,3,4,5]
    let start: Int           // 起始小节（含）
    let end: Int             // 结束小节（含，右 barline 带 ending stop）
}

struct MXGroup {
    let brackets: [MXBracket]
    let k: Int               // 总遍次 = 最大编号
    var firstStart: Int { brackets[0].start }
    var firstEnd: Int { brackets[0].end }
    var lastEnd: Int { brackets[brackets.count - 1].end }
}

enum MusicXMLRepeater {

    /// 返回展开后的小节（深拷贝）与源小节下标序列（map）。无反复时 map 为恒等。
    static func expand(_ raw: [MXRawMeasure]) throws -> (measures: [MXRawMeasure], map: [Int]) {
        let n = raw.count
        // 1. 非标准摆位 / 反向摆位（黄金集 0 例，直接拒）
        for m in raw {
            if m.nonStandardBarline {
                throw MusicXMLRepeatError.malformed("ending/repeat 摆位非标准（start 应在左、stop 应在右）")
            }
            if m.leftRepeat == "backward" || m.rightRepeat == "forward" {
                throw MusicXMLRepeatError.malformed("反复线方向摆位非标准（end 在左 / start 在右）")
            }
        }

        // 2. 由 ending start/stop 标记还原 bracket 跨度
        let brackets = try buildBrackets(raw)
        for b in brackets where b.nums.contains(where: { $0 < 1 }) {
            throw MusicXMLRepeatError.malformed("volta 房子编号非法（含 0 或缺 number 属性）")
        }

        // 3. 按编号重置分组 + 一致性校验
        let groups = try groupBrackets(brackets)

        // 3.5 顺序配对检测：每个反复锚点（volta 段一个、非房子内的 backward 一个）
        // 都必须能在前一锚点区域之后找到一个新的 forward；否则就是嵌套/外包反复
        // （music21 能展但超出"简单成对+顺序 volta"范围），保守拦截，绝不硬展。
        let bracketCovered = Set(groups.flatMap { g in
            g.brackets.flatMap { Array($0.start...$0.end) }
        })
        let bracketStarts = Set(groups.flatMap { g in g.brackets.map { $0.start } })
        struct Anchor { let end: Int; let regionEnd: Int }
        var anchors: [Anchor] = groups.map { Anchor(end: $0.firstEnd, regionEnd: $0.lastEnd) }
        for i in 0..<n where raw[i].rightRepeat == "backward" && !bracketCovered.contains(i) {
            anchors.append(Anchor(end: i, regionEnd: i))
        }
        anchors.sort { ($0.end, $0.regionEnd) < ($1.end, $1.regionEnd) }
        var consumed = -1
        for (ai, a) in anchors.enumerated() {
            var foundF: Int?
            if consumed + 1 <= a.end {
                for i in (consumed + 1)...a.end where raw[i].leftRepeat == "forward" {
                    foundF = i
                }
            }
            if foundF == nil {
                if ai == 0 && consumed == -1 {
                    // 首个锚点允许隐含从全曲开头反复
                    foundF = 0
                } else {
                    throw MusicXMLRepeatError.malformed("出现嵌套/外包反复（第 \(a.end + 1) 小节收尾缺少对应的新开始线），暂不支持")
                }
            }
            consumed = max(consumed, a.regionEnd)
        }

        // 4. 递归求播放顺序，同时记录被使用的 forward
        var usedForward = Set<Int>()
        var handledGroups = Set<Int>()
        let map = try expandRange(lo: 0, hi: n, raw: raw, groups: groups,
                                  usedForward: &usedForward, handled: &handledGroups)

        // 5. 每个 group 都必须被实际展开到
        if handledGroups.count != groups.count {
            throw MusicXMLRepeatError.malformed("存在无法配对到反复段的 volta 房子")
        }
        // 6. 不允许 forward-only（有开始反复线却没有任何收尾）；
        // 落在房子起始小节上的 forward 属于 volta 排版，不单独计数。
        for (i, m) in raw.enumerated()
        where m.leftRepeat == "forward" && !bracketStarts.contains(i) {
            if !usedForward.contains(i) {
                throw MusicXMLRepeatError.malformed("第 \(i + 1) 小节开始反复线没有匹配的收尾（forward-only）")
            }
        }
        // 7. 净校验：从第 0 小节开始，且每个源小节至少出现一次（不漏小节）
        guard let first = map.first, first == 0 else {
            throw MusicXMLRepeatError.malformed("展开后不是从首小节开始")
        }
        if Set(map) != Set(0..<n) {
            throw MusicXMLRepeatError.malformed("展开结果遗漏了源小节")
        }

        // 8. 按 map 深拷贝（不复制反复标记，展开后即为线性谱）
        let measures = map.map { idx -> MXRawMeasure in
            let s = raw[idx]
            let c = MXRawMeasure()
            c.contentEndQl = s.contentEndQl
            c.harmonies = s.harmonies
            c.sounds = s.sounds.map { ev in
                MXSoundEvent(offQl: ev.offQl, ql: ev.ql, isRest: ev.isRest, tuplet: ev.tuplet,
                             rawTie: ev.rawTie, components: ev.components)
            }
            return c
        }
        return (measures, map)
    }

    // MARK: bracket 还原

    private static func buildBrackets(_ raw: [MXRawMeasure]) throws -> [MXBracket] {
        var starts: [(i: Int, set: [Int])] = []
        var stops: [(j: Int, set: [Int])] = []
        for (i, m) in raw.enumerated() {
            for s in m.endStarts { starts.append((i, s)) }
            for s in m.endStops { stops.append((i, s)) }
        }
        var brackets: [MXBracket] = []
        var usedStop = Set<Int>()
        for st in starts {
            // 优先同集合精确匹配，再退而求其次取有编号交集的 stop
            var pick = stops.indices.first { idx in
                !usedStop.contains(idx) && stops[idx].j >= st.i && stops[idx].set == st.set
            }
            if pick == nil {
                pick = stops.indices.first { idx in
                    !usedStop.contains(idx) && stops[idx].j >= st.i
                    && Set(stops[idx].set).intersection(st.set).count > 0
                }
            }
            guard let pi = pick else {
                throw MusicXMLRepeatError.malformed("第 \(st.i + 1) 小节开始的 volta 房子缺少 stop/discontinue 收尾")
            }
            usedStop.insert(pi)
            brackets.append(MXBracket(nums: st.set, start: st.i, end: stops[pi].j))
        }
        // 有 stop 但没有任何 start 引用 → 结构异常
        if stops.count != usedStop.count {
            throw MusicXMLRepeatError.malformed("存在没有开始标记的 volta 收尾")
        }
        return brackets.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    // MARK: 分组（对齐 music21 _groupRepeatBracketIndices）

    private static func groupBrackets(_ brackets: [MXBracket]) throws -> [MXGroup] {
        var rawGroups: [[MXBracket]] = []
        var cur: [MXBracket] = []
        var found = Set<Int>()
        for b in brackets {
            if let f0 = b.nums.first, found.contains(f0), !cur.isEmpty {
                rawGroups.append(cur); cur = []; found = []
            }
            cur.append(b); found.formUnion(b.nums)
        }
        if !cur.isEmpty { rawGroups.append(cur) }

        return try rawGroups.map { bs in
            // 编号必须恰好连续 1..k
            let concat = bs.flatMap { $0.nums }
            let k = concat.max() ?? 0
            guard k >= 1, concat == Array(1...k) else {
                throw MusicXMLRepeatError.malformed("volta 编号不连续：\(concat)（应为 1..\(max(k,1))）")
            }
            // 跨度必须严格相邻、不重叠
            for r in 0..<(bs.count - 1) {
                if bs[r + 1].start != bs[r].end + 1 {
                    throw MusicXMLRepeatError.malformed("volta 房子之间不连续或重叠：\(bs[r].end + 1) → \(bs[r + 1].start)")
                }
            }
            return MXGroup(brackets: bs, k: k)
        }
    }

    // MARK: 递归展开

    private static func expandRange(lo: Int, hi: Int, raw: [MXRawMeasure],
                                    groups: [MXGroup], usedForward: inout Set<Int>,
                                    handled: inout Set<Int>) throws -> [Int] {
        guard lo < hi else { return [] }

        // 该区间内第一个右收尾（backward end）
        guard let E = firstBackward(raw: raw, lo: lo, hi: hi) else {
            return Array(lo..<hi)
        }

        // 最近的 forward（没有则隐含从本区间头 lo 反复）
        var F = lo
        for i in lo...E where raw[i].leftRepeat == "forward" { F = i }
        if raw[F].leftRepeat == "forward" { usedForward.insert(F) }

        // 是否为 volta 段：某 group 的第一房子收尾恰为 E，且该 group 起点在 [F,E]
        if let gi = groups.firstIndex(where: { g in
            g.firstEnd == E && g.firstStart >= F && g.firstStart <= E
        }) {
            let g = groups[gi]
            // 公共体 (F, firstStart) 内不得再有反复（真嵌套），不支持；
            // F 自身的 forward 是本段起点，需排除。
            if F + 1 < g.firstStart {
                for i in (F + 1)..<g.firstStart {
                    if raw[i].rightRepeat == "backward" || raw[i].leftRepeat == "forward" {
                        throw MusicXMLRepeatError.malformed("volta 公共体内出现嵌套反复（不支持）")
                    }
                }
            }
            // 非末房子的结束小节必须带 backward 收尾
            for bi in 0..<(g.brackets.count - 1) {
                if raw[g.brackets[bi].end].rightRepeat != "backward" {
                    throw MusicXMLRepeatError.malformed("第 \(bi + 1) 房子缺少反复收尾线")
                }
            }
            handled.insert(gi)

            var seq = try expandRange(lo: lo, hi: F, raw: raw, groups: groups,
                                      usedForward: &usedForward, handled: &handled)
            let common = Array(F..<g.firstStart)
            for p in 1...g.k {
                seq += common
                for b in g.brackets where b.nums.contains(p) {
                    seq += Array(b.start...b.end)
                }
            }
            seq += try expandRange(lo: g.lastEnd + 1, hi: hi, raw: raw, groups: groups,
                                   usedForward: &usedForward, handled: &handled)
            return seq
        }

        // 简单成对反复
        // region (F,E] 内不允许再出现 forward（真嵌套）
        if F < E {
            for i in (F + 1)...E where raw[i].leftRepeat == "forward" {
                throw MusicXMLRepeatError.malformed("出现嵌套反复（不支持）")
            }
        }
        let times = raw[E].rightRepeatTimes ?? 2
        guard times >= 1 else {
            throw MusicXMLRepeatError.malformed("反复 times 非法：\(times)")
        }
        var seq = try expandRange(lo: lo, hi: F, raw: raw, groups: groups,
                                  usedForward: &usedForward, handled: &handled)
        let region = Array(F...E)
        for _ in 0..<times { seq += region }
        seq += try expandRange(lo: E + 1, hi: hi, raw: raw, groups: groups,
                               usedForward: &usedForward, handled: &handled)
        return seq
    }

    private static func firstBackward(raw: [MXRawMeasure], lo: Int, hi: Int) -> Int? {
        for i in lo..<hi where raw[i].rightRepeat == "backward" { return i }
        return nil
    }
}
