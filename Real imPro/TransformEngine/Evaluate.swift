import Foundation

// MARK: - 完整的变换表达式求值引擎（对应 Java Evaluate.java 1540行）
extension TransformEngine {
    
    /// 变换表达式求值内核
    struct Evaluate {
        static let shared = Self()
        private init() {}
        
        // MARK: - 变量帧（支持多种类型的值）
        struct TransformFrame {
            /// 数字变量
            private var numberVariables: [String: Double] = [:]
            /// 字符串变量
            private var stringVariables: [String: String] = [:]
            /// NCP 变量
            private var ncpVariables: [String: NoteChordPair] = [:]
            
            /// 数字变量读写
            subscript(number key: String) -> Double? {
                get { numberVariables[key] }
                set { numberVariables[key] = newValue }
            }
            
            /// 字符串变量读写
            subscript(string key: String) -> String? {
                get { stringVariables[key] }
                set { stringVariables[key] = newValue }
            }
            
            /// NCP 变量读写
            subscript(ncp key: String) -> NoteChordPair? {
                get { ncpVariables[key] }
                set { ncpVariables[key] = newValue }
            }
            
            /// 设置数字变量
            mutating func setVar(name: String, value: Double) {
                numberVariables[name] = value
            }
            
            /// 设置字符串变量
            mutating func setVar(name: String, value: String) {
                stringVariables[name] = value
            }
            
            /// 设置 NCP 变量
            mutating func setVar(name: String, value: NoteChordPair) {
                ncpVariables[name] = value
            }
            
            /// 获取数字变量
            func getNumberVar(name: String) -> Double? {
                numberVariables[name]
            }
            
            /// 获取字符串变量
            func getStringVar(name: String) -> String? {
                stringVariables[name]
            }
            
            /// 获取 NCP 变量
            func getNCPVar(name: String) -> NoteChordPair? {
                ncpVariables[name]
            }
            
            /// 检查变量是否存在
            func hasVar(name: String) -> Bool {
                numberVariables[name] != nil ||
                stringVariables[name] != nil ||
                ncpVariables[name] != nil
            }
            
            /// 清空所有变量
            mutating func clear() {
                numberVariables.removeAll()
                stringVariables.removeAll()
                ncpVariables.removeAll()
            }
        }
        
        // MARK: - 操作符枚举（对应 Java Operators enum）
        enum Operator: String {
            // 基础逻辑
            case and = "and"
            case or = "or"
            case not = "not"
            case ifOp = "if"
            case equals = "="
            case abs = "abs"
            case greater = ">"
            case greaterEq = ">="
            case less = "<"
            case lessEq = "<="
            case member = "member"
            
            // 基础算术运算
            case plus = "+"
            case minus = "-"
            case times = "*"
            case divide = "/"
            
            // 和弦相关
            case chordEquals = "chord="
            case chordFamily = "chord-family"
            
            // 时值特殊判断
            case triplet = "triplet?"
            case quintuplet = "quintuplet?"
            case rest = "rest?"
            
            // 时值运算
            case duration = "duration"
            case durationEq = "duration="
            case durationAdd = "duration+"
            case durationSub = "duration-"
            case durationMul = "duration*"
            case durationGr = "duration>"
            case durationGrEq = "duration>="
            case durationLt = "duration<"
            case durationLtEq = "duration<="
            
            // 音高相关
            case noteCategory = "note-category"
            case relativePitch = "relative-pitch"
            case absolutePitch = "absolute-pitch"
            case pitchAdd = "pitch+"
            case pitchSub = "pitch-"
            case pitchGr = "pitch>"
            case pitchGrEq = "pitch>="
            case pitchLt = "pitch<"
            case pitchLtEq = "pitch<="
            
            // 音符变换
            case scaleDuration = "scale-duration"
            case addDuration = "add-duration"
            case subtractDuration = "subtract-duration"
            case multiplyDuration = "multiply-duration"
            case setDuration = "set-duration"
            case setRelativePitch = "set-relative-pitch"
            case transposeDiatonic = "transpose-diatonic"
            case transposeChromatic = "transpose-chromatic"
            case makeRest = "make-rest"
            case getNote = "get-note"
            
            // 调试用
            case printNote = "print-note"
        }
        
        // MARK: - Tokenizer
        private func tokenize(_ input: String) -> [String] {
            var tokens: [String] = []
            var buffer = ""
            for c in input {
                if c == "(" || c == ")" {
                    if !buffer.isEmpty {
                        tokens.append(buffer)
                        buffer = ""
                    }
                    tokens.append(String(c))
                } else if c.isWhitespace {
                    if !buffer.isEmpty {
                        tokens.append(buffer)
                        buffer = ""
                    }
                } else {
                    buffer.append(c)
                }
            }
            if !buffer.isEmpty { tokens.append(buffer) }
            return tokens
        }
        
        // MARK: - S-Expression Parser
        private func parseSExpr(tokens: [String], ptr: inout Int) -> [Any]? {
            guard ptr < tokens.count, tokens[ptr] == "(" else { return nil }
            ptr += 1
            var children: [Any] = []
            while ptr < tokens.count, tokens[ptr] != ")" {
                let currTok = tokens[ptr]
                if currTok == "(" {
                    guard let sub = parseSExpr(tokens: tokens, ptr: &ptr) else { return nil }
                    children.append(sub)
                } else {
                    children.append(currTok)
                    ptr += 1
                }
            }
            ptr += 1
            return children
        }
        
