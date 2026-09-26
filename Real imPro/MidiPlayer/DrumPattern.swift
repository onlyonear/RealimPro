import Foundation

// MARK: - DrumPatternElement 鼓组元素

struct DrumPatternElement {
    var onsetSlots: Int         // 击打起始 slot (相对 Pattern 起始)
    var durationSlots: Int      // 持续时长 (rest时表示等待时长)
    var velocity: UInt8         // MIDI 力度 0-127
    var isRest: Bool            // true=R休止, false=X击打
}

// MARK: - 标准 MIDI 鼓映射 (General MIDI)
struct DrumKit {
    static let kick: UInt8      = 36   // Bass Drum
    static let snare: UInt8     = 38   // Acoustic Snare
    static let closedHH: UInt8  = 42   // Closed Hi-Hat
    static let openHH: UInt8    = 46   // Open Hi-Hat
    static let ride: UInt8      = 51   // Ride Cymbal 1
    static let crash: UInt8     = 49   // Crash Cymbal 1
    static let highTom: UInt8   = 50   // High Tom
    static let midTom: UInt8    = 47   // Low-Mid Tom
    static let lowTom: UInt8    = 43   // Low Tom (Floor)
    static let pedalHH: UInt8   = 44   // Pedal Hi-Hat
    static let sidestick: UInt8 = 37   // Side Stick
    static let openHiConga: UInt8 = 63 // Open Hi Conga
    static let lowConga: UInt8    = 64 // Low Conga
    static let claves: UInt8     = 75  // Claves
    static let muteHiConga: UInt8 = 62 // Mute Hi Conga
    static let cabasa: UInt8      = 69 // Cabasa
    static let maracas: UInt8     = 70 // Maracas
}

// MARK: - DrumPattern 鼓组 Pattern
// 对应 Java DrumPattern — 包含一组鼓乐器规则的组合

class DrumPattern: Pattern {
    /// 鼓轨定义: 每个乐器一条规则 (音符号 → 击打序列)
    var rules: [DrumRule] = []
    
    override var durationSlots: Int {
        rules.map { $0.totalSlots }.max() ?? 480
    }
}

// MARK: - DrumRule 单乐器规则
// 一个乐器 (如 ride = 51) 在一小节内的击打节奏序列

struct DrumRule {
    let midiNote: UInt8         // MIDI 音符号 (36=kick, 51=ride, 等)
    var elements: [DrumPatternElement] = []
    
    /// 所有元素累计总时长 (slots)
    var totalSlots: Int {
        elements.map { $0.onsetSlots + $0.durationSlots }.max() ?? 480
    }
}

// MARK: - Swing 模式 (basicSwing)
extension DrumPattern {
    static func basicSwing() -> DrumPattern {
        let dp = DrumPattern()
        dp.rules.append(DrumRule(midiNote: DrumKit.ride, elements: [
            element(0,60,80),  element(60,60,55),  element(120,60,80), element(180,60,55),
            element(240,60,80), element(300,60,55), element(360,60,80), element(420,60,55),
        ]))
        return dp
    }
}

// MARK: - Ballad 模式池 (aligning ballad.sty, swing 0.55 → 66/54)
extension DrumPattern {
    
    private static let balladPool: [(factory: () -> DrumPattern, weight: Float)] = [(balladLightSwing, 1.0)]
    
    static func ballad() -> DrumPattern {
        return balladLightSwing()
    }
    
    /// Ride X4 + HH R4: 仅拍1正拍击打 + 2拍轻踩
    static func balladSparse() -> DrumPattern {
        let dp = DrumPattern()
        dp.rules.append(DrumRule(midiNote: DrumKit.ride, elements: [
            DrumPatternElement(onsetSlots: 0, durationSlots: 120, velocity: 60, isRest: false),
        ]))
        dp.rules.append(DrumRule(midiNote: DrumKit.pedalHH, elements: [
            DrumPatternElement(onsetSlots: 0, durationSlots: 120, velocity: 0, isRest: true),
            DrumPatternElement(onsetSlots: 120, durationSlots: 120, velocity: 45, isRest: false),
            DrumPatternElement(onsetSlots: 240, durationSlots: 240, velocity: 0, isRest: true),
        ]))
        return dp
    }
    
