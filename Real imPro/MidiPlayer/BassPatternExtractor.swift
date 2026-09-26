import Foundation

// MARK: - BassPatternExtractor 贝斯 Pattern → CompanionNote 生成器
// 将 BassPattern 的相对音高展开为实际 MIDI 音符，
// 根据和弦进行自动解析根音/三音/五音/七音。

struct BassPatternExtractor {
    
    /// 标准 MIDI 音名 → 半音偏移 (C=0, C#=1, ..., B=11)
    private static let noteToChromatic: [String: Int] = [
        "c": 0, "c#": 1, "db": 1, "d": 2, "d#": 3, "eb": 3,
        "e": 4, "f": 5, "f#": 6, "gb": 6, "g": 7, "g#": 8,
        "ab": 8, "a": 9, "a#": 10, "bb": 10, "b": 11
    ]
    
    /// 和弦音程字典： 和弦类型 → [相对于根音的半音偏移]
    private static let chordIntervals: [String: [Int]] = [
        "maj7": [0, 4, 7, 11],
        "m7":   [0, 3, 7, 10],
        "7":    [0, 4, 7, 10],
        "dim":  [0, 3, 6],      // dim 三和弦 (无 7)
        "dim7": [0, 3, 6, 9],
        "m7b5": [0, 3, 6, 10],
        "mMaj7":[0, 3, 7, 11],
        "6":    [0, 4, 7, 9],
        "m6":   [0, 3, 7, 9],
        "sus4": [0, 5, 7],      // 4 替代 3 (三和弦)
        "7sus": [0, 5, 7, 10],  // dom7 sus4
        "aug":  [0, 4, 8],       // aug 三和弦
        "aug7": [0, 4, 8, 10],   // aug7
        "7b5":  [0, 4, 6, 10],   // dom7 ♭5
    ]
    
    /// 解析和弦名 → 根音 MIDI (C=0) + 和弦类型 + 音程
    private static func parseChord(_ name: String) -> (root: Int, intervals: [Int])? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let cleaned = trimmed.lowercased()
        guard let first = cleaned.first else { return nil }
        
        // 提取根音
        let rootChar = String(first)
        // 处理 C# / Db 等
        var rootStr = rootChar
        var remaining = String(cleaned.dropFirst())
        if remaining.hasPrefix("#") || remaining.hasPrefix("b") {
            rootStr += String(remaining.removeFirst())
        }
        
        guard let rootChromatic = noteToChromatic[rootStr] else { return nil }
        
        // 从原始（未小写）名称截取同长度后缀 — 保留 M7/mMaj 大小写
        let origRemaining = String(trimmed.dropFirst(rootStr.count))
        
        // 匹配和弦类型
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
        
