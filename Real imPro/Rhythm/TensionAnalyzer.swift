import Foundation

// MARK: - TensionAnalyzer
// 功能: 切分音分析 · 节拍层级 · 旋律重音 · 时值重音 · 复合节拍重音 · 棱角度 · 平均音高
//
// 论文引用:
//   getSyncopation / getSyncopation2:
//     Longuet-Higgins & Lee (1984) "The Rhythmic Interpretation of Monophonic Music"
//   getMetricalHierarchy:
//     Lerdahl & Jackendoff (1983) "A Generative Theory of Tonal Music"
//   getMelodicAccent:
//     Thomassen (1982) "Melodic accent: Experiments and a tentative model"
//   getDurationalAccent:
//     Parncutt (1994) "A perceptual model of pulse salience and metrical accent"
//   getMeterAccent:
//     Eerola (2003) "The Dynamics of Musical Expectancy" (复合模型)

struct TensionAnalyzer {

    // ═════════════════════════════════════════════════════════════
    // 静态常量 — Tension.java 第31-63行
    // ═════════════════════════════════════════════════════════════

    /// 32分音符精度节拍权重 (每小节32个slot)
    /// Java L33: private static int[] WEIGHTS = {0, -5, -4, -5, -3, -5, -4, -5, -2, ...}
    /// 值越负 = 节拍位置越弱 (0=强拍全音符, -5=弱拍32分音符)
    static let weights: [Int] = [
         0, -5, -4, -5,  -3, -5, -4, -5,  -2, -5, -4, -5,  -3, -5, -4, -5,
        -1, -5, -4, -5,  -3, -5, -4, -5,  -2, -5, -4, -5,  -3, -5, -4, -5
    ]

    /// 4拍精度节拍权重 (简化版, 每拍4个slot)
    /// Java L32: private static int[] WEIGHTS_4 = {0, -2, -1, -2}
    static let weights4: [Int] = [0, -2, -1, -2]

    /// 低精度每小节slot数 — L40: SLOTS_PER_MEASURE = 32
    static let slotsPerMeasure: Int = 32

    /// 高精度每小节slot数 (四分音符=120slots) — L41: SLOTS_PER_MEASURE2 = 480
    static let slotsPerMeasureHighRes: Int = 480

    /// 每分钟秒数 — L42: SECONDS_PER_MINUTE = 60
    private static let secondsPerMinute: Double = 60

    /// Parncutt时值重音参数 — L43-44: TAU=0.5, ACCENT_INDEX=2
    private static let tau: Double = 0.5
    private static let accentIndex: Double = 2

    // L45-62: 节拍层级时值阈值 (单位: 高精度slot = 1/480全音符)
    private static let wholeSlot: Int            = 480   // L45: WHOLE_NOTE
    private static let halfSlot: Int             = 240   // L47: HALF_NOTE
    private static let quarterSlot: Int          = 120   // L49: QUARTER_NOTE
    private static let eighthSlot: Int           = 60    // L51: EIGHTH_NOTE
    private static let eighthTripletSlot: Int    = 40    // L53: EIGHTH_NOTE_TRIPLET
    private static let sixteenthSlot: Int        = 30    // L55: SIXTEENTH_NOTE
    private static let sixteenthTripletSlot: Int = 20    // L57: SIXTEENTH_NOTE_TRIPLET
    private static let thirtySecondSlot: Int     = 15    // L59: THIRTY_SECOND_NOTE
    private static let thirtySecondTripletSlot: Int = 10 // L61: THIRTY_SECOND_NOTE_TRIPLET

    // L46-62: 对应的节拍层级值 (Lerdahl & Jackendoff 1983)
    //   全音符=0 > 二分=-1 > 四分=-2 > 八分=-3 >
    //   八分三连=-4 = 十六分=-4 > 十六分三连=-5 = 32分=-5 > 32分三连=-6
    private static let wholeValue: Int            = 0    // L46: WHOLE_NOTE_VALUE
    private static let halfValue: Int             = -1   // L48: HALF_NOTE_VALUE
    private static let quarterValue: Int          = -2   // L50: QUARTER_NOTE_VALUE
    private static let eighthValue: Int           = -3   // L52: EIGHTH_NOTE_VALUE
    private static let eighthTripletValue: Int    = -4   // L54: EIGHTH_NOTE_TRIPLET_VALUE
    private static let sixteenthValue: Int        = -4   // L56: SIXTEENTH_NOTE_VALUE
    private static let sixteenthTripletValue: Int = -5   // L58: SIXTEENTH_NOTE_TRIPLET_VALUE
    private static let thirtySecondValue: Int     = -5   // L60: THIRTY_SECOND_NOTE_VALUE
    private static let thirtySecondTripletValue: Int = -6 // L62: THIRTY_SECOND_NOTE_TRIPLET_VALUE