        // MARK: - 求值入口（返回 Any?）
        /// 求值表达式，返回任意类型的值（Double, String, NoteChordPair, Bool 等）
        func evaluateAny(_ expression: String, frame: inout TransformFrame, ncp: NoteChordPair? = nil) -> Any? {
            let tokens = tokenize(expression)
            var ptr = 0
            guard let ast = parseSExpr(tokens: tokens, ptr: &ptr) else {
                // 不是表达式，尝试解析为字面量
                return parseLiteral(expression, frame: frame)
            }
            return evalNode(ast, frame: &frame, ncp: ncp)
        }
        
        /// 求值表达式，返回 Double（兼容旧接口）
        func evaluate(_ expression: String, frame: inout TransformFrame, ncp: NoteChordPair? = nil) -> Double {
            let result = evaluateAny(expression, frame: &frame, ncp: ncp)
            return coerceToDouble(result)
        }
        
        /// 解析字面量
        private func parseLiteral(_ str: String, frame: TransformFrame) -> Any? {
            // 数字
            if let num = Double(str) {
                return num
            }
            // 变量
            if frame.hasVar(name: str) {
                if let num = frame.getNumberVar(name: str) { return num }
                if let str = frame.getStringVar(name: str) { return str }
                if let ncp = frame.getNCPVar(name: str) { return ncp }
            }
            // 默认返回字符串
            return str
        }
        
        /// 强制转换为 Double
        private func coerceToDouble(_ value: Any?) -> Double {
            guard let val = value else { return 0.0 }
            if let num = val as? Double { return num }
            if let num = val as? Int { return Double(num) }
            if let bool = val as? Bool { return bool ? 1.0 : 0.0 }
            if let str = val as? String {
                if let num = Double(str) { return num }
                return str.isEmpty ? 0.0 : 1.0
            }
            return 0.0
        }
        
        /// 强制转换为 Bool
        private func coerceToBool(_ value: Any?) -> Bool {
            guard let val = value else { return false }
            if let bool = val as? Bool { return bool }
            if let num = val as? Double { return num != 0 }
            if let num = val as? Int { return num != 0 }
            if let str = val as? String { return !str.isEmpty }
            return true
        }
        
        /// 强制转换为 String
        private func coerceToString(_ value: Any?) -> String {
            guard let val = value else { return "" }
            if let str = val as? String { return str }
            if let num = val as? Double {
                if num.truncatingRemainder(dividingBy: 1) == 0 {
                    return String(Int(num))
                }
                return String(num)
            }
            if let num = val as? Int { return String(num) }
            if let bool = val as? Bool { return bool ? "true" : "false" }
            return "\(val)"
        }
        
        /// 检查是否为 NCP
        private func isNCP(_ value: Any?) -> NoteChordPair? {
            value as? NoteChordPair
        }
        
        // MARK: - 递归求值 AST 节点
        private func evalNode(_ node: Any, frame: inout TransformFrame, ncp: NoteChordPair?) -> Any? {
            // 叶子节点：字符串
            if let str = node as? String {
                return parseLiteral(str, frame: frame)
            }
            
            // 列表节点：函数调用
            guard let list = node as? [Any], !list.isEmpty else { return nil }
            
            let opRaw = list[0] as? String ?? ""
            let argsRaw = Array(list.dropFirst())
            
            // 先求值所有参数
            var evaledArgs: [Any?] = []
            for argNode in argsRaw {
                evaledArgs.append(evalNode(argNode, frame: &frame, ncp: ncp))
            }
            
            // 查找操作符
            guard let op = Operator(rawValue: opRaw) else {
                // 未知操作符，返回 0
                return 0.0
            }
            
            // 分发到具体函数
            return applyOperator(op, args: evaledArgs, frame: &frame, ncp: ncp)
        }
        
