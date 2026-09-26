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
