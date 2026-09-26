import Foundation
// MARK: - BassElement 贝斯 Pattern 元素
// 对应 Java BassPatternElement — 相对和弦度的音符定义
// BassNoteType 定义在 AccompanimentModels.swift
/// 一个贝斯音符元素: 音类型 + 时值 + 音域方向
struct BassElement {
    var noteType: BassNoteType
    var durationSlots: Int      // 持续时长 (slots)
    var onsetSlots: Int = 0     // 相对起始位置 (自动累计)
    var velocity: UInt8 = 90
    var chromaticOffset: Int = 0  // X 类型的半音偏移 (+1 上行半音, -1 下行)
    var minMidi: UInt8 = 28     // E1 — 贝斯最低音
    var maxMidi: UInt8 = 55     // G3 — 贝斯最高音
}
// MARK: - BassPattern 贝斯 Pattern
// 对应 Java BassPattern — 一小节内的贝斯节奏/音高模式
class BassPattern: Pattern {
    var elements: [BassElement] = []
    override var durationSlots: Int {
        elements.map { $0.onsetSlots + $0.durationSlots }.max() ?? 480
    }
}
// MARK: - weightedRandom helper
private func weightedRandomBass<T>(pool: [(factory: () -> T, weight: Float)]) -> T {
    let totalWeight = pool.reduce(0) { $0 + $1.weight }
    var r = Float.random(in: 0..<totalWeight)
    for item in pool {
        if r < item.weight { return item.factory() }
        r -= item.weight
    }
    return pool[0].factory()
}

// MARK: - Ballad 模式池
extension BassPattern {
    private static let balladPool: [(factory: () -> BassPattern, weight: Float)] = [
        (balladDottedChordApproach, 10.0),
        (balladWholeRoot,           10.0),
        (balladRootFifth,           10.0),
        (balladDottedChordRest,      8.0),
    ]

    static func ballad() -> BassPattern {
        return weightedRandomBass(pool: balladPool)
    }

    /// 根据风格名动态选取 pattern（供 BassPatternExtractor 按小节随机化）
    static func forStyle(_ style: String) -> BassPattern {
        switch style.lowercased() {
        case "ballad":  return ballad()
        case "blues", "shuffle": return blues()
        case "bossa":   return bossa()
        case "waltz":   return waltz()
        case "latin":   return latin()
        case "afro":    return afro()
        default:        return basicSwing()
        }
    }

    /// B4. R8 C4 A4 (w=10): 附点根音 + 八分休 + 四分五音 + 四分趋近
    static func balladDottedChordApproach() -> BassPattern {
        let bp = BassPattern()
        var c = 0
        bp.elements.append(BassElement(noteType: .bass,     durationSlots: 180, onsetSlots: c, velocity: 68)); c += 180
        bp.elements.append(BassElement(noteType: .rest,     durationSlots: 60,  onsetSlots: c));              c += 60
        bp.elements.append(BassElement(noteType: .fifth,    durationSlots: 120, onsetSlots: c, velocity: 65)); c += 120
        bp.elements.append(BassElement(noteType: .approach, durationSlots: 120, onsetSlots: c, velocity: 65))
        return bp
    }

    /// B4 (w=10): 全音根音铺底
    static func balladWholeRoot() -> BassPattern {
        let bp = BassPattern()
        bp.elements.append(BassElement(noteType: .bass, durationSlots: 480, onsetSlots: 0, velocity: 68))
        return bp
    }

    /// Root + Fifth: 根音二分 + 五音二分
    static func balladRootFifth() -> BassPattern {
        let bp = BassPattern()
        bp.elements = [
            BassElement(noteType: .bass, durationSlots: 240, onsetSlots: 0, velocity: 68),
            BassElement(noteType: .fifth, durationSlots: 240, onsetSlots: 240, velocity: 65),
        ]
        return bp
    }

    /// B4. R8 C4. R8 (w=8): 附点根音 + 八分休 + 附点五音 + 八分休
    static func balladDottedChordRest() -> BassPattern {
        let bp = BassPattern()
        var c = 0
        bp.elements.append(BassElement(noteType: .bass,  durationSlots: 180, onsetSlots: c, velocity: 68)); c += 180
        bp.elements.append(BassElement(noteType: .rest,  durationSlots: 60,  onsetSlots: c));              c += 60
        bp.elements.append(BassElement(noteType: .fifth, durationSlots: 180, onsetSlots: c, velocity: 65)); c += 180
        bp.elements.append(BassElement(noteType: .rest,  durationSlots: 60,  onsetSlots: c))
        return bp
    }

