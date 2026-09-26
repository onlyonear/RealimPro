import Foundation

// MARK: - BrickDictionaryParser — 解析原版 Impro-Visor 的 My.dictionary 砖库文件
//
// 原版格式 (S-表达式):
//   (defbrick Name(variant) Mode Type Key
//            (chord ChordName Duration)
//            (brick SubBrickName RefKey Duration))
//
// 关键设计:
//   1. 变体是任意字符串 (main/minor on/rainy/var 1 等), 不拼进最终砖名
//   2. 每个变体生成独立 BrickTemplate, name = 砖名 (不含变体)
//   3. 子砖引用展开时 transpose 到引用指定的 key
//   4. Type=Invisible 的砖只用于展开, 不加入最终库
//   5. duration 字段在展开阶段忽略 (CYK 只看和弦名序列)

struct BrickDictionaryParser {

    // MARK: - 解析中间结构

    private enum BrickSubBlock {
        case chord(name: String, duration: Int)
        case brickRef(name: String, key: Int, duration: Int)  // key = 引用指定的调性 PC
    }

    private struct RawBrickDef {
        let name: String           // 砖名 (不含变体)
        let variant: String        // 变体 (任意字符串, 默认 "")
        let mode: String           // Major/Minor/Dominant
        let type: String           // 砖类型 (Cadence/Approach/Invisible/... 16种值)
        let referenceKey: Int      // 参考调性 PC 0=C...11=B
        let subBlocks: [BrickSubBlock]
    }

    struct ParseResult {
        let bricks: [BrickLibrary.BrickTemplate]       // 展开后的可见砖 (Type != Invisible)
        let brickTypeCosts: [String: Int]              // brick-type 代价表 (16个)
        let invisibleCount: Int                          // Invisible 砖数量
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

        // 1. 移除注释
        let cleaned = removeComments(content)

        // 2. 词法分析
        let tokens = tokenize(cleaned)

        // 3. 第一遍: 解析所有 defbrick 和 brick-type
        var rawBricks: [RawBrickDef] = []
        var brickTypeCosts: [String: Int] = [:]
        var index = 0
        while index < tokens.count {
            if tokens[index] == "(" {
                index += 1  // 跳过 (
                if index < tokens.count {
                    let keyword = tokens[index]
                    index += 1
                    if keyword == "defbrick" {
                        if let def = parseDefbrick(tokens: tokens, index: &index) {
                            rawBricks.append(def)
                        }
                    } else if keyword == "brick-type" {
                        parseBrickType(tokens: tokens, index: &index, costs: &brickTypeCosts)
                    } else {
                        // 其他顶层表达式 (equiv/diatonic 等), 跳过到匹配的 )
                        skipToMatchingParen(tokens: tokens, index: &index)
                    }
                }
            } else {
                index += 1
            }
        }

        dprint("[BRICK-DICT] 第一遍解析: defbrick=\(rawBricks.count) brick-type=\(brickTypeCosts.count)")

        // 4. 构建 brickMap: 砖名 → 变体列表 (保持文件顺序)
        var brickMap: [String: [RawBrickDef]] = [:]
        for def in rawBricks {
            if brickMap[def.name] == nil {
                brickMap[def.name] = []
            }
            brickMap[def.name]!.append(def)
        }

        // 5. 第二遍: 递归展开所有子砖, 生成 BrickTemplate
        var resultBricks: [BrickLibrary.BrickTemplate] = []
        var invisibleCount = 0

        for def in rawBricks {
            if def.type == "Invisible" {
                invisibleCount += 1
                continue  // Invisible 砖不加入最终库
            }
            if let template = expandBrick(def, brickMap: brickMap, depth: 0) {
                resultBricks.append(template)
            }
        }

        dprint("[BRICK-DICT] 第二遍展开: visible=\(resultBricks.count) invisible=\(invisibleCount)")

        return ParseResult(
            bricks: resultBricks,
            brickTypeCosts: brickTypeCosts,
            invisibleCount: invisibleCount
        )
    }

    /// 加载默认的 My.dictionary (从 app bundle 或 grammars 目录)
    /// 返回 ParseResult (含 bricks + brickTypeCosts), 失败返回 nil
    /// 问题5: 改为返回完整 ParseResult, 暴露 brickTypeCosts 供 generateProductions 使用
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

    // MARK: - 注释移除

    private static func removeComments(_ content: String) -> String {
        var result = ""
        var lines = content.components(separatedBy: .newlines)
        for i in 0..<lines.count {
            var line = lines[i]
            // 移除 // 行注释
            if let slashRange = line.range(of: "//") {
                line = String(line[..<slashRange.lowerBound])
            }
            result += line + "\n"
        }
        // 移除 /* */ 块注释
        while let start = result.range(of: "/*") {
            if let end = result[start.upperBound...].range(of: "*/") {
                result.removeSubrange(start.lowerBound..<end.upperBound)
            } else {
                break  // 未闭合的块注释, 移除剩余部分
            }
        }
        return result
    }

    // MARK: - 词法分析

