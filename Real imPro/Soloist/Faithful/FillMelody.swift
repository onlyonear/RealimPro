import Foundation

let MELODY_GEN_LIMIT = 15
let SLOTS_PER_MEASURE = 480

// MARK: 节奏重组（复刻 fillMelody 前半）
/// 把顶层结构聚合成 section：slope/triadic/X 整体保留，裸符号摊平。
func reorganize(_ top: [SExpr]) -> [[SExpr]] {
    var section: [SExpr] = []
    for element in top {
        if let items = element.items, let head = items.first?.sym,
           head == "slope" || head == "triadic" || head == "X" {
            section.append(element)
        } else if let items = element.items {
            section.append(contentsOf: items)   // 非结构列表：摊平
        } else {
            section.append(element)             // 裸符号
        }
    }
    return [section]
}

// MARK: fillPartOfMelody（重试到音域合规）
func fillPartOfMelody(rng: inout S2RNG, section: [SExpr], context: ChordContext,
                      minPitch: Int, maxPitch: Int, avoidRepeats: Bool,
                      startPosition: Int = 0, startOldPitch: Int = 0) -> MelodyPart2 {
    var last = MelodyPart2()
    for attempt in 0..<MELODY_GEN_LIMIT {
        let state = LickGenState(rng: rng, minPitch: minPitch, maxPitch: maxPitch,
                                 avoidRepeats: avoidRepeats)
        state.position = startPosition
        state.oldPitch = startOldPitch
        fillMelodyHelper(state: state, section: section, context: context,
                         minPitch: minPitch, maxPitch: maxPitch, attempt: attempt)
        last = state.result
        rng = state.rng
        if last.lowest >= minPitch - 1 && last.highest <= maxPitch + 1 {
            return last
        }
    }
    return last
}

// MARK: fillMelody（单小节入口）
func fillMelody(text: String, chordName: String, seed: Int64,
                minPitch: Int = 54, maxPitch: Int = 84,
                initOldPitch: Int = 0) throws -> (MelodyPart2, [String]) {
    let top = SExprParser.parse(text)
    let sections = reorganize(top)
    let context: ChordContext
    if chordName.contains(":") {
        var parts: [(name: String, duration: Int)] = []
        for piece in chordName.split(separator: ",") {
            let nv = piece.split(separator: ":")
            parts.append((String(nv[0]).trimmingCharacters(in: .whitespaces),
                          Int(String(nv[1]).trimmingCharacters(in: .whitespaces)) ?? 0))
        }
        guard let multi = ChordContext(parts: parts) else {
            throw FaithfulError.chordUnavailable(name: chordName)
        }
        context = multi
    } else {
        guard let chord = ChordCatalog.chordIfExists(chordName) else {
            throw FaithfulError.chordUnavailable(name: chordName)
        }
        context = ChordContext(chord: chord)
    }
    var rng = S2RNG(seed: seed)
    var combined = MelodyPart2()
    for section in sections {
        let part = fillPartOfMelody(rng: &rng, section: section, context: context,
                                    minPitch: minPitch, maxPitch: maxPitch, avoidRepeats: true,
                                    startPosition: 0, startOldPitch: initOldPitch)
        for n in part.notes { combined.addNote(n) }
    }
    return (combined, rng.trace)
}
