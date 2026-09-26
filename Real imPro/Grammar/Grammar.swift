//
//  Grammar.swift
//  Improlyze
//
//  Grammar 核心引擎 - 解析语法文件，生成抽象旋律
//  第一阶段：支持最简单的语法（base, rule, 变量, 简单表达式）
//

import Foundation

// MARK: - 语法规则

/// 语法规则
struct GrammarRule {
    let lhs: String           // 左部非终结符名
    let lhsParams: [String]   // 左部参数名
    let rhs: [GrammarSymbol]  // 右部展开结果
    let weight: Double        // 权重（parse时默认值，展开时重算）
    let isBase: Bool          // 是否是 base 规则（优先级高）
    let condition: String?    // 条件表达式 (如 "(builtin brick Sad-Cadence)") 展开时求值
}


// MARK: - Grammar 引擎

class Grammar {
    
    // MARK: - 属性

    private var rules: [GrammarRule] = []
    private var startSymbol: String = ""
    /// 原私有parameters废弃，改用对外可访问的主参数字典
    public var masterParameters: [String: Any] = [:]
    
    // 变量环境 - 用于变量替换
    private var variableEnvironment: [String: Int] = [:]
    
    // 终结符缓冲区 - 收集生成的终结符
    private var terminalBuffer: [GrammarTerminal] = []
    
    // 当前槽位
    private var currentSlot: Int = 0
    private var totalSlots: Int = 0
    
    // 当前和弦（用于 chord-family builtin）
    public var currentChordName: String = "C"
    public var currentChordBlock: ChordBlock?
    
    var slotsPerBeat: Int = 120        // quarter note = 120 slots (default 4/4)
    var beatsPerMeasure: Int = 4       // numerator of time signature
    var measureOffset: Int = 0         // absolute slot position of current chord within measure
    private var pendingApproach: Bool = false  // A→CHORD resolution gate
    
    // ═════ Beat position helpers (Java Scorer.java strongBeatScore alignment) ═════
    private var measureLength: Int { beatsPerMeasure * slotsPerBeat }
    private var strongBeatsPerMeasure: Int {
        if beatsPerMeasure <= 3 { return 1 }              // 2/4, 3/4 → 1 strong beat
        else if beatsPerMeasure % 2 == 0 { return 2 }     // 4/4, 6/8, 12/8 → 2 strong beats
        else if beatsPerMeasure % 3 == 0 { return 3 }     // 9/8 → 3 strong beats
        return 1
    }
    private var timeBetweenStrongBeats: Int { measureLength / strongBeatsPerMeasure }
    
    private func absSlot() -> Int { measureOffset + currentSlot }
    
    private func isOnBeat() -> Bool { absSlot() % slotsPerBeat == 0 }
    private func isStrongBeat() -> Bool { absSlot() % timeBetweenStrongBeats == 0 }
    
    // 栈式展开用的符号栈
    private var stack: [GrammarSymbol] = []
    
    // Share 缓存: 参数化键 "name:param1:param2" → 展开结果
    // M2: 支持参数化多层嵌套share，CharlieParker BRICK规则复用核心
    private var shareCache: [String: [GrammarSymbol]] = [:]
    private func shareKey(_ name: String, _ params: [Int]) -> String {
        return name + ":" + params.map(String.init).joined(separator: ":")
    }
    
    // MARK: 分级调试日志工具
    /// 日志类型区分：chord 和弦匹配 / rule 规则选择 / pitch 音池抽样 / general 通用
    enum LogType: String {
        case chordMatch = "【和弦匹配】"
        case ruleSelect = "【规则选择】"
        case pitchSample = "【音高抽样】"
        case general = "【通用文法】"
    }
    
    private func log(_ type: LogType, msg: String) {
        // 如需关闭日志，注释下方print一行即可
        #if DEBUG
        dprint("Grammar \(type.rawValue) \(msg)")
        #endif
    }
    
    // MARK: - 初始化
    
    init(grammarFile: String) {
        loadGrammarFile(grammarFile)
    }
    
    // MARK: 新增无参构造，供Strategy动态替换文件使用
    init() {}
    
    // MARK: - 加载语法文件
    
    private func loadGrammarFile(_ fileName: String) {
        #if DEBUG
        dprint("Grammar: 尝试加载文件 \(fileName).grammar")
        #endif
        
        guard let filePath = Bundle.main.path(forResource: fileName, ofType: "rules") else {
            dprint("Grammar: ❌ 找不到文件 \(fileName).grammar")
            #if DEBUG
            dprint("Grammar: Bundle 路径: \(Bundle.main.bundlePath)")
            #endif
            return
        }
        
        //dprint("Grammar: ✅ 找到文件，路径: \(filePath)")
        
        do {
            let content = try String(contentsOfFile: filePath, encoding: .utf8)
            //dprint("Grammar: ✅ 文件读取成功，内容长度: \(content.count) 字符")
            //dprint("Grammar: 文件前 200 字符:\n\(String(content.prefix(200)))")
            parseGrammarContent(content)
            //dprint("Grammar: ✅ 解析完成，共 \(rules.count) 条规则")
            //dprint("Grammar: 开始符号: \(startSymbol)")
            for (i, rule) in rules.enumerated() {
                //dprint("Grammar:   规则 \(i): \(rule.lhs) (base=\(rule.isBase), params=\(rule.lhsParams), weight=\(rule.weight))")
            }
        } catch {
            //dprint("Grammar: ❌ 读取文件失败 \(error)")
        }
    }
    
    // MARK: - 解析语法内容
    
    private func parseGrammarContent(_ content: String) {
        // 按行处理，去掉注释和空行
        let lines = content.components(separatedBy: .newlines)
        
        var allExpressions: [String] = []
        var currentExpression = ""
        var parenCount = 0
        
        for line in lines {
            // 去掉注释
            let cleanedLine = line.components(separatedBy: ";").first ?? ""
            
            for char in cleanedLine {
                if char == "(" {
                    parenCount += 1
                    currentExpression.append(char)
                } else if char == ")" {
                    parenCount -= 1
                    currentExpression.append(char)
                    
                    if parenCount == 0 {
                        allExpressions.append(currentExpression.trimmingCharacters(in: .whitespacesAndNewlines))
                        currentExpression = ""
                    }
                } else {
                    if parenCount > 0 {
                        currentExpression.append(char)
                    }
                }
            }
        }
        
        // 解析每个表达式
        for expr in allExpressions {
            parseExpression(expr)
        }
    }
    
