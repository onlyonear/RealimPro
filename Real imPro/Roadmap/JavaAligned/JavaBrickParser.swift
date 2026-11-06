//
//  JavaBrickParser.swift
//  RealimPro
//
//  J2（独立 Java 对齐 Roadmap 链）砖块字典解析 + 产生式构造。
//  忠实复刻 Java：
//    · BrickLibrary.processDictionary（BrickLibrary.java:645）
//        —— 读 My.dictionary 的 defbrick，递归实现子砖，Cadence 自动生成
//           Overrun / Dropback 变体（addBrick:173-237）；
//    · CYKParser.createRules（CYKParser.java:234）
//        —— 把砖编译成二元（BinaryProduction）/ 一元（UnaryProduction）产生式。
//
//  与现有 Swift BrickLibrary.swift（动态产生式、精选约109砖）完全分离、互不影响；
//  本文件只被 JavaAligned 链内部使用，不接 UI。
//

import Foundation

enum JavaBrickParser {

    // MARK: - 对外规则数据结构

    /// 产生式中的一个「体块」。
    /// - isChord=true：id 是 Advisor 家族串（dominant/minor7/major/minor/half-diminished/diminished/sus4）
    /// - isChord=false：id 是砖（或辅助非终结符）的内部名（空格）
    struct JPart: Equatable {
        let isChord: Bool
        let id: String
        let key: Int          // 相对砖 key 的半音偏移（mod12）；一元规则不用
        let dur: Int64
    }

    /// 二元产生式（对应 BinaryProduction）。
    struct JBRule: Equatable {
        let head: String          // 头符号（结果砖名；内部空格）
        let type: String          // 砖类型（Approach/Cadence/Invisible...）
        let mode: String
        let variant: String
        let cost: Int64
        let arbitrary: Bool       // 是否含任意时长（dur==0 通配）
        let p1: JPart
        let p2: JPart
    }

    /// 一元产生式（对应 UnaryProduction；单块砖）。
    struct JURule: Equatable {
        let head: String
        let type: String
        let mode: String
        let variant: String
        let cost: Int64
        let hk: Int               // 头砖 key（绝对）
        let termKey: Int          // 唯一体块 key（绝对）
        let part: JPart           // 体块（key 字段不用）
    }

    // MARK: - 砖类型成本（My.dictionary 的 16 条 brick-type，逐行实测）

    static let typeCost: [String: Int64] = [
        "Approach": 45,
        "Cadence": 25,
        "CESH": 10,
        "Deceptive-Cadence": 60,
        "Dropback": 30,
        "Ending": 30,
        "Invisible": 2000,
        "Overrun": 30,
        "On-Off": 1005,
        "Off-On": 1010,
        "On-Off+": 100,
        "On": 550,
        "Opening": 25,
        "Pullback": 45,
        "Turnaround": 20,
        "Misc": 40
    ]

    static func cost(of type: String) -> Int64 { typeCost[type] ?? 40 }

    // MARK: - 名字口径（dashless 内部空格 / dashed 显示连字符）

    static func dashless(_ s: String) -> String { s.replacingOccurrences(of: "-", with: " ") }
    static func dashed(_ s: String) -> String { s.replacingOccurrences(of: " ", with: "-") }

    // MARK: - 和弦名 → (root, family, rawQuality)

    /// 复用生产 PostProcessorFull 的根音/质量解析（单一事实来源），
    /// 再派生 Advisor 家族串与「保留大小写」的原始质量串。
    static func parseChord(_ name: String) -> (root: Int, family: String, rawQuality: String) {
        let parsed = PostProcessorFull.parseRootQuality(name)
        var q = parsed.quality
        if let slash = q.firstIndex(of: "/") { q = String(q[..<slash]) }
        let qc = PostProcessorFull.qualityClass(ofQuality: q)
        return (parsed.rootPC, familyString(qc, rawQuality: q), q)
    }

    /// RoadQualityClass + 原始质量 → Advisor 家族串。
    /// sus 单独识别（equiv: sus4→dominant，但 CYK 家族匹配需要 sus4）。
    static func familyString(_ qc: PostProcessorFull.RoadQualityClass, rawQuality q: String) -> String {
        if q.localizedCaseInsensitiveContains("sus") { return "sus4" }
        switch qc {
        case .dominant:   return "dominant"
        case .minor7:     return "minor7"
        case .halfDim:    return "half-diminished"
        case .diminished: return "diminished"
        case .minor:      return "minor"
        case .major:      return q.contains("aug") || q.contains("+") ? "augmented" : "major"
        default:          return "major"
        }
    }

