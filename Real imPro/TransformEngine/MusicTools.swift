import Foundation

// MARK: - 时值工具类
/// 一拍 = 120 slots
enum DurationTools {
    static let slotsPerBeat = 120
    
    // MARK: - 时值字符串 → Slots（对应 Duration.getDuration0）
    /// 支持格式："1", "2", "4", "8", "16", "32" + 附点 "." + 连音 "/3", "/5"
    /// 例如："4" = 四分音符 = 120 slots，"8." = 附点八分 = 90 slots，"16/3" = 十六分三连音 = 40 slots
    static func slots(from durationString: String) -> Int {
        let str = durationString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return 0 }
        
        // 分离连音部分（如 "/3"）
        var tupletDivisor = 1
        var mainPart = str
        if let slashRange = str.range(of: "/") {
            let tupletStr = String(str[slashRange.upperBound...])
            tupletDivisor = Int(tupletStr) ?? 1
            mainPart = String(str[..<slashRange.lowerBound])
        }
        
        // 分离附点
        var dotMultiplier = 1.0
        if mainPart.hasSuffix(".") {
            dotMultiplier = 1.5
            mainPart = String(mainPart.dropLast())
        }
        
        // 解析基础时值（分母）
        guard let baseDenominator = Double(mainPart) else { return 0 }
        guard baseDenominator > 0 else { return 0 }
        
        // 全音符为基准："1" = 4拍 = 480 slots
        let beats = 4.0 / baseDenominator
        var slots = Int(beats * Double(slotsPerBeat) * dotMultiplier)
        
        // 连音处理：三连音 = 原时值 * 2/3，五连音 = 原时值 * 4/5
        if tupletDivisor > 1 {
            slots = Int(Double(slots) * Double(tupletDivisor - 1) / Double(tupletDivisor))
        }
        
        return max(slots, 1)
    }
    
    // MARK: - Slots → 时值字符串（对应 Note.getDurationString）
    static func durationString(from slots: Int) -> String {
        guard slots > 0 else { return "0" }
        
        // 计算是几拍（可能不是整数）
        let beats = Double(slots) / Double(slotsPerBeat)
        
        // 尝试匹配标准时值
        let standardDurations: [(name: String, beats: Double)] = [
            ("1", 4.0),      // 全音符
            ("2", 2.0),      // 二分
            ("4", 1.0),      // 四分
            ("8", 0.5),      // 八分
            ("16", 0.25),    // 十六分
            ("32", 0.125),   // 三十二分
            ("64", 0.0625)   // 六十四分
        ]
        
        // 先尝试精确匹配
        for dur in standardDurations {
            if abs(beats - dur.beats) < 0.001 {
                return dur.name
            }
            // 附点
            if abs(beats - dur.beats * 1.5) < 0.001 {
                return dur.name + "."
            }
        }
        
        // 尝试连音匹配（三连音、五连音）
        for dur in standardDurations {
            // 三连音：原时值 * 2/3
            let tripletBeats = dur.beats * 2.0 / 3.0
            if abs(beats - tripletBeats) < 0.001 {
                return dur.name + "/3"
            }
            // 五连音：原时值 * 4/5
            let quintupletBeats = dur.beats * 4.0 / 5.0
            if abs(beats - quintupletBeats) < 0.001 {
                return dur.name + "/5"
            }
        }
        
        // 都不匹配，返回近似的 slots 数字（兜底）
        return "\(slots)"
    }
    
    // MARK: - 辅助判断
    static func isTriplet(_ durationString: String) -> Bool {
        durationString.contains("/3")
    }
    
    static func isQuintuplet(_ durationString: String) -> Bool {
        durationString.contains("/5")
    }
    
    static func isDotted(_ durationString: String) -> Bool {
        durationString.contains(".") && !durationString.contains("/")
    }
}

// MARK: - 相对音高工具（对应 NoteConverter + addRelPitch）
/// 相对音高格式：[变音符号][度数]，如 "3", "#3", "b5", "9", "b9", "#11"
/// 度数 1-7 为一个八度，8 = 高八度 1 音，9 = 高八度 2 音（九音），以此类推
enum RelativePitchTools {
    
    // MARK: - 相对音高相加（对应 Evaluate.addRelPitch）
    /// 两个相对音高相加，返回结果相对音高字符串
    static func add(_ rp1: String, _ rp2: String) -> String {
        // 分离变音符号和数字
        let (augment1, num1) = parseRelativePitch(rp1)
        let (augment2, num2) = parseRelativePitch(rp2)
        
        // 数字相加（注意：相对音高是 1-based，且没有 0）
        var addTotal = num1 + num2
        if num1 > 0 { addTotal -= 1 }
        if num2 > 0 { addTotal -= 1 }
        
        if addTotal >= 0 {
            addTotal += 1
        }
        
        // 合并变音符号
        var flats = 0
        var sharps = 0
        
        for c in augment1 {
            if c == "b" { flats += 1 }
            else if c == "#" { sharps += 1 }
        }
        for c in augment2 {
            if c == "b" { flats += 1 }
            else if c == "#" { sharps += 1 }
        }
        
        let netFlats = flats - sharps
        let netSharps = sharps - flats
        
        var augments = ""
        for _ in 0..<netFlats { augments += "b" }
        for _ in 0..<netSharps { augments += "#" }
        
        return augments + String(addTotal)
    }
    