    /// 正值偏移量 (使getMetricalHierarchyList输出全部≥0) — L63: OFFSET = 6
    private static let hierarchyOffset: Int = 6


    // ═════════════════════════════════════════════════════════════
    // Thomassen 1982 旋律重音运动矩阵 — Tension.java 第33-39行
    //
    // 矩阵格式: [C1重音概率, C2重音概率]
    // C1 = interval1 的 motion 方向, C2 = interval2 的 motion 方向
    //
    // 例: C1UP_C2DOWN[0]=0.83 表示“先上后下”模式中当前音符有83%概率获得重音
    // ═════════════════════════════════════════════════════════════

    /// 同→同: 连续同音重复 (几乎不重音) — L33: C1SAME_C2SAME = {0.00001, 0}
    private static let c1same_c2same: [Double]   = [0.00001, 0]

    /// 异→同: 变化后静止 (C1重音) — L34: C1NOT_C2SAME = {1, 0}
    private static let c1not_c2same: [Double]    = [1, 0]

    /// 同→异: 同音后变化 (C2重音) — L35: C1SAME_C2NOT = {0.00001, 1}
    private static let c1same_c2not: [Double]    = [0.00001, 1]

    /// 上→下: 先上后下 — L36: C1UP_C2DOWN = {0.83, 0.17}
    private static let c1up_c2down: [Double]     = [0.83, 0.17]

    /// 下→上: 先下后上 — L37: C1DOWN_C2UP = {0.71, 0.29}
    private static let c1down_c2up: [Double]     = [0.71, 0.29]

    /// 上→上: 连续上行 — L38: C1UP_C2UP = {0.33, 0.67}
    private static let c1up_c2up: [Double]       = [0.33, 0.67]

    /// 下→下: 连续下行 — L39: C1DOWN_C2DOWN = {0.67, 0.33}
    private static let c1down_c2down: [Double]   = [0.67, 0.33]


    // MARK: - 方法1: getAngularity
    // ═════════════════════════════════════════════════════════════
    // Java L74-85: public static double getAngularity(int[] notes)
    //
    // 计算大跳音程(>3半音)占全部音程的比例。
    // 值越高 → 旋律越"棱角分明"(跳进多)
    // 值越低 → 旋律越"平滑"(级进多)

    static func getAngularity(notes: [Int]) -> Double {
        guard notes.count > 1 else { return 0 }          // L75: 防御
        var angular: Double = 0                           // L76: angularIntervals

        for i in 1..<notes.count {                       // L77: for each interval
            let interval = abs(notes[i] - notes[i - 1])   // L79: Math.abs(notes[i] - notes[i-1])
            if interval > 3 {                              // L79: > 3
                angular += 1                               // L81: angularIntervals++
            }
        }
        return angular / Double(notes.count - 1)          // L84: return angularIntervals / (n-1)
    }


    // MARK: - 方法2: getAveragePitchHeight
    // ═════════════════════════════════════════════════════════════
    // Java L92-100: public static int getAveragePitchHeight(int[] notes)
    //
    // 计算音符序列的平均MIDI音高

    static func getAveragePitchHeight(notes: [Int]) -> Int {
        guard !notes.isEmpty else { return 0 }            // L93: 防御
        let sum = notes.reduce(0, +)                      // L95-97: for(i:notes) sum += i
        return sum / notes.count                          // L99: return sum / notes.length
    }


    // MARK: - 方法3: getMeterAccent (Eerola 2003 复合模型)
    // ═════════════════════════════════════════════════════════════
    // Java L112-123: public double getMeterAccent(int[] onsets, int[] notes, int tempo)
    //
    // 三重音模型乘积:
    //   meterAccent = MetricalHierarchy × MelodicAccent × DurationalAccent
    // 对每个音符计算三因子乘积后取均值

