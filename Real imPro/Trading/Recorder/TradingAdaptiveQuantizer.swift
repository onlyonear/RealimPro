import Foundation

// MARK: - Trading / Quantize / 自适应网格（M2-1b → M2-1c 半拍混合）
//
// 问题演进：
//   M1  ：整轮只能选一种网格（继承 Java quantum[]），十六分与三连互不整除 → 必有一方被压扁。
//   M2-1b：按"拍"选网格 → 同一小节内可共存，但**同一拍内**仍只能二选一。
//   M2-1c：按"拍的格子组合"选 → 允许一拍内前半三连、后半十六分（谱面合法：
//          三连组占一个八分的时值，后接两个十六分，合计一拍）。
//
// 记谱事实：同一瞬间既三等分又四等分，五线谱写不出来（需嵌套三连）。
//   所以"逐音"的上限就是"每种细分占一个独立的时间块"，本文件实现到该上限。
//
// 本文件不改 TradingQuantizer（M2-1 冻结）。

enum TradingAdaptiveQuantizer {

    /// 一拍 = 120 slot
    static let slotsPerBeat = 120

    /// 一拍可用的"格子组合"（每项和恒为 120）。从简到繁，打平时取靠前的（能不画三连就不画）。
    static let patterns: [[Int]] = [
        [60, 60],                     // 两个八分
        [30, 30, 30, 30],             // 四个十六分
        [40, 40, 40],                 // 八分三连
        [20, 20, 20, 20, 20, 20],     // 十六分三连
        [20, 20, 20, 30, 30],         // 前半拍三连 + 后半拍十六分
        [30, 30, 20, 20, 20],         // 前半拍十六分 + 后半拍三连
    ]

    /// 只含直拍细分的候选（swing / 普通八分十六分用）
    static let straightPatterns: [[Int]] = [
        [60, 60],
        [30, 30, 30, 30],
    ]

    // MARK: - 单拍打分

    /// 给一拍选格子组合：把这一拍的音头挪动总量最小的那个组合。
    static func choosePattern(onsets: [Int], beatStart: Int, allowed: [[Int]]? = nil) -> [Int] {
        guard !onsets.isEmpty else { return [60, 60] }
        let pool = allowed ?? patterns

        var best = pool[0]
        var bestCost = Int.max

        for p in pool {
            var bounds: [Int] = []
            var acc = 0
            for w in p { bounds.append(acc); acc += w }
            bounds.append(acc)          // 拍末也算落点（抢拍音应归下一拍，而不是挤进本拍末尾）

            var cost = 0
            var mapped: [Int] = []
            for o in onsets {
                let local = o - beatStart
                var bi = 0
                var bd = Int.max
                for (i, b) in bounds.enumerated() {
                    let d = abs(local - b)
                    if d < bd { bd = d; bi = i }
                }
                cost += bd
                mapped.append(bi)
            }
            // 两个音头被吸到同一条界线 = 丢音，重罚
            let unique = Set(mapped).count
            if unique < mapped.count { cost += 1000 * (mapped.count - unique) }

            // 打平：保留靠前（更简单）的组合
            if cost < bestCost { bestCost = cost; best = p }
        }
        return best
    }

    // MARK: - 摇摆识别

    /// swing 八分：一拍正好两颗音头，落在 0 与 2/3 拍（80 slot）附近 → 写成两个普通八分。
    /// 不能只看这一拍：四分三连（3 音跨 2 拍）的第 1 拍也是 0/80，会误伤；
    /// 故要求相邻拍里不出现 40（三连的中间音）。
    private static func isSwingBeat(local: [Int], prev: [Int], next: [Int]) -> Bool {
        guard local.count == 2 else { return false }
        // 80±8 = 72~88（swing 比 0.6~0.73）；再宽会把"附点八分"(90) 误判成 swing
        guard abs(local[0]) <= 12, abs(local[1] - 80) <= 8 else { return false }
        let tripletish: ([Int]) -> Bool = { b in b.contains { $0 >= 28 && $0 <= 52 } }
        return !tripletish(prev) && !tripletish(next)
    }

    // MARK: - 整轮

