import Foundation

// MARK: - 智能伴奏生成引擎 (Pattern驱动架构, 多风格路由)

class AccompanimentGenerator {
    static let shared = AccompanimentGenerator()
    
    /// - Parameter chordSegments: 和弦段序列（支持一小节内多个和弦）；nil 时按「每小节一个和弦」兜底（等价旧行为）
    func generate(style: String,
                  measureCount: Int,
                  chordSymbols: [String] = [],
                  chordSegments: [ChordSegment]? = nil,
                  slotsPerMeasure: Int = 480) -> BackingTrackData {
        var trackData = BackingTrackData()
        let chords = chordSymbols.isEmpty
            ? Array(repeating: "Cmaj7", count: measureCount)
            : chordSymbols

        // 统一成「和弦段」时间线：外部传了就用（含小节内多和声）；否则按每小节一段兜底
        let segments: [ChordSegment]
        if let cs = chordSegments, !cs.isEmpty {
            segments = cs
        } else {
            segments = (0..<measureCount).map { i in
                ChordSegment(chord: i < chords.count ? chords[i] : (chords.last ?? "Cmaj7"),
                             startSlot: i * slotsPerMeasure,
                             durationSlots: slotsPerMeasure)
            }
        }
        
        // [P3-a 新增] Java .sty 伴奏型（styleId 形如 "sty:swing"）：交通用 StyleEngine 解析 bundle 内 .sty 并展开三轨，命中即返回。
        if StyleEngine.shared.isStyStyle(style) {
            return StyleEngine.shared.render(styleId: style,
                                             measureCount: measureCount,
                                             chordSegments: segments,
                                             slotsPerMeasure: slotsPerMeasure)
        }

        // [P3-a 说明] 下方手写风格 switch 原样保留：.sty 已在上方提前 return；选 "Swing"/"Ballad"/... 仍走原手写路径，行为不变。
        switch style.lowercased() {
        case "ballad":
            let drumPattern  = DrumPattern.ballad()
            trackData.drumNotes = DrumPatternExtractor.generate(pattern: drumPattern, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure)
            trackData.bassNotes = BassPatternExtractor.generate(style: "ballad", segments: segments, slotsPerMeasure: slotsPerMeasure)
            trackData.pianoNotes = ChordPatternExtractor.generate(segments: segments, slotsPerMeasure: slotsPerMeasure, style: style)
            
        case "shuffle":
            let drumPattern  = DrumPattern.blues()
            trackData.drumNotes = DrumPatternExtractor.generate(pattern: drumPattern, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure)
            trackData.bassNotes = BassPatternExtractor.generate(style: "shuffle", segments: segments, slotsPerMeasure: slotsPerMeasure)
            trackData.pianoNotes = ChordPatternExtractor.generate(segments: segments, slotsPerMeasure: slotsPerMeasure, style: style)
            
        case "bossa":
            let drumPattern  = DrumPattern.bossa()
            trackData.drumNotes = DrumPatternExtractor.generate(pattern: drumPattern, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure)
            trackData.bassNotes = BassPatternExtractor.generate(style: "bossa", segments: segments, slotsPerMeasure: slotsPerMeasure)
            trackData.pianoNotes = ChordPatternExtractor.generate(segments: segments, slotsPerMeasure: slotsPerMeasure, style: style)
            
        case "waltz":
            let drumPattern  = DrumPattern.waltz()
            trackData.drumNotes = DrumPatternExtractor.generate(pattern: drumPattern, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure)
            trackData.bassNotes = BassPatternExtractor.generate(style: "waltz", segments: segments, slotsPerMeasure: slotsPerMeasure)
            trackData.pianoNotes = ChordPatternExtractor.generate(segments: segments, slotsPerMeasure: slotsPerMeasure, style: style)
            
        case "latin":
            let drumPattern  = DrumPattern.latin()
            trackData.drumNotes = DrumPatternExtractor.generate(pattern: drumPattern, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure)
            trackData.bassNotes = BassPatternExtractor.generate(style: "latin", segments: segments, slotsPerMeasure: slotsPerMeasure)
            trackData.pianoNotes = ChordPatternExtractor.generate(segments: segments, slotsPerMeasure: slotsPerMeasure, style: style)
            
        case "afro":
            let drumPattern  = DrumPattern.afro()
            trackData.drumNotes = DrumPatternExtractor.generate(pattern: drumPattern, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure)
            trackData.bassNotes = BassPatternExtractor.generate(style: "afro", segments: segments, slotsPerMeasure: slotsPerMeasure)
            trackData.pianoNotes = ChordPatternExtractor.generate(segments: segments, slotsPerMeasure: slotsPerMeasure, style: style)
            
        default:
            let drumPattern  = DrumPattern.basicSwing()
            let bassPattern  = BassPattern.basicSwing()
            trackData.drumNotes = DrumPatternExtractor.generate(pattern: drumPattern, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure)
            trackData.bassNotes = BassPatternExtractor.generate(pattern: bassPattern, segments: segments, slotsPerMeasure: slotsPerMeasure)
            trackData.pianoNotes = ChordPatternExtractor.generate(segments: segments, slotsPerMeasure: slotsPerMeasure, style: style)
        }
        
        return trackData
    }
    func generateSimpleSwing(measureCount: Int,
                             chordSymbols: [String] = [],
                             chordSegments: [ChordSegment]? = nil,
                             slotsPerMeasure: Int = 480) -> BackingTrackData {
        return generate(style: "swing", measureCount: measureCount, chordSymbols: chordSymbols, chordSegments: chordSegments, slotsPerMeasure: slotsPerMeasure)
    }
}
