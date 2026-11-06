import Foundation

// MARK: - StyleChordRenderer
// .sty 钢琴(comping)渲染器。自建、不改 ChordPatternExtractor（守住“只 3 处生产接线”）。
//  - voicing：每个击弦点用一个贯穿全曲的 FullVoicingEngine（音域/排布取自 .sty：swing 为 d-(50)~a(69)、open），
//    经 ChordSymbolMapper.resolve → engine.voicing(forForm:rootRise:)，保持跨段声部连接；
//  - 时间线：复刻 ChordPatternExtractor.generateTimeline 的 while/residual/push/跨小节窗口切割
//    （对齐 Java Style.getChordPattern + makeChordline），唯一区别是句型从 .sty chord-pattern 加权抽取；
//  - 人性化：力度 ±8、起点 ±3 抖动（同现有 Swift comping，固定种子可复现）；
//  - 力度取 Java 规则原值（无 V 默认 127、V 标记原样，见 Style.java:1414），引擎内【不做响度压缩】：
//    响度平衡属混音层，列入 P3-c 真机听感验收用单一播放端增益统一处理，避免把弱音（如军鼓 fill V10）压到近无声。

enum StyleChordRenderer {

    private static let chordChannel: UInt8 = 1
    private static let defaultVelocity: UInt8 = 127   // Java Style.java:1414 chordline 初始 volume=127

    static func render(parsed: ParsedStyle,
                       segments: [ChordSegment],
                       slotsPerMeasure: Int,
                       rng: StyleRNG) -> [CompanionNote] {
        let styPatterns = parsed.chordPatterns
        guard !styPatterns.isEmpty else { return [] }

        let engine = FullVoicingEngine(rng: StyleVoicingRNG(rng: rng))
        engine.lowMidi = parsed.chordLow
        engine.highMidi = parsed.chordHigh
        engine.requestType = voicingType(parsed.voicingType)

        var notes: [CompanionNote] = []
        var missed = 0
        var residual: ChordPattern? = nil
        var residualOrigin = 0

        for seg in segments {
            var remaining = seg.durationSlots
            var segAbsBase = seg.startSlot
            var firstOfSeg = true

            while remaining > 0 {
                let pat: ChordPattern
                let origin: Int
                if let r = residual {
                    pat = r
                    origin = residualOrigin
                    residual = nil
                } else {
                    let index = rng.nextWeightedIndex(styPatterns.map { $0.weight })
                    pat = convert(styPatterns[min(index, styPatterns.count - 1)])
                    origin = 0
                }

                let patRemain = pat.durationSlots - origin
                let segLen = min(max(patRemain, 0), remaining)
                guard segLen > 0 else { residual = nil; break }   // 防御：异常空片段不死循环

                let push = (firstOfSeg && origin == 0) ? pat.pushSlots : 0
                let winStart = origin
                let winEnd = origin + segLen

                for el in pat.elements where el.noteType == .chord {
                    let s = max(el.onsetSlots, winStart)
                    let e = min(el.onsetSlots + el.durationSlots, winEnd)
                    guard e > s else { continue }
                    var absOn = segAbsBase + (s - winStart) - push
                    if absOn < 0 { absOn = 0 }   // 全曲开头抢拍不得早于 0（对齐 Java time<0 钳 0）
                    emitVoicing(chordName: seg.chord, engine: engine,
                                absStart: absOn, duration: e - s,
                                baseVelocity: el.velocity, rng: rng,
                                into: &notes, missed: &missed)
                }

                remaining -= segLen
                segAbsBase += segLen
                firstOfSeg = false
                let consumedEnd = origin + segLen
                if consumedEnd < pat.durationSlots {
                    residual = pat
                    residualOrigin = consumedEnd
                }
            }
        }

        #if DEBUG
        if missed > 0 {
            print("[StyleEngine] chord: \(missed) hit point(s) had no voicing and were skipped")
        }
        #endif
        notes.sort { $0.startSlot < $1.startSlot }
        return notes
    }

    // MARK: .sty chord-pattern（X/R/V token）→ ChordPattern（供时间线复用）

    private static func convert(_ sp: StylePattern) -> ChordPattern {
        let cp = ChordPattern()
        cp.pushSlots = sp.pushSlots
        cp.patternLengthSlots = sp.lengthSlots > 0 ? sp.lengthSlots : slotsPerMeasureFallback
        var onset = 0
        var velocity = defaultVelocity
        var elements: [ChordElement] = []
        for token in sp.ruleTrees {
            guard let s = token.asAtom else { continue }   // (push …) 已在解析期提取，这里跳过
            let lead = String(s.prefix(1))
            let rest = String(s.dropFirst())
            if lead == "V", let v = Int(rest) {
                velocity = UInt8(clamping: v)
                continue
            }
            if (lead == "X" || lead == "R") && s.count >= 2 {
                let dur = StyleDuration.slots(rest)
                elements.append(ChordElement(onsetSlots: onset,
                                             durationSlots: dur,
                                             velocity: velocity,
                                             noteType: lead == "X" ? .chord : .rest))
                onset += dur
            }
        }
        cp.elements = elements
        return cp
    }

    private static let slotsPerMeasureFallback = 480

    // MARK: 单个击弦点 → 一组 voicing MIDI（无候选则跳过并计数）

    private static func emitVoicing(chordName: String,
                                    engine: FullVoicingEngine,
                                    absStart: Int,
                                    duration: Int,
                                    baseVelocity: UInt8,
                                    rng: StyleRNG,
                                    into notes: inout [CompanionNote],
                                    missed: inout Int) {
        guard let resolved = ChordSymbolMapper.resolve(chordName),
              let voicing = engine.voicing(forForm: resolved.canonical, rootRise: resolved.rise),
              !voicing.isEmpty else {
            missed += 1
            return
        }
        // 同一击弦点所有音共用一个力度（±8 人性化）；起点每音独立 ±3（模拟手指滚奏）。
        let velocity = UInt8(clamping: Int(baseVelocity) + rng.nextInt(17) - 8)
        for midi in voicing.sorted() {
            let start = max(0, absStart + rng.nextInt(7) - 3)
            notes.append(CompanionNote(startSlot: start,
                                       midiPitch: UInt8(clamping: midi),
                                       durationSlots: duration,
                                       volume: velocity,
                                       channel: chordChannel))
        }
    }

    private static func voicingType(_ raw: String) -> JazzVoicingType {
        switch raw.lowercased() {
        case "closed": return .closed
        case "shout":  return .shout
        case "all":    return .all
        default:       return .open
        }
    }
}
