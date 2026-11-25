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
        // T0-PROBEFIX(F8): 对齐 Java Duration.getDuration —— 支持 "+" 连加（如 8+16=60+30=90），逐段求和。
        if str.contains("+") {
            var sum = 0
            for piece in str.components(separatedBy: "+") { sum += singleSlots(piece) }
            return sum
        }
        return singleSlots(str)
    }

    static func singleSlots(_ durationString: String) -> Int {
        let str = durationString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return 0 }
        // 单段：分离连音部分（如 "/3"）
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
        // F18 对齐 Java Note.getDurationString(L1086 起)：用两路固定顺序贪心分解、取字符更短者。
        // 关键：300=二分+八分须输出 "2+8"（=240+60），210→"4+8+16"，90→"8+16"，40→"8/3"。
        // 旧实现只认单值标准/附点/三连，其余兜底成裸 slot 串（如 "300"），下游 duration>= 再把
        // "300" 当时值分母误解析成 ~1，导致 mordant 等 guard 被误判 false。
        guard slots > 0 else { return "" } // Java: value<=0 返回空串
        // (单位 slots, token, 是否要求整除才取——对应 accumulateExactValue 的五连音)
        let order1: [(Int, String, Bool)] = [
            (480, "1", false), (240, "2", false), (120, "4", false), (96, "4/5", true),
            (60, "8", false), (48, "8/5", true), (30, "16", false), (24, "16/5", true),
            (15, "32", false), (12, "32/5", true),
            (160, "2/3", false), (80, "4/3", false), (40, "8/3", false),
            (20, "16/3", false), (10, "32/3", false),
            (8, "60", false), (4, "120", false), (2, "240", false), (1, "480", false)
        ]
        let order2: [(Int, String, Bool)] = [
            (160, "2/3", false), (80, "4/3", false), (40, "8/3", false),
            (20, "16/3", false), (10, "32/3", false),
            (480, "1", false), (240, "2", false), (120, "4", false),
            (60, "8", false), (30, "16", false), (15, "32", false),
            (8, "60", false), (4, "120", false), (2, "240", false), (1, "480", false)
        ]
        func decompose(_ order: [(Int, String, Bool)]) -> String {
            var rem = slots
            var out = ""
            for (unit, token, exactOnly) in order {
                if exactOnly {
                    if rem % unit == 0 { while rem >= unit { out += "+" + token; rem -= unit } }
                } else {
                    while rem >= unit { out += "+" + token; rem -= unit }
                }
            }
            return out
        }
        let a = decompose(order1)
        let b = decompose(order2)
        let picked = a.count <= b.count ? a : b
        return picked.hasPrefix("+") ? String(picked.dropFirst()) : picked
    }

    /*
    // F18【旧码封存】单值匹配版，无法表达加法型时值，保留备查不删。
    static func durationString_legacy(from slots: Int) -> String {
        guard slots > 0 else { return "0" }
        let beats = Double(slots) / Double(slotsPerBeat)
        let standardDurations: [(name: String, beats: Double)] = [
            ("1", 4.0), ("2", 2.0), ("4", 1.0), ("8", 0.5),
            ("16", 0.25), ("32", 0.125), ("64", 0.0625)
        ]
        for dur in standardDurations {
            if abs(beats - dur.beats) < 0.001 { return dur.name }
            if abs(beats - dur.beats * 1.5) < 0.001 { return dur.name + "." }
        }
        for dur in standardDurations {
            let tripletBeats = dur.beats * 2.0 / 3.0
            if abs(beats - tripletBeats) < 0.001 { return dur.name + "/3" }
            let quintupletBeats = dur.beats * 4.0 / 5.0
            if abs(beats - quintupletBeats) < 0.001 { return dur.name + "/5" }
        }
        return "\(slots)"
    }
    */
    
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
        // T0-PROBEFIX(仅探针副本, 生产待 T1): 原码 `0..<netSharps`/`0..<netFlats`
        // 在净升降号为负时 0..<(-1) 直接 Range trap (b3/#1 即崩)。改为带符号累加。
        let net = sharps - flats
        if net > 0 { for _ in 0..<net { augments += "#" } }
        else if net < 0 { for _ in 0..<(-net) { augments += "b" } }
        
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
        // T0-PROBEFIX(F3-泛化): 任意和弦都走 Java NoteConverter 七族 12 项固定拼写表，
        // family 由 TransformVocabulary.javaFamily 运行时判定（区分 minor/minor7），不再依赖 13 名白名单。
        let fam = TransformVocabulary.javaFamily(chordName)
        let fwd = (fam == "sus4" || fam == "alt") ? "dominant" : fam
        let root = rootPitchClass(from: chordName)
        var off = (midiPitch % 12) - root
        if off < 0 { off += 12 }
        let table = TransformVocabulary.scales[fwd] ?? TransformVocabulary.scales["major"]!
        return table[off]
    }

    // T0-PROBE: 相对拼写 → 相对根音的半音偏移（严格对应 Java LickGen.makeRelativeNote
    // 自带的每族「自然级 1..7 → 半音偏移」switch；注意 sus4/未知族走 major，与正向拼写表不同）。
    // 变音号 b/# 在取级之前对基准音 -1/+1，故 = 级偏移 + 变音累计。带符号、不 mod。
    static let makeRelOffset: [String: [Int]] = [
        "major":          [0, 2, 4, 5, 7, 9, 11],
        "minor":          [0, 2, 3, 5, 7, 9, 11],
        "minor7":         [0, 2, 3, 5, 7, 9, 10],
        "dominant":       [0, 2, 4, 5, 7, 9, 10],
        "half-diminished":[0, 2, 3, 5, 7, 9, 10],
        "diminished":     [0, 2, 3, 5, 6, 8, 9],
        "augmented":      [0, 2, 4, 5, 8, 9, 10],
    ]
    static func goldSemitonesAbove(relativeSpell: String, chordName: String) -> Int? {
        // T0-PROBEFIX(F5-泛化): family 运行时判定；makeRelativeNote 逆映射 sus4/未列族→major。
        let jf = TransformVocabulary.javaFamily(chordName)
        let fam = makeRelOffset[jf] != nil ? jf : "major"
        guard let off = makeRelOffset[fam] else { return nil }
        var acc = 0; var numStr = ""
        for c in relativeSpell {
            if c == "b" { acc -= 1 } else if c == "#" { acc += 1 } else { numStr.append(c) }
        }
        guard var degree = Int(numStr) else { return nil }
        // 复刻 makeRelativeNote 的任意八度归一：<0 加8降八度，>7 减7升八度
        var oct = 0
        while degree < 0 { oct -= 1; degree += 8 }
        while degree > 7 { oct += 1; degree -= 7 }
        guard degree >= 1, degree <= 7 else { return nil }
        return off[degree - 1] + acc + 12 * oct
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
        // T0-PROBEFIX(F9): 旧实现 pcMap["Eb".uppercased()="EB"] 查无→错返 0(C)，导致 Eb/Ab/Bb 等带降号根全部错位。
        // 统一复用生产 GTVocResolver.splitRoot（正确处理 b/# 与等音根）。
        let cleanName = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return 0 }
        let noSlash = cleanName.split(separator:"/",maxSplits:1).first.map(String.init) ?? cleanName
        return GTVocResolver.splitRoot(noSlash).0
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
        // T0-PROBEFIX(F4-正解): 对齐 Java LickGen.classifyNote —— 休止/无词表->X；
        // 命中【真实 My.voc 词表 spell】->C，命中 color->L，其余 X。走 G1 全量 114 型表(按根转调)。
        guard midiPitch >= 0 else { return .passing }   // rest -> "X"
        let pc = midiPitch % 12
        if let v = TransformVocabulary.vocab(chordName) {
            if v.spell.contains(pc) { return .chord }
            if v.color.contains(pc) { return .color }
            return .passing
        }
        // 表未命中兜底（统计未命中率，不静默）：按族级近似
        TransformVocabulary.noteCategoryMiss()
        let rootPC = rootPitchClass(from: chordName)
        let relativePC = (midiPitch - rootPC + 120) % 12
        let family = ChordBlock(name: chordName, duration: 0).getChordFamily()
        let chordTones: [Int]
        let colorTones: [Int]
        switch family {
        case .major: chordTones = [0, 4, 7, 11]; colorTones = [2, 9]
        case .minor: chordTones = [0, 3, 7, 10]; colorTones = [2, 9]
        case .dominant: chordTones = [0, 4, 7, 10]; colorTones = [2, 5, 9]
        case .diminished: chordTones = [0, 3, 6, 9]; colorTones = []
        case .halfDiminished: chordTones = [0, 3, 6, 10]; colorTones = [2]
        case .augmented: chordTones = [0, 4, 8]; colorTones = []
        case .sus: chordTones = [0, 5, 7]; colorTones = [2, 9]
        case .unknown: chordTones = [0, 4, 7]; colorTones = []
        }
        if chordTones.contains(relativePC) { return .chord }
        if colorTones.contains(relativePC) { return .color }
        return .passing
    }

    private static func rootPitchClass(from chordName: String) -> Int {
        // T0-PROBEFIX(F9): 旧实现 pcMap["Eb".uppercased()="EB"] 查无→错返 0(C)，导致 Eb/Ab/Bb 等带降号根全部错位。
        // 统一复用生产 GTVocResolver.splitRoot（正确处理 b/# 与等音根）。
        let cleanName = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return 0 }
        let noSlash = cleanName.split(separator:"/",maxSplits:1).first.map(String.init) ?? cleanName
        return GTVocResolver.splitRoot(noSlash).0
    }
}