    // MARK: - 相对音高取反（用于减法）
    static func negate(_ rp: String) -> String {
        var result = ""
        var numStr = ""
        
        for c in rp {
            if c == "b" { result += "#" }  // b 变 #
            else if c == "#" { result += "b" }  // # 变 b
            else { numStr.append(c) }
        }
        
        guard var num = Int(numStr) else { return rp }
        
        // 数字取反：1 → -1, 2 → -2, ...
        // 注意：相对音高没有 0，-1 表示低八度的 7 音？不对，让我看 Java 版的逻辑
        // Java 版 pitch_subtraction 中的处理：
        // value = -1*value + 1;
        // if(value == 0) value = 1;
        // 这看起来是把正数变成对应的"反向"度数
        
        // 重新理解：相对音高的减法，实际上是加上"反向"的音程
        // 比如 3 - 2 = 2（从三音往下走二度，得到二音？不对...）
        
        // 让我按照 Java 版的逻辑来实现
        num = -1 * num + 1
        if num == 0 { num = 1 }
        
        return result + String(num)
    }
    
    // MARK: - 解析相对音高字符串
    /// 返回 (变音符号字符串, 度数数字)
    static func parseRelativePitch(_ rp: String) -> (String, Int) {
        var augment = ""
        var numStr = ""
        
        for c in rp {
            if c == "#" || c == "b" {
                augment.append(c)
            } else {
                numStr.append(c)
            }
        }
        
        let num = Int(numStr) ?? 0
        return (augment, num)
    }
    
    // MARK: - 绝对MIDI音高 → 相对音高（对应 NoteConverter.noteToRelativePitch）
    /// 根据和弦根音和性质，将绝对音高转换为相对音高字符串
    static func relativePitch(midiPitch: Int, chordName: String) -> String {
        guard midiPitch >= 0 else { return "0" }  // 休止符
        
        // 解析根音
        let rootPC = rootPitchClass(from: chordName)
        
        // 计算相对音程（0-11）
        let relativeSemitones = (midiPitch - rootPC + 120) % 12
        
        // 判断和弦性质
        let family = ChordBlock(name: chordName, duration: 0).getChordFamily()
        
        // 根据和弦性质确定音阶
        let scaleIntervals: [Int]
        switch family {
        case .major:
            scaleIntervals = [0, 2, 4, 5, 7, 9, 11]  // 大调音阶
        case .minor:
            scaleIntervals = [0, 2, 3, 5, 7, 8, 10]  // 自然小调
        case .dominant:
            scaleIntervals = [0, 2, 4, 5, 7, 9, 10]  // 混合利底亚
        case .diminished:
            scaleIntervals = [0, 2, 3, 5, 6, 8, 9, 11]  // 减音阶（取前7个）
        case .halfDiminished:
            scaleIntervals = [0, 2, 3, 5, 6, 8, 10]  // 洛克里亚
        case .augmented:
            scaleIntervals = [0, 3, 4, 7, 8, 11]  // 全音阶（取前6个）
        case .sus:
            scaleIntervals = [0, 2, 5, 7, 9]  // sus 音阶
        case .unknown:
            scaleIntervals = [0, 2, 4, 5, 7, 9, 11]  // 默认大调
        }
        
        // 找到最接近的音阶度数
        var bestDegree = 1
        var bestDistance = Int.max
        
        for (i, interval) in scaleIntervals.enumerated() {
            let dist = abs(relativeSemitones - interval)
            if dist < bestDistance {
                bestDistance = dist
                bestDegree = i + 1  // 1-based
            }
        }
        
        // 计算变音符号（偏离音阶的半音数）
        let scaleInterval = scaleIntervals[bestDegree - 1]
        let semitoneOffset = relativeSemitones - scaleInterval
        
        var augment = ""
        if semitoneOffset > 0 {
            for _ in 0..<semitoneOffset { augment += "#" }
        } else if semitoneOffset < 0 {
            for _ in 0..<(-semitoneOffset) { augment += "b" }
        }
        
        return augment + String(bestDegree)
    }
    
