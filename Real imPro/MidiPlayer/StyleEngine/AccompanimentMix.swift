import Foundation

// MARK: - P3-c 伴奏混音 / 贝斯音域 校准常量（纯播放·渲染层；不改生成算法与 .sty 资源）
// 乐手版：把移植来的 Java 伴奏与 App 原手写伴奏的音量拉到同一档，再按 Java 原版主次
// （独奏最响、钢琴垫底、贝司/鼓居中）摆位；并把贝司音区沉回传统 walking 区间。
// 真机并听 Java 校准时只需调本文件常量，不必动引擎。
enum AccompanimentMix {

    // ① Java 原版固定通道席位（imp/util/Preferences.java :123-143，值/127 = 线性振幅）
    //    MELODY=127(1.0)  BASS=60(0.472)  DRUMS=60(0.472)  CHORDS=40(0.315)
    static let seatMelody: Float = 127.0 / 127.0   // 1.000 独奏（萨克斯）满席，不做来源归一
    static let seatBass: Float   = 60.0  / 127.0   // 0.472
    static let seatDrum: Float   = 60.0  / 127.0   // 0.472
    static let seatPiano: Float  = 40.0  / 127.0   // 0.315

    // ② 真机校准总旋钮（默认 1.0；某轨整体偏轻/偏响就调这里：>1 提亮，<1 压暗）
    static let trimMelody: Float = 1.0
    static let trimBass: Float   = 1.0
    static let trimDrum: Float   = 1.0
    static let trimPiano: Float  = 1.0

    // ③ 鼓"编制补偿"（振幅倍数，能量乘平方）：.sty 是完整鼓组、手写基准仅单件 Ride，
    //    严格按能量归一会把鼓组压残；故把鼓的目标响度相对手写基准上调。1.4≈+2.9dB，真机定
    //    （鼓残就↑到 1.6，轰/抢戏就↓到 1.2）。
    static let drumEnsembleBoost: Float = 1.4

    // ④ 手写 Simple Swing 参考能量 Σvel²（16 小节 Cmaj7/Am7/Dm7/G7，spm480，种子12345 实测）。
    //    运行时按"每小节平均能量"比较，与曲长无关。
    static let refMeasures: Double = 16
    static let refDrumEnergy: Double = 603200
    static let refBassEnergy: Double = 504400
    static let refPianoEnergy: Double = 312148

    // ⑤ 贝斯音域：覆盖 .sty 文件头普遍的 G2-C4（偏高），回到 Java 引擎内置默认 G1-G3。
    //    Style.java:188 bassLow=g---(G1=31)、:193 bassHigh=g-(G3=55)；.sty 在 load():790-797 覆盖之。
    //    备选更沉的传统四弦 walking 音区 E1-G3：把 bassRangeLow 改为 28（电贝最低空弦 E1）做真机 A/B。
    static let bassRangeLow: Int = 31    // G1
    static let bassRangeHigh: Int = 55   // G3

    // ⑥ [P3-e] 手写伴奏能量归一允许的最大“放大”振幅倍数。手写老 pattern 织体稀疏（鼓单件 Ride、
    //    Shuffle/Bossa 贝斯轻），需放大才能与丰满的 .sty 等响；.sty 仍只压不放(g≤1)。
    //    隔离探针实测保留的三个手写风格最大需求 1.37（Bossa 贝斯），取 1.6 留余量且保证 contentGain<1 不削波；
    //    真机若某手写轨过轰可下调此值，过轻则上调（但不应使任一 contentGain 超过 1）。
    static let handGainCap: Float = 1.6

    // ⑦ [P3-c.2] 手写专属响度补偿（线性振幅倍数，直接乘节点音量；能量变化≈平方）。
    //    真机实测：仅靠 ⑥ 的每小节 Σvel² 能量归一，手写与 .sty 数学等响但听感仍偏弱/空——
    //    手写老 pattern 织体比 .sty 稀 3~11 倍（钢琴音点少、鼓单件 Ride），把少数音拧大≠持续铺满。
    //    故在能量归一之后、节点音量上再给手写三轨一个额外乘区，补偿稀疏织体的听感折损；.sty 不套此乘区。
    //    起始值经隔离探针验证 contentGain 峰值 0.928<1（不削波）；最终以真机并听同族 .sty 定标，
    //    来回切 Simple Shuffle/Afro/Bossa ↔ Java，听感等响即锁定，过响↓、仍弱↑。
    //    钢琴织体最稀（raw 能量比最高达 11 倍）给最大补偿，贝司/鼓次之。
    static let handPianoBoost: Float = 1.6   // 振幅 ×1.6 ≈ +4.1dB
    static let handBassBoost:  Float = 1.3   // 振幅 ×1.3 ≈ +2.3dB
    static let handDrumBoost:  Float = 1.3   // 振幅 ×1.3 ≈ +2.3dB
}