    /// 按拍算出整轮每拍的格子组合。
    static func patternsFor(onsets: [Int], offsets: [Int], turnLength: Int, forceSwing: Bool = false) -> [[Int]] {
        let beats = (turnLength + slotsPerBeat - 1) / slotsPerBeat
        guard beats > 0 else { return [] }

        // [抢拍归位] 拍末 15 slot（≈62ms）内的音属于**下一拍**：
        // 若算进本拍，三连拍会被挤成 4 个音头 → 退回 16 分三连（实测第 2 小节第 1 拍的错法）。
        let normalized: [Int] = onsets.map { o in
            let b = o / slotsPerBeat
            let into = o - b * slotsPerBeat
            return into >= slotsPerBeat - 15 ? (b + 1) * slotsPerBeat : o
        }

        var localOn: [[Int]] = []
        localOn.reserveCapacity(beats)
        for b in 0..<beats {
            let lo = b * slotsPerBeat
            let hi = min(lo + slotsPerBeat, turnLength)
            var on = normalized.filter { $0 >= lo && $0 < hi }.map { $0 - lo }.sorted()
            // 窄规则：一拍 4 个音头、前 3 个是标准三连(0/40/80)、第 4 个 ≥90 →
            // 第 4 个其实是下一拍的抢拍音，不计入本拍（否则三连被挤成 16 分三连）。
            if on.count == 4, abs(on[0]) <= 12, abs(on[1] - 40) <= 12, abs(on[2] - 80) <= 12, on[3] >= 90 {
                on.removeLast()
            }
            localOn.append(on)
        }

        var out: [[Int]] = []
        out.reserveCapacity(beats)
        // 三连的中间音（1/3 拍，40 slot 附近）——只有它出现，才允许这一带用三连
        let inThird: (Int) -> Bool = { $0 >= 28 && $0 <= 52 }

        // [整轮律动判定] 人手的 swing 不稳定（后半拍可能落在 65~100 之间浮动），
        // 逐拍卡死位置会把同一件事判成八分/附点/三连三种写法。
        // 改为看整轮统计：两音拍的"第二颗位置"如果多数落在 55~105，就整轮按 swing 记谱。
        var secondPositions: [Int] = []
        for on in localOn where on.count == 2 { secondPositions.append(on[1]) }
        let twoBeatCount = secondPositions.count
        let swingVotes = secondPositions.filter { $0 >= 55 && $0 <= 105 }.count
        // [Swing 开关] 用户明说"我按摇摆吹"时不必猜：1~2 音的拍一律八分（Java 的 SWING_THRESHOLD 同思路）
        let isSwingTurn = forceSwing || (twoBeatCount >= 3 && swingVotes * 10 >= twoBeatCount * 6)

        for b in 0..<beats {
            let lo = b * slotsPerBeat
            let on = localOn[b]
            let prev = b > 0 ? localOn[b - 1] : []
            let next = b + 1 < beats ? localOn[b + 1] : []

            // [核心判据] 三连一拍必然 3 个音；swing 一拍最多 2 个。
            //   ≤2 个音头且周围没有"1/3 位置的音"（四分三连跨拍）→ 只许直拍细分。
            //   这样 swing 的 80（= 2/3 拍）永远不会被写成三连。
            // [三连上下文，收窄版] 只有"整拍只有一颗音、落在一拍 1/3 处"的邻居，
            // 才说明这是四分三连跨拍（0/80 | 40 | 0/80）——那才是真三连。
            // 邻居若有多颗音（swing 里跑出来的提前半拍），不算三连上下文，
            // 否则整片 swing 会被拉成三连（实测过的那种 q_t3+8_t3）。
            let middleThirdOnly: ([Int]) -> Bool = { b in
                b.count == 1 && b[0] >= 28 && b[0] <= 52
            }
            // 跨拍四分三连的"中间那一拍"：只有一颗音、落在 40，且邻居是 0/80 形态
            let isMiddleThirdBeat: ([Int], [Int], [Int]) -> Bool = { cur, p, n in
                guard cur.count == 1, cur[0] >= 28, cur[0] <= 52 else { return false }
                let swingPair: ([Int]) -> Bool = { b in
                    b.count == 2 && abs(b[0]) <= 15 && abs(b[1] - 80) <= 12
                }
                return swingPair(p) || swingPair(n)
            }
            let tripletContext = (on.count >= 3 && on.contains(where: inThird))
                || middleThirdOnly(prev) || middleThirdOnly(next)

            // 整轮被判为 swing → 所有 1~2 音拍一律写两个普通八分（爵士惯例）
            // 整轮判为 swing 时，**忽略邻居拍的三连上下文**：
            //   否则个别"提前的半拍音"（落在 40 附近）会把整片区域拉成三连，
            //   出现 "q_t3 + 8_t3"（正是实测里反复出现的那种错法）。
            // [直拍优先] 一拍 ≥3 个音头、且 ≥75% 落在 30 格（十六分）附近 →
            // 只允许直拍细分，避免"4 个十六分"被读成"2 个十六分 + 一组三连"。
            let onThirty = on.filter { let r = $0 % 30; return min(r, 30 - r) <= 6 }.count
            if on.count >= 3, onThirty * 4 >= on.count * 3 {
                out.append(choosePattern(onsets: on.map { $0 + lo }, beatStart: lo,
                                         allowed: straightPatterns))
                continue
            }

            // 注意：只有"第二颗在后半拍（≥55）"才算 swing；0/30 这种十六分对仍走打分
            // 90 是"附点八分"的位置，不是 swing（swing 簇 72~88）→ 放到打分去，
            // 让 [30,30,30,30] 以 0 代价胜出，写成 8d+16。
            if isSwingTurn, !on.isEmpty, on.count <= 2, !tripletContext,
               !isMiddleThirdBeat(on, prev, next),
               (on.count == 1 || (on[1] >= 55 && on[1] <= 88)) {
                out.append([60, 60])
                continue
            }
            // 单拍兜底：一拍两颗、第二颗在 2/3 拍附近 → 两个八分
            if on.count == 2, !tripletContext, abs(on[0]) <= 15, abs(on[1] - 80) <= 8 {
                out.append([60, 60])
                continue
            }
            if isMiddleThirdBeat(on, prev, next) {
                out.append([40, 40, 40])
                continue
            }
            if on.count <= 2 && !tripletContext {
                out.append(choosePattern(onsets: on.map { $0 + lo }, beatStart: lo,
                                         allowed: straightPatterns))
            } else {
                out.append(choosePattern(onsets: on.map { $0 + lo }, beatStart: lo))
            }
        }
        return out
    }

    /// 兼容旧调用：把组合压成"主格宽"（仅用于日志/展示）
    static func dominantWidth(_ p: [Int]) -> Int {
        p.min() ?? 60
    }
}
