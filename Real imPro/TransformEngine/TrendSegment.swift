import Foundation

// MARK: - TrendSegment — 趋势段落 (绑定和弦区间 + 指定Trend类型)
// 为 GrammarStrategy 提供统一音符池查询接口

struct TrendSegment {

    /// 趋势段编码名称
    let name: String
    /// 趋势实例 (多态生成器)
    let trend: any Trend
    /// 关联的和弦名列表
    let chordNames: [String]
    /// 对应 KeySpan 调性引用
    let key: Key
    /// 音域限制
    let pitchRange: ClosedRange<Int>
    /// 密度系数 (0.0-1.0, 越高音符越密)
    let density: Double

    /// P1-1: 趋势→变换权重映射 (供Transform引擎查询)
    var transformWeights: [String: Double] = [:]

    // MARK: - 初始化

    init(name: String,
         trend: any Trend,
         chordNames: [String],
         key: Key,
         pitchRange: ClosedRange<Int> = 48...84,
         density: Double = 0.5,
         transformWeights: [String: Double] = [:]) {
        self.name = name
        self.trend = trend
        self.chordNames = chordNames
        self.key = key
        self.pitchRange = pitchRange
        self.density = density
        self.transformWeights = transformWeights
    }

    // MARK: - 音符池查询

    /// 获取当前趋势段对所有和弦的合并音符池
    func generateNotePool(chordBlocks: [ChordBlock]) -> [Int] {
        var pool = Set<Int>()
        for chord in chordBlocks {
            guard chordNames.contains(chord.name) else { continue }
            let notes = trend.generateNotePool(chord: chord, key: key, range: pitchRange)
            pool.formUnion(notes)
        }
        // 按密度稀疏化
        let sorted = Array(pool).sorted()
        if density >= 1.0 { return sorted }
        let keepCount = max(1, Int(Double(sorted.count) * density))
        return Array(sorted.prefix(keepCount))
    }

    /// 获取单和弦音符池
    func generateNotePool(for chord: ChordBlock) -> [Int] {
        trend.generateNotePool(chord: chord, key: key, range: pitchRange)
    }
}

// MARK: - 趋势类型映射表 (和弦句型 → 推荐趋势)

extension TrendSegment {

    /// Brick和声句型 → 适配趋势策略
    static func trendForBrick(_ brickName: String, key: Key) -> TrendSegment? {
        let chordPattern: [String]
        let trendType: any Trend
        switch brickName {
        case "ii-V-I":
            chordPattern = ["Dm7", "G7", "Cmaj7"]
            trendType = ArpeggioTrend(direction: 1, octaves: 2)
        case "ii-V":
            chordPattern = ["Dm7", "G7"]
            trendType = AscendingTrend(stepSize: 2)
        case "V-I":
            chordPattern = ["G7", "Cmaj7"]
            trendType = ChromaticTrend(approachDirection: 1)
        case "I-vi-ii-V":
            chordPattern = ["Cmaj7", "Am7", "Dm7", "G7"]
            trendType = DiatonicTrend(direction: 1)
        case "tritone-sub":
            chordPattern = ["Dm7", "Db7", "Cmaj7"]
            trendType = ChromaticTrend(approachDirection: -1)
        default:
            return nil
        }
        return TrendSegment(
            name: brickName,
            trend: trendType,
            chordNames: chordPattern,
            key: key
        )
    }

    /// 按Brick库自动匹配趋势段
    static func segments(for bricks: [(name: String, start: Double, end: Double, key: String)],
                          roadmap: JazzRoadmap) -> [TrendSegment] {
        bricks.compactMap { brick in
            let ks = KeySpan(startBeat: brick.start, endBeat: brick.end,
                             rootPC: PitchClass(noteName: brick.key).index,
                             mode: .major, isTemporary: false)
            let key = Key(keySpan: ks)
            return trendForBrick(brick.name, key: key)
        }
    }
}
