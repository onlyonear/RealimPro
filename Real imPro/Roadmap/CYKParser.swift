import Foundation

// MARK: - CYKParser — 基础句法解析 (仅Solo生成必需，舍弃编辑器完整语法)
// 用于识别 ii-V-I 等标准爵士和声进行, 输出 TreeNode 链供 BrickLibrary 匹配
//
// v3 修复 (2026-07-12):
//   [+] 和弦族标准化模糊匹配 (m9/m11/m13/ø/m7b5/dom7/maj7 → family 归一)
//   [+] modKeys 调性一致性校验 (过滤跨调错误乐句组合)
//   [+] 轻量化和弦等价类硬编码字典 (ø↔m7b5, Δ7↔maj7, °↔dim)
//   [−] 舍弃: 文件加载等价规则 / 时长缩放 / section边界 / 任意时长 / 变体类型

// ═══════════════════════════════════════════════════════════
// 0. 和弦族标准化 & 等价类工具
// ═══════════════════════════════════════════════════════════

/// 和弦记谱等价字典 — 不同记谱方式归一为统一名称
/// 注: ChordFamily 使用 JazzHarmonicModels.swift 中的统一定义
/// 例: "ø7" ↔ "m7b5"  /  "Δ7" ↔ "maj7"  /  "°7" ↔ "dim7"
enum ChordEquivalence {
    /// 等价组: 每组第一个为规范名 (canonical)，其余为别名
    static let groups: [[String]] = [
        ["m7b5",   "ø",   "ø7",   "half-dim",  "half-diminished", "h7"],
        ["maj7",   "Δ",   "Δ7",   "δ",   "δ7",   "M7",         "major7"],
        ["aug",    "+",   "aug7", "+7",  "wholetone", "whole-tone"],
        ["dim7",   "°",   "°7",   "dim"],
        ["m7",     "-7",  "min7", "minor"],
        ["7",      "dom7","dominant7"],
        ["sus4",   "sus", "7sus4", "11", "11th", "sus11"],
        ["mM7",    "mΔ7", "mδ7", "minMaj7", "minor-major7"],
    ]

    /// 将任意和弦记谱名归一化为规范名
    static func canonical(_ quality: String) -> String {
        let q = quality.lowercased().trimmingCharacters(in: .whitespaces)
        for group in groups {
            if group.contains(q) { return group[0] }
        }
        return q
    }
}

/// 和弦名解析结果
struct ParsedChordName {
    let root: String       // 根音字母 "C","D","E","F","G","A","B" 含升降号
    let quality: String    // 质量部分（已归一化） "m7","maj7","7","m7b5"...
    let rootValue: Int     // 根音数值 0=C .. 11=B

    static func parse(_ name: String) -> ParsedChordName? {
        let cleaned = name.trimmingCharacters(in: .whitespaces)
        guard cleaned.count >= 2 else { return nil }

        // 提取根音 (处理单字母或带升降号的根音)
        var idx = 1
        if cleaned.count > 1 {
            let second = cleaned[cleaned.index(cleaned.startIndex, offsetBy: 1)]
            if second == "#" || second == "b" {
                idx = 2
            }
        }
        let rootStr = String(cleaned.prefix(idx))
        let qualityStr = idx < cleaned.count ? String(cleaned.suffix(cleaned.count - idx)) : ""

        guard let rv = ChordNameUtils.rootToValue(rootStr) else { return nil }

        return ParsedChordName(
            root: rootStr,
            quality: ChordEquivalence.canonical(qualityStr),
            rootValue: rv
        )
    }
}

/// 和弦名静态工具
enum ChordNameUtils {
    private static let rootMap: [String: Int] = [
        "C":0,  "C#":1, "Db":1,
        "D":2,  "D#":3, "Eb":3,
        "E":4,
        "F":5,  "F#":6, "Gb":6,
        "G":7,  "G#":8, "Ab":8,
        "A":9,  "A#":10,"Bb":10,
        "B":11
    ]