    static func getMeterAccent(onsets: [Int], notes: [Int], tempo: Int) -> Double {
        let mh = getMetricalHierarchyList(onsets: onsets) // L114: getMetricalHierarchyList(onsets)
        let ma = getMelodicAccent(notes: notes)            // L115: getMelodicAccent(notes)
        let du = getDurationalAccent(onsets: onsets, tempo: tempo) // L116: getDurationalAccent(onsets,tempo)

        let count = min(mh.count, ma.count, du.count)      // 取最小交集长度
        guard count > 0 else { return 0 }                  // L117: 防御

        var sum: Double = 0                                 // L117: int sum = 0
        for i in 0..<count {
            sum += Double(mh[i]) * ma[i] * du[i]            // L120: sum += (mh[i] * ma[i] * du[i])
        }
        return sum / Double(count)                          // L122: return sum / mh.length
    }


    // MARK: - 方法4: getMetricalHierarchyList
    // ═════════════════════════════════════════════════════════════
    // Java L130-143: public static int[] getMetricalHierarchyList(int[] onsets)
    //
    // 对每个音符触发点(onsets[i]==1), 计算其 metrical hierarchy + OFFSET(6)
    // 输出长度 = 音符总数(非slot总数), 所有值 ≥ 0

    static func getMetricalHierarchyList(onsets: [Int]) -> [Int] {
        var result: [Int] = []                              // L132: new int[onsets.length]

        for i in 0..<onsets.count {                        // L135: for(int i=0; i<onsets.length; i++)
            if onsets[i] == 1 {                             // L137: if(onsets[i] == 1)
                // L138: metricalHierarchyList[listIndex] = getMetricalHierarchy(i) + OFFSET
                result.append(getMetricalHierarchy(index: i) + hierarchyOffset)
            }
        }
        return result                                       // L142: return metricalHierarchyList
    }


    // MARK: - 方法5: getMetricalHierarchy (Lerdahl & Jackendoff 1983)
    // ═════════════════════════════════════════════════════════════
    // Java L151-193: public static int getMetricalHierarchy(int index)
    //
    // 节拍层级判定 — 通过取模运算从大到小匹配:
    //   全音符=0 > 二分=-1 > 四分=-2 > 八分=-3 >
    //   八分三连=-4 = 十六分=-4 > 十六分三连=-5 = 32分=-5 > 32分三连=-6
    //
    // 参数 index: 高精度slot(480slots/全音符)绝对位置

    static func getMetricalHierarchy(index: Int) -> Int {
        // L153: if(index % WHOLE_NOTE == 0) return WHOLE_NOTE_VALUE
        if index % wholeSlot == 0            { return wholeValue }
        // L157: else if(index % HALF_NOTE == 0) return HALF_NOTE_VALUE
        else if index % halfSlot == 0        { return halfValue }
        // L161: else if(index % QUARTER_NOTE == 0) return QUARTER_NOTE_VALUE
        else if index % quarterSlot == 0     { return quarterValue }
        // L165: else if(index % EIGHTH_NOTE == 0) return EIGHTH_NOTE_VALUE
        else if index % eighthSlot == 0      { return eighthValue }
        // L169: else if(index % EIGHTH_NOTE_TRIPLET == 0) return EIGHTH_NOTE_TRIPLET_VALUE
        else if index % eighthTripletSlot == 0 { return eighthTripletValue }
        // L173: else if(index % SIXTEENTH_NOTE == 0) return SIXTEENTH_NOTE_VALUE
        else if index % sixteenthSlot == 0   { return sixteenthValue }
        // L177: else if(index % SIXTEENTH_NOTE_TRIPLET == 0) return SIXTEENTH_NOTE_TRIPLET_VALUE
        else if index % sixteenthTripletSlot == 0 { return sixteenthTripletValue }
        // L181: else if(index % THIRTY_SECOND_NOTE == 0) return THIRTY_SECOND_NOTE_VALUE
        else if index % thirtySecondSlot == 0 { return thirtySecondValue }
        // L185: else if(index % THIRTY_SECOND_NOTE_TRIPLET == 0) return THIRTY_SECOND_NOTE_TRIPLET_VALUE
        else if index % thirtySecondTripletSlot == 0 { return thirtySecondTripletValue }
        // L191: else return THIRTY_SECOND_NOTE_TRIPLET_VALUE
        else                                 { return thirtySecondTripletValue }
    }


