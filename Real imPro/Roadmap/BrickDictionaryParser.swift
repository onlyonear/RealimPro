import Foundation

// MARK: - BrickDictionaryParser — 解析原版 Impro-Visor 的 My.dictionary 砖库文件
//
// 原版格式 (嵌套 S-表达式):
//   (defbrick Name[(variant)] Mode Type Key
//            (chord ChordName Duration)
//            (brick SubBrickName[(subvariant)] RefKey Duration))
//
// 关键设计:
//   1. 完整 S-表达式递归建树：`Name(var 1)` 的 `(var 1)` 是 name 后的一个嵌套 list，
//      不再把 `(` `)` 当普通分隔符硬切（旧实现因此字段错位：mode="("、type=var、空壳）。
//   2. 变体是任意字符串 (main/var 1/3 steps 等), 不拼进最终砖名, 每个变体生成独立 BrickTemplate。
//   3. `(brick Sub (variant) Key dur)` 按 variant 选择对应子砖定义后递归展开, 再 transpose 到 Key。
//   4. Type=Invisible 的砖可作为子砖被引用展开, 但自身不进入最终可见砖库。
//   5. duration 字段在展开阶段忽略 (CYK 只看和弦名序列)。
//   6. equiv/diatonic 顶层表达式不解析（下游 PostProcessorFull 手抄 qualityClass/diatonicSets
//      已实测与词典语义等价，见 audit_harness/Q2_results.md）；不自动生成 Overrun/Dropback（已拍板放弃档B）。

struct BrickDictionaryParser {

    // MARK: - S 表达式节点

    private enum SNode {
        case atom(String)
        case list([SNode])

        var isList: Bool { if case .list = self { return true }; return false }
        var atomText: String { if case .atom(let s) = self { return s }; return "" }
        var children: [SNode] { if case .list(let c) = self { return c }; return [] }
    }

    // MARK: - 解析中间结构

    private struct RawDef {
        let name: String           // 砖名 (不含变体)
        let variant: String        // 变体 (任意字符串, 默认 "")
        let mode: String           // Major/Minor/Dominant
        let type: String           // 砖类型 (Cadence/Approach/Invisible/... 16种值)
        let referenceKey: Int      // 参考调性 PC 0=C...11=B
        let body: [SNode]          // (chord ...) / (brick ...) 子块
    }

    struct ParseResult {
        let bricks: [BrickLibrary.BrickTemplate]       // 展开后的可见砖 (Type != Invisible)
        let brickTypeCosts: [String: Int]              // brick-type 代价表 (16个)
        let invisibleCount: Int                        // Invisible 砖数量
    }

    // MARK: - 公共入口

    /// 从 My.dictionary 文件解析砖库
    /// - Parameter fileURL: My.dictionary 文件路径
    /// - Returns: 解析结果, 失败返回 nil
    static func parse(fileURL: URL) -> ParseResult? {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            dprint("[BRICK-DICT] ❌ 无法读取文件: \(fileURL.path)")
            return nil
        }

        // 1. 移除注释 + 词法/语法分析成 S 表达式树
        let cleaned = removeComments(content)
        let root = parseAll(cleaned)

        // 2. 第一遍: 解析所有 defbrick 和 brick-type (其余顶层表达式忽略)
        var rawDefs: [RawDef] = []
        var brickTypeCosts: [String: Int] = [:]

        for node in root {
            guard case .list(let items) = node, !items.isEmpty,
                  case .atom(let keyword) = items[0] else { continue }
            switch keyword {
            case "defbrick":
                if let d = parseDefbrick(items) { rawDefs.append(d) }
            case "brick-type":
                if items.count >= 3, case .atom(let t) = items[1], case .atom(let c) = items[2] {
                    brickTypeCosts[t] = Int(c) ?? 0
                }
            default:
                break  // equiv/diatonic 等: 下游手抄等价, 不解析
            }
        }

        dprint("[BRICK-DICT] 第一遍解析: defbrick=\(rawDefs.count) brick-type=\(brickTypeCosts.count)")