    static func rootToValue(_ root: String) -> Int? {
        return rootMap[root]
    }

    /// 模12取正余数 (同Java modKeys)
    static func modKeys(_ value: Int) -> Int {
        return ((value % 12) + 12) % 12
    }

    /// 提取和弦质量→归一化族名
    /// 去除根音和扩展音，返回基础家族
    static func normalizeToFamily(_ quality: String) -> ChordFamily {
        let q = quality.lowercased()

        // 小大七 / mM7
        if q.hasPrefix("mm") || q.hasPrefix("mδ") || q.hasPrefix("m-") ||
           q.contains("minmaj") || q.contains("minor-major") {
            return .minor
        }

        // 半减七
        if q.hasPrefix("ø") || q == "m7b5" || q == "h7" ||
           q.contains("half-dim") || q == "half-diminished" {
            return .halfDiminished
        }

        // 减七
        if q.hasPrefix("°") || q.hasPrefix("dim") || q == "o7" {
            return .diminished
        }

        // 增和弦
        if q.hasPrefix("+") || q.hasPrefix("aug") {
            return .augmented
        }

        // 挂留
        if q.contains("sus") {
            return .sus
        }

        // 属七 (含各种扩展/变化)
        if q.hasPrefix("7") || q.hasPrefix("9") || q.hasPrefix("13") ||
           q.hasPrefix("dom") || q.contains("7b") || q.contains("7#") ||
           q.contains("7alt") {
            return .dominant
        }

        // 大和弦 (maj7, maj9, maj13, 6, M7, Δ7) — 必须在"m"前缀之前
        // 否则"maj7"会被"m"前缀误判为minor7
        if q.hasPrefix("maj") || q.hasPrefix("δ") || q.hasPrefix("Δ") ||
           q.hasPrefix("M") || q == "6" || q == "69" {
            return .major
        }

        // 小和弦 (m7, m9, m11, m13, -7, min) — "m"前缀放在"maj"之后
        if q.hasPrefix("m") || q.hasPrefix("-") || q.contains("min") {
            return .minor
        }

        // 纯根音 (无质量 → 大和弦)
        if q.isEmpty { return .major }

        return .unknown
    }

    /// 完整和弦名 → 族名
    /// 例: "Dm9" → .minor,  "G7b9" → .dominant,  "F#ø7" → .halfDiminished
    static func chordToFamily(_ chordName: String) -> ChordFamily {
        guard let parsed = ParsedChordName.parse(chordName) else {
            return .unknown
        }
        return normalizeToFamily(parsed.quality)
    }

    /// 提取根音数值 (0=C .. 11=B)
    static func extractRoot(_ chordName: String) -> Int? {
        return ParsedChordName.parse(chordName)?.rootValue
    }
}

// ═══════════════════════════════════════════════════════════
// 1. 句法产生式 (Production)
// ═══════════════════════════════════════════════════════════

/// 二元产生式: A → B C (两个子节点合并)
struct BinaryProduction {
    let left:  String       // 左子节点标识
    let right: String       // 右子节点标识
    let result: String      // 结合后的brick名称
    let weight: Int         // 优先级权重
    let keyDiff: Int?       // 新增: 预期左右子节点间模12调差 (nil=不做校验)
                            // 例: ii→V 在任意大调中 ii_root→V_root 差5半音

    init(left: String, right: String, result: String,
         weight: Int, keyDiff: Int? = nil) {
        self.left = left; self.right = right; self.result = result
        self.weight = weight; self.keyDiff = keyDiff
    }
}

/// 一元产生式: A → B (单子节点重命名/扩展)
struct UnaryProduction {
    let child:  String
    let result: String
}

/// 替换规则: ChordName → BrickName (v3: 增加和弦族字段)
struct SubstitutionDefinition {
    let chordName: String   // 具体和弦名 (如 "Dm7")
    let brickName: String   // 功能名 (如 "ii")
    let cost: Int           // 替换代价 (越低越优先匹配)
    let family: ChordFamily // 新增: 该条目的和弦族

