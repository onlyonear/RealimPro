import Foundation

// MARK: - PostProcessorFull — 完整移植 Impro-Visor RoadMap findKeys 调性分析
//
// 移植来源 (权威参考):
//   核心算法  /Users/onlyonear/Desktop/imp/roadmap/cykparser/PostProcessor.java
//            findKeys()            行 149-367
//            diatonicChordCheck()  行 859-940
//            findModeFromQuality    ChordBlock.java:502-521
//   规则数据  /Users/onlyonear/Desktop/imp/vocab/My.dictionary
//            equiv 规则            行 60-80
//            diatonic 规则         行 84-86
//   颜色     /Users/onlyonear/Desktop/imp/roadmap/RoadMapSettings.java
//            generateColors()      行 365-370
//
// 已取代 TonalAnalyzer (MVP 临时方案, 已删除):
//   原 TonalAnalyzer 用 "CYK 砖名匹配 + 属七根音+纯四度" 启发式推断调性中心。
//   PostProcessorFull 忠实移植原版 findKeys 的 "反向遍历 + diatonicChordCheck
//   调内吸收" 算法, 输出每个和弦的调性中心, 并采用原版绝对 PC 色表着色。
//
// 设计约束 (不破坏现有功能):
//   - 本文件为纯函数式分析模块, 只读 roadmap.flattenRoadmap()。
//   - 不复用/不修改 现有 KeySpan / KeySpanFactory / JazzBlock / ChordBlock / Brick。
//   - 输出沿用现有 AnalysisResult 三件套, 渲染层零感知。
//   - 分析侧使用独立模型 (RoadQualityClass / AnalysisChord / RoadKeySpan)。

enum PostProcessorFull {

    // ═══════════════════════════════════════════════════════════
    // 1. 分析侧数据模型
    // ═══════════════════════════════════════════════════════════

    /// 和弦质量类别。
    /// 对应 My.dictionary 的 5 条 equiv 等价规则的代表和弦 (每条规则首元素):
    ///   (equiv C   CM   CMajor C6 ...)   → major     (代表 "C")
    ///   (equiv Cm  Cminor Cm6 ...)       → minor     (代表 "Cm")
    ///   (equiv Cm7 Cm9 Cm11 Cm13)        → minor7    (代表 "Cm7")
    ///   (equiv Cm7b5 Cm9b5 Cm11b5)       → halfDim   (代表 "Cm7b5")
    ///   (equiv C7  C7alt Csus ...)       → dominant  (代表 "C7")
    ///   (equiv Co  Cdim Cdim7 ...)       → diminished(代表 "Co")
    enum RoadQualityClass: Hashable {
        case major, minor, minor7, halfDim, dominant, diminished, other
    }

    /// 分析侧单和弦 block (扁平化后的最小单元)。
    /// 对应 Java Block/ChordBlock 的调性元数据子集。
    struct AnalysisChord {
        let name: String
        let rootPC: Int            // key: 根音 pitch class (0=C ... 11=B)
        let mode: String           // findModeFromQuality: "Major"/"Dominant"/"Minor"
        let qualityClass: RoadQualityClass
        let duration: Double       // 拍数
        let isSectionEnd: Bool     // 对应 Java Block.isSectionEnd()
    }

    /// 调性跨度 (对应 Java KeySpan: key + mode + duration)。
    /// 用和弦索引区间 [startIdx, endIdx) 表达 duration, 便于逐和弦映射。
    struct RoadKeySpan {
        var key: Int               // 调性中心根音 PC
        var mode: String           // "Major"/"Minor"/"Dominant"
        var startIdx: Int          // 覆盖的和弦起始索引 (inclusive)
        var endIdx: Int            // 覆盖的和弦结束索引 (exclusive)
    }

    // ═══════════════════════════════════════════════════════════
    // 2. 规则数据 (硬编码自 My.dictionary, 注释标注来源行号)
    // ═══════════════════════════════════════════════════════════

    /// 调内和弦集: [调式 -> [根音PC -> 允许的质量类别集合]]。
    /// 来源: My.dictionary:84-86
    ///   (diatonic Major    C Dm Dm6 Dm7 Dm9 Dm11 Em Em7 F G7 G7sus Gsus Am Am7 Am9 Bo Bm7b5)
    ///   (diatonic Minor    Cm Dm7b5 Dm9b5 Eb Fm Fm7 Fm6 Fm9 F G7 Gm7 G7sus Gsus Ab Am7b5 Bb7 Bo Bo7)
    ///   (diatonic Dominant C7 C7sus4 C7sus Csus C9 C9sus4 Dm Dm7 Eo Em7b5 F Fsus G7sus Gsus Am Am7 Bb)
    /// 注: sus/sus4/7sus/9sus 经 equiv 规则5 归入 dominant 类 (代表 "C7")。
    static let diatonicSets: [String: [Int: Set<RoadQualityClass>]] = [
        "Major": [
            0:  [.major],                       // C
            2:  [.minor, .minor7, .halfDim],    // Dm Dm6 Dm7 Dm9 Dm11 (+ Dm7b5 借用 iiø, 修 "Iø" 荒谬标注)
            4:  [.minor, .minor7],              // Em Em7
            5:  [.major],                       // F
            7:  [.dominant],                    // G7 G7sus Gsus
            9:  [.minor, .minor7],              // Am Am7 Am9
            11: [.diminished, .halfDim],        // Bo Bm7b5
        ],
        "Minor": [
            0:  [.minor],                       // Cm
            2:  [.halfDim],                     // Dm7b5 Dm9b5
            3:  [.major],                       // Eb
            5:  [.minor, .minor7, .major],      // Fm Fm7 Fm6 Fm9 F
            7:  [.dominant, .minor7],           // G7 Gm7 G7sus Gsus
            8:  [.major],                       // Ab
            9:  [.halfDim],                     // Am7b5
            10: [.dominant],                    // Bb7
            11: [.diminished],                  // Bo Bo7
        ],
        "Dominant": [
            0:  [.dominant],                    // C7 C9 C7sus4 C7sus Csus C9sus4
            2:  [.minor, .minor7],              // Dm Dm7
            4:  [.diminished, .halfDim],        // Eo Em7b5
            5:  [.major, .dominant],            // F Fsus
            7:  [.dominant],                    // G7sus Gsus
            9:  [.minor, .minor7],              // Am Am7
            10: [.major],                       // Bb
        ],
    ]