    // MARK: - 解析单个表达式
    
    private func parseExpression(_ expr: String) {
        // 去掉最外层的括号
        let inner = String(expr.dropFirst().dropLast())
        let tokens = tokenize(inner)
        
        guard !tokens.isEmpty else { return }
        
        let firstToken = tokens[0]
        
        switch firstToken {
        case "startsymbol":
            if tokens.count > 1 {
                startSymbol = tokens[1]
            }
            
        case "parameter":
            if tokens.count > 1 {
                let paramStr = tokens.dropFirst().joined(separator: " ")
                if let paramExpr = parseSimpleList(paramStr) {
                    if paramExpr.count == 2 {
                        let key = paramExpr[0]
                        let rawVal = paramExpr[1]
                        // 优先尝试转整数（适配 min-pitch 58 / max-pitch 82）
                        if let intNum = Int(rawVal) {
                            masterParameters[key] = intNum
                        } else if let doubleNum = Double(rawVal) {
                            // 浮点参数（chord-tone-weight 0.7 / leap-prob 0.01 等）
                            masterParameters[key] = doubleNum
                        } else {
                            // 字符串类型参数兜底
                            masterParameters[key] = rawVal
                        }
                    }
                }
            }
            
        case "base":
            parseRule(tokens: Array(tokens.dropFirst()), isBase: true)
            
        case "rule":
            parseRule(tokens: Array(tokens.dropFirst()), isBase: false)
            
        default:
            // 其他类型暂时忽略
            break
        }
    }
    
    // MARK: - 解析规则
    
    private func parseRule(tokens: [String], isBase: Bool) {
        guard tokens.count >= 3 else { return }
        
        // 左部：比如 (P 0) 或 (P Y)
        let lhsStr = tokens[0]
        let lhsTokens = parseSimpleList(lhsStr) ?? []
        
        guard !lhsTokens.isEmpty else { return }
        
        let lhsName = lhsTokens[0]
        let lhsParams = Array(lhsTokens.dropFirst())
        
        // 右部：比如 (Seg1 (P (- Y 120)))
        let rhsStr = tokens[1]
        
        // 权重：支持固定数字 / (expr == target) 条件表达式
        let weightStr = tokens[2]
        var finalWeight: Double = 1.0
        if weightStr.contains("!=") {
            // M6: != 条件权重 — (builtin brick X) != target → 非匹配时激活
            let parts = weightStr.components(separatedBy: "!=").map{ $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                let exprResult = evaluateExpr(parts[0])
                finalWeight = formatExprValue(exprResult) != parts[1] ? 1.0 : 0.0
            } else {
                finalWeight = 1.0
            }
        } else if weightStr.contains("==") {
            // 拆分表达式与目标字符串
            let parts = weightStr.components(separatedBy: "==").map{ $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                let exprRaw = parts[0]
                let targetVal = parts[1]
                // 求值表达式字符串
                let exprResult = evaluateExpr(exprRaw)
                // 用 formatExprValue 格式化（整数去 .0, 小数保留），避免 "1.0" != "1" 语义 bug
                let exprStr = formatExprValue(exprResult)
                finalWeight = exprStr == targetVal ? 1.0 : 0.0
            } else {
                log(.ruleSelect, msg: "警告：权重表达式分割异常(==数量不对)，使用默认权重1.0，原始字符串：\(weightStr)")
                finalWeight = 1.0
            }
        } else if weightStr.hasPrefix("(builtin") {
            // M2: builtin 表达式不转数字，condition 字段已独立保存
            finalWeight = 1.0
        } else {
            // 普通数字权重
            finalWeight = Double(weightStr) ?? {
                log(.ruleSelect, msg: "警告：权重无法转为数字，使用默认权重1.0，原始字符串：\(weightStr)")
                return 1.0
            }()
        }
        
        // 解析右部
        let rhsSymbols = parseRHS(rhsStr)
        
        // 条件表达式 (builtin brick X)，展开时与 currentChordBlock 求值
        let conditionExpr: String? = weightStr.hasPrefix("(builtin") ? weightStr : nil
        
        let rule = GrammarRule(
            lhs: lhsName,
            lhsParams: lhsParams,
            rhs: rhsSymbols,
            weight: finalWeight,
            isBase: isBase,
            condition: conditionExpr
        )
        
        rules.append(rule)
        
        // Debug: 打印右部详情
        //dprint("Grammar:     右部符号数: \(rhsSymbols.count)")
        for (j, sym) in rhsSymbols.enumerated() {
            //dprint("Grammar:       [\(j)] \(sym)")
        }
    }
    
    // MARK: - 解析右部
    
    private func parseRHS(_ rhsStr: String) -> [GrammarSymbol] {
        var symbols: [GrammarSymbol] = []
        
        // 去掉最外层括号
        let inner = String(rhsStr.dropFirst().dropLast())
        let tokens = tokenize(inner)
        
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            
            if token.hasPrefix("(") {
                // 这是一个列表，可能是非终结符带参数，或者特殊形式
                // 找到匹配的右括号
                var listStr = ""
                var parenCount = 0
                var j = i
                
                while j < tokens.count {
                    for char in tokens[j] {
                        if char == "(" { parenCount += 1 }
                        if char == ")" { parenCount -= 1 }
                    }
                    listStr += tokens[j] + " "
                    j += 1
                    
                    if parenCount == 0 { break }
                }
                
                listStr = listStr.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // 解析这个列表
                if let symbol = parseListSymbol(listStr) {
                    symbols.append(symbol)
                }
                
                i = j
            } else {
                // 单个 token，可能是终结符或非终结符
                if let terminal = GrammarTerminalParser.parseTerminal(token) {
                    symbols.append(.terminal(terminal))
                } else {
                    symbols.append(.nonTerminal(token, []))
                }
                
                i += 1
            }
        }
        