    init(chordName: String, brickName: String, cost: Int,
         family: ChordFamily? = nil) {
        self.chordName = chordName
        self.brickName = brickName
        self.cost = cost
        // 自动推导族 (如果未指定)
        self.family = family ?? ChordNameUtils.chordToFamily(chordName)
    }
}

// ═══════════════════════════════════════════════════════════
// 2. 句法树节点 (TreeNode) — v3: 增加 key 字段
// ═══════════════════════════════════════════════════════════

class TreeNode {
    let name: String               // 节点标识 (Chord名 / Brick名 / 产生式结果)
    let startIndex: Int            // 在原始和弦序列中的起始位置
    let endIndex: Int              // 结束位置 (exclusive)
    let brickName: String?         // 匹配成功的Brick名称 (nil=未匹配)
    let children: [TreeNode]       // 子节点 (0=叶节点/ChordBlock, 1=一元, 2=二元)
    let cost: Int                  // 累积代价
    let key: Int?                  // 新增: 该节点根音模12值 (nil=未知/无调性)

    init(name: String, startIndex: Int, endIndex: Int,
         brickName: String? = nil, children: [TreeNode] = [],
         cost: Int = 0, key: Int? = nil) {
        self.name = name
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.brickName = brickName
        self.children = children
        self.cost = cost
        self.key = key
    }

    var isLeaf: Bool { children.isEmpty }

    /// 获取最右侧子节点的 key (用于合并节点继承调性)
    var rightmostKey: Int? {
        if isLeaf { return key }
        return children.last?.rightmostKey ?? key
    }

    /// 展平为 ChordBlock 名称列表
    func flattenNames() -> [String] {
        if isLeaf { return [name] }
        return children.flatMap { $0.flattenNames() }
    }

    /// 递归收集所有匹配成功的Brick名称
    func collectBricks() -> [String] {
        var result: [String] = []
        if let bn = brickName { result.append(bn) }
        for child in children { result.append(contentsOf: child.collectBricks()) }
        return result
    }
}

// ═══════════════════════════════════════════════════════════
// 3. CYK 解析引擎 (v3 修复版)
// ═══════════════════════════════════════════════════════════

struct CYKParser {

    /// 阶段4.2: 动态产生式开关 (true=动态生成, false=硬编码)
    static var useDynamicProductions = false

    /// 替换规则表
    private let substitutions: [SubstitutionDefinition]
    /// 二元产生式表
    private let binaryProductions: [BinaryProduction]
    /// 性能优化: 按 prod.left 建索引, 每个 cell 只遍历 left 匹配的产生式子集
    private let leftIndex: [String: [BinaryProduction]]

    init(substitutions: [SubstitutionDefinition] = Self.defaultSubstitutions,
         binaryProductions: [BinaryProduction]? = nil) {
        self.substitutions = substitutions
        self.binaryProductions = binaryProductions ?? Self.defaultProductions
        // 构建 left 索引: key = prod.left, value = 该 left 对应的所有产生式
        var idx: [String: [BinaryProduction]] = [:]
        for prod in self.binaryProductions {
            idx[prod.left, default: []].append(prod)
        }
        self.leftIndex = idx
    }

    // MARK: - 解析入口

    /// 对一段和弦序列做 CYK 句法解析
    /// - Parameter chords: 和弦名称数组
    /// - Returns: 最优解析树 (根节点)
    func parse(chords: [String]) -> TreeNode? {
        return parseInternal(chords: chords).root
    }

    /// 阶段4.1: 使用预计算标签替代substitution查找
    func parseWithLabels(labels: [String], chordNames: [String]) -> TreeNode? {
        return parseInternal(chords: chordNames, labels: labels).root
    }

    /// 性能优化: 同 parseWithLabels, 但返回 dp 表供 extractAllBricks 复用, 避免重跑 CYK
    /// 方案A: dp 改为多值 [[[String: TreeNode]]]
    func parseWithLabelsReturnDP(labels: [String], chordNames: [String]) -> (root: TreeNode?, dp: [[[String: TreeNode]]], n: Int) {
        return parseInternal(chords: chordNames, labels: labels)
    }

