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

    /// 对齐 Java `(push 8/3)`：整句提前量(slot)。只在「该小节第一个片段、且为新抽句型开头」时生效一次。
    /// 8/3 = 八分三连音 = 40 slots。目前仅 swing 的 4 小节长铺底句使用。
    var pushSlots: Int = 0

    /// 句型规则的总时长(slot，含尾部休止、也允许 > 一小节用于跨小节)。
    /// 0 时退回按最后一个 element 结尾推算（旧行为，供其余 5 种整小节风格使用）。
    var patternLengthSlots: Int = 0

    override var durationSlots: Int {
        if patternLengthSlots > 0 { return patternLengthSlots }
        return elements.map { $0.onsetSlots + $0.durationSlots }.max() ?? 480
    }
}

// MARK: - 加权模式池: swing.sty 原版克制铺底
extension ChordPattern {
    
    // 对齐 swing.sty 原版三句权重 50 / 30 / 10（总和 90，与原版一致；加权随机不要求满 100）
    private static let patternPool: [(factory: () -> ChordPattern, weight: Float)] = [
        (longPad,       50),   // X2+4+8 R8 经典铺底
        (oneAndFour,    30),   // X2 R4 V90 X4 二四拍呼吸
        (heldFourBars,  10),   // X1+1+1+1 (push 8/3) 连续4小节正拍铺底、第一下抢拍
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
    
    // MARK: - 3种来自 swing.sty 的 Comping 节奏 (480 slots/小节)
    
    /// longPad: 第1拍正拍按下, 持续420 slots (3.5拍), 留60休止
    /// 对齐原版: X2+4+8 R8（规则总长 480，尾部 60 休止）
    static func longPad() -> ChordPattern {
        let cp = ChordPattern()
        cp.patternLengthSlots = 480
        cp.elements.append(ChordElement(onsetSlots: 0,   durationSlots: 420, velocity: 75, noteType: .chord))
        return cp
    }
    
    /// oneAndFour: 第1拍正拍按 240slots → 第4拍正拍按 120slots。
    /// 对齐原版: X2 R4 V90 X4（规则总长 480）。原版第一击满力度、第二击前标 V90(=127 的 0.71)，
    /// 即「前重后轻」的句尾呼吸；这里第一击 74、第二击 53(≈74×0.71) 复刻同一相对关系（再经全局钢琴增益）。
    static func oneAndFour() -> ChordPattern {
        let cp = ChordPattern()
        cp.patternLengthSlots = 480
        cp.elements.append(ChordElement(onsetSlots: 0,   durationSlots: 240, velocity: 74, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 360, durationSlots: 120, velocity: 53, noteType: .chord))
        return cp
    }

    /// heldFourBars: 对齐原版 X1+1+1+1（数字 1=全音符=480，四句相加=1920=4 小节）+ (push 8/3=40)。
    /// 跨小节时间线会把这一个长音按小节切成 4 段：连续 4 小节每小节正拍铺一个，第一下整体提前 40 抢拍；
    /// 后 3 小节由 residual 延续、不再随机抽句型，形成原版那种「锁定 4 小节的稳定铺底」。
    static func heldFourBars() -> ChordPattern {
        let cp = ChordPattern()
        cp.patternLengthSlots = 1920   // 4 小节 × 480
        cp.pushSlots = 40              // push 8/3（八分三连音）
        cp.elements.append(ChordElement(onsetSlots: 0, durationSlots: 1920, velocity: 78, noteType: .chord))
        return cp
    }

    // MARK: - 以下两句为旧的「固定位置近似」实现，2026-09-05 起被 heldFourBars 取代、封存不进池。
    // 若听感想切回旧的切分近似，把上面 patternPool 的 heldFourBars 换回这两句即可（代码保留勿删）。
//    static func charleston() -> ChordPattern {
//        let cp = ChordPattern()
//        cp.elements.append(ChordElement(onsetSlots: 74,  durationSlots: 46,  velocity: 78, noteType: .chord))
//        cp.elements.append(ChordElement(onsetSlots: 194, durationSlots: 166, velocity: 82, noteType: .chord))
//        return cp
//    }
//    static func theJab() -> ChordPattern {
//        let cp = ChordPattern()
//        cp.elements.append(ChordElement(onsetSlots: 434, durationSlots: 46, velocity: 95, noteType: .chord))
//        return cp
//    }
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
// 原版 ballad.sty 力度档位（V 记号）：四分音符及更长一律 V90（统一基准）、八分 V50、十六分 V40 —— 音越短越轻。
// 本池现有句型最短只到四分，故全部击弦统一到同一基准 62（再经全局钢琴增益）；
// 若日后加入八分/十六分句型，按 八分≈48 / 十六分≈40 分档即可对齐原版层次。
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

    /// X4: 全音铺底 (onset=0, dur=480) —— 原版 V90 统一基准
    static func balladWhole() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 0, durationSlots: 480, velocity: 62, noteType: .chord))
        return cp
    }

    /// X2: 二分音 (onset=0, dur=240) —— 原版 V90 统一基准
    static func balladHalf() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 0, durationSlots: 240, velocity: 62, noteType: .chord))
        return cp
    }

    /// X1: 四分音点缀 (onset=0, dur=120) —— 原版 V90 统一基准
    static func balladQuarter() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 0, durationSlots: 120, velocity: 62, noteType: .chord))
        return cp
    }

    /// X1+1: 1、2拍（均为四分，原版同属 V90，两声等响）
    static func balladBeat1And2() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 0,   durationSlots: 120, velocity: 62, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 120, durationSlots: 360, velocity: 62, noteType: .chord))
        return cp
    }

    /// X1+2: 1、3拍（均为四分，原版同属 V90，两声等响）
    static func balladBeat1And3() -> ChordPattern {
        let cp = ChordPattern()
        cp.elements.append(ChordElement(onsetSlots: 0,   durationSlots: 240, velocity: 62, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 240, durationSlots: 240, velocity: 62, noteType: .chord))
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

// MARK: - Afro 模式池 (逐句对齐 african.sty，时值经 Java Duration 金标准换算)
extension ChordPattern {
    // 原版权重 2 / 2 / 3 / 4。其中 P2/P4 是半小节(240)句型，由跨小节时间线再抽一句拼满整小节。
    private static let afroPool: [(factory: () -> ChordPattern, weight: Float)] = [
        (afroP1, 2.0),
        (afroP2, 2.0),
        (afroP3, 3.0),
        (afroP4, 4.0),
    ]
    
    static func afro() -> ChordPattern {
        return weightedRandom(pool: afroPool)
    }

    /// african.sty 句1 (weight 2, 整小节): X2+16+32+120+480 R16 X8/3 X16+32+32/3 R8+120+480
    /// 击弦点 0/290、320/40(八分三连音位)、360/55
    static func afroP1() -> ChordPattern {
        let cp = ChordPattern()
        cp.patternLengthSlots = 480
        cp.elements.append(ChordElement(onsetSlots: 0,   durationSlots: 290, velocity: 65, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 320, durationSlots: 40,  velocity: 70, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 360, durationSlots: 55,  velocity: 65, noteType: .chord))
        return cp
    }

    /// african.sty 句2 (weight 2, 半小节 240): X4/3 X4/3 X16+32 R16+120+480
    /// 击弦点 0/80、80/80(两个四分三连音)、160/45
    static func afroP2() -> ChordPattern {
        let cp = ChordPattern()
        cp.patternLengthSlots = 240
        cp.elements.append(ChordElement(onsetSlots: 0,   durationSlots: 80, velocity: 65, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 80,  durationSlots: 80, velocity: 65, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 160, durationSlots: 45, velocity: 70, noteType: .chord))
        return cp
    }

    /// african.sty 句3 (weight 3, 整小节): X2/3+2/3 X8/3 X8/3+32/3 R8+32/3
    /// 击弦点 0/320、320/40、360/50
    static func afroP3() -> ChordPattern {
        let cp = ChordPattern()
        cp.patternLengthSlots = 480
        cp.elements.append(ChordElement(onsetSlots: 0,   durationSlots: 320, velocity: 65, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 320, durationSlots: 40,  velocity: 70, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 360, durationSlots: 50,  velocity: 65, noteType: .chord))
        return cp
    }

    /// african.sty 句4 (weight 4, 半小节 240): R16+120+480 X16/3 R8+120+480 X8+16+32+32/3 X120+480
    /// 击弦点 35/20、120/115、235/5（弱起三连音碎句）
    static func afroP4() -> ChordPattern {
        let cp = ChordPattern()
        cp.patternLengthSlots = 240
        cp.elements.append(ChordElement(onsetSlots: 35,  durationSlots: 20,  velocity: 70, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 120, durationSlots: 115, velocity: 65, noteType: .chord))
        cp.elements.append(ChordElement(onsetSlots: 235, durationSlots: 5,   velocity: 70, noteType: .chord))
        return cp
    }

    // MARK: - 旧 afro 两句（整数拍近似）2026-09-05 起被上面 4 句取代、封存，勿删便于日后 A/B。
//    static func afroChord() -> ChordPattern {
//        let cp = ChordPattern()
//        cp.elements.append(ChordElement(onsetSlots: 0,   durationSlots: 120, velocity: 65, noteType: .chord))
//        cp.elements.append(ChordElement(onsetSlots: 160, durationSlots: 40,  velocity: 70, noteType: .chord))
//        cp.elements.append(ChordElement(onsetSlots: 240, durationSlots: 120, velocity: 65, noteType: .chord))
//        cp.elements.append(ChordElement(onsetSlots: 400, durationSlots: 40,  velocity: 70, noteType: .chord))
//        return cp
//    }
//    static func afroChordLight() -> ChordPattern {
//        let cp = ChordPattern()
//        cp.elements.append(ChordElement(onsetSlots: 0,   durationSlots: 120, velocity: 62, noteType: .chord))
//        cp.elements.append(ChordElement(onsetSlots: 320, durationSlots: 40,  velocity: 58, noteType: .chord))
//        return cp
//    }
}
