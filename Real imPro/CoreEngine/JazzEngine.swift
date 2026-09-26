import Foundation

// MARK: - 乐理标签枚举（用于区分和弦音、趋近音等）
enum MusicTheoryTag {
    case chordTone      // 和弦音 (蓝)
    case colorTone      // 色彩音 (绿)
    case approachNote   // 趋近音/经过音 (红)
    case foreignTone    // 外音 (红)
    case unknown        // 未知
}

// MARK: - 🌟 新增：专属的倚音（Grace Note）数据结构
struct GeneratedGraceNote: Identifiable {
    let id = UUID()
    var pitch: String
    var duration: String // 用于决定视觉符尾（如 "8" 画一根尾巴，"16" 画两根）
    var isRest: Bool = false
}

// MARK: - 用于 UI 展示的乐谱数据模型
struct GeneratedNote: Identifiable {
    let id = UUID()
    let pitch: String
    var tag: MusicTheoryTag
    let isRest: Bool
    let duration: String      // 真实时值字符串 (如 "q", "8", "16")
    let isTriplet: Bool       // 是否属于三连音
    
    // 🌟 注入延音线记忆（跨小节切分音专用，设为 var 并赋默认值，保证不影响你旧代码里的调用）
    var isTieStart: Bool = false
    var isTieEnd: Bool = false
    
    // 🌟 核心升级：挂载在这个主力音符“前面”的所有倚音集合
    // 设为 var 并赋默认值 []，保证完全兼容你所有的历史初始化代码，不会引发任何报错！
    var graceNotes: [GeneratedGraceNote] = []
}

struct GeneratedMeasure: Identifiable {
    let id = UUID()
    let chord: String  // 主和弦（兼容旧代码）
    var notes: [GeneratedNote]
    let chordAnnotations: [(chord: String, noteIndex: Int)]  // 和弦标签及对应音符位置
    let sectionName: String?  // 🌟 段落名，如 "A", "B", "C"，nil 表示不是段落开始
    var slotsPerMeasure: Int = 480  // 3/4=360, 4/4=480
}

// MARK: - 爵士乐理生成引擎
class JazzEngine {
    
    private var pendingResolutionTarget: String? = nil
    private var lastMidiNote: Int = 60
    
    // 动态节奏令牌模型
    struct RhythmToken {
        let symbolType: String  // "N", "L", "R"
        let duration: String    // "q", "8", "16"
        let isTriplet: Bool
    }
    
    // 🎵 概率文法树状节奏裂变器
    private func generateDynamicRhythm() -> [RhythmToken] {
        var tokens: [RhythmToken] = []
        
        for _ in 0..<4 {
            let r = Double.random(in: 0...1)
            
            if r < 0.15 {
                tokens.append(createToken(duration: "q", isTriplet: false))
            } else if r < 0.55 {
                tokens.append(createToken(duration: "8", isTriplet: false))
                tokens.append(createToken(duration: "8", isTriplet: false))
            } else if r < 0.80 {
                tokens.append(createToken(duration: "8", isTriplet: true))
                tokens.append(createToken(duration: "8", isTriplet: true))
                tokens.append(createToken(duration: "8", isTriplet: true))
            } else {
                tokens.append(createToken(duration: "16", isTriplet: false))
                tokens.append(createToken(duration: "16", isTriplet: false))
                tokens.append(createToken(duration: "16", isTriplet: false))
                tokens.append(createToken(duration: "16", isTriplet: false))
            }
        }
        return tokens
    }
    
    private func createToken(duration: String, isTriplet: Bool) -> RhythmToken {
        let r = Double.random(in: 0...1)
        var type = "N"
        if r < 0.15 {
            type = "R"
        } else if r < 0.45 {
            type = "L"
        }
        return RhythmToken(symbolType: type, duration: duration, isTriplet: isTriplet)
    }
    
    private func getChromaticLowerApproach(for target: String) -> String {
        let map = ["C":"B", "C#":"C", "Db":"C", "D":"C#", "D#":"D", "Eb":"D", "E":"D#", "F":"E", "F#":"F", "Gb":"F", "G":"F#", "G#":"G", "Ab":"G", "A":"G#", "A#":"A", "Bb":"A", "B":"A#"]
        return map[target] ?? "C"
    }
    
    private func getBaseMidi(for pitch: String) -> Int {
        let map = ["C":0, "C#":1, "Db":1, "D":2, "D#":3, "Eb":3, "E":4, "F":5, "F#":6, "Gb":6, "G":7, "G#":8, "Ab":8, "A":9, "A#":10, "Bb":10, "B":11]
        return map[pitch] ?? 0
    }
    
    private func chooseNextChordTone(from availableTones: [String]) -> String {
        if availableTones.isEmpty { return "C" }
        var bestTone = availableTones[0]
        var minPenalty = 9999
        
        for tone in availableTones {
            let baseVal = getBaseMidi(for: tone)
            let lastVal = lastMidiNote % 12
            let dist = min(abs(baseVal - lastVal), 12 - abs(baseVal - lastVal))
            var currentPenalty = 0
            
            if dist == 0 { currentPenalty += 50 }
            if dist == 3 || dist == 4 || dist == 5 { currentPenalty -= 10 }
            if dist > 5 { currentPenalty += dist * 2 }
            currentPenalty += Int.random(in: 0...2)
            
            if currentPenalty < minPenalty {
                minPenalty = currentPenalty
                bestTone = tone
            }
        }
        lastMidiNote = 60 + getBaseMidi(for: bestTone)
        return bestTone
    }
    