    /// Ride X4 X8 X8 + HH R4 X4 R4 X4: 66/54 Swing 全拍 + 2/4 踩镲
    static func balladLightSwing() -> DrumPattern {
        let dp = DrumPattern()
        dp.rules.append(DrumRule(midiNote: DrumKit.ride, elements: [
            DrumPatternElement(onsetSlots: 0,   durationSlots: 66,  velocity: 65, isRest: false),
            DrumPatternElement(onsetSlots: 66,  durationSlots: 54,  velocity: 63, isRest: false),
            DrumPatternElement(onsetSlots: 120, durationSlots: 66,  velocity: 65, isRest: false),
            DrumPatternElement(onsetSlots: 186, durationSlots: 54,  velocity: 63, isRest: false),
            DrumPatternElement(onsetSlots: 240, durationSlots: 66,  velocity: 65, isRest: false),
            DrumPatternElement(onsetSlots: 306, durationSlots: 54,  velocity: 63, isRest: false),
            DrumPatternElement(onsetSlots: 360, durationSlots: 66,  velocity: 65, isRest: false),
            DrumPatternElement(onsetSlots: 426, durationSlots: 54,  velocity: 63, isRest: false),
        ]))
        dp.rules.append(DrumRule(midiNote: DrumKit.pedalHH, elements: [
            DrumPatternElement(onsetSlots: 0,   durationSlots: 120, velocity: 0,  isRest: true),
            DrumPatternElement(onsetSlots: 120, durationSlots: 120, velocity: 50, isRest: false),
            DrumPatternElement(onsetSlots: 240, durationSlots: 120, velocity: 0,  isRest: true),
            DrumPatternElement(onsetSlots: 360, durationSlots: 120, velocity: 50, isRest: false),
        ]))
        return dp
    }
    
    /// R4 X4 X4 X4: 拍2,3,4 正拍击打
    static func balladPad() -> DrumPattern {
        let dp = DrumPattern()
        dp.rules.append(DrumRule(midiNote: DrumKit.ride, elements: [
            DrumPatternElement(onsetSlots: 0,   durationSlots: 120, velocity: 0,  isRest: true),
            DrumPatternElement(onsetSlots: 120, durationSlots: 120, velocity: 60, isRest: false),
            DrumPatternElement(onsetSlots: 240, durationSlots: 120, velocity: 60, isRest: false),
            DrumPatternElement(onsetSlots: 360, durationSlots: 120, velocity: 60, isRest: false),
        ]))
        dp.rules.append(DrumRule(midiNote: DrumKit.pedalHH, elements: [
            DrumPatternElement(onsetSlots: 0,   durationSlots: 120, velocity: 0,  isRest: true),
            DrumPatternElement(onsetSlots: 120, durationSlots: 120, velocity: 45, isRest: false),
            DrumPatternElement(onsetSlots: 240, durationSlots: 120, velocity: 0,  isRest: true),
            DrumPatternElement(onsetSlots: 360, durationSlots: 120, velocity: 45, isRest: false),
        ]))
        return dp
    }
}

// MARK: - weightedRandom helper
private func weightedRandomDrum<T>(pool: [(factory: () -> T, weight: Float)]) -> T {
    let totalWeight = pool.reduce(0) { $0 + $1.weight }
    var r = Float.random(in: 0..<totalWeight)
    for item in pool {
        if r < item.weight { return item.factory() }
        r -= item.weight
    }
    return pool[0].factory()
}

// MARK: - Blues/Shuffle 模式池 (aligning shuffle.sty, swing 0.67 → 80/40)
extension DrumPattern {

    private static let bluesPool: [(factory: () -> DrumPattern, weight: Float)] = [
        (bluesShuffleFull,  8.0),
        (bluesShuffleLight, 3.0),
    ]

    static func blues() -> DrumPattern {
        return weightedRandomDrum(pool: bluesPool)
    }
    
