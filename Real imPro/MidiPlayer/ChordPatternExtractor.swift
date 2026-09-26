import Foundation

// MARK: - ChordPatternExtractor 钢琴伴奏 → CompanionNote 生成器
// 将 ChordPattern 的切分节奏映射为具体和弦 Voicing 的 MIDI 音符

struct ChordPatternExtractor {
    
    /// 标准 MIDI 音名 → 半音偏移 (复用 BassPatternExtractor 逻辑)
    private static let noteToChromatic: [String: Int] = [
        "c": 0, "c#": 1, "db": 1, "d": 2, "d#": 3, "eb": 3,
        "e": 4, "f": 5, "f#": 6, "gb": 6, "g": 7, "g#": 8,
        "ab": 8, "a": 9, "a#": 10, "bb": 10, "b": 11
    ]
    
    /// 爵士 Voicing 字典: 和弦类型 → [相对根音半音偏移]
    /// Shell voicing (3+7) + 扩展音, 根音留给贝斯
    private static let voicings: [String: [Int]] = [
        "maj7":  [4, 11, 14],  // 3, 7, 9
        "m7":    [3, 10, 14],  // 3, 7, 9
        "7":     [4, 10, 14],  // 3, 7, 9
        "dim":   [3, 6, 12],   // 3, 5, 8  (dim 三和弦 — 无 7)
        "dim7":  [3, 6, 9],    // 3, 5, 7
        "m7b5":  [3, 6, 10],   // 3, 5, 7
        "mMaj7": [3, 11, 14],  // 3, 7, 9
        "6":     [4, 9, 14],   // 3, 6, 9
        "m6":    [3, 9, 14],   // 3, 6, 9
        "sus4":  [5, 7, 12],   // 4, 5, 8  (三和弦 — 无 7)
        "7sus":  [5, 7, 10],   // 4, 5, 7
        "aug":   [4, 8, 12],   // 3, #5, 8 (三和弦 — 无 7)
        "aug7":  [4, 8, 10],   // 3, #5, 7 (小七 — 特征音保护)
        "7b5":   [4, 6, 10],   // 3, ♭5, 7
    ]
    
    // 钢琴音域: A2-C6 (MIDI 45-76, 略放宽)
    private static let defaultMinMidi = 48   // C3 — 原版 chord-low 默认
    private static let defaultMaxMidi = 69   // A4 — 原版 chord-high 默认
    private static let afroMaxMidi    = 60   // C4 — african.sty chord-high
    private static let swingMinMidi   = 50   // D3 — swing.sty chord-low
    private static let balladMinMidi  = 47   // B2 — ballad.sty chord-low
    private static let balladMaxMidi  = 71   // B4 — ballad.sty chord-high
    
    // MARK: - 和弦解析 (复用 BassPatternExtractor 逻辑)
    
    private static func parseChord(_ name: String) -> (root: Int, voicing: [Int])? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let cleaned = trimmed.lowercased()
        guard let first = cleaned.first else { return nil }
        
        var rootStr = String(first)
        var remaining = String(cleaned.dropFirst())
        if remaining.hasPrefix("#") || remaining.hasPrefix("b") {
            rootStr += String(remaining.removeFirst())
        }
        
        guard let rootChromatic = noteToChromatic[rootStr] else { return nil }
        
        // 从原始（未小写）名称截取同长度后缀 — 保留 M7/mMaj 大小写
        let origRemaining = String(trimmed.dropFirst(rootStr.count))
        
        let type: String
        if origRemaining.lowercased().contains("mmaj") || origRemaining.lowercased().contains("mm7") {
            type = "mMaj7"
        } else if origRemaining.contains("M6") || origRemaining.lowercased().contains("maj6") {
            type = "6"
        } else if origRemaining.lowercased().contains("maj") || origRemaining.contains("M7") || origRemaining.contains("△") {
            type = "maj7"
        } else {
            let lower = remaining.lowercased()
            if lower.contains("dim") || lower.contains("°") || lower.contains("o") {
                type = lower.contains("7") ? "dim7" : "dim"
            } else if lower.contains("m7b5") || lower.contains("ø") || lower.contains("min7b5") || lower.contains("-7b5") || lower.contains("m7♭5") {
                type = "m7b5"
            } else if lower.contains("b5") || lower.contains("♭5") || lower.contains("-5") {
                type = "7b5"
            } else if lower.contains("aug") || lower.contains("+") || lower.contains("#5") || lower.contains("♯5") {
                type = lower.contains("7") ? "aug7" : "aug"
            } else if lower.contains("sus") {
                type = lower.contains("7") || lower.contains("9") || lower.contains("11") || lower.contains("13") ? "7sus" : "sus4"
            } else if lower.contains("m6") {
                type = "m6"
            } else if lower.contains("6") {
                type = "6"
            } else if lower.hasPrefix("-") || (lower.contains("m") && !lower.contains("dom")) {
                type = lower.contains("7") ? "m7" : "m7"
            } else if lower.contains("7") || lower.contains("9") || lower.contains("11") || lower.contains("13") {
                type = "7"
            } else {
                type = "maj7"
            }
        }
        
