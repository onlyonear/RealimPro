import Foundation

// MARK: - RhythmGenerator
// 功能: 随机节奏生成 + 切分音爬山调优 + 文法记谱串双向转换

struct RhythmGenerator {

    // ──────────────────────────────────────────────
    // 静态常量 — 对应 Java Generator.java 第33-65行
    // ──────────────────────────────────────────────

    /// 32个slot的节拍权重表 (0=全音符强拍, -5=32分音符弱拍)
    /// Java: private static int[] WEIGHTS = {0, -5, -4, -5, ...}
    static let weights: [Int] = [
         0, -5, -4, -5,  -3, -5, -4, -5,  -2, -5, -4, -5,  -3, -5, -4, -5,
        -1, -5, -4, -5,  -3, -5, -4, -5,  -2, -5, -4, -5,  -3, -5, -4, -5
    ]

    /// 每小节的slot数 (32分音符为单位)
    /// Java: private static int NUM_SLOTS = WEIGHTS.length
    static let slotsPerMeasure: Int = 32

    /// 节拍层级常量 — Java: WHOLE_WEIGHT=0 .. THIRTY_SECOND_WEIGHT=5
    private static let wholeWeight      = 0
    private static let halfWeight       = 1
    private static let quarterWeight    = 2
    private static let eighthWeight     = 3
    private static let sixteenthWeight  = 4
    private static let thirtySecondWeight = 5

    /// 最高音符生成概率 — Java: HIGHTEST_NOTE_PROBABILITY = .95
    private static let highestNoteProbability: Double = 0.95

    /// Approach导音染色概率 — Java: APPROACH_PROBABILITY = .5
    private static let approachProbability: Double = 0.5

    /// 时值slot数 — Java: THIRTY_SECOND=1, SIXTEENTH=2, EIGHTH=4, QUARTER=8, HALF=16, WHOLE=32
    private static let thirtySecondSlots = 1
    private static let sixteenthSlots    = 2
    private static let eighthSlots       = 4
    private static let quarterSlots      = 8
    private static let halfSlots         = 16
    private static let wholeSlots        = 32

    /// 文法记谱串 — Java: THIRTY_SECOND_NOTE="32", SIXTEENTH_NOTE="16", ...
    private static let thirtySecondNote = "32"
    private static let sixteenthNote    = "16"
    private static let eighthNote       = "8"
    private static let quarterNote      = "4"
    private static let halfNote         = "2"
    private static let wholeNote        = "1"

    private static let thirtySecondRest = "R32"
    private static let sixteenthRest    = "R16"
    private static let eighthRest       = "R8"
    private static let quarterRest      = "R4"
    private static let halfRest         = "R2"
    private static let wholeRest        = "R1"

    private static let sixteenthApproach = "A16"
    private static let eighthApproach    = "A8"


    // MARK: - 核心方法1: generateRhythm
    // ──────────────────────────────────────────────
    // Java: public static int[] generateRhythm(int measures)  — 第408-437行
    //
    // 逻辑:
    //   1. 分配 measures * 32 长度的 int 数组
    //   2. 逐slot计算 invMetHier = -WEIGHTS[i%32] + 1  (1=全音符强拍, 6=32分弱拍)
    //   3. weight = 1.0 / invMetHier  (仅invMetHier≤5时有效, 6→weight=0永不生成32分)
    //   4. 十六分音符不与前一音连续出现时 weight=0 (防节奏碎化)
    //   5. 八分以上音符跟在十六分后时 weight=2 (鼓励节奏对)
    //   6. Math.random() <= weight * 0.95 → rhythm[i]=1 否则=0