    func generateMeasure(for chord: String) -> GeneratedMeasure {
        let chordDictionary: [String: [String]] = [
            "Dm7": ["D", "F", "A", "C"], "G7": ["G", "B", "D", "F"], "Cmaj7": ["C", "E", "G", "B"],
            "Gm7": ["G", "Bb", "D", "F"], "C7": ["C", "E", "G", "Bb"], "Fmaj7": ["F", "A", "C", "E"],
            "Bbmaj7": ["Bb", "D", "F", "A"], "Em7b5": ["E", "G", "Bb", "D"], "A7": ["A", "C#", "E", "G"]
        ]
        let currentChordTones = chordDictionary[chord] ?? ["C", "E", "G"]
        
        let dynamicRhythm = generateDynamicRhythm()
        var generatedNotes: [GeneratedNote] = []
        
        for token in dynamicRhythm {
            if token.symbolType == "R" {
                generatedNotes.append(GeneratedNote(pitch: "b/4", tag: .unknown, isRest: true, duration: token.duration + "r", isTriplet: token.isTriplet))
                continue
            }
            
            if let requiredTarget = pendingResolutionTarget {
                generatedNotes.append(GeneratedNote(pitch: requiredTarget, tag: .chordTone, isRest: false, duration: token.duration, isTriplet: token.isTriplet))
                lastMidiNote = 60 + getBaseMidi(for: requiredTarget)
                pendingResolutionTarget = nil
                continue
            }
            
            if token.symbolType == "N" {
                let chosenTone = chooseNextChordTone(from: currentChordTones)
                generatedNotes.append(GeneratedNote(pitch: chosenTone, tag: .chordTone, isRest: false, duration: token.duration, isTriplet: token.isTriplet))
                
            } else if token.symbolType == "L" {
                let targetNote = chooseNextChordTone(from: currentChordTones)
                let realApproachPitch = getChromaticLowerApproach(for: targetNote)
                generatedNotes.append(GeneratedNote(pitch: realApproachPitch, tag: .approachNote, isRest: false, duration: token.duration, isTriplet: token.isTriplet))
                pendingResolutionTarget = targetNote
            }
        }
        
        let logStr = dynamicRhythm.map { "\($0.duration)\($0.isTriplet ? "t" : "")" }.joined(separator: "-")
        //dprint("🥁 [引擎日志] 生成小节: \(chord) | 节拍构成: [\(logStr)] | 总音符数: \(generatedNotes.count)")
        
        // 单和弦时，标签在第0个音符位置
        let annotations = [(chord: chord, noteIndex: 0)]
        return GeneratedMeasure(chord: chord, notes: generatedNotes, chordAnnotations: annotations, sectionName: nil)
    }
}

// MARK: - 小节时值归一化扩展
extension Array where Element == GeneratedMeasure {
    /// 溢出截断至 slotsPerMeasure（不对齐补齐——VexFlow 字符串精度不足）
    func normalizeMeasuredSlots() -> [GeneratedMeasure] {
        let needsFix = contains { measure in
            let cap = measure.slotsPerMeasure
            let total = measure.notes.reduce(0) { $0 + Self.slotsFor($1.duration, $1.isTriplet) }
            return total > cap
        }
        guard needsFix else { return self }

        return map { measure in
            let cap = measure.slotsPerMeasure
            let total = measure.notes.reduce(0) { $0 + Self.slotsFor($1.duration, $1.isTriplet) }
            guard total > cap else { return measure }

            var notes = measure.notes
            var remaining = total
            var i = notes.count - 1
            while remaining > cap, i >= 0 {
                let note = notes[i]
                let noteSlots = Self.slotsFor(note.duration, note.isTriplet)
                if noteSlots > (remaining - cap) {
                    let excess = remaining - cap
                    let target = noteSlots - excess
                    let shrunk = Self.shrinkDuration(note.duration, note.isTriplet, target)
                    let shrunkSlots = Self.slotsFor(shrunk, note.isTriplet)
                    notes[i] = GeneratedNote(
                        pitch: note.pitch, tag: note.tag, isRest: note.isRest,
                        duration: shrunk, isTriplet: note.isTriplet,
                        isTieStart: note.isTieStart, isTieEnd: note.isTieEnd,
                        graceNotes: note.graceNotes
                    )
                    remaining -= (noteSlots - shrunkSlots)
                    break
                } else {
                    remaining -= noteSlots; i -= 1
                }
            }
            return GeneratedMeasure(
                chord: measure.chord, notes: notes,
                chordAnnotations: measure.chordAnnotations,
                sectionName: measure.sectionName,
                slotsPerMeasure: measure.slotsPerMeasure
            )
        }
    }

    private static let slotMap: [String: Int] = ["w":480,"h":240,"q":120,"8":60,"16":30,"32":15]

    private static func slotsFor(_ d: String, _ triplet: Bool) -> Int {
        let raw = d.replacingOccurrences(of: "d", with: "").replacingOccurrences(of: "r", with: "")
        let base = slotMap[raw] ?? 60
        let dotted = d.contains("d") ? base / 2 : 0
        return triplet ? (base + dotted) * 2 / 3 : base + dotted
    }

    private static func shrinkDuration(_ d: String, _ t: Bool, _ target: Int) -> String {
        let keys = ["w","h","q","8","16","32"]
        for key in keys { if slotsFor(key, t) <= target { return key } }
        return t ? "32_t3" : "32"
    }
}