        guard let intervals = voicings[type] else { return nil }
        return (rootChromatic, intervals)
    }
    
    // MARK: - 极简声部连接 (Minimal Voice Leading)
    
    /// 上一和弦的实际 MIDI 音符 (跨小节持久，声部连接)
    private static var lastVoicingMidis: [UInt8] = [55]   // F#3 初始锚点
    private static var lastVoicingCenter: Double {
        Double(lastVoicingMidis.reduce(0, { Int($0) + Int($1) })) / Double(lastVoicingMidis.count)
    }
    
    /// 整体块平移: 转位 + 八度偏移, 保持和弦形状不变, 选距离最近且在音域内的
    private static func bestInversion(root: Int, intervals: [Int], style: String) -> [UInt8] {
        let minMidi: Int
        let maxMidi: Int
        switch style.lowercased() {
        case "swing":  minMidi = Self.swingMinMidi;  maxMidi = Self.defaultMaxMidi
        case "ballad": minMidi = Self.balladMinMidi; maxMidi = Self.balladMaxMidi
        case "afro":   minMidi = Self.defaultMinMidi; maxMidi = Self.afroMaxMidi
        default:       minMidi = Self.defaultMinMidi; maxMidi = Self.defaultMaxMidi
        }
        var bestMidis: [Int] = []
        var bestDist = Double.infinity
        
        for inv in 0..<min(3, intervals.count) {
            // 转位: 轮转音程数组, 首个通过 +12 推高一个八度
            let shifted = (inv..<inv+intervals.count).map { i in
                intervals[i % intervals.count] + (i < intervals.count ? 0 : 12)
            }
            
            // 基础 MIDI: C3(48) + root + voicing
            let raw = shifted.map { 48 + root + $0 }
            
            // 整体八度平移 0 或 -12 半音, 禁止 +12 避免音过高
            for octave in [-12, 0] {
                let candidate = raw.map { $0 + octave }
                guard let hi = candidate.max(), let lo = candidate.min(),
                      hi <= maxMidi && lo >= minMidi else { continue }
                
                let center = Double(candidate.reduce(0, +)) / Double(candidate.count)
                let commonTones = candidate.filter { lastVoicingMidis.contains(UInt8($0)) }.count
                let dist = abs(center - lastVoicingCenter) - Double(commonTones) * 8.0
                if dist < bestDist {
                    bestDist = dist
                    bestMidis = candidate
                }
            }
        }
        
        // 兜底强制钳位 (防止 Afro + 高根音 + 扩展voicing 死循环)
        if bestMidis.isEmpty {
            var fallback = intervals.map { 48 + root + $0 }
            for _ in 0..<4 {
                guard let hi = fallback.max(), hi > maxMidi else { break }
                fallback = fallback.map { $0 - 12 }
            }
            for _ in 0..<4 {
                guard let lo = fallback.min(), lo < minMidi else { break }
                fallback = fallback.map { $0 + 12 }
            }
            bestMidis = fallback
        }
        
        lastVoicingMidis = bestMidis.map { UInt8($0) }
        return bestMidis.map { UInt8($0) }
    }
    private static func jitterVelocity(_ base: UInt8) -> UInt8 {
        let j = Int.random(in: -8...8)
        let v = Int(base) + j
        return UInt8(max(10, min(127, v)))
    }
    
    private static func jitterStartSlot(_ base: Int) -> Int {
        return max(0, base + Int.random(in: -3...3))
    }
    
    // MARK: - Public API
    
    // MARK: - 动态平铺

    private static func tileElements(_ elements: [ChordElement], slotsPerMeasure: Int, style: String) -> [ChordElement] {
        let L = style.lowercased() == "waltz" ? 360 : 480
        if L == 0 { return elements }
        var result: [ChordElement] = []
        var cursor = 0
        while cursor < slotsPerMeasure {
            for var el in elements {
                el.onsetSlots += cursor
                if el.onsetSlots >= slotsPerMeasure { continue }
                if el.onsetSlots + el.durationSlots > slotsPerMeasure {
                    el.durationSlots = slotsPerMeasure - el.onsetSlots
                }
                result.append(el)
            }
            cursor += L
        }
        return result
    }
    
    /// 根据 ChordPattern + 和弦列表生成钢琴伴奏音符 (逐小节抽卡 + 独立抖动 + 块平移)
    static func generate(
        pattern _unused: ChordPattern? = nil,
        chordSymbols: [String],
        measureCount: Int,
        slotsPerMeasure: Int = 480,
        style: String = "swing"
    ) -> [CompanionNote] {
        var notes: [CompanionNote] = []
        
        for measure in 0..<measureCount {
            let pattern = style.lowercased() == "ballad" ? ChordPattern.ballad()
                        : style.lowercased() == "bossa" ? ChordPattern.bossa()
                        : style.lowercased() == "waltz" ? ChordPattern.waltz()
                        : style.lowercased() == "latin" ? ChordPattern.latin()
                        : style.lowercased() == "shuffle" || style.lowercased() == "blues" ? ChordPattern.blues()
                        : style.lowercased() == "afro" ? ChordPattern.afro()
                        : ChordPattern.basicSwing()
            let chordName = measure < chordSymbols.count
                ? chordSymbols[measure]
                : (chordSymbols.last ?? "Cmaj7")
            
            guard let (root, intervals) = parseChord(chordName) else { continue }
            
            let measureOffset = measure * slotsPerMeasure
            
            for element in Self.tileElements(pattern.elements, slotsPerMeasure: slotsPerMeasure, style: style) {
                guard element.noteType == .chord else { continue }
                // 人性化时间微调: ±3 slots
                
                let midis = bestInversion(root: root, intervals: intervals, style: style)
                let vel = jitterVelocity(element.velocity)
                
                for midi in midis {
                    // Bug2: 每个 voicing 音独立抖动, 模拟手指滚奏
                    let absStart = jitterStartSlot(measureOffset + element.onsetSlots)
                    notes.append(CompanionNote(
                        startSlot: absStart,
                        midiPitch: midi,
                        durationSlots: element.durationSlots,
                        volume: vel,
                        channel: 1
                    ))
                }
            }
        }
        
        notes.sort { $0.startSlot < $1.startSlot }
        return notes
    }
}