    // ═══════════════════════════════════════════════════════════
    // 3. 和弦名解析与质量分类 (对应 equiv 等价规则 + findModeFromQuality)
    // ═══════════════════════════════════════════════════════════

    /// 符号归一化: 统一各种记谱符号, 保留大小写 (M=大七, m=小)。
    static func normalizeQuality(_ raw: String) -> String {
        var q = raw
        q = q.replacingOccurrences(of: "♭", with: "b")
        q = q.replacingOccurrences(of: "♯", with: "#")
        q = q.replacingOccurrences(of: "−", with: "-")   // U+2212
        q = q.replacingOccurrences(of: "–", with: "-")   // en-dash
        q = q.replacingOccurrences(of: "Δ", with: "maj")
        q = q.replacingOccurrences(of: "δ", with: "maj")
        q = q.replacingOccurrences(of: "^", with: "maj")   // iReal Pro 的 maj7 简写 (D^ = Dmaj7, D^7 = Dmaj7)
        q = q.replacingOccurrences(of: "ø", with: "m7b5")
        q = q.replacingOccurrences(of: "°", with: "dim")
        return q
    }

    /// 从和弦名拆出 (根音PC, 质量串)。
    /// 根音规则: 首字母大写 + 可选 #/b。质量 = 根音之后剩余部分。
    static func parseRootQuality(_ name: String) -> (rootPC: Int, quality: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        var rootLen = 1
        if n.count > 1 {
            let second = n[n.index(n.startIndex, offsetBy: 1)]
            if second == "#" || second == "b" { rootLen = 2 }
        }
        let rootStr = String(n.prefix(rootLen)).uppercased()
        let quality = rootLen < n.count ? String(n.dropFirst(rootLen)) : ""
        let pc = rootPC(from: rootStr)
        return (pc, quality)
    }

    /// 根音名 → pitch class。
    static func rootPC(from rootStr: String) -> Int {
        switch rootStr {
        case "C": return 0;  case "C#", "DB": return 1;  case "D": return 2
        case "D#", "EB": return 3;  case "E": return 4;  case "F": return 5
        case "F#", "GB": return 6;  case "G": return 7
        case "G#", "AB": return 8;  case "A": return 9
        case "A#", "BB": return 10; case "B": return 11
        default: return 0
        }
    }

    /// 质量串 → 质量类别 (对应 My.dictionary 的 5 条 equiv 等价规则)。
    /// 检查顺序至关重要: halfDim(含 m7b5) 必须先于 minor7, maj 必须先于 m。
    static func qualityClass(ofQuality rawQuality: String) -> RoadQualityClass {
        let q = normalizeQuality(rawQuality)
        let lower = q.lowercased()

        // (equiv Co Cdim Cdim7 Co7 CoM7) → diminished
        if lower.hasPrefix("dim") || lower.hasPrefix("o") { return .diminished }

        // (equiv Cm7b5 Cm9b5 Cm11b5) → halfDim
        if lower.contains("m7b5") || lower.contains("m9b5") || lower.contains("m11b5")
            || lower.hasPrefix("h7") || lower.contains("half") { return .halfDim }

        // (equiv C CM CMajor C6 C69 Cadd9 Cadd2 Csus2 ...) → major
        // 注: "M" 用大小写敏感判断 (M7=大七), "maj"/"mΔ" 已归一化为 maj。
        if lower.hasPrefix("maj") || q.hasPrefix("M")
            || lower.isEmpty || lower.hasPrefix("6") || lower.hasPrefix("69")
            || lower.hasPrefix("add") || lower.hasPrefix("sus2") { return .major }

        // (equiv Cm7 Cm9 Cm11 Cm13) → minor7
        if lower.hasPrefix("m7") || lower.hasPrefix("m9")
            || lower.hasPrefix("m11") || lower.hasPrefix("m13")
            || lower.hasPrefix("-7") { return .minor7 }

        // (equiv Cm Cminor Cm6 Cm69 CmM7 Cm+ Cmb6 Cm#5) → minor
        if lower.hasPrefix("m") || lower.hasPrefix("min") || lower.hasPrefix("-") {
            return .minor
        }

        // (equiv C7 C7alt C7b9 ... Csus Csus4 C7sus ...) → dominant
        if lower.hasPrefix("7") || lower.hasPrefix("9") || lower.hasPrefix("13")
            || lower.hasPrefix("sus") { return .dominant }

        // aug/+ 等不在任何等价规则 → 非调内
        return .other
    }

