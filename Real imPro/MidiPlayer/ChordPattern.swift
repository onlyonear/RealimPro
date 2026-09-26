import Foundation


enum ChordNoteType {
    case chord      // 弹奏和弦 (voicing)
    case rest       // 休止
}

struct ChordElement {
    var onsetSlots: Int         // 起始 slot (相对 Pattern 起始)
    var durationSlots: Int      // 持续时长
    var velocity: UInt8 = 80
    var noteType: ChordNoteType = .chord
}

// MARK: - ChordPattern 钢琴伴奏 Pattern
// 对应 Java ChordPattern — 一小节内的和弦节奏模式

class ChordPattern: Pattern {
    var elements: [ChordElement] = []
    
    override var durationSlots: Int {
        elements.map { $0.onsetSlots + $0.durationSlots }.max() ?? 480
    }
}

// MARK: - 加权模式池: swing.sty 原版克制铺底
extension ChordPattern {
    
    private static let patternPool: [(factory: () -> ChordPattern, weight: Float)] = [
        (longPad,       50),   // 经典铺底, 80%克制
        (oneAndFour,    30),   // 二四拍呼吸
        (charleston,    15),   // 现代切分调剂, 20%灵动
        (theJab,         5),   // 跨小节提前
    ]
    
    static func basicSwing() -> ChordPattern {
        let totalWeight = patternPool.reduce(0) { $0 + $1.weight }
        let r = Float.random(in: 0..<totalWeight)
        var accum: Float = 0
        for (factory, w) in patternPool {
            accum += w
            if r < accum { return factory() }
        }
        return longPad()
    }
    
    // MARK: - 4种来自 swing.sty 的 Comping 节奏 (480 slots/小节)
    
    /// longPad: 第1拍正拍按下, 持续420 slots (3.5拍), 留60休止
    /// 对齐原版: X2+4+8 R8
    static func longPad() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 0,   durationSlots: 420, velocity: 75, noteType: .chord))
        return cp
    }
    
    /// oneAndFour: 第1拍正拍按 240slots → 第4拍正拍按 120slots (vel 90)
    /// 对齐原版: X2 R4 V90 X4
    static func oneAndFour() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 0,   durationSlots: 240, velocity: 75, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 360, durationSlots: 120, velocity: 90, noteType: .chord))
        return cp
    }
    
    /// Charleston: 1拍反(74, 46slots) + 2拍反(194, 166slots → 延音到第4拍前)
    /// 对齐原版: X1+1+1+1 (push 8/3) 的简化拆分
    static func charleston() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 74,  durationSlots: 46,  velocity: 78, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 194, durationSlots: 166, velocity: 82, noteType: .chord))
        return cp
    }
    
    /// theJab: 极度稀疏, 仅第4拍反拍 (434, 46slots, vel 95)
    /// 对齐原版: push 跨小节前刺戳
    static func theJab() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 434, durationSlots: 46, velocity: 95, noteType: .chord))
        return cp
    }
}

// MARK: - weightedRandom helper
private func weightedRandom<T>(pool: [(factory: () -> T, weight: Float)]) -> T {
    let totalWeight = pool.reduce(0) { $0 + $1.weight }
    var r = Float.random(in: 0..<totalWeight)
    for item in pool {
        if r < item.weight { return item.factory() }
        r -= item.weight
    }
    return pool[0].factory()
}

// MARK: - Ballad 模式池
extension ChordPattern {

    private static let balladPool: [(factory: () -> ChordPattern, weight: Float)] = [
        (balladWhole,        7.0),  // X4: 全音符铺底 (权重7)
        (balladHalf,         7.0),  // X2: 二分音符 (权重7)
        (balladQuarter,      7.0),  // X1: 四分音符点缀 (权重7)
        (balladBeat1And2,    0.0),  // X1+1: 1、2拍各按一下 (权重7)
        (balladBeat1And3,    7.0),  // X1+2: 1、3拍各按一下 (权重7)
        (balladArpeggio,     0.0),  // 稀疏琶音: 两声轻柔击打
        (balladRest,         3.0),  // 整小节静音 (呼吸)
    ]

    static func ballad() -> ChordPattern {
        return weightedRandom(pool: balladPool)
    }

    /// X4: 全音铺底 (onset=0, dur=480, vel=65)
    static func balladWhole() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 0, durationSlots: 480, velocity: 60, noteType: .chord))
        return cp
    }

    /// X2: 二分音 (onset=0, dur=240, vel=60)
    static func balladHalf() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 0, durationSlots: 240, velocity: 60, noteType: .chord))
        return cp
    }

    /// X1: 四分音点缀 (onset=0, dur=120, vel=55)
    static func balladQuarter() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 0, durationSlots: 120, velocity: 55, noteType: .chord))
        return cp
    }

    /// X1+1: 1、2拍重音
    static func balladBeat1And2() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 0,   durationSlots: 120, velocity: 65, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 120, durationSlots: 360, velocity: 55, noteType: .chord))
        return cp
    }

    /// X1+2: 1、3拍重音
    static func balladBeat1And3() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 0,   durationSlots: 240, velocity: 65, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 240, durationSlots: 240, velocity: 55, noteType: .chord))
        return cp
    }

    /// 稀疏琶音: 两声轻柔击打 + 休止
    static func balladArpeggio() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 0,   durationSlots: 120, velocity: 50, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 180, durationSlots: 120, velocity: 43, noteType: .chord))
        return cp
    }

    /// 完整休止 (呼吸小节)
    static func balladRest() -> ChordPattern {
        return ChordPattern()
    }
}