    /// B4. A8 (w=7): 附点根音 + 八分趋近
    static func balladDottedApproach() -> BassPattern {
        let bp = BassPattern()
        var c = 0
        bp.elements.append(BassElement(noteType: .bass,     durationSlots: 180, onsetSlots: c, velocity: 68)); c += 180
        bp.elements.append(BassElement(noteType: .approach, durationSlots: 60,  onsetSlots: c, velocity: 65)); c += 60
        bp.elements.append(BassElement(noteType: .rest,     durationSlots: 240, onsetSlots: c))
        return bp
    }
}
// MARK: - Blues/Shuffle 模式池
extension BassPattern {
    private static let bluesPool: [(factory: () -> BassPattern, weight: Float)] = [
        (shuffleFullRoot,         10.0),  // B8 R8 ×4: 四拍全根 (权重10)
        (shuffleHalfRoot,          8.0),  // B8 R8 ×2: 前半根音 (权重8)
        (shuffleRootFifth,         5.0),  // B8 R8 (5)8 R8: 根+五音稀疏 (权重5)
        (shuffleRootFifthSeventh,  4.0),  // 根+五+b7 线 (权重4)
        (shuffleRootThirdFifth,    2.0),  // 根+三+五+三 线 (权重2)
    ]

    static func blues() -> BassPattern {
        return weightedRandomBass(pool: bluesPool)
    }

    /// B8 R8 ×4 (w=10): 四拍根音 + 反拍休止
    static func shuffleFullRoot() -> BassPattern {
        let bp = BassPattern()
        let onsets = [0,120,240,360]
        for o in onsets {
            bp.elements.append(BassElement(noteType: .bass, durationSlots: 80, onsetSlots: o, velocity: 75))
            bp.elements.append(BassElement(noteType: .rest, durationSlots: 40, onsetSlots: o+80))
        }
        return bp
    }

    /// B8 R8 ×2 (w=8): 前半两根音 + 后半沉静
    static func shuffleHalfRoot() -> BassPattern {
        let bp = BassPattern()
        bp.elements.append(BassElement(noteType: .bass, durationSlots: 80, onsetSlots: 0,   velocity: 75))
        bp.elements.append(BassElement(noteType: .rest, durationSlots: 40, onsetSlots: 80))
        bp.elements.append(BassElement(noteType: .bass, durationSlots: 80, onsetSlots: 120, velocity: 75))
        bp.elements.append(BassElement(noteType: .rest, durationSlots: 280, onsetSlots: 200))
        return bp
    }

    /// B8 R8 (X5)8 R8 (w=5): 根音 + 五音 + 休
    static func shuffleRootFifth() -> BassPattern {
        let bp = BassPattern()
        bp.elements.append(BassElement(noteType: .bass,  durationSlots: 80, onsetSlots: 0,   velocity: 75))
        bp.elements.append(BassElement(noteType: .rest,  durationSlots: 40, onsetSlots: 80))
        bp.elements.append(BassElement(noteType: .fifth, durationSlots: 80, onsetSlots: 120, velocity: 72))
        bp.elements.append(BassElement(noteType: .rest,  durationSlots: 280, onsetSlots: 200))
        return bp
    }

    /// B+5+b7+B+B (w=4): 根｜五｜b7→根线
    static func shuffleRootFifthSeventh() -> BassPattern {
        let bp = BassPattern()
        bp.elements.append(BassElement(noteType: .bass,    durationSlots: 80, onsetSlots: 0,   velocity: 75))
        bp.elements.append(BassElement(noteType: .rest,    durationSlots: 40, onsetSlots: 80))
        bp.elements.append(BassElement(noteType: .fifth,   durationSlots: 80, onsetSlots: 120, velocity: 72))
        bp.elements.append(BassElement(noteType: .seventh, durationSlots: 40, onsetSlots: 200, velocity: 75))
        bp.elements.append(BassElement(noteType: .bass,    durationSlots: 80, onsetSlots: 240, velocity: 75))
        bp.elements.append(BassElement(noteType: .rest,    durationSlots: 40, onsetSlots: 320))
        bp.elements.append(BassElement(noteType: .bass,    durationSlots: 80, onsetSlots: 360, velocity: 75))
        bp.elements.append(BassElement(noteType: .rest,    durationSlots: 40, onsetSlots: 440))
        return bp
    }

