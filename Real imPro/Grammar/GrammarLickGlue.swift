import Foundation

// MARK: - GrammarLickGlue — LickGen 管线衔接胶水层
//
// ⚠️ 架构永久废弃:
//   ❌ buildSolo()      — 巨型单循环 → 已由三层管线替代
//   ❌ completeOutlines()   — N-Gram轮廓补全 → 永久移除
//   ❌ generateSoloFromOutline() — Soloist语料拼接 → 永久移除
//   ❌ chooseNote()     — 28条概率查表 → GrammarNoteConverter Roulette Wheel替代
//   ❌ adjustTriadicPitch() — 平行五八度 → GrammarNoteConverter makeGarzoneTriad替代
//   ❌ Bernoulli/cumulativeProbs/addToRootList — 辅助算法 → 已内联至对应模块
//


// ═════════════════════════════════════════════════════════════
// 1. NoteCategory — 音符类型分类
//
// Java L63-72: NOTE/CHORD/SCALE/COLOR/APPROACH/RANDOM/BASS/GOAL/OUTSIDE
// 架构精简: 6 类核心分类 (RANDOM/BASS/GOAL 由管线内部处理)
// ═════════════════════════════════════════════════════════════

enum NoteCategory: String {
    case chordTone      // 和弦音 — Java L64: CHORD = 1001
    case colorTone      // 色彩音 — Java L66: COLOR = 1003
    case scaleTone      // 音阶音 — Java L65: SCALE = 1002
    case approachNote   // 趋近音 — Java L67: APPROACH = 1004
    case outsideNote    // 外音   — Java L71: OUTSIDE = 1008
    case rest           // 休止符

    /// 是否为音阶内合法音
    var isDiatonic: Bool {
        self == .chordTone || self == .colorTone || self == .scaleTone
    }
}


// ═════════════════════════════════════════════════════════════
// 2. classifyTerminal — 文法符号类型映射
//
// Java L518-522: classifyNote(token)
//   switch token:
//     C_* → CHORD_TONE     X_* → SCALE_TONE
//     L_* → COLOR_TONE     A_* → APPROACH
//     Y_* → OUTSIDE        R_* → REST
//
// 架构说明: 位于 buildSolo 巨型循环内, 此处提取为独立纯函数,
//         可插在 Grammar.run() 产出 [GrammarTerminal] 与
//         GrammarNoteConverter.convert() 之间。
// ═════════════════════════════════════════════════════════════

func classifyTerminal(_ terminal: GrammarTerminal) -> NoteCategory {
    switch terminal.type {

    case .chord:        // Java L520: C_* → CHORD_TONE
        return .chordTone

    case .color:        // Java L521: L_* → COLOR_TONE
        return .colorTone

    case .scale, .arbitrary:  // Java L520: S_*/X_* → SCALE_TONE
        return .scaleTone

    case .approach:     // Java L520: A_* → APPROACH
        return .approachNote

    case .outside:      // Java: Y_* → OUTSIDE
        return .outsideNote

    case .rest:         // Java L522: R_* → REST
        return .rest

    // ── 复合类型: 乐观映射, 实际音高由 NoteConverter 内部分支处理 ──
    // H (Java T_NOTE): 普通音符, 0.7权重多数是和弦音, 暂定黑色(P0-3后按实际音高动态分类)
    case .note: return .chordTone

    case .scaleDegree, .slope, .triadic:
        // 架构: scaleDegree/slope/triadic 在 GrammarNoteConverter 有专门分支
        // (selectSlopePitch / makeGarzoneTriad), 此处返回 scaleTone 仅作为默认分类
        return .scaleTone
    }
}


// ═════════════════════════════════════════════════════════════
// 3. TerminalClassifier — 批量分类 + 类型计数
//
// Java L120-123: 构建标识符
//   if(numTypes[0] != 0) haveChord = 1; else haveChord = 0;
//   if(numTypes[1] != 0) haveColor = 1; else haveColor = 0;
//   if(numTypes[2] != 0) haveRandom = 1; else haveRandom = 0;
//
// 架构说明: 散布在 buildSolo 循环中逐 slot 累积 numTypes,
//         此处提取为独立结构体, 一次性批量处理整段 [GrammarTerminal]。
// ═════════════════════════════════════════════════════════════

struct TerminalClassifier {

    /// 分类后的类别数组 (与输入同序)
    let categories: [NoteCategory]

    /// 各类型可用计数 — Java: numTypes[0]=numChord, [1]=numColor, [2]=numScale
    let chordCount: Int
    let colorCount: Int
    let scaleCount: Int

    /// Java L120-123: 从 [GrammarTerminal] 批量分类并统计
    init(terminals: [GrammarTerminal]) {
        var cats: [NoteCategory] = []
        var cChord = 0, cColor = 0, cScale = 0

        for t in terminals {
            let cat = classifyTerminal(t)
            cats.append(cat)

            // Java L121-123: numTypes 计数累积
            switch cat {
            case .chordTone:  cChord += 1
            case .colorTone:  cColor += 1
            case .scaleTone:  cScale += 1
            default: break
            }
        }

        self.categories = cats
        self.chordCount = cChord
        self.colorCount = cColor
        self.scaleCount = cScale
    }

