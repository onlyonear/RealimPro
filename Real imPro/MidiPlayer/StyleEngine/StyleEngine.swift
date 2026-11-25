import Foundation

// MARK: - StyleRNG
// .sty 展开的随机源。Java 用 java.util.Random（加权抽取/取音）与 Math.random()（placePitchNear/pressure），
// 不要求与 Java 逐音一致，只需：① 固定种子可复现（回归 / DEBUG 对拍）；② 正式播放真随机。

protocol StyleRNG {
    func nextDouble() -> Double                 // [0, 1)
    func nextInt(_ count: Int) -> Int           // [0, count)
    func nextWeightedIndex(_ weights: [Double]) -> Int
}

extension StyleRNG {
    /// 加权随机下标（Java getPattern 的等长加权选择）。
    func nextWeightedIndex(_ weights: [Double]) -> Int {
        guard !weights.isEmpty else { return 0 }
        let total = weights.reduce(0, +)
        guard total > 0 else { return 0 }
        var r = nextDouble() * total
        for (i, w) in weights.enumerated() {
            r -= w
            if r < 0 { return i }
        }
        return weights.count - 1
    }
}

/// SplitMix64：固定种子、跨设备一致，用于回归与 DEBUG 对拍。
final class SeededStyleRNG: StyleRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    func nextDouble() -> Double {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(1 << 53)
    }
    func nextInt(_ count: Int) -> Int {
        guard count > 0 else { return 0 }
        return Int(nextDouble() * Double(count)) % count
    }
}

/// 系统真随机，用于正式播放（每次伴奏不同，与 Java 行为一致）。
final class RandomStyleRNG: StyleRNG {
    private var generator = SystemRandomNumberGenerator()
    func nextDouble() -> Double { Double.random(in: 0..<1, using: &generator) }
    func nextInt(_ count: Int) -> Int {
        guard count > 0 else { return 0 }
        return Int.random(in: 0..<count, using: &generator)
    }
}

/// 把 StyleRNG 适配给 FullVoicingEngine 的 VoicingRNG（钢琴排簿候选随机）。
struct StyleVoicingRNG: VoicingRNG {
    let rng: StyleRNG
    func nextIndex(_ count: Int) -> Int { rng.nextInt(count) }
}

// MARK: - StyleEngine
// .sty 引擎总入口：从 bundle 加载并缓存解析结果，调度鼓 / 贝斯 / 钢琴三轨渲染，产出 BackingTrackData。
// P3-a 只注册标准 swing（id "sty:swing" → 资源 swing.sty）；P3-b 再注册其余 45 个并接二级菜单。

final class StyleEngine {
    static let shared = StyleEngine()