    // MARK: - 方法6: getMelodicAccent (Thomassen 1982)
    // ═════════════════════════════════════════════════════════════
    // Java L200-257: public static double[] getMelodicAccent(int[] notes)
    //
    // 步骤:
    //   1. 构建 mel2[n-3][2] 矩阵: 对每三个连续音符, 分析两个音程方向组合
    //      mel2[i][0] = C1重音概率, mel2[i][1] = C2重音概率
    //   2. 卷积: p2[0]=1, p2[1]=mel2[0][0],
    //            p2[k] = mel2[k-2][1] × mel2[k-1][0]  (前C2 × 当前C1)
    //   3. p2[n-1] = mel2[last][1]
    //
    // [BUGFIX] 原版Java L227/231存在条件重复Bug:
    //   Java L227: else if(motion1 < 0 && motion2 < 0) → C1UP_C2UP
    //   Java L231: else if(motion1 < 0 && motion2 < 0) → C1DOWN_C2DOWN  (不可达!)
    //   已修正: L227→motion1>0&&motion2>0, L231→motion1<0&&motion2<0

    static func getMelodicAccent(notes: [Int]) -> [Double] {
        let n = notes.count
        guard n >= 3 else { return Array(repeating: 1.0, count: n) } // L201: 防御

        // L202: double[][] mel2 = new double[notes.length - 3][2]
        let mel2Rows = n - 3
        var mel2 = [[Double]](repeating: [0, 0], count: mel2Rows)

        // L203: for(int i = 0; i < notes.length - 3; i++)
        for i in 0..<mel2Rows {
            let m1 = notes[i + 1] - notes[i]      // L205: motion1 = notes[i+1] - notes[i]
            let m2 = notes[i + 2] - notes[i + 1]  // L206: motion2 = notes[i+2] - notes[i+1]

            // L207-234: 7路运动方向判定 → 查6组概率矩阵
            if m1 == 0 && m2 == 0 {                    // L207: 同→同
                mel2[i] = c1same_c2same                // L209: C1SAME_C2SAME → [0.00001, 0]
            } else if m1 != 0 && m2 == 0 {             // L211: 异→同
                mel2[i] = c1not_c2same                 // L213: C1NOT_C2SAME → [1, 0]
            } else if m1 == 0 && m2 != 0 {             // L215: 同→异
                mel2[i] = c1same_c2not                 // L217: C1SAME_C2NOT → [0.00001, 1]
            } else if m1 > 0 && m2 < 0 {               // L219: 上→下
                mel2[i] = c1up_c2down                  // L221: C1UP_C2DOWN → [0.83, 0.17]
            } else if m1 < 0 && m2 > 0 {               // L223: 下→上
                mel2[i] = c1down_c2up                  // L225: C1DOWN_C2UP → [0.71, 0.29]
            } else if m1 > 0 && m2 > 0 {               // [BUGFIX] L227原: m1<0&&m2<0
                mel2[i] = c1up_c2up                    // L229: C1UP_C2UP → [0.33, 0.67]
            } else if m1 < 0 && m2 < 0 {               // [BUGFIX] L231原: m1<0&&m2<0(重复)
                mel2[i] = c1down_c2down                // L233: C1DOWN_C2DOWN → [0.67, 0.33]
            } else {
                mel2[i] = [1.0, 0]                     // 理论不可达, 兜底
            }
        }

        // ── 卷积计算最终重音概率 ──
        var p2 = [Double](repeating: 0, count: n)      // L236: double[] p2 = new double[n]

        p2[0] = 1.0                                     // L237: p2[0] = 1
        p2[1] = mel2[0][0]                              // L238: p2[1] = mel2[0][0]

        // L239: for(int k = 2; k < notes.length - 2; k++)
        for k in 2..<(n - 2) {
            let first  = mel2[k - 2][1]                 // L241: mel2[k-2][2] — 注意Java用第2列
            let second = mel2[k - 1][0]                 // L242: mel2[k-1][1] — 注意Java用第1列

            // L243-254: 任一为0则用另一, 都不为0则相乘
            if first == 0 { p2[k] = second }            // L245: if(first==0) p2[k]=second
            else if second == 0 { p2[k] = first }       // L249: else if(second==0) p2[k]=first
            else { p2[k] = first * second }             // L253: else p2[k]=first*second
        }

        // L256: p2[notes.length - 1] = mel2[mel2.length - 1][1]
        if mel2Rows > 0 { p2[n - 1] = mel2[mel2Rows - 1][1] }
        else { p2[n - 1] = 1.0 }

        return p2                                       // L257: return p2
    }


    // MARK: - 方法7: getDurationalAccent (Parncutt 1994)
    // ═════════════════════════════════════════════════════════════
    // Java L266-276: public static double[] getDurationalAccent(int[] onsets, int tempo)
    //
    // Parncutt (1994) 时值重音公式:
    //   dAccent[i] = (1 − e^(−duration / 0.5))^2

