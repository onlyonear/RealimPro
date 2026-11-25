//
//  GrammarTerminals.swift
//  Improlyze
//
//  Grammar 终结符定义和工具函数
//  第一阶段：支持最简单的终结符（C4, L8, R2 等）
//

import Foundation

// MARK: - 终结符类型

/// 抽象音符类型 — 对齐 Java Constants.java T_CHORD/T_COLOR/T_SCALE/T_NOTE (L881-884)
enum GrammarTerminalType: String {
    case chord = "C"        // 和弦音 (Java T_CHORD)
    case color = "L"        // 色彩音 (Java T_COLOR, 9/11/13延伸音)
    case scale = "S"        // 音阶音 (Java T_SCALE, 7声音阶)
    case note = "H"         // 普通音符 (Java T_NOTE, checkNote直接return true; 选音池=chord∪color∪scale三池加权, P0-3实现)
    case approach = "A"     // 趋近音
    case arbitrary = "X"    // 任意音
    case outside = "Y"      // 外音
    case rest = "R"         // 休止符
    case scaleDegree        // 音阶级数
    case slope              // 斜率/旋律轮廓
    case triadic            // 三和弦分解
}

/// 终结符 - 表示一个抽象的音符或休止符
struct GrammarTerminal {
    let type: GrammarTerminalType
    let durationSlots: Int
    let isDotted: Bool
    let tuplet: Int
    let scaleDegree: String? // 音阶级数（仅 scaleDegree 类型使用，如 "3", "b5"）
    let minSlope: Int?      // 最小斜率（仅 slope 类型使用）
    let maxSlope: Int?      // 最大斜率（仅 slope 类型使用）
    let slopeNotes: [GrammarTerminal]? // 内部音符
    let slopeMin: Int?      // 父 slope min 展平子音符携带
    let slopeMax: Int?      // 父 slope max 展平子音符携带
    
    var actualDuration: Int {
        // slope 类型：总时值是内部所有音符时值之和
        if type == .slope, let notes = slopeNotes {
            return notes.reduce(0) { $0 + $1.actualDuration }
        }
        // triadic / 普通类型统一复用基础时值计算
        var duration = durationSlots
        if isDotted {
            duration = duration * 3 / 2
        }
        if tuplet > 0 {
            duration = duration * (tuplet - 1) / tuplet
        }
        return duration
    }
    
    // 便捷初始化：普通抽象音符（triadic 直接复用此构造）
    init(type: GrammarTerminalType, durationSlots: Int, isDotted: Bool = false, tuplet: Int = 0,
         slopeMin: Int? = nil, slopeMax: Int? = nil) {
        self.type = type
        self.durationSlots = durationSlots
        self.isDotted = isDotted
        self.tuplet = tuplet
        self.slopeMin = slopeMin
        self.slopeMax = slopeMax
        self.scaleDegree = nil
        self.minSlope = nil
        self.maxSlope = nil
        self.slopeNotes = nil
    }
    
    // 便捷初始化：音阶级数
    init(scaleDegree: String, durationSlots: Int, isDotted: Bool = false, tuplet: Int = 0) {
        self.type = .scaleDegree
        self.durationSlots = durationSlots
        self.isDotted = isDotted
        self.tuplet = tuplet
        self.scaleDegree = scaleDegree
        self.minSlope = nil
        self.maxSlope = nil
        self.slopeNotes = nil
        self.slopeMin = nil
        self.slopeMax = nil
    }
    
    // 便捷初始化：slope 斜率
    init(minSlope: Int, maxSlope: Int, slopeNotes: [GrammarTerminal]) {
        self.type = .slope
        self.durationSlots = 0
        self.isDotted = false
        self.tuplet = 0
        self.scaleDegree = nil
        self.minSlope = minSlope
        self.maxSlope = maxSlope
        self.slopeNotes = slopeNotes
        self.slopeMin = nil
        self.slopeMax = nil
    }
}

// MARK: - 符号类型

/// 语法符号 - 可以是终结符，也可以是非终结符
enum GrammarSymbol {
    case terminal(GrammarTerminal)
    case nonTerminal(String, [String])  // 参数保留原始字符串，延迟求值
    case list([GrammarSymbol])
}

// MARK: - 解析工具

class GrammarTerminalParser {
    
    /// 解析一个终结符字符串，比如 "C4", "L8", "R2.", "C16", "C8/3"
    static func parseTerminal(_ string: String) -> GrammarTerminal? {
        let str = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return nil }
        
        // 第一个字符是类型
        let firstChar = String(str.prefix(1))
        guard let type = GrammarTerminalType(rawValue: firstChar) else {
            return nil
        }
        
        // 剩余部分直接作为完整时值字符串（支持 4、8、4+8、16/3、8./3 等全部格式）
        let durationStr = String(str.dropFirst())
        let (durationSlots, isDotted, tuplet) = parseDuration(durationStr)
        
        // 解析失败兜底
        guard durationSlots > 0 else { return nil }
        