        guard let intervals = chordIntervals[type] else { return nil }
        return (rootChromatic, intervals)
    }
    
    /// 将 BassElement 的相对音高转为 MIDI 数字
    /// - Parameter element: 贝斯元素 (noteType=B/3/5/7/X/R)
    /// - Parameter chordRoot: 和弦根音半音偏移 (C=0)
    /// - Parameter intervals: 和弦音程数组
    /// - Returns: MIDI pitch (或 0 表示休止)
    private static func resolvePitch(
        element: BassElement,
        chordRoot: Int,
        intervals: [Int],
        lastPitch: Int = 36,
        nextChordName: String? = nil
    ) -> UInt8 {
        switch element.noteType {
        case .rest:
            return 0
            
        case .bass:
            // 根音 — 落在 E1-G2 贝斯音域
            return midiInBassRange(chordRoot, element: element)
            
        case .third:
            return midiInBassRange(chordRoot + intervals[1 % intervals.count], element: element)
            
        case .fifth:
            return midiInBassRange(chordRoot + intervals[min(2, intervals.count - 1)], element: element)
            
        case .seventh:
            let seventhDeg = intervals.count >= 4 ? intervals[3] : 10
            return midiInBassRange(chordRoot + seventhDeg, element: element)
            
        case .pitch:
            let target = lastPitch + element.chromaticOffset
            let clamped = max(Int(element.minMidi), min(Int(element.maxMidi), target))
            return UInt8(clamped)
            
        case .approach:
            // 跨小节趋近: 计算下一小节根音 → 取半音方向接近
            if let nextName = nextChordName, let (nextRoot, _) = parseChord(nextName) {
                let currentRootMidi = 24 + chordRoot
                let nextRootMidi = 24 + nextRoot
                let approach = nextRootMidi > currentRootMidi
                    ? nextRootMidi - 1   // 上行 → 取下一根音的下方半音
                    : nextRootMidi + 1   // 下行 → 取下一根音的上方半音
                return UInt8(max(Int(element.minMidi), min(Int(element.maxMidi), approach)))
            }
            // fallback: 无下一和弦 → 取当前根音上方半音
            let fallback = 24 + chordRoot + 1
            return UInt8(max(Int(element.minMidi), min(Int(element.maxMidi), fallback)))
            
        case .repeatPrev:
            return UInt8(lastPitch)
        }
    }
    
    /// 将半音偏移转换到贝斯音域内的 MIDI pitch
    private static func midiInBassRange(_ chromatic: Int, element: BassElement) -> UInt8 {
        // 贝斯基础八度 = 1 (C1=24, E1=28)
        var pitch = 24 + chromatic  // C1 = MIDI 24
        while pitch < element.minMidi { pitch += 12 }
        while pitch > element.maxMidi { pitch -= 12 }
        return UInt8(pitch)
    }
    
    // MARK: - Public API
    
    // MARK: - 动态平铺

    private static func tileElements(_ elements: [BassElement], slotsPerMeasure: Int) -> [BassElement] {
        let L = elements.map { $0.onsetSlots + $0.durationSlots }.max() ?? 480
        if L == 0 { return elements }
        var result: [BassElement] = []
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
    
    /// 从 BassPattern + 和弦列表生成贝斯线
    /// - Parameters:
    ///   - pattern: 贝斯 Pattern (1小节)
    ///   - chordSymbols: 和弦符号数组 (如 ["Cmaj7", "Dm7", "G7", "Cmaj7"])
    ///   - measureCount: 总小节数 (和弦数应与此一致)
    /// - Returns: 贝斯 CompanionNote 数组
    static func generate(
        pattern: BassPattern? = nil,
        style: String? = nil,
        chordSymbols: [String],
        measureCount: Int,
        slotsPerMeasure: Int = 480
    ) -> [CompanionNote] {
        var notes: [CompanionNote] = []
        var lastPitch = 36  // C2
        
        for measure in 0..<measureCount {
            let chordName = measure < chordSymbols.count
                ? chordSymbols[measure] : (chordSymbols.last ?? "C7")
            let (root, intervals) = parseChord(chordName) ?? (0, [0,4,7,10])
            
            let measureOffset = measure * slotsPerMeasure
            let nextChordName = measure + 1 < chordSymbols.count ? chordSymbols[measure + 1] : nil
            
            let basePattern: BassPattern
            if let style = style {
                basePattern = BassPattern.forStyle(style)  // 每小节随机选取
            } else {
                basePattern = pattern!
            }
            
            for var element in Self.tileElements(basePattern.elements, slotsPerMeasure: slotsPerMeasure) {
                element.onsetSlots += measureOffset
                
                let midi = resolvePitch(element: element, chordRoot: root, intervals: intervals, lastPitch: lastPitch, nextChordName: nextChordName)
                
                if element.noteType != .rest {
                    lastPitch = Int(midi)
                    notes.append(CompanionNote(
                        startSlot: element.onsetSlots,
                        midiPitch: midi,
                        durationSlots: element.durationSlots,
                        volume: element.velocity,
                        channel: 2
                    ))
                }
            }
        }
        
        return notes
    }
}
