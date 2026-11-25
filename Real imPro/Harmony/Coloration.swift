import Foundation

// MARK: - Coloration — 色彩音分类配置 (P1-4)
// 定义4级音符色彩分类: CHORD_TONE/COLOR_TONE/APPROACH_TONE/FOREIGN_TONE
// 为导音生成 / Transform变换 / 音高选择统一提供色彩音判定标准

enum Coloration: Int {
    case chordTone    = 0   // 和弦音 (1-3-5-7)
    case colorTone    = 1   // 色彩延伸音 (9-11-13 / alter)
    case approachTone = 2   // 半音/全音趋近音
    case foreignTone  = 3   // 外音 (非和弦/非色彩/非趋近)

    // MARK: - 按和弦+音高判定音符类型

    ///  determineColor:
    /// - Parameters:
    ///   - midiPitch: 音符 MIDI
    ///   - chordName: 所属和弦
    ///   - prevMidi: 前音MIDI (检测Approach: 前一音是否在目标音半音范围内)
    ///   - chordFamily: 和弦族 (可选, 自动推断)
    /// - Returns: 色彩等级分类
    static func classify(midiPitch: Int,
                         chordName: String,
                         prevMidi: Int? = nil,
                         chordFamily: ChordFamily? = nil) -> Coloration {
        let pc = midiPitch % 12
        let rootPC = rootPitchClass(chordName)
        let relativePC = (pc - rootPC + 12) % 12

        // 1. 和弦音判定 (1-3-5-7)
        let chordIntervals = chordToneIntervals(for: chordFamily ?? familyFromName(chordName))
        if chordIntervals.contains(relativePC) {
            return .chordTone
        }

        // 2. Approach音判定: 前一音在目标音半音范围内
        if let prev = prevMidi {
            let target = midiPitch
            let diff = abs(target - prev)
            if diff == 1 || diff == 2 {
                // 且目标音是和弦音→判定为approach
                let targetRelative = (target % 12 - rootPC + 12) % 12
                if chordIntervals.contains(targetRelative) {
                    return .approachTone
                }
            }
        }

        // 3. 色彩延伸音判定 (9-11-13 + alter)
        let colorIntervals = ChordExtensionTonePool.tonesFor(chordFamily ?? familyFromName(chordName))
        if colorIntervals.contains(relativePC) {
            return .colorTone
        }

        // 4. 兜底: 外音
        return .foreignTone
    }

    /// 批量分类 (用于整段旋律调色)
    static func classifyMelody(_ pitches: [Int],
                                chordName: String,
                                chordFamily: ChordFamily? = nil) -> [Coloration] {
        var result: [Coloration] = []
        for i in 0..<pitches.count {
            let prev = i > 0 ? pitches[i-1] : nil
            result.append(classify(midiPitch: pitches[i], chordName: chordName, prevMidi: prev, chordFamily: chordFamily))
        }
        return result
    }

    // MARK: - 内部辅助

    private static func rootPitchClass(_ chordName: String) -> Int {
        let n = chordName.replacingOccurrences(of: "♭", with: "b").replacingOccurrences(of: "♯", with: "#")
        let root = n.prefix { $0.isLetter && $0.isUppercase || $0 == "#" || $0 == "b" }
        switch String(root) {
        case "C": return 0; case "C#","Db": return 1; case "D": return 2
        case "D#","Eb": return 3; case "E": return 4; case "F": return 5
        case "F#","Gb": return 6; case "G": return 7; case "G#","Ab": return 8
        case "A": return 9; case "A#","Bb": return 10; case "B": return 11
        default: return 0
        }
    }

    private static func chordToneIntervals(for family: ChordFamily) -> Set<Int> {
        switch family {
        case .major: return [0, 4, 7, 11]
        case .minor: return [0, 3, 7, 10]
        case .dominant: return [0, 4, 7, 10]
        case .halfDiminished: return [0, 3, 6, 10]
        case .diminished: return [0, 3, 6, 9]
        case .augmented: return [0, 4, 8, 10]
        case .sus: return [0, 5, 7]
        case .unknown: return [0, 4, 7]
        }
    }

    private static func familyFromName(_ name: String) -> ChordFamily {
        ChordQuality(chordName: name).chordFamily
    }
    
    // MARK: - 变音后缀解析
    
    /// 从和弦名后缀中提取变音音程 (如 C7#9b13 → [#9=3, b13=8])
    /// - Parameter chordName: 完整和弦名
    /// - Returns: 变音距根音半音数列表
    static func alteredSuffixIntervals(from chordName: String) -> [Int] {
        let root = chordName.prefix { $0.isLetter && $0.isUppercase || $0 == "#" || $0 == "b" }
        let suffix = String(chordName.dropFirst(root.count)).lowercased()
        
        var intervals: [Int] = []
        guard let pattern = try? NSRegularExpression(pattern: "([b#])(\\d+)") else { return intervals }
        let matches = pattern.matches(in: suffix, range: NSRange(suffix.startIndex..., in: suffix))
        
        for match in matches {
            guard let accRange = Range(match.range(at: 1), in: suffix),
                  let numRange = Range(match.range(at: 2), in: suffix),
                  let degree = Int(suffix[numRange]) else { continue }
            let sign = suffix[accRange] == "#" ? 1 : -1
            let base: Int
            switch degree {
            case 5:  base = 7    // b5=6, #5=8
            case 9:  base = 2    // b9=1, #9=3
            case 11: base = 5    // #11=6
            case 13: base = 9    // b13=8
            default: continue
            }
            intervals.append(base + sign)
        }
        return intervals
    }
}