    static func getDurationalAccent(onsets: [Int], tempo: Int) -> [Double] {
        // L268: double[] durations = getNoteDurationsInSecs(onsets, tempo)
        let durations = getNoteDurationsInSecs(onsets: onsets, tempo: tempo)

        // L269: double[] dAccents = new double[durations.length]
        var dAccents = [Double](repeating: 0, count: durations.count)

        // L270: for(int i = 0; i < durations.length; i++)
        for i in 0..<durations.count {
            let expVal = exp(-durations[i] / tau)        // L272: Math.exp((durations[i] * -1) / TAU)
            dAccents[i] = pow(1.0 - expVal, accentIndex) // L273: Math.pow((1 - exp), ACCENT_INDEX)
        }
        return dAccents                                  // L275: return dAccents
    }


    // MARK: - 方法8: getNoteDurationsInSecs (私有)
    // ═════════════════════════════════════════════════════════════
    // Java L284-310: private static double[] getNoteDurationsInSecs(int[] onsets, int tempo)
    //
    // 将高精度slot数组(480slots/全音符)转换为音符物理时长(秒)
    //   音符beats数 = 占用的slot数 / 480 / 4
    //   物理时长(秒) = beats数 / bps  (bps = tempo/60)

    private static func getNoteDurationsInSecs(onsets: [Int], tempo: Int) -> [Double] {
        let bps = Double(tempo) / secondsPerMinute       // L286: bps = tempo / SECONDS_PER_MINUTE
        var durations: [Double] = []                     // L289: durations array
        var noteLength = 0                               // L287: noteLength = 0
        var isNote = false                               // L288: note = false

        // L291: for(int i = 0; i < onsets.length; i++)
        for i in 0..<onsets.count {
            if onsets[i] == 1 {                          // L293: if(onsets[i] == 1)
                if isNote {                              // L295: if(note == true)
                    // L297: double beats = noteLength / SLOTS_PER_MEASURE2 / 4
                    let beats = Double(noteLength) / Double(slotsPerMeasureHighRes) / 4.0
                    durations.append(beats / bps)        // L298: durations[dIndex] = beats / bps
                }
                isNote = true                            // L301: note = true
                noteLength = 1                           // L302: noteLength = 1
            } else if isNote {                           // L304: else if(note == true)
                noteLength += 1                          // L306: noteLength++
            }
        }

        // 最后一个未闭合音符 (Java中原while循环隐式处理)
        if isNote, noteLength > 0 {
            let beats = Double(noteLength) / Double(slotsPerMeasureHighRes) / 4.0
            durations.append(beats / bps)
        }

        return durations                                 // L309: return durations
    }


    // MARK: - 方法9: getSyncopation (Longuet-Higgins & Lee 1984)
    // ═════════════════════════════════════════════════════════════
    // Java L340-371: public static int getSyncopation(int[] onsets, int measures)
    //
    // 切分音 = 弱拍触发点相对于前一个强拍触发点的WEIGHTS差值累加
    // 使用低精度 WEIGHTS 数组 (32slots/小节)

    static func getSyncopation(onsets: [Int], measures: Int) -> Int {
        // L342: int[] w = getWeightArray(measures, WEIGHTS)
        let w = getWeightArray(measures: measures, baseWeights: weights)
        var synco = 0                                     // L343: synco = 0

        // L346: for(int i = 0; i < onsets.length; i++)
        let limit = min(onsets.count, w.count)
        for i in 0..<limit {
            if onsets[i] == 0 {                           // L348: if(onsets[i] == 0)
                var nPos = i                              // L350: nPos = i

                // L351: while(onsets[nPos]==0 && nPos>0) nPos--
                while nPos > 0, nPos < onsets.count, onsets[nPos] == 0 {
                    nPos -= 1
                }

                // L355: if(!(onsets[nPos] == 0))
                if nPos < onsets.count, onsets[nPos] != 0 {
                    let sv = w[i] - w[nPos]              // L357: syncoValue = w[i] - w[nPos]
                    if sv > 0 { synco += sv }             // L358-360: if(syncoValue>0) synco+=syncoValue
                }
            }
        }
        return synco                                      // L370: return synco
    }


    // MARK: - 方法10: getSyncopation2 (改进版, 支持三连音)
    // ═════════════════════════════════════════════════════════════
    // Java L378-401: public static int getSyncopation2(int[] onsets)
    //
    // 改进: 用 getMetricalHierarchy() 替代 WEIGHTS 查表,
    // 支持三连音等非2的幂次节奏划分(如40slots八分三连音)
    // 使用高精度slot (480slots/全音符)

