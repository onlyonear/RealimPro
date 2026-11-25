import Foundation

// MARK: - 反复展开器（M2）
// 只支持线性可表达的反复：简单成对反复（可带 times）+ volta 房子（1..N）。
// 展开顺序严格对齐 music21 repeat.Expander.measureMap()；任何结构异常
// （编号含 0、不连续、重叠、缺终止线、forward 无配对、真嵌套等）一律抛错拦截，
// 绝不硬展。D.S./D.C./Coda/Fine 在 Parser 置 hasNav，由 Importer 拦截。

enum MusicXMLRepeatError: Error, CustomStringConvertible {
    case malformed(String)
    // [旧码封存 P1修复 20261010] 原：var description: String { "V8 反复结构无法可靠展开: \(caseMsg)" }
    var description: String {
        return String(format: NSLocalizedString("V8 反复结构无法可靠展开: %@", comment: ""), caseMsg)
    }
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

/// G4 导航展开结果
struct MXNavResult {
    let map: [Int]       // 导航展开后的源小节下标序列
    let applied: Bool    // false = 结构不合规，已降级（沿用原 map）
}

enum MusicXMLRepeater {

    /// 返回展开后的小节（深拷贝）与源小节下标序列（map）。无反复时 map 为恒等。
    static func expand(_ raw: [MXRawMeasure]) throws -> (measures: [MXRawMeasure], map: [Int]) {
        let n = raw.count
        // 1. 非标准摆位 / 反向摆位（黄金集 0 例，直接拒）
        for m in raw {
            if m.nonStandardBarline {
                throw MusicXMLRepeatError.malformed(NSLocalizedString("ending/repeat 摆位非标准（start 应在左、stop 应在右）", comment: ""))
            }
            if m.leftRepeat == "backward" || m.rightRepeat == "forward" {
                throw MusicXMLRepeatError.malformed(NSLocalizedString("反复线方向摆位非标准（end 在左 / start 在右）", comment: ""))
            }
        }

        // 2. 由 ending start/stop 标记还原 bracket 跨度
        let allBrackets = try buildBrackets(raw)
        // [Repeater 增强] 编号非法的 volta 不报错，过滤掉（对齐 music21 宽容线性化）
        let invalidBrackets = allBrackets.filter { $0.nums.contains(where: { $0 < 1 }) }
        let brackets = allBrackets.filter { !$0.nums.contains(where: { $0 < 1 }) }

        // [Repeater 增强 v2] 编号非法（<1，如 ending 0）的 volta：只移除 ending 标记，
        // 保留 forward/backward，让其退回简单成对反复（对齐 MuseScore：ending 0 当无效忽略，
        // 反复仍执行）。不再清理关联的 forward/backward。
        let clearEnding = Set(invalidBrackets.flatMap { b in Array(b.start...b.end) })
        // 构建清理后的 workRaw：只复制需要改动的小节，其余复用原实例
        let workRaw: [MXRawMeasure] = raw.enumerated().map { idx, m in
            guard clearEnding.contains(idx) else { return m }
            let c = MXRawMeasure()
            c.sounds = m.sounds
            c.harmonies = m.harmonies
            c.contentEndQl = m.contentEndQl
            c.leftRepeat = m.leftRepeat
            c.leftRepeatTimes = m.leftRepeatTimes
            c.rightRepeat = m.rightRepeat
            c.rightRepeatTimes = m.rightRepeatTimes
            c.endStarts = []
            c.endStops = []
            c.nonStandardBarline = m.nonStandardBarline
            return c
        }

        // 3. 按编号重置分组 + 一致性校验
        let rawGroups = try groupBrackets(brackets)
        // [Repeater 增强 v2] 静态剔除"1 房子离反复终点过远"的不可靠结构：
        // 1 房子结束到该 group 第一个 backward 的 gap > 4（One_Note_Samba 型，gap=12；
        // 标准铅谱 1 房子贴终点，实测 12 首 gap 仅 1~3）。
        // 注意：不再用"group 之后还有 backward"判据——后面可接另一个独立反复段（Autumn/Lullaby 型）。
        let groups = rawGroups.filter { g in
            if let eIdx = (g.firstStart..<n).first(where: { workRaw[$0].rightRepeat == "backward" }) {
                if eIdx - g.brackets[0].end > 4 { return false }
            }
            return true
        }
        // [Repeater 增强 v2] 只要有 group 被剔除，就整体保守拒绝（expandSafely 降级线性 + 横幅），
        // 避免"房子还在、播放却走简单反复"的半吊子状态。
        if groups.count != rawGroups.count {
            throw MusicXMLRepeatError.malformed(NSLocalizedString("反复结构超出可可靠展开范围（不支持）", comment: ""))
        }

        // 3.5 backward 顺序配对校验（对齐 music21/MuseScore 的配对口径）：
        // 按顺序处理每个 backward，在"上一个 backward 之后"到当前 backward 之间找它的 forward。
        //  - 找到显式 forward：若该 forward 已被使用 = 真嵌套，拒绝；否则标记使用。
        //  - 找不到显式 forward：隐式跳回全曲开头 0；若 0 已被某个显式 forward 占用
        //    （Samba_triste 型：一个 forward 覆盖两个 backward），拒绝，绝不硬展。
        do {
            var usedForwardCheck = Set<Int>()
            var prevBackward = -1
            for i in 0..<n where workRaw[i].rightRepeat == "backward" {
                let B = i
                var foundF: Int?
                if prevBackward + 1 <= B {
                    for j in (prevBackward + 1)...B where workRaw[j].leftRepeat == "forward" {
                        foundF = j
                    }
                }
                if let F = foundF {
                    if usedForwardCheck.contains(F) {
                        throw MusicXMLRepeatError.malformed(NSLocalizedString("嵌套反复：forward 被重复配对（不支持）", comment: ""))
                    }
                    usedForwardCheck.insert(F)
                } else {
                    // 隐式 forward = 0；若 0 已被显式占用则拒绝
                    if usedForwardCheck.contains(0) {
                        throw MusicXMLRepeatError.malformed(NSLocalizedString("多段连续反复：孤立 backward 找不到属于自己的 forward（不支持）", comment: ""))
                    }
                }
                prevBackward = B
            }
        }

        // 4. 递归求播放顺序，同时记录被使用的 forward
        var usedForward = Set<Int>()
        var usedBackward = Set<Int>()
        var handledGroups = Set<Int>()
        let map = try expandRange(lo: 0, hi: n, raw: workRaw, groups: groups,
                                  usedForward: &usedForward, usedBackward: &usedBackward,
                                  handled: &handledGroups)

        // 5. [Repeater 增强] 无法配对的 volta 不报错，忽略（对齐 music21 宽容线性化）
        // 旧逻辑：handledGroups.count != groups.count 就 throw
        // 新逻辑：未展开的 group 直接忽略，不影响其他小节
        // 6. 不允许 forward-only（有开始反复线却没有任何收尾）；
        // 落在房子起始小节上的 forward 属于 volta 排版，不单独计数。
        let bracketStartSet = Set(groups.flatMap { g in g.brackets.map { $0.start } })
        for (i, m) in workRaw.enumerated()
        where m.leftRepeat == "forward" && !bracketStartSet.contains(i) {
            if !usedForward.contains(i) {
                throw MusicXMLRepeatError.malformed(String(format: NSLocalizedString("第 %d 小节开始反复线没有匹配的收尾（forward-only）", comment: ""), i + 1))
            }
        }
        // 7. 净校验：从第 0 小节开始，且每个源小节至少出现一次（不漏小节）
        guard let first = map.first, first == 0 else {
            throw MusicXMLRepeatError.malformed(NSLocalizedString("展开后不是从首小节开始", comment: ""))
        }
        if Set(map) != Set(0..<n) {
            throw MusicXMLRepeatError.malformed(NSLocalizedString("展开结果遗漏了源小节", comment: ""))
        }

        // 8. 按 map 深拷贝（不复制反复标记，展开后即为线性谱）
        let measures = map.map { idx -> MXRawMeasure in
            let s = workRaw[idx]
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
                throw MusicXMLRepeatError.malformed(String(format: NSLocalizedString("第 %d 小节开始的 volta 房子缺少 stop/discontinue 收尾", comment: ""), st.i + 1))
            }
            usedStop.insert(pi)
            brackets.append(MXBracket(nums: st.set, start: st.i, end: stops[pi].j))
        }
        // 有 stop 但没有任何 start 引用 → 结构异常
        if stops.count != usedStop.count {
            throw MusicXMLRepeatError.malformed(NSLocalizedString("存在没有开始标记的 volta 收尾", comment: ""))
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
                throw MusicXMLRepeatError.malformed(String(format: NSLocalizedString("volta 编号不连续：%@（应为 1..%d）", comment: ""), String(describing: concat), max(k, 1)))
            }
            // [Repeater 增强 v2] 允许相邻房子之间夹"反复终点区间"（标准铅谱：1 房子在终点前、
            // 2 房子在终点后）。只拒绝真重叠；gap 的合法性在 expandRange 内校验。
            for r in 0..<(bs.count - 1) {
                if bs[r + 1].start <= bs[r].end {
                    throw MusicXMLRepeatError.malformed(String(format: NSLocalizedString("volta 房子重叠：%d → %d", comment: ""), bs[r].end, bs[r + 1].start))
                }
            }
            return MXGroup(brackets: bs, k: k)
        }
    }

    // MARK: 递归展开

    private static func expandRange(lo: Int, hi: Int, raw: [MXRawMeasure],
                                    groups: [MXGroup], usedForward: inout Set<Int>,
                                    usedBackward: inout Set<Int>,
                                    handled: inout Set<Int>) throws -> [Int] {
        guard lo < hi else { return [] }

        // 该区间内第一个右收尾（backward end），跳过已处理的
        guard let E = firstBackward(raw: raw, lo: lo, hi: hi, usedBackward: usedBackward) else {
            return Array(lo..<hi)
        }

        // [Repeater 增强] 孤立 backward 的隐式 forward 在全曲开头 0（对齐 music21）
        var F = 0
        var foundForward = false
        for i in lo...E where raw[i].leftRepeat == "forward" {
            F = i
            foundForward = true
        }
        if foundForward && raw[F].leftRepeat == "forward" { usedForward.insert(F) }

        // [Repeater 增强 v2] 是否为 volta 段：第一房子起点在 [F,E]、其结束不晚于 E，
        // 且 E 落在第二房子之前（允许第一房子结束在反复终点前一小节）。
        if let gi = groups.firstIndex(where: { g in
            g.firstStart >= F && g.firstStart <= E
            && g.brackets[0].end <= E
            && (g.brackets.count == 1 || E < g.brackets[1].start)
        }) {
            let g = groups[gi]
            // 公共体 (F, firstStart) 内不得再有反复（真嵌套），不支持；
            // F 自身的 forward 是本段起点，需排除。
            if F + 1 < g.firstStart {
                for i in (F + 1)..<g.firstStart {
                    if raw[i].rightRepeat == "backward" || raw[i].leftRepeat == "forward" {
                        throw MusicXMLRepeatError.malformed(NSLocalizedString("volta 公共体内出现嵌套反复（不支持）", comment: ""))
                    }
                }
            }
            // [Repeater 增强 v2] 第一房子结束到反复终点 E 之间的 gap：
            // 内部（不含 E）不得有反复记号；E 自身带 backward（firstBackward 已保证）。
            let b0End = g.brackets[0].end
            if b0End < E {
                for i in (b0End + 1)..<E {
                    if raw[i].rightRepeat == "backward" || raw[i].leftRepeat == "forward" {
                        throw MusicXMLRepeatError.malformed(NSLocalizedString("volta 反复终点区间内出现嵌套反复（不支持）", comment: ""))
                    }
                }
            }
            handled.insert(gi)

            var seq = try expandRange(lo: lo, hi: F, raw: raw, groups: groups,
                                      usedForward: &usedForward, usedBackward: &usedBackward,
                                      handled: &handled)
            let common = Array(F..<g.firstStart)
            // 第一遍：common + 第一房子 + 第一房子结束到 E 的 gap（含反复终点，只第一遍）
            seq += common
            seq += Array(g.brackets[0].start...b0End)
            if b0End < E { seq += Array((b0End + 1)...E) }
            // 第 2..k 遍：common + 对应房子（跳过第一房子与反复终点）
            for p in 2...g.k {
                seq += common
                for b in g.brackets where b.nums.contains(p) {
                    seq += Array(b.start...b.end)
                }
            }
            seq += try expandRange(lo: g.lastEnd + 1, hi: hi, raw: raw, groups: groups,
                                   usedForward: &usedForward, usedBackward: &usedBackward,
                                   handled: &handled)
            return seq
        }

        // 简单成对反复
        // region (F,E] 内不允许再出现未使用的 forward（真嵌套）
        // [Repeater 增强] 已配对过的 forward（在 usedForward 里）跳过，不算嵌套
        if F < E {
            for i in (F + 1)...E where raw[i].leftRepeat == "forward" && !usedForward.contains(i) {
                throw MusicXMLRepeatError.malformed(NSLocalizedString("出现嵌套反复（不支持）", comment: ""))
            }
        }
        let times = raw[E].rightRepeatTimes ?? 2
        guard times >= 1 else {
            throw MusicXMLRepeatError.malformed(String(format: NSLocalizedString("反复 times 非法：%d", comment: ""), times))
        }

        // [Repeater 增强] 孤立 backward：隐式 forward(F=0) 在当前区间(lo)之前
        if !foundForward && lo > 0 {
            // 标记该 backward 已处理，递归跳回开头时不会再触发
            usedBackward.insert(E)
            // 第一遍：当前区间走到 E（尾巴部分）
            var seq = Array(lo...E)
            // 剩余 times-1 遍：从开头 F 完整展开（含 volta），E 已被跳过
            for _ in 1..<times {
                seq += try expandRange(lo: F, hi: E + 1, raw: raw, groups: groups,
                                       usedForward: &usedForward, usedBackward: &usedBackward,
                                       handled: &handled)
            }
            // E 之后
            seq += try expandRange(lo: E + 1, hi: hi, raw: raw, groups: groups,
                                   usedForward: &usedForward, usedBackward: &usedBackward,
                                   handled: &handled)
            return seq
        }

        var seq = try expandRange(lo: lo, hi: F, raw: raw, groups: groups,
                                  usedForward: &usedForward, usedBackward: &usedBackward,
                                  handled: &handled)
        let region = Array(F...E)
        for _ in 0..<times { seq += region }
        seq += try expandRange(lo: E + 1, hi: hi, raw: raw, groups: groups,
                               usedForward: &usedForward, usedBackward: &usedBackward,
                               handled: &handled)
        return seq
    }

    private static func firstBackward(raw: [MXRawMeasure], lo: Int, hi: Int,
                                      usedBackward: Set<Int>) -> Int? {
        for i in lo..<hi where raw[i].rightRepeat == "backward" && !usedBackward.contains(i) {
            return i
        }
        return nil
    }

    /// 安全展开：尽力展开，失败时降级为恒等序列，不抛错。
    /// - Returns: (展开后小节, map, hadError)
    ///   hadError = true 表示反复未真正展开（用户可见提示）
    static func expandSafely(_ raw: [MXRawMeasure]) -> (measures: [MXRawMeasure], map: [Int], hadError: Bool) {
        do {
            let result = try expand(raw)
            return (result.measures, result.map, false)
        } catch {
            // 展开失败：降级为原始序列，标记 hadError=true
            let map = Array(0..<raw.count)
            return (raw, map, true)
        }
    }

    // MARK: G4 导航展开（D.S. / D.C. / Coda / Fine）
    // 在普通反复展开后的 map 上做后处理：prefix 保留到 Dir 触发点，再拼
    // 「Segno/曲首 → To Coda/Fine/曲终」的尾巴，al Coda 再补 Coda 段。
    // 任何结构不合规都返回 applied=false（调用方降级，保持现状）。
    static func applyNavigation(map: [Int], raw: [MXRawMeasure]) -> MXNavResult {
        let n = raw.count
        let degrade = MXNavResult(map: map, applied: false)

        // 1. 收集字形位置
        var firstSegno = -1
        var codaMarks: [(index: Int, id: String?)] = []
        for (i, m) in raw.enumerated() {
            for mark in m.navMarks {
                switch mark.kind {
                case .segno: if firstSegno < 0 { firstSegno = i }
                case .coda: codaMarks.append((i, mark.id))
                }
            }
        }

        // 2. 收集播放指令
        var dirIndex = -1
        var dirSections = Set<Int>()   // 含 D.S./D.C. 指令的小节（同小节 words+sound 去重）
        var isDC = false
        var segnoIdRef: String?
        var hasToCoda = false
        var toCodaIndex = -1
        var toCodaIdRef: String?
        var hasFine = false
        var fineIndex = -1
        for (i, m) in raw.enumerated() {
            for d in m.navDirectives {
                switch d.kind {
                case .dalSegno(let id):
                    dirSections.insert(i)
                    if dirIndex < 0 { dirIndex = i; isDC = false; segnoIdRef = id }
                case .daCapo:
                    dirSections.insert(i)
                    if dirIndex < 0 { dirIndex = i; isDC = true }
                case .toCoda(let id):
                    hasToCoda = true; toCodaIndex = i; toCodaIdRef = id
                case .fineMark:
                    hasFine = true; fineIndex = i
                }
            }
        }

        // 3. 必须恰好一个小节含 D.S./D.C. 触发点（多条导航业界语义不统一，降级）
        guard dirIndex >= 0, dirSections.count == 1 else { return degrade }

        // 4. 确定 Segno 目标（D.C. 目标固定为曲首 0）
        var segnoTarget = firstSegno
        if !isDC {
            if let sid = segnoIdRef {
                // 显式指定 id：必须命中，找不到就降级，不静默退回第一个 segno（多段谱会跳错）
                guard let hit = raw.enumerated().first(where: { _, m in
                    m.navMarks.contains { $0.kind == .segno && $0.id == sid }
                }) else { return degrade }
                segnoTarget = hit.offset
            }
            guard segnoTarget >= 0 else { return degrade }   // D.S. 缺 Segno
        }
        let target = isDC ? 0 : segnoTarget

        // 5. 确定 Coda 目标（按 id 解析，id 缺失再退回 Dir 之后第一个 coda 字形）
        var codaTarget = -1
        if hasToCoda {
            if let cid = toCodaIdRef,
               let hit = raw.enumerated().first(where: { _, m in
                   m.navMarks.contains { $0.kind == .coda && $0.id == cid }
               }) {
                codaTarget = hit.offset
            }
            if codaTarget < 0 {
                codaTarget = codaMarks.first { $0.index > dirIndex }?.index ?? -1
            }
        }

        // 6. 合规校验（任一不满足即降级，绝不硬展）
        guard target < dirIndex else { return degrade }                 // 目标必须在 Dir 之前
        // 硬约束第 6 条：Dir 不得落在已展开重复区间内，两种命中：
        //  (a) Dir 小节在普通反复 map 里出现多次（位于反复区间内部）；
        //  (b) Dir 小节自身右 barline 带 backward（D.S. 与反复终点同小节，第二遍可能被 volta 跳过）。
        let dirOccurrences = map.reduce(0) { $0 + ($1 == dirIndex ? 1 : 0) }
        let dirIsBackward = raw[dirIndex].rightRepeat == "backward"
        guard dirOccurrences == 1, !dirIsBackward else { return degrade }
        if hasToCoda {
            guard toCodaIndex >= 0, codaTarget >= 0 else { return degrade }
            guard toCodaIndex >= target else { return degrade }        // To Coda 不早于 Segno
            guard toCodaIndex < dirIndex else { return degrade }       // To Coda 必须在 Dir 之前（§3.1 第3条）
            guard codaTarget > toCodaIndex else { return degrade }     // Coda 段在 To Coda 之后
        }
        if hasFine {
            guard fineIndex >= 0, fineIndex < dirIndex else { return degrade } // Fine 在 Dir 之前
        }

        // 7. 在普通反复展开的 map 上定位最后一次 Dir 触发点
        guard let iDir = map.lastIndex(of: dirIndex) else { return degrade }
        let prefix = Array(map[0...iDir])

        // 8. 拼尾巴：target → limit；al Coda 再补 Coda 段到曲终
        let limit = hasToCoda ? toCodaIndex : (hasFine ? fineIndex : n - 1)
        guard target <= limit else { return degrade }
        let tailA = Array(target...limit)
        let tailB = hasToCoda ? Array(codaTarget..<n) : []

        let out = prefix + tailA + tailB

        // 9. 硬约束第 7 条：总数上限（防炸）
        let cap = max(4 * n, n + 64)
        guard out.count <= cap, out.count <= 300 else { return degrade }
        guard out.count >= map.count else { return degrade }

        return MXNavResult(map: out, applied: true)
    }
}
