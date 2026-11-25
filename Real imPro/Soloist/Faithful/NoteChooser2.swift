import Foundation

// MARK: NoteChooser（复刻 HarnessNoteChooser）
// 每行：[查找类型, 有chord, 有color, 有random, 概率chord, 概率color, 概率random, 概率scale]
private let PROB_TABLE: [[Int]] = [
    [0,1,1,1, 100,0,0,0],
    [0,1,1,0, 100,0,0,0],
    [0,1,0,1, 100,0,0,0],
    [0,1,0,0, 100,0,0,0],
    [0,0,1,1, 0,100,0,0],
    [0,0,1,0, 0,100,0,0],
    [0,0,0,1, 0,0,100,0],
    [1,1,1,1, 0,100,0,0],
    [1,1,1,0, 10,90,0,0],
    [1,1,0,1, 85,0,15,0],
    [1,1,0,0, 100,0,0,0],
    [1,0,1,1, 0,100,0,0],
    [1,0,1,0, 0,100,0,0],
    [1,0,0,1, 0,0,100,0],
    [3,1,1,1, 0,0,0,100],
    [3,1,1,0, 0,0,0,100],
    [3,1,0,1, 0,0,0,100],
    [3,1,0,0, 0,0,0,100],
    [3,0,1,1, 0,0,0,100],
    [3,0,1,0, 0,0,0,100],
    [3,0,0,1, 0,0,100,0],
    [2,1,1,1, 50,25,25,0],
    [2,1,1,0, 80,20,0,0],
    [2,1,0,1, 50,0,50,0],
    [2,1,0,0, 100,0,0,0],
    [2,0,1,1, 0,50,50,0],
    [2,0,1,0, 0,100,0,0],
    [2,0,0,1, 0,0,100,0],
]
private let TYPE_MAP = [CHORD, COLOR, RANDOM, SCALE]

struct NoteChooser2 {
    /// 复刻 getNote，返回最终音高
    func getNote(rng: inout S2RNG, minPitch: Int, maxPitch: Int,
                 low: Int, high: Int, type: Int,
                 numTypes: [Int], noteTypes: [Int], attempt: Int,
                 doNotSwitchOctave: Bool = false) -> Int {
        let lookupType: Int
        switch type {
        case CHORD: lookupType = 0
        case COLOR: lookupType = 1
        case RANDOM: lookupType = 2
        default: lookupType = 3   // SCALE
        }
        let haveChord = numTypes[0] != 0 ? 1 : 0
        let haveColor = numTypes[1] != 0 ? 1 : 0
        let haveRandom = numTypes[2] != 0 ? 1 : 0
        let identifier = [lookupType, haveChord, haveColor, haveRandom]

        // 查表
        var probs = [0,0,0,0]
        for row in PROB_TABLE where Array(row.prefix(4)) == identifier {
            probs = Array(row.suffix(4))
        }

        // V9：选新类型
        var randNum = rng.nextInt("V9:noteType", 100) + 1
        var newType = 0
        for i in 0..<probs.count {
            randNum -= probs[i]
            if randNum <= 0 { newType = i; break }
        }

        // V10：选具体音高
        randNum = rng.nextInt("V10:notePitch", numTypes[newType]) + 1
        var pitchDiff = 0
        for i in 0..<noteTypes.count {
            let matches = noteTypes[i] == TYPE_MAP[newType]
                       || (newType == 3 && (noteTypes[i] == CHORD || noteTypes[i] == COLOR))
            if matches { randNum -= 1 }
            if randNum <= 0 { pitchDiff = i; break }
        }
        var finalPitch = low + pitchDiff
        // 最后一个 attempt 的八度兜底：仅当 doNotSwitchOctave==false 时，超界音强制升降八度
        // （buildSolo/generateSoloFromOutline 路径 doNotSwitchOctave=true，兜底不触发）
        if attempt >= MELODY_GEN_LIMIT - 1 && !doNotSwitchOctave {
            while finalPitch > maxPitch { finalPitch -= 12 }
            while finalPitch < minPitch { finalPitch += 12 }
        }
        return finalPitch
    }
}