    // [旧码封存 P3-b 20261011] P3-a 只注册标准 swing：
    // private let idToResource: [String: String] = [ "sty:swing": "swing" ]
    //
    // [P3-d] 已移植的 Java .sty 资源名（不含扩展名）：P3-b 46 → P3-b.1 下架 3（=43）→ P3-d 增 10（=53），
    // [P3-e] 真机听感再下架 3（blues-clair / waltz-chopin / african-slow，资源 mv 入 .backup/P3e-20261011/，未删除）→ 现 50，
    // 与 Bundle 内 Resources/Styles/*.sty 一一对应。
    // 顺序即菜单分组顺序；新增风格只需把资源拷入 Resources/Styles/ 并在此登记 + 在 BandMixerView 加 case。
    static let styResourceNames: [String] = [
        // Swing 11
        "swing", "swing-backbeat", "swing-square-comp", "swing-substitute",
        "swing-BarryHarris", "swing-BobbyTimmons", "swing-BudPowell", "swing-HoraceSilver",
        "swing-RedGarland", "swing-SonnyClark", "swing-TadDameron",
        // P3-b.1 下架（真机听感）：shuffle-light / rock-triplet / rock-triplet-2，资源已移入 .backup/P3b1-20261011/removed_styles/（未删除）
        // 旧码封存（原 Shuffle 5）：
        // "shuffle", "shuffle-cloppety", "shuffle-light", "boogie-shuffle-1", "boogie-shuffle-2",
        // 旧码封存（原 Rock 13）：
        // "rock-50s", "rock-6-8", "rock-brushes", "rock-calypso", "rock-heavy-even",
        // "rock-light", "rock-light-even", "rock-medium", "rock-medium-even", "rock-slow",
        // "rock-triplet", "rock-triplet-2", "folk-rock",
        // Shuffle 4
        "shuffle", "shuffle-cloppety", "boogie-shuffle-1", "boogie-shuffle-2",
        // Rock 11（folk-rock 保留）
        "rock-50s", "rock-6-8", "rock-brushes", "rock-calypso", "rock-heavy-even",
        "rock-light", "rock-light-even", "rock-medium", "rock-medium-even", "rock-slow",
        "folk-rock",
        // Latin 10
        "latin", "latin-2-3-son-clave", "latin-3-2-son-clave", "latin-enhanced", "latin-fast",
        "latin-new", "latin-pedal-bass-1", "latin-pedal-bass-2", "latin-plain", "latin-with-guiro",
        // Funk 2 / Blues 2 / Two-beat / Tango（[P3-e] blues-clair 真机听感下架，旧行封存：）
        // "funk", "funk-disco", "pop-blues", "senor-blues", "blues-clair", "two-beat", "tango",
        "funk", "funk-disco", "pop-blues", "senor-blues", "two-beat", "tango",
        // [P3-d] Ballad 1 / Bossa 3 / Waltz / African（[P3-e] waltz-chopin、african-slow 真机听感下架，旧两行封存：）
        "ballad",
        "bossa", "bossaA", "bossaB",
        // 旧码封存："waltz", "waltz-chopin", "waltz-parisienne",
        "waltz", "waltz-parisienne",
        // 旧码封存："african", "african-slow", "african3"
        "african", "african3"
    ]

    /// 接线层 styleId（"sty:"+资源名）→ bundle 资源名。
    private let idToResource: [String: String] = {
        var d: [String: String] = [:]
        for n in StyleEngine.styResourceNames { d["sty:" + n] = n }
        return d
    }()
    private var cache: [String: ParsedStyle] = [:]
    private init() {}

    func isStyStyle(_ style: String) -> Bool { idToResource[style] != nil }

    func load(_ styleId: String) -> ParsedStyle? {
        if let cached = cache[styleId] { return cached }
        guard let resource = idToResource[styleId] else { return nil }
        let candidates = [
            Bundle.main.url(forResource: resource, withExtension: "sty"),
            Bundle.main.url(forResource: resource, withExtension: "sty", subdirectory: "Styles"),
            Bundle.main.url(forResource: resource, withExtension: "sty", subdirectory: "Resources/Styles"),
            Bundle.main.url(forResource: resource, withExtension: "sty", subdirectory: "Real imPro/Resources/Styles")
        ].compactMap { $0 }
        guard let url = candidates.first,
              let text = try? String(contentsOf: url, encoding: .utf8),
              let parsed = StyleParser.parse(text: text) else { return nil }
        cache[styleId] = parsed
        return parsed
    }

    /// 生成三轨伴奏。seed 非空 → 可复现（回归 / DEBUG）；nil → 真随机。
    func render(styleId: String,
                measureCount: Int,
                chordSegments: [ChordSegment],
                slotsPerMeasure: Int,
                seed: UInt64? = nil) -> BackingTrackData {
        var data = BackingTrackData()
        guard let parsed = load(styleId) else { return data }
        let rng: StyleRNG = seed.map { SeededStyleRNG(seed: $0) } ?? RandomStyleRNG()

        data.bassNotes = StyleBassRenderer.render(parsed: parsed, segments: chordSegments,
                                                  slotsPerMeasure: slotsPerMeasure, rng: rng)
        data.pianoNotes = StyleChordRenderer.render(parsed: parsed, segments: chordSegments,
                                                    slotsPerMeasure: slotsPerMeasure, rng: rng)
        data.drumNotes = StyleDrumRenderer.render(parsed: parsed, measureCount: measureCount,
                                                  slotsPerMeasure: slotsPerMeasure, rng: rng)
        data.compSwing = parsed.compSwing
        data.melodySwing = parsed.melodySwing
        return data
    }
}
