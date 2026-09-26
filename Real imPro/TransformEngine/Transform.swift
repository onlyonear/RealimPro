import Foundation

extension TransformEngine {
    /// 原版顶层 Transform 总入口：装载全部替换规则，分动机/装饰音两阶段批量执行变换流水线
    struct Transform {
        /// 动机类替换规则组列表
        var motifSubstitutions: [Substitution]
        /// 装饰音类替换规则组列表
        var embellishmentSubstitutions: [Substitution]
        
        init(
            motifSubstitutions: [Substitution] = [],
            embellishmentSubstitutions: [Substitution] = []
        ) {
            self.motifSubstitutions = motifSubstitutions
            self.embellishmentSubstitutions = embellishmentSubstitutions
        }
        
        /// 深拷贝整套变换库
        func copy() -> Self {
            let copyMotif = motifSubstitutions.map { $0.copy() }
            let copyEmbellish = embellishmentSubstitutions.map { $0.copy() }
            return Transform(motifSubstitutions: copyMotif, embellishmentSubstitutions: copyEmbellish)
        }
        
        // MARK: 对外核心入口：整段旋律完整执行变换流水线
        /// - Parameters:
        ///   ncpSequence: 原始音符和弦序列（只读，内部生成副本运算）
        ///   chordBlocks: 整首曲子完整和弦序列
        ///   metre: 拍号 [每小节拍数, 每拍slot总数]
        ///   enforceDuration: 变换强制总时值不变
        ///   rectify: 是否修正音高到和弦音（默认true）
        /// - Returns: 变换后全新 NCP 旋律数组
        mutating func applyAllTransformations(
            ncpSequence: [NoteChordPair],
            chordBlocks: [ChordBlock],
            metre: [Int],
            enforceDuration: Bool = true,
            rectify: Bool = true,
            enableTrendDetection: Bool = false,
            chordChecker: TrendChordChecker? = nil
        ) -> [NoteChordPair] {
            var workingMelody = ncpSequence.map { $0.copy() }

            // 诊断: Transform前时值分布
            Self.logDurationDistribution(workingMelody, title: "Transform前")

            // 诊断: 超低音排查 — Transform前音符音高范围
            let preMidi = workingMelody.compactMap { $0.note.midiPitch >= 0 ? $0.note.midiPitch : nil }
            if !preMidi.isEmpty {
                //dprint("=== Transform前音符音高范围 ===")
                //dprint("最小MIDI: \(preMidi.min() ?? 0), 最大MIDI: \(preMidi.max() ?? 0)")
                //dprint("低于48的超低音数量: \(preMidi.filter { $0 < 48 }.count)")
            }

            // ── Trend预分段: 检测旋律趋势并按趋势段独立执行Transform ──
            // 【T1 封存】Java 对齐内核按整首两阶段替换、不走 Swift 自研 Trend 分段；
            // 仅旧 19 模板链（开关关）保留本段。
            if !TransformEngine.useJavaAlignedTransform, enableTrendDetection, let checker = chordChecker, workingMelody.count >= 3 {
                var segmented: [NoteChordPair] = []
                let trendTypes: [any TrendProtocol] = [
                    AscendingTrend(), DescendingTrend(), ChromaticTrend(),
                    DiatonicTrend(), SkipTrend(), ArpeggioTrend()
                ]
                for trend in trendTypes {
                    let det = TrendDetector(trend: trend, chordChecker: checker)
                    let segments = det.detect(ncps: workingMelody, chords: chordBlocks)
                    if segments.isEmpty { continue }
                    var pos = 0
                    for seg in segments {
                        // 趋势段内执行两阶段变换
                        var slice = seg.ncps
                        slice = applySubstitutionGroup(melody: slice, subsList: motifSubstitutions,
                            allChords: chordBlocks, metre: metre, enforceDuration: enforceDuration)
                        slice = applySubstitutionGroup(melody: slice, subsList: embellishmentSubstitutions,
                            allChords: chordBlocks, metre: metre, enforceDuration: enforceDuration)
                        segmented.append(contentsOf: slice)
                        pos += seg.count
                    }
                    // 末尾未覆盖部分
                    if pos < workingMelody.count {
                        segmented.append(contentsOf: workingMelody[pos...])
                    }
                    workingMelody = segmented
                    break  // 只取第一个命中趋势类型
                }
            }

            // 【T1 分流】总开关开 → Java 对齐通用内核（26 乐手静态表，两层保序去随机首取，
            // 空阶段跳过 F16）；关 → 旧 19 手写模板两阶段（整段封存保留，回退=翻 false）。
            if TransformEngine.useJavaAlignedTransform {
                let table = TransformMusicianRegistry.tableWithFallback(TransformEngine.javaAlignedMusician) ?? []
                workingMelody = JavaAlignedTransformEngine.apply(to: workingMelody, table: table)
            } else {
                // 第一阶段：motif 动机替换（旧链·封存）
                workingMelody = applySubstitutionGroup(
                    melody: workingMelody,
                    subsList: motifSubstitutions,
                    allChords: chordBlocks,
                    metre: metre,
                    enforceDuration: enforceDuration
                )

                // 第二阶段：embellishment 装饰音替换（旧链·封存）
                workingMelody = applySubstitutionGroup(
                    melody: workingMelody,
                    subsList: embellishmentSubstitutions,
                    allChords: chordBlocks,
                    metre: metre,
                    enforceDuration: enforceDuration
                )
            }
            
            // 第三阶段：Rectify 音高修正（默认开启）
            if rectify {
                workingMelody = rectifyMelody(workingMelody, chordBlocks: chordBlocks)
                // 最终兜底：强制clamp到48~84, pitch≤0用前一个音填充
                var clampCount = 0
                let preClamp = workingMelody  // 保存引用用于查找前一个音
                workingMelody = preClamp.enumerated().map { (idx, ncp) in
                    if ncp.note.midiPitch == -1 { return ncp }
                    var pitch = ncp.note.midiPitch
                    // 空音/未赋值pitch: 用前一个音高填充
                    if pitch <= 0 {
                        clampCount += 1
                        pitch = idx > 0 ? preClamp[idx-1].note.midiPitch : 60
                        //dprint("⚠️ 空音填充")
                    } else if pitch < 48 || pitch > 84 {
                        clampCount += 1
                        //dprint("⚠️ 被clamp的音")
                    }
                    while pitch < 48 { pitch += 12 }
                    while pitch > 84 { pitch -= 12 }
                    let clamped = PhysicalNote(midiPitch: pitch, durationSlots: ncp.note.durationSlots)
                    return NoteChordPair(note: clamped, chord: ncp.chord, slot: ncp.slot, transformVar: ncp.transformVar)
                }
                //dprint("一共被clamp的音数：\(clampCount)")
            }

            // 诊断: 超低音排查 — Transform后音符音高范围 (已注释)
            /*
            let postMidi = workingMelody.compactMap { $0.note.midiPitch >= 0 ? $0.note.midiPitch : nil }
            if !postMidi.isEmpty {
                #if DEBUG
                dprint("=== Transform后音符音高范围 ===")
                #endif
                #if DEBUG
                dprint("最小MIDI: \(postMidi.min() ?? 0), 最大MIDI: \(postMidi.max() ?? 0)")
                #endif
                #if DEBUG
                dprint("低于48的超低音数量: \(postMidi.filter { $0 < 48 }.count)")
                #endif
                if let minPitch = postMidi.min(), minPitch < 48 {
                    if let idx = postMidi.firstIndex(of: minPitch) {
                        #if DEBUG
                        dprint("⚠️ 超低音位置：第\(idx)个音，MIDI=\(minPitch)")
                        #endif
                        if idx > 0 { dprint("  前一个音MIDI=\(postMidi[idx-1])") }
                        if idx < postMidi.count - 1 { dprint("  后一个音MIDI=\(postMidi[idx+1])") }
                    }
                }
            }
            */

            // 诊断: Transform后时值分布 (已注释)
            // Self.logDurationDistribution(workingMelody, title: "Transform后")

            return workingMelody
        }
        
