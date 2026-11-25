import Foundation

// MARK: - ChordExtensionTonePool — 8类和弦族延伸音白名单
// 按和弦族提供精确的9/11/13/alt延伸音候选音列表, 替代硬编码 [2,5,9]
//
// 使用: ChordExtensionTonePool.tonesFor(.dominant) → (primary:[2,5,9], altered:[1,6,8], avoid:[3])

struct ChordExtensionTonePool {

    /// 单类和弦族的延伸音配置
    struct ToneSet {
        let primary:  [Int]   // 可用延伸音 (半音距根音)
        let altered:  [Int]   // alter音 (仅dominant)
        let avoidTones: [Int] // 避用音
    }

    // ═══════════════════════════════════════════════════════════
    // 8类和弦族白名单 (interval from root in semitones)
    // ═══════════════════════════════════════════════════════════

    private static let families: [ChordFamily: ToneSet] = [
        .major: ToneSet(
            //primary:   [2, 5, 9],       // 9, 11, 13
            //altered:   [6],             // #11 (仅Lydian场景)
            //avoidTones: [1, 8]          // b9, b13 避用
            primary:   [2, 5, 6, 9],    // 9, 11, #11, 13 (自然11放宽为色彩音, 对齐现代爵士maj7sus4实践)
            altered:   [],
            avoidTones: [1, 8]          // b9, b13 避用 (自然11不再avoid)
        ),
        .minor: ToneSet(
            primary:   [2, 5, 9],       // 9, 11, 13
            altered:   [],
            avoidTones: [1, 6, 8]       // b9, #11, b13 避用
        ),
        .dominant: ToneSet(
            primary:   [2, 5, 9],       // 9, 11, 13 (自然11放宽为色彩音, 对齐sus4/Mixolydian实践)
            altered:   [1, 3, 6, 8],   // b9, #9, #11, b13
            avoidTones: []              // 自然11不再avoid (alt属七在colorIntervals中单独排除)
        ),
        .halfDiminished: ToneSet(
            primary:   [2, 5, 8],       // 9, 11, b13
            altered:   [],
            avoidTones: [4]             // 大三度 (M3) 避用
        ),
        .diminished: ToneSet(
            primary:   [2, 5, 8, 10],   // 9, 11, b13, 7(减七特性)
            altered:   [],
            avoidTones: [4, 6]          // 3, #11 避用
        ),
        .augmented: ToneSet(
            primary:   [2, 6, 9],       // 9, #11, 13（b7已为和弦音）
            altered:   [],
            avoidTones: [5]             // 11避用(与#5冲突)
        ),
        .sus: ToneSet(
            primary:   [2, 5, 9],       // 9, 11, 13
            altered:   [],
            avoidTones: [4]             // 3避用(sus无三音)
        ),
        .unknown: ToneSet(
            primary:   [2, 5, 9],       // 默认: maj7延伸
            altered:   [],
            avoidTones: []
        )
    ]

    // MARK: - 查询入口

    /// 获取指定和弦族的所有可用延伸音(含alter)
    static func tonesFor(_ family: ChordFamily) -> [Int] {
        guard let set = families[family] else {
            return families[.unknown]!.primary
        }
        return set.primary + set.altered
    }

    /// 仅获取安全延伸音(不含alter)
    static func primaryTonesFor(_ family: ChordFamily) -> [Int] {
        families[family]?.primary ?? families[.unknown]!.primary
    }

    /// 获取避用音
    static func avoidTonesFor(_ family: ChordFamily) -> [Int] {
        families[family]?.avoidTones ?? []
    }
}