        // MARK: - 操作符分发
        private func applyOperator(_ op: Operator, args: [Any?], frame: inout TransformFrame, ncp: NoteChordPair?) -> Any? {
            switch op {
            // MARK: 基础逻辑
            case .and: return op_and(args)
            case .or: return op_or(args)
            case .not: return op_not(args)
            case .ifOp: return op_if(args)
            case .equals: return op_equals(args)
            case .abs: return op_abs(args)
            case .greater: return op_greater(args)
            case .greaterEq: return op_greaterEq(args)
            case .less: return op_less(args)
            case .lessEq: return op_lessEq(args)
            case .member: return op_member(args)
                
            // MARK: 基础算术运算
            case .plus: return op_plus(args)
            case .minus: return op_minus(args)
            case .times: return op_times(args)
            case .divide: return op_divide(args)
            
            // MARK: 和弦相关
            case .chordEquals: return op_chordEquals(args)
            case .chordFamily: return op_chordFamily(args)
                
            // MARK: 时值特殊判断
            case .triplet: return op_triplet(args)
            case .quintuplet: return op_quintuplet(args)
            case .rest: return op_rest(args)
                
            // MARK: 时值运算
            case .duration: return op_duration(args)
            case .durationEq: return op_durationEq(args)
            case .durationAdd: return op_durationAdd(args)
            case .durationSub: return op_durationSub(args)
            case .durationMul: return op_durationMul(args)
            case .durationGr: return op_durationGr(args)
            case .durationGrEq: return op_durationGrEq(args)
            case .durationLt: return op_durationLt(args)
            case .durationLtEq: return op_durationLtEq(args)
                
            // MARK: 音高相关
            case .noteCategory: return op_noteCategory(args)
            case .relativePitch: return op_relativePitch(args)
            case .absolutePitch: return op_absolutePitch(args)
            case .pitchAdd: return op_pitchAdd(args)
            case .pitchSub: return op_pitchSub(args)
            case .pitchGr: return op_pitchGr(args)
            case .pitchGrEq: return op_pitchGrEq(args)
            case .pitchLt: return op_pitchLt(args)
            case .pitchLtEq: return op_pitchLtEq(args)
                
            // MARK: 音符变换
            case .scaleDuration: return op_scaleDuration(args)
            case .addDuration: return op_addDuration(args)
            case .subtractDuration: return op_subtractDuration(args)
            case .multiplyDuration: return op_multiplyDuration(args)
            case .setDuration: return op_setDuration(args)
            case .setRelativePitch: return op_setRelativePitch(args)
            case .transposeDiatonic: return op_transposeDiatonic(args)
            case .transposeChromatic: return op_transposeChromatic(args)
            case .makeRest: return op_makeRest(args)
            case .getNote: return op_getNote(args)
                
            // MARK: 调试
            case .printNote: return op_printNote(args)
            }
        }
        
        // MARK: - 辅助：获取时值（slots）
        private func getDurationSlots(_ value: Any?) -> Int {
            if let ncp = isNCP(value) {
                return ncp.getDuration()
            }
            let str = coerceToString(value)
            return DurationTools.slots(from: str)
        }
        
        // MARK: - 辅助：读取数字（支持分数）
        private func readNumber(_ str: String) -> Double {
            if str.contains("/") {
                let parts = str.split(separator: "/")
                if parts.count == 2,
                   let numerator = Double(parts[0]),
                   let denominator = Double(parts[1]),
                   denominator != 0 {
                    return numerator / denominator
                }
            }
            return Double(str) ?? 0
        }
        
        // MARK: - 辅助：检查是否为相对音高格式
        private func isRelativePitchFormat(_ str: String) -> Bool {
            let pattern = "^[b#]*-?\\d+$"
            return str.range(of: pattern, options: .regularExpression) != nil
        }
        
        // MARK: ===== 基础逻辑运算 =====
        
        /// (and arg1 arg2 ...) - 所有参数都为真则返回真
        private func op_and(_ args: [Any?]) -> Bool {
            for arg in args {
                if !coerceToBool(arg) {
                    return false
                }
            }
            return true
        }
        
        /// (or arg1 arg2 ...) - 至少一个参数为真则返回真
        private func op_or(_ args: [Any?]) -> Bool {
            for arg in args {
                if coerceToBool(arg) {
                    return true
                }
            }
            return false
        }
        
        /// (not arg) - 逻辑非
        private func op_not(_ args: [Any?]) -> Bool {
            guard let first = args.first else { return false }
            return !coerceToBool(first)
        }
        
        /// (if condition true-branch false-branch) - 条件语句
        private func op_if(_ args: [Any?]) -> Any? {
            guard args.count >= 3 else { return nil }
            let condition = coerceToBool(args[0])
            return condition ? args[1] : args[2]
        }
        
        /// (= arg1 arg2) - 等于比较
        private func op_equals(_ args: [Any?]) -> Bool {
            guard args.count >= 2 else { return false }
            let first = args[0]
            let second = args[1]
            
            // 都是数字
            if let num1 = first as? Double, let num2 = second as? Double {
                return num1 == num2
            }
            if let num1 = first as? Int, let num2 = second as? Int {
                return num1 == num2
            }
            
            // 都是字符串
            let str1 = coerceToString(first)
            let str2 = coerceToString(second)
            return str1 == str2
        }
        
        /// (abs num) - 绝对值
        private func op_abs(_ args: [Any?]) -> Double {
            guard let first = args.first else { return 0 }
            return abs(coerceToDouble(first))
        }
        
        /// (> arg1 arg2) - 大于
        private func op_greater(_ args: [Any?]) -> Bool {
            guard args.count >= 2 else { return false }
            let num1 = coerceToDouble(args[0])
            let num2 = coerceToDouble(args[1])
            return num1 > num2
        }
        
        /// (>= arg1 arg2) - 大于等于
        private func op_greaterEq(_ args: [Any?]) -> Bool {
            guard args.count >= 2 else { return false }
            let num1 = coerceToDouble(args[0])
            let num2 = coerceToDouble(args[1])
            return num1 >= num2
        }
        
        /// (< arg1 arg2) - 小于
        private func op_less(_ args: [Any?]) -> Bool {
            guard args.count >= 2 else { return false }
            let num1 = coerceToDouble(args[0])
            let num2 = coerceToDouble(args[1])
            return num1 < num2
        }
        
        /// (<= arg1 arg2) - 小于等于
        private func op_lessEq(_ args: [Any?]) -> Bool {
            guard args.count >= 2 else { return false }
            let num1 = coerceToDouble(args[0])
            let num2 = coerceToDouble(args[1])
            return num1 <= num2
        }
        
