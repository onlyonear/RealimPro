//
//  JavaCYKParser.swift
//  RealimPro
//
//  J2（独立 Java 对齐 Roadmap 链）静态 CYK 解析 + findLaunchers。
//  忠实复刻 Java：
//    · CYKParser.createRules/fillTable/findSolution（CYKParser.java:234/351/385）
//        —— 静态字典砖编译出的产生式 → CYK 动态规划 → 每段最优砖划分；
//    · TreeNode.overlapCopy（重叠砖）；
//    · PostProcessor.findLaunchers（PostProcessor.java:377）
//        —— Dominant Cycle / 圈五链 / 曲尾回绕 / 单属 Launcher。
//
//  与现有 Swift BrickLibrary.parseBricksV2（动态产生式）完全分离、互不影响；不接 UI。
//

import Foundation

enum JavaCYKParser {

    // MARK: - 叶子（逐和弦）

    struct JLeaf {
        let idx: Int                 // 全局和弦序号
        let name: String             // 完整和弦名（裸和弦顶块显示用）
        let root: Int                // 根音 PC
        let family: String           // Advisor 家族串
        let rawQuality: String       // 保留大小写的质量串
        let dur: Int64               // 时长（slots）
        let isSectionEnd: Bool       // 是否段尾（下一个是段首）
        var mode: String { JavaBrickParser.modeFromRawQuality(rawQuality) }
    }

    // MARK: - 顶层解块（CYK 输出 / findLaunchers 后）

    enum JTopBlock {
        case chord(JLeaf)
        case brick(name: String, type: String, mode: String, key: Int,
                   startIdx: Int, endIdx: Int, leaves: [JLeaf])

        var startIdx: Int {
            switch self {
            case .chord(let leaf): return leaf.idx
            case .brick(_, _, _, _, let s, _, _): return s
            }
        }
        var endIdx: Int {
            switch self {
            case .chord(let leaf): return leaf.idx + 1
            case .brick(_, _, _, _, _, let e, _): return e
            }
        }
        var firstLeaf: JLeaf {
            switch self {
            case .chord(let leaf): return leaf
            case .brick(_, _, _, _, _, _, let leaves): return leaves[0]
            }
        }
        var key: Int {
            switch self {
            case .chord(let leaf): return leaf.root
            case .brick(_, _, _, let k, _, _, _): return k
            }
        }
        var btype: String {
            switch self {
            case .chord: return ""
            case .brick(_, let t, _, _, _, _, _): return t
            }
        }
        var bname: String {
            switch self {
            case .chord(let leaf): return leaf.family
            case .brick(let n, _, _, _, _, _, _): return n
            }
        }
        /// 是否段尾块（末叶子带段尾标记；对应 Block.isSectionEnd）。
        var isSectionEnd: Bool {
            switch self {
            case .chord(let leaf): return leaf.isSectionEnd
            case .brick(_, _, _, _, _, _, let leaves):
                return leaves.last?.isSectionEnd ?? false
            }
        }
    }

    // MARK: - 等价字典（AbstractProduction.adict）

    static let adict: [String: String] = [
        "bass": "any",
        "half-diminished": "minor7",
        "sus4": "dominant",
        "augmented": "major",
        "minor7": "minor"
    ]

    static func mod12(_ x: Int) -> Int { ((x % 12) + 12) % 12 }

    // MARK: - CYK 树节点

    final class JNode {
        var head: String
        var isChord: Bool
        var key: Int
        var cost: Double
        var dur: Int64
        var isEnd: Bool
        var leafOv: Bool
        var isSub: Bool
        var height: Int
        var family: String
        var c1: JNode?
        var c2: JNode?
        var invisible: Bool = false
        var mode: String
        var btype: String

        init(head: String, isChord: Bool, key: Int, cost: Double, dur: Int64,
             isEnd: Bool, leafOv: Bool, isSub: Bool, height: Int, family: String,
             c1: JNode? = nil, c2: JNode? = nil, invisible: Bool = false,
             mode: String, btype: String) {
            self.head = head; self.isChord = isChord; self.key = key; self.cost = cost
            self.dur = dur; self.isEnd = isEnd; self.leafOv = leafOv; self.isSub = isSub
            self.height = height; self.family = family; self.c1 = c1; self.c2 = c2
            self.invisible = invisible; self.mode = mode; self.btype = btype
        }