        return GrammarTerminal(
            type: type,
            durationSlots: durationSlots,
            isDotted: isDotted,
            tuplet: tuplet
        )
    }
    
    /// 将音符时值转换为 slot 数
    /// 1 = 全音符, 2 = 二分, 4 = 四分, 8 = 八分, 16 = 十六分, 32 = 三十二分
    private static func noteValueToSlots(_ noteValue: Int) -> Int {
        // 一拍 = 120 slots（四分音符）
        // 全音符 = 4 拍 = 480 slots
        // 二分 = 2 拍 = 240 slots
        // 四分 = 1 拍 = 120 slots
        // 八分 = 0.5 拍 = 60 slots
        // 十六分 = 0.25 拍 = 30 slots
        // 三十二分 = 0.125 拍 = 15 slots
        
        switch noteValue {
        case 1: return 480
        case 2: return 240
        case 4: return 120
        case 8: return 60
        case 16: return 30
        case 32: return 15
        default:
            // 其他值按比例计算
            return 480 / noteValue
        }
    }
    
    /// 判断一个字符串是不是终结符
    static func isTerminal(_ string: String) -> Bool {
        return parseTerminal(string) != nil
    }
    
    // MARK: - Scale Degree 终结符
    
    /// 判断一个符号列表是否是 scale degree 终结符
    /// 格式：(X <degree> <duration>)，例如 (X 3 8), (X b5 4.)
    static func isScaleDegreeTerminal(_ symbols: [String]) -> Bool {
        guard symbols.count == 3 else { return false }
        guard symbols[0] == "X" else { return false }
        // 第二个是级数（可以是数字或带升降号的字符串）
        // 第三个是时值字符串
        return true
    }
    
    /// 解析 scale degree 终结符
    /// 输入是符号数组，例如 ["X", "3", "8"] 或 ["X", "b5", "4."]
    static func parseScaleDegreeTerminal(_ symbols: [String]) -> GrammarTerminal? {
        guard isScaleDegreeTerminal(symbols) else { return nil }
        
        let degree = symbols[1]
        let durationStr = symbols[2]
        
        let (slots, isDotted, tuplet) = parseDuration(durationStr)
        
        return GrammarTerminal(scaleDegree: degree, durationSlots: slots, isDotted: isDotted, tuplet: tuplet)
    }
    
    /// 解析时值字符串，返回 (slots, isDotted, tuplet)
    /// 支持加法时值，如 "2+4"（二分+四分=三拍）、"2.+8/3+32"
    private static func parseDuration(_ durationStr: String) -> (Int, Bool, Int) {
        // 检查是否是加法时值（包含 + 号）
        if durationStr.contains("+") {
            let parts = durationStr.components(separatedBy: "+")
            var totalSlots = 0
            
            for part in parts {
                let (slots, isDotted, tuplet) = parseSingleDuration(part)
                var duration = slots
                if isDotted {
                    duration = duration * 3 / 2
                }
                if tuplet > 0 {
                    duration = duration * (tuplet - 1) / tuplet
                }
                totalSlots += duration
            }
            
            // 加法时值返回总 slots，isDotted 和 tuplet 设为默认值（总时值已计算好）
            return (totalSlots, false, 0)
        } else {
            // 单个时值
            return parseSingleDuration(durationStr)
        }
    }
    
    /// 解析单个时值字符串（不含 + 号）
    private static func parseSingleDuration(_ durationStr: String) -> (Int, Bool, Int) {
        var str = durationStr
        
        // 检查是否有附点
        let isDotted = str.contains(".")
        str = str.replacingOccurrences(of: ".", with: "")
        
        // 检查是否有连音（/3 三连音，/5 五连音）
        var tuplet = 0
        if str.contains("/") {
            let parts = str.components(separatedBy: "/")
            if parts.count == 2, let tupletValue = Int(parts[1]) {
                tuplet = tupletValue
                str = parts[0]
            }
        }
        
        // 解析时值
        guard let durationValue = Int(str) else {
            return (0, false, 0)
        }
        
        let slots = noteValueToSlots(durationValue)
        return (slots, isDotted, tuplet)
    }
    
    // MARK: - Slope 终结符
    
    /// 判断一个符号列表是否是 slope 终结符
    /// 格式：(slope <min> <max> <note1> <note2> ...)
    /// 例如：(slope 1 3 C8 C8 C8), (slope -4 -1 S16 S16 S16 S16)
    static func isSlopeTerminal(_ symbols: [String]) -> Bool {
        guard symbols.count >= 4 else { return false }
        guard symbols[0] == "slope" else { return false }
        // 第二个和第三个必须是数字（min 和 max）
        guard Int(symbols[1]) != nil else { return false }
        guard Int(symbols[2]) != nil else { return false }
        // 后面至少有一个音符
        return true
    }
    
    /// 解析 slope 终结符
    /// 输入是符号数组，例如 ["slope", "1", "3", "C8", "C8", "C8"]
    static func parseSlopeTerminal(_ symbols: [String]) -> GrammarTerminal? {
        guard isSlopeTerminal(symbols) else { return nil }
        
        let minSlope = Int(symbols[1]) ?? 0
        let maxSlope = Int(symbols[2]) ?? 0
        
        // 解析后面的所有音符
        var notes: [GrammarTerminal] = []
        for i in 3..<symbols.count {
            let noteStr = symbols[i]
            if let note = parseTerminal(noteStr) {
                notes.append(note)
            }
        }
        
        guard !notes.isEmpty else { return nil }
        
        return GrammarTerminal(minSlope: minSlope, maxSlope: maxSlope, slopeNotes: notes)
    }
    // MARK: - Triadic 终结符
    /// 判断符号列表是否为 triadic 三和弦分解终结符，格式：(triadic 4) / (triadic 8.)
    static func isTriadicTerminal(_ symbols: [String]) -> Bool {
        guard symbols.count == 2 else { return false }
        return symbols[0] == "triadic"
    }

    /// 解析 triadic 终结符
    static func parseTriadicTerminal(_ symbols: [String]) -> GrammarTerminal? {
        guard isTriadicTerminal(symbols) else { return nil }
        let durStr = symbols[1]
        let (slots, isDotted, tuplet) = parseDuration(durStr)
        // 复用通用构造器，不再使用专属triadic初始化
        return GrammarTerminal(type: .triadic, durationSlots: slots, isDotted: isDotted, tuplet: tuplet)
    }
}