    /// 质量串 → 调式 (对应 ChordBlock.findModeFromQuality, Java ChordBlock.java:502-521)。
    ///   M/""/6 开头 → Major; 7/9/11/13 开头 → Dominant; 其余 → Minor。
    static func chordMode(ofQuality rawQuality: String) -> String {
        let q = normalizeQuality(rawQuality)
        let lower = q.lowercased()
        if lower.hasPrefix("maj") || q.hasPrefix("M") || lower.isEmpty || lower.hasPrefix("6") {
            return "Major"
        }
        if lower.hasPrefix("7") || lower.hasPrefix("9")
            || lower.hasPrefix("11") || lower.hasPrefix("13") {
            return "Dominant"
        }
        return "Minor"
    }

    // ═══════════════════════════════════════════════════════════
    // 4. diatonicChordCheck (核心: PostProcessor.java:859-940)
    // ═══════════════════════════════════════════════════════════

    /// 判断一个和弦是否调内 (diatonic) 于给定 key/mode。
    /// 移植自 Java diatonicChordCheck:
    ///   1) 减和弦永远调内 (行 864-867: isDiminished → true);
    ///   2) 将和弦转调到 C (等价于取相对 key 的音程 interval);
    ///   3) 经 equiv 规则确定代表质量类 (cSym);
    ///   4) 检查 (interval, 质量类) 是否在 diatonic 规则集合内。
    static func diatonicChordCheck(chord: AnalysisChord, key: Int, mode: String) -> Bool {
        // Java 行 864-867: 减和弦直接调内 (经过和弦启发式)
        if chord.qualityClass == .diminished { return true }

        // Java 行 870-877: transpose(OCTAVE - key) → 相对 key 的音程
        let interval = (chord.rootPC - key + 12) % 12

        // 不在任何 equiv 规则 (cSym == null) → 非调内
        if chord.qualityClass == .other { return false }

        // Java 行 920-936: 检查 (interval, 质量类) 是否在 diatonic 集合内
        guard let set = diatonicSets[mode] else { return false }
        return set[interval]?.contains(chord.qualityClass) ?? false
    }

    // ═══════════════════════════════════════════════════════════
    // 5. findKeys 主循环 (PostProcessor.java:149-367)
    // ═══════════════════════════════════════════════════════════

    /// 反向遍历和弦, 用 diatonicChordCheck 做调内吸收, 输出调性跨度链。
    ///
    /// 与原版差异 (已向用户说明的可接受偏差):
    ///   - iOS 侧 flattenRoadmap() 丢失 Brick 边界, 故以 "单和弦" 为最小 block
    ///     (原版在 Brick 边界做归并判定)。Brick 级 ii-V-of-X 分组列为后续 P2。
    ///   - NOCHORD 已在 ContentView 构建 roadmap 前被过滤, 无需处理。
    static func findKeys(_ chords: [AnalysisChord], tonicPC: Int) -> [RoadKeySpan] {
        guard !chords.isEmpty else { return [] }
        let n = chords.count

        // Java 行 185-189: 用最后一个和弦初始化 current KeySpan
        var current = RoadKeySpan(
            key: chords[n - 1].rootPC,
            mode: chords[n - 1].mode,
            startIdx: n - 1, endIdx: n
        )
        var keymap: [RoadKeySpan] = []

        // Java 行 196: 反向遍历 (i 从 n-2 到 0)
        var i = n - 2
        while i >= 0 {
            let block = chords[i]

            // ── 主调 tonic 锚定 ──
            // root==tonicPC 的 major 和弦 (全曲主调的主和弦) 强制归主调, 而非被邻近调
            // 吸收为借用音。修 A Foggy Day 的 M5 F^7 被 A 小调吸收成 bVI (F 恰是 A 小调
            // 的自然 bVI, diatonicChordCheck 判定调内) 的问题 —— 主调 tonic 不应被降级。
            // 转调 tonic (如 Giant Steps 的 B^7/G^7) root≠tonicPC, 不受影响。
            let isTonicAnchor = block.qualityClass == .major && block.rootPC == tonicPC
            if isTonicAnchor {
                if current.key == tonicPC && current.mode == "Major" {
                    current.startIdx = i            // 已是主调, 向前扩展
                } else {
                    keymap.insert(current, at: 0)   // 终结前一调
                    current = RoadKeySpan(key: tonicPC, mode: "Major",
                                           startIdx: i, endIdx: i + 1)
                }
            } else if block.isSectionEnd {
                // Java 行 202-251: 段落结尾强制开新 KeySpan
                let entry = current                    // 刚终结的 KeySpan
                keymap.insert(entry, at: 0)
                current = RoadKeySpan(key: block.rootPC, mode: block.mode,
                                       startIdx: i, endIdx: i + 1)
                // Java 行 217-223: 若段落结尾和弦调内于前一键, 则继承前一键
                if diatonicChordCheck(chord: block, key: entry.key, mode: entry.mode) {
                    current.key = entry.key
                    current.mode = entry.mode
                }
            } else {
                // Java 行 326-344 (ChordBlock 分支)
                if diatonicChordCheck(chord: block, key: current.key, mode: current.mode) {
                    current.startIdx = i            // augmentDuration → 向前扩展
                } else {
                    keymap.insert(current, at: 0)
                    current = RoadKeySpan(key: block.rootPC, mode: block.mode,
                                           startIdx: i, endIdx: i + 1)
                }
            }
            i -= 1
        }

        // Java 行 358: 加入最前的 KeySpan
        keymap.insert(current, at: 0)
        return keymap
    }