        var isOverlap: Bool {
            if let c2 { return c2.isOverlap }
            if let c1 { return c1.isOverlap }
            return leafOv
        }
        var trimmedHead: String {
            head.replacingOccurrences(of: " with Overrun", with: "")
                .replacingOccurrences(of: " with Dropback", with: "")
        }
    }

    // MARK: - 匹配

    static func matchPart(_ part: JavaBrickParser.JPart, _ node: JNode) -> Bool? {
        if node.isChord {
            guard part.isChord else { return nil }
            let nodeFam = node.family
            let prodFam = part.id
            if nodeFam == prodFam { return false }
            if let mapped = adict[nodeFam], mapped == prodFam || mapped == "any" { return true }
            return nil
        } else {
            guard !part.isChord else { return nil }
            if node.head == part.id || node.trimmedHead == part.id { return false }
            return nil
        }
    }

    struct Match { let key: Int; let cost: Double; let familyMatch: Bool }

    static func checkBinary(_ r: JavaBrickParser.JBRule, _ a: JNode, _ b: JNode) -> Match? {
        guard a.key != -1, b.key != -1 else { return nil }
        guard mod12(r.p2.key - r.p1.key) == mod12(b.key - a.key) else { return nil }
        let m1 = matchPart(r.p1, a); let m2 = matchPart(r.p2, b)
        guard let f1 = m1, let f2 = m2 else { return nil }
        let familyMatch = f1 || f2
        let newKey = mod12(b.key - r.p2.key)
        let scales = r.arbitrary || (a.dur * r.p2.dur == b.dur * r.p1.dur)
        var baseCost = Double(r.cost)
        if !scales { baseCost = Double(r.cost) * 100.0 }
        var add: Double = 0
        if a.isSub { add += 5 }
        if b.isSub { add += 5 }
        if b.isOverlap { add += 5 }
        if familyMatch { add += 5 }
        return Match(key: newKey, cost: baseCost + add, familyMatch: familyMatch)
    }

    static func checkUnary(_ r: JavaBrickParser.JURule, _ t: JNode) -> (key: Int, familyMatch: Bool)? {
        guard let fm = matchPart(r.part, t) else { return nil }
        let newKey = mod12(t.key - r.termKey - r.hk)
        return (newKey, fm)
    }

    // MARK: - 规则首符号索引（性能优化，结果与全扫相同）

    struct RuleIndex {
        var byChordFam: [String: [Int]] = [:]
        var byBrickHead: [String: [Int]] = [:]
        init(_ brs: [JavaBrickParser.JBRule]) {
            for (ri, r) in brs.enumerated() {
                if r.p1.isChord { byChordFam[r.p1.id, default: []].append(ri) }
                else { byBrickHead[r.p1.id, default: []].append(ri) }
            }
        }
        func candidates(for a: JNode) -> [Int] {
            if a.isChord {
                let fams = [a.family, adict[a.family]].compactMap { $0 }
                var res = Set<Int>()
                if adict[a.family] == "any" {
                    for (_, v) in byChordFam { v.forEach { res.insert($0) } }
                } else {
                    for f in fams { (byChordFam[f] ?? []).forEach { res.insert($0) } }
                }
                return res.sorted()
            } else {
                var res = Set<Int>()
                (byBrickHead[a.head] ?? []).forEach { res.insert($0) }
                (byBrickHead[a.trimmedHead] ?? []).forEach { res.insert($0) }
                return res.sorted()
            }
        }
    }