    /// 提取所有匹配到的Brick区间 (不要求完整语法树)
    /// - Returns: [(brickName, startIndex, endIndex)] — start包含, end不包含
    func extractAllBricks(chords: [String], labels: [String]? = nil) -> [(name: String, start: Double, end: Double)] {
        let (_, dp, n) = parseInternal(chords: chords, labels: labels)
        return extractAllBricks(from: dp, n: n)
    }

    /// 性能优化: 复用已有 dp 表提取 Brick 区间, 不再重跑 CYK
    /// 方案A: 遍历多值 dp[i][j].values
    func extractAllBricks(from dp: [[[String: TreeNode]]], n: Int) -> [(name: String, start: Double, end: Double)] {
        var result: [(name: String, start: Double, end: Double)] = []
        for i in 0..<n {
            let minJ = i + 2
            guard minJ <= n else { continue }
            for j in minJ...n {
                for node in dp[i][j].values {
                    guard let bn = node.brickName else { continue }
                    // 过滤中间节点: 长度超3且非最终组名
                    let isIntermediate = bn.count > 3 && bn.contains("_") && !bn.contains("-")
                    if isIntermediate { continue }
                    result.append((name: bn, start: Double(i), end: Double(j)))
                }
            }
        }
        return result
    }

    // MARK: - 内部实现