    // MARK: - 相对音高 → 绝对MIDI音高（对应 LickGen.makeRelativeNote 的音高部分）
    static func midiPitch(from relativePitch: String, chordName: String, referenceOctave: Int = 60) -> Int {
        let (augment, degree) = parseRelativePitch(relativePitch)
        guard degree > 0 else { return -1 }
        
        let rootPC = rootPitchClass(from: chordName)
        
        // 判断和弦性质
        let family = ChordBlock(name: chordName, duration: 0).getChordFamily()
        
        // 根据和弦性质确定音阶
        let scaleIntervals: [Int]
        switch family {
        case .major:
            scaleIntervals = [0, 2, 4, 5, 7, 9, 11]
        case .minor:
            scaleIntervals = [0, 2, 3, 5, 7, 8, 10]
        case .dominant:
            scaleIntervals = [0, 2, 4, 5, 7, 9, 10]
        case .diminished:
            scaleIntervals = [0, 2, 3, 5, 6, 8, 9, 11]
        case .halfDiminished:
            scaleIntervals = [0, 2, 3, 5, 6, 8, 10]
        case .augmented:
            scaleIntervals = [0, 3, 4, 7, 8, 11]
        case .sus:
            scaleIntervals = [0, 2, 5, 7, 9]
        case .unknown:
            scaleIntervals = [0, 2, 4, 5, 7, 9, 11]
        }
        
        // 计算八度偏移
        let degreeIndex = (degree - 1) % scaleIntervals.count
        let octaveShift = (degree - 1) / scaleIntervals.count
        
        // 基础音程
        var semitoneInterval = scaleIntervals[degreeIndex]
        
        // 加上变音符号
        for c in augment {
            if c == "#" { semitoneInterval += 1 }
            else if c == "b" { semitoneInterval -= 1 }
        }
        
        // 计算绝对音高（以参考八度的根音为基准）
        let referenceRoot = referenceOctave - (referenceOctave % 12) + (rootPC % 12)
        var midi = referenceRoot + semitoneInterval + octaveShift * 12
        
        // 确保在合理范围内
        while midi < 0 { midi += 12 }
        while midi > 127 { midi -= 12 }
        
        return midi
    }
    
    // MARK: - 辅助：解析和弦名获取根音 PitchClass
    private static func rootPitchClass(from chordName: String) -> Int {
        let cleanName = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return 0 }
        
        var rootStr = ""
        let chars = Array(cleanName)
        if chars.count > 0 { rootStr.append(chars[0]) }
        if chars.count > 1 && (chars[1] == "#" || chars[1] == "b") { rootStr.append(chars[1]) }
        
        let pcMap: [String: Int] = [
            "C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3,
            "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8,
            "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11
        ]
        
        return pcMap[rootStr.uppercased()] ?? 0
    }
}

// MARK: - 音符分类工具（对应 LickGen.classifyNote）
enum NoteCategoryTools {
    /// 音符分类：C = 和弦音, L = 色彩音, X = 外音, R = 休止符
    enum Category: String {
        case chord = "C"
        case color = "L"
        case passing = "X"
        case rest = "R"
    }
    
    /// 分类音符
    static func classify(midiPitch: Int, chordName: String) -> Category {
        // 休止符
        guard midiPitch >= 0 else { return .rest }
        
        let rootPC = rootPitchClass(from: chordName)
        let relativePC = (midiPitch - rootPC + 120) % 12
        
        // 判断和弦性质
        let family = ChordBlock(name: chordName, duration: 0).getChordFamily()
        
        // 和弦音（1, 3, 5, 7 等核心和弦音）
        let chordTones: [Int]
        // 色彩音（9, 11, 13 等延伸音）
        let colorTones: [Int]
        
        switch family {
        case .major:
            chordTones = [0, 4, 7, 11]  // 1, 3, 5, 7
            colorTones = [2, 9]         // 9, 13
        case .minor:
            chordTones = [0, 3, 7, 10]  // 1, b3, 5, b7
            colorTones = [2, 9]         // 9, 13
        case .dominant:
            chordTones = [0, 4, 7, 10]  // 1, 3, 5, b7
            colorTones = [2, 5, 9]      // 9, 11, 13
        case .diminished:
            chordTones = [0, 3, 6, 9]   // 1, b3, b5, bb7
            colorTones = []
        case .halfDiminished:
            chordTones = [0, 3, 6, 10]  // 1, b3, b5, b7
            colorTones = [2]            // 9
        case .augmented:
            chordTones = [0, 4, 8]      // 1, 3, #5
            colorTones = []
        case .sus:
            chordTones = [0, 5, 7]      // 1, 4, 5 (sus4)
            colorTones = [2, 9]         // 9, 13
        case .unknown:
            chordTones = [0, 4, 7]      // 默认大三和弦
            colorTones = []
        }
        
        if chordTones.contains(relativePC) {
            return .chord
        }
        if colorTones.contains(relativePC) {
            return .color
        }
        return .passing
    }
    
    private static func rootPitchClass(from chordName: String) -> Int {
        let cleanName = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return 0 }
        
        var rootStr = ""
        let chars = Array(cleanName)
        if chars.count > 0 { rootStr.append(chars[0]) }
        if chars.count > 1 && (chars[1] == "#" || chars[1] == "b") { rootStr.append(chars[1]) }
        
        let pcMap: [String: Int] = [
            "C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3,
            "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8,
            "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11
        ]
        
        return pcMap[rootStr.uppercased()] ?? 0
    }
}