        // MARK: - Rectify 音高修正 (P0-1: 支持保留色彩音/Approach音)
        /// 修正音高到和弦音/色彩音; includeColor=true保留9/11/13, includeApproach=true保留半音趋近
        private func rectifyMelody(_ melody: [NoteChordPair], chordBlocks: [ChordBlock],
                                    includeColor: Bool = true, includeApproach: Bool = true) -> [NoteChordPair] {
            var chordTimeline: [(startSlot: Int, chord: ChordBlock)] = []
            var currentSlot = 0
            for chord in chordBlocks {
                let chordSlots = Int(chord.duration * Double(Constants.slotsPerBeat))
                chordTimeline.append((startSlot: currentSlot, chord: chord))
                currentSlot += chordSlots
            }
            return melody.map { ncp in
                if ncp.note.midiPitch == -1 { return ncp }
                var targetChord: ChordBlock? = nil
                for entry in chordTimeline.reversed() {
                    if ncp.slot >= entry.startSlot { targetChord = entry.chord; break }
                }
                guard let chord = targetChord else { return ncp }
                let pitchClass = ncp.note.midiPitch % 12
                let chordTones = getChordTones(chord: chord)
                guard !chordTones.isEmpty else { return ncp }
                // 和弦音 → 直接保留
                if chordTones.contains(pitchClass) { return ncp }
                // 色彩音保留 (9/11/13)
                if includeColor {
                    let colorTones = getColorTones(chord: chord)
                    if colorTones.contains(pitchClass) { return ncp }
                }
                // Approach音保留 (半音上下邻)
                if includeApproach {
                    for ct in chordTones {
                        if pitchClass == (ct + 1) % 12 || pitchClass == (ct + 11) % 12 { return ncp }
                    }
                }
                var closestPitch = ncp.note.midiPitch
                var minDistance = 12
                for tone in chordTones {
                    let octaveBase = (ncp.note.midiPitch / 12) * 12
                    for octaveOffset in [-12, 0, 12] {
                        let candidate = octaveBase + tone + octaveOffset
                        guard candidate >= 0 && candidate <= 127 else { continue }
                        let distance = abs(candidate - ncp.note.midiPitch)
                        if distance < minDistance { minDistance = distance; closestPitch = candidate }
                    }
                }
                closestPitch = max(0, min(127, closestPitch))
                let correctedNote = PhysicalNote(midiPitch: closestPitch, durationSlots: ncp.note.durationSlots)
                return NoteChordPair(note: correctedNote, chord: ncp.chord, slot: ncp.slot, transformVar: ncp.transformVar)
            }
        }
        