    private func parseInternal(chords: [String], labels: [String]? = nil) -> (root: TreeNode?, dp: [[[String: TreeNode]]], n: Int) {
        guard !chords.isEmpty else { return (nil, [], 0) }
        let n = chords.count
        // 方案A: dp 改为多值 [[[String: TreeNode]]], 每个格子按 brickName 去重存多个 TreeNode
        // 原版 Java 是 LinkedList<TreeNode>[][] (多值), Swift 之前简化成单值导致中间节点与最终砖互斥
        var dp: [[[String: TreeNode]]] = Array(repeating: Array(repeating: [:], count: n + 1), count: n)

        // ── 初始化: 叶节点 = 单个和弦 ──
        for i in 0..<n {
            let chordName = chords[i]
            let inputKey = ChordNameUtils.extractRoot(chordName)

            let bestBrick: String?
            let bestCost: Int

            if let preLabels = labels, i < preLabels.count {
                // 阶段4.1: substitution优先，预计算标签为fallback
                // 修复: 只做精确 chordName 匹配, 去掉 family+root 和 prefix 模糊匹配
                //   模糊匹配会把 Am7b5→"i"(应为iiø)、Gm6→"ii"(应为I), 导致 iiø-V-i 砖不匹配
                //   复杂和弦(m6/m7b5/7b13等)走 fallback labels (P0-d computeLabel), 标签正确
                let inputFamily = ChordNameUtils.chordToFamily(chordName)
                var bb: String? = nil
                var bc = Int.max
                for sub in substitutions where sub.chordName == chordName {
                    if sub.cost < bc { bc = sub.cost; bb = sub.brickName }
                }
                // fallback: 相对音程标签
                bestBrick = bb ?? preLabels[i]
                bestCost = bb != nil ? bc : 3  // 问题2: labels兜底cost从10降到3, 复杂和弦与常见和弦优先级接近
                // 🔍 DEBUG: 验证叶子 substitution 模糊匹配是否把 Am7b5→vi, Gm6→ii
                #if DEBUG
                if chordName == "Am7b5" || chordName == "Gm6" || chordName == "D7b13" {
                    dprint("🔍 [LEAF-DEBUG] \(chordName) -> \(bestBrick ?? "nil") (cost=\(bestCost), family=\(inputFamily), substitutionHit=\(bb != nil))")
                }
                #endif
            } else {
                // 回退: substitution 精确查找 (同有 labels 分支, 去掉模糊匹配)
                var bb: String? = nil
                var bc = Int.max
                for sub in substitutions where sub.chordName == chordName {
                    if sub.cost < bc { bc = sub.cost; bb = sub.brickName }
                }
                bestBrick = bb
                bestCost = bc
            }

            // 方案A: 多值 dp, 叶子节点按 brickName(或 chordName)作 key 存入字典
            let leafNode = TreeNode(
                name: chordName,
                startIndex: i, endIndex: i + 1,
                brickName: bestBrick,
                cost: bestCost,
                key: inputKey
            )
            let leafKey = bestBrick ?? chordName  // brickName 为 nil 时用 chordName 作 dictionary key
            dp[i][i + 1][leafKey] = leafNode
        }

        // ── CYK 动态规划: 合并子区间 (方案A 多值 dp) ──
        // 多值 dp: 每个格子存 [brickName: TreeNode], 中间节点与最终砖共存 (对齐原版 Java LinkedList<TreeNode>[][])
        // v3: 保留 modKeys 调性一致性校验
        for len in 2...n {
            for i in 0...(n - len) {
                let j = i + len
                // dp[i][j] 初始化为 [:], 无需 best 单值变量

                // fallback: 每个格子只保留 cost 最低的一个 (全局最优), 避免多值 dp 下节点爆炸
                var bestFallback: TreeNode? = nil
                var bestFallbackCost = Int.max

                for k in (i + 1)..<j {
                    let leftNodes = Array(dp[i][k].values)
                    let rightNodes = Array(dp[k][j].values)
                    guard !leftNodes.isEmpty, !rightNodes.isEmpty else { continue }

                    for left in leftNodes {
                        for right in rightNodes {
                            // 溢出保护
                            guard left.cost < Int.max / 2, right.cost < Int.max / 2 else { continue }

                            // 性能优化: 用 leftIndex 取候选产生式(双字段: brickName + name)
                            var candidateProds: [BinaryProduction] = []
                            if let bn = left.brickName, let prods = leftIndex[bn] {
                                candidateProds.append(contentsOf: prods)
                            }
                            if let prods = leftIndex[left.name] {
                                candidateProds.append(contentsOf: prods)
                            }
                            // 去重(同一产生式可能同时匹配 brickName 和 name)
                            var seenProd = Set<String>()
                            for prod in candidateProds {
                                let prodKey = "\(prod.left)|\(prod.right)|\(prod.result)"
                                guard !seenProd.contains(prodKey) else { continue }
                                seenProd.insert(prodKey)

                                let leftMatch = left.brickName == prod.left || left.name == prod.left
                                let rightMatch = right.brickName == prod.right || right.name == prod.right

                                guard leftMatch && rightMatch else { continue }

                                // ── v3 调性一致性校验 ──
                                if let expectedDiff = prod.keyDiff {
                                    if let lk = left.rightmostKey, let rk = right.rightmostKey {
                                        let actualDiff = ChordNameUtils.modKeys(rk - lk)
                                        let diffDelta = ChordNameUtils.modKeys(actualDiff - expectedDiff)
                                        if diffDelta != 0 && diffDelta != 11 {
                                            continue  // 调性不一致，跳过此产生式
                                        }
                                    }
                                    // key 信息缺失 (nil) 不强制校验
                                }

                                let totalCost = left.cost + right.cost + prod.weight
                                let node = TreeNode(
                                    name: prod.result,
                                    startIndex: i, endIndex: j,
                                    brickName: prod.result,
                                    children: [left, right],
                                    cost: totalCost,
                                    key: right.rightmostKey
                                )
                                // 按 brickName 去重插入: 同 key 只留 cost 最低的
                                let dictKey = prod.result
                                if let existing = dp[i][j][dictKey] {
                                    if totalCost < existing.cost {
                                        dp[i][j][dictKey] = node
                                    }
                                } else {
                                    dp[i][j][dictKey] = node
                                }
                            }

                            // fallback: 只记录全局最低 cost, 不在循环内写字典 (避免节点爆炸)
                            let fallbackCost = left.cost + right.cost + 100
                            if fallbackCost < bestFallbackCost {
                                bestFallbackCost = fallbackCost
                                bestFallback = TreeNode(
                                    name: "\(left.name)+\(right.name)",
                                    startIndex: i, endIndex: j,
                                    children: [left, right],
                                    cost: fallbackCost,
                                    key: right.rightmostKey
                                )
                            }
                        }
                    }
                }
                // 循环结束后写入 1 个 fallback (每个格子只存 cost 最低的一个)
                if let bf = bestFallback {
                    dp[i][j][bf.name] = bf
                }
            }
        }

        // root: 从多值 dp[0][n] 中取 cost 最低的完整解析树
        let root = dp[0][n].values.min(by: { $0.cost < $1.cost })
        return (root, dp, n)
    }

