import Foundation

// MARK: - StyleDrumRenderer
// .sty 鼓渲染器：逐小节按权重抽一条 drum-pattern，转换为现有 DrumPattern / DrumRule，
// 复用已验证的 DrumPatternExtractor.generate（同 slot 多鼓去重、channel 9、休止不发声），
// 再按小节偏移到全曲时间线。鼓名→MIDI 走 StyleDrumMap（Acoustic_Bass_Drum=35，区别于手写 kick=36）。

enum StyleDrumRenderer {

    static func render(parsed: ParsedStyle,
                       measureCount: Int,
                       slotsPerMeasure: Int,
                       rng: StyleRNG) -> [CompanionNote] {
        let patterns = parsed.drumPatterns
        guard !patterns.isEmpty else { return [] }

        var out: [CompanionNote] = []
        for measure in 0..<measureCount {
            let index = rng.nextWeightedIndex(patterns.map { $0.weight })
            let styPattern = patterns[min(index, patterns.count - 1)]

            let drumPattern = DrumPattern()
            for rule in styPattern.rules {
                guard let midi = StyleDrumMap.midi(rule.drumName) else { continue }
                let elements: [DrumPatternElement] = rule.hits.map {
                    DrumPatternElement(onsetSlots: $0.onsetSlots,
                                       durationSlots: $0.durationSlots,
                                       velocity: $0.isRest ? 0 : $0.velocity,
                                       isRest: $0.isRest)
                }
                if !elements.isEmpty {
                    drumPattern.rules.append(DrumRule(midiNote: midi, elements: elements))
                }
            }

            let oneBar = DrumPatternExtractor.generate(pattern: drumPattern,
                                                       measureCount: 1,
                                                       slotsPerMeasure: slotsPerMeasure)
            let base = measure * slotsPerMeasure
            out.append(contentsOf: oneBar.map {
                CompanionNote(startSlot: $0.startSlot + base,
                              midiPitch: $0.midiPitch,
                              durationSlots: $0.durationSlots,
                              volume: $0.volume,
                              channel: $0.channel)
            })
        }
        return out
    }
}