    static func generateRhythm(measures: Int) -> [Int] {
        let totalSlots = measures * slotsPerMeasure
        var rhythm = [Int](repeating: 0, count: totalSlots)
        var prevIndex = 0

        for i in 0..<totalSlots {
            // Java: int invMetHier = (WEIGHTS[i % NUM_SLOTS] * -1) + 1;
            let invMetHier = (-weights[i % slotsPerMeasure]) + 1   // 1(强)~6(弱)

            // Java: if (invMetHier <= SIXTEENTH_WEIGHT + 1) weight = 1.0 / invMetHier;
            var weight: Double = 0
            if invMetHier <= sixteenthWeight + 1 {   // invMetHier ≤ 5
                weight = 1.0 / Double(invMetHier)
            }

            // Java: 十六分音符(sixteenthWeight+1=5)不与前一音连续出现 → weight=0
            //       prevIndex != i - SIXTEENTH 表示前一个音不在恰好2个slot之前
            if invMetHier == sixteenthWeight + 1 && prevIndex != i - sixteenthSlots {
                weight = 0
            }

            // Java: 八分以上音符(invMetHier < 5)跟在十六分后(prevIndex == i-2) → weight=2
            if invMetHier < sixteenthWeight + 1 && prevIndex == i - sixteenthSlots {
                weight = 2
            }

            // Java: if (random <= weight * HIGHTEST_NOTE_PROBABILITY) rhythm[i]=1
            if Double.random(in: 0...1) <= weight * highestNoteProbability {
                rhythm[i] = 1
                prevIndex = i
            } else {
                rhythm[i] = 0
            }
        }
        return rhythm
    }


    // MARK: - 核心方法2: generateSyncopation (两个重载)
    // ──────────────────────────────────────────────
    // Java: public static int[] generateSyncopation(int measures, int mySynco, int[] rArray) — 第310-387行
    //
    // 逻辑:
    //   1. 计算当前切分音值 synco = getSyncopation(rhythm, measures)
    //   2. 若 synco > targetSynco: 随机挑slot将强拍音移到弱拍(降低切分音)
    //   3. 若 synco < targetSynco: 随机挑slot将弱拍音移到强拍(增加切分音)
    //   4. 每次尝试后重算, 若未朝目标方向变化则回滚
    //   5. 爬山迭代至收敛

    static func generateSyncopation(measures: Int, targetSynco: Int, initialRhythm: [Int]) -> [Int] {
        var rhythm = initialRhythm
        var synco = getSyncopation(onsets: rhythm, measures: measures)

        // ── 降低切分音(太切分了, 往回调) ──
        // Java: while (synco > mySynco && synco > 2)
        while synco > targetSynco && synco > 2 {
            let i = Int.random(in: 0..<(slotsPerMeasure * measures))
            var searchIdx = i
            if i < slotsPerMeasure * measures - 1 {
                // Java: int desiredWeight = (WEIGHTS[index % NUM_SLOTS] * -1) - 1;
                let desiredWeight = (-weights[searchIdx % slotsPerMeasure]) - 1

                // Java: if (WHOLE_WEIGHT <= desiredWeight && desiredWeight < EIGHTH_WEIGHT)
                if wholeWeight <= desiredWeight && desiredWeight < eighthWeight {
                    // 找到下一个具有desiredWeight的slot
                    while (-weights[searchIdx % slotsPerMeasure]) != desiredWeight {
                        searchIdx += 1
                    }
                    var prevI = 0
                    let prevIndex = rhythm[i]
                    if searchIdx < rhythm.count {
                        prevI = rhythm[searchIdx]
                        rhythm[searchIdx] = 1           // 移动到弱拍
                        rhythm[i] = 0                    // 移除原强拍
                        // Java: 保护十六分音符连续性
                        if i >= 2 && searchIdx <= rhythm.count - 3
                            && (rhythm[i - sixteenthSlots] == 1 || rhythm[i + sixteenthSlots] == 1) {
                            rhythm[i] = 1
                        }
                    }
                    let synco2 = getSyncopation(onsets: rhythm, measures: measures)
                    // Java: 若切分音反而增加则回滚
                    if synco2 > synco {
                        rhythm[i] = prevIndex
                        rhythm[searchIdx] = prevI
                    }
                    synco = getSyncopation(onsets: rhythm, measures: measures)
                }
            }
        }

        // ── 增加切分音(不够切分, 加强) ──
        // Java: while (synco < mySynco)
        while synco < targetSynco {
            let i = Int.random(in: 0..<(slotsPerMeasure * measures))
            var searchIdx = i
            if i < slotsPerMeasure * measures - 1 {
                let desiredWeight = (-weights[searchIdx % slotsPerMeasure]) - 1

                if wholeWeight <= desiredWeight && desiredWeight < eighthWeight {
                    while (-weights[searchIdx % slotsPerMeasure]) != desiredWeight {
                        searchIdx += 1
                    }
                    var prevI = 0
                    let prevIndex = rhythm[i]
                    if searchIdx < rhythm.count {
                        prevI = rhythm[searchIdx]
                        rhythm[i] = 1                    // 移到强拍
                        rhythm[searchIdx] = 0             // 移除原弱拍
                        // Java: 保护十六分音符连续性(在searchIdx侧)
                        if searchIdx >= 2 && searchIdx <= rhythm.count - 3
                            && (rhythm[searchIdx - sixteenthSlots] == 1 || rhythm[searchIdx + sixteenthSlots] == 1) {
                            rhythm[searchIdx] = 1
                        }
                    }
                    let synco2 = getSyncopation(onsets: rhythm, measures: measures)
                    // Java: 若切分音反而减少则回滚
                    if synco2 < synco {
                        rhythm[i] = prevIndex
                        rhythm[searchIdx] = prevI
                    }
                    synco = getSyncopation(onsets: rhythm, measures: measures)
                }
            }
        }
        return rhythm
    }