    /// ChordBlock.findModeFromQuality（ChordBlock.java:502）——按质量文本【大小写】判调式。
    /// 关键 quirk：「maj7」是小写 m，不匹配大写 M → 落到 Minor（如 Bbmaj7 → Minor）。
    static func modeFromRawQuality(_ q: String) -> String {
        if q.hasPrefix("M") || q.isEmpty || q.hasPrefix("6") { return "Major" }
        if q.hasPrefix("7") || q.hasPrefix("9") || q.hasPrefix("11") || q.hasPrefix("13") {
            return "Dominant"
        }
        return "Minor"
    }

    // MARK: - S 表达式读取（Tokenizer 等价）

    /// 把字典文本切成 "(" / ")" / 普通 token，跳过 // 行注释与 /* 块注释。
    static func tokenize(_ s: String) -> [String] {
        // 关键：My.dictionary 是 Windows CRLF，Swift Character 把 "\r\n" 当作单个 grapheme，
        // 会使「找 "\n"」的行注释扫描一路吃到文件尾。先统一归一为 LF。
        let s = s.replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")
        let chars = Array(s)
        let n = chars.count
        var toks: [String] = []
        var i = 0
        while i < n {
            let c = chars[i]
            if c == "/" && i + 1 < n && chars[i + 1] == "/" {
                i += 2
                while i < n && chars[i] != "\n" { i += 1 }
            } else if c == "/" && i + 1 < n && chars[i + 1] == "*" {
                i += 2
                while i + 1 < n && !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i += 2
            } else if c == "(" || c == ")" {
                toks.append(String(c)); i += 1
            } else if c.isWhitespace {
                i += 1
            } else {
                var j = i
                while j < n {
                    let d = chars[j]
                    if d == "(" || d == ")" || d.isWhitespace { break }
                    j += 1
                }
                toks.append(String(chars[i..<j])); i = j
            }
        }
        return toks
    }

    /// token → 嵌套数组（叶子为 String）。
    static func parseSexpr(_ toks: [String]) -> [[Any]] {
        var pos = 0
        var top: [[Any]] = []
        func parseList() -> [Any] {
            pos += 1 // consume "("
            var arr: [Any] = []
            while pos < toks.count && toks[pos] != ")" {
                if toks[pos] == "(" { arr.append(parseList()) }
                else { arr.append(toks[pos]); pos += 1 }
            }
            if pos < toks.count { pos += 1 } // consume ")"
            return arr
        }
        while pos < toks.count {
            if toks[pos] == "(" { top.append(parseList()) }
            else { pos += 1 }
        }
        return top
    }

    // MARK: - 原始 defbrick（未实现引用）

    enum RawItem {
        case chord(root: Int, family: String, rawQuality: String, dur: Int64)
        case brick(name: String, variant: String, refKey: Int, dur: Int64)
    }

    struct RawDef {
        let name: String
        let variant: String
        let mode: String
        let type: String
        let key: Int
        let items: [RawItem]
    }

    static func asList(_ e: Any) -> [Any]? { e as? [Any] }
    static func str(_ e: Any) -> String {
        if let lst = e as? [Any] { return lst.map(str).joined(separator: " ") }
        return "\(e)"
    }

    /// 从一个 sexpr 元素取 (name, variant)；带括号限定符 → name=首项, variant=其余空格连接。
    static func nameVariant(_ e: Any) -> (name: String, variant: String) {
        if let lst = asList(e) {
            let nm = dashless(str(lst[0]))
            let variant = lst.dropFirst().map(str).joined(separator: " ")
            return (nm, variant)
        }
        return (dashless(str(e)), "")
    }

    static func parseDuration(_ e: Any) -> Int64 {
        let s = str(e)
        if s == "*" { return 0 }
        return Int64(s) ?? 0
    }