        /// (member item list...) - 检查元素是否在列表中
        private func op_member(_ args: [Any?]) -> Bool {
            guard args.count >= 2 else { return false }
            let item = args[0]
            let list = Array(args.dropFirst())
            
            let itemStr = coerceToString(item)
            let itemNum = coerceToDouble(item)
            
            for listItem in list {
                // 字符串比较
                if itemStr == coerceToString(listItem) {
                    return true
                }
                // 数字比较
                if itemNum == coerceToDouble(listItem) {
                    return true
                }
            }
            return false
        }
        
        // MARK: ===== 基础算术运算 =====
        
        /// (+ arg1 arg2 ...) - 加法（支持多个参数）
        private func op_plus(_ args: [Any?]) -> Double {
            var result: Double = 0
            for arg in args {
                result += coerceToDouble(arg)
            }
            return result
        }
        
        /// (- arg1 arg2 ...) - 减法（第一个参数减去后面所有参数）
        private func op_minus(_ args: [Any?]) -> Double {
            guard let first = args.first else { return 0 }
            var result = coerceToDouble(first)
            for arg in args.dropFirst() {
                result -= coerceToDouble(arg)
            }
            return result
        }
        
        /// (* arg1 arg2 ...) - 乘法（支持多个参数）
        private func op_times(_ args: [Any?]) -> Double {
            guard !args.isEmpty else { return 1 }
            var result: Double = 1
            for arg in args {
                result *= coerceToDouble(arg)
            }
            return result
        }
        
        /// (/ arg1 arg2 ...) - 除法（第一个参数除以后面所有参数）
        private func op_divide(_ args: [Any?]) -> Double {
            guard let first = args.first else { return 0 }
            var result = coerceToDouble(first)
            for arg in args.dropFirst() {
                let divisor = coerceToDouble(arg)
                if divisor != 0 {
                    result /= divisor
                }
            }
            return result
        }
        
        // MARK: ===== 和弦相关 =====
        
        /// (chord= ncp1 ncp2) - 和弦相等比较
        private func op_chordEquals(_ args: [Any?]) -> Bool {
            guard args.count >= 2 else { return false }
            guard let ncp1 = isNCP(args[0]),
                  let ncp2 = isNCP(args[1]) else {
                return false
            }
            return ncp1.chord.name == ncp2.chord.name
        }
        
        /// (chord-family ncp) - 获取和弦家族
        private func op_chordFamily(_ args: [Any?]) -> String {
            guard let first = args.first,
                  let ncp = isNCP(first) else {
                return "none"
            }
            let family = ncp.chord.getChordFamily()
            return family.rawValue
        }
        
        // MARK: ===== 时值特殊判断 =====
        
        /// (triplet? ncp-or-duration) - 是否三连音
        private func op_triplet(_ args: [Any?]) -> Bool {
            guard let first = args.first else { return false }
            
            if let ncp = isNCP(first) {
                let durStr = DurationTools.durationString(from: ncp.getDuration())
                return DurationTools.isTriplet(durStr)
            }
            
            let str = coerceToString(first)
            return DurationTools.isTriplet(str)
        }
        
        /// (quintuplet? ncp-or-duration) - 是否五连音
        private func op_quintuplet(_ args: [Any?]) -> Bool {
            guard let first = args.first else { return false }
            
            if let ncp = isNCP(first) {
                let durStr = DurationTools.durationString(from: ncp.getDuration())
                return DurationTools.isQuintuplet(durStr)
            }
            
            let str = coerceToString(first)
            return DurationTools.isQuintuplet(str)
        }
        
        /// (rest? ncp) - 是否休止符
        private func op_rest(_ args: [Any?]) -> Bool {
            guard let first = args.first else { return false }
            if let ncp = isNCP(first) {
                return ncp.note.isRest
            }
            return false
        }
        
        // MARK: ===== 时值运算 =====
        
        /// (duration ncp) - 获取时值字符串
        private func op_duration(_ args: [Any?]) -> String {
            guard let first = args.first,
                  let ncp = isNCP(first) else {
                return "0"
            }
            return DurationTools.durationString(from: ncp.getDuration())
        }
        
        /// (duration= arg1 arg2) - 时值相等
        private func op_durationEq(_ args: [Any?]) -> Bool {
            guard args.count >= 2 else { return false }
            let dur1 = getDurationSlots(args[0])
            let dur2 = getDurationSlots(args[1])
            return dur1 == dur2
        }
        
        /// (duration+ arg1 arg2) - 时值相加
        private func op_durationAdd(_ args: [Any?]) -> String {
            guard args.count >= 2 else { return "0" }
            let dur1 = getDurationSlots(args[0])
            let dur2 = getDurationSlots(args[1])
            return DurationTools.durationString(from: dur1 + dur2)
        }
        
        /// (duration- arg1 arg2) - 时值相减
        private func op_durationSub(_ args: [Any?]) -> String? {
            guard args.count >= 2 else { return nil }
            let dur1 = getDurationSlots(args[0])
            let dur2 = getDurationSlots(args[1])
            let result = dur1 - dur2
            guard result >= 0 else { return nil }
            return DurationTools.durationString(from: result)
        }
        