    /// 全阵容: Ride 80/40 shuffle + Snare 2/4 + Kick 1/3
    static func bluesShuffleFull() -> DrumPattern {
        let dp = DrumPattern()
        dp.rules.append(DrumRule(midiNote: DrumKit.ride, elements: [
            element(0,80,65),   element(80,40,50),
            element(120,80,65), element(200,40,50),
            element(240,80,65), element(320,40,50),
            element(360,80,65), element(440,40,50),
        ]))
        dp.rules.append(DrumRule(midiNote: DrumKit.snare, elements: [
            element(80,40,23),
            element(120,80,60),
            element(200,40,23),
            element(320,40,23),
            element(360,80,60),
            element(440,40,23),
        ]))
        dp.rules.append(DrumRule(midiNote: DrumKit.kick, elements: [
            element(0,200,70),
            element(240,240,70),
        ]))
        dp.rules.append(DrumRule(midiNote: DrumKit.pedalHH, elements: [
            element(120,120,50),
            element(360,120,50),
        ]))
        return dp
    }
    
    /// 轻量: Ride shuffle + Kick 1/3, 无 Snare
    static func bluesShuffleLight() -> DrumPattern {
        let dp = DrumPattern()
        dp.rules.append(DrumRule(midiNote: DrumKit.ride, elements: [
            element(0,80,65), element(80,40,50), element(120,80,65), element(200,40,50),
            element(240,80,65), element(320,40,50), element(360,80,65), element(440,40,50),
        ]))
        dp.rules.append(DrumRule(midiNote: DrumKit.kick, elements: [
            element(0,120,80), element(120,120,0,true), element(240,120,80), element(360,120,0,true),
        ]))
        return dp
    }
    
    /// 极简: 仅 Ride shuffle
    static func bluesShuffleHHOnly() -> DrumPattern {
        let dp = DrumPattern()
        dp.rules.append(DrumRule(midiNote: DrumKit.ride, elements: [
            element(0,80,65), element(80,40,45), element(120,80,65), element(200,40,45),
            element(240,80,65), element(320,40,45), element(360,80,65), element(440,40,45),
        ]))
        return dp
    }
    
    /// shuffle-light: HH 密集三连 + Snare 切分 + Kick 二分
    static func bluesLightSnareAccent() -> DrumPattern {
        let dp = DrumPattern()
        dp.rules.append(DrumRule(midiNote: DrumKit.ride, elements: [
            element(0,80,60), element(80,40,45), element(120,80,60), element(200,40,45),
            element(240,80,60), element(320,40,45), element(360,80,60), element(440,40,45),
        ]))
        dp.rules.append(DrumRule(midiNote: DrumKit.snare, elements: [
            element(0,120,0,true), element(120,120,0,true), element(240,120,70), element(360,120,0,true),
        ]))
        dp.rules.append(DrumRule(midiNote: DrumKit.kick, elements: [
            element(0,240,90), element(240,240,90),
        ]))
        return dp
    }
    
    private static func element(_ onset: Int, _ dur: Int, _ vel: UInt8, _ rest: Bool = false) -> DrumPatternElement {
        DrumPatternElement(onsetSlots: onset, durationSlots: dur, velocity: vel, isRest: rest)
    }
}

// MARK: - Latin 模式池 (Tresillo Clave 0/180/360, Conga 360/420, Montuno 切分)
extension DrumPattern {
    
    private static let latinPool: [(factory: () -> DrumPattern, weight: Float)] = [(latinStandard, 1.0)]
    
    static func latin() -> DrumPattern {
        return latinStandard()
    }
    
    /// Latin Standard: Ride 60/60 + SideStick Tresillo(0/180/360) + HighTom Conga(360/420) + Kick
    static func latinStandard() -> DrumPattern {
        let dp = DrumPattern()
        dp.rules.append(DrumRule(midiNote: DrumKit.ride, elements: [
            element(0,60,75),   element(60,60,50),
            element(120,60,65), element(180,60,50),
            element(240,60,75), element(300,60,50),
            element(360,60,65), element(420,60,50),
        ]))
        dp.rules.append(DrumRule(midiNote: DrumKit.sidestick, elements: [
            element(0,60,85), element(180,60,95), element(360,60,85),
        ]))
        dp.rules.append(DrumRule(midiNote: DrumKit.openHiConga, elements: [
            element(360,60,80),
        ]))
        dp.rules.append(DrumRule(midiNote: DrumKit.lowConga, elements: [
            element(420,60,90),
        ]))
        dp.rules.append(DrumRule(midiNote: DrumKit.kick, elements: [
            element(0,240,65), element(240,240,65),
        ]))
        return dp
    }
}

// MARK: - Waltz 模式池 (3/4, 360 slots, Swing 80/40)
extension DrumPattern {
    
