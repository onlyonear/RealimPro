import Foundation

// MARK: - StyleBassRenderer
// .sty 贝斯（walking bass）渲染器。逐和弦把 bass-pattern 规则拼满该和弦时长。
// 忠实移植 Java：
//   BassPattern.applyRules（stylePatterns/BassPattern.java:640-905）规则码
//     B 根音 / C 随机和弦音 / S 首选音阶的二·三度经过（getIntervals :961-984）/
//     A 下一和弦根音 ±1 趋近 / N 下一和弦根音并结束本段 / R 休止 / = 重复上一音 /
//     V 力度 / (X degree dur) 音阶度数（getInterval :942-950）；
//   每个非休非=音先 transpose(-24)（:857），再 placePitchNear（MARGIN=11，：1029-1085）、
//   pressure（:1096-1137，center 实算到 high 的历史 quirk、四次方软拉回），最后按风格音域硬钳；
//   Style.getPattern（:1020-1087）：取 ≤剩余 的最长句，等长按权重随机；放不下才取 ≥剩余 的最短句截断；
//   Style.addToBassline（:1513-1600）逐和弦 while 拼满；趋近音仅在该句填到段边界时指下一和弦（:1552-1554）；
//   初始音 = 音域中点（:2195-2196），段首八度钳回（:2292-2302）。

enum StyleBassRenderer {
    private static let margin = 11
    private static let softMargin = 6
    private static let defaultVelocity: UInt8 = 127   // Java 规则层无 V 标记时默认 MAX_VOLUME(Style.java:2364)
    private static let bassChannel: UInt8 = 2

    private enum Op {
        case root, chordTone, scaleTone, approach, next, rest, same
        case volume(UInt8)
        case degree(index: Int, alteration: Int)
    }
    private struct Event {
        let op: Op
        let slots: Int
    }

    static func render(parsed: ParsedStyle,
                       segments: [ChordSegment],
                       slotsPerMeasure: Int,
                       rng: StyleRNG) -> [CompanionNote] {
        let patterns = parsed.bassPatterns
        guard !patterns.isEmpty else { return [] }
        let low = parsed.bassLow, high = parsed.bassHigh

        var notes: [CompanionNote] = []
        var globalLast: Int?

        for (i, seg) in segments.enumerated() {
            guard let harmony = StyleScaleTable.resolve(seg.chord) else { continue }
            let nextHarmony = (i + 1 < segments.count) ? StyleScaleTable.resolve(segments[i + 1].chord) : nil

            var last = globalLast ?? ((low + high) / 2)
            // 段首八度钳回
            if last > high { last -= 12 }
            else if last < low { last += 12 }

            var remaining = seg.durationSlots
            var cursor = 0

            while remaining > 0 {
                guard let pattern = getPattern(patterns, remaining: remaining, rng: rng) else { break }
                let events = parseEvents(pattern.ruleTrees)
                let fillTo = min(pattern.lengthSlots, remaining)
                var localCursor = 0
                var endSegment = false
                var runningVel = defaultVelocity

                for event in events {
                    if case .volume(let v) = event.op { runningVel = v; continue }
                    if localCursor >= fillTo { break }
                    let dur = min(max(0, event.slots), fillTo - localCursor)

                    switch event.op {
                    case .volume:
                        break
                    case .rest:
                        localCursor += event.slots
                        continue
                    case .next:
                        if let nh = nextHarmony {
                            let midi = place(nh.rootPC, last: last, low: low, high: high, rng: rng)
                            if dur > 0 {
                                notes.append(CompanionNote(startSlot: seg.startSlot + cursor + localCursor,
                                                           midiPitch: UInt8(clamping: midi),
                                                           durationSlots: dur,
                                                           volume: runningVel,
                                                           channel: bassChannel))
                            }
                            last = midi
                        }
                        localCursor += event.slots
                        endSegment = true
                    default:
                        guard let pc = pitchClass(for: event.op, harmony: harmony,
                                                  nextHarmony: nextHarmony, last: last, rng: rng) else {
                            localCursor += event.slots
                            continue
                        }
                        let midi: Int
                        if case .same = event.op {
                            midi = last
                        } else {
                            midi = place(pc, last: last, low: low, high: high, rng: rng)
                        }
                        if dur > 0 {
                            notes.append(CompanionNote(startSlot: seg.startSlot + cursor + localCursor,
                                                       midiPitch: UInt8(clamping: midi),
                                                       durationSlots: dur,
                                                       volume: runningVel,
                                                       channel: bassChannel))
                        }
                        last = midi
                        localCursor += event.slots
                    }
                    if endSegment { break }
                }

                let filled = endSegment ? remaining : min(pattern.lengthSlots, remaining)
                cursor += filled
                remaining -= filled
                if endSegment { remaining = 0 }
            }
            globalLast = last
        }
        return notes
    }

    // MARK: 规则解析

    private static func parseEvents(_ trees: [StyleSex]) -> [Event] {
        var events: [Event] = []
        for tk in trees {
            if let items = tk.asList {
                // (X degree duration [mod])
                if items.first?.asAtom == "X", items.count >= 3,
                   let degreeAtom = items[1].asAtom, let durAtom = items[2].asAtom {
                    let (idx, alt) = parseDegree(degreeAtom)
                    events.append(Event(op: .degree(index: idx, alteration: alt),
                                        slots: StyleDuration.slots(durAtom)))
                }
                continue
            }
            guard let s = tk.asAtom else { continue }
            let lead = String(s.prefix(1))
            let rest = String(s.dropFirst())

            if lead == "U" || lead == "D" { continue }   // 方向修饰：默认走 placePitchNear+pressure，忽略
            if lead == "V" {
                events.append(Event(op: .volume(UInt8(clamping: Int(rest) ?? 100)), slots: 0))
                continue
            }
            let op: Op
            switch lead {
            case "B": op = .root
            case "C": op = .chordTone
            case "S": op = .scaleTone
            case "A": op = .approach
            case "N": op = .next
            case "R": op = .rest
            case "=": op = .same
            default:  op = .root
            }
            let slots = s.count >= 2 ? StyleDuration.slots(rest) : 0
            events.append(Event(op: op, slots: slots))
        }
        return events
    }