    /// B+3+5+3 (w=2): 根｜三｜五｜三线
    static func shuffleRootThirdFifth() -> BassPattern {
        let bp = BassPattern()
        bp.elements.append(BassElement(noteType: .bass,   durationSlots: 80, onsetSlots: 0,   velocity: 75))
        bp.elements.append(BassElement(noteType: .rest,   durationSlots: 40, onsetSlots: 80))
        bp.elements.append(BassElement(noteType: .third,  durationSlots: 80, onsetSlots: 120, velocity: 72))
        bp.elements.append(BassElement(noteType: .rest,   durationSlots: 40, onsetSlots: 200))
        bp.elements.append(BassElement(noteType: .fifth,  durationSlots: 80, onsetSlots: 240, velocity: 72))
        bp.elements.append(BassElement(noteType: .rest,   durationSlots: 40, onsetSlots: 320))
        bp.elements.append(BassElement(noteType: .third,  durationSlots: 80, onsetSlots: 360, velocity: 72))
        bp.elements.append(BassElement(noteType: .rest,   durationSlots: 40, onsetSlots: 440))
        return bp
    }
}
// MARK: - Latin 模式池 (古巴 Tumbao 180-120-120-60)
extension BassPattern {
    private static let latinPool: [(factory: () -> BassPattern, weight: Float)] = [
        (latinTumbao1, 5.0),
        (latinTumbao2, 2.0),
    ]
    static func latin() -> BassPattern {
        return weightedRandomBass(pool: latinPool)
    }
    /// B4+8 (X 5 4) B4 A8: 180-120-120-60
    static func latinTumbao1() -> BassPattern {
        let bp = BassPattern()
        bp.elements.append(BassElement(noteType: .bass,  durationSlots: 180, onsetSlots: 0,   velocity: 78))
        bp.elements.append(BassElement(noteType: .fifth, durationSlots: 60,  onsetSlots: 180, velocity: 80))
        bp.elements.append(BassElement(noteType: .fifth, durationSlots: 240, onsetSlots: 240, velocity: 78))
        return bp
    }
    /// 简化变体: 180-180-120
    static func latinTumbao2() -> BassPattern {
        let bp = BassPattern()
        bp.elements.append(BassElement(noteType: .bass,  durationSlots: 180, onsetSlots: 0,   velocity: 78))
        bp.elements.append(BassElement(noteType: .fifth, durationSlots: 180, onsetSlots: 180, velocity: 80))
        bp.elements.append(BassElement(noteType: .bass,  durationSlots: 120, onsetSlots: 360, velocity: 78))
        return bp
    }
}
// MARK: - Waltz 模式池 (3/4, 360 slots)
extension BassPattern {
    private static let waltzPool: [(factory: () -> BassPattern, weight: Float)] = [
        (waltzDottedRoot, 5.0),
        (waltzRootFifth,  2.0),
    ]
    static func waltz() -> BassPattern {
        return weightedRandomBass(pool: waltzPool)
    }
    /// B2.: 附点二分根音
    static func waltzDottedRoot() -> BassPattern {
        let bp = BassPattern()
        bp.elements.append(BassElement(noteType: .bass, durationSlots: 360, onsetSlots: 0, velocity: 80))
        return bp
    }
    /// B2 C4: 二分根 + 四分五
    static func waltzRootFifth() -> BassPattern {
        let bp = BassPattern()
        bp.elements.append(BassElement(noteType: .bass,  durationSlots: 240, onsetSlots: 0,   velocity: 80))
        bp.elements.append(BassElement(noteType: .fifth, durationSlots: 120, onsetSlots: 240, velocity: 75))
        return bp
    }
    /// (X 5 2+32) B4: 二分五 + 四分根
    static func waltzFifthRoot() -> BassPattern {
        let bp = BassPattern()
        bp.elements.append(BassElement(noteType: .fifth, durationSlots: 240, onsetSlots: 0,   velocity: 75))
        bp.elements.append(BassElement(noteType: .bass,  durationSlots: 120, onsetSlots: 240, velocity: 80))
        return bp
    }
}
// MARK: - Bossa Nova 模式池 (60/60 平直, 180-60-180-60 切分)
extension BassPattern {
    private static let bossaPool: [(factory: () -> BassPattern, weight: Float)] = [
        (bossaBasic,   5.0),
        (bossaFifthUp, 2.0),
    ]
    static func bossa() -> BassPattern {
        return weightedRandomBass(pool: bossaPool)
    }
    /// root(X5) / root / fifth / fifth
    static func bossaBasic() -> BassPattern {
        let bp = BassPattern()
        bp.elements.append(BassElement(noteType: .bass,   durationSlots: 180, onsetSlots: 0,   velocity: 78))
        bp.elements.append(BassElement(noteType: .bass,   durationSlots: 60,  onsetSlots: 180, velocity: 40))
        bp.elements.append(BassElement(noteType: .fifth,  durationSlots: 180, onsetSlots: 240, velocity: 75))
        bp.elements.append(BassElement(noteType: .fifth,  durationSlots: 60,  onsetSlots: 420, velocity: 40))
        return bp
    }
    /// root / fifth (up) / root / approach
    static func bossaFifthUp() -> BassPattern {
        let bp = BassPattern()
        bp.elements.append(BassElement(noteType: .bass,     durationSlots: 180, onsetSlots: 0,   velocity: 78))
        bp.elements.append(BassElement(noteType: .fifth,    durationSlots: 60,  onsetSlots: 180, velocity: 60))
        bp.elements.append(BassElement(noteType: .bass,     durationSlots: 180, onsetSlots: 240, velocity: 75))
        bp.elements.append(BassElement(noteType: .approach, durationSlots: 60,  onsetSlots: 420, velocity: 68))
        return bp
    }
    /// B2 + C2: 二分根-五分
    static func bossaHalf() -> BassPattern {
        let bp = BassPattern()
        bp.elements.append(BassElement(noteType: .bass,  durationSlots: 240, onsetSlots: 0,   velocity: 75))
        bp.elements.append(BassElement(noteType: .fifth, durationSlots: 240, onsetSlots: 240, velocity: 75))
        return bp
    }
}
// MARK: - Swing 模式
extension BassPattern {
    /// 爵士 Walking Bass (4拍全音符, 根→三→五→趋近)
    static func basicSwing() -> BassPattern {
        let bp = BassPattern()
        var cursor = 0
        // 拍1: 根音 (120 slots)
        bp.elements.append(BassElement(noteType: .bass, durationSlots: 120, onsetSlots: cursor)); cursor += 120
        // 拍2: 三度音 (120 slots)
        bp.elements.append(BassElement(noteType: .third, durationSlots: 120, onsetSlots: cursor)); cursor += 120
        // 拍3: 五度音 (120 slots)
        bp.elements.append(BassElement(noteType: .fifth, durationSlots: 120, onsetSlots: cursor)); cursor += 120
        // 拍4: 半音趋近音
        bp.elements.append(BassElement(noteType: .approach, durationSlots: 120, onsetSlots: cursor,
                                        velocity: 85))
        return bp
    }
}