    /// Java L121-123: 返回 [numChord, numColor, numScale]
    var numTypes: [Int] {
        [chordCount, colorCount, scaleCount]
    }

    /// Java L120: haveChord判定
    var hasChordTone: Bool { chordCount > 0 }
    /// Java L122: haveColor判定
    var hasColorTone: Bool { colorCount > 0 }
    /// Java L123: haveScale判定 (scale = chord+color+scale total)
    var hasScaleTone: Bool { (chordCount + colorCount + scaleCount) > 0 }
}


// ═════════════════════════════════════════════════════════════
// 4. PitchSelectionContext — 音高选择上下文容器
//
// Java L107-108: getNote(minPitch, maxPitch, low, high, type, numTypes, noteTypes, attempts)
//
// 架构说明:  chooseNote 依赖 NoteChooser 28条概率查表,
//         本项目已由 GrammarNoteConverter.selectPitch() 的
//         Roulette Wheel 加权抽样 + ExpectancyCore 动态评分替代。
//         本结构体仅作为上下文数据容器, 供管线间传递参数。
// ═════════════════════════════════════════════════════════════

struct PitchSelectionContext {
    /// Java L107: minPitch — 全局最低音域
    let globalMin: Int
    /// Java L107: maxPitch — 全局最高音域
    let globalMax: Int

    /// Java L108: low — 当前选择窗口下限
    let low: Int
    /// Java L108: high — 当前选择窗口上限
    let high: Int

    /// Java: lastPitch — 上一个已选音符音高 (邻近性计算)
    let lastPitch: Int

    /// 当前和弦名 (由 GrammarNoteConverter.findChordAt 提供)
    let chordName: String

    /// Java L108: numTypes — [numChord, numColor, numScale]
    let availableTypes: [Int]

    /// 从 GrammarNoteConverter.convert() 上下文构造
    init(globalMin: Int, globalMax: Int,
         low: Int, high: Int,
         lastPitch: Int,
         chordName: String,
         classifier: TerminalClassifier) {
        self.globalMin = globalMin
        self.globalMax = globalMax
        self.low = low
        self.high = high
        self.lastPitch = lastPitch
        self.chordName = chordName
        self.availableTypes = classifier.numTypes
    }
}


// ═════════════════════════════════════════════════════════════
// 5. LightPostProcessor — 轻量化旋律后置处理
//
// Java: checkNote() 八度修正 — 对应 clampToRange
// Java: fillMelody() 轮廓补全 — 对应 smoothLargeLeaps (简化版)
//
// ⚠️ 架构约束:
//   ❌ 不复现 completeOutlines / N-Gram 拼接
//   ❌ 不复现 adjustTriadicPitch (已由 makeGarzoneTriad 替代)
//   ✅ 仅保留最小化 sanity check: 音域钳位 + 极端大跳平滑
// ═════════════════════════════════════════════════════════════

/// Solo 整流（Rectify）档位：控制把"非合法音"就近吸附到合法音的作用范围
/// 对齐 Java RectifyPitchesCommand（默认全拍、合法集合=和弦音+色彩音）
enum RectifyMode: String, CaseIterable {
    case off          // 完全不整流
    case strongBeat   // 仅强拍整流，且只吸附到和弦音（Swift 历史行为，弱拍保持自由）
    case allBeats     // 全拍对齐 Java：每个非休止音都检查，合法集合=和弦音+色彩音，只拔真正外音

    /// 调音台档位菜单显示名（英文，遵循 UI 英文约束）
    var label: String {
        switch self {
        case .off:        return "Off"
        case .strongBeat: return "Strong Beats"
        case .allBeats:   return "All Beats (Java)"
        }
    }

