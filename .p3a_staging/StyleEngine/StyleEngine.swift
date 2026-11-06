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

    /// 接线层使用的 styleId → bundle 内资源名（不含扩展名）。
    private let idToResource: [String: String] = [
        "sty:swing": "swing"
    ]
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