    /// 从全部顶层 sexpr 抽出 defbrick（其余 brick-type/diatonic/equiv 已硬编码，跳过）。
    static func parseRawDefs(_ tops: [[Any]]) -> [RawDef] {
        var defs: [RawDef] = []
        for arr in tops {
            guard arr.first.map(str) == "defbrick", arr.count >= 6 else { continue }
            var c = 1
            let baseName = dashless(str(arr[c])); c += 1
            var variant = ""
            // 名字后可紧跟一个括号限定符子列表 (main)/(var 1)/(minor on)，须先消费再读 mode/type/key。
            if c < arr.count, let ql = asList(arr[c]) {
                variant = ql.map(str).joined(separator: " ")
                c += 1
            }
            guard c + 3 <= arr.count else { continue }
            let mode = str(arr[c]); c += 1
            let type = str(arr[c]); c += 1
            let key = parseChord(str(arr[c])).root; c += 1
            var items: [RawItem] = []
            for it in arr.dropFirst(c) {
                guard let lst = asList(it), let head = lst.first.map(str) else { continue }
                if head == "chord" && lst.count == 3 {
                    let pc = parseChord(str(lst[1]))
                    items.append(.chord(root: pc.root, family: pc.family,
                                        rawQuality: pc.rawQuality, dur: parseDuration(lst[2])))
                } else if head == "brick" && (lst.count == 4 || lst.count == 5) {
                    // (brick Name[(variant)] RefKey dur)
                    var idx = 1
                    let bnv = nameVariant(lst[idx]); idx += 1
                    let refKey = parseChord(str(lst[idx])).root; idx += 1
                    let dur = parseDuration(lst[idx])
                    items.append(.brick(name: bnv.name, variant: bnv.variant,
                                        refKey: refKey, dur: dur))
                }
            }
            defs.append(RawDef(name: baseName, variant: variant, mode: mode,
                               type: type, key: key, items: items))
        }
        return defs
    }

    // MARK: - 递归实现（realize）

    /// 已实现的块（在某个具体 key 框架内）。
    indirect enum RealBlock {
        case chord(root: Int, family: String, rawQuality: String, dur: Int64)
        case brick(name: String, variant: String, mode: String, type: String,
                   key: Int, blocks: [RealBlock])
    }

    struct RealBrick {
        let name: String
        let variant: String
        let mode: String
        let type: String
        let key: Int
        let blocks: [RealBlock]
    }

    static func mod12(_ x: Int) -> Int { ((x % 12) + 12) % 12 }

    static func transpose(_ b: RealBlock, diff: Int) -> RealBlock {
        switch b {
        case .chord(let root, let family, let q, let dur):
            return .chord(root: mod12(root + diff), family: family, rawQuality: q, dur: dur)
        case .brick(let name, let variant, let mode, let type, let key, let blocks):
            return .brick(name: name, variant: variant, mode: mode, type: type,
                          key: mod12(key + diff),
                          blocks: blocks.map { transpose($0, diff: diff) })
        }
    }

    static func totalDur(_ b: RealBlock) -> Int64 {
        switch b {
        case .chord(_, _, _, let dur): return dur
        case .brick(_, _, _, _, _, let blocks): return blocks.map(totalDur).reduce(0, +)
        }
    }

    static func flatten(_ b: RealBlock) -> [RealBlock] {
        switch b {
        case .chord: return [b]
        case .brick(_, _, _, _, _, let blocks): return blocks.flatMap(flatten)
        }
    }

    /// 按比例缩放时长（Brick.setDuration:838；chord 用 ratio round，brick 递归）。
    static func scale(_ b: RealBlock, ratio: Double) -> RealBlock {
        switch b {
        case .chord(let root, let family, let q, let dur):
            let nd = max(0, Int64((Double(dur) * ratio).rounded()))
            return .chord(root: root, family: family, rawQuality: q, dur: nd)
        case .brick(let name, let variant, let mode, let type, let key, let blocks):
            return .brick(name: name, variant: variant, mode: mode, type: type, key: key,
                          blocks: blocks.map { scale($0, ratio: ratio) })
        }
    }

