import Foundation

func getRootPC(_ name: String) -> Int {
    let chars = Array(name)
    guard !chars.isEmpty else { return 0 }
    var rootStr = String(chars[0]).uppercased()
    if chars.count > 1 && (chars[1] == "#" || chars[1] == "b") { rootStr.append(chars[1]) }
    let pcMap: [String: Int] = ["C": 0, "C#": 1, "Db": 1, "D": 2, "Eb": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "Ab": 8, "A": 9, "Bb": 10, "B": 11]
    return pcMap[rootStr] ?? 0
}

enum ChordQuality {
    case major7, minor7, dominant7, halfDiminished, diminished7, augmented7, minorMajor7, alt, sus

    init(chordName: String) {
        let name = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.contains("dim7") || name.contains("o7") {
            self = .diminished7
        } else if name.contains("m7b5") || name.contains("ø") {
            self = .halfDiminished
        } else if name.contains("mMaj") {
            self = .minorMajor7
        } else if name.contains("maj") || name.contains("M7") || name.contains("▲") {
            self = .major7
        } else if name.contains("m") {
            self = .minor7
        } else if name.contains("aug") || name.contains("+") {
            self = .augmented7
        } else if name.contains("alt") {
            self = .alt
        } else if name.contains("dim") {
            self = .diminished7
        } else if name.contains("sus") {
            self = .sus
        } else {
            self = .dominant7
        }
    }

    var chordIntervals: [Int] {
        switch self {
        case .major7:        return [0, 4, 7, 11]
        case .minor7:        return [0, 3, 7, 10]
        case .dominant7:     return [0, 4, 7, 10]
        case .halfDiminished:return [0, 3, 6, 10]
        case .diminished7:   return [0, 3, 6, 9]
        case .augmented7:    return [0, 4, 8, 10]
        case .minorMajor7:   return [0, 3, 7, 11]
        case .alt:           return [0, 4, 6, 8, 10]
        case .sus:           return [0, 5, 7]
        }
    }
}

func getChordTones(chordName: String, minPitch: Int, maxPitch: Int) -> [Int] {
    let cleanName = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
    let rootPC = getRootPC(cleanName)
    print("根音PC: \(rootPC) (Eb=3, E=4)")
    let quality = ChordQuality(chordName: cleanName)
    print("和弦类型: \(quality)")
    let intervals = quality.chordIntervals
    print("和弦音程: \(intervals)")

    var validPitches: [Int] = []

    for interval in intervals {
        let targetPC = (rootPC + interval) % 12
        for octave in [48, 60, 72] {
            let pitch = targetPC + octave
            if pitch >= minPitch && pitch <= maxPitch {
                validPitches.append(pitch)
            }
        }
    }

    return validPitches.sorted()
}

// 测试Ebdim7
let chordName = "Ebdim7"
let tones = getChordTones(chordName: chordName, minPitch: 48, maxPitch: 84)
print("和弦音MIDI列表: \(tones)")
let names = tones.map { m -> String in
    let pc = m % 12
    let oct = m / 12 - 1
    let nn = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
    return "\(nn[pc])\(oct)"
}
print("和弦音名: \(names)")
print("E4(MIDI64)是否在和弦音中: \(tones.contains(64))")