    static func getSyncopation2(onsets: [Int]) -> Int {
        var synco = 0                                     // L380: synco = 0

        // L381: for(int i = 0; i < onsets.length; i++)
        for i in 0..<onsets.count {
            if onsets[i] == 0 {                           // L383: if(onsets[i] == 0)
                var nPos = i                              // L385: nPos = i

                // L386: while(onsets[nPos]==0 && nPos>0) nPos--
                while nPos > 0, nPos < onsets.count, onsets[nPos] == 0 {
                    nPos -= 1
                }

                // L390: if(!(onsets[nPos] == 0))
                if nPos < onsets.count, onsets[nPos] != 0 {
                    // L392: syncoValue = getMetricalHierarchy(i) - getMetricalHierarchy(nPos)
                    let sv = getMetricalHierarchy(index: i) - getMetricalHierarchy(index: nPos)
                    if sv > 0 { synco += sv }             // L393-395
                }
            }
        }
        return synco                                      // L400: return synco
    }


    // MARK: - 方法11: getWindowedSyncopation (WEIGHTS版滑动窗)
    // ═════════════════════════════════════════════════════════════
    // Java L319-332: public static int[] getWindowedSyncopation(int[] onsets, int measures, int windowSize)
    //
    // 按 windowSize 小节切分, 逐窗调用 getSyncopation

    static func getWindowedSyncopation(onsets: [Int], measures: Int, windowSize: Int) -> [Int] {
        let slotsPerWindow = slotsPerMeasure * windowSize  // L321: SLOTS_PER_MEASURE * windowSize
        let numWindows = measures / windowSize             // L323: output.length
        var output = [Int](repeating: 0, count: numWindows)
        var outIdx = 0                                     // L322: outputIndex = 0

        // L324: for(int onsetIndex=0; onsetIndex<onsets.length-1; onsetIndex+=slotsPerWindow)
        var onsetIdx = 0
        while onsetIdx < onsets.count, outIdx < numWindows {
            let end = min(onsetIdx + slotsPerWindow, onsets.count)
            let slice = Array(onsets[onsetIdx..<end])     // L327: System.arraycopy
            output[outIdx] = getSyncopation(onsets: slice, measures: windowSize) // L328
            outIdx += 1                                    // L329: outputIndex++
            onsetIdx += slotsPerWindow
        }
        return output                                      // L331: return output
    }


    // MARK: - 方法12: getWindowedSyncopation2 (三连音版滑动窗)
    // ═════════════════════════════════════════════════════════════
    // Java L410-423: public static int[] getWindowedSyncopation2(int[] onsets, int measures, int windowSize)
    //
    // 使用 getSyncopation2 (高精度+三连音) 的滑动窗口版本

    static func getWindowedSyncopation2(onsets: [Int], measures: Int, windowSize: Int) -> [Int] {
        let slotsPerWindow = slotsPerMeasureHighRes * windowSize // L412: SLOTS_PER_MEASURE2 * windowSize
        let numWindows = measures / windowSize             // L414
        var output = [Int](repeating: 0, count: numWindows)
        var outIdx = 0                                     // L413

        var onsetIdx = 0
        while onsetIdx < onsets.count, outIdx < numWindows {
            let end = min(onsetIdx + slotsPerWindow, onsets.count)
            let slice = Array(onsets[onsetIdx..<end])     // L418: System.arraycopy
            output[outIdx] = getSyncopation2(onsets: slice) // L419
            outIdx += 1
            onsetIdx += slotsPerWindow
        }
        return output                                      // L422
    }


    // MARK: - 方法13: getWeightArray (私有辅助)
    // ═════════════════════════════════════════════════════════════
    // Java L430-441: private static int[] getWeightArray(int measures, int[] weights)
    //
    // 将基础权重数组(如32元素)重复扩展到 measures 小节长度

    private static func getWeightArray(measures: Int, baseWeights: [Int]) -> [Int] {
        let totalLen = baseWeights.count * measures       // L432: weights.length * measures
        var result = [Int](repeating: 0, count: totalLen) // L433: Arrays.copyOf

        // L435: for(int i = measures; i > 1; i--)
        for m in 0..<measures {
            let offset = m * baseWeights.count
            // L437: System.arraycopy(weights, 0, weightArray, offset, weights.length)
            for j in 0..<baseWeights.count {
                result[offset + j] = baseWeights[j]
            }
        }
        return result                                      // L440: return weightArray
    }
}