    static func makeBrick(head: String, type: String, mode: String, key: Int,
                   c1: JNode, c2: JNode?, cost: Double, isEnd: Bool) -> JNode {
        let dur = c2 != nil ? c1.dur + c2!.dur : c1.dur
        let h = c2 != nil ? max(c1.height, c2!.height) + 1 : c1.height + 1
        let sub = c2 != nil ? (c1.isSub || c2!.isSub) : false
        let n = JNode(head: head, isChord: false, key: key, cost: cost, dur: dur,
                      isEnd: isEnd, leafOv: false, isSub: sub, height: h, family: "",
                      c1: c1, c2: c2, mode: mode, btype: type)
        n.invisible = (type == "Invisible")
        return n
    }

    // MARK: overlapCopy

    static func overlapCopy(_ n: JNode) -> JNode {
        if let c2 = n.c2 {
            let oc2 = overlapCopy(c2)
            let copy = makeBrick(head: n.head, type: n.btype, mode: n.mode, key: n.key,
                                 c1: n.c1!, c2: oc2, cost: n.cost + 10, isEnd: n.isEnd)
            copy.invisible = n.invisible
            return copy
        } else if let c1 = n.c1 {
            let oc1 = overlapCopy(c1)
            let copy = makeBrick(head: n.head, type: n.btype, mode: n.mode, key: n.key,
                                 c1: oc1, c2: nil, cost: n.cost + 5, isEnd: n.isEnd)
            copy.invisible = n.invisible
            return copy
        } else {
            return JNode(head: n.head, isChord: true, key: n.key, cost: n.cost + 5,
                         dur: n.dur, isEnd: n.isEnd, leafOv: true, isSub: false,
                         height: 1, family: n.family, c1: nil, c2: nil,
                         mode: n.mode, btype: n.btype)
        }
    }

    // MARK: - 单段 CYK

    enum Cell {
        case node(JNode)
        case join(Int)
    }
    struct Segment { let s: Int; let e: Int; let node: JNode }