    private static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for char in input {
            if char == "(" || char == ")" {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                tokens.append(String(char))
            } else if char.isWhitespace || char.isNewline {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    // MARK: - 第一遍: 解析 defbrick

    private static func parseDefbrick(tokens: [String], index: inout Int) -> RawBrickDef? {
        guard index < tokens.count else { return nil }

        // 1. 读取砖名 (可能含变体括号)
        let nameToken = tokens[index]
        index += 1

        var brickName = ""
        var variant = ""

        if let parenStart = nameToken.firstIndex(of: "(") {
            brickName = String(nameToken[..<parenStart])
            let inside = nameToken[nameToken.index(after: parenStart)...]
            if let parenEnd = inside.firstIndex(of: ")") {
                variant = String(inside[..<parenEnd])
            }
        } else {
            brickName = nameToken
        }

        // 2. 读取 Mode (第3字段)
        guard index < tokens.count else { return nil }
        let mode = tokens[index]
        index += 1

        // 3. 读取 Type (第4字段, 16种值)
        guard index < tokens.count else { return nil }
        let type = tokens[index]
        index += 1

        // 4. 读取参考 Key (第5字段)
        guard index < tokens.count else { return nil }
        let keyStr = tokens[index]
        index += 1
        let referenceKey = noteNameToPC(keyStr)

        // 5. 读取子块列表, 直到匹配外层 )
        var subBlocks: [BrickSubBlock] = []
        while index < tokens.count && tokens[index] != ")" {
            if tokens[index] == "(" {
                index += 1  // 跳过 (
                guard index < tokens.count else { break }
                let subKeyword = tokens[index]
                index += 1
                if subKeyword == "chord" {
                    // (chord ChordName Duration)
                    guard index < tokens.count else { break }
                    let chordName = tokens[index]
                    index += 1
                    var duration = 1
                    if index < tokens.count && tokens[index] != ")" {
                        duration = Int(tokens[index]) ?? 1
                        index += 1
                    }
                    subBlocks.append(.chord(name: chordName, duration: duration))
                    // 跳过到 )
                    skipToMatchingParen(tokens: tokens, index: &index)
                } else if subKeyword == "brick" {
                    // (brick SubBrickName RefKey Duration)
                    guard index < tokens.count else { break }
                    let subBrickName = tokens[index]
                    index += 1
                    var refKey = 0
                    if index < tokens.count && tokens[index] != ")" {
                        refKey = noteNameToPC(tokens[index])
                        index += 1
                    }
                    var duration = 1
                    if index < tokens.count && tokens[index] != ")" {
                        duration = Int(tokens[index]) ?? 1
                        index += 1
                    }
                    subBlocks.append(.brickRef(name: subBrickName, key: refKey, duration: duration))
                    // 跳过到 )
                    skipToMatchingParen(tokens: tokens, index: &index)
                } else {
                    // 未知子块, 跳过
                    skipToMatchingParen(tokens: tokens, index: &index)
                }
            } else {
                index += 1
            }
        }

        // 跳过外层 )
        if index < tokens.count && tokens[index] == ")" {
            index += 1
        }

        return RawBrickDef(
            name: brickName,
            variant: variant,
            mode: mode,
            type: type,
            referenceKey: referenceKey,
            subBlocks: subBlocks
        )
    }

    // MARK: - 解析 brick-type

    private static func parseBrickType(tokens: [String], index: inout Int, costs: inout [String: Int]) {
        guard index < tokens.count else { return }
        let typeName = tokens[index]
        index += 1
        guard index < tokens.count else { return }
        let cost = Int(tokens[index]) ?? 0
        index += 1
        costs[typeName] = cost
        // 跳过到 )
        skipToMatchingParen(tokens: tokens, index: &index)
    }

    // MARK: - 跳过到匹配的右括号

    private static func skipToMatchingParen(tokens: [String], index: inout Int) {
        var depth = 1
        while index < tokens.count && depth > 0 {
            if tokens[index] == "(" {
                depth += 1
            } else if tokens[index] == ")" {
                depth -= 1
            }
            index += 1
        }
    }

    // MARK: - 第二遍: 递归展开子砖

    private static func expandBrick(_ def: RawBrickDef, brickMap: [String: [RawBrickDef]], depth: Int) -> BrickLibrary.BrickTemplate? {
        // 防止循环引用
        guard depth < 10 else {
            dprint("[BRICK-DICT] ⚠️ 递归深度超限, 截断砖: \(def.name)")
            return nil
        }

        var chords: [String] = []

        for subBlock in def.subBlocks {
            switch subBlock {
            case .chord(let name, _):
                // chord 只加 1 次和弦名 (duration 忽略)
                chords.append(name)

            case .brickRef(let subName, let refKey, _):
                // 查找子砖的所有变体, 选第一个 (对齐原版 getFirst())
                guard let subVariants = brickMap[subName], !subVariants.isEmpty else {
                    dprint("[BRICK-DICT] ⚠️ 子砖未找到: \(subName) (父砖: \(def.name))")
                    continue
                }
                let subDef = subVariants[0]  // 第一个变体 (含 Invisible)

                // 递归展开子砖
                guard let subTemplate = expandBrick(subDef, brickMap: brickMap, depth: depth + 1) else {
                    continue
                }

                // 核心: transpose 到引用指定的 key
                let transposed = subTemplate.transpose(to: refKey)
                chords.append(contentsOf: transposed.chords)
            }
        }

        // 每个变体生成独立 BrickTemplate, name = 砖名 (不含变体)
        let category = mapTypeToCategory(def.type)
        let beats = Double(chords.count)  // 每个和弦 1 拍

        return BrickLibrary.BrickTemplate(
            name: def.name,  // 核心: 不含变体
            chords: chords,
            category: category,
            style: ["swing", "bebop"],
            beats: beats,
            substitutions: [],
            referenceKey: def.referenceKey,
            type: def.type,          // 问题5: 传递原始 type 字符串, 用于 brick-type cost 差异化
            mode: def.mode           // P0: 传递调式 (Major/Minor/Dominant), 用于 findKeys Brick 分支
        )
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
        if upper.count >= 2 {
            let two = String(upper.prefix(2))
            if let pc = map[two] { return pc }
        }
        let one = String(upper.prefix(1))
        return map[one] ?? 0
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