    /// 实现一个 RawDef 到它【自己的参考框架】（key=def.key）。
    static func realize(_ def: RawDef, defsByName: [String: [RawDef]]) -> RealBrick {
        var blocks: [RealBlock] = []
        for item in def.items {
            switch item {
            case .chord(let root, let family, let q, let dur):
                blocks.append(.chord(root: root, family: family, rawQuality: q, dur: dur))
            case .brick(let bname, let bvariant, let refKey, let dur):
                // 选被引用 def：variant 空 → 该名列表第一项；否则匹配 variant。
                guard let candidates = defsByName[bname], !candidates.isEmpty else {
                    continue
                }
                let refDef: RawDef
                if bvariant.isEmpty {
                    refDef = candidates[0]
                } else if let m = candidates.first(where: { $0.variant == bvariant }) {
                    refDef = m
                } else {
                    refDef = candidates[0]
                }
                let realized = realize(refDef, defsByName: defsByName)
                let diff = mod12(refKey - refDef.key)
                var child = RealBlock.brick(name: realized.name, variant: realized.variant,
                                           mode: realized.mode, type: realized.type,
                                           key: realized.key, blocks: realized.blocks)
                child = transpose(child, diff: diff)
                if dur > 0 {
                    // 具体时长：按比例缩放到目标 dur。
                    let cur = totalDur(child)
                    if cur > 0 && cur != dur {
                        child = scale(child, ratio: Double(dur) / Double(cur))
                    }
                } else {
                    // 通配 "*"：Java getBrick(...,d=0)→setDuration(0)，子砖全部 0 时长（arbitrary），
                    // 靠 overlapCopy 在表内匹配，不额外占用真实叶子。
                    child = scale(child, ratio: 0)
                }
                // 引用块以被引用砖名呈现（内部名）
                blocks.append(child)
            }
        }
        return RealBrick(name: def.name, variant: def.variant, mode: def.mode,
                         type: def.type, key: def.key, blocks: blocks)
    }

    // MARK: - Overrun / Dropback 变体（addBrick:173-237）

    /// 对一个已实现 Cadence 砖生成 Overrun / Dropback。
    static func cadenceVariants(_ cad: RealBrick) -> [RealBrick] {
        guard cad.type == "Cadence" else { return [] }
        let leaves = flatten(.brick(name: cad.name, variant: cad.variant, mode: cad.mode,
                                    type: cad.type, key: cad.key, blocks: cad.blocks))
        guard let lastCase = leaves.last,
              case .chord(let lastRoot, let lastFamily, let lastQ, let lastDur) = lastCase else {
            return []
        }
        func cadBlock() -> RealBlock {
            .brick(name: cad.name, variant: cad.variant, mode: cad.mode, type: cad.type,
                   key: cad.key, blocks: cad.blocks)
        }

        // Overrun：终止式 + 末和弦圈五下一和弦（同名质量）。
        let ovChord: RealBlock = .chord(root: mod12(lastRoot + 5), family: lastFamily,
                                        rawQuality: lastQ, dur: lastDur)
        let overrun = RealBrick(name: cad.name + " + Overrun", variant: cad.variant,
                                mode: cad.mode, type: "Overrun", key: cad.key,
                                blocks: [cadBlock(), ovChord])

        // Dropback：终止式 + 相对 VI（key+9）属七。
        let dbChord: RealBlock = .chord(root: mod12(cad.key + 9), family: "dominant",
                                        rawQuality: "7", dur: lastDur)
        let dropback = RealBrick(name: cad.name + " + Dropback", variant: cad.variant,
                                 mode: cad.mode, type: "Dropback", key: cad.key,
                                 blocks: [cadBlock(), dbChord])
        return [overrun, dropback]
    }

    // MARK: - createRules（CYKParser.java:234）

    /// 一个块在【砖参考框架】内的体描述。key＝该块在参考框架内的绝对根音（chord）或砖 key。
    static func blockSymbol(_ b: RealBlock) -> (isChord: Bool, id: String, key: Int, dur: Int64) {
        switch b {
        case .chord(let root, let family, _, let dur):
            return (true, family, root, dur)
        case .brick(let name, _, _, _, let key, _):
            return (false, name, key, totalDur(b))
        }
    }

    static func anyArbitrary(in blocks: [RealBlock]) -> Bool {
        for b in blocks {
            for leaf in flatten(b) {
                if case .chord(_, _, _, let dur) = leaf, dur == 0 { return true }
            }
        }
        return false
    }

