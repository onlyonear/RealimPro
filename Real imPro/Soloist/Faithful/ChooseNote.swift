import Foundation

// MARK: chooseNote（复刻 LickGen.chooseNote 最小路径）
let GOAL_PROB = 0
let MIN_JUMP_UPPER_BOUND = 6

func chooseNote(rng: inout S2RNG, position: Int, low l0: Int, high h0: Int,
                context: ChordContext, type t0: Int, lastPitch: Int,
                minPitch: Int, maxPitch: Int, oldPitch: Int, attempt: Int,
                doNotSwitchOctave: Bool = false) -> Int {
    var type = t0
    var low = l0
    var high = h0

    // V1 goalCheck：即使 GOAL_PROB=0，nextInt(100) 仍无条件消耗一次（与 Java 3089 一致）
    if rng.nextInt("V1:goalCheck", 100) < GOAL_PROB {
        type = GOAL
    }

    // low==high 约束放宽
    if low == high {
        if low != oldPitch + 1 { low -= 1 }
        if high != oldPitch - 1 { high += 1 }
    }
    // 大跳约束放宽（最小路径通常不触发）
    if low - lastPitch >= MIN_JUMP_UPPER_BOUND { low -= MIN_JUMP_UPPER_BOUND / 2 }
    if high - lastPitch <= -MIN_JUMP_UPPER_BOUND { high += MIN_JUMP_UPPER_BOUND / 2 }
    // 边界修正
    if low > high && low > lastPitch { low = high }
    if high < low && high < lastPitch { high = low }
    // NOTE 等价 SCALE
    if type == NOTE { type = SCALE }

    let chord = context.chordAt(position: position)

    // 区间枚举 + 类型统计；CHORD 找不到时最多扩展 3 次
    // 口径对齐 Java：numTypes 在循环外初始化、循环内不重置，跨多次枚举"累加"
    var noteTypes: [Int] = []
    var numTypes = [0,0,0,0]
    var j = 0
    while j == 0 || (type == CHORD && j < 3 && numTypes[0] == 0) {
        noteTypes = getNoteTypes(low: low, high: high, chord: chord)
        for nt in noteTypes {
            switch nt {
            case CHORD: numTypes[0] += 1; numTypes[3] += 1
            case COLOR: numTypes[1] += 1; numTypes[3] += 1
            default: numTypes[2] += 1   // RANDOM
            }
        }
        if type == CHORD && numTypes[0] == 0 {
            if low != oldPitch + 1 { low -= 1 }
            if high != oldPitch - 1 { high += 1 }
        }
        j += 1
    }

    return NoteChooser2().getNote(rng: &rng, minPitch: minPitch, maxPitch: maxPitch,
                                  low: low, high: high, type: type,
                                  numTypes: numTypes, noteTypes: noteTypes, attempt: attempt,
                                  doNotSwitchOctave: doNotSwitchOctave)
}