    private static let waltzPool: [(factory: () -> DrumPattern, weight: Float)] = [(waltzSwing, 1.0)]
    
    static func waltz() -> DrumPattern {
        return waltzSwing()
    }
    
    /// 3/4 Swing: Ride 80/40 + Kick 0/240
    static func waltzSwing() -> DrumPattern {
        let dp = DrumPattern()
        dp.rules.append(DrumRule(midiNote: DrumKit.ride, elements: [
            DrumPatternElement(onsetSlots: 0, durationSlots: 80, velocity: 63, isRest: false),
            DrumPatternElement(onsetSlots: 80, durationSlots: 40, velocity: 57, isRest: false),
            DrumPatternElement(onsetSlots: 120, durationSlots: 80, velocity: 63, isRest: false),
            DrumPatternElement(onsetSlots: 200, durationSlots: 40, velocity: 57, isRest: false),
            DrumPatternElement(onsetSlots: 240, durationSlots: 80, velocity: 63, isRest: false),
            DrumPatternElement(onsetSlots: 320, durationSlots: 40, velocity: 57, isRest: false),
        ]))
        dp.rules.append(DrumRule(midiNote: DrumKit.kick, elements: [
            DrumPatternElement(onsetSlots: 0, durationSlots: 180, velocity: 68, isRest: false),
            DrumPatternElement(onsetSlots: 180, durationSlots: 60, velocity: 0, isRest: true),
            DrumPatternElement(onsetSlots: 240, durationSlots: 120, velocity: 68, isRest: false),
        ]))
        return dp
    }
}

// MARK: - Bossa 模式池 (SideStick 3-3-2 clavé)
extension DrumPattern {
    
    private static let bossaPool: [(factory: () -> DrumPattern, weight: Float)] = [(bossaStandard, 1.0)]
    
    static func bossa() -> DrumPattern {
        return bossaStandard()
    }
    
    /// Bossa Standard: Ride 60/60 + SideStick 3-3-2 + Kick
    static func bossaStandard() -> DrumPattern {
        let dp = DrumPattern()
        dp.rules.append(DrumRule(midiNote: DrumKit.ride, elements: [
            element(0,60,65),   element(60,60,50),
            element(120,60,60), element(180,60,50),
            element(240,60,65), element(300,60,50),
            element(360,60,60), element(420,60,50),
        ]))
        dp.rules.append(DrumRule(midiNote: DrumKit.claves, elements: [
            element(0,60,80), element(180,60,85), element(360,60,80),
        ]))
        return dp
    }
}

// MARK: - Afro 模式池 (12/8 复合律动, 40 slots 网格)
extension DrumPattern {
    private static let afroPool: [(factory: () -> DrumPattern, weight: Float)] = [(afroStandard, 1.0)]
    
    static func afro() -> DrumPattern {
        return afroStandard()
    }
    
    static func afroStandard() -> DrumPattern {
        let dp = DrumPattern()
        dp.rules.append(DrumRule(midiNote: DrumKit.kick, elements: [
            element(0,120,70), element(120,120,70), element(240,120,70), element(360,120,70),
        ]))
        dp.rules.append(DrumRule(midiNote: DrumKit.closedHH, elements: [
            element(0,40,60), element(40,40,45), element(80,40,55),
            element(120,40,60), element(160,40,45), element(200,40,55),
            element(240,40,60), element(280,40,45), element(320,40,55),
            element(360,40,60), element(400,40,45), element(440,40,55),
        ]))
        dp.rules.append(DrumRule(midiNote: DrumKit.openHiConga, elements: [
            element(0,40,75), element(40,40,70), element(120,40,75), element(160,40,70),
            element(240,40,75), element(320,40,75), element(400,40,70),
        ]))
        dp.rules.append(DrumRule(midiNote: DrumKit.muteHiConga, elements: [
            element(0,120,65), element(120,120,0,true), element(240,120,65), element(360,120,0,true),
        ]))
        dp.rules.append(DrumRule(midiNote: DrumKit.maracas, elements: [
            element(0,40,50), element(40,40,40), element(80,40,45),
            element(120,40,50), element(160,40,40), element(200,40,45),
            element(240,40,50), element(280,40,40), element(320,40,45),
            element(360,40,50), element(400,40,40), element(440,40,45),
        ]))
        return dp
    }
}