    /// Java: public static int[] generateSyncopation(int measures, int mySynco) — 第397-400行
    /// 先随机生成节奏，再爬山调优切分音
    static func generateSyncopation(measures: Int, targetSynco: Int) -> [Int] {
        let rhythm = generateRhythm(measures: measures)
        return generateSyncopation(measures: measures, targetSynco: targetSynco, initialRhythm: rhythm)
    }


    // MARK: - 核心方法3: generateString
    // ──────────────────────────────────────────────
    // Java: public static String[] generateString(int[] rhythm, String noteType) — 第76-125行
    //
    // 将节奏数组(1/0序列)转换为文法记谱串数组, 如 ["C4", "X8", "A16", "R8"]
    // noteType参数:
    //   "C" → approach模式(导音染色, 50%概率将弱拍8分/16分替换为A8/A16)
    //   其他 → 普通模式(如"X"=scale tone, "L"=color tone)

    static func generateString(rhythm: [Int], noteType: String) -> [String] {
        let nt = noteType.uppercased()
        // Java: boolean approach = noteType.equals("C")
        let isApproachMode = (nt == "C")

        var rhythmsStr = ""
        var prev: Int = -1

        for i in 0..<rhythm.count {
            if rhythm[i] == 1 {
                if prev != -1 {
                    // Java: 前一个触发点存在, 计算时值差
                    let diff = i - prev
                    // Java: (WEIGHTS[prev % NUM_SLOTS] * -1) >= EIGHTH_WEIGHT → offbeat
                    let isOffbeat = (-weights[prev % slotsPerMeasure]) >= eighthWeight
                    rhythmsStr += getString(diff: diff, isRest: false, offbeat: isOffbeat,
                                            noteType: nt, approach: isApproachMode)
                    prev = i
                } else if i > 0 {
                    // Java: 第一个音符但不是从slot 0开始 → 前面补休止符
                    rhythmsStr += getString(diff: i, isRest: true, offbeat: false,
                                            noteType: nt, approach: isApproachMode)
                }
                prev = i
            }
        }

        // Java: 处理尾部
        if prev == -1 {
            // Java: 整段没有音符 → 全部休止
            rhythmsStr += getString(diff: rhythm.count, isRest: true, offbeat: false,
                                    noteType: nt, approach: isApproachMode)
        } else if prev != rhythm.count {
            // Java: 最后一个音符后还有休止
            let diff = rhythm.count - prev
            let isOffbeat = (-weights[prev % slotsPerMeasure]) >= eighthWeight
            rhythmsStr += getString(diff: diff, isRest: false, offbeat: isOffbeat,
                                    noteType: nt, approach: isApproachMode)
        }

        // Java: rhythms.split("\\s+") — 按空白字符分割
        let trimmed = rhythmsStr.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? [] : trimmed.components(separatedBy: .whitespaces)
    }


