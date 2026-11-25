import Foundation

// MARK: - Constants — 全局常量归集 (P0附加)
// 统一跨文件使用的魔术数字, 消除全工程硬编码

struct Constants {

    // MARK: 时间/节奏常量

    /// 每个节拍的槽位数
    static let slotsPerBeat: Int = 120

    /// 默认BPM
    static let defaultBPM: Double = 120.0

    /// Swing摇摆比值 (2/3 = 0.66)
    static let defaultSwingRatio: Double = 0.66

    // MARK: 音域常量 (MIDI音高)

    /// 最低可用音 (C3)
    static let lowestMidiNote: Int = 48

    /// 最高可用音 (C6)
    static let highestMidiNote: Int = 84

    // MARK: Expectancy评分默认权重

    static let expectancyRootWeight: Double = 1.0
    static let expectancyThirdWeight: Double = 0.9
    static let expectancyFifthWeight: Double = 0.8
    static let expectancySeventhWeight: Double = 0.9
    static let expectancyColorToneWeight: Double = 0.7
    static let expectancyApproachWeight: Double = 0.85
    static let expectancyOutsideTonePenalty: Double = 0.3

    // MARK: MIDI力度常量

    static let midiVelocityDownbeat: UInt8 = 100
    static let midiVelocityOffbeat: UInt8 = 80
    static let midiVelocityPassingTone: UInt8 = 60
}