        /// (duration* arg1 arg2) - 时值相乘
        private func op_durationMul(_ args: [Any?]) -> String? {
            guard args.count >= 2 else { return nil }
            let dur1 = getDurationSlots(args[0])
            let multiplier = coerceToDouble(args[1])
            let result = Int(Double(dur1) * multiplier)
            guard result >= 0 else { return nil }
            return DurationTools.durationString(from: result)
        }
        
        /// (duration> arg1 arg2) - 时值大于
        private func op_durationGr(_ args: [Any?]) -> Bool {
            guard args.count >= 2 else { return false }
            let dur1 = getDurationSlots(args[0])
            let dur2 = getDurationSlots(args[1])
            return dur1 > dur2
        }
        
        /// (duration>= arg1 arg2) - 时值大于等于
        private func op_durationGrEq(_ args: [Any?]) -> Bool {
            guard args.count >= 2 else { return false }
            let dur1 = getDurationSlots(args[0])
            let dur2 = getDurationSlots(args[1])
            return dur1 >= dur2
        }
        
        /// (duration< arg1 arg2) - 时值小于
        private func op_durationLt(_ args: [Any?]) -> Bool {
            guard args.count >= 2 else { return false }
            let dur1 = getDurationSlots(args[0])
            let dur2 = getDurationSlots(args[1])
            return dur1 < dur2
        }
        
        /// (duration<= arg1 arg2) - 时值小于等于
        private func op_durationLtEq(_ args: [Any?]) -> Bool {
            guard args.count >= 2 else { return false }
            let dur1 = getDurationSlots(args[0])
            let dur2 = getDurationSlots(args[1])
            return dur1 <= dur2
        }
        
        // MARK: ===== 音高相关 =====
        
        /// (note-category ncp) - 音符分类
        /// 返回 "C" (和弦音), "L" (色彩音), "X" (外音), "R" (休止符)
        private func op_noteCategory(_ args: [Any?]) -> String {
            guard let first = args.first,
                  let ncp = isNCP(first) else {
                return "X"
            }
            let category = NoteCategoryTools.classify(
                midiPitch: ncp.note.midiPitch,
                chordName: ncp.chord.name
            )
            return category.rawValue
        }
        
        /// (relative-pitch ncp) - 相对音高
        private func op_relativePitch(_ args: [Any?]) -> Any? {
            guard let first = args.first,
                  let ncp = isNCP(first) else {
                return nil
            }
            
            if ncp.note.isRest {
                return "0"
            }
            
            let rp = RelativePitchTools.relativePitch(
                midiPitch: ncp.note.midiPitch,
                chordName: ncp.chord.name
            )
            
            if rp == "0" {
                return nil
            }
            
            // 如果是纯数字，返回 Int；否则返回 String
            if let num = Int(rp) {
                return num
            }
            return rp
        }
        
        /// (absolute-pitch ncp) - 绝对音高（音符名）
        private func op_absolutePitch(_ args: [Any?]) -> String? {
            guard let first = args.first,
                  let ncp = isNCP(first) else {
                return nil
            }
            
            if ncp.note.isRest {
                return nil
            }
            
            // 将 MIDI 音高转换为音名
            let midi = ncp.note.midiPitch
            let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
            let octave = (midi / 12) - 1
            let noteIndex = midi % 12
            return "\(noteNames[noteIndex])\(octave)"
        }
        
        /// (pitch+ arg1 arg2) - 音高相加
        private func op_pitchAdd(_ args: [Any?]) -> Any? {
            guard args.count >= 2 else { return nil }
            let arg1 = args[0]
            let arg2 = args[1]
            
            let str1 = coerceToString(arg1)
            let str2 = coerceToString(arg2)
            
            // 都是相对音高格式
            if isRelativePitchFormat(str1) && isRelativePitchFormat(str2) {
                return RelativePitchTools.add(str1, str2)
            }
            
            // 一个是相对音高，一个是 NCP
            if isRelativePitchFormat(str1), let ncp2 = isNCP(arg2) {
                if ncp2.note.isRest { return nil }
                let rp2 = RelativePitchTools.relativePitch(
                    midiPitch: ncp2.note.midiPitch,
                    chordName: ncp2.chord.name
                )
                return RelativePitchTools.add(str1, rp2)
            }
            
            if let ncp1 = isNCP(arg1), isRelativePitchFormat(str2) {
                if ncp1.note.isRest { return nil }
                let rp1 = RelativePitchTools.relativePitch(
                    midiPitch: ncp1.note.midiPitch,
                    chordName: ncp1.chord.name
                )
                return RelativePitchTools.add(rp1, str2)
            }
            
            // 都是 NCP，返回平均音高
            if let ncp1 = isNCP(arg1), let ncp2 = isNCP(arg2) {
                return Double(ncp1.note.midiPitch + ncp2.note.midiPitch) / 2.0
            }
            
            return nil
        }
        
