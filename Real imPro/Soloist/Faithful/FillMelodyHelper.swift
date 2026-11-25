import Foundation

// MARK: 发声状态（复刻 LickGen 实例中与发声相关的可变字段）
final class LickGenState {
    var rng: S2RNG
    var position = 0
    var oldPitch = 0
    var prevSlot: Int?            // result.slots 中前一个音符的绝对 slot
    var result = MelodyPart2()
    let minPitch: Int
    let maxPitch: Int
    let avoidRepeats: Bool
    var doNotSwitchOctave: Bool

    init(rng: S2RNG, minPitch: Int, maxPitch: Int, avoidRepeats: Bool, doNotSwitchOctave: Bool = false) {
        self.rng = rng; self.minPitch = minPitch; self.maxPitch = maxPitch
        self.avoidRepeats = avoidRepeats
        self.doNotSwitchOctave = doNotSwitchOctave
    }

    // getRandomNote：probs 为空（harness 同口径），但仍无条件消耗一次 nextDouble（V5），
    // 遍历空 availProbs 后返回中心 pitch（与 Java 3586-3598 一致）
    func getRandomNote() -> Int {
        _ = rng.nextDouble("V5:getRandomNote")
        return (maxPitch + minPitch) / 2
    }

    // MARK: addNote（复刻休止合并/重复合并）
    func addNote(_ note: Note2) {
        let slotsInserted = note.rhythmValue
        position += slotsInserted
        if note.isRest {
            if let ps = prevSlot, result.slots[ps]?.isRest == true {
                // 与前休止合并：拉长前音符，不新建单元
                result.mergeRhythm(atSlot: ps, extra: slotsInserted)
            } else {
                prevSlot = result.addNote(note)
            }
        } else {
            if avoidRepeats, let ps = prevSlot, let pn = result.slots[ps],
               !pn.isRest, pn.pitch == note.pitch {
                // 重复音合并
                result.mergeRhythm(atSlot: ps, extra: slotsInserted)
            } else {
                prevSlot = result.addNote(note)
            }
        }
    }
}

// MARK: fillMelodyHelper（slope 主干；支持 REST 与 default 选音）
/// 对单个 section（含一个或多个 (slope ...) 结构）发声
func fillMelodyHelper(state: LickGenState, section: [SExpr], context: ChordContext,
                      minPitch: Int, maxPitch: Int, attempt: Int) {
    // 首音：oldPitch==0 时取随机起始
    if state.oldPitch == 0 {
        state.oldPitch = state.getRandomNote()
    }
    // 遍历 section 中每个结构（X 音阶度数或 slope 结构）
    for structure in section {
        // X 结构：确定性音阶度数，不消耗随机源
        if isScaleDegree(structure) {
            let rel = makeRelativeNote(structure, chord: context.chordAt(position: state.position))
            state.addNote(Note2(pitch: rel.pitch, rhythmValue: rel.rhythmValue, isRest: false))
            state.oldPitch = rel.pitch
            continue
        }
        guard let items = structure.items, let first = items.first?.sym, first == "slope" else {
            continue
        }
        var body = Array(items.dropFirst())
        guard let lowerLimit = body.first?.num,
              let upperLimit = body.dropFirst().first?.num else { continue }
        body = Array(body.dropFirst(2))

        var pitch = state.oldPitch
        var si = 0
        while si < body.count {
            guard let symbol = body[si].sym else { si += 1; continue }
            let parsed = parseNote(symbol)
            let type = parsed.type
            let rv = parsed.rhythmValue
            if type == REST {
                state.addNote(.makeRest(rv))
                si += 1
            } else if type == APPROACH {
                if si + 1 < body.count {
                    // 后面有 target：消耗 target 并为其选音
                    si += 1
                    guard let targetSymbol = body[si].sym else { si += 1; continue }
                    let targetParsed = parseNote(targetSymbol)
                    let nextType = targetParsed.type
                    let targetRv = targetParsed.rhythmValue
                    let nextPitch = chooseNote(rng: &state.rng,
                                              position: state.position + rv,
                                              low: state.oldPitch + lowerLimit,
                                              high: state.oldPitch + upperLimit,
                                              context: context, type: nextType,
                                              lastPitch: state.oldPitch,
                                              minPitch: minPitch, maxPitch: maxPitch,
                                              oldPitch: state.oldPitch, attempt: attempt,
                                              doNotSwitchOctave: state.doNotSwitchOctave)
                    // 推导 approach 音高（与 Java 2070-2103 一致）
                    var approachPitch: Int
                    if nextPitch + 1 == state.oldPitch {
                        approachPitch = nextPitch - 1
                    } else if nextPitch - 1 == state.oldPitch {
                        approachPitch = nextPitch + 1
                    } else if lowerLimit == 0 || upperLimit == 0 {
                        approachPitch = nextPitch
                        if upperLimit > 0 { approachPitch = nextPitch - 1 }
                        if lowerLimit < 0 { approachPitch = nextPitch + 1 }
                    } else if lowerLimit > 0 {
                        approachPitch = nextPitch - 1
                    } else if upperLimit < 0 {
                        approachPitch = nextPitch + 1
                    } else {
                        approachPitch = nextPitch - 1
                    }
                    state.addNote(Note2(pitch: approachPitch, rhythmValue: rv, isRest: false))
                    state.addNote(Note2(pitch: nextPitch, rhythmValue: targetRv, isRest: false))
                    pitch = nextPitch
                } else {
                    // 末尾 approach：用 SCALE 选音
                    pitch = chooseNote(rng: &state.rng, position: state.position,
                                       low: state.oldPitch + lowerLimit,
                                       high: state.oldPitch + upperLimit,
                                       context: context, type: SCALE,
                                       lastPitch: state.oldPitch,
                                       minPitch: minPitch, maxPitch: maxPitch,
                                       oldPitch: state.oldPitch, attempt: attempt,
                                       doNotSwitchOctave: state.doNotSwitchOctave)
                    state.addNote(Note2(pitch: pitch, rhythmValue: rv, isRest: false))
                }
                state.oldPitch = pitch
                si += 1
            } else {
                let chosen = chooseNote(rng: &state.rng, position: state.position,
                                       low: state.oldPitch + lowerLimit,
                                       high: state.oldPitch + upperLimit,
                                       context: context, type: type,
                                       lastPitch: state.oldPitch,
                                       minPitch: minPitch, maxPitch: maxPitch,
                                       oldPitch: state.oldPitch, attempt: attempt,
                                       doNotSwitchOctave: state.doNotSwitchOctave)
                pitch = chosen
                state.addNote(Note2(pitch: chosen, rhythmValue: rv, isRest: false))
                state.oldPitch = pitch
                si += 1
            }
        }
    }
}
