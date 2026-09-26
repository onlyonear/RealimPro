import Foundation

// MARK: - 基础调式枚举 (提取自 Java 的 findModeFromQuality 逻辑)
// MARK: 完整8类爵士和弦族
enum ChordFamily: String, Equatable {
    case major          // maj, maj7, maj9, 6
    case minor          // m, m7, m9
    case dominant       // 7,9,13,7b9,7#9
    case halfDiminished // m7b5, ø7
    case diminished     // dim, dim7, o7
    case augmented      // aug, +7
    case sus            // sus4, sus2, sus7
    case unknown
}

enum JazzMode: String {
    case major = "Major"
    case minor = "Minor"
    case dominant = "Dominant"
    case dorian = "Dorian"           // P1-KeyMode: So What风格
    case phrygian = "Phrygian"       // P1-KeyMode: Flamenco爵士
    case lydian = "Lydian"           // P1-KeyMode: #11特性
    case locrian = "Locrian"         // P1-KeyMode: 半减七功能
    case unknown = "Unknown"
}

// MARK: - 核心乐理协议：统一单和弦(ChordBlock)与和弦语块(Brick)
/// 对应 Java 源码中的 `abstract class Block`
protocol JazzBlock {
    var name: String { get }        // 名字，如 "Dm7" 或 "ii-V-I"
    var duration: Double { get }       // 持续的物理节拍长度
    var length: Int { get }         // 内部包含的独立和弦数量
    var isSingleChord: Bool { get } // 是否只包含单个和弦
    
    /// 将复杂的嵌套语块，彻底展平为一维的单和弦数组
    func flatten() -> [ChordBlock]
    /// 获取这个语块起跑的第一个和弦
    func getFirstChord() -> ChordBlock?
}

// MARK: - 单词层：和弦块 (ChordBlock)
/// 对应 Java 源码中的 `ChordBlock.java`，爵士乐语法的最小“单词”
struct ChordBlock: JazzBlock, Equatable {
    var name: String
    var duration: Double
    var isSectionStart: Bool = false  // 🌟 是否是段落开始的第一个和弦
    var brickType: String? = nil       // P0-2: CYK解析出的Brick句型标识 ("ii-V-I"等)
    
    var length: Int { return 1 }
    var isSingleChord: Bool { return true }
    
    // 【核心基因移植】和弦性质与调性推断引擎
    func findModeFromQuality() -> JazzMode {
        let qualityStr = name.drop { $0.isLetter && $0.isUppercase || $0 == "#" || $0 == "b" }
        let q = String(qualityStr)
        
        if q.hasPrefix("M") || q.hasPrefix("maj") || q.isEmpty || q.hasPrefix("6") {
            return .major
        } else if q.hasPrefix("7") || q.hasPrefix("9") || q.hasPrefix("11") || q.hasPrefix("13") {
            return .dominant
        } else {
            return .minor
        }
    }
    
    /// 完整8大类和弦族识别（供builtin chord-family调用）
    func getChordFamily() -> ChordFamily {
        let qualityStr = name.drop { $0.isLetter && $0.isUppercase || $0 == "#" || $0 == "b" }
        let q = String(qualityStr).lowercased()
        
        if q.contains("dim7") || q.contains("o7") {
            return .diminished                  // 仅带 7 的 dim/o 为减七
        }
        if q.contains("m7b5") || q.contains("ø") || q.contains("dim") || q == "o" || q.hasPrefix("h") {
            return .halfDiminished              // 普通 dim/减三和弦为半减七; iReal Pro "h" = m7b5
        }
        if q.contains("aug") || q.contains("+") {
            return .augmented
        }
        if q.hasPrefix("sus") {
            return .sus
        }
        // 🌟 修复: maj7 必须在小写 "m" 之前判断 (否则 "maj7" 会被 hasPrefix("m") 误判成 minor)
        if q.hasPrefix("maj") || q.hasPrefix("M") || q == "6" || q.hasPrefix("^") {
            return .major                        // iReal Pro "^" = maj7 (D^ = Dmaj7)
        }
        if q.hasPrefix("m") {
            return .minor
        }
        if q.hasPrefix("7") || q.hasPrefix("9") || q.hasPrefix("13") || q.hasPrefix("b9") || q.hasPrefix("#9") {
            return .dominant
        }
        if q.isEmpty { return .major }
        return .unknown
    }