    // MARK: - 核心方法4: getArray (两个重载)
    // ──────────────────────────────────────────────
    // Java: public static int[] getArray(Polylist rhythmString) — 第133-142行
    // 将文法记谱串(如 ["X8","X4","R8"]) 转换为节奏数组 [1,0,0,0, 1,0,0,0,0,0,0,0, 0,0,0,0]
    // Swift: 用 [String] 替代 Polylist

    static func getArray(rhythmStrings: [String]) -> [Int] {
        var result: [Int] = []
        getArrayRecursive(rhythmStrings: rhythmStrings, index: 0, result: &result)
        return result
    }

    /// Java: private static ArrayList<Integer> getArray(Polylist rhythmString, ArrayList<Integer> r) — 第151-203行
    /// 递归解析每个token(如 "X8"), 去掉首字符后按时值映射为 1 + N个0
    private static func getArrayRecursive(rhythmStrings: [String], index: Int, result: inout [Int]) {
        guard index < rhythmStrings.count else { return }

        // Java: String rString = ((String) rhythmString.first()).substring(1);
        var token = rhythmStrings[index]
        if token.hasPrefix("R") || token.hasPrefix("A") || token.hasPrefix("X")
            || token.hasPrefix("C") || token.hasPrefix("L") {
            token = String(token.dropFirst())   // 去掉类型前缀, 只留时值部分
        }

        // Java: if(rString.equals(WHOLE_NOTE)) { rhythms.add(1); for(...) add 31个0; }
        switch token {
        case wholeNote:     // "1" → 32 slots
            result.append(1)
            for _ in 1..<wholeSlots { result.append(0) }
        case halfNote:      // "2" → 16 slots
            result.append(1)
            for _ in 1..<halfSlots { result.append(0) }
        case quarterNote:   // "4" → 8 slots
            result.append(1)
            for _ in 1..<quarterSlots { result.append(0) }
        case eighthNote:    // "8" → 4 slots
            result.append(1)
            for _ in 1..<eighthSlots { result.append(0) }
        default:            // "16"/"32"/其他 → 默认16分音符(2 slots)
            result.append(1)
            for _ in 1..<sixteenthSlots { result.append(0) }
        }

        // Java: if(rhythmString.rest().nonEmpty()) return getArray(rhythmString.rest(), rhythms);
        getArrayRecursive(rhythmStrings: rhythmStrings, index: index + 1, result: &result)
    }


    // MARK: - 私有辅助: getString 递归时值分解
    // ──────────────────────────────────────────────
    // Java: private static String getString(int diff, boolean rest, boolean offbeat,
    //                                       String noteType, boolean approach) — 第214-300行
    //
    // 递归分解时值差 diff(以32分音符为单位):
    //   非rest: WHOLE→"X1" → HALF→"X2" → QUARTER→"X4" → EIGHTH→"X8" → SIXTEENTH→"X16" → 32ND→"32"
    //    offbeat && approach: EIGHTH/SIXTEENTH 位置50%概率替换为"A8"/"A16"(导音)
    //   rest: WHOLE→"R1" → HALF→"R2" → ... → SIXTEENTH→"R16" → 32ND→"R32"