    // ═══════════════════════════════════════════════════════════
    // 5b. findLaunchers 移植 (PostProcessor.java:377-536 + doesResolve 964-972)
    // ═══════════════════════════════════════════════════════════

    /// 移植自 Java findLaunchers 的 dominant 分支 (行 478-528) + doesResolve (行 964-972) +
    /// CYK brick 的 key 语义 (ii-V / I-vi-ii-V / turnaround 共享 tonic)。
    ///
    /// 处理 "属七解决到 tonic" 的关系, 并把整个 "预解决进行" (ii / vi / iii) 一并归到 tonic。
    ///
    /// 六优先级 (属七隐含 tonic t = (属七根音 + 纯四度) % 12):
    ///   优先级 1  属七→major tonic (三种解决音程, 均归该 tonic):
    ///             V-I   : tonic = v+5  (正常属七)
    ///             bII-I : tonic = v+11 (tritone sub, Db7→C, 标 bII7)
    ///             bVII-I: tonic = v+2  (backdoor, Bb7→C, 标 bVII7)
    ///   优先级 1b section-end 属七→minor tonic (跨 section 转调, Java 行 518)
    ///   优先级 1c 小调 iiø-V: 前面 halfDim iiø, 属七归小调 tonic t (标 V7alt)
    ///   优先级 2  次级属七 V/ii: v→ii(v+5)→V(v+10)→I(v+3), 属七归主调 v+3 (标 VI7)
    ///   优先级 3  循环回绕: 最后一个属七解决到开头 tonic (Java 行 489-499)
    ///   优先级 4  ii-V 结构: 属七前面紧邻 ii (根音=t+2), 即使 tonic 不在进行里
    ///   优先级 5  IV7 借用: 属七前面是 major tonic 且属七=前面+5 (blues 四级属七, 标 IV7)
    ///
    /// 归并后向前扩展: 从 ii 继续向前, 把连续的 diatonic 非 major/非 dominant 和弦
    /// (如 I-vi-ii-V 的 vi、iii-vi-ii-V 的 iii) 一并归 t, 直到遇到 major/dominant
    /// (可能是另一个 tonic 或属七) 或 section 边界。
    static func resolveDominantLaunchers(chords: [AnalysisChord],
                                         tonalCenters: inout [Int],
                                         keyModes: inout [String],
                                         tonicPC: Int,
                                         songMode: JazzMode) {
        let n = chords.count
        guard n >= 2 else { return }

        // ii 质量类: minor(纯小) / minor7 / halfDim (iiø)
        func isII(_ c: AnalysisChord) -> Bool {
            c.qualityClass == .minor || c.qualityClass == .minor7 || c.qualityClass == .halfDim
        }

        for i in 0..<n {
            let chord = chords[i]
            // Java 行 479: 仅处理属七 (dominant)
            guard chord.qualityClass == .dominant else { continue }

            let v = chord.rootPC
            let t = (v + 5) % 12   // 隐含 tonic (属七 + 纯四度下行解决)

            var tonicRoot: Int?
            var tonicMode: String?
            var resolveNextMinor = false   // 优先级 2b 命中: V-i, 需同时归后面的 minor tonic

            // ── 优先级 1: 属七解决到下一个 major tonic ──
            //   三种解决音程 (均归该 major tonic):
            //     V-I    : tonic = v+5  (正常属七)
            //     bII-I  : tonic = v+11 (tritone sub, Db7→C, 标 bII7)
            //     bVII-I : tonic = v+2  (backdoor, Bb7→C, 标 bVII7)
            if i < n - 1, chords[i + 1].qualityClass == .major {
                let next = chords[i + 1].rootPC
                if next == (v + 5) % 12 || next == (v + 11) % 12 || next == (v + 2) % 12 {
                    tonicRoot = next
                    tonicMode = "Major"
                }
            }
            // ── 优先级 1b: section-end 属七解决到下一个 minor tonic (跨 section 转调,
            //    对应 Java 行 518 doesResolve && isSectionEnd, 不限目标质量) ──
            if tonicRoot == nil, i < n - 1, chord.isSectionEnd,
               chords[i + 1].rootPC == (v + 5) % 12 {
                tonicRoot = (v + 5) % 12
                tonicMode = chords[i + 1].mode
            }
            // ── 优先级 1c: 小调 iiø-V (前面 halfDim iiø, 归小调 tonic t) ──
            //   例: Em7b5-A7b9 的 A7b9 = D 小调 V7alt, 优先于次级属七 VI7
            if tonicRoot == nil, i > 0, chords[i - 1].qualityClass == .halfDim,
               chords[i - 1].rootPC == (t + 2) % 12 {
                tonicRoot = t
                tonicMode = "Minor"
            }
            // ── 优先级 2: 次级属七 V/ii (v → ii(v+5) → V(v+10) → I(v+3)) ──
            //   例: Em7-A7-Dm7-G7-Cmaj7 的 A7 = V/ii = VI7 of C, 归主调 v+3
            if tonicRoot == nil, i < n - 3,
               isII(chords[i + 1]), chords[i + 1].rootPC == (v + 5) % 12,
               chords[i + 2].qualityClass == .dominant, chords[i + 2].rootPC == (v + 10) % 12,
               chords[i + 3].qualityClass == .major, chords[i + 3].rootPC == (v + 3) % 12 {
                tonicRoot = (v + 3) % 12
                tonicMode = "Major"
            }
            // ── 优先级 2b: 属七 → minor tonic (V-i, 段落内 minor 解决) ──
            //   例: All Of Me 的 A7-D-7 = V-i of D minor, A7 归 D 标 V (而非独立 A 调标 I)。
            //   排在优先级 2 (完整 ii-V-I 次级属七) 之后, 不抢 V/ii 的 VI7 判断。
            if tonicRoot == nil, i < n - 1,
               (chords[i + 1].qualityClass == .minor || chords[i + 1].qualityClass == .minor7),
               chords[i + 1].rootPC == (v + 5) % 12 {
                tonicRoot = (v + 5) % 12
                tonicMode = "Minor"
                resolveNextMinor = true
            }
            // ── 优先级 3: 循环回绕 (最后属七 -> 开头 tonic) 或 解决到歌曲主调 ──
            if tonicRoot == nil, i == n - 1 {
                if chords[0].rootPC == (v + 5) % 12 {
                    tonicRoot = (v + 5) % 12
                    tonicMode = chords[0].mode
                } else if (v + 5) % 12 == tonicPC {
                    tonicRoot = tonicPC
                    tonicMode = (songMode == .minor) ? "Minor" : "Major"
                }
            }
            // ── 优先级 4: ii-V 结构 (前面 ii, 隐含 tonic t) ──
            if tonicRoot == nil, i > 0, isII(chords[i - 1]), chords[i - 1].rootPC == (t + 2) % 12 {
                tonicRoot = t
                tonicMode = (chords[i - 1].qualityClass == .halfDim) ? "Minor" : "Major"
            }
            // ── 优先级 5: IV7 借用 (大调 IV 位置的属七, blues/借用) ──
            //   例: Gm7-C7-Fmaj7-Bb7 的 Bb7 = F 的 IV7 (Fmaj7→Bb7 是 I→IV7), 归 F 标 IV7。
            //   条件: 前面是 major tonic, 且属七根音 = 前面 tonic + 5 (属七是前面的 IV)。
            //   Java 原版 diatonic 规则里 Major 的 IV 只有 major (不含 dominant), 故
            //   findKeys 会把 IV7 独立成新调; 但 Java 的级数标注相对全曲主调标 IV7,
            //   这里在调性中心层就把它归回前面的 major tonic, 对齐级数语义。
            if tonicRoot == nil, i > 0, chords[i - 1].qualityClass == .major,
               (chords[i - 1].rootPC + 5) % 12 == v {
                tonicRoot = chords[i - 1].rootPC
                tonicMode = "Major"
            }

            guard let tr = tonicRoot, let tm = tonicMode else { continue }

            // 归 V
            tonalCenters[i] = tr
            keyModes[i] = tm

            // 优先级 2b V-i: 同时把后面的 minor tonic 也归 t (标 i)。
            //   修 All Of Me 的 A7-D-7: A7 归 D 后 D-7 仍残留 tc=A 标 iv 的问题。
            if resolveNextMinor, i < n - 1 {
                tonalCenters[i + 1] = tr
                keyModes[i + 1] = tm
                // 持续 minor tonic: 向后归连续的相同根音 minor tonic (D-7 持续两小节等)
                var k = i + 2
                while k < n, chords[k].rootPC == tr,
                      (chords[k].qualityClass == .minor || chords[k].qualityClass == .minor7) {
                    tonalCenters[k] = tr
                    keyModes[k] = tm
                    k += 1
                }
            }

            // 归前面的预解决和弦 (ii / iii / vi 等 diatonic 非 major/非 dominant), 并向前扩展
            if i > 0 {
                let prev = chords[i - 1]
                if prev.qualityClass != .major && prev.qualityClass != .dominant,
                   diatonicChordCheck(chord: prev, key: tr, mode: tm) {
                    tonalCenters[i - 1] = tr
                    keyModes[i - 1] = tm

                    var j = i - 2
                    while j >= 0 {
                        let c = chords[j]
                        // 遇 major (可能是另一个 tonic) 或 dominant (另一个属七) 停止
                        if c.qualityClass == .major || c.qualityClass == .dominant { break }
                        // 若 c 前面是 dominant 且 c 是其 V-i 解决目标, 停止 (c 是前一个调的 tonic)
                        if j > 0, chords[j - 1].qualityClass == .dominant,
                           c.rootPC == (chords[j - 1].rootPC + 5) % 12 { break }
                        // 不跨过 section 边界
                        if c.isSectionEnd { break }
                        // 连续 diatonic 的非 major/非 dominant 和弦 (vi / iii / ii 等) 归 t
                        if diatonicChordCheck(chord: c, key: tr, mode: tm) {
                            tonalCenters[j] = tr
                            keyModes[j] = tm
                            j -= 1
                        } else {
                            break
                        }
                    }
                }
            }
        }

        // ── 副属链后处理: 属七 → 属七 (V/V 链), 前面的副属归后面的 tonic ──
        //   Java Dominant-Cycle brick: D7-G7 (key=C), A7-D7-G7 (key=C)
        for i in stride(from: n - 2, through: 0, by: -1) {
            guard chords[i].qualityClass == .dominant else { continue }
            guard chords[i + 1].qualityClass == .dominant else { continue }
            guard chords[i + 1].rootPC == (chords[i].rootPC + 5) % 12 else { continue }
            // 排除 ii-V of V: 属七前面是它的 ii (root = v+7) 时, 它是 ii-V 的 V, 不是副属链
            if i > 0, isII(chords[i - 1]), chords[i - 1].rootPC == (chords[i].rootPC + 7) % 12 { continue }
            tonalCenters[i] = tonalCenters[i + 1]
            keyModes[i] = keyModes[i + 1]
        }

        // ── 兜底: 独立成调的属七/半减七/减七 归全曲主调 ──
        //   findKeys 会把无解决目标的属七/半减七独立成自己的根音调, 标荒谬的 I/Iø
        //   (tonic 不可能是 dominant/halfDim/diminished)。这里统一归回全曲主调,
        //   让 degreeLabel 相对主调算出正确级数 (如 B7#11→bVII7 of Db, D7#11→II7 of C)。
        for i in 0..<n {
            let c = chords[i]
            let isNonTonic = c.qualityClass == .dominant
                || c.qualityClass == .halfDim
                || c.qualityClass == .diminished
            guard isNonTonic else { continue }
            guard tonalCenters[i] == c.rootPC, c.rootPC != tonicPC else { continue }
            tonalCenters[i] = tonicPC
            keyModes[i] = (songMode == .minor) ? "Minor" : "Major"
        }
    }