    static func runSection(_ leaves: [JLeaf],
                    binary: [JavaBrickParser.JBRule],
                    unary: [JavaBrickParser.JURule]) -> [JTopBlock] {
        let size = leaves.count
        let emptyCell: [JNode] = []
        let emptyRow = [[JNode]](repeating: emptyCell, count: size)
        var table = [[[JNode]]](repeating: emptyRow, count: size)

        // terminals
        for i in 0..<size {
            let l = leaves[i]
            let bare = JNode(head: "", isChord: true, key: l.root, cost: 1000,
                             dur: l.dur, isEnd: l.isSectionEnd, leafOv: false, isSub: false,
                             height: 1, family: l.family, c1: nil, c2: nil,
                             mode: l.mode, btype: "")
            var cell = [bare]
            var unaries = [JNode]()
            for t in cell {
                for r in unary {
                    if let m = checkUnary(r, t) {
                        unaries.append(makeBrick(head: r.head, type: r.type, mode: r.mode,
                                                 key: m.key, c1: t, c2: nil,
                                                 cost: Double(r.cost) + 5,
                                                 isEnd: t.isEnd))
                    }
                }
            }
            cell.append(contentsOf: unaries)
            table[i][i] = cell
        }

        // nonterminals
        let rindex = RuleIndex(binary)
        for startCol in 1..<size {
            for row in 0..<(size - startCol) {
                let col = startCol + row
                var cell = [JNode]()
                var overlaps = [JNode]()
                for index in 0..<(col - row) {
                    for a in table[row][row + index] {
                        guard !a.isEnd && !a.isOverlap else { continue }
                        let cand = rindex.candidates(for: a)
                        for b in table[row + index + 1][col] {
                            guard !b.isOverlap else { continue }
                            for ri in cand {
                                let r = binary[ri]
                                if let m = checkBinary(r, a, b) {
                                    let newNode = makeBrick(head: r.head, type: r.type,
                                                            mode: r.mode, key: m.key,
                                                            c1: a, c2: b, cost: m.cost,
                                                            isEnd: b.isEnd)
                                    cell.append(newNode)
                                    if r.type != "On-Off" && r.type != "Off-On" &&
                                       !b.isEnd && !b.isOverlap && b.dur != 0 {
                                        overlaps.append(overlapCopy(newNode))
                                    }
                                }
                            }
                        }
                    }
                }
                // unary reprocess
                var unaries = [JNode]()
                for t in cell {
                    for r in unary {
                        if let m = checkUnary(r, t) {
                            unaries.append(makeBrick(head: r.head, type: r.type, mode: r.mode,
                                                     key: m.key, c1: t, c2: nil,
                                                     cost: Double(r.cost) + (m.familyMatch ? 5 : 0),
                                                     isEnd: t.isEnd))
                        }
                    }
                }
                cell.append(contentsOf: unaries)
                table[row][col] = cell
                if col - 1 >= row { table[row][col - 1].append(contentsOf: overlaps) }
            }
        }

        // findSolution
        var best = [[JNode?]](repeating: [JNode?](repeating: nil, count: size), count: size)
        var prov = [[Cell]](repeating: [Cell](repeating: .join(-1), count: size), count: size)
        func better(_ x: JNode, _ y: JNode?) -> Bool {
            guard let y else { return true }
            if x.cost < y.cost { return true }
            if x.cost == y.cost && x.height > y.height { return true }
            return false
        }
        for row in 0..<size {
            for col in row..<size {
                var pick: JNode? = nil
                for n in table[row][col] {
                    let shown = n.isChord || !n.invisible
                    if shown && better(n, pick) { pick = n }
                }
                best[row][col] = pick
                if pick != nil { prov[row][col] = .node(pick!) }
            }
        }
        // DP
        for i in stride(from: size - 2, through: 0, by: -1) {
            for j in (i + 1)..<size {
                for k in (i + 1)...j {
                    let c1 = best[i][k - 1], c2 = best[k][j]
                    guard let c1, let c2 else { continue }
                    let sum = c1.cost + c2.cost
                    if sum < (best[i][j]?.cost ?? .infinity) {
                        let join = JNode(head: "", isChord: false, key: c2.key, cost: sum,
                                         dur: c1.dur + c2.dur, isEnd: c2.isEnd, leafOv: false,
                                         isSub: c1.isSub || c2.isSub,
                                         height: max(c1.height, c2.height) + 1, family: "",
                                         c1: c1, c2: c2, mode: "Major", btype: "")
                        best[i][j] = join
                        prov[i][j] = .join(k)
                    }
                }
            }
        }

        // emit → JTopBlock
        var out: [JTopBlock] = []
        func emit(_ i: Int, _ j: Int) {
            switch prov[i][j] {
            case .node(let n):
                if n.isChord {
                    out.append(.chord(leaves[i]))
                } else {
                    let rangeLeaves = Array(leaves[i...j])
                    out.append(.brick(name: n.head, type: n.btype, mode: n.mode, key: n.key,
                                      startIdx: leaves[i].idx, endIdx: leaves[j].idx + 1,
                                      leaves: rangeLeaves))
                }
            case .join(let k):
                if k < 0 {
                    if let n = best[i][j] {
                        if n.isChord { out.append(.chord(leaves[i])) }
                        else {
                            out.append(.brick(name: n.head, type: n.btype, mode: n.mode,
                                              key: n.key, startIdx: leaves[i].idx,
                                              endIdx: leaves[j].idx + 1,
                                              leaves: Array(leaves[i...j])))
                        }
                    }
                } else {
                    emit(i, k - 1); emit(k, j)
                }
            }
        }
        emit(0, size - 1)
        return out
    }

    // MARK: - 分段解析（CYKParser.parse:668；按 isSectionEnd 切段，拼完再 findLaunchers）

    /// 对全部叶子跑分段静态 CYK，返回拼接后的顶层块（尚未 findLaunchers）。
    static func parse(leaves: [JLeaf],
               binary: [JavaBrickParser.JBRule],
               unary: [JavaBrickParser.JURule]) -> [JTopBlock] {
        guard !leaves.isEmpty else { return [] }
        var solution: [JTopBlock] = []
        var prev = 0
        for (i, leaf) in leaves.enumerated() where leaf.isSectionEnd {
            solution.append(contentsOf: runSection(Array(leaves[prev...i]),
                                                   binary: binary, unary: unary))
            prev = i + 1
        }
        if prev < leaves.count {
            solution.append(contentsOf: runSection(Array(leaves[prev..<leaves.count]),
                                                   binary: binary, unary: unary))
        }
        return solution
    }