    // MARK: - P1-1 Chord.getTypeIndex() 和弦音层级判定
    /// Chord.java getTypeIndex: 区分 root/3/5/7/9/11/13/alter
    /// - Parameters:
    ///   - pitchClass: 目标 MIDI 音高 (0-127)
    /// - Returns: 0=root 1=b3/3 2=P5 3=7 4=9 5=11 6=13, -1=non-chord
    func getTypeIndex(for midiPitch: Int) -> Int {
        let rootPC = chordRootPC()
        let relative = ((midiPitch % 12) - rootPC + 12) % 12
        let family = getChordFamily()
        // 按和弦族分层鉴定
        switch relative {
        case 0:  return 0   // 根音
        case 4:  return 1   // 大三度 (major/dominant/aug/sus)
        case 3:  return (family == .minor || family == .halfDiminished || family == .diminished) ? 1 : -1
        case 7:  return 2   // 纯五度
        case 11: return (family == .major) ? 3 : -1   // 大七度
        case 10: return (family == .minor || family == .dominant || family == .halfDiminished || family == .diminished) ? 3 : -1  // 小七度/减七
        case 2:  return 4   // 9 (所有和弦族)
        case 5:  return 5   // 11 (major/minor/dominant/halfdim)
        case 9:  return 6   // 13 (major/minor/dominant)
        case 1:  return (family == .dominant) ? 4 : -1  // b9→alter 9 (属七特性)
        case 6:  return (family == .dominant || family == .augmented) ? 5 : -1  // #11
        case 8:  return (family == .dominant || family == .halfDiminished) ? 6 : -1  // b13
        default: return -1
        }
    }

    /// 辅助: 从和弦名提取根音pitch class
    func chordRootPC() -> Int {
        let n = name.replacingOccurrences(of: "♭", with: "b").replacingOccurrences(of: "♯", with: "#")
        let root = n.prefix { $0.isLetter && $0.isUppercase || $0 == "#" || $0 == "b" }
        switch String(root) {
        case "C": return 0; case "C#","Db": return 1; case "D": return 2
        case "D#","Eb": return 3; case "E": return 4; case "F": return 5
        case "F#","Gb": return 6; case "G": return 7; case "G#","Ab": return 8
        case "A": return 9; case "A#","Bb": return 10; case "B": return 11
        default: return 0
        }
    }

    /// 任意音名(含 Cb/Fb/E#/B# 等音与重升降) → pitch class。
    /// 首字符为自然音名, 其余 '#' 升半音 / 'b' 降半音, 循环到 0..<12。
    static func spellToPC(_ s: String) -> Int {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let f = t.first else { return 0 }
        let nat: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        guard var pc = nat[f] else { return 0 }
        for ch in t.dropFirst() {
            if ch == "#" { pc += 1 } else if ch == "b" { pc -= 1 }
        }
        return ((pc % 12) + 12) % 12
    }

    /// 分析链"定中心参考音"(对齐 Java 金标准口径): 斜杠和弦 C/E 按 polychord 处理,
    /// 取斜杠低音作为 KeySpan/砖匹配参考音 (Java BatchHarness 把 '/' 替换为 '\' 后
    /// ChordBlock.getKey() 返回 polybase 根音 = 低音); 无斜杠时等同根音。
    /// 注意: 罗马级数仍用 chordRootPC() (C/E 在 C 调仍是 I, 不是 III)。
    func centerPC() -> Int {
        if let slash = name.lastIndex(of: "/") {
            let bass = String(name[name.index(after: slash)...]).trimmingCharacters(in: .whitespaces)
            if !bass.isEmpty { return ChordBlock.spellToPC(bass) }
        }
        return chordRootPC()
    }

    
    func flatten() -> [ChordBlock] {
        return [self]
    }
    
    func getFirstChord() -> ChordBlock? {
        return self
    }
}

// MARK: - 词组层：和弦语块 (Brick)
/// 对应 Java 源码中的 `Brick.java`，爵士乐的高级“词组/成语” (如 2-5-1 进行)
struct Brick: JazzBlock {
    var name: String
    var subBlocks: [JazzBlock] // 内部可以包含 ChordBlock，甚至嵌套其他的 Brick!
    
    // 动态计算总时长 (对应 Java 里的 accumulator 逻辑)
    var duration: Double {
        return subBlocks.reduce(0.0) { $0 + $1.duration }
    }
    
    // 展平后的总和弦数
    var length: Int {
        return flatten().count
    }
    
    var isSingleChord: Bool {
        return length == 1
    }
    
    // 将嵌套的语块（比如一个二五一砖块里套着另一个替换砖块）彻底展平
    func flatten() -> [ChordBlock] {
        return subBlocks.flatMap { $0.flatten() }
    }
    
    func getFirstChord() -> ChordBlock? {
        return flatten().first
    }
}