    /// 收起胶囊里的短标签（宽度受限）
    var shortLabel: String {
        switch self {
        case .off:        return "Off"
        case .strongBeat: return "Strong"
        case .allBeats:   return "All·Java"
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // UI 可见档位说明（调试用，勿删 .off / .strongBeat 两个 case 与分支逻辑）
    // ----------------------------------------------------------------------------
    // 目前产品上只保留 .allBeats（对齐 Java 的全拍整流，听感已确认）。
    // .off（完全不整流）与 .strongBeat（仅强拍、只吸附和弦音的 Swift 历史行为）
    // 的枚举、process 分支、rectifyStrongBeats 函数全部保留，仅在调音台菜单中隐藏，
    // 方便日后调试对比：
    //   • 想临时在 UI 恢复对比 → 把下面 userVisibleCases 改回 RectifyMode.allCases；
    //   • 想代码级强制某档 → 直接改 GrammarStrategy.rectifyMode 默认值即可。
    // ═══════════════════════════════════════════════════════════════════
    static let userVisibleCases: [RectifyMode] = [.allBeats]

}

enum LightPostProcessor {

    // MARK: 音域钳位 — 对应 Java checkNote() 八度升降修正

    /// Java: while(pitch > maxPitch) pitch -= 12; while(pitch < minPitch) pitch += 12;
    /// - Parameters:
    ///   - melody: 待处理的音符序列
    ///   - minPitch: 最低 MIDI 音高 (默认来自 grammar min-pitch)
    ///   - maxPitch: 最高 MIDI 音高 (默认来自 grammar max-pitch)
    /// - Returns: 钳位至 [minPitch, maxPitch] 的音符序列
    static func clampToRange(_ melody: [PhysicalNote],
                             minPitch: Int,
                             maxPitch: Int) -> [PhysicalNote] {
        melody.map { note in
            var pitch = note.midiPitch
            guard pitch != -1 else { return note }       // 休止符不动

            while pitch > maxPitch { pitch -= 12 }       // Java L180-181
            while pitch < minPitch { pitch += 12 }       // Java L183-184

            return PhysicalNote(midiPitch: pitch, durationSlots: note.durationSlots,
                                tuplet: note.tuplet, terminalType: note.terminalType)
        }
    }

    // MARK: 大跳平滑 — 对应 Java fillMelody() 简化版

    /// 将 ≥maxLeap 半音的跳进修正到最近八度位置。
    /// 架构: 平行五八度避免已由 makeGarzoneTriad 处理, 此处仅钳位极端跳跃。
    /// - Parameters:
    ///   - melody: 待处理音符序列
    ///   - maxLeap: 最大允许跳进 (默认 12 半音 = 一个八度)
    /// - Returns: 平滑后的序列
    static func smoothLargeLeaps(_ melody: [PhysicalNote],
                                 maxLeap: Int = 12) -> [PhysicalNote] {
        guard melody.count > 1 else { return melody }

        var result = melody
        for i in 1..<result.count {
            let prev = result[i - 1].midiPitch
            let curr = result[i].midiPitch
            guard prev != -1, curr != -1 else { continue }

            let leap = abs(curr - prev)
            guard leap > maxLeap else { continue }

            // 将当前音移到前一音的最近八度位置
            let octBase = (prev / 12) * 12
            let pc = curr % 12
            var best = octBase + pc

            // 向上/下八度选更近者
            let up = best + 12, down = best - 12
            if abs(up - prev) < abs(best - prev) { best = up }
            else if abs(down - prev) < abs(best - prev) { best = down }

            result[i] = PhysicalNote(midiPitch: best, durationSlots: result[i].durationSlots,
                                      tuplet: result[i].tuplet, terminalType: result[i].terminalType)
        }
        return result
    }

    // MARK: 综合后处理入口

    /// Java checkNote() + fillMelody() 合并精简
    /// - Parameters:
    ///   - melody: 原始音符序列 (GrammarNoteConverter.convert 输出)
    ///   - minPitch: 音域下限
    ///   - maxPitch: 音域上限
    ///   - maxLeap: 最大允许跳进 (默认 12)
    /// - Returns: 处理后的音符序列
    static func process(_ melody: [PhysicalNote],
                        minPitch: Int, maxPitch: Int,
                        maxLeap: Int = 12,
                        chordBlocks: [ChordBlock]? = nil,
                        slotsPerBeat: Int = 120,
                        beatsPerMeasure: Int = 4,
                        rectifyMode: RectifyMode = .strongBeat) -> [PhysicalNote] {
        let clamped = clampToRange(melody, minPitch: minPitch, maxPitch: maxPitch)
        let smoothed = smoothLargeLeaps(clamped, maxLeap: maxLeap)
        // 二次钳位：smoothLargeLeaps 的八度移位可能把音移出 [minPitch, maxPitch]（如 prev=58,curr=82 → best=52），必须再钳一次
        let reClamped = clampToRange(smoothed, minPitch: minPitch, maxPitch: maxPitch)
        guard let chords = chordBlocks else {
            return mergeAdjacent(reClamped)
        }
        let rectified: [PhysicalNote]
        switch rectifyMode {
        case .off:
            // 不整流，直接进入相邻同音合并
            rectified = reClamped
        case .strongBeat:
            // Swift 历史行为：仅强拍、只吸附到和弦音（趋近音豁免逻辑保持原样）
            rectified = rectifyStrongBeats(reClamped, chordBlocks: chords,
                                           slotsPerBeat: slotsPerBeat,
                                           beatsPerMeasure: beatsPerMeasure)
        case .allBeats:
            // 对齐 Java RectifyPitchesCommand：全拍位，合法集合=和弦音+色彩音
            rectified = rectifyAllBeats(reClamped, chordBlocks: chords,
                                        slotsPerBeat: slotsPerBeat,
                                        beatsPerMeasure: beatsPerMeasure)
        }
        return mergeAdjacent(rectified)
    }
    
    /// 所有音高修改完成后兜底合并相邻同音（对齐 Java avoidRepeats）
    /// 保留 terminalType / tuplet，不合并休止符
    static func mergeAdjacent(_ melody: [PhysicalNote]) -> [PhysicalNote] {
        guard melody.count > 1 else { return melody }
        var result: [PhysicalNote] = []
        for note in melody {
            guard let last = result.last,
                  last.midiPitch == note.midiPitch,
                  last.midiPitch >= 0 else {
                result.append(note); continue
            }
            result[result.count - 1] = PhysicalNote(
                midiPitch:     last.midiPitch,
                durationSlots: last.durationSlots + note.durationSlots,
                tuplet:        last.tuplet,
                terminalType:  last.terminalType
            )
        }
        return result
    }
    
    // MARK: - rectify 强拍修正 (Java RectifyPitchesCommand / Scorer.strongBeatScore)
    
    /// 将落在正拍/强拍位置的非和弦音修正为最近和弦音（弱拍保持自由）
    /// 对齐 Java RectifyPitchesCommand，但仅修正强拍（Java 修正全拍位）
    /// 三段判断结构（对齐 Java L232→L249→L267）：
    ///   1. 已是和弦音 → 保留
    ///   2. 声学趋近音豁免（不看终端标签，±1半音解决到下一和弦音）→ 保留
    ///   3. 其余 → 吸附到最近和弦音（等距优先向上）
    /// 【T1】可用音集注入（默认 nil）。nil → 走既有 getChordTonesForRectify（ChordQuality 族级，
    /// grammar 默认整流逐音不变）；guide&Transform 传入 G1 词表 provider（spell+color 绝对 PC 展开）。
    /// 形参含义与 getChordTonesForRectify 一致：(和弦名, 最低音高, 最高音高, 是否含色彩音) -> 实际 MIDI 音高数组
    typealias RectifyUsableToneProvider = (_ chordName: String, _ minPitch: Int, _ maxPitch: Int, _ includeColor: Bool) -> [Int]

    static func rectifyStrongBeats(_ melody: [PhysicalNote],
                                    chordBlocks: [ChordBlock],
                                    slotsPerBeat: Int = 120,
                                    beatsPerMeasure: Int = 4,
                                    usableToneProvider: RectifyUsableToneProvider? = nil) -> [PhysicalNote] {
        let measureLength = beatsPerMeasure * slotsPerBeat
        let strongBeatInterval = measureLength / (beatsPerMeasure <= 3 ? 1 : (beatsPerMeasure % 2 == 0 ? 2 : (beatsPerMeasure % 3 == 0 ? 3 : 1)))
        
        var result = melody
        var accumSlot = 0
        
        for (i, note) in melody.enumerated() {
            let absSlot = accumSlot % measureLength
            let isOnBeat = absSlot % slotsPerBeat == 0
            let isStrong = absSlot % strongBeatInterval == 0
            
            // 弱拍/反拍：不修正，保持自由（爵士"弱拍紧张"语法）
            // 休止符：不修正
            guard (isOnBeat || isStrong), note.midiPitch >= 0 else {
                accumSlot += note.durationSlots
                continue
            }
            
            // ── 第1段：查当前和弦音，已是和弦音 → 保留（对齐 Java L232 enhMember）──
            let currentChordTones = getChordTonesAtSlot(slot: accumSlot, chordBlocks: chordBlocks,
                                                           slotsPerBeat: slotsPerBeat,
                                                           refPitch: note.midiPitch,
                                                           usableToneProvider: usableToneProvider)
            let isAlreadyChordTone = currentChordTones.contains {
                abs($0 - note.midiPitch) % 12 == 0
            }
            if isAlreadyChordTone {
                accumSlot += note.durationSlots
                continue
            }
            
            // ── 第2段：声学趋近音豁免（对齐 Java L249-266，不看终端标签）──
            // 长时值限制：强拍上持续超过 approachMaxSlots 的趋近音不豁免
            // （短时值=装饰音/倚音，快速解决；长时值=强拍持续紧张音，应吸附）
            // 阈值 60 = 八分音符；可按需调整为 30（十六分，更严格）或 80（含三连音八分）
            let approachMaxSlots = 60
            if note.durationSlots <= approachMaxSlots, i + 1 < melody.count {
                let nextNote = melody[i + 1]
                if nextNote.midiPitch >= 0
                    && abs(nextNote.midiPitch - note.midiPitch) == 1 {  // Java adjacentPitch = ±1
                    let nextSlot = accumSlot + note.durationSlots
                    let nextChordTones = getChordTonesAtSlot(slot: nextSlot, chordBlocks: chordBlocks,
                                                               slotsPerBeat: slotsPerBeat,
                                                               refPitch: nextNote.midiPitch,
                                                               usableToneProvider: usableToneProvider)
                    let nextIsChordTone = nextChordTones.contains {
                        abs($0 - nextNote.midiPitch) % 12 == 0
                    }
                    if nextIsChordTone {
                        // 趋近音豁免：短时值 + 半音解决 → 保留（无论原始终端类型是 A/X/L/S/H）
                        accumSlot += note.durationSlots
                        continue
                    }
                }
            }
            // 长时值趋近音（durationSlots > approachMaxSlots）或无解决的趋近音
            // → 落入第3段，吸附到最近和弦音
            
            // ── 第3段：其余 → 吸附到最近和弦音（对齐 Java L267-271 getClosestMatch）──
            if !currentChordTones.isEmpty {
                let nearest = findClosestMatch(pitch: note.midiPitch, chordTones: currentChordTones)
                result[i] = PhysicalNote(
                    midiPitch: nearest,
                    durationSlots: note.durationSlots,
                    tuplet: note.tuplet,
                    terminalType: "C"  // 修正后标记为和弦音，着色反映实际听感
                )
            }

            accumSlot += note.durationSlots
        }
        return result
    }
    
    // MARK: - rectify 全拍对齐 Java RectifyPitchesCommand（趋近音豁免逻辑与 rectifyStrongBeats 保持一致，未改动）

    /// 全拍整流：对每个非休止音检查（不限强拍）
    ///   1. 已是"和弦音或色彩音" → 保留（Java usableTones = spell + color，色彩音受保护）
    ///   2. 声学趋近音豁免 → 保留（半音±1 + 下一音为合法音；时长阈值：正拍≤十六分30、反拍/拍缝≤八分60）
    ///   3. 其余真正外音 → 就近吸附到最近的"和弦音/色彩音"（等距优先向上）
    static func rectifyAllBeats(_ melody: [PhysicalNote],
                                chordBlocks: [ChordBlock],
                                slotsPerBeat: Int = 120,
                                beatsPerMeasure: Int = 4,
                                usableToneProvider: RectifyUsableToneProvider? = nil) -> [PhysicalNote] {
        var result = melody
        var accumSlot = 0

        // 方案A（2026-09-06）：正拍判定从"仅第1/3强拍"推广到"每一拍的拍点"。
        // 正拍 = 小节内起始 slot 整除一拍(slotsPerBeat=120)：4/4 下第 1/2/3/4 拍拍点(slot=0/120/240/360)都算正拍；
        // 反拍/拍缝（八分反拍60、八分三连40/80、十六分30/90 等，%120≠0）仍为非正拍、维持宽松阈值。
        // 该判定只看音符【起始点】，且用整除一拍、与拍号无关，三拍/奇数拍同样成立。
        let measureLength = beatsPerMeasure * slotsPerBeat

        for (i, note) in melody.enumerated() {
            // 休止符不修正
            guard note.midiPitch >= 0 else {
                accumSlot += note.durationSlots
                continue
            }

            // 方案A：所有【正拍】趋近放行阈值=30（十六分及更短才当装饰放行，八分60/八分三连40 一律吸附）；
            // 反拍/拍缝维持 60（八分及以内可作弱位紧张音保留）。只收紧"趋近豁免"的时长，
            // 不改动趋近音的生成逻辑、不改反拍、不改第1段合法集合与第3段吸附规则。
            let absSlotInMeasure = accumSlot % measureLength
            let isOnBeat = absSlotInMeasure % slotsPerBeat == 0

            // ── 第1段：当前音已是 和弦音/色彩音 → 保留（对齐 Java L235 enhMember(usableTones)）──
            let usableTones = getChordTonesAtSlot(slot: accumSlot, chordBlocks: chordBlocks,
                                                  slotsPerBeat: slotsPerBeat,
                                                  refPitch: note.midiPitch,
                                                  includeColor: true,
                                                  usableToneProvider: usableToneProvider)
            let isUsable = usableTones.contains { abs($0 - note.midiPitch) % 12 == 0 }
            if isUsable {
                accumSlot += note.durationSlots
                continue
            }

            // ── 第2段：声学趋近音豁免 ──
            // allBeats 对齐 Java RectifyPitchesCommand L215-216/L249：下一音属于下一和弦的
            // 「和弦音+色彩音」(nextUsableTones = nextSpell + nextColor) 即豁免，故 includeColor: true。
            // 注意：rectifyStrongBeats 的合法集合只有和弦音，那里保持只查和弦音，与此处不同，勿合并。
            // 正拍收紧到 30（十六分及更短放行），反拍/拍缝维持 60（八分）。
            let approachMaxSlots = isOnBeat ? 30 : 60
            var isApproach = false
            if note.durationSlots <= approachMaxSlots, i + 1 < melody.count {
                let nextNote = melody[i + 1]
                if nextNote.midiPitch >= 0 && abs(nextNote.midiPitch - note.midiPitch) == 1 {
                    let nextSlot = accumSlot + note.durationSlots
                    let nextChordTones = getChordTonesAtSlot(slot: nextSlot, chordBlocks: chordBlocks,
                                                             slotsPerBeat: slotsPerBeat,
                                                             refPitch: nextNote.midiPitch,
                                                             includeColor: true,
                                                             usableToneProvider: usableToneProvider)
                    isApproach = nextChordTones.contains { abs($0 - nextNote.midiPitch) % 12 == 0 }
                }
            }
            if isApproach {
                accumSlot += note.durationSlots
                continue
            }

            // ── 第3段：其余 → 就近吸附到最近的 和弦音/色彩音（对齐 Java L271 getClosestMatch）──
            if !usableTones.isEmpty {
                let nearest = findClosestMatch(pitch: note.midiPitch, chordTones: usableTones)
                result[i] = PhysicalNote(
                    midiPitch: nearest,
                    durationSlots: note.durationSlots,
                    tuplet: note.tuplet,
                    terminalType: "C"  // 整流后标记为稳定音；屏幕染色仍按实际音高实时判定
                )
            }

            accumSlot += note.durationSlots
        }
        return result
    }

    // MARK: [T2 Hunk9] guide & Transform 专用整流（spell-only，与 rectifyAllBeats 共存、互不影响）
    // [色彩档→三态 20260914] 形参由 Bool allowColor 升级为 GuideRectifyColorMode（默认 .off=出厂 spell-only，
    //   对齐 Java colorBox 不勾）；.full=spell+全 color（对齐 Java RectifyPitchesCommand colorTones=true，
    //   即 colorBox 勾选，已与 Java TransformRandomColorGold 逐音 diff=0）；.conservative=spell+自然9/11/13。
    //   旧 Bool 语义由 GTVocResolver 委托保留。grammar 不接此档。

    /// 对齐 Java RectifyPitchesCommand 出厂设置（chordTones=true、colorTones 按三态），供 guide&Transform 使用。
    /// 与 grammar 的 rectifyAllBeats（定稿、勿改）三处差异：
    ///  ① 可用音集 = G1 词汇表 spell（.off 出厂）/ spell+保守色（.conservative）/ spell+全 color（.full）；
    ///     表未命中回退族级（同 includeColor/palette 口径）并经 onTableMiss 计数，不崩不静默；
    ///  ② 趋近音【无时长门槛】（guide always rectify：只要与下一音半音±1 且下一音为可用音即保留，不看正/反拍时长）；
    ///  ③ 结尾合并相邻【非休止】同音（Java removeRepeatedNotesInPlace：休止/null 断链、时值相加）。
    /// - Parameter colorMode: [Guide Color 圆点 20260914] off=spell-only（默认，对齐 Java 出厂 colorBox 不勾）；
    ///   conservative=spell+自然9/11/13（与 grammar 同源）；full=spell+全量 color（对齐 Java 勾选 colorBox）
    static func rectifyGuideSpellOnly(_ melody: [PhysicalNote],
                                      chordBlocks: [ChordBlock],
                                      slotsPerBeat: Int = 120,
                                      beatsPerMeasure: Int = 4,
                                      colorMode: GuideRectifyColorMode = .off,
                                      onTableMiss: ((String) -> Void)? = nil) -> [PhysicalNote] {
        let allowColorBool = (colorMode != .off)   // 「是否含色彩」布尔位（趋近豁免 / includeColor 用）
        // G1 可用音 provider：off→spell-only（出厂）；conservative→spell+保守色；full→spell+全 color。
        // 表未命中回退族级，并按三态给对应 palette（off 不给 palette=仅和弦）。
        let provider: RectifyUsableToneProvider = { chordName, minPitch, maxPitch, _ in
            if let r = GTVocResolver.resolve(name: chordName, colorMode: colorMode), !r.candidatePCs.isEmpty {
                var out: [Int] = []
                for pc in r.candidatePCs {
                    for oct in [48, 60, 72, 84] {
                        let p = pc + oct
                        if p >= minPitch && p <= maxPitch { out.append(p) }
                    }
                }
                return out.sorted()
            }
            onTableMiss?(chordName)   // 表未命中：登记，回退族级（不崩、不静默）
            let famPalette: ColorPaletteMode? = colorMode == .off ? nil : (colorMode == .full ? .full : .conservative)
            return getChordTonesForRectify(chordName: chordName, minPitch: minPitch, maxPitch: maxPitch,
                                           includeColor: allowColorBool, palette: famPalette)
        }

        var result = melody
        var accumSlot = 0
        for (i, note) in melody.enumerated() {
            // 休止符不修正
            guard note.midiPitch >= 0 else { accumSlot += note.durationSlots; continue }

            // 第1段：已是可用音（spell-only 或 spell+color）→ 保留
            let usableTones = getChordTonesAtSlot(slot: accumSlot, chordBlocks: chordBlocks,
                                                  slotsPerBeat: slotsPerBeat,
                                                  refPitch: note.midiPitch,
                                                  includeColor: allowColorBool,
                                                  usableToneProvider: provider)
            if usableTones.contains(where: { abs($0 - note.midiPitch) % 12 == 0 }) {
                accumSlot += note.durationSlots
                continue
            }

            // 第2段：趋近音豁免（无时长门槛）——与下一音半音±1，且下一音为其和弦可用音（spell/spell+color）
            var isApproach = false
            if i + 1 < melody.count {
                let nextNote = melody[i + 1]
                if nextNote.midiPitch >= 0 && abs(nextNote.midiPitch - note.midiPitch) == 1 {
                    let nextSlot = accumSlot + note.durationSlots
                    let nextUsable = getChordTonesAtSlot(slot: nextSlot, chordBlocks: chordBlocks,
                                                         slotsPerBeat: slotsPerBeat,
                                                         refPitch: nextNote.midiPitch,
                                                         includeColor: allowColorBool,
                                                         usableToneProvider: provider)
                    isApproach = nextUsable.contains { abs($0 - nextNote.midiPitch) % 12 == 0 }
                }
            }
            if isApproach { accumSlot += note.durationSlots; continue }

            // 第3段：其余 → 就近吸附可用音（等距优先向上）
            if !usableTones.isEmpty {
                let nearest = findClosestMatch(pitch: note.midiPitch, chordTones: usableTones)
                result[i] = PhysicalNote(midiPitch: nearest,
                                         durationSlots: note.durationSlots,
                                         tuplet: note.tuplet,
                                         terminalType: "C")
            }
            accumSlot += note.durationSlots
        }
        // 结尾：合并相邻非休止同音（对齐 Java removeRepeatedNotesInPlace）
        return mergeAdjacentSameSounding(result)
    }

    /// [T2] 合并相邻【非休止】同音：休止断链，相邻同音时值相加（仅 guide&Transform 整流末尾使用）
    private static func mergeAdjacentSameSounding(_ notes: [PhysicalNote]) -> [PhysicalNote] {
        var out: [PhysicalNote] = []
        for n in notes {
            if n.midiPitch < 0 { out.append(n); continue }   // 休止断链
            if let last = out.last, last.midiPitch >= 0, last.midiPitch == n.midiPitch {
                out[out.count - 1] = PhysicalNote(midiPitch: last.midiPitch,
                                                  durationSlots: last.durationSlots + n.durationSlots,
                                                  tuplet: last.tuplet,
                                                  terminalType: last.terminalType)
            } else {
                out.append(n)
            }
        }
        return out
    }

    // [Guide Color 圆点 20260914] palette=nil 时维持旧行为（读 ChordQuality.activePalette，grammar rectifyAllBeats
    // 与 getChordTonesAtSlot 兜底路径不传=逐音不变）；guide 三态显式传 .conservative/.full。
    private static func getChordTonesForRectify(chordName: String, minPitch: Int, maxPitch: Int,
                                                includeColor: Bool = false,
                                                palette: ColorPaletteMode? = nil) -> [Int] {
        let cleanName = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
        let quality = ChordQuality(chordName: cleanName)
        let rootPC = getRootPCForRectify(cleanName)
        // includeColor=true 时合法集合 = 和弦音 + 色彩音（对齐 Java usableTones = spell + color），去重保序
        var intervals = quality.chordIntervals
        if includeColor {
            var seen = Set(intervals)
            for c in quality.colorIntervals(for: cleanName, palette: palette) where !seen.contains(c) {
                intervals.append(c)
                seen.insert(c)
            }
        }
        var pitches: [Int] = []
        for interval in intervals {
            let pc = (rootPC + interval) % 12
            for oct in [48, 60, 72, 84] {
                let p = pc + oct
                if p >= minPitch && p <= maxPitch { pitches.append(p) }
            }
        }
        return pitches.isEmpty ? [60] : pitches.sorted()
    }
    
    private static func getRootPCForRectify(_ name: String) -> Int {
        let n = name.replacingOccurrences(of: "♭", with: "b").replacingOccurrences(of: "♯", with: "#")
        // pcMap 补全所有异名同音（与 ContentView.chordRootPC / GrammarNoteConverter.getRootPC 一致）
        let pcMap: [String: Int] = [
            "C": 0, "B#": 0,
            "C#": 1, "Db": 1,
            "D": 2,
            "D#": 3, "Eb": 3,
            "E": 4, "Fb": 4,
            "F": 5, "E#": 5,
            "F#": 6, "Gb": 6,
            "G": 7,
            "G#": 8, "Ab": 8,
            "A": 9,
            "A#": 10, "Bb": 10,
            "B": 11, "Cb": 11
        ]
        // 只匹配大写字母 + #/b，小写质量字母(m/a/j/s/u/d/i)自动终止
        // 对齐 JazzHarmonicModels.chordRootPC 的解析方式
        var root = String(n.prefix(while: { $0.isLetter && $0.isUppercase || $0 == "#" || $0 == "b" }))
        if root.isEmpty { root = String(n.prefix(1)) }  // 兜底：至少取第一个字符
        return pcMap[root] ?? 0
    }
    
    /// 获取指定 slot 位置的和弦音（用于 rectify 的当前和弦/下一和弦查询）
    /// 对齐 Java RectifyPitchesCommand L204-207 的 usableTones / nextUsableTones 构建
    /// - Parameters:
    ///   - slot: 绝对 slot 位置（从拍0开始）
    ///   - chordBlocks: 和弦块数组（cb.duration 为拍数）
    ///   - slotsPerBeat: 每拍 slot 数（默认 120）
    ///   - refPitch: 参考音高，用于限定查询范围（refPitch±12）
    /// - Returns: 该 slot 位置和弦的和弦音数组（实际 MIDI 音高）
    private static func getChordTonesAtSlot(slot: Int, chordBlocks: [ChordBlock],
                                              slotsPerBeat: Int, refPitch: Int,
                                              includeColor: Bool = false,
                                              usableToneProvider: RectifyUsableToneProvider? = nil) -> [Int] {
        var cAccum = 0
        for cb in chordBlocks {
            let cbSlots = Int(Double(cb.duration) * Double(slotsPerBeat))
            if slot >= cAccum && slot < cAccum + cbSlots {
                // 【T1】注入优先：guide&Transform 传 G1 词表 provider；nil（grammar 默认）走原族级，逐音不变
                if let provider = usableToneProvider {
                    return provider(cb.name, refPitch - 12, refPitch + 12, includeColor)
                }
                return getChordTonesForRectify(chordName: cb.name,
                                                minPitch: refPitch - 12,
                                                maxPitch: refPitch + 12,
                                                includeColor: includeColor)
            }
            cAccum += cbSlots
        }
        return []
    }
    
    // MARK: - 对齐 Java Note.getClosestMatch (Note.java:399-454)
    
    /// 吸附到最近和弦音，等距时优先向上（对齐 Java 搜索顺序 P, P+1, P-1, P+2, P-2...）
    /// Java L429-443: stepSearch 0→P, 1(奇)→P+1, 2(偶)→P-1, 3(奇)→P+2, 4(偶)→P-2...
    /// - Parameters:
    ///   - pitch: 原始音高
    ///   - chordTones: 候选和弦音（实际 MIDI 音高，在 pitch±12 范围内）
    /// - Returns: 最近的和弦音，等距优先向上
    private static func findClosestMatch(pitch: Int, chordTones: [Int]) -> Int {
        // step 0: 精确匹配
        if chordTones.contains(pitch) { return pitch }
        // step 1,2,3...: 先向上，再向下（对齐 Java 奇数步向上、偶数步向下）
        for step in 1...24 {
            if step % 2 == 1 {
                // 奇数步：向上
                let up = pitch + (step + 1) / 2
                if chordTones.contains(up) { return up }
            } else {
                // 偶数步：向下
                let down = pitch - step / 2
                if chordTones.contains(down) { return down }
            }
        }
        return chordTones.first ?? pitch
    }

    // MARK: - P0-4 Swing时隙偏移

    /// Part.makeSwing() 八分音符摇摆偏移
    /// - Parameters:
    ///   - melody: 输入旋律 (每音已含 durationSlots)
    ///   - swingValue: 偏移比例 (默认 0.666 = 爵士经典 2:1摇摆)
    ///   - beatSlots: 每拍slot数 (默认 120 = BEAT)
    /// - Returns: swing偏移后的旋律
    static func makeSwing(_ melody: [PhysicalNote],
                          swingValue: Double = 0.666,
                          beatSlots: Int = 120) -> [PhysicalNote] {
        guard swingValue != 0.5 else { return melody } // 无偏移
        var result = melody

        // 按拍遍历: 检查每拍的第2个八分音符→偏移
        var beatStart = 0
        var i = 0
        while i < result.count {
            let note = result[i]
            if note.midiPitch == -1 { i += 1; continue } // 跳过休止符

            let slotInBeat = beatStart % beatSlots
            // 如果在后半个八分(between beatSlots/2 and beatSlots), 做swing偏移
            if slotInBeat >= beatSlots / 2 {
                let offset = Int(Double(beatSlots) * swingValue) - beatSlots / 2
                if offset != 0 {
                    // 将当前音符时值按swing比例重新分配
                    let swingDur = note.durationSlots + offset
                    result[i] = PhysicalNote(midiPitch: note.midiPitch,
                                             durationSlots: max(1, swingDur))
                }
            }
            beatStart += note.durationSlots
            i += 1
        }
        return result
    }

    // MARK: - P1-2 Part.mergeTies() 延音线合并

    /// Part.java mergeTies: 相邻同音合并时值, 跨小节延音
    /// - Parameter melody: 按时间顺序排列的音符序列
    /// - Returns: 合并延音后的旋律
    static func mergeTies(_ melody: [PhysicalNote]) -> [PhysicalNote] {
        guard melody.count > 1 else { return melody }
        var result: [PhysicalNote] = []
        var i = 0
        while i < melody.count {
            let current = melody[i]
            if current.midiPitch == -1 { result.append(current); i += 1; continue }
            var merged = current
            var j = i + 1
            while j < melody.count {
                let next = melody[j]
                if next.midiPitch == merged.midiPitch {
                    merged = PhysicalNote(midiPitch: merged.midiPitch,
                                          durationSlots: merged.durationSlots + next.durationSlots)
                    j += 1
                } else { break }
            }
            result.append(merged)
            i = j
        }
        return result
    }
}
