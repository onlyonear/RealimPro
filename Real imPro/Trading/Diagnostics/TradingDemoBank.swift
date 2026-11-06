import Foundation

#if DEBUG

// MARK: - Trading / DemoBank / 节奏样本库（M2-6b 听验用）
//
// 8 组确定性素材，每组 4 小节（1920 slot）。目的：让你的耳朵逐条对照"听到的 vs 谱上画的"。
// 全部单音线（录音器是单音线），音高各不相同便于分辨。
enum TradingDemoBank {

    typealias N = TradingRoundTripHarness.N

    struct Item { let name: String; let notes: [N] }

    static func all() -> [Item] {
        [eighth(), sixteenth(), eighthTriplet(), sixteenthTriplet(),
         syncopation(), dotted(), mixed(), longAndRest(), swing(), beatMix()]
    }

    // MARK: 9 swing 八分（演奏 2:1，谱面应写成平均八分）
    static func swing() -> Item {
        var a: [N] = []
        for b in 0..<16 {                       // 4 小节，每拍一对
            let base = b * 120
            a.append(N(pitch: 67 + (b % 5), start: base, dur: 80, triplet: false))       // 长
            a.append(N(pitch: 67 + ((b + 2) % 5), start: base + 80, dur: 40, triplet: false)) // 短
        }
        return Item(name: "⑨ swing 八分（听 2:1，记平均八分）", notes: a)
    }

    // MARK: 10 拍内混合（前半拍三连 + 后半拍十六分，同一拍里两种细分）
    static func beatMix() -> Item {
        var a: [N] = []
        for b in 0..<16 {
            let base = b * 120
            // 前半拍：三个十六分三连
            a.append(N(pitch: 67, start: base, dur: 20, triplet: true))
            a.append(N(pitch: 69, start: base + 20, dur: 20, triplet: true))
            a.append(N(pitch: 71, start: base + 40, dur: 20, triplet: true))
            // 后半拍：两个十六分
            a.append(N(pitch: 72, start: base + 60, dur: 30, triplet: false))
            a.append(N(pitch: 74, start: base + 90, dur: 30, triplet: false))
        }
        return Item(name: "⑩ 拍内混合（前半三连 + 后半十六分）", notes: a)
    }

    // MARK: 1 直八分
    static func eighth() -> Item {
        var a: [N] = []
        // 第 1-2 小节：每拍两个八分
        for bar in 0..<2 {
            for k in 0..<8 {
                a.append(N(pitch: 67 + (k % 5), start: bar * 480 + k * 60, dur: 60, triplet: false))
            }
        }
        // 第 3 小节：四分
        for k in 0..<4 { a.append(N(pitch: 72 + k, start: 960 + k * 120, dur: 120, triplet: false)) }
        // 第 4 小节：二分 + 休止
        a.append(N(pitch: 76, start: 1440, dur: 240, triplet: false))
        return Item(name: "① 直八分", notes: a)
    }

    // MARK: 2 十六分
    static func sixteenth() -> Item {
        var a: [N] = []
        for bar in 0..<2 {
            // 前两拍：每拍 4 个十六分；后两拍休止
            for k in 0..<8 {
                a.append(N(pitch: 64 + (k % 6), start: bar * 480 + k * 30, dur: 30, triplet: false))
            }
        }
        // 第 3 小节：两拍八分 + 一拍十六分
        for k in 0..<4 { a.append(N(pitch: 72 + k, start: 960 + k * 60, dur: 60, triplet: false)) }
        for k in 0..<4 { a.append(N(pitch: 76 + k, start: 1200 + k * 30, dur: 30, triplet: false)) }
        return Item(name: "② 十六分", notes: a)
    }

    // MARK: 3 八分三连
    static func eighthTriplet() -> Item {
        var a: [N] = []
        for bar in 0..<2 {
            for k in 0..<12 {
                a.append(N(pitch: 67 + (k % 5), start: bar * 480 + k * 40, dur: 40, triplet: true))
            }
        }
        // 第 3 小节：四分三连（每音 80）
        for k in 0..<6 { a.append(N(pitch: 72 + k, start: 960 + k * 80, dur: 80, triplet: true)) }
        return Item(name: "③ 八分三连 + 四分三连", notes: a)
    }