        // 3. brickMap: 砖名 → 变体定义列表 (保持文件顺序, 对齐 Java polymap)
        var brickMap: [String: [RawDef]] = [:]
        for d in rawDefs { brickMap[d.name, default: []].append(d) }

        // 4. 第二遍: 对全部 def (含 Invisible 叶子) 递归展开, 使其可被上层砖引用
        var allTemplates: [BrickLibrary.BrickTemplate] = []
        var invisibleCount = 0
        for d in rawDefs {
            if let t = expand(d, brickMap: brickMap, depth: 0) {
                allTemplates.append(t)
                if d.type == "Invisible" { invisibleCount += 1 }
            }
        }

        // 5. Invisible 砖只作展开积木, 不进入最终可见砖库
        let resultBricks = allTemplates.filter { $0.type != "Invisible" }

        dprint("[BRICK-DICT] 第二遍展开: visible=\(resultBricks.count) invisible=\(invisibleCount)")

        return ParseResult(
            bricks: resultBricks,
            brickTypeCosts: brickTypeCosts,
            invisibleCount: invisibleCount
        )
    }

    /// 加载默认的 My.dictionary (从 app bundle 或 grammars 目录)
    /// 返回 ParseResult (含 bricks + brickTypeCosts), 失败返回 nil
    static func loadDefault() -> ParseResult? {
        // 尝试从 bundle 加载
        if let bundleURL = Bundle.main.url(forResource: "My", withExtension: "dictionary") {
            if let result = parse(fileURL: bundleURL) {
                return result
            }
        }
        // 尝试从 grammars 目录加载 (开发环境)
        let fm = FileManager.default
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dictURL = appSupport.appendingPathComponent("grammars/My.dictionary")
            if fm.fileExists(atPath: dictURL.path) {
                if let result = parse(fileURL: dictURL) {
                    return result
                }
            }
        }
        dprint("[BRICK-DICT] ⚠️ 无法加载 My.dictionary, fallback 到硬编码砖")
        return nil
    }

    // MARK: - defbrick 解析 (从 S 表达式树读取, qualifier 是嵌套 list, 不会错位)

    private static func parseDefbrick(_ items: [SNode]) -> RawDef? {
        guard items.count >= 3, case .atom(let name) = items[1] else { return nil }
        var idx = 2
        var variant = ""
        // 名字后若紧跟一个 list, 它就是 (variant)
        if idx < items.count, items[idx].isList {
            variant = items[idx].children.map { $0.atomText }.joined(separator: " ")
            idx += 1
        }
        // 随后三个 atom: Mode / Type / Key
        guard idx + 2 < items.count,
              case .atom(let mode) = items[idx],
              case .atom(let type) = items[idx + 1],
              case .atom(let key) = items[idx + 2] else { return nil }
        idx += 3
        let body = Array(items[idx...])
        return RawDef(name: name, variant: variant, mode: mode, type: type,
                      referenceKey: noteNameToPC(key), body: body)
    }

    // MARK: - 递归展开 (按 variant 选子砖 + transpose)

    private static func expand(_ d: RawDef, brickMap: [String: [RawDef]], depth: Int) -> BrickLibrary.BrickTemplate? {
        // 防止循环引用
        guard depth < 12 else {
            dprint("[BRICK-DICT] ⚠️ 递归深度超限, 截断砖: \(d.name)")
            return nil
        }

        var chords: [String] = []
        for blk in d.body {
            guard case .list(let b) = blk, !b.isEmpty, case .atom(let kw) = b[0] else { continue }
            if kw == "chord", b.count >= 2, case .atom(let cn) = b[1] {
                chords.append(cn)
            } else if kw == "brick", b.count >= 2, case .atom(let subName) = b[1] {
                // (brick SubName [(subvariant)] RefKey Duration)
                var j = 2
                var subVariant = ""
                if j < b.count, b[j].isList {
                    subVariant = b[j].children.map { $0.atomText }.joined(separator: " ")
                    j += 1
                }
                guard j < b.count, case .atom(let refKeyStr) = b[j] else { continue }
                let refKey = noteNameToPC(refKeyStr)
                guard let subVariants = brickMap[subName], !subVariants.isEmpty else {
                    dprint("[BRICK-DICT] ⚠️ 子砖未找到: \(subName) (父砖: \(d.name))")
                    continue
                }
                // 按 variant 选择子砖定义, 无匹配回退第一个 (对齐 Java getFirst/variant 匹配)
                let subDef = subVariant.isEmpty
                    ? subVariants[0]
                    : (subVariants.first { $0.variant == subVariant } ?? subVariants[0])
                if let subTemplate = expand(subDef, brickMap: brickMap, depth: depth + 1) {
                    let transposed = subTemplate.transpose(to: refKey)
                    chords.append(contentsOf: transposed.chords)
                }
            }
        }

        return BrickLibrary.BrickTemplate(
            name: d.name,  // 不含变体
            chords: chords,
            category: mapTypeToCategory(d.type),
            style: ["swing", "bebop"],
            beats: Double(chords.count),
            substitutions: [],
            referenceKey: d.referenceKey,
            type: d.type,    // 原始 type, 供 brick-type cost 差异化
            mode: d.mode     // Major/Minor/Dominant, 供 findKeys Brick 分支
        )
    }

    // MARK: - 注释移除

    private static func removeComments(_ content: String) -> String {
        var result = ""
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            var l = line
            if let range = l.range(of: "//") { l = String(l[..<range.lowerBound]) }
            result += l + "\n"
        }
        while let start = result.range(of: "/*") {
            if let end = result[start.upperBound...].range(of: "*/") {
                result.removeSubrange(start.lowerBound..<end.upperBound)
            } else {
                break
            }
        }
        return result
    }

    // MARK: - 词法分析 (括号/空白切 token, 保留括号作为结构符)

    private static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for ch in input {
            if ch == "(" || ch == ")" {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(ch))
            } else if ch.isWhitespace || ch.isNewline {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    // MARK: - 递归构建 S 表达式树

    private static func parseAll(_ input: String) -> [SNode] {
        let tokens = tokenize(input)
        var index = 0
        var nodes: [SNode] = []
        while index < tokens.count {
            if let (node, next) = parseNode(tokens, index) {
                nodes.append(node); index = next
            } else {
                index += 1
            }
        }
        return nodes
    }

    private static func parseNode(_ tokens: [String], _ i: Int) -> (SNode, Int)? {
        guard i < tokens.count else { return nil }
        if tokens[i] == "(" {
            var idx = i + 1
            var children: [SNode] = []
            while idx < tokens.count && tokens[idx] != ")" {
                if tokens[idx] == "(" {
                    if let (sub, next) = parseNode(tokens, idx) { children.append(sub); idx = next }
                    else { idx += 1 }
                } else {
                    children.append(.atom(tokens[idx])); idx += 1
                }
            }
            return (.list(children), idx + 1)
        } else {
            return (.atom(tokens[i]), i + 1)
        }
    }

    // MARK: - 辅助函数

    /// 音名转 PC (0=C, 1=Db/C#, ..., 11=B)
    private static func noteNameToPC(_ name: String) -> Int {
        let upper = name.uppercased()
        let map: [String: Int] = [
            "C": 0, "C#": 1, "DB": 1, "D": 2, "D#": 3, "EB": 3,
            "E": 4, "F": 5, "F#": 6, "GB": 6, "G": 7, "G#": 8,
            "AB": 8, "A": 9, "A#": 10, "BB": 10, "B": 11
        ]
        if upper.count >= 2, let pc = map[String(upper.prefix(2))] { return pc }
        return map[String(upper.prefix(1))] ?? 0
    }

    /// Type 映射到 BrickCategory
    private static func mapTypeToCategory(_ type: String) -> BrickLibrary.BrickTemplate.BrickCategory {
        switch type.lowercased() {
        case "cadence", "deceptive-cadence":
            return .cadence
        case "turnaround":
            return .turnaround
        case "approach", "pullback", "dropback", "overrun", "ending", "opening":
            return .passing
        case "on-off", "off-on", "on-off+", "on":
            return .blues
        case "cesh":
            return .modal
        default:
            return .extended
        }
    }
}
