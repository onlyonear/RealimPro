//
//  TradingResponderGuard.swift
//  Real imPro
//
//  M2-7 H2: RepeatAndRectify 1:1 对拍守卫（DEBUG-only）。
//  内置数据取自 Java 金标准（Gold.java 加载 My.voc 实跑），不依赖外部文件。
//  真机：devicectl ... -- -tradingProbe responder
//

#if DEBUG
import Foundation

enum TradingResponderGuard {

    static let chords24: [String] = ["A7", "D7", "A7", "A7", "D7", "D7", "A7", "A7", "E7", "D7", "A7", "E7", "A7", "D7", "A7", "A7", "D7", "D7", "A7", "A7", "E7", "D7", "A7", "E7"]

    static let responseStarts = [4, 12, 20]

    static let userPhrases: [Int: [TradingSlotNote]] = [
        1: [
            TradingSlotNote(pitch: 69, startSlot: 0, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 73, startSlot: 120, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 76, startSlot: 180, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 74, startSlot: 240, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 73, startSlot: 360, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 74, startSlot: 420, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 74, startSlot: 480, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 74, startSlot: 600, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 78, startSlot: 720, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 81, startSlot: 840, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 69, startSlot: 960, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 71, startSlot: 1080, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: -1, startSlot: 1200, durationSlots: 120, isRest: true),
            TradingSlotNote(pitch: 76, startSlot: 1320, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 69, startSlot: 1440, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 73, startSlot: 1560, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 76, startSlot: 1680, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 69, startSlot: 1800, durationSlots: 120, isRest: false),
        ],
        2: [
            TradingSlotNote(pitch: 64, startSlot: 0, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 68, startSlot: 120, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 71, startSlot: 180, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 76, startSlot: 240, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 68, startSlot: 360, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 69, startSlot: 420, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 74, startSlot: 480, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 78, startSlot: 600, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 81, startSlot: 720, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 74, startSlot: 840, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 69, startSlot: 960, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 73, startSlot: 1080, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 76, startSlot: 1200, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 69, startSlot: 1320, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 76, startSlot: 1440, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 68, startSlot: 1560, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 71, startSlot: 1620, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 76, startSlot: 1680, durationSlots: 240, isRest: false),
        ],
        3: [
            TradingSlotNote(pitch: 62, startSlot: 0, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 75, startSlot: 120, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 78, startSlot: 180, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 81, startSlot: 240, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 75, startSlot: 360, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 76, startSlot: 420, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 74, startSlot: 480, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 78, startSlot: 600, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 81, startSlot: 720, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 74, startSlot: 840, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 69, startSlot: 960, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 73, startSlot: 1080, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 76, startSlot: 1200, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 69, startSlot: 1320, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 69, startSlot: 1440, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 75, startSlot: 1560, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 76, startSlot: 1620, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 69, startSlot: 1680, durationSlots: 240, isRest: false),
        ],
    ]

    static let goldResponses: [Int: [TradingSlotNote]] = [
        1: [
            TradingSlotNote(pitch: 69, startSlot: 0, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 74, startSlot: 120, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 76, startSlot: 180, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 74, startSlot: 240, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 73, startSlot: 360, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 74, startSlot: 420, durationSlots: 300, isRest: false),
            TradingSlotNote(pitch: 78, startSlot: 720, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 81, startSlot: 840, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 69, startSlot: 960, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 71, startSlot: 1080, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: -1, startSlot: 1200, durationSlots: 120, isRest: true),
            TradingSlotNote(pitch: 76, startSlot: 1320, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 69, startSlot: 1440, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 73, startSlot: 1560, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 76, startSlot: 1680, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 69, startSlot: 1800, durationSlots: 120, isRest: false),
        ],
        2: [
            TradingSlotNote(pitch: 64, startSlot: 0, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 69, startSlot: 120, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 71, startSlot: 180, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 76, startSlot: 240, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 68, startSlot: 360, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 69, startSlot: 420, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 74, startSlot: 480, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 78, startSlot: 600, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 81, startSlot: 720, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 74, startSlot: 840, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 69, startSlot: 960, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 73, startSlot: 1080, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 76, startSlot: 1200, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 69, startSlot: 1320, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 76, startSlot: 1440, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 69, startSlot: 1560, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 71, startSlot: 1620, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 76, startSlot: 1680, durationSlots: 240, isRest: false),
        ],
        3: [
            TradingSlotNote(pitch: 62, startSlot: 0, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 76, startSlot: 120, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 78, startSlot: 180, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 81, startSlot: 240, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 75, startSlot: 360, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 76, startSlot: 420, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 74, startSlot: 480, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 78, startSlot: 600, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 81, startSlot: 720, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 74, startSlot: 840, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 69, startSlot: 960, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 73, startSlot: 1080, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 76, startSlot: 1200, durationSlots: 120, isRest: false),
            TradingSlotNote(pitch: 69, startSlot: 1320, durationSlots: 240, isRest: false),
            TradingSlotNote(pitch: 75, startSlot: 1560, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 76, startSlot: 1620, durationSlots: 60, isRest: false),
            TradingSlotNote(pitch: 69, startSlot: 1680, durationSlots: 240, isRest: false),
        ],
    ]

    @discardableResult
    static func run() -> Bool {
        let spb = 480
        var failures = 0
        for (ti, resStart) in responseStarts.enumerated() {
            let turn = ti + 1
            guard let user = userPhrases[turn], let gold = goldResponses[turn] else {
                print("❌ [RESPONDER] 轮\(turn) 内置数据缺失"); failures += 1; continue }
            let resNames = Array(chords24[resStart..<resStart + 4])
            var blocks: [TradingChordBlock] = []
            for (k, n) in resNames.enumerated() {
                blocks.append(TradingChordBlock(name: n, startSlot: k * spb, durationSlots: spb)) }
            let out = TradingResponder.respond(notes: user, responseChords: blocks,
                                       mode: .repeatAndRectify,
                                       toneSet: { TradingChordToneSet.toneSet(chordName: $0) })
            if out.count != gold.count {
                print("❌ [RESPONDER] 轮\(turn) 音数不同：swift=\(out.count) java=\(gold.count)"); failures += 1; continue }
            var bad = 0
            for i in 0..<out.count {
                if out[i] != gold[i] {
                    print("❌ [RESPONDER] 轮\(turn) 音\(i)：swift=\(out[i]) java=\(gold[i])"); bad += 1 } }
            if bad == 0 { print("✅ [RESPONDER] 轮\(turn) 逐位一致（\(gold.count) 音）") }
            failures += bad
        }
        if failures == 0 {
            print("🎉 [RESPONDER] 守卫通过：3 轮 RepeatAndRectify 与 Java 金标准 1:1")
        } else {
            print("❌ [RESPONDER] 守卫失败：\(failures) 处不符") }
        return failures == 0
    }
}

#endif