        return symbols
    }
    
    // MARK: - 解析列表符号
    
    private func parseListSymbol(_ listStr: String) -> GrammarSymbol? {
        let inner = String(listStr.dropFirst().dropLast())
        let tokens = tokenize(inner)
        
        guard !tokens.isEmpty else { return nil }
        
        let firstToken = tokens[0]
        
        // 检查是不是 scale degree 终结符，比如 (X 3 8) 或 (X b5 4.)
        if firstToken == "X" && tokens.count == 3 {
            if let terminal = GrammarTerminalParser.parseScaleDegreeTerminal(tokens) {
                return .terminal(terminal)
            }
        }
        
        // 检查是不是 slope 终结符
        if firstToken == "slope" {
            if let terminal = GrammarTerminalParser.parseSlopeTerminal(tokens) {
                return .terminal(terminal)
            }
        }
        
        // 新增 triadic 三和弦分解语法解析
        if firstToken == "triadic", tokens.count == 2 {
            if let terminal = GrammarTerminalParser.parseTriadicTerminal(tokens) {
                return .terminal(terminal)
            }
        }
        
        // F1: fill 包装器 — (fill 4 (V4 V4)) 在指定拍数内循环填充
        if firstToken == "fill", tokens.count >= 3 {
            return .nonTerminal("fill", Array(tokens.dropFirst()))
        }
        
        // 检查是不是表达式，比如 (- Y 120)
        if firstToken == "+" || firstToken == "-" || firstToken == "*" || firstToken == "/" {
            // 这是一个表达式，第一阶段我们在展开时求值
            return .nonTerminal(firstToken, [])
        }
        
        // 否则认为是非终结符带参数，保留原始字符串，展开时再求值
        let params = Array(tokens.dropFirst())
        return .nonTerminal(firstToken, params)
    }
    
    // MARK: - 分词（修复版：正确处理括号内的空格）
    
    private func tokenize(_ string: String) -> [String] {
        var tokens: [String] = []
        var currentToken = ""
        var parenDepth = 0
        
        for char in string {
            if char == "(" {
                // 只有在最外层（括号深度为0）时，左括号才开始新 token
                if parenDepth == 0 && !currentToken.isEmpty {
                    tokens.append(currentToken)
                    currentToken = ""
                }
                currentToken.append(char)
                parenDepth += 1
            } else if char == ")" {
                currentToken.append(char)
                parenDepth -= 1
                // 只有回到最外层时，右括号才结束当前 token
                if parenDepth == 0 {
                    tokens.append(currentToken)
                    currentToken = ""
                }
            } else if char.isWhitespace {
                // 只有在最外层时，空格才分隔 token
                if parenDepth == 0 && !currentToken.isEmpty {
                    tokens.append(currentToken)
                    currentToken = ""
                } else if parenDepth > 0 {
                    // 括号内的空格，保留在 token 中
                    currentToken.append(char)
                }
            } else {
                currentToken.append(char)
            }
        }
        
        if !currentToken.isEmpty {
            tokens.append(currentToken)
        }
        
        return tokens
    }
    
    // MARK: - 解析简单列表
    
    private func parseSimpleList(_ string: String) -> [String]? {
        let str = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard str.hasPrefix("(") && str.hasSuffix(")") else {
            // 不是列表，直接返回单个元素
            return [str]
        }
        
        let inner = String(str.dropFirst().dropLast())
        return inner.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    }
    
    // MARK: - 运行生成
    
    func run(startSlot: Int, numSlots: Int) -> [GrammarTerminal] {
        #if DEBUG
        dprint("[GRAMMAR-RUN] startSlot=\(startSlot) numSlots=\(numSlots)")
        #endif
        // 重置状态
        terminalBuffer = []
        currentSlot = startSlot
        totalSlots = numSlots
        variableEnvironment = [:]
        stack = []
        shareCache = [:]
        
        // 从开始符号开始，参数是总 slots 数
        let startSym = GrammarSymbol.nonTerminal(startSymbol, [String(numSlots)])
        stack.append(startSym)
        // 阶段2新增：初始化时清空share缓存（防止跨和弦缓存污染）
        shareCache.removeAll()
        
        // 栈式迭代展开
        var remainingSlots = numSlots
        var iterations = 0
        let maxIterations = 10000 // 安全限制，防止死循环
        
        while remainingSlots > 0 && !stack.isEmpty && iterations < maxIterations {
            iterations += 1
            
            // 1. 收集栈顶的终结符
            remainingSlots = accumulateTerminals()
            
            // 2. 如果栈空了或者填满了，退出
            if stack.isEmpty || remainingSlots <= 0 {
                break
            }
            
            // 3. 展开栈顶的非终结符
            remainingSlots = applyRules()
        }
        
        // 🌟 终极修复 1：如果语法树提前结束，导致当前和弦的 slots 没填满，
        // 必须用休止符填满黑洞！否则 ContentView 会把下一个和弦的音符往前生拉硬拽导致跨拍错位！
        if currentSlot < totalSlots {
            let gap = totalSlots - currentSlot
            if gap > 0 {
                let rest = GrammarTerminal(type: .rest, durationSlots: gap, isDotted: false, tuplet: 0)
                terminalBuffer.append(rest)
                currentSlot = totalSlots
                #if DEBUG
                dprint("Grammar: 🩹 探测到时间黑洞，自动填补 \(gap) slots 的休止符")
                #endif
            }
        }
        
        if iterations >= maxIterations {
            #if DEBUG
            dprint("Grammar: ⚠️ 达到最大迭代次数限制(10000)，停止展开")
            #endif
        }
        
        //dprint("Grammar: ✅ 展开完成，迭代次数: \(iterations), 生成音符数: \(terminalBuffer.count)")
        
        // A→C 收尾: 趋近音后紧跟休止符 → 降级为和弦音
        for i in 0..<(terminalBuffer.count - 1) {
            if terminalBuffer[i].type == .approach && terminalBuffer[i + 1].type == .rest {
                terminalBuffer[i] = GrammarTerminal(type: .chord,
                    durationSlots: terminalBuffer[i].durationSlots,
                    isDotted: terminalBuffer[i].isDotted,
                    tuplet: terminalBuffer[i].tuplet)
            }
        }

        return terminalBuffer
    }
    
    // MARK: - 展开符号
    
    private func expandSymbol(_ symbol: GrammarSymbol, depth: Int = 0) {
        // 深度限制，防止无限递归
        guard depth < 500 else {
            #if DEBUG
            dprint("Grammar: 达到最大深度限制，停止展开")
            #endif
            return
        }
        
        // 如果已经生成足够的时值，停止（而不是用音符数量限制）
        guard currentSlot < totalSlots else {
            return
        }
        
        // 安全限制：最多生成 1000 个音符，防止无限递归
        guard terminalBuffer.count < 1000 else {
            #if DEBUG
            dprint("Grammar: 达到最大音符数限制(1000)，停止展开")
            #endif
            return
        }
        
        switch symbol {
        case .terminal(let terminal):
            // 🌟 趋近音拍位过滤 + A→CHORD解决校验 (Java Generator offbeat gate)
            var resolvedTerminal = terminal
            
            if terminal.type == .approach {
                // A→CHORD: 若前一个终端已是A且未解决，强制当前终端为和弦音
                if pendingApproach {
                    resolvedTerminal = GrammarTerminal(type: .chord, durationSlots: terminal.durationSlots,
                                                        isDotted: terminal.isDotted, tuplet: terminal.tuplet)
                    pendingApproach = false
                }
                
                else if isOnBeat() || isStrongBeat() {
                    resolvedTerminal = GrammarTerminal(type: .chord, durationSlots: terminal.durationSlots,
                                                        isDotted: terminal.isDotted, tuplet: terminal.tuplet)
                    #if DEBUG
                    dprint("  [GRAMMAR-A2C] downbeat filter: approach→chord slot=\(currentSlot) onBeat=\(isOnBeat()) strong=\(isStrongBeat())")
                    #endif
                } else {
                    pendingApproach = true  // 标记期待下一个终端为和弦音
                }
            } else {
                // 非A终端：清除pending门禁
                pendingApproach = false
            }
            
            // 追加 (复用原有截断逻辑)
            if currentSlot + resolvedTerminal.actualDuration > totalSlots {
                let gap = totalSlots - currentSlot
                if gap > 0 {
                    let rest = GrammarTerminal(type: .rest, durationSlots: gap, isDotted: false, tuplet: 0)
                    terminalBuffer.append(rest)
                }
                currentSlot = totalSlots
                return
            }
            terminalBuffer.append(resolvedTerminal)
            #if DEBUG
            dprint("【Grammar输出】 终端类型=\(resolvedTerminal.type.rawValue)(\(resolvedTerminal.type)) 时值=\(resolvedTerminal.actualDuration)slots 当前槽位=\(currentSlot)")
            #endif
            currentSlot += resolvedTerminal.actualDuration
            
        case .nonTerminal(let name, let params):
            // 非终结符，先求值参数（替换变量、计算表达式），再展开
            let intParams = evaluateParams(params)
            expandNonTerminal(name: name, params: intParams, depth: depth + 1)
            
        case .list(let symbols):
            // 列表，依次展开
            for sym in symbols {
                expandSymbol(sym, depth: depth + 1)
            }
        }
    }
    
    // MARK: - 展开非终结符
    
    private func expandNonTerminal(name: String, params: [Int], depth: Int = 0) {
        // F1: fill 包装器 — (fill beats body) 递归填充指定拍数
        if name == "fill", params.count >= 2 {
            let beats = params[0]
            let slots = beats * 120  // 1拍=120slots (BEAT常量)
            // params[1:] 是 fill 体表达式的原始 tokens（可能包含括号列表）
            // 从原始规则右部取填充体 — 通过栈传递
            var filled = 0
            while filled < slots && currentSlot < totalSlots {
                // 每次填充前重置share缓存（Java unshareall 语义）
                shareCache.removeAll()
                // 递归调用 run 填充指定拍数
                let savedSlot = currentSlot
                let _ = run(startSlot: currentSlot, numSlots: min(slots - filled, totalSlots - currentSlot))
                filled += currentSlot - savedSlot
                if currentSlot >= totalSlots { break }
            }
            return
        }
        
        // M2: share缓存命中 — 参数化键复用BRICK等嵌套展开结果
        if name == "unshareall" {
            shareCache.removeAll()
            return
        }
        if name == "share", params.count >= 1 {
            let innerName = String(params[0])
            let sk = shareKey(innerName, Array(params.dropFirst()))
            if var cached = shareCache[sk] {
                for sym in cached { expandSymbol(sym, depth: depth + 1) }
                return
            }
        }
        let sk = shareKey(name, params)
        if var cached = shareCache[sk] {
            for sym in cached { expandSymbol(sym, depth: depth + 1) }
            return
        }
        #if DEBUG
        dprint("Grammar: [深度\(depth)] 展开非终结符 \(name), 参数: \(params)")
        #endif
        
        // 找到所有匹配的规则
        let matchingRules = findRules(name: name, params: params)
        #if DEBUG
        dprint("Grammar: [深度\(depth)] 匹配规则数: \(matchingRules.count)")
        #endif
        
        guard !matchingRules.isEmpty else {
            dprint("Grammar: ❌ 找不到匹配的规则 \(name)")
            return
        }
        
        #if DEBUG
        dprint("Grammar: [深度\(depth)] 匹配的规则:")
        #endif
        for (i, rule) in matchingRules.enumerated() {
            #if DEBUG
            dprint("Grammar:   \(i): \(rule.lhs) params=\(rule.lhsParams) base=\(rule.isBase) weight=\(rule.weight)")
            #endif
        }
        
        // 按权重随机选择一个规则
        let selectedRule = selectRuleByWeight(matchingRules)
        
        // M2: 缓存选中规则的RHS，供后续share命中复用
        shareCache[sk] = selectedRule.rhs
        
        // 保存当前变量环境
        let savedEnvironment = variableEnvironment
        
        // 【修复bug】用选中的selectedRule绑定参数，不是第一个匹配的规则！
        for (i, paramName) in selectedRule.lhsParams.enumerated() {
            if i < params.count {
                variableEnvironment[paramName] = params[i]
            }
        }
        
        // 展开右部
        for symbol in selectedRule.rhs {
            expandSymbol(symbol, depth: depth)
        }
        
        // 恢复变量环境
        variableEnvironment = savedEnvironment
    }
    
    // MARK: - 表达式求值（展开时调用）
    
    /// 求值参数列表，把字符串转成 Int
    private func evaluateParams(_ params: [String]) -> [Int] {
        // 参数是整数语义, evaluateExpr 已改 Double, 这里截断回 Int
        return params.map { Int(evaluateExpr($0)) }
    }
    
    /// 把表达式结果格式化为字符串：整数去 .0（"1"而非"1.0"），小数保留（"0.1"）
    /// 解决 evaluateExpr 改 Double 后 String(1.0)="1.0" != "1" 的语义 bug
    private func formatExprValue(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e12 {
            return String(Int(value))
        }
        return String(value)
    }
    
    /// 递归求值单个表达式
    private func evaluateExpr(_ expr: String) -> Double {
        let trimmed = expr.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. 如果是数字，直接返回
        if let intVal = Int(trimmed) {
            return Double(intVal)
        }
        
        // 2. 如果是变量，从当前环境中取值
        if let varVal = variableEnvironment[trimmed] {
            return Double(varVal)
        }
        
        // 3. 如果是表达式，比如 (- Y 1) 或 (builtin chord-family (major dominant))
        if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") {
            let inner = String(trimmed.dropFirst().dropLast())
            let tokens = tokenize(inner)
            
            // builtin 操作符
            if tokens.count >= 2 && tokens[0] == "builtin" {
                return evaluateBuiltin(name: tokens[1], arg: tokens.count > 2 ? tokens[2] : "")
            }
            
            // 二元算术运算
            if tokens.count == 3 {
                let op = tokens[0]
                let left = evaluateExpr(tokens[1])
                let right = evaluateExpr(tokens[2])
                
                switch op {
                case "+": return left + right
                case "-": return left - right
                case "*": return left * right
                case "/":
                    if right == 0 {
                        log(.general, msg: "警告：表达式除零，使用被除数 \(left) 替代")
                        return left
                    }
                    return left / right
                default: break
                }
            }
        }
        
        // 无法求值，区分错误类型打印日志
        if trimmed.starts(with: "(builtin") {
            log(.general, msg: "警告：无法识别builtin指令，表达式:\(expr)，返回0")
        } else if ["+", "-", "*", "/"].contains(String(trimmed.prefix(1))) {
            log(.general, msg: "警告：算术表达式格式非法，表达式:\(expr)，返回0")
        } else {
            log(.general, msg: "警告：未知表达式/变量不存在，表达式:\(expr)，返回0")
        }
        return 0.0
    }
    
    /// 求值 builtin 操作符
    private func evaluateBuiltin(name: String, arg: String) -> Double {
        switch name {
        case "chord-family":
            // 参数是一个和弦族列表，如 (major dominant)
            let familyList = parseFamilyList(arg)
            let currentFamily = getChordFamily(currentChordName)
            return familyList.contains(currentFamily) ? 1.0 : 0.0
            
        case "brick":
            // 对齐原版 Grammar.java:1155-1174:
            // currentBlock==null → return ZERO(0)
            // brickname.equals(blockName) → return ONE(1.0)
            // 不匹配 → return 0.1 (软匹配, 不是 0)
            guard let brickType = currentChordBlock?.brickType else { return 0.0 }
            let matched = JazzRoadmap.grammarBrickMatches(cykName: brickType, grammarName: arg)
            #if DEBUG
            dprint("[BUILTIN-BRICK] arg=\(arg) chord=\(currentChordBlock?.name ?? "?") brickType=\(brickType) → \(matched ? 1.0 : 0.1)")
            #endif
            return matched ? 1.0 : 0.1
            
        case "current-slot":
            // 阶段2新增：返回当前slot位置
            return Double(currentSlot)
            
        case "total-slots":
            // 阶段2新增：返回总slot数
            return Double(totalSlots)
            
        case "random":
            // 阶段2新增：随机数（参数为最大值，返回0~max-1）
            guard let max = Int(arg) else { return 0.0 }
            return Double(Int.random(in: 0..<max))
            
        case "mod":
            // 阶段2新增：取模运算（参数格式 "a b"，返回a%b）
            let parts = arg.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]), b != 0 else {
                return 0.0
            }
            return Double(a % b)
            
        default:
            #if DEBUG
            dprint("Grammar: ⚠️ 未知的 builtin: \(name)")
            #endif
            return 0.0
        }
    }
    
    /// 解析和弦族列表，如 (major dominant minor) -> ["major", "dominant", "minor"]
    private func parseFamilyList(_ listStr: String) -> [String] {
        var str = listStr.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 去掉外层括号
        if str.hasPrefix("(") && str.hasSuffix(")") {
            str = String(str.dropFirst().dropLast())
        }
        
        // 按空格分割
        return str.components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    
    // MARK: - 和弦族判断（用于 chord-family builtin）
    
    /// 和弦族判断（用于 chord-family builtin），优先使用完整ChordBlock，降级字符串兼容
    private func getChordFamily(_ chordName: String) -> String {
        if let block = currentChordBlock {
            return block.getChordFamily().rawValue
        }
        // 降级兼容：无完整块时用旧字符串匹配逻辑
        let cleanName = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanName.contains("dim") || cleanName.contains("°") || cleanName.contains("o7") {
            return "diminished"
        }
        if cleanName.contains("ø") || cleanName.contains("m7b5") {
            return "half-diminished"
        }
        if cleanName.contains("aug") || cleanName.contains("+") {
            return "augmented"
        }
        if cleanName.contains("sus") {
            return "sus"
        }
        if cleanName.contains("alt") {
            return "dominant"
        }
        if cleanName.contains("m") && !cleanName.contains("maj") && !cleanName.contains("M7") && !cleanName.contains("▲") {
            return cleanName.contains("7") ? "minor" : "minor"
        }
        if cleanName.contains("7") && !cleanName.contains("maj") && !cleanName.contains("M7") && !cleanName.contains("▲") {
            return "dominant"
        }
        return "major"
    }
    
    // MARK: - 查找匹配的规则
    
    private func findRules(name: String, params: [Int]) -> [GrammarRule] {
        var baseRules: [GrammarRule] = []
        var normalRules: [GrammarRule] = []
        
        // M2 诊断: BRICK规则统计
        if name == "BRICK" {
            let allBRICKRules = rules.filter { $0.lhs == "BRICK" }
            let conds = allBRICKRules.compactMap { $0.condition }.map { c in
                c.replacingOccurrences(of: "(builtin brick ", with: "").replacingOccurrences(of: ")", with: "")
            }
            #if DEBUG
            dprint("[BRICK-RULES] total=\(allBRICKRules.count) duration=\(params) conditions=\(Set(conds).sorted())")
            #endif
        }
        
        for rule in rules {
            if rule.lhs != name { continue }
            
            // 阶段2优化：参数数量允许规则参数更少（兼容缺省参数）
            if rule.lhsParams.count > params.count { continue }
            
            // 检查参数是否匹配
            var matches = true
            for (i, paramName) in rule.lhsParams.enumerated() {
                if let intValue = Int(paramName) {
                    if i < params.count && intValue != params[i] {
                        matches = false
                        break
                    }
                }
            }
            
            if matches {
                // M2: 延迟求值 builtin 条件 — 有 currentChordBlock 时重新算权重
                var effectiveWeight = rule.weight
                if let cond = rule.condition, currentChordBlock != nil {
                    effectiveWeight = evaluateExpr(cond) * rule.weight  // evaluateExpr 已返回 Double
                }
                // 权重为 0 → 跳过
                guard effectiveWeight > 0 else { continue }
                
                // Step2-Fix: P规则时长上限过滤 — BRICK时长>Y时跳过, 防止旋律截断
                if name == "P" && !params.isEmpty {
                    if case .nonTerminal("BRICK", let brickParams) = rule.rhs.first,
                       let brickDur = Int(brickParams.first ?? ""), brickDur > params[0] {
                        continue
                    }
                }
                
                // 临时替换 weight 用于 selectRuleByWeight
                let effectiveRule = GrammarRule(
                    lhs: rule.lhs, lhsParams: rule.lhsParams, rhs: rule.rhs,
                    weight: effectiveWeight, isBase: rule.isBase, condition: rule.condition)
                
                if rule.isBase {
                    baseRules.append(effectiveRule)
                } else {
                    normalRules.append(effectiveRule)
                }
            }
        }
        
        let result = baseRules.isEmpty ? normalRules : baseRules
        return result
    }
    
    // MARK: - 按权重选择规则
    
    private func selectRuleByWeight(_ rules: [GrammarRule]) -> GrammarRule {
        guard rules.count > 1 else { return rules[0] }
        
        let totalWeight = rules.reduce(0.0) { $0 + $1.weight }
        let random = Double.random(in: 0..<totalWeight)
        
        var cumulative = 0.0
        for rule in rules {
            cumulative += rule.weight
            if random < cumulative {
                return rule
            }
        }
        
        return rules.last!
    }
    
    // MARK: - 栈式展开（新架构）
    
    /// 从栈顶收集终结符，直到遇到非终结符或栈空
    /// - Returns: 剩余需要填充的 slots 数
    private func accumulateTerminals() -> Int {
        var remainingSlots = totalSlots - currentSlot
        
        while remainingSlots > 0 && !stack.isEmpty {
            guard let top = stack.last else { break }
            
            switch top {
            case .terminal(let terminal):
                // 是终结符，弹出并加入缓冲区
                stack.removeLast()
                
                // 检查是否超过总 slots
                if currentSlot + terminal.actualDuration > totalSlots {
                    // 🌟 终极修复 2：如果下一个音符放不下被截断了，剩下的畸形空间不能直接扔掉不管！
                    // 必须用休止符严丝合缝地填满它，保持排版网格绝对对齐。
                    let gap = totalSlots - currentSlot
                    if gap > 0 {
                        let rest = GrammarTerminal(type: .rest, durationSlots: gap, isDotted: false, tuplet: 0)
                        terminalBuffer.append(rest)
                    }
                    currentSlot = totalSlots
                    return 0
                }
                
                terminalBuffer.append(terminal)
                currentSlot += terminal.actualDuration
                remainingSlots -= terminal.actualDuration
                
            default:
                // 不是终结符，停止收集
                return remainingSlots
            }
        }
        
        return remainingSlots
    }
    
    /// 求值右部中的所有表达式，把变量和表达式替换成具体值
    private func evaluateRHS(_ symbols: [GrammarSymbol]) -> [GrammarSymbol] {
        var result: [GrammarSymbol] = []
        
        for symbol in symbols {
            switch symbol {
            case .terminal(let terminal):
                // 终结符不需要求值
                result.append(.terminal(terminal))
                
            case .nonTerminal(let name, let params):
                // 非终结符，求值每个参数（用 formatExprValue 格式化，整数去 .0）
                let evaluatedParams = params.map { formatExprValue(evaluateExpr($0)) }
                result.append(.nonTerminal(name, evaluatedParams))
                
            case .list(let innerSymbols):
                // 列表，递归求值
                let evaluatedInner = evaluateRHS(innerSymbols)
                result.append(.list(evaluatedInner))
            }
        }
        
        return result
    }
    
    /// 应用规则：弹出栈顶非终结符，展开后把右部压回栈
    /// - Returns: 剩余需要填充的 slots 数
    private func applyRules() -> Int {
        guard !stack.isEmpty else {
            return totalSlots - currentSlot
        }
        
        let top = stack.removeLast()
        
        switch top {
        case .nonTerminal(let name, let params):
            // 先检查是不是 wrapper 类型
            switch name {
            case "unshareall":
                // 清空所有缓存
                shareCache.removeAll()
                #if DEBUG
                dprint("Grammar: 📦 unshareall - 清空所有 share 缓存")
                #endif
                return totalSlots - currentSlot
                
            case "fill":
                // fill wrapper：(fill 4 (P Y))
                guard params.count >= 2 else {
                    dprint("Grammar: ❌ fill 缺少参数")
                    return totalSlots - currentSlot
                }
                
                // 第一个参数：拍数
                let beatsStr = params[0]
                let beats = evaluateExpr(beatsStr)  // evaluateExpr 已返回 Double
                
                // 第二个参数：要填充的语法
                let grammarStr = params[1]
                
                // 解析要填充的语法符号
                var grammarSym: GrammarSymbol?
                if grammarStr.hasPrefix("(") {
                    grammarSym = parseListSymbol(grammarStr)
                } else {
                    grammarSym = .nonTerminal(grammarStr, [])
                }
                
                guard let sym = grammarSym else {
                    dprint("Grammar: ❌ 无法解析 fill 的语法: \(grammarStr)")
                    return totalSlots - currentSlot
                }
                
                // 保存当前的全局栈
                let savedStack = stack
                
                // 设置 fill 的内部初始栈
                stack = [sym]
                
                // 执行 outerFill 填充
                outerFill(beats: beats)
                
                // 记录填充后的内部栈状态
                let innerResultStack = stack
                
                // 恢复全局栈
                stack = savedStack
                
                // 把 fill 的展开结果压入全局栈
                // 展开顺序：先执行 unshareall，然后是内部栈的内容
                // 所以压入顺序：先压入内部栈（栈底到栈顶），最后压入 unshareall（栈顶）
                stack.append(contentsOf: innerResultStack)
                stack.append(.nonTerminal("unshareall", []))
                
                #if DEBUG
                dprint("Grammar: 📦 fill 展开完成，内部栈剩余 \(innerResultStack.count) 个符号")
                #endif
                
                return totalSlots - currentSlot
                
            case "share", "unshare":
                // share/unshare wrapper
                let isShare = name == "share"
                guard !params.isEmpty else {
                    dprint("Grammar: ❌ share/unshare 缺少参数")
                    return totalSlots - currentSlot
                }
                
                // 第一个参数是非终结符（可以是简单名字，也可以是带参数的列表）
                let firstParam = params[0]
                
                // 解析非终结符的名字（用于缓存 key）
                var nonTermName = ""
                if firstParam.hasPrefix("(") {
                    // 带参数的非终结符，比如 "(P 480)"，提取名字
                    if let innerSym = parseListSymbol(firstParam) {
                        if case .nonTerminal(let innerName, _) = innerSym {
                            nonTermName = innerName
                        }
                    }
                } else {
                    // 简单名字，比如 "P"
                    nonTermName = firstParam
                }
                
                guard !nonTermName.isEmpty else {
                    dprint("Grammar: ❌ 无法解析 share/unshare 的非终结符")
                    return totalSlots - currentSlot
                }
                
                // 检查缓存中有没有
                if let cachedRHS = shareCache[nonTermName] {
                    if !isShare { // unshare
                        // 删除缓存
                        shareCache.removeValue(forKey: nonTermName)
                        #if DEBUG
                        dprint("Grammar: 📦 unshare - 删除缓存: \(nonTermName)")
                        #endif
                    } else {
                        #if DEBUG
                        dprint("Grammar: 📦 share - 命中缓存: \(nonTermName)")
                        #endif
                    }
                    
                    // 把缓存的右部逆序压入栈
                    for symbol in cachedRHS.reversed() {
                        stack.append(symbol)
                    }
                    
                    return totalSlots - currentSlot
                }
                
                // 缓存没有命中，需要展开
                // 先解析要展开的非终结符
                var symbolToExpand: GrammarSymbol?
                if firstParam.hasPrefix("(") {
                    symbolToExpand = parseListSymbol(firstParam)
                } else {
                    symbolToExpand = .nonTerminal(firstParam, [])
                }
                
                guard let sym = symbolToExpand else {
                    dprint("Grammar: ❌ 无法解析 share 的非终结符: \(firstParam)")
                    return totalSlots - currentSlot
                }
                
                // 展开这个非终结符（选规则 + 求值右部）
                if case .nonTerminal(let innerName, let innerParams) = sym {
                    let intParams = evaluateParams(innerParams)
                    let matchingRules = findRules(name: innerName, params: intParams)
                    
                    guard !matchingRules.isEmpty else {
                        dprint("Grammar: ❌ share 找不到匹配的规则: \(innerName)")
                        return totalSlots - currentSlot
                    }
                    
                    let selectedRule = selectRuleByWeight(matchingRules)
                    
                    // 保存当前变量环境
                    let savedEnvironment = variableEnvironment
                    
                    // 绑定参数到变量
                    for (i, paramName) in selectedRule.lhsParams.enumerated() {
                        if i < intParams.count {
                            variableEnvironment[paramName] = intParams[i]
                        }
                    }
                    
                    // 求值右部
                    let evaluatedRHS = evaluateRHS(selectedRule.rhs)
                    
                    // 恢复变量环境
                    variableEnvironment = savedEnvironment
                    
                    // 如果是 share，缓存起来
                    if isShare {
                        shareCache[nonTermName] = evaluatedRHS
                        #if DEBUG
                        dprint("Grammar: 📦 share - 缓存展开结果: \(nonTermName), 符号数: \(evaluatedRHS.count)")
                        #endif
                    }
                    
                    // 把右部逆序压入栈
                    for symbol in evaluatedRHS.reversed() {
                        stack.append(symbol)
                    }
                    
                    return totalSlots - currentSlot
                }
                
                #if DEBUG
                dprint("Grammar: ❌ share 的参数不是非终结符")
                #endif
                return totalSlots - currentSlot
                
            default:
                // 普通非终结符，正常展开
                let intParams = evaluateParams(params)
                
                // M2 诊断: BRICK查询时的实际参数
                if name == "BRICK" && !intParams.isEmpty {
                    #if DEBUG
                    dprint("[APPLYRULES-BRICK] name=\(name) rawParams=\(params) intParams=\(intParams)")
                    #endif
                }
                #if DEBUG
                dprint("[APPLYRULES-EXPAND] name=\(name) params=\(intParams)")
                #endif
                
                // 找到匹配的规则
                var matchingRules = findRules(name: name, params: intParams)
                
                // M3 诊断: BRICK匹配结果
                if name == "BRICK" {
                    let conds = matchingRules.compactMap { $0.condition }
                    #if DEBUG
                    dprint("[BRICK-MATCHING] found=\(matchingRules.count) conds=\(conds.count)")
                    #endif
                }
                
                // ========== 🌟 栈引擎内置自适应 BRICK 降级机制 (终极无损版) ==========
                if name == "BRICK" && matchingRules.isEmpty {
                    let duration = intParams.first ?? 480
                    
                    // 【修正1：安全传参】使用整数除法转为拍数，避免 "4.0" 导致 EvaluateExpr 解析失败
                    let beatsInt = max(1, duration / 120) 
                    
                    // 动态搜寻当前 .grammar 文件中真正存在的帕克风格非终结符（以 Q 开头）
                    var availableFallbackNames = rules.filter { $0.lhs.hasPrefix("Q") }.map { $0.lhs }
                    
                    // 【修正2：次级安全兜底】如果连 Q 开头的规则都没有，排除 BRICK 抓取任意非终结符
                    if availableFallbackNames.isEmpty {
                        availableFallbackNames = rules.filter { $0.lhs != "BRICK" && $0.lhs != "P" }.map { $0.lhs }
                    }
                    
                    if let fallbackName = availableFallbackNames.randomElement() {
                        #if DEBUG
                        dprint("Grammar: 🧱 栈引擎成功拦截 BRICK 数据库请求！chord=\(currentChordName ?? "?") brickType=\(currentChordBlock?.brickType ?? "nil") duration=\(intParams.first ?? 0)")
                        #endif
                        #if DEBUG
                        dprint("Grammar: 🔄 智能降级：动态盲抽真实句型 [\(fallbackName)]，填充 \(beatsInt) 拍")
                        #endif
                        
                        // BRICK降级: 直接压Q非终结符, 由主循环applyRules()展开
                        // 不再wrap在fill中, 避免fill→run()→P→BRICK递归死循环
                        stack.append(GrammarSymbol.nonTerminal(fallbackName, []))
                        
                        // 直接返回，让下一轮迭代立刻去弹栈并展开Q规则
                        return totalSlots - currentSlot
                    } else {
                        #if DEBUG
                        dprint("Grammar: ⚠️ 降级失败：文法文件中没有任何可用的非终结符")
                        #endif
                    }
                }
                // ===================================================================
                
                guard !matchingRules.isEmpty else {
                    dprint("Grammar: ❌ 找不到匹配的规则 \(name)")
                    return totalSlots - currentSlot
                }
                
                // 按权重选一条规则
                let selectedRule = selectRuleByWeight(matchingRules)
                
                // 保存当前变量环境
                let savedEnvironment = variableEnvironment
                
                // 绑定参数到变量
                for (i, paramName) in selectedRule.lhsParams.enumerated() {
                    if i < intParams.count {
                        variableEnvironment[paramName] = intParams[i]
                    }
                }
                
                // 求值右部（所有变量和表达式都会被替换成具体值）
                let evaluatedRHS = evaluateRHS(selectedRule.rhs)
                
                // 恢复变量环境（右部已经求值完，后面不需要这些变量了）
                variableEnvironment = savedEnvironment
                
                // 把右部逆序压入栈（栈是后进先出，逆序压入才能保证展开顺序正确）
                for symbol in evaluatedRHS.reversed() {
                    stack.append(symbol)
                }
            }
            
        case .list(let symbols):
            // 列表，把元素逆序压入栈
            for symbol in symbols.reversed() {
                stack.append(symbol)
            }
            
        case .terminal:
            // 不应该到这里，终结符应该被 accumulateTerminals 处理了
            #if DEBUG
            dprint("Grammar: ⚠️ applyRules 遇到了终结符")
            #endif
            // 重新压回去
            stack.append(top)
        }
        
        return totalSlots - currentSlot
    }
    
    /// outerFill：在指定拍数内反复填充当前栈顶的语法
    /// - Parameter beats: 需要填充的拍数
    private func outerFill(beats: Double) {
        let slotsToFill = Int(beats * 120.0) // 一拍 = 120 slots
        let originalStack = stack
        
        var remaining = slotsToFill
        var iterations = 0
        let maxIterations = 10000
        
        #if DEBUG
        dprint("Grammar: 📦 fill 开始，填充 \(beats) 拍 (\(slotsToFill) slots)")
        #endif
        
        while remaining > 0 && iterations < maxIterations {
            iterations += 1
            
            // 如果栈空了，重置为原始栈，继续填充
            if stack.isEmpty {
                stack = originalStack
                #if DEBUG
                dprint("Grammar: 📦 fill 栈空了，重置继续填充，剩余: \(remaining) slots")
                #endif
            }
            
            // 阶段2优化：先检查全局slot是否超限
            if currentSlot >= totalSlots {
                break
            }
            
            // 记录填充前的位置
            let slotBefore = currentSlot
            
            // 收集终结符
            let currentRemaining = accumulateTerminals()
            remaining = currentRemaining
            
            if remaining <= 0 {
                break
            }
            
            // 应用一条规则
            _ = applyRules()
        }
        
        if iterations >= maxIterations {
            #if DEBUG
            dprint("Grammar: ⚠️ fill 达到最大迭代次数")
            #endif
        }
        
        #if DEBUG
        dprint("Grammar: 📦 fill 结束，实际填充了 \(slotsToFill - remaining) slots")
        #endif
    }
}
// MARK: - GrammarSymbol 调试扩展
// 暂时注释，枚举成员名称不匹配，后续核对 GrammarTerminalType 原名后再重写
/*
extension GrammarSymbol: CustomStringConvertible {
    var description: String {
        switch self {
        case .terminal(let terminal):
            switch terminal.type {
            case .note:
                return "Terminal(note, duration:\(terminal.durationSlots))"
            case .rest:
                return "Terminal(rest, duration:\(terminal.durationSlots))"
            case .scaleDegree:
                return "Terminal(scaleDegree, duration:\(terminal.durationSlots))"
            case .slope:
                return "Terminal(slope, duration:\(terminal.durationSlots))"
            }
        case .nonTerminal(let name, let params):
            return "NonTerminal(\(name), params: \(params))"
        case .list(let symbols):
            return "List([\(symbols.map { $0.description }.joined(separator: ", "))])"
        }
    }
}
*/

// MARK: - GrammarRule 调试扩展
extension GrammarRule: CustomStringConvertible {
    var description: String {
        return "Rule(lhs:\(lhs)(\(lhsParams.joined(separator: ","))), weight:\(weight), base:\(isBase))"
    }
}