    // MARK: 4 十六分三连
    static func sixteenthTriplet() -> Item {
        var a: [N] = []
        for bar in 0..<2 {
            for k in 0..<12 where k < 6 {   // 前两拍：每拍 6 个十六分三连
                a.append(N(pitch: 64 + (k % 6), start: bar * 480 + k * 20, dur: 20, triplet: true))
            }
        }
        return Item(name: "④ 十六分三连", notes: a)
    }

    // MARK: 5 切分
    static func syncopation() -> Item {
        var a: [N] = []
        for bar in 0..<2 {
            let b = bar * 480
            a.append(N(pitch: 67, start: b + 0,   dur: 120, triplet: false))   // 正拍长
            a.append(N(pitch: 69, start: b + 180, dur: 60,  triplet: false))   // 反拍短
            a.append(N(pitch: 71, start: b + 240, dur: 120, triplet: false))
            a.append(N(pitch: 72, start: b + 420, dur: 60,  triplet: false))
        }
        // 第 3-4 小节：跨拍长音
        a.append(N(pitch: 74, start: 960, dur: 360, triplet: false))           // 附点二分
        a.append(N(pitch: 76, start: 1320, dur: 120, triplet: false))
        a.append(N(pitch: 79, start: 1440, dur: 480, triplet: false))          // 全音符
        return Item(name: "⑤ 切分 + 跨拍长音", notes: a)
    }

    // MARK: 6 附点
    static func dotted() -> Item {
        var a: [N] = []
        for bar in 0..<2 {
            let b = bar * 480
            a.append(N(pitch: 67, start: b + 0,   dur: 180, triplet: false))   // 附点四分
            a.append(N(pitch: 69, start: b + 180, dur: 60,  triplet: false))
            a.append(N(pitch: 71, start: b + 240, dur: 180, triplet: false))
            a.append(N(pitch: 72, start: b + 420, dur: 60,  triplet: false))
        }
        a.append(N(pitch: 74, start: 960, dur: 90, triplet: false))            // 附点八分
        a.append(N(pitch: 76, start: 1050, dur: 30, triplet: false))
        return Item(name: "⑥ 附点", notes: a)
    }

    // MARK: 7 混合（十六分 + 三连 + 切分）
    static func mixed() -> Item {
        var a: [N] = []
        // 第 1 小节：十六分
        for k in 0..<8 { a.append(N(pitch: 64 + k % 5, start: k * 30, dur: 30, triplet: false)) }
        // 第 2 小节：八分三连
        for k in 0..<12 { a.append(N(pitch: 67 + k % 5, start: 480 + k * 40, dur: 40, triplet: true)) }
        // 第 3 小节：切分
        a.append(N(pitch: 72, start: 960, dur: 120, triplet: false))
        a.append(N(pitch: 74, start: 1140, dur: 60, triplet: false))
        a.append(N(pitch: 76, start: 1200, dur: 120, triplet: false))
        // 第 4 小节：全音符
        a.append(N(pitch: 79, start: 1440, dur: 480, triplet: false))
        return Item(name: "⑦ 混合（16分+三连+切分）", notes: a)
    }

    // MARK: 8 长音与休止
    static func longAndRest() -> Item {
        var a: [N] = []
        a.append(N(pitch: 60, start: 0,    dur: 480, triplet: false))   // 全音符
        a.append(N(pitch: 64, start: 480,  dur: 240, triplet: false))   // 二分
        a.append(N(pitch: 67, start: 720,  dur: 240, triplet: false))   // 二分
        a.append(N(pitch: 71, start: 960,  dur: 120, triplet: false))   // 四分
        // 1020-1200 休止
        a.append(N(pitch: 74, start: 1200, dur: 120, triplet: false))
        // 1320-1440 休止
        a.append(N(pitch: 76, start: 1440, dur: 360, triplet: false))   // 附点二分
        return Item(name: "⑧ 长音与休止", notes: a)
    }
}

#endif
