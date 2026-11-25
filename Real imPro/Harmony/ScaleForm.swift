import Foundation

// MARK: - ScaleForm — 核心音阶数据库 (P1 · 约100行)
// 仅保留4套标准音阶; 教会调式由大调音程旋转动态推导, 不冗余存储

struct ScaleForm {

    /// 音阶类型
    enum ScaleType: String, CaseIterable {
        case major            // Ionian: W-W-H-W-W-W-H
        case naturalMinor     // Aeolian: W-H-W-W-H-W-W
        case harmonicMinor    // W-H-W-W-H-A-H  (A=增二度=3半音)
        case melodicMinor     // W-H-W-W-W-W-H  (上行)
    }

    /// 获取音阶音程 (相对根音, 半音数)
    static func intervals(for type: ScaleType) -> [Int] {
        switch type {
        case .major:         return [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor:  return [0, 2, 3, 5, 7, 8, 10]
        case .harmonicMinor: return [0, 2, 3, 5, 7, 8, 11]
        case .melodicMinor:  return [0, 2, 3, 5, 7, 9, 11]
        }
    }

    /// 获取完整音阶音高 (MIDI, 3个八度)
    static func pitches(for type: ScaleType, tonic: PitchClass,
                        in range: ClosedRange<Int> = 48...84) -> [Int] {
        let ints = intervals(for: type)
        var result: [Int] = []
        for interval in ints {
            let pc = (tonic.index + interval) % 12
            for octave in stride(from: (range.lowerBound/12)*12, through: (range.upperBound/12)*12, by: 12) {
                let pitch = pc + octave
                if range.contains(pitch) { result.append(pitch) }
            }
        }
        return result.sorted()
    }

    /// 教会调式: 通过大调音程旋转动态生成 (不冗余存储)
    /// modeDegree: 1=Ionian, 2=Dorian, 3=Phrygian, 4=Lydian, 5=Mixolydian, 6=Aeolian, 7=Locrian
    static func modeIntervals(degree: Int) -> [Int] {
        let major = Self.intervals(for: .major)
        // 旋转: 从degree-1位置开始, 将前面的音高上移八度
        let offset = (degree - 1) % 7
        var rotated = Array(major[offset...] + major[..<offset])
        // 修正: 后续音高需要补八度
        for i in (7 - offset)..<7 {
            rotated[i] += 12
        }
        // 归一到0-12范围
        let base = rotated[0]
        return rotated.map { ($0 - base + 12) % 12 }.sorted()
    }

    /// 教会调式名称
    static let modeNames = [
        1: "Ionian", 2: "Dorian", 3: "Phrygian",
        4: "Lydian", 5: "Mixolydian", 6: "Aeolian", 7: "Locrian"
    ]

    /// Blues音阶 (1, b3, 4, b5, 5, b7)
    static let bluesIntervals: [Int] = [0, 3, 5, 6, 7, 10]
    /// Pentatonic Major (1, 2, 3, 5, 6)
    static let pentatonicMajorIntervals: [Int] = [0, 2, 4, 7, 9]
    /// Pentatonic Minor (1, b3, 4, 5, b7)
    static let pentatonicMinorIntervals: [Int] = [0, 3, 5, 7, 10]

    // MARK: - 从 Key 生成音阶 (对接现有数据类型)

    /// 根据 Key 获取对应的 ScaleForm.ScaleType
    static func type(for mode: JazzMode) -> ScaleType {
        switch mode {
        case .major:    return .major
        case .minor:    return .naturalMinor
        case .dominant: return .major  // Mixolydian近似
        case .dorian:   return .naturalMinor  // Aeolian近似(Dorian→Minor+D)
        case .phrygian: return .naturalMinor  // Aeolian近似(Phrygian→Minor+E)
        case .lydian:   return .major         // Ionian近似(Lydian→Major+F)
        case .locrian:  return .naturalMinor  // Aeolian近似(Locrian→Minor+B)
        case .unknown:  return .major
        }
    }

    /// 从 Key 生成音阶音高
    static func pitches(for key: Key, in range: ClosedRange<Int> = 48...84) -> [Int] {
        pitches(for: type(for: key.mode), tonic: key.tonic, in: range)
    }
}
