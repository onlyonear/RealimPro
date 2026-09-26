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

    case .lowColor:        // Java L521: L_* → COLOR_TONE
        return .colorTone

    case .midColor, .arbitrary:  // Java L520: S_*/X_* → SCALE_TONE
        return .scaleTone

    case .approach:     // Java L520: A_* → APPROACH
        return .approachNote

    case .outside:      // Java: Y_* → OUTSIDE
        return .outsideNote

    case .rest:         // Java L522: R_* → REST
        return .rest

    // ── 复合类型: 乐观映射, 实际音高由 NoteConverter 内部分支处理 ──
    case .highColor: return .colorTone    // H: 高色彩音

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
                        beatsPerMeasure: Int = 4) -> [PhysicalNote] {
        let clamped = clampToRange(melody, minPitch: minPitch, maxPitch: maxPitch)
        let smoothed = smoothLargeLeaps(clamped, maxLeap: maxLeap)
        guard let chords = chordBlocks else {
            return mergeAdjacent(smoothed)
        }
        let rectified = rectifyStrongBeats(smoothed, chordBlocks: chords,
                                           slotsPerBeat: slotsPerBeat,
                                           beatsPerMeasure: beatsPerMeasure)
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
    
    /// 将落在正拍/强拍位置的非和弦音(A/L/S/H)修正为最近和弦音
    /// Java: rectify=true 参数启动, LickGen RECTIFY_DEFAULT = "true"
    static func rectifyStrongBeats(_ melody: [PhysicalNote],
                                    chordBlocks: [ChordBlock],
                                    slotsPerBeat: Int = 120,
                                    beatsPerMeasure: Int = 4) -> [PhysicalNote] {
        let measureLength = beatsPerMeasure * slotsPerBeat
        let strongBeatInterval = measureLength / (beatsPerMeasure <= 3 ? 1 : (beatsPerMeasure % 2 == 0 ? 2 : (beatsPerMeasure % 3 == 0 ? 3 : 1)))
        
        var result = melody
        var accumSlot = 0
        
        for (i, note) in melody.enumerated() {
            let absSlot = accumSlot % measureLength
            let isOnBeat = absSlot % slotsPerBeat == 0
            let isStrong = absSlot % strongBeatInterval == 0
            
            // 仅修正正拍/强拍上的非和弦音, 保留弱拍/反拍的外音
            if (isOnBeat || isStrong), let tt = note.terminalType, tt != "C", tt != "R" {
                // 找到当前累积slot所属和弦
                var chordTones: [Int] = []
                var cAccum = 0
                for cb in chordBlocks {
                    let cbSlots = Int(Double(cb.duration) * Double(slotsPerBeat))
                    if accumSlot >= cAccum && accumSlot < cAccum + cbSlots {
                        chordTones = getChordTonesForRectify(chordName: cb.name,
                                                              minPitch: note.midiPitch - 12,
                                                              maxPitch: note.midiPitch + 12)
                        break
                    }
                    cAccum += cbSlots
                }
                
                // 替换为最近和弦音
                if !chordTones.isEmpty {
                    let nearest = chordTones.min(by: { abs($0 - note.midiPitch) < abs($1 - note.midiPitch) })!
                    result[i] = PhysicalNote(midiPitch: nearest,
                                              durationSlots: note.durationSlots,
                                              tuplet: note.tuplet,
                                              terminalType: "C")
                }
            }
            
            accumSlot += note.durationSlots
        }
        return result
    }
    
    private static func getChordTonesForRectify(chordName: String, minPitch: Int, maxPitch: Int) -> [Int] {
        let cleanName = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
        let quality = ChordQuality(chordName: cleanName)
        let rootPC = getRootPCForRectify(cleanName)
        let intervals = quality.chordIntervals
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
        let pcMap: [String: Int] = ["C":0,"C#":1,"Db":1,"D":2,"D#":3,"Eb":3,"E":4,"F":5,"F#":6,"Gb":6,"G":7,"G#":8,"Ab":8,"A":9,"A#":10,"Bb":10,"B":11]
        var root = String(n.prefix(while: { $0.isLetter || $0 == "#" || $0 == "b" }))
        if root.count > 1 && (root.hasSuffix("#") || root.hasSuffix("b")) { } else { root = String(name.prefix(1)) }
        return pcMap[root] ?? 0
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