    // MARK: - 默认规则表 (v3: 增加 family + keyDiff)

    /// 默认替换规则: 常见和弦名 → Brick 映射 (覆盖12个爵士常用调)
    /// v3: 显式标注 family 字段，支持族级模糊匹配
    static let defaultSubstitutions: [SubstitutionDefinition] = [
        // ====== C大调 ======
        SubstitutionDefinition(chordName: "Dm7",   brickName: "ii",   cost: 1, family: .minor),
        SubstitutionDefinition(chordName: "G7",    brickName: "V",    cost: 1, family: .dominant),
        SubstitutionDefinition(chordName: "Cmaj7", brickName: "I",    cost: 1, family: .major),
        SubstitutionDefinition(chordName: "Fmaj7", brickName: "IV",   cost: 1, family: .major),
        SubstitutionDefinition(chordName: "Am7",   brickName: "vi",   cost: 1, family: .minor),
        SubstitutionDefinition(chordName: "Em7",   brickName: "iii",  cost: 1, family: .minor),
        SubstitutionDefinition(chordName: "Bm7b5", brickName: "viiø", cost: 1, family: .halfDiminished),
        SubstitutionDefinition(chordName: "Dm7b5", brickName: "iiø",  cost: 1, family: .halfDiminished),

        // ====== F大调 ======
        SubstitutionDefinition(chordName: "Gm7",   brickName: "ii",   cost: 1, family: .minor),
        SubstitutionDefinition(chordName: "C7",    brickName: "V",    cost: 1, family: .dominant),
        SubstitutionDefinition(chordName: "Fmaj7", brickName: "I",    cost: 2, family: .major),

        // ====== Bb大调 ======
        SubstitutionDefinition(chordName: "Cm7",   brickName: "ii",   cost: 1, family: .minor),
        SubstitutionDefinition(chordName: "F7",    brickName: "V",    cost: 1, family: .dominant),
        SubstitutionDefinition(chordName: "Bbmaj7",brickName: "I",    cost: 1, family: .major),

        // ====== Eb大调 ======
        SubstitutionDefinition(chordName: "Fm7",   brickName: "ii",   cost: 1, family: .minor),
        SubstitutionDefinition(chordName: "Bb7",   brickName: "V",    cost: 1, family: .dominant),
        SubstitutionDefinition(chordName: "Ebmaj7",brickName: "I",    cost: 1, family: .major),

        // ====== Ab大调 ======
        SubstitutionDefinition(chordName: "Bbm7",  brickName: "ii",   cost: 1, family: .minor),
        SubstitutionDefinition(chordName: "Eb7",   brickName: "V",    cost: 1, family: .dominant),
        SubstitutionDefinition(chordName: "Abmaj7",brickName: "I",    cost: 1, family: .major),

        // ====== Db大调 ======
        SubstitutionDefinition(chordName: "Ebm7",  brickName: "ii",   cost: 1, family: .minor),
        SubstitutionDefinition(chordName: "Ab7",   brickName: "V",    cost: 1, family: .dominant),
        SubstitutionDefinition(chordName: "Dbmaj7",brickName: "I",    cost: 1, family: .major),

        // ====== Gb大调 ======
        SubstitutionDefinition(chordName: "Abm7",  brickName: "bvi",  cost: 2, family: .minor),
        SubstitutionDefinition(chordName: "Db7",   brickName: "bII7", cost: 1, family: .dominant),
        SubstitutionDefinition(chordName: "Gbmaj7",brickName: "I",    cost: 1, family: .major),

        // ====== B大调 ======
        SubstitutionDefinition(chordName: "C#m7",  brickName: "ii",   cost: 1, family: .minor),
        SubstitutionDefinition(chordName: "F#7",   brickName: "V",    cost: 1, family: .dominant),
        SubstitutionDefinition(chordName: "Bmaj7", brickName: "I",    cost: 1, family: .major),

        // ====== E大调 ======
        SubstitutionDefinition(chordName: "F#m7",  brickName: "ii",   cost: 1, family: .minor),
        SubstitutionDefinition(chordName: "B7",    brickName: "V",    cost: 1, family: .dominant),
        SubstitutionDefinition(chordName: "Emaj7", brickName: "I",    cost: 1, family: .major),

        // ====== A大调 ======
        SubstitutionDefinition(chordName: "Bm7",   brickName: "ii",   cost: 1, family: .minor),
        SubstitutionDefinition(chordName: "E7",    brickName: "V",    cost: 1, family: .dominant),
        SubstitutionDefinition(chordName: "Amaj7", brickName: "I",    cost: 1, family: .major),

        // ====== D大调 ======
        SubstitutionDefinition(chordName: "Em7",   brickName: "ii",   cost: 2, family: .minor),
        SubstitutionDefinition(chordName: "A7",    brickName: "V",    cost: 1, family: .dominant),
        SubstitutionDefinition(chordName: "Dmaj7", brickName: "I",    cost: 1, family: .major),

        // ====== G大调 ======
        SubstitutionDefinition(chordName: "Am7",   brickName: "ii",   cost: 2, family: .minor),
        SubstitutionDefinition(chordName: "D7",    brickName: "V",    cost: 1, family: .dominant),
        SubstitutionDefinition(chordName: "Gmaj7", brickName: "I",    cost: 1, family: .major),
        SubstitutionDefinition(chordName: "Bm7",   brickName: "iii",  cost: 1, family: .minor),
        SubstitutionDefinition(chordName: "F#m7b5",brickName: "viiø", cost: 1, family: .halfDiminished),

        // ====== 副属/替代 (通用) ======
        SubstitutionDefinition(chordName: "E7",    brickName: "V/V",   cost: 2, family: .dominant),
        SubstitutionDefinition(chordName: "A7",    brickName: "V/ii",  cost: 2, family: .dominant),
        SubstitutionDefinition(chordName: "B7",    brickName: "V/iii", cost: 3, family: .dominant),
        SubstitutionDefinition(chordName: "Db7",   brickName: "bII7",  cost: 2, family: .dominant),
        SubstitutionDefinition(chordName: "G7b9",  brickName: "V", cost: 1, family: .dominant),
        SubstitutionDefinition(chordName: "Bdim7", brickName: "vii°",  cost: 1, family: .diminished),
        
        // M4: 常见小调ii-V-i + 扩展和弦变体 (cost=2降低优先级)
        SubstitutionDefinition(chordName: "Dm7b5", brickName: "iiø",   cost: 1, family: .halfDiminished), // Cm key
        SubstitutionDefinition(chordName: "G7#5",  brickName: "V", cost: 2, family: .dominant),
        SubstitutionDefinition(chordName: "Cm7",   brickName: "i",     cost: 2, family: .minor),         // minor tonic
        SubstitutionDefinition(chordName: "Em7b5", brickName: "iiø",   cost: 2, family: .halfDiminished), // Dm key
        SubstitutionDefinition(chordName: "A7b9",  brickName: "V", cost: 2, family: .dominant),
        SubstitutionDefinition(chordName: "Dm7",   brickName: "i",     cost: 3, family: .minor),
        
        // M2: A小调 iiø-V-i 冒烟测试 (Bm7b5→E7b9→Am)
        SubstitutionDefinition(chordName: "Bm7b5", brickName: "iiø",   cost: 0, family: .halfDiminished),
        SubstitutionDefinition(chordName: "E7b9",  brickName: "V", cost: 0, family: .dominant),
        SubstitutionDefinition(chordName: "Am",    brickName: "i",     cost: 0, family: .minor),
        
        // S1: 补缺失和弦标签 (消灭残余休止)
        SubstitutionDefinition(chordName: "Em7",   brickName: "iii",  cost: 2, family: .minor),
        SubstitutionDefinition(chordName: "Fm7",   brickName: "iv",   cost: 2, family: .minor),
        SubstitutionDefinition(chordName: "Emaj7", brickName: "I",    cost: 3, family: .major),
        SubstitutionDefinition(chordName: "B7",    brickName: "V",    cost: 2, family: .dominant),
        SubstitutionDefinition(chordName: "E7b13", brickName: "V",    cost: 2, family: .dominant),
        SubstitutionDefinition(chordName: "Ebdim7",brickName: "viio", cost: 2, family: .diminished),
    ]