        /// (pitch- arg1 arg2) - 音高相减
        private func op_pitchSub(_ args: [Any?]) -> Any? {
            guard args.count >= 2 else { return nil }
            let arg1 = args[0]
            let arg2 = args[1]
            
            let str1 = coerceToString(arg1)
            let str2 = coerceToString(arg2)
            
            // 都是相对音高格式
            if isRelativePitchFormat(str1) && isRelativePitchFormat(str2) {
                let negRp2 = RelativePitchTools.negate(str2)
                return RelativePitchTools.add(str1, negRp2)
            }
            
            // 一个是相对音高，一个是 NCP
            if isRelativePitchFormat(str1), let ncp2 = isNCP(arg2) {
                if ncp2.note.isRest { return nil }
                let rp2 = RelativePitchTools.relativePitch(
                    midiPitch: ncp2.note.midiPitch,
                    chordName: ncp2.chord.name
                )
                let negRp2 = RelativePitchTools.negate(rp2)
                return RelativePitchTools.add(str1, negRp2)
            }
            
            if let ncp1 = isNCP(arg1), isRelativePitchFormat(str2) {
                if ncp1.note.isRest { return nil }
                let rp1 = RelativePitchTools.relativePitch(
                    midiPitch: ncp1.note.midiPitch,
                    chordName: ncp1.chord.name
                )
                let negRp2 = RelativePitchTools.negate(str2)
                return RelativePitchTools.add(rp1, negRp2)
            }
            
            // 都是 NCP，返回音高差
            if let ncp1 = isNCP(arg1), let ncp2 = isNCP(arg2) {
                return Double(ncp1.note.midiPitch - ncp2.note.midiPitch) / 2.0
            }
            
            return nil
        }
        
        /// (pitch> arg1 arg2) - 音高大于
        private func op_pitchGr(_ args: [Any?]) -> Bool? {
            let subResult = op_pitchSub(args)
            guard let sub = subResult else { return nil }
            
            let subStr = coerceToString(sub)
            
            // 负数表示更低
            if subStr.hasPrefix("-") {
                return false
            }
            
            // 如果以 1 结尾，需要看变音符号
            if subStr.hasSuffix("1") {
                let firstChar = subStr.first
                if firstChar == "#" {
                    return true
                } else {
                    return false
                }
            }
            
            return true
        }
        
        /// (pitch>= arg1 arg2) - 音高大于等于
        private func op_pitchGrEq(_ args: [Any?]) -> Bool? {
            let subResult = op_pitchSub(args)
            guard let sub = subResult else { return nil }
            
            let subStr = coerceToString(sub)
            
            // 负数表示更低
            if subStr.hasPrefix("-") {
                return false
            }
            
            // 如果以 1 结尾，需要看变音符号
            if subStr.hasSuffix("1") {
                let firstChar = subStr.first
                if firstChar == "b" {
                    return false
                } else {
                    return true
                }
            }
            
            return true
        }
        
        /// (pitch< arg1 arg2) - 音高小于
        private func op_pitchLt(_ args: [Any?]) -> Bool? {
            let subResult = op_pitchSub(args)
            guard let sub = subResult else { return nil }
            
            let subStr = coerceToString(sub)
            
            // 负数表示更低
            if subStr.hasPrefix("-") {
                return true
            }
            
            // 如果以 1 结尾，需要看变音符号
            if subStr.hasSuffix("1") {
                let firstChar = subStr.first
                if firstChar == "b" {
                    return true
                } else {
                    return false
                }
            }
            
            return false
        }
        
        /// (pitch<= arg1 arg2) - 音高小于等于
        private func op_pitchLtEq(_ args: [Any?]) -> Bool? {
            let subResult = op_pitchSub(args)
            guard let sub = subResult else { return nil }
            
            let subStr = coerceToString(sub)
            
            // 负数表示更低
            if subStr.hasPrefix("-") {
                return true
            }
            
            // 如果以 1 结尾，需要看变音符号
            if subStr.hasSuffix("1") {
                let firstChar = subStr.first
                if firstChar == "#" {
                    return false
                } else {
                    return true
                }
            }
            
            return false
        }
        
        // MARK: ===== 音符变换 =====
        
        /// (scale-duration scale ncp...) - 缩放时值
        private func op_scaleDuration(_ args: [Any?]) -> Any? {
            guard args.count >= 2 else { return nil }
            
            let scale = coerceToDouble(args[0])
            let ncps = Array(args.dropFirst())
            
            // 单个 NCP
            if ncps.count == 1, let ncp = isNCP(ncps[0]) {
                let newSlots = Int(Double(ncp.getDuration()) * scale)
                return ncp.setDuration(max(newSlots, 1))
            }
            
            // 多个 NCP，返回数组
            var result: [NoteChordPair] = []
            for ncpArg in ncps {
                if let ncp = isNCP(ncpArg) {
                    let newSlots = Int(Double(ncp.getDuration()) * scale)
                    result.append(ncp.setDuration(max(newSlots, 1)))
                }
            }
            return result
        }
        
        /// (add-duration duration ncp...) - 增加时值
        private func op_addDuration(_ args: [Any?]) -> Any? {
            guard args.count >= 2 else { return nil }
            
            let durStr = coerceToString(args[0])
            let addSlots = DurationTools.slots(from: durStr)
            let ncps = Array(args.dropFirst())
            
            // 单个 NCP
            if ncps.count == 1, let ncp = isNCP(ncps[0]) {
                let newSlots = ncp.getDuration() + addSlots
                return ncp.setDuration(newSlots)
            }
            
            // 多个 NCP
            var result: [NoteChordPair] = []
            for ncpArg in ncps {
                if let ncp = isNCP(ncpArg) {
                    let newSlots = ncp.getDuration() + addSlots
                    result.append(ncp.setDuration(newSlots))
                }
            }
            return result
        }
        