// MARK: - Afro 模式池 (12/8 triplet grid, 40 slots)
extension BassPattern {
    private static let afroPool: [(factory: () -> BassPattern, weight: Float)] = [
        (afroBass,      5.0),
        (afroBassLight, 2.0),
    ]
    
    static func afro() -> BassPattern {
        return weightedRandomBass(pool: afroPool)
    }
    
    static func afroBass() -> BassPattern {
        let bp = BassPattern()
        bp.elements.append(BassElement(noteType: .bass,     durationSlots: 80, onsetSlots: 0,   velocity: 85))
        bp.elements.append(BassElement(noteType: .bass,     durationSlots: 40, onsetSlots: 80,  velocity: 75))
        bp.elements.append(BassElement(noteType: .fifth,    durationSlots: 80, onsetSlots: 160, velocity: 80))
        bp.elements.append(BassElement(noteType: .bass,     durationSlots: 80, onsetSlots: 240, velocity: 85))
        bp.elements.append(BassElement(noteType: .approach, durationSlots: 80, onsetSlots: 320, velocity: 75))
        bp.elements.append(BassElement(noteType: .fifth,    durationSlots: 80, onsetSlots: 400, velocity: 80))
        return bp
    }

    static func afroBassLight() -> BassPattern {
        let bp = BassPattern()
        bp.elements.append(BassElement(noteType: .bass,  durationSlots: 80, onsetSlots: 0,   velocity: 75))
        bp.elements.append(BassElement(noteType: .rest,  durationSlots: 40, onsetSlots: 80))
        bp.elements.append(BassElement(noteType: .bass,  durationSlots: 80, onsetSlots: 160, velocity: 75))
        bp.elements.append(BassElement(noteType: .fifth, durationSlots: 80, onsetSlots: 240, velocity: 72))
        bp.elements.append(BassElement(noteType: .rest,  durationSlots: 200, onsetSlots: 320))
        return bp
    }
}