    private static func parseDegree(_ s: String) -> (Int, Int) {
        var t = s
        var alteration = 0
        if t.hasPrefix("b") { alteration = -1; t.removeFirst() }
        else if t.hasPrefix("#") { alteration = 1; t.removeFirst() }
        let n = Int(t) ?? 1
        return (n, alteration)
    }

    // MARK: 取音

    private static func pitchClass(for op: Op,
                                   harmony: StyleHarmony,
                                   nextHarmony: StyleHarmony?,
                                   last: Int,
                                   rng: StyleRNG) -> Int? {
        switch op {
        case .root:
            return harmony.rootPC
        case .chordTone:
            let rel = harmony.chordTones[rng.nextInt(harmony.chordTones.count)]
            return (harmony.rootPC + rel) % 12
        case .scaleTone:
            let candidates = scaleApproachClasses(harmony: harmony, last: last)
            let pool = candidates.isEmpty ? harmony.chordTones.map { ($0 + harmony.rootPC) % 12 } : candidates
            return pool[rng.nextInt(pool.count)]
        case .approach:
            guard let nr = nextHarmony?.rootPC else { return harmony.rootPC }
            return (nr + (rng.nextInt(2) == 0 ? 1 : -1)) % 12
        case .next:
            return nextHarmony?.rootPC ?? harmony.rootPC
        case .same:
            return last % 12
        case .degree(let index, let alteration):
            if let scale = harmony.scale, !scale.isEmpty {
                let i = ((index - 1) % scale.count + scale.count) % scale.count
                return (harmony.rootPC + scale[i] + alteration + 12) % 12
            } else {
                let tones = harmony.chordTones
                let i = ((index - 1) % tones.count + tones.count) % tones.count
                return (harmony.rootPC + tones[i] + alteration + 12) % 12
            }
        case .rest, .volume:
            return nil
        }
    }

    /// S 码：首选音阶中相对上一音的音阶二度（±1 级）与三度（±2 级）候选，对齐 getIntervals(2)+getIntervals(3)。
    private static func scaleApproachClasses(harmony: StyleHarmony, last: Int) -> [Int] {
        guard let scale = harmony.scale, !scale.isEmpty else { return [] }
        var series: [Int] = []
        for oct in -1...3 {
            for pc in scale { series.append(harmony.rootPC + pc + 12 * oct + 36) }
        }
        guard let rootPos = series.indices.min(by: { abs(series[$0] - last) < abs(series[$1] - last) }) else {
            return []
        }
        var out: Set<Int> = []
        for delta in [1, -1, 2, -2] {
            let idx = rootPos + delta
            if series.indices.contains(idx) { out.insert(series[idx] % 12) }
        }
        return Array(out)
    }

    // MARK: 八度放置 / 软边界

    private static func place(_ pitchClass: Int, last: Int, low: Int, high: Int, rng: StyleRNG) -> Int {
        var p = 60 + ((pitchClass % 12) + 12) % 12   // spell transpose(rise) 的中央八度近似
        p -= 24                                        // BassPattern 统一 transpose(-24)
        // placePitchNear：朝 base(last) 收敛到 ±MARGIN（Java 两个随机分支方向相同，净效果确定性）
        while p > last + margin { p -= 12 }
        while p < last - margin { p += 12 }
        // pressure 软拉回
        p = pressure(p, low: low, high: high, rng: rng)
        // 风格音域硬边界
        while p > high { p -= 12 }
        while p < low { p += 12 }
        return p
    }

    /// 对齐 BassPattern.pressure（:1096-1137）。注意 Java 的 center = low + (high-low) = high（注释自承只有期望一半），
    /// 故上软界 high+6 几乎不触发，实际效果集中在「音低于 high-6 时按距离四次方概率抬一个八度」。
    private static func pressure(_ x0: Int, low: Int, high: Int, rng: StyleRNG) -> Int {
        var x = x0
        let center = low + (high - low)
        let softHigh = center + softMargin
        let softLow = center - softMargin

        if x > softHigh {
            let numerator = x - softHigh
            let denominator = high - softHigh
            if denominator != 0 {
                var prob = Double(numerator) / Double(denominator)
                prob = prob * prob * prob * prob
                if rng.nextDouble() < prob { x -= 12 }
            }
        } else if x < softLow {
            let numerator = softLow - x
            let denominator = softLow - low
            if denominator != 0 {
                var prob = Double(numerator) / Double(denominator)
                prob = prob * prob * prob * prob
                if rng.nextDouble() < prob { x += 12 }
            }
        }
        return x
    }

    // MARK: getPattern

    private static func getPattern(_ patterns: [StylePattern], remaining: Int, rng: StyleRNG) -> StylePattern? {
        let fitting = patterns.filter { $0.lengthSlots > 0 && $0.lengthSlots <= remaining }
        if !fitting.isEmpty {
            let longest = fitting.map { $0.lengthSlots }.max()!
            let equalLength = patterns.filter { $0.lengthSlots == longest }
            let idx = rng.nextWeightedIndex(equalLength.map { $0.weight })
            return equalLength[min(idx, equalLength.count - 1)]
        }
        return patterns.filter { $0.lengthSlots >= remaining }.min { $0.lengthSlots < $1.lengthSlots }
    }
}