    /// 默认二元产生式: 两个Brick→更大Brick
    /// v3: keyDiff 标注左右子节点间预期模12调差 (5=纯四度上行/纯五度下行, 2=大二度)
    static let defaultProductions: [BinaryProduction] = [
        // [级1] 二和弦核心组合
        BinaryProduction(left: "ii",   right: "V",     result: "ii-V",    weight: 1, keyDiff: 5),
        BinaryProduction(left: "V",    right: "I",     result: "V-I",     weight: 1, keyDiff: 5),
        BinaryProduction(left: "IV",   right: "V",     result: "IV-V",    weight: 2, keyDiff: 2),
        BinaryProduction(left: "I",    right: "IV",    result: "I-IV",    weight: 2, keyDiff: 5),
        BinaryProduction(left: "vi",   right: "ii",    result: "vi-ii",   weight: 1, keyDiff: 5),
        BinaryProduction(left: "iii",  right: "vi",    result: "iii-vi",  weight: 2, keyDiff: 5),

        // [级1] 三和弦经典进行 (ii-V-I 两种构造路径)
        BinaryProduction(left: "ii-V", right: "I",     result: "ii-V-I",  weight: 1, keyDiff: nil),
        BinaryProduction(left: "ii",   right: "V-I",   result: "ii-V-I",  weight: 2, keyDiff: nil),
        BinaryProduction(left: "ii-V", right: "V-I",   result: "ii-V-I",  weight: 3, keyDiff: nil),
        BinaryProduction(left: "IV-V", right: "I",     result: "IV-V-I",  weight: 2, keyDiff: nil),
        BinaryProduction(left: "vi-ii",right: "V",     result: "I-vi-ii-V",weight: 1, keyDiff: nil),

        // [级2] 小调 ii-V-i
        BinaryProduction(left: "iiø",  right: "V", result: "iiø-V",   weight: 1, keyDiff: 5),
        BinaryProduction(left: "iiø-V",right: "i",     result: "minor-ii-V-i", weight: 1, keyDiff: nil),

        // [级2] 副属进行
        BinaryProduction(left: "V/V",  right: "V",     result: "V/V-V",   weight: 3, keyDiff: 5),
        BinaryProduction(left: "V/ii", right: "ii",    result: "V/ii-ii", weight: 3, keyDiff: 5),
        BinaryProduction(left: "V/iii",right: "iii",   result: "V/iii-iii",weight: 3, keyDiff: 5),

        // [级3] 替代进行
        BinaryProduction(left: "bII7", right: "I",     result: "tritone-sub",   weight: 3, keyDiff: nil),
        BinaryProduction(left: "bII7", right: "ii-V-I",result: "tritone-sub-I", weight: 4, keyDiff: nil),
        BinaryProduction(left: "viiø", right: "iii",   result: "vii-iii",       weight: 4, keyDiff: nil),
        BinaryProduction(left: "ii-V",right: "iii-vi", result: "ii-V-iii-vi",   weight: 5, keyDiff: nil),
    ]
}