    private static func getString(diff: Int, isRest: Bool, offbeat: Bool,
                                  noteType: String, approach: Bool) -> String {
        if !isRest {
            // ── 非休止符: 按 noteType + 时值标记 生成 ──
            if diff >= wholeSlots {          // ≥32 → 全音符
                return "\(noteType)\(wholeNote) " +
                       getString(diff: diff - wholeSlots, isRest: true, offbeat: false,
                                 noteType: noteType, approach: approach)
            } else if diff >= halfSlots {    // ≥16 → 二分音符
                return "\(noteType)\(halfNote) " +
                       getString(diff: diff - halfSlots, isRest: true, offbeat: false,
                                 noteType: noteType, approach: approach)
            } else if diff >= quarterSlots { // ≥8 → 四分音符
                return "\(noteType)\(quarterNote) " +
                       getString(diff: diff - quarterSlots, isRest: true, offbeat: false,
                                 noteType: noteType, approach: approach)
            } else if diff >= eighthSlots {  // ≥4 → 八分音符
                // Java: offbeat && approach时 50%替换为A8
                if offbeat && approach && Double.random(in: 0...1) > approachProbability {
                    return "\(eighthApproach) " +
                           getString(diff: diff - eighthSlots, isRest: true, offbeat: false,
                                     noteType: noteType, approach: approach)
                } else {
                    return "\(noteType)\(eighthNote) " +
                           getString(diff: diff - eighthSlots, isRest: true, offbeat: false,
                                     noteType: noteType, approach: approach)
                }
            } else if diff >= sixteenthSlots { // ≥2 → 十六分音符
                // Java: offbeat && approach时 50%替换为A16
                if offbeat && approach && Double.random(in: 0...1) > approachProbability {
                    return "\(sixteenthApproach) " +
                           getString(diff: diff - sixteenthSlots, isRest: true, offbeat: false,
                                     noteType: noteType, approach: approach)
                } else {
                    return "\(noteType)\(sixteenthNote) " +
                           getString(diff: diff - sixteenthSlots, isRest: true, offbeat: false,
                                     noteType: noteType, approach: approach)
                }
            } else if diff >= thirtySecondSlots { // ≥1 → 32分音符
                return "\(thirtySecondNote) " +
                       getString(diff: diff - thirtySecondSlots, isRest: true, offbeat: false,
                                 noteType: noteType, approach: approach)
            } else {
                return ""  // diff==0, 递归终止
            }
        } else {
            // ── 休止符 ──
            if diff >= wholeSlots {
                return "\(wholeRest) " +
                       getString(diff: diff - wholeSlots, isRest: true, offbeat: false,
                                 noteType: noteType, approach: approach)
            } else if diff >= halfSlots {
                return "\(halfRest) " +
                       getString(diff: diff - halfSlots, isRest: true, offbeat: false,
                                 noteType: noteType, approach: approach)
            } else if diff >= quarterSlots {
                return "\(quarterRest) " +
                       getString(diff: diff - quarterSlots, isRest: true, offbeat: false,
                                 noteType: noteType, approach: approach)
            } else if diff >= eighthSlots {
                return "\(eighthRest) " +
                       getString(diff: diff - eighthSlots, isRest: true, offbeat: false,
                                 noteType: noteType, approach: approach)
            } else if diff >= sixteenthSlots {
                return "\(sixteenthRest) " +
                       getString(diff: diff - sixteenthSlots, isRest: true, offbeat: false,
                                 noteType: noteType, approach: approach)
            } else if diff >= thirtySecondSlots {
                return "\(thirtySecondRest) " +
                       getString(diff: diff - thirtySecondSlots, isRest: true, offbeat: false,
                                 noteType: noteType, approach: approach)
            } else {
                return ""  // diff==0, 递归终止
            }
        }
    }