    // MARK: - findLaunchers（PostProcessor.java:377）

    /// altResolution（getAlternateResolution:565）；仅 diff∈{6 Tritone,8 Bauble,9 Yardbird,11 Nowhere}。
    static func altResolution(domRoot: Int, resRoot: Int) -> String {
        let diff = mod12(resRoot + 7 - domRoot)
        let table = ["", "", "", "", "", "", "Tritone", "", "Bauble", "Yardbird", "", "Nowhere"]
        return table[diff]
    }

    /// 对整条 solution 跑一次 findLaunchers（CYKParser.java:689）。
    static func findLaunchers(_ blocks: [JTopBlock]) -> [JTopBlock] {
        var out: [JTopBlock] = []
        let n = blocks.count

        for i in 0..<n {
            let postBlock: JTopBlock = (i != n - 1) ? blocks[i + 1] : blocks[0]

            switch blocks[i] {
            case .brick(let name, let type, let mode, let key, let s, let e, let leaves):
                var brickName = name
                var brickMode = mode

                // 名字以 Approach 结尾且有 altResolution → 改名 + 取 post 模式。
                if brickName.hasSuffix("Approach") {
                    let baseKey = leaves.last?.root ?? key
                    let alt = altResolution(domRoot: baseKey, resRoot: postBlock.key)
                    if !alt.isEmpty {
                        brickName = brickName.replacingOccurrences(of: "Straight", with: alt)
                        brickName = brickName.replacingOccurrences(of: "Sad", with: alt)
                        brickMode = postBlock.firstLeaf.mode
                    }
                }

                let isQualifiedApproach = brickName.contains("Approach") && brickName != "Approach"
                let isSlowLauncher = brickName == "Dominant Cycle" && (e - s) == 2
                let isDogleg = brickName == "Dogleg Approach"

                if (isQualifiedApproach || isSlowLauncher || isDogleg),
                   leaves.last?.isSectionEnd == true {
                    if isDogleg {
                        brickName = "Dogleg Slow Launcher"
                    } else if isQualifiedApproach {
                        brickName = brickName.replacingOccurrences(of: "Approach", with: "Launcher")
                    } else if isSlowLauncher {
                        brickName = "Slow Launcher"
                    }
                    out.append(.brick(name: brickName, type: "Launcher", mode: brickMode, key: key,
                                      startIdx: s, endIdx: e, leaves: leaves))
                } else {
                    out.append(.brick(name: brickName, type: type, mode: brickMode, key: key,
                                      startIdx: s, endIdx: e, leaves: leaves))
                }

            case .chord(let leaf):
                guard leaf.family == "dominant" else {
                    out.append(blocks[i]); continue
                }
                let postFirst = postBlock.firstLeaf

                // 单属 Launcher：解决到 post 且在段尾。
                if mod12(leaf.root + 5) == postBlock.key && leaf.isSectionEnd {
                    let launcherKey = mod12(leaf.root + 5)
                    out.append(.brick(name: "Launcher", type: "Launcher",
                                      mode: postFirst.mode, key: launcherKey,
                                      startIdx: leaf.idx, endIdx: leaf.idx + 1,
                                      leaves: [leaf]))
                } else {
                    // altResolution 特殊命名（四首不触发）；否则保留裸和弦。
                    let alt = altResolution(domRoot: leaf.root, resRoot: postBlock.key)
                    if !alt.isEmpty {
                        out.append(.brick(name: alt + " Launcher", type: "Launcher",
                                          mode: "Dominant", key: leaf.root,
                                          startIdx: leaf.idx, endIdx: leaf.idx + 1,
                                          leaves: [leaf]))
                    } else {
                        out.append(.chord(leaf))
                    }
                }
            }
        }
        return out
    }
}
