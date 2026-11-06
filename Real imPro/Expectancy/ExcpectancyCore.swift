import Foundation

// MARK: - 协议抽象：依赖你的现有和弦/音高工具接口（适配你工程，无需强耦合具体类）
protocol ChordPitchLookupProtocol {
    /// 判断是否和弦根音
    static func isRootPitch(_ midi: Int, chordName: String) -> Bool
    /// 判断是否和弦内音（1/3/5/7）
    static func isChordTone(_ midi: Int, chordName: String) -> Bool
    /// 判断是否和弦色彩延伸音（9/11/13等）
    static func isColorTone(_ midi: Int, chordName: String) -> Bool
    /// 判断是否调式自然音阶内音
    static func isScaleTone(_ midi: Int, chordName: String) -> Bool
}

// MARK: - Expectancy 核心结构体（全部静态纯函数，无实例状态，轻量化）
struct ExpectancyCore {
    // MARK:
    /// 八度间隔
    private static let P_OCTAVE = 12
    /// MIDI最低可用音
    private static let A = 21
    /// MIDI最高可用音
    private static let C_EIGHTH = 108
    /// 中央C MIDI
    private static let MIDDLE_C = 60
    /// 低音下限
    private static let LOW_BASS = 24
    
    // 稳定度分级（固定分值）
    private static let STABILITY_ROOT = 6
    private static let STABILITY_CHORD_TONE = 5
    private static let STABILITY_COLOR_TONE = 4
    private static let STABILITY_OUTSIDE = 1
    private static let STABILITY_NO_CHORD = 1
    
    // 邻近度查表：音程距离 0~14 对应权重，数组原样复制
    private static let PROXIMITY_TABLE: [Double] = [
        24, 36, 32, 25, 20, 16, 12, 9, 6, 4, 2, 1, 0.25, 0.02, 0.01
    ]
    // 旋律方向得分表
    private static let DIRECTION_WEIGHTS: [Double] = [
        6, 20, 12, 6, 0, 6, 12, 25, 36, 52, 75
    ]
    // 同音重复衰减系数
    private static let REPEAT_MOBILITY_FACTOR = 0.67
    // 基础权重修正值
    private static let BASE_WEIGHT = 15
    private static let QUARTER_WEIGHT = 5
    // 四分音符slot常量（和你Grammar全局统一）
    static let QUARTER_SLOT = 120
    
    // MARK: 对外总入口：计算单个候选音完整期望值（getExpectancy完整逻辑）
    /// - Parameters:
    ///   - candidatePitch: 待打分候选MIDI音高
    ///   - prevPitch: 上一个音符MIDI
    ///   - prevPrevPitch: 上上一个音符MIDI（用于判断旋律走向）
    ///   - chordName: 当前小节和弦名
    ///   - lookup: 你的和弦音判断工具实现
    /// - Returns: 期望值总分，分值越高旋律越流畅自然
    static func computeExpectancyScore(
        candidatePitch: Int,
        prevPitch: Int,
        prevPrevPitch: Int,
        chordName: String,
        lookup: ChordPitchLookupProtocol.Type
    ) -> Double {
        let stability = calcStability(pitch: candidatePitch, chord: chordName, lookup: lookup)
        let proximity = calcProximity(pitch: candidatePitch, lastPitch: prevPitch)
        let directionScore = calcDirectionScore(newPitch: candidatePitch, p1: prevPitch, p2: prevPrevPitch)
        let mobility = calcMobility(pitch: candidatePitch, lastPitch: prevPitch)
        
        // 核心计算公式
        let total = (Double(stability) * proximity * mobility) + directionScore
        return total
    }
    
    // MARK: 子函数1：音稳定度计算（stability()）
    private static func calcStability(
        pitch: Int,
        chord: String,
        lookup: ChordPitchLookupProtocol.Type
    ) -> Int {
        if chord.isEmpty {
            return STABILITY_NO_CHORD
        }
        if lookup.isRootPitch(pitch, chordName: chord) {
            return STABILITY_ROOT
        } else if lookup.isChordTone(pitch, chordName: chord) {
            return STABILITY_CHORD_TONE
        } else if lookup.isColorTone(pitch, chordName: chord) {
            return STABILITY_COLOR_TONE
        } else {
            return STABILITY_OUTSIDE
        }
    }
    
    // MARK: 子函数2：音邻近度（proximity()）
    private static func calcProximity(pitch: Int, lastPitch: Int) -> Double {
        let distance = abs(pitch - lastPitch)
        if distance >= PROXIMITY_TABLE.count {
            return PROXIMITY_TABLE.last!
        }
        return PROXIMITY_TABLE[distance]
    }
    
    // MARK: 子函数3：旋律方向得分（direction()）
    private static func calcDirectionScore(newPitch: Int, p1: Int, p2: Int) -> Double {
        // 算法逻辑：仅基于前一个音程（p2 → p1）的大小和方向计算
        // 注意：算法未使用当前音newPitch参数，此为固有实现方式
        let intervalSize = abs(p1 - p2)
        let prevDirection = p1 - p2
        
        if intervalSize <= 4 {
            // 小三度以内的小音程：上行得分，下行得0
            if prevDirection < 0 {
                return 0
            } else {
                switch intervalSize {
                case 0: return DIRECTION_WEIGHTS[0]  // 6
                case 1: return DIRECTION_WEIGHTS[1]  // 20
                case 2: return DIRECTION_WEIGHTS[2]  // 12
                case 3: return DIRECTION_WEIGHTS[3]  // 6
                default: return DIRECTION_WEIGHTS[4] // 0
                }
            }
        } else {
            // 纯四度以上的大音程：下行得分，上行得0
            if prevDirection > 0 {
                return 0
            } else {
                switch intervalSize {
                case 5: return DIRECTION_WEIGHTS[5]   // 6
                case 6: return DIRECTION_WEIGHTS[6]   // 12
                case 7: return DIRECTION_WEIGHTS[7]   // 25
                case 8: return DIRECTION_WEIGHTS[8]   // 36
                case 9: return DIRECTION_WEIGHTS[9]   // 52
                default: return DIRECTION_WEIGHTS[10] // 75
                }
            }
        }
    }
    
    // MARK: 子函数4：重复抑制系数（mobility()）
    private static func calcMobility(pitch: Int, lastPitch: Int) -> Double {
        return pitch == lastPitch ? REPEAT_MOBILITY_FACTOR : 1.0
    }
    
    // MARK: 批量工具：计算一段旋律平均期望值（适配文法EXPECTANCY内置表达式）
    static func averageExpectancy(
        melody: [Int],
        chordList: [String],
        lookup: ChordPitchLookupProtocol.Type
    ) -> Double {
        guard melody.count >= 3, melody.count == chordList.count else { return 0 }
        var sum = 0.0
        for i in 2..<melody.count {
            let score = computeExpectancyScore(
                candidatePitch: melody[i],
                prevPitch: melody[i-1],
                prevPrevPitch: melody[i-2],
                chordName: chordList[i],
                lookup: lookup
            )
            sum += score
        }
        return sum / Double(melody.count - 2)
    }
}