        /// 获取和弦的音高集合（相对于根音的半音数，0-11）
        private func getChordTones(chord: ChordBlock) -> Set<Int> {
            // 解析根音
            let rootMidi = parseRootMidi(chordName: chord.name)
            let rootClass = rootMidi % 12
            
            // 根据和弦族获取音程
            let family = chord.getChordFamily()
            var intervals: [Int]
            
            switch family {
            case .major:
                // 大和弦：根、三、五、大七
                intervals = [0, 4, 7, 11]
            case .minor:
                // 小和弦：根、小三、五、小七
                intervals = [0, 3, 7, 10]
            case .dominant:
                // 属七：根、三、五、小七
                intervals = [0, 4, 7, 10]
            case .halfDiminished:
                // 半减七：根、小三、减五、小七
                intervals = [0, 3, 6, 10]
            case .diminished:
                // 减七：根、小三、减五、减七
                intervals = [0, 3, 6, 9]
            case .augmented:
                // 增三：根、三、增五
                intervals = [0, 4, 8]
            case .sus:
                // sus和弦：根、四/二、五
                if chord.name.lowercased().contains("sus2") {
                    intervals = [0, 2, 7]
                } else {
                    intervals = [0, 5, 7]  // sus4
                }
            case .unknown:
                // 未知和弦，默认大三和弦
                intervals = [0, 4, 7]
            }
            
            // 转换为绝对音高（模12）
            return Set(intervals.map { ($0 + rootClass) % 12 })
        }
        
        /// 解析和弦根音的MIDI音高
        private func parseRootMidi(chordName: String) -> Int {
            let name = chordName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return 60 }  // 默认C
            
            var index = name.startIndex
            var rootNote: Character?
            var accidental = 0
            
            // 第一个字符是音名
            rootNote = name[index]
            index = name.index(after: index)
            
            // 检查变音记号
            if index < name.endIndex {
                if name[index] == "#" {
                    accidental = 1
                    index = name.index(after: index)
                } else if name[index] == "b" {
                    accidental = -1
                    index = name.index(after: index)
                }
            }
            
            // 音名到MIDI的映射（C4=60为基准，这里只需要相对关系）
            let noteOffsets: [Character: Int] = [
                "C": 0, "D": 2, "E": 4, "F": 5,
                "G": 7, "A": 9, "B": 11
            ]
            
            let baseOffset = noteOffsets[rootNote ?? "C"] ?? 0
            return baseOffset + accidental
        }

        // P0-1: 色彩音提取 — 9/11/13延伸音 + alter音, 用于rectify保留判断
        private func getColorTones(chord: ChordBlock) -> Set<Int> {
            let rootMidi = parseRootMidi(chordName: chord.name)
            let rootClass = rootMidi % 12
            let family = chord.getChordFamily()
            // 复用 ChordExtensionTonePool 已建立的8族白名单
            let tones = ChordExtensionTonePool.tonesFor(family)
            return Set(tones.map { ($0 + rootClass) % 12 })
        }
        