        /// (subtract-duration duration ncp...) - 减少时值
        private func op_subtractDuration(_ args: [Any?]) -> Any? {
            guard args.count >= 2 else { return nil }
            
            let durStr = coerceToString(args[0])
            let subSlots = DurationTools.slots(from: durStr)
            let ncps = Array(args.dropFirst())
            
            // 单个 NCP
            if ncps.count == 1, let ncp = isNCP(ncps[0]) {
                let newSlots = max(ncp.getDuration() - subSlots, 1)
                return ncp.setDuration(newSlots)
            }
            
            // 多个 NCP
            var result: [NoteChordPair] = []
            for ncpArg in ncps {
                if let ncp = isNCP(ncpArg) {
                    let newSlots = max(ncp.getDuration() - subSlots, 1)
                    result.append(ncp.setDuration(newSlots))
                }
            }
            return result
        }
        
        /// (multiply-duration multiplier ncp...) - 乘时值
        private func op_multiplyDuration(_ args: [Any?]) -> Any? {
            guard args.count >= 2 else { return nil }
            
            let multiplier = coerceToDouble(args[0])
            let ncps = Array(args.dropFirst())
            
            // 单个 NCP
            if ncps.count == 1, let ncp = isNCP(ncps[0]) {
                let newSlots = Int(Double(ncp.getDuration()) * multiplier)
                return ncp.setDuration(max(newSlots, 1))
            }
            
            // 多个 NCP
            var result: [NoteChordPair] = []
            for ncpArg in ncps {
                if let ncp = isNCP(ncpArg) {
                    let newSlots = Int(Double(ncp.getDuration()) * multiplier)
                    result.append(ncp.setDuration(max(newSlots, 1)))
                }
            }
            return result
        }
        
        /// (set-duration duration ncp...) - 设置时值
        private func op_setDuration(_ args: [Any?]) -> Any? {
            guard args.count >= 2 else { return nil }
            
            let durStr = coerceToString(args[0])
            let newSlots = DurationTools.slots(from: durStr)
            let ncps = Array(args.dropFirst())
            
            // 单个 NCP
            if ncps.count == 1, let ncp = isNCP(ncps[0]) {
                return ncp.setDuration(newSlots)
            }
            
            // 多个 NCP
            var result: [NoteChordPair] = []
            for ncpArg in ncps {
                if let ncp = isNCP(ncpArg) {
                    result.append(ncp.setDuration(newSlots))
                }
            }
            return result
        }
        
        /// (set-relative-pitch rel-pitch ncp...) - 设置相对音高
        private func op_setRelativePitch(_ args: [Any?]) -> Any? {
            guard args.count >= 2 else { return nil }
            
            let relPitch = coerceToString(args[0])
            let ncps = Array(args.dropFirst())
            
            // 单个 NCP
            if ncps.count == 1, let ncp = isNCP(ncps[0]) {
                let newMidi = RelativePitchTools.midiPitch(
                    from: relPitch,
                    chordName: ncp.chord.name,
                    referenceOctave: ncp.note.midiPitch
                )
                let newNote = PhysicalNote(
                    midiPitch: newMidi,
                    durationSlots: ncp.note.durationSlots
                )
                return NoteChordPair(
                    note: newNote,
                    chord: ncp.chord,
                    slot: ncp.slot,
                    transformVar: ncp.transformVar
                )
            }
            
            // 多个 NCP
            var result: [NoteChordPair] = []
            for ncpArg in ncps {
                if let ncp = isNCP(ncpArg) {
                    let newMidi = RelativePitchTools.midiPitch(
                        from: relPitch,
                        chordName: ncp.chord.name,
                        referenceOctave: ncp.note.midiPitch
                    )
                    let newNote = PhysicalNote(
                        midiPitch: newMidi,
                        durationSlots: ncp.note.durationSlots
                    )
                    let newNCP = NoteChordPair(
                        note: newNote,
                        chord: ncp.chord,
                        slot: ncp.slot,
                        transformVar: ncp.transformVar
                    )
                    result.append(newNCP)
                }
            }
            return result
        }
        
        /// (transpose-diatonic rel-pitch ncp...) - 全音阶移调
        private func op_transposeDiatonic(_ args: [Any?]) -> Any? {
            guard args.count >= 2 else { return nil }
            
            let relPitch = coerceToString(args[0])
            let ncps = Array(args.dropFirst())
            
            // 单个 NCP
            if ncps.count == 1, let ncp = isNCP(ncps[0]) {
                return transposeDiatonicSingle(ncp, by: relPitch)
            }
            
            // 多个 NCP
            var result: [NoteChordPair] = []
            for ncpArg in ncps {
                if let ncp = isNCP(ncpArg) {
                    if let transposed = transposeDiatonicSingle(ncp, by: relPitch) {
                        result.append(transposed)
                    }
                }
            }
            return result
        }
        
