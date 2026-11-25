import Foundation

// MARK: 节奏符号 → 类型（复刻 parseNote）
/// 把 "C4"/"L16"/"R2" 等节奏符号解析为 (类型, 时值)
func parseNote(_ symbol: String) -> (type: Int, rhythmValue: Int) {
    let headChar = symbol.first!
    let dur = Duration2.getDuration(String(symbol.dropFirst()))
    let type: Int
    switch headChar {
    case "H": type = NOTE
    case "C": type = CHORD
    case "S": type = SCALE
    case "L": type = COLOR
    case "A": type = APPROACH
    case "X": type = RANDOM
    case "O": type = OUTSIDE
    case "E": type = EXPECTANCY
    case "R": return (REST, dur)
    case "B": type = BASS
    case "G": type = GOAL
    default: type = NOTE
    }
    return (type, dur)
}

// MARK: 音高归类（复刻 checkNote / getNoteTypes）
/// 判断某 MIDI 音在当前和弦下是否为指定类型
func checkNote(pitch: Int, chord: Chord2, type: Int) -> Bool {
    let pc = ((pitch % 12) + 12) % 12
    switch type {
    case NOTE:
        return true
    case BASS:
        return false   // 单小节驱动不涉及
    case CHORD:
        return chord.isChordTone(pc)
    case COLOR:
        return chord.isColorTone(pc)
    default:
        return false
    }
}

/// 枚举 [low, high] 内每个音的类型（CHORD/COLOR/RANDOM）
func getNoteTypes(low: Int, high: Int, chord: Chord2) -> [Int] {
    (low...high).map { pitch -> Int in
        if checkNote(pitch: pitch, chord: chord, type: CHORD) { return CHORD }
        if checkNote(pitch: pitch, chord: chord, type: COLOR) { return COLOR }
        return RANDOM
    }
}