    // ═══════════════════════════════════════════════════════════
    // 5c. 借用 major 后处理 (modal interchange)
    // ═══════════════════════════════════════════════════════════

    /// 识别「短暂偏离主调后立即回到主调」的借用大和弦 (modal interchange), 归回主调
    /// 标 bII(拿坡里)/bVI/bVII, 而非独立成调标 I。
    ///
    /// 保守原则: 只处理三种形态明确、信号单一的借用, 避免误判 Giant Steps 这类大三度
    /// 转调 (其 tonic 根音虽落在主调的 bVI/bIII 位置, 但后面接的是新调的 V-I, 而非
    /// 主调的 V-I):
    ///   - bII (拿坡里, rel=+1) : 后续 ≤4 个和弦内回到主调 I
    ///       例 A Flower (Db) 的 D^7→Eb7→D^→Db6
    ///   - bVI (rel=+8)          : 后面紧邻主调 V (dominant, root=主调+7)
    ///       例 Night And Day (C) 的 Ab^7→G7→C^7
    ///   - bVII (rel=+10)        : 后面紧邻主调 I (major, root=主调)
    ///       例 backdoor 的前身 bVIImaj7→I
    static func resolveBorrowedMajors(chords: [AnalysisChord], tonalCenters: inout [Int],
                                      keyModes: inout [String], tonicPC: Int) {
        let n = chords.count
        for i in 0..<n {
            let c = chords[i]
            guard c.qualityClass == .major else { continue }
            guard tonalCenters[i] == c.rootPC else { continue }  // 独立成调 (否则已是主调一部分)
            guard c.rootPC != tonicPC else { continue }          // 主调 I 本身

            let rel = (c.rootPC - tonicPC + 12) % 12

            // 若前面紧邻它的 V (V-I 支持), 则是真正的转调 tonic (如 Very Early 的
            // Ab7b9→Db^7), 而非 modal interchange 借用 —— 跳过。
            if i > 0, chords[i - 1].qualityClass == .dominant,
               chords[i - 1].rootPC == (c.rootPC + 7) % 12 {
                continue
            }

            var borrow = false

            if rel == 1, i < n - 1 {
                // bII 拿坡里: 后续 ≤4 个和弦内回到主调 I
                for j in (i + 1)...min(i + 4, n - 1) {
                    if chords[j].qualityClass == .major && chords[j].rootPC == tonicPC {
                        borrow = true
                        break
                    }
                }
            } else if rel == 8 {
                // bVI: 后面紧邻主调 V
                if i < n - 1, chords[i + 1].qualityClass == .dominant,
                   chords[i + 1].rootPC == (tonicPC + 7) % 12 {
                    borrow = true
                }
            } else if rel == 10 {
                // bVII: 后面紧邻主调 I
                if i < n - 1, chords[i + 1].qualityClass == .major,
                   chords[i + 1].rootPC == tonicPC {
                    borrow = true
                }
            }

            if borrow {
                tonalCenters[i] = tonicPC
                keyModes[i] = "Major"
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // 3.7 resolveMinorTonics (iiø-V-i 的 i 拉回自身)
    // ═══════════════════════════════════════════════════════════

    /// 识别 iiø-V-i 的 i (minor tonic) 被 findKeys 反向遍历 / 向前扩展错误归到
    /// 后面调的 iii 的场景, 把 i 拉回自身 (标 i)。独立后处理 pass, 不改 findKeys /
    /// 优先级逻辑, 可整体回退。
    ///
    /// 触发条件 (信号单一, 保守):
    ///   1. c 是 minor / minor7
    ///   2. c 前面紧邻 halfDim(root=c+2) + dominant(root=c+7)  ← 标准 iiø-V
    ///   3. 【pivot 保护】c 后面不是 ii-V (c 不是 c+10 调的 ii):
    ///        即 i+1 dominant(root=c+5) 且 i+2 major(root=c+10)
    ///      若是 pivot (如 Autumn Leaves 的 G-7 = F 的 ii), 跳过, 保持现状。
    ///
    /// 命中后: 把 c 及后续同根音 minor tonic 归 c (Minor), 标 i。
    static func resolveMinorTonics(chords: [AnalysisChord], tonalCenters: inout [Int],
                                   keyModes: inout [String]) {
        let n = chords.count
        guard n >= 3 else { return }
        for i in 0..<n {
            let c = chords[i]
            guard c.qualityClass == .minor || c.qualityClass == .minor7 else { continue }
            let tonic = c.rootPC
            // 前面紧邻 iiø-V: halfDim(tonic+2) + dominant(tonic+7)
            guard i >= 2,
                  chords[i - 1].qualityClass == .dominant,
                  chords[i - 1].rootPC == (tonic + 7) % 12,
                  chords[i - 2].qualityClass == .halfDim,
                  chords[i - 2].rootPC == (tonic + 2) % 12 else { continue }
            // pivot 保护: c 后面是 ii-V (c 是 tonic+10 调的 ii), 保持现状
            if i < n - 2,
               chords[i + 1].qualityClass == .dominant,
               chords[i + 1].rootPC == (tonic + 5) % 12,
               chords[i + 2].qualityClass == .major,
               chords[i + 2].rootPC == (tonic + 10) % 12 {
                continue
            }
            // 归 i
            tonalCenters[i] = tonic
            keyModes[i] = "Minor"
            // 持续同根音 minor tonic (C-7 持续多小节等)
            var k = i + 1
            while k < n, chords[k].rootPC == tonic,
                  (chords[k].qualityClass == .minor || chords[k].qualityClass == .minor7) {
                tonalCenters[k] = tonic
                keyModes[k] = "Minor"
                k += 1
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // 6. 颜色系统 (绝对 PC 色表, RoadMapSettings.generateColors)
    // ═══════════════════════════════════════════════════════════

    /// 12 个绝对调性中心颜色 (0=C ... 11=B)。
    /// 移植 RoadMapSettings.generateColors(float sat), 用 sat=0.6, brightness=1.0:
    ///   keyColors[(i*7)%12] = HSB(hue=i/13, sat, 1.0)
    static let keyColors: [String] = {
        var colors = Array(repeating: "", count: 12)
        for i in 0..<12 {
            colors[(i * 7) % 12] = hsbToHex(hue: Double(i) / 13.0,
                                            saturation: 0.6, brightness: 1.0)
        }
        return colors
    }()

    /// 调性中心 PC → 颜色 hex (绝对 PC 色表, 与歌曲主调无关)。
    static func color(forTonalCenter pc: Int) -> String {
        let idx = ((pc % 12) + 12) % 12
        return keyColors[idx]
    }

    /// HSB → "#RRGGBB" (移植 java.awt.Color.HSBtoRGB)。
    static func hsbToHex(hue: Double, saturation: Double, brightness: Double) -> String {
        var r = 0.0, g = 0.0, b = 0.0
        if saturation == 0 {
            r = brightness; g = brightness; b = brightness
        } else {
            let h = (hue - floor(hue)) * 6.0
            let f = h - floor(h)
            let p = brightness * (1.0 - saturation)
            let q = brightness * (1.0 - saturation * f)
            let t = brightness * (1.0 - saturation * (1.0 - f))
            switch Int(h) {
            case 0: r = brightness; g = t; b = p
            case 1: r = q; g = brightness; b = p
            case 2: r = p; g = brightness; b = t
            case 3: r = p; g = q; b = brightness
            case 4: r = t; g = p; b = brightness
            default: r = brightness; g = p; b = q
            }
        }
        func c(_ v: Double) -> Int { Int((v * 255.0).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }

    // ═══════════════════════════════════════════════════════════
    // 7. 级数计算 (相对该和弦的调性中心)
    // ═══════════════════════════════════════════════════════════

    /// 单和弦 → 功能级数 (相对该和弦的调性中心 tonicPC)。
    /// mode 为该和弦所在 KeySpan 的调式 ("Major"/"Minor"/"Dominant")。
    /// quality 为和弦质量串 (归一化后), 用于判断属七是否带变化音 (V7alt 约定)。
    static func degreeLabel(rootPC: Int, family: ChordFamily, tonicPC: Int,
                            mode: String, quality: String) -> String {
        let isMinorMode = (mode == "Minor")
        let interval = (rootPC - tonicPC + 12) % 12
        let degree: String
        switch interval {
        case 0:  degree = isMinorMode ? "i" : "I"
        case 1:  degree = "bII"
        case 2:  degree = "ii"
        case 3:  degree = isMinorMode ? "III" : "bIII"
        case 4:  degree = "iii"
        case 5:  degree = isMinorMode ? "iv" : "IV"
        case 6:  degree = "bV"
        case 7:  degree = "V"
        case 8:  degree = "bVI"
        case 9:  degree = isMinorMode ? "VI" : "vi"
        case 10: degree = "bVII"
        case 11: degree = "vii"
        default: degree = "I"
        }
        switch (degree, family) {
        case ("ii", .halfDiminished): return "iiø"
        case ("ii", .dominant):   return "II7"     // 二级属七 (V/V, 副属链)
        case ("V", .dominant):   return (isMinorMode && isAlteredDominant(quality)) ? "V7alt" : "V"
        case ("I", .dominant):   return "I7"      // blues I7 (Db 大调里的 Db7)
        case ("bII", .dominant): return "bII7"
        case ("bVII", .dominant): return "bVII7"   // backdoor (Fm7-Bb7-Cmaj7 的 Bb7)
        case ("IV", .dominant):  return "IV7"      // IV7 借用 (blues 四级属七, Fmaj7→Bb7)
        case ("vi", .dominant):   return "VI7"     // 次级属七 V/ii (Em7-A7-Dm7 的 A7)
        case ("bVI", .minor):    return "bvi"
        case ("I", .diminished): return "#I°"      // 主音上的经过减七 (Dbo7→Db6 的 Dbo7)
        case (_, .diminished):   return "\(degree)°"
        case (_, .halfDiminished): return "\(degree)ø"
        default: return degree
        }
    }

    /// 属七是否带变化音 (b9/#9/b5/#5/b13/#11/alt)。
    /// 用于 degreeLabel 的 V7alt 约定: 小调 V 属七带变化音才标 V7alt (如 E7b9),
    /// 纯属七 (如 A Foggy Day 的 E7, 是 V/iii 副属而非小调属七) 标 V。
    static func isAlteredDominant(_ quality: String) -> Bool {
        let q = normalizeQuality(quality).lowercased()
        return q.contains("b9") || q.contains("#9") || q.contains("b5")
            || q.contains("#5") || q.contains("b13") || q.contains("#11")
            || q.contains("alt")
    }

    // ═══════════════════════════════════════════════════════════
    // 8. 主入口: 分析整首乐曲, 输出 AnalysisResult
    // ═══════════════════════════════════════════════════════════

    /// 完整调性分析。
    /// - Parameters:
    ///   - roadmap: 已填充和弦的 JazzRoadmap
    ///   - tonicPC: 全曲主调根音 PC (来自歌曲调号, 用于级数标注)
    ///   - mode: 全曲主调调式 (用于级数 bIII/iv 等判断)
    ///   - beatsPerMeasure: 每小节拍数
    /// - Returns: 按小节组织的分析结果 (供 SheetMusicView 消费)
    static func analyze(roadmap: JazzRoadmap, tonicPC: Int,
                        mode: JazzMode = .major,
                        beatsPerMeasure: Double = 4.0) -> AnalysisResult {
        let flat = roadmap.flattenRoadmap()
        guard !flat.isEmpty else { return AnalysisResult(measures: []) }

        // 1. 构建分析侧和弦序列 (含 isSectionEnd 映射)
        var chords: [AnalysisChord] = []
        for (idx, cb) in flat.enumerated() {
            let (rootPC, quality) = parseRootQuality(cb.name)
            let isSectionEnd = (idx + 1 < flat.count) ? flat[idx + 1].isSectionStart : false
            chords.append(AnalysisChord(
                name: cb.name,
                rootPC: rootPC,
                mode: chordMode(ofQuality: quality),
                qualityClass: qualityClass(ofQuality: quality),
                duration: cb.duration,
                isSectionEnd: isSectionEnd
            ))
        }

        // 2. findKeys 推断调性跨度链
        let keySpans = findKeys(chords, tonicPC: tonicPC)

        // 3. 逐和弦映射调性中心 + 调性中心调式
        let defaultKeyMode = (mode == .minor) ? "Minor" : "Major"
        var tonalCenters = Array(repeating: tonicPC, count: chords.count)
        var keyModes = Array(repeating: defaultKeyMode, count: chords.count)
        for span in keySpans {
            if span.startIdx < span.endIdx {
                for idx in span.startIdx..<span.endIdx where idx < chords.count {
                    tonalCenters[idx] = span.key
                    keyModes[idx] = span.mode
                }
            }
        }

        // 3.5 findLaunchers 循环回绕修正 (方案 1+2: 属七解决到 tonic)
        //     处理 findKeys 线性反向遍历无法覆盖的循环 ii-V (结尾属七 -> 开头 tonic)
        resolveDominantLaunchers(chords: chords, tonalCenters: &tonalCenters, keyModes: &keyModes,
                                 tonicPC: tonicPC, songMode: mode)

        // 3.6 借用 major (modal interchange): 拿坡里 bII / bVI / bVIImaj7 归主调
        resolveBorrowedMajors(chords: chords, tonalCenters: &tonalCenters, keyModes: &keyModes,
                              tonicPC: tonicPC)

        // 3.7 iiø-V-i 的 i 拉回自身 (独立后处理, 含 pivot 保护)
        resolveMinorTonics(chords: chords, tonalCenters: &tonalCenters, keyModes: &keyModes)

        // 4. 按小节组织分析结果
        return buildMeasureAnalysis(
            flat: flat, tonalCenters: tonalCenters, keyModes: keyModes,
            beatsPerMeasure: beatsPerMeasure
        )
    }

    /// 按小节组装 AnalysisResult。
    private static func buildMeasureAnalysis(flat: [ChordBlock], tonalCenters: [Int],
                                             keyModes: [String],
                                             beatsPerMeasure: Double) -> AnalysisResult {
        var measures: [MeasureAnalysis] = []
        var currentMeasure: [ChordAnalysis] = []
        var measureBeatAccum: Double = 0

        for (index, chord) in flat.enumerated() {
            let tc = index < tonalCenters.count ? tonalCenters[index] : 0
            let tcMode = index < keyModes.count ? keyModes[index] : "Major"
            let (_, quality) = parseRootQuality(chord.name)
            let label = degreeLabel(rootPC: chord.chordRootPC(),
                                    family: chord.getChordFamily(),
                                    tonicPC: tc, mode: tcMode,
                                    quality: quality)
            let analysis = ChordAnalysis(
                chord: chord.name,
                functionLabel: label,
                tonalCenterPC: tc,
                colorHex: color(forTonalCenter: tc),
                beatStart: measureBeatAccum,
                beatDuration: chord.duration
            )
            currentMeasure.append(analysis)
            measureBeatAccum += chord.duration

            if measureBeatAccum >= beatsPerMeasure - 0.001 || index == flat.count - 1 {
                measures.append(MeasureAnalysis(chordAnalyses: currentMeasure))
                currentMeasure = []
                measureBeatAccum = 0
            }
        }
        return AnalysisResult(measures: measures)
    }
}