        /// 单个 NCP 的全音阶移调
        private func transposeDiatonicSingle(_ ncp: NoteChordPair, by relPitch: String) -> NoteChordPair? {
            if ncp.note.isRest { return nil }
            
            // 获取当前相对音高
            let currentRP = RelativePitchTools.relativePitch(
                midiPitch: ncp.note.midiPitch,
                chordName: ncp.chord.name
            )
            
            // 计算目标相对音高
            let targetRP = RelativePitchTools.add(currentRP, relPitch)
            
            // 解析目标相对音高，计算八度偏移
            let (augment, degree) = RelativePitchTools.parseRelativePitch(targetRP)
            
            // 计算八度偏移（超过 7 度的部分）
            let scaleSize = 7  // 一个八度 7 个音
            var octaveShift = 0
            var normalizedDegree = degree
            
            if degree > 0 {
                octaveShift = (degree - 1) / scaleSize
                normalizedDegree = (degree - 1) % scaleSize + 1
            } else if degree < 0 {
                octaveShift = (degree / scaleSize) - 1
                normalizedDegree = degree % scaleSize
                if normalizedDegree == 0 {
                    normalizedDegree = scaleSize
                }
                // 转换为正数度数
                normalizedDegree = scaleSize + normalizedDegree + 1
            }
            
            // 构造归一化的相对音高（一个八度内）
            let normalizedRP = augment + String(normalizedDegree)
            
            // 生成参考音（一个八度内的目标音）
            let referenceMidi = ncp.note.midiPitch - (ncp.note.midiPitch % 12)
            let targetMidiInOctave = RelativePitchTools.midiPitch(
                from: normalizedRP,
                chordName: ncp.chord.name,
                referenceOctave: referenceMidi
            )
            
            // 加上八度偏移
            let finalMidi = targetMidiInOctave + octaveShift * 12
            
            let newNote = PhysicalNote(
                midiPitch: finalMidi,
                durationSlots: ncp.note.durationSlots
            )
            
            return NoteChordPair(
                note: newNote,
                chord: ncp.chord,
                slot: ncp.slot,
                transformVar: ncp.transformVar
            )
        }
        
        /// (transpose-chromatic semitones ncp...) - 半音阶移调
        private func op_transposeChromatic(_ args: [Any?]) -> Any? {
            guard args.count >= 2 else { return nil }
            
            let semitones = Int(coerceToDouble(args[0]))
            let ncps = Array(args.dropFirst())
            
            // 单个 NCP
            if ncps.count == 1, let ncp = isNCP(ncps[0]) {
                if ncp.note.isRest { return nil }
                let newMidi = ncp.note.midiPitch + semitones
                let newNote = PhysicalNote(
                    midiPitch: max(0, min(127, newMidi)),
                    durationSlots: ncp.note.durationSlots
                )
                return NoteChordPair(
                    note: newNote,
                    chord: ncp.chord,
                    slot: ncp.slot,
                    transformVar: ncp.transformVar
                )
            }
            
            // 多个 NCP
            var result: [NoteChordPair] = []
            for ncpArg in ncps {
                if let ncp = isNCP(ncpArg) {
                    if ncp.note.isRest { continue }
                    let newMidi = ncp.note.midiPitch + semitones
                    let newNote = PhysicalNote(
                        midiPitch: max(0, min(127, newMidi)),
                        durationSlots: ncp.note.durationSlots
                    )
                    let newNCP = NoteChordPair(
                        note: newNote,
                        chord: ncp.chord,
                        slot: ncp.slot,
                        transformVar: ncp.transformVar
                    )
                    result.append(newNCP)
                }
            }
            return result
        }
        
        /// (make-rest ncp...) - 变成休止符
        private func op_makeRest(_ args: [Any?]) -> Any? {
            guard !args.isEmpty else { return nil }
            
            // 单个 NCP
            if args.count == 1, let ncp = isNCP(args[0]) {
                let restNote = PhysicalNote(
                    midiPitch: -1,
                    durationSlots: ncp.note.durationSlots
                )
                return NoteChordPair(
                    note: restNote,
                    chord: ncp.chord,
                    slot: ncp.slot,
                    transformVar: ncp.transformVar
                )
            }
            
            // 多个 NCP
            var result: [NoteChordPair] = []
            for arg in args {
                if let ncp = isNCP(arg) {
                    let restNote = PhysicalNote(
                        midiPitch: -1,
                        durationSlots: ncp.note.durationSlots
                    )
                    let newNCP = NoteChordPair(
                        note: restNote,
                        chord: ncp.chord,
                        slot: ncp.slot,
                        transformVar: ncp.transformVar
                    )
                    result.append(newNCP)
                }
            }
            return result
        }
        
        /// (get-note ncp...) - 获取音符（返回 NCP 的音符部分）
        /// 注意：Swift 版没有独立的 Note 类，这里返回 NCP 本身（因为音符信息都在 NCP 里）
        private func op_getNote(_ args: [Any?]) -> Any? {
            guard !args.isEmpty else { return nil }
            
            if args.count == 1 {
                return isNCP(args[0])
            }
            
            var result: [NoteChordPair] = []
            for arg in args {
                if let ncp = isNCP(arg) {
                    result.append(ncp)
                }
            }
            return result
        }
        
        /// (print-note ncp) - 打印音符（调试用）
        private func op_printNote(_ args: [Any?]) -> String {
            guard let first = args.first,
                  let ncp = isNCP(first) else {
                return "nil"
            }
            if ncp.note.isRest {
                return "Rest(\(ncp.note.durationSlots))"
            }
            return "Note(midi:\(ncp.note.midiPitch), dur:\(ncp.note.durationSlots), chord:\(ncp.chord.name))"
        }
    }
}