// MARK: - Blues/Shuffle 模式池 (aligning shuffle.sty)
extension ChordPattern {
    
    private static let bluesPool: [(factory: () -> ChordPattern, weight: Float)] = [
        (bluesSyncopated,   1.0),
        (bluesHalf,         5.0),
        (bluesSparseOffbeat, 5.0),
    ]
    
    static func blues() -> ChordPattern {
        return weightedRandom(pool: bluesPool)
    }
    
    static func bluesHalf() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 0, durationSlots: 240, velocity: 75, noteType: .chord))
        return cp
    }
    
    static func bluesSparseOffbeat() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 0,   durationSlots: 120, velocity: 60, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 240, durationSlots: 120, velocity: 60, noteType: .chord))
        return cp
    }
    /// 切分对位: 正拍120 + 反拍40 (200/440 punch)
    static func bluesSyncopated() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 0,   durationSlots: 120, velocity: 70, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 200, durationSlots: 40,  velocity: 60, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 240, durationSlots: 120, velocity: 70, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 440, durationSlots: 40,  velocity: 60, noteType: .chord))
        return cp
    }
}

// MARK: - Latin 模式池 (Montuno 切分)
extension ChordPattern {
    
    private static let latinPool: [(factory: () -> ChordPattern, weight: Float)] = [
        (latinMontunoSyncopated, 5.0),
        (latinMontuno1,          2.0),
    ]
    
    static func latin() -> ChordPattern {
        return weightedRandom(pool: latinPool)
    }
    
    /// Montuno Syncopated: 齿轮咬合 — 避开贝斯正拍，反拍交错
    static func latinMontunoSyncopated() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 60,  durationSlots: 120, velocity: 80, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 180, durationSlots: 60,  velocity: 85, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 300, durationSlots: 120, velocity: 80, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 420, durationSlots: 60,  velocity: 80, noteType: .chord))
        return cp
    }
    
    /// X4+8 X8 X2: 0/180/240
    static func latinMontuno1() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 0,   durationSlots: 180, velocity: 80, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 180, durationSlots: 60,  velocity: 85, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 240, durationSlots: 240, velocity: 75, noteType: .chord))
        return cp
    }
    
    /// 多切分点缀
    static func latinMontuno2() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 60,  durationSlots: 120, velocity: 75, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 180, durationSlots: 60,  velocity: 85, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 240, durationSlots: 120, velocity: 75, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 360, durationSlots: 120, velocity: 80, noteType: .chord))
        return cp
    }
}

// MARK: - Waltz 模式池 (3/4, 360 slots)
extension ChordPattern {
    
    private static let waltzPool: [(factory: () -> ChordPattern, weight: Float)] = [
        (waltzFull,   5.0),
        (waltzDotted, 2.0),
    ]
    
    static func waltz() -> ChordPattern {
        return weightedRandom(pool: waltzPool)
    }
    
    /// X2 X4: 二分 + 四分
    static func waltzFull() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 0,   durationSlots: 240, velocity: 65, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 240, durationSlots: 120, velocity: 75, noteType: .chord))
        return cp
    }
    
    /// X2.: 附点二分
    static func waltzDotted() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 0, durationSlots: 360, velocity: 70, noteType: .chord))
        return cp
    }
}

// MARK: - Bossa Nova 模式池 (切分同步 SideStick)
extension ChordPattern {
    
    private static let bossaPool: [(factory: () -> ChordPattern, weight: Float)] = [
        (bossaSyncopated, 4.0),
        (bossaOffbeat,    5.0),
    ]
    
    static func bossa() -> ChordPattern {
        return weightedRandom(pool: bossaPool)
    }
    
    /// 咬合 SideStick: onset=0/180/300/420, dur=90, vel=75
    static func bossaSyncopated() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 0,   durationSlots: 120, velocity: 68, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 180, durationSlots: 60,  velocity: 63, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 240, durationSlots: 120, velocity: 68, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 420, durationSlots: 60,  velocity: 63, noteType: .chord))
        return cp
    }
    
    /// 反拍点缀: onset=60/240/360, dur=90, vel=70
    static func bossaOffbeat() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 60,  durationSlots: 90, velocity: 65, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 240, durationSlots: 90, velocity: 65, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 360, durationSlots: 90, velocity: 65, noteType: .chord))
        return cp
    }
    
    /// 极简铺底: onset=0, dur=480, vel=55
    static func bossaPad() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 0, durationSlots: 480, velocity: 55, noteType: .chord))
        return cp
    }
}

// MARK: - Afro 模式池
extension ChordPattern {
    private static let afroPool: [(factory: () -> ChordPattern, weight: Float)] = [
        (afroChord,      5.0),
        (afroChordLight, 2.0),
    ]
    
    static func afro() -> ChordPattern {
        return weightedRandom(pool: afroPool)
    }
    
    static func afroChord() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 0,   durationSlots: 120, velocity: 65, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 160, durationSlots: 40,  velocity: 70, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 240, durationSlots: 120, velocity: 65, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 400, durationSlots: 40, velocity: 70, noteType: .chord))
        return cp
    }

    static func afroChordLight() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 0,   durationSlots: 120, velocity: 62, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 320, durationSlots: 40,  velocity: 58, noteType: .chord))
        return cp
    }
}
