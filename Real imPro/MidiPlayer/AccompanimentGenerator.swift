import Foundation

// MARK: - 智能伴奏生成引擎 (Pattern驱动架构, 多风格路由)

class AccompanimentGenerator {
    static let shared = AccompanimentGenerator()
    
    func generate(style: String,
                  measureCount: Int,
                  chordSymbols: [String] = [],
                  slotsPerMeasure: Int = 480) -> BackingTrackData {
        var trackData = BackingTrackData()
        let chords = chordSymbols.isEmpty
            ? Array(repeating: "Cmaj7", count: measureCount)
            : chordSymbols
        
        switch style.lowercased() {
        case "ballad":
            let drumPattern  = DrumPattern.ballad()
            trackData.drumNotes = DrumPatternExtractor.generate(pattern: drumPattern, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure)
            trackData.bassNotes = BassPatternExtractor.generate(style: "ballad", chordSymbols: chords, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure)
            trackData.pianoNotes = ChordPatternExtractor.generate(chordSymbols: chords, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure, style: style)
            
        case "shuffle":
            let drumPattern  = DrumPattern.blues()
            trackData.drumNotes = DrumPatternExtractor.generate(pattern: drumPattern, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure)
            trackData.bassNotes = BassPatternExtractor.generate(style: "shuffle", chordSymbols: chords, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure)
            trackData.pianoNotes = ChordPatternExtractor.generate(chordSymbols: chords, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure, style: style)
            
        case "bossa":
            let drumPattern  = DrumPattern.bossa()
            trackData.drumNotes = DrumPatternExtractor.generate(pattern: drumPattern, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure)
            trackData.bassNotes = BassPatternExtractor.generate(style: "bossa", chordSymbols: chords, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure)
            trackData.pianoNotes = ChordPatternExtractor.generate(chordSymbols: chords, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure, style: style)
            
        case "waltz":
            let drumPattern  = DrumPattern.waltz()
            trackData.drumNotes = DrumPatternExtractor.generate(pattern: drumPattern, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure)
            trackData.bassNotes = BassPatternExtractor.generate(style: "waltz", chordSymbols: chords, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure)
            trackData.pianoNotes = ChordPatternExtractor.generate(chordSymbols: chords, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure, style: style)
            
        case "latin":
            let drumPattern  = DrumPattern.latin()
            trackData.drumNotes = DrumPatternExtractor.generate(pattern: drumPattern, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure)
            trackData.bassNotes = BassPatternExtractor.generate(style: "latin", chordSymbols: chords, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure)
            trackData.pianoNotes = ChordPatternExtractor.generate(chordSymbols: chords, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure, style: style)
            
        case "afro":
            let drumPattern  = DrumPattern.afro()
            trackData.drumNotes = DrumPatternExtractor.generate(pattern: drumPattern, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure)
            trackData.bassNotes = BassPatternExtractor.generate(style: "afro", chordSymbols: chords, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure)
            trackData.pianoNotes = ChordPatternExtractor.generate(chordSymbols: chords, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure, style: style)
            
        default:
            let drumPattern  = DrumPattern.basicSwing()
            let bassPattern  = BassPattern.basicSwing()
            trackData.drumNotes = DrumPatternExtractor.generate(pattern: drumPattern, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure)
            trackData.bassNotes = BassPatternExtractor.generate(pattern: bassPattern, chordSymbols: chords, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure)
            trackData.pianoNotes = ChordPatternExtractor.generate(chordSymbols: chords, measureCount: measureCount, slotsPerMeasure: slotsPerMeasure, style: style)
        }
        
        return trackData
    }
    func generateSimpleSwing(measureCount: Int,
                             chordSymbols: [String] = [],
                             slotsPerMeasure: Int = 480) -> BackingTrackData {
        return generate(style: "swing", measureCount: measureCount, chordSymbols: chordSymbols, slotsPerMeasure: slotsPerMeasure)
    }
}