        // MARK: 批量遍历一组Substitution — 确定性调试模式
        // 【T1 封存】旧 19 手写模板链专用：单层 candidates.randomElement()（L362）随机选择，
        // 与 Java「weight 装袋→保序去重首取」不一致。Java 对齐内核不走此函数；
        // 仅在 useJavaAlignedTransform=false（默认）时可达，整段保留供回退/对照，勿删。
        private func applySubstitutionGroup(
            melody: [NoteChordPair],
            subsList: [Substitution],
            allChords: [ChordBlock],
            metre: [Int],
            enforceDuration: Bool
        ) -> [NoteChordPair] {
            var workingMelody = melody
            var pos = 0
            let maxIterations = workingMelody.count * 8
            var iter = 0

            #if DEBUG
            dprint("=== applySubstitutionGroup 开始 === 初始\(melody.count)音符")
            #endif
            for (i, ncp) in melody.enumerated() {
                #if DEBUG
                dprint("  初始[\(i)] slot=\(ncp.slot) dur=\(ncp.note.durationSlots) midi=\(ncp.note.midiPitch)")
                #endif
            }

            while pos < workingMelody.count, iter < maxIterations {
                iter += 1
                var candidates: [(newNotes: [NoteChordPair], matchLen: Int, name: String)] = []

                for sub in subsList {
                    guard sub.enabled, sub.weight > 0 else { continue }
                    let maxMatchLen = sub.maxMatchLength()
                    guard maxMatchLen > 0, pos + maxMatchLen <= workingMelody.count else { continue }

                    let testSegment = Array(workingMelody[pos..<min(pos + maxMatchLen, workingMelody.count)])
                    guard let transformedSeg = sub.apply(
                        melody: testSegment, chords: allChords,
                        startSlot: testSegment.first?.slot ?? 0, enforceDuration: enforceDuration
                    ) else { continue }

                    let matchLen = sub.findMatchLength(in: testSegment)
                    let actualMatchLen = min(matchLen, testSegment.count)
                    guard actualMatchLen > 0 else { continue }

                    let repeatCount = max(1, sub.weight)
                    for _ in 0..<repeatCount {
                        candidates.append((newNotes: transformedSeg, matchLen: actualMatchLen, name: sub.name))
                    }
                }

                // DEBUG: 打印所有候选
                #if DEBUG
                dprint("--- 迭代#\(iter) pos=\(pos) curDur=\(workingMelody[pos].note.durationSlots) ---")
                #endif
                for c in candidates {
                    #if DEBUG
                    dprint("  候选: \(c.name)[wt\(c.matchLen)] → \(c.newNotes.count)音 \(c.newNotes.map{"\($0.note.midiPitch)(\($0.note.durationSlots))"})")
                    #endif
                }

                if !candidates.isEmpty {
                    // 加权轮盘赌选择: candidates已按weight重复加入, 随机抽取即实现加权随机
                    let selected = candidates.randomElement()!
                    #if DEBUG
                    dprint("  ✅ 选中: \(selected.name) 替换[\(pos)..<\(pos+selected.matchLen)]")
                    #endif
                    workingMelody.replaceSubrange(pos..<pos + selected.matchLen, with: selected.newNotes)
                    pos += selected.matchLen  // 跳过匹配段, 不重入已替换区域
                } else {
                    #if DEBUG
                    dprint("  ⏭ 无匹配, pos+=1")
                    #endif
                    pos += 1
                }
            }

            #if DEBUG
            dprint("=== applySubstitutionGroup 结束 === 最终\(workingMelody.count)音符, 总dur=\(workingMelody.reduce(0){$0+$1.note.durationSlots})")
            #endif
            return workingMelody
        }
        
        // MARK: 规则增删管理
        mutating func addMotifSubstitution(_ sub: Substitution) {
            motifSubstitutions.append(sub)
        }
        
        mutating func addEmbellishmentSubstitution(_ sub: Substitution) {
            embellishmentSubstitutions.append(sub)
        }
        
        mutating func clearAllRules() {
            motifSubstitutions.removeAll()
            embellishmentSubstitutions.removeAll()
        }

        // MARK: - 诊断工具

        private static func logDurationDistribution(_ notes: [NoteChordPair], title: String) {
            var durationCount: [Int: Int] = [:]
            for ncp in notes {
                if ncp.note.midiPitch == -1 { continue }
                let dur = ncp.note.durationSlots
                durationCount[dur, default: 0] += 1
            }
            //dprint("=== \(title) 时值分布 ===")
            for (dur, count) in durationCount.sorted(by: { $0.key > $1.key }) {
                let noteName: String
                switch dur {
                    case 480: noteName = "全音符"
                    case 360: noteName = "附点二分"
                    case 240: noteName = "二分音符"
                    case 180: noteName = "附点四分"
                    case 120: noteName = "四分音符"
                    case 60:  noteName = "八分音符"
                    case 40:  noteName = "八分三连音"
                    case 30:  noteName = "十六分音符"
                    default:  noteName = "\(dur)slots"
                }
                //dprint("  \(noteName)(\(dur)slots): \(count)个")
            }
            let total = durationCount.values.reduce(0, +)
            //dprint("  总音符数: \(total)")
            //dprint("========================")
        }
    }
}
