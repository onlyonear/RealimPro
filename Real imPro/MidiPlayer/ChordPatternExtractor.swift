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
        "maj7sus": [5, 7, 11], // 【新增】4, 5, 大七（大七挂四 maj7sus4，根音留给贝斯）
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
        // 【新增·最优先窄分支】大七挂四：sus + 大七标志(maj/△/大写M7) → maj7sus；其余走既有链，行为不变
        if remaining.contains("sus") &&
            (origRemaining.lowercased().contains("maj") || origRemaining.contains("△") || origRemaining.contains("M7")) {
            type = "maj7sus"
        } else if origRemaining.lowercased().contains("mmaj") || origRemaining.lowercased().contains("mm7") {
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

    /// 钢琴伴奏整体力度增益（2026-09-05：钢琴偶尔会盖过/抢萨克斯 Solo，整体轻压一档≈-10%）。
    /// 只作用于钢琴伴奏(channel 1)，不影响贝斯/鼓/Solo。觉得压太多改回 1.0、想更轻改 0.85 即可。
    private static let pianoMasterGain: Double = 0.9
    private static func scalePianoVelocity(_ v: UInt8) -> UInt8 {
        UInt8(max(1, min(127, (Double(v) * pianoMasterGain).rounded())))
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
    
    // MARK: - Full 规则 voicing（对齐原版，阶段2接入）

    /// 各风格钢琴音域，与 bestInversion(Simple) 的取值保持一致
    private static func voicingRange(for style: String) -> (low: Int, high: Int) {
        switch style.lowercased() {
        case "swing":  return (Self.swingMinMidi,  Self.defaultMaxMidi)
        case "ballad": return (Self.balladMinMidi, Self.balladMaxMidi)
        case "afro":   return (Self.defaultMinMidi, Self.afroMaxMidi)
        default:       return (Self.defaultMinMidi, Self.defaultMaxMidi)
        }
    }

    /// Full 路径：和弦名 -> 完整规则 voicing 绝对 MIDI；解析/无候选时返回 nil（由调用方回退 Simple）
    private static func fullVoicingMidis(_ chordName: String, engine: FullVoicingEngine) -> [UInt8]? {
        guard let resolved = ChordSymbolMapper.resolve(chordName),
              let notes = engine.voicing(forForm: resolved.canonical, rootRise: resolved.rise),
              !notes.isEmpty else { return nil }
        return notes.sorted().map { UInt8($0) }
    }

    /// 根据和弦列表生成钢琴伴奏音符。
    /// 2026-09-05：swing / afro 走「跨段时间线」(长句 residual 切割 + 短句拼接 + push 抢拍)；
    /// 其余 5 种风格(ballad/bossa/waltz/latin/shuffle)走「逐段独立抽卡」。
    /// 时间线单位是「和弦段」(ChordSegment)：一小节一个和弦=一段，一小节多个和弦=多段，故小节内换和弦也能跟上。
    static func generate(
        pattern _unused: ChordPattern? = nil,
        segments: [ChordSegment],
        slotsPerMeasure: Int = 480,
        style: String = "swing"
    ) -> [CompanionNote] {
        let styleKey = style.lowercased()
        let engine = Self.makeVoicingEngine(style)
        if styleKey == "swing" || styleKey == "afro" {
            return generateTimeline(segments: segments, style: styleKey, engine: engine)
        } else {
            return generateLegacy(segments: segments, style: style,
                                  styleKey: styleKey, engine: engine)
        }
    }

    // MARK: 钢琴和声档位引擎（默认 Full；Simple 封存，可经 UserDefaults 复活）
    /// 2026-09-05 听感确认后【默认 Full】(对齐原版完整规则 voicing)。
    /// 临时切回 Simple(固定 3+7+9 shell)：UserDefaults 写 "pianoVoicingModeRaw"="simple"，无需改代码。
    private static func makeVoicingEngine(_ style: String) -> FullVoicingEngine? {
        let modeRaw = UserDefaults.standard.string(forKey: "pianoVoicingModeRaw") ?? PianoVoicingMode.full.rawValue
        guard modeRaw != PianoVoicingMode.simple.rawValue else { return nil }
        let e = FullVoicingEngine()
        let r = Self.voicingRange(for: style)
        e.lowMidi = r.low
        e.highMidi = r.high
        e.requestType = .open
        return e
    }

    /// 按风格抽一个钢琴节奏句型
    private static func drawPattern(_ styleKey: String) -> ChordPattern {
        switch styleKey {
        case "ballad":                         return ChordPattern.ballad()
        case "bossa":                          return ChordPattern.bossa()
        case "waltz":                          return ChordPattern.waltz()
        case "latin":                          return ChordPattern.latin()
        case "shuffle", "blues":               return ChordPattern.blues()
        case "afro":                           return ChordPattern.afro()
        default:                               return ChordPattern.basicSwing()
        }
    }

    /// 单个击弦点 → 一组 MIDI（Full 优先、回退 Simple，保证不哑火），并做人性化时间/力度抖动
    private static func emitVoicing(
        chordName: String, style: String, engine: FullVoicingEngine?,
        absStart: Int, duration: Int, baseVelocity: UInt8, into notes: inout [CompanionNote]
    ) {
        let simpleParsed = parseChord(chordName)
        let midis: [UInt8]
        if let engine, let full = Self.fullVoicingMidis(chordName, engine: engine) {
            midis = full
        } else if let (root, intervals) = simpleParsed {
            midis = bestInversion(root: root, intervals: intervals, style: style)
        } else {
            return
        }
        let vel = scalePianoVelocity(jitterVelocity(baseVelocity))
        for midi in midis {
            // Bug2: 每个 voicing 音独立抖动, 模拟手指滚奏
            notes.append(CompanionNote(
                startSlot: jitterStartSlot(absStart),
                midiPitch: midi,
                durationSlots: duration,
                volume: vel,
                channel: 1
            ))
        }
    }

    // MARK: 旧路径：逐段独立抽卡（其余 5 种风格使用）。单和弦小节=一段，等价旧的逐小节行为。
    private static func generateLegacy(
        segments: [ChordSegment],
        style: String, styleKey: String, engine: FullVoicingEngine?
    ) -> [CompanionNote] {
        var notes: [CompanionNote] = []
        for seg in segments {
            let pattern = drawPattern(styleKey)
            let chordName = seg.chord

            // Simple 路径预解析；Full 路径即使 Simple 解析失败也不整段跳过(Mapper 覆盖更广)
            let simpleParsed = parseChord(chordName)
            if engine == nil, simpleParsed == nil { continue }

            // 平铺上限 = 本段时长（小节内多和弦时，每段只在自己的拍数内铺）
            for element in Self.tileElements(pattern.elements, slotsPerMeasure: seg.durationSlots, style: style) {
                guard element.noteType == .chord else { continue }
                emitVoicing(chordName: chordName, style: style, engine: engine,
                            absStart: seg.startSlot + element.onsetSlots,
                            duration: element.durationSlots,
                            baseVelocity: element.velocity, into: &notes)
            }
        }
        notes.sort { $0.startSlot < $1.startSlot }
        return notes
    }

    // MARK: 新路径：跨段时间线（对齐 Java Style.getChordPattern + makeChordline 的 while 循环）
    /// - 长句型(>本段剩余)按窗口 [origin, origin+segLen) 切分，剩余存 residual，跨到后续段/小节；
    /// - 短句型(<剩余)整句用完后 while 再抽一句拼满（african 的半小节句型靠此填满）；
    /// - push 只作用于每段第一个「新抽(origin==0)」片段，整句提前；全曲第一个负起点钳到 0。
    /// - 片段即使因 push 落到上一段位置，仍配「当前段」的和弦（对齐 Java currentChord 抢入）。
    private static func generateTimeline(
        segments: [ChordSegment],
        style: String, engine: FullVoicingEngine?
    ) -> [CompanionNote] {
        var notes: [CompanionNote] = []
        var residual: ChordPattern? = nil
        var residualOrigin = 0

        for seg in segments {
            var remaining = seg.durationSlots
            var segAbsBase = seg.startSlot
            var firstOfSeg = true

            while remaining > 0 {
                let pat: ChordPattern
                let origin: Int
                if let r = residual {
                    pat = r; origin = residualOrigin; residual = nil
                } else {
                    pat = drawPattern(style); origin = 0
                }

                let patRemain = pat.durationSlots - origin
                let segLen = min(max(patRemain, 0), remaining)
                guard segLen > 0 else { residual = nil; break }  // 防御：异常空片段不死循环

                let push = (firstOfSeg && origin == 0) ? pat.pushSlots : 0
                let winStart = origin
                let winEnd = origin + segLen

                for el in pat.elements where el.noteType == .chord {
                    let s = max(el.onsetSlots, winStart)
                    let e = min(el.onsetSlots + el.durationSlots, winEnd)
                    guard e > s else { continue }
                    var absOn = segAbsBase + (s - winStart) - push
                    if absOn < 0 { absOn = 0 }   // 全曲开头抢拍不得早于 0（对齐 Java time<0 钳 0）
                    emitVoicing(chordName: seg.chord, style: style, engine: engine,
                                absStart: absOn, duration: e - s,
                                baseVelocity: el.velocity, into: &notes)
                }

                remaining -= segLen
                segAbsBase += segLen
                firstOfSeg = false
                let consumedEnd = origin + segLen
                if consumedEnd < pat.durationSlots {
                    residual = pat
                    residualOrigin = consumedEnd
                }
            }
        }
        notes.sort { $0.startSlot < $1.startSlot }
        return notes
    }
}