    // MARK: - 内联切分音计算 (从 Tension.java 提取, generateSyncopation 依赖)
    // ──────────────────────────────────────────────
    // Java: Tension.getSyncopation(int[] onsets, int measures) — Longuet-Higgins & Lee (1984)
    //
    // 对每个未触发slot, 向前找到最近触发slot,
    // 计算 syncoValue = WEIGHTS[i] - WEIGHTS[nPos],
    // 若 syncoValue > 0 (即当前位置比前一个触发点更弱) → 累计入切分音值

    private static func getSyncopation(onsets: [Int], measures: Int) -> Int {
        // Java: int[] w = getWeightArray(measures, WEIGHTS);
        let w = getWeightArray(measures: measures, baseWeights: weights)
        var synco = 0

        for i in 0..<onsets.count {
            if onsets[i] == 0 {
                var nPos = i
                // Java: while(onsets[nPos] == 0 && nPos > 0) nPos--;
                while nPos > 0 && onsets[nPos] == 0 {
                    nPos -= 1
                }
                if onsets[nPos] != 0 {
                    let syncoValue = w[i] - w[nPos]
                    if syncoValue > 0 {
                        synco += syncoValue
                    }
                }
            }
        }
        return synco
    }

    /// Java: private static int[] getWeightArray(int measures, int[] weights) — Tension.java 第430-441行
    /// 将32元素权重数组重复扩展到 measures 小节长度
    private static func getWeightArray(measures: Int, baseWeights: [Int]) -> [Int] {
        let totalLength = baseWeights.count * measures
        var result = [Int](repeating: 0, count: totalLength)
        for m in 0..<measures {
            let offset = m * baseWeights.count
            for j in 0..<baseWeights.count {
                result[offset + j] = baseWeights[j]
            }
        }
        return result
    }

    // MARK: - P1-3 动态三连音生成

    ///  RhythmGenerator 三连音动态时值分配
    /// 将指定的基础时长按三连音比例(2:1:1)拆分, 替代固定模板
    /// - Parameters:
    ///   - baseDuration: 基础总时值 (slots, 如 120=四分音符, 240=二分)
    ///   - pitchPattern: 音高序列 (nil=同音重复)
    /// - Returns: 三连音 PhysicalNote 数组
    static func generateTriplet(baseDuration: Int,
                                pitchPattern: [Int]? = nil,
                                ratio: (Int, Int, Int) = (2, 1, 1)) -> [PhysicalNote] {
        let total = ratio.0 + ratio.1 + ratio.2
        let d1 = baseDuration * ratio.0 / total
        let d2 = baseDuration * ratio.1 / total
        let d3 = baseDuration - d1 - d2  // 修正取整误差

        let pitches = pitchPattern ?? [60, 60, 60]
        let p1 = pitches.count > 0 ? pitches[0] : 60
        let p2 = pitches.count > 1 ? pitches[1] : p1
        let p3 = pitches.count > 2 ? pitches[2] : p2

        return [
            PhysicalNote(midiPitch: p1, durationSlots: max(1, d1)),
            PhysicalNote(midiPitch: p2, durationSlots: max(1, d2)),
            PhysicalNote(midiPitch: p3, durationSlots: max(1, d3))
        ]
    }

    /// 三连音 + Swing偏移叠加: 对三连音组内第2/3音做swing修正
    static func generateTripletWithSwing(baseDuration: Int,
                                          pitchPattern: [Int]? = nil,
                                          swingValue: Double = 0.666) -> [PhysicalNote] {
        var triplet = generateTriplet(baseDuration: baseDuration, pitchPattern: pitchPattern)
        guard triplet.count == 3, swingValue != 0.5 else { return triplet }
        let swingOffset = Int(Double(baseDuration) * swingValue) - baseDuration / 2
        if swingOffset > 0 {
            triplet[1] = PhysicalNote(midiPitch: triplet[1].midiPitch,
                                       durationSlots: max(1, triplet[1].durationSlots + swingOffset))
        }
        return triplet
    }
}