    /// 把全部已实现砖（含变体）编译成 (binary, unary) 规则。
    static func createRules(_ bricks: [RealBrick]) -> (binary: [JBRule], unary: [JURule]) {
        // 先收集所有「砖名 + 辅助非终结符名」用于 K/C 分类。
        var headSet = Set<String>()
        for rb in bricks {
            headSet.insert(rb.name)
            let sz = rb.blocks.count
            if sz > 2 {
                for k in 1..<(sz - 1) { headSet.insert(rb.name + rb.variant + String(k)) }
            }
        }
        func makePart(_ b: RealBlock, brickKey: Int) -> JPart {
            let s = blockSymbol(b)
            let isK = !s.isChord && headSet.contains(s.id)
            return JPart(isChord: !isK, id: isK ? s.id : s.id,
                         key: mod12(s.key - brickKey), dur: s.dur)
        }

        var binary: [JBRule] = []
        var unary: [JURule] = []

        for rb in bricks {
            let subs = rb.blocks
            let sz = subs.count
            guard sz >= 1 else { continue }

            if sz == 1 {
                let s = blockSymbol(subs[0])
                let isK = !s.isChord && headSet.contains(s.id)
                let part = JPart(isChord: !isK, id: s.id,
                                 key: mod12(s.key - rb.key), dur: s.dur)
                unary.append(JURule(head: rb.name, type: rb.type, mode: rb.mode,
                                    variant: rb.variant, cost: cost(of: rb.type),
                                    hk: rb.key, termKey: s.key, part: part))
            } else if sz == 2 {
                let arbitrary = anyArbitrary(in: subs)
                binary.append(JBRule(head: rb.name, type: rb.type, mode: rb.mode,
                                     variant: rb.variant, cost: cost(of: rb.type),
                                     arbitrary: arbitrary,
                                     p1: makePart(subs[0], brickKey: rb.key),
                                     p2: makePart(subs[1], brickKey: rb.key)))
            } else {
                // 3+ 块：辅助链。
                let leafDur: [Int64] = subs.map { blockSymbol($0).dur }

                // 第一规则：b0 + b1
                let aux1 = rb.name + rb.variant + "1"
                binary.append(JBRule(head: aux1, type: "Invisible", mode: rb.mode,
                                     variant: rb.variant, cost: cost(of: "Invisible"),
                                     arbitrary: anyArbitrary(in: [subs[0], subs[1]]),
                                     p1: makePart(subs[0], brickKey: rb.key),
                                     p2: makePart(subs[1], brickKey: rb.key)))
                var prevAux = aux1
                var prevDur = leafDur[0] + leafDur[1]

                // 中间规则
                for i in 2..<(sz - 1) {
                    let auxN = rb.name + rb.variant + String(i)
                    let auxChild = JPart(isChord: false, id: prevAux, key: 0, dur: prevDur)
                    binary.append(JBRule(head: auxN, type: "Invisible", mode: rb.mode,
                                         variant: rb.variant, cost: cost(of: "Invisible"),
                                         arbitrary: anyArbitrary(in: Array(subs[0...i])),
                                         p1: auxChild,
                                         p2: makePart(subs[i], brickKey: rb.key)))
                    prevDur += leafDur[i]
                    prevAux = auxN
                }

                // 最终规则
                let auxChild = JPart(isChord: false, id: prevAux, key: 0, dur: prevDur)
                binary.append(JBRule(head: rb.name, type: rb.type, mode: rb.mode,
                                     variant: rb.variant, cost: cost(of: rb.type),
                                     arbitrary: anyArbitrary(in: subs),
                                     p1: auxChild,
                                     p2: makePart(subs[sz - 1], brickKey: rb.key)))
            }
        }
        return (binary, unary)
    }

    // MARK: - 总入口

    /// 从字典文本构建全部规则（含 Overrun/Dropback 变体）。
    static func buildRules(fromDictionaryText text: String)
        -> (binary: [JBRule], unary: [JURule], brickCount: Int) {
        let tops = parseSexpr(tokenize(text))
        let rawDefs = parseRawDefs(tops)
        var defsByName: [String: [RawDef]] = [:]
        for d in rawDefs {
            defsByName[d.name, default: []].append(d)
        }

        var allBricks: [RealBrick] = []
        for d in rawDefs {
            let rb = realize(d, defsByName: defsByName)
            allBricks.append(rb)
            if rb.type == "Cadence" {
                allBricks.append(contentsOf: cadenceVariants(rb))
            }
        }

        let rules = createRules(allBricks)
        return (rules.binary, rules.unary, allBricks.count)
    }

    /// 从 App 包内 My.dictionary 加载规则。
    static func loadBundledRules() -> (binary: [JBRule], unary: [JURule])? {
        guard let url = Bundle.main.url(forResource: "My", withExtension: "dictionary"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let r = buildRules(fromDictionaryText: text)
        return (r.binary, r.unary)
    }
}
