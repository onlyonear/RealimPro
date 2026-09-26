//
//  GrammarStrategy.swift
//  Improlyze
//
//  Grammar 策略 - 实现 JazzImproStrategy 协议，接入现有系统
//  第一阶段：最简单的接入
//

import Foundation
/// 旋律生成+Transform后处理工作模式
enum MelodyTransformMode: String, CaseIterable {
    /// 仅原生文法生成，不执行变换后处理
    case rawGrammar
    /// 文法生成 → 经过Transform引擎修饰处理
    case grammarWithTransform
}

/// 文法展开视野模式（整曲化改造，对齐 Java Grammar.run 对整段选区一次性展开）
/// - wholeSong：整曲一次 run（Java 语义，目标行为，默认）
/// - segment ：逐砖段独立 run 再拼接（改造前旧行为，仅保留用于盲听对照/一键回退）
/// 由调音台临时档写入 UserDefaults("grammarSegmentModeRaw")；盲听定版后删除 UI，wholeSong 成为唯一行为。
enum GrammarSegmentMode: String, CaseIterable {
    case wholeSong
    case segment
    var label: String {
        switch self {
        case .wholeSong: return "Whole Song"   // 整曲：长线完整乐句
        case .segment:   return "Segmented"    // 分段：旧版逐段拼接
        }
    }
    var shortLabel: String {
        switch self {
        case .wholeSong: return "Whole"
        case .segment:   return "Segment"
        }
    }
    /// 当前生效模式。整曲化已定稿（2026-09-05）：调音台临时档已移除，**固定 .wholeSong**。
    /// 不再读 UserDefaults——避免盲听期残留的 "segment" 把用户锁在旧行为。
    /// 若日后需内部 A/B：把下面一行换回
    /// `GrammarSegmentMode(rawValue: UserDefaults.standard.string(forKey: "grammarSegmentModeRaw") ?? "") ?? .wholeSong`
    /// 并恢复 BandMixerView 的 PHRASE Menu 即可。
    static func current() -> GrammarSegmentMode {
        .wholeSong
    }
}
class GrammarStrategy: JazzImproStrategy {

    let name: String
    private let grammarFileName: String

    // MARK: 缓存语法实例，避免每次生成都重新解析文件
    private var cachedGrammar: Grammar?

    // MARK: Transform后处理配置属性
    var transformMode: MelodyTransformMode = .rawGrammar
    var activeTransform: TransformEngine.Transform = TransformEngine.Transform()
    var metre: [Int] = [4, 4]
    var activeTrendSegment: TrendSegment?  // Trend生成系统注入点

    // P1-后置: 复杂度控制开关
    var enableApproachNotes: Bool = false   // 趋近音
    var enableSyncopation:  Bool = false   // 切分音

    // 整流档位：产品固定全拍对齐原版(.allBeats)；Off/StrongBeats 逻辑保留在 GrammarLickGlue 供调试
    var rectifyMode: RectifyMode = .allBeats
    // D4 色彩音池档位（conservative=白名单历史行为；full=对齐 Java 全量），由 UI 注入
    var colorMode: ColorPaletteMode = .conservative
    // Q4 八度放置策略。2026-09-06 盲听定稿固定 .smooth（rooted/Leaps 听感不佳已放弃；枚举与分支保留备查）
    var octaveMode: OctavePlacementMode = .smooth

    init(grammarFileName: String, displayName: String) {
        self.name = displayName
        self.grammarFileName = grammarFileName
        // 初始化时加载默认变换规则
        self.activeTransform = .makeDefault()
        // 初始化时预加载语法
        self.cachedGrammar = Grammar(grammarFile: grammarFileName)
    }

    // 获取或创建语法实例（缓存）
    private func getGrammar() -> Grammar {
        if let cached = cachedGrammar {
            return cached
        }
        let grammar = Grammar(grammarFile: grammarFileName)
        cachedGrammar = grammar
        return grammar
    }

    // 协议要求统一入口，自动分发双生成链路+变换后处理

    func generateSolo(for roadmap: JazzRoadmap) -> [PhysicalNote] {
        // ⏱️ 性能分析: 总耗时起点
        let perfTotal = CFAbsoluteTimeGetCurrent()

        // 阶段4.2 POC: 启用动态产生式
        CYKParser.useDynamicProductions = true
        let chordBlocks = roadmap.flattenRoadmap()

        // 阶段2(P1): 触发调性链自动解析 (供ChordExtensionTonePool转调适配)
        if roadmap.keyMap.isEmpty { roadmap.buildKeyMap() }

        // P0-1: 主动Trend调度 — 每3~5小节切换趋势, 注入activeTrendSegment
        assignTrendSegment(chordBlocks: chordBlocks, roadmap: roadmap)

        // P0-5: 和弦动态替换 (副本操作, 不修改原始roadmap)
        // [封存 20260914 方案A] 旧 grammar&Transform 用下面这行做 10% 随机三全音/次属替代，
        // 但加花对着替代和弦匹配、收尾 convert/整流却按【原始和弦】，自相矛盾且白掷一次随机；
        // Java Transform 是对选区原始 ChordPart 做的，没有这层随机。方案A 起加花统一用原始
        // chordBlocks，故把该调用一并注释封存（不是只丢弃结果），避免每轮白掷随机、也避免后人误判其仍生效。
        // 和声替代（三全音/次属/后门/调式互换）属独立功能，未来立项时做「贯穿加花/整流/渲染」的显式开关。
        // SubstitutionDictionary.swift 文件本身保留不删。
        // let substitutedBlocks = SubstitutionDictionary.resolve(chordBlocks: chordBlocks, style: grammarFileName)

        // ⏱️ CYK#1: stampBrickTypes
        let perfCYK1 = CFAbsoluteTimeGetCurrent()
        // P0-2: CYK解析→标注brickType到每个ChordBlock (仅用于Grammar层, 不修改原始Roadmap)
        let annotatedBlocks = roadmap.stampBrickTypes()
        let perfCYK1Elapsed = (CFAbsoluteTimeGetCurrent() - perfCYK1) * 1000

        // P0-1 修复(方案A): rawGrammar 模式跳过 NCP 往返, 直接使用文法 terminals
        // 原因: batchToNCP→batchToTerminals 会丢失 scaleDegree 字符串 (X3/X5/X7 的级数信息),
        //       导致 getPitchFromScaleDegree 永远不被调用, X 终端退化为"从音阶就近选音"
        let outTerminals: [GrammarTerminal]
        // [方案A 20260914] grammarWithTransform 改为 convert-before-transform：分支内先选真实音、
        // 引擎加花后以 PhysicalNote 直通并承载于此（nil = 走下方共享 convert 的旧路径，rawGrammar 恒 nil）。
        var concreteOverride: [PhysicalNote]? = nil

        // 使用缓存的语法实例，避免重复解析（方案A 上提：xform 分支内 convert 也需要它）
        let grammar = getGrammar()
        _pendingTrendSegment = activeTrendSegment  // P0-1: 注入Trend池桥接
        // D4: 生成本条 Solo 前注入色彩音池档位（convert 入口会清空和弦解析缓存，故此处设置对整条链生效）
        ChordQuality.activePalette = colorMode
        // Q4: 同步注入八度放置策略（smooth/rooted），仅影响 X 级数音选哪个八度
        OctavePlacementMode.active = octaveMode

        // ⏱️ 文法展开 (含 CYK#2 parseBricks)
        let perfExpand = CFAbsoluteTimeGetCurrent()
        switch transformMode {
        case .rawGrammar:
            outTerminals = generateRawGrammarTerminalSequence(roadmap: roadmap, chordBlocks: annotatedBlocks)

        case .grammarWithTransform:
            let terminals = generateRawGrammarTerminalSequence(roadmap: roadmap, chordBlocks: annotatedBlocks)
            // ── [旧链·封存 20260914 方案A] 占位60→加花→回转重选：在一片占位音高上跑相对算子，
            //    出端 terminalType 缺失回落 .chord 再二次 convert，把加花色彩音全部抹平，故停用：
            // let preNCP = GrammarTerminal.batchToNCP(terminals: terminals, chordBlocks: substitutedBlocks, metre: metre)
            // let ncpSequence = activeTransform.applyAllTransformations(ncpSequence: preNCP, chordBlocks: substitutedBlocks, metre: metre)
            // outTerminals = TransformEngine.NoteChordPair.batchToTerminals(ncpSequence: ncpSequence)
            //
            // ── [方案A] convert-before-transform（对齐 Java / guide：先定具体音再加花、加完不二次重选）──
            // 1) 与 rawGrammar 同一个选音函数、同一套已上提的全局状态，先选出真实音高（含 terminalType）
            let rawConcrete = GrammarNoteConverter.convert(
                abstractMelody: terminals,
                roadmap: roadmap,
                grammarParameters: grammar.masterParameters,
                beatsPerMeasure: metre.first ?? 4
            )
            // 2) 真实音高桥（复用既有 PhysicalNote.batchToNCP）；和弦统一用【原始 chordBlocks】，不用随机替代
            let preNCP = PhysicalNote.batchToNCP(guideToneLine: rawConcrete, chordBlocks: chordBlocks)
            // 3) 直调 Java 对齐引擎（与 GuideTransformBridge 同一个；不走 applyAllTransformations 内额外的
            //    family 整流与 48–84 硬钳，整流只保留下方 LightPost.rectifyAllBeats 一次，对齐 Java 只整流一次）。
            //    乐手沿用全局所选（ContentView 生成前写入 javaAlignedMusician）；mode 缺省=生产真洗牌 SystemRNG。
            let tbl = TransformMusicianRegistry.tableWithFallback(TransformEngine.javaAlignedMusician) ?? []
            // ── [和弦时间线修复 20260924] 旧码封存：原先未传 chordTimeline，引擎从 NCP 音头反推和弦边界，
            //    长音横跨换和弦、边界无音头时漏掉中间和弦（实测 B7+ 被挂成 Dm7），加花 guard 误否、RNG 失步。
            //    直接复用共享 PhysicalNote.chordTimeline（batchToNCP 内部也是同一口径），不重复写累加循环。
            // let xformed = TransformEngine.JavaAlignedTransformEngine.apply(to: preNCP, table: tbl)
            let chordTimeline = PhysicalNote.chordTimeline(chordBlocks: chordBlocks)
            let xformed = TransformEngine.JavaAlignedTransformEngine.apply(to: preNCP, table: tbl,
                                                                          chordTimeline: chordTimeline)
            // 4) NCP→PhysicalNote 保留引擎具体音高/时值/三连；不回抽象 terminal、不二次 convert
            concreteOverride = xformed.map {
                PhysicalNote(midiPitch: $0.note.midiPitch, durationSlots: $0.note.durationSlots,
                             tuplet: $0.note.tuplet, terminalType: $0.note.terminalType)
            }
            outTerminals = []  // 本分支由 concreteOverride 承载，下方共享 convert 不再执行
        }
        let perfExpandElapsed = (CFAbsoluteTimeGetCurrent() - perfExpand) * 1000

        // ⏱️ 音高选择 (核心热路径)
        let perfPitch = CFAbsoluteTimeGetCurrent()
        // [方案A] xform 分支已在上方选好真实音并加花（concreteOverride 非空）直接用；rawGrammar 走共享 convert（一音不变）
        let rawMelody = concreteOverride ?? GrammarNoteConverter.convert(
            abstractMelody: outTerminals,
            roadmap: roadmap,
            grammarParameters: grammar.masterParameters,
            beatsPerMeasure: metre.first ?? 4
        )
        let perfPitchElapsed = (CFAbsoluteTimeGetCurrent() - perfPitch) * 1000

        // ── 胶水层后置处理: 音域钳位 + 大跳平滑 + rectify 整流（档位由 rectifyMode 决定）──
        let perfPost = CFAbsoluteTimeGetCurrent()
        let postProcessed = LightPostProcessor.process(
            rawMelody,
            minPitch: grammar.masterParameters["min-pitch"] as? Int ?? 58,
            maxPitch: grammar.masterParameters["max-pitch"] as? Int ?? 82,
            chordBlocks: chordBlocks,
            slotsPerBeat: 120,
            beatsPerMeasure: metre.first ?? 4,
            rectifyMode: rectifyMode
        )
        let perfPostElapsed = (CFAbsoluteTimeGetCurrent() - perfPost) * 1000

        let perfTotalElapsed = (CFAbsoluteTimeGetCurrent() - perfTotal) * 1000
        // ⏱️ 性能分析日志
        dprint("⏱️ [PERF] generateSolo 总耗时: \(String(format: "%.1f", perfTotalElapsed))ms | " +
              "CYK#1(stamp): \(String(format: "%.1f", perfCYK1Elapsed))ms | " +
              "文法展开(含CYK#2): \(String(format: "%.1f", perfExpandElapsed))ms | " +
              "音高选择: \(String(format: "%.1f", perfPitchElapsed))ms | " +
              "后处理: \(String(format: "%.1f", perfPostElapsed))ms | " +
              // [方案A] 统一以最终进入胶水层的音符数为准（xform 分支 outTerminals 为空、真实承载是 rawMelody）
              "音符数: \(rawMelody.count)")

        // 🔍 诊断: dump前20个MIDI音高
        let pitches = postProcessed.prefix(20).map { $0.midiPitch }
        //dprint("🎵 [PITCH DUMP] first 20 midi pitches: \(pitches)")
        return postProcessed
    }

    private func generateRawGrammarTerminalSequence(roadmap: JazzRoadmap, chordBlocks: [ChordBlock]) -> [GrammarTerminal] {
        var allAbstractMelody: [GrammarTerminal] = []
        let grammar = getGrammar()
        grammar.slotsPerBeat = JazzGuideToneEngine.slotsPerBeat
        grammar.beatsPerMeasure = metre.first ?? 4

        // Step2: 构建和声段 (每和弦取最长覆盖砖)
        let (_, bricks) = roadmap.parseBricks()
        let sections = buildBrickSections(chordBlocks: chordBlocks, bricks: bricks,
                                          slotsPerBeat: JazzGuideToneEngine.slotsPerBeat)
        #if DEBUG
        dprint("[STEP2-SECTIONS] count=\(sections.count) bricks=\(sections.map { "\($0.brickName)(\($0.totalSlots)slots)" })")
        #endif

        switch GrammarSegmentMode.current() {
        case .wholeSong:
            // ═══ 整曲一次 run（对齐 Java：Notate 对整段选区一次性 grammar.run，视野=整曲）═══
            // 1) 构造「全局 slot → 和弦」调度：每个和弦一条，brickType 设为其所属砖段砖名
            //    （与旧版 effectiveChord 覆盖段首 brickType 的语义一致，供 builtin brick 选乐句）；
            // 2) measureOffset=0，使 Grammar.absSlot()==全局 slot，选规则时按当前位置查到正确和弦；
            // 3) 超长 BRICK 走 .keepTruncate（允许起句、末尾自然截断），4–8 小节完整乐句因此可达。
            // 注：ChordBlock 是 struct，这里的拷贝改 brickType 不会污染音高层使用的原始 chordBlocks。
            var schedule: [(startSlot: Int, block: ChordBlock)] = []
            var cursor = 0
            for section in sections {
                for (block, blockSlots) in zip(section.chordBlocks, section.chordSlots) {
                    var scheduled = block
                    scheduled.brickType = section.brickName
                    schedule.append((startSlot: cursor, block: scheduled))
                    cursor += blockSlots
                }
            }
            grammar.measureOffset = 0
            grammar.brickOverflowMode = .keepTruncate
            grammar.setChordSchedule(schedule)
            let totalSlotsAll = sections.reduce(0) { $0 + $1.totalSlots }
            let fullMelody = grammar.run(startSlot: 0, numSlots: totalSlotsAll)
            allAbstractMelody.append(contentsOf: fullMelody)

        case .segment:
            // ═══ 旧版：逐砖段独立 run(0, 段长) 再拼接（盲听回退，行为与整曲化改造前完全一致）═══
            grammar.brickOverflowMode = .exclude
            grammar.setChordSchedule([])  // 空调度 → Grammar.refreshChordAtCurrentSlot 直接返回，沿用外部逐段赋值
            var accumulatedSlot = 0
            for section in sections {
                let startChord = section.chordBlocks.first!
                // Step2: 用段的砖名覆盖首和弦 brickType (避免大砖覆盖小砖的映射失效)
                var effectiveChord = startChord
                effectiveChord.brickType = section.brickName
                grammar.measureOffset = accumulatedSlot % (grammar.slotsPerBeat * grammar.beatsPerMeasure)
                grammar.currentChordName = effectiveChord.name
                grammar.currentChordBlock = effectiveChord

                let sectionMelody = grammar.run(startSlot: 0, numSlots: section.totalSlots)
                allAbstractMelody.append(contentsOf: sectionMelody)
                accumulatedSlot += section.totalSlots
            }
        }

        allAbstractMelody = flattenSlopeTerminals(allAbstractMelody, slotsPerBeat: grammar.slotsPerBeat, beatsPerMeasure: grammar.beatsPerMeasure)
        return allAbstractMelody
    }

    /// Step2: 和声分段结构
    private struct BrickSection {
        let brickName: String
        let totalSlots: Int
        let chordBlocks: [ChordBlock]
        let chordSlots: [Int]  // 每个和弦的 slot 数
    }

    /// Step2: 每和弦取最长覆盖砖，连续同砖合并为段
    private func buildBrickSections(chordBlocks: [ChordBlock],
                                     bricks: [(name: String, start: Double, end: Double, key: String, referenceKey: Int)] = [],
                                     slotsPerBeat: Int = 120) -> [BrickSection] {
        let n = chordBlocks.count
        // 1. 每和弦选最长覆盖砖
        var bestBrick = [(String?, Int)](repeating: (nil, 0), count: n)
        for brick in bricks {
            let s = Int(brick.start.rounded(.down))
            let e = Int(brick.end.rounded(.down))
            let len = e - s
            for i in max(0,s)..<min(n,e) where len > bestBrick[i].1 {
                bestBrick[i] = (brick.name, len)
            }
        }
        // 2. 连续同砖合并
        var sections: [BrickSection] = []
        var i = 0
        while i < n {
            let brickName = bestBrick[i].0 ?? chordBlocks[i].brickType ?? "nil"
            var j = i + 1
            while j < n && (bestBrick[j].0 ?? "nil") == brickName { j += 1 }
            let blockSlice = Array(chordBlocks[i..<j])
            let totalSlots = blockSlice.reduce(0) { $0 + Int(Double($1.duration) * Double(slotsPerBeat)) }
            let chordSlots = blockSlice.map { Int(Double($0.duration) * Double(slotsPerBeat)) }
            sections.append(BrickSection(brickName: brickName, totalSlots: totalSlots,
                                         chordBlocks: blockSlice, chordSlots: chordSlots))
            i = j
        }
        return sections
    }

    /// 将斜率终结符展开为内部子音符列表（对齐 GrammarNoteConverter 的 slope 分支）
    /// 必须在 NCP 往返前展开，否则 slopeNotes 会丢失导致选音回退 C4
    /// 🌟 新增: slope 内子终端拍位过滤（expandSymbol 未覆盖 slope 内部，导致正拍趋近音绕过过滤）
    /// 对齐 Java Generator.offbeat gate: 趋近音只能出现在反拍，正拍/强拍上的 A→C
    private func flattenSlopeTerminals(_ terminals: [GrammarTerminal], slotsPerBeat: Int, beatsPerMeasure: Int) -> [GrammarTerminal] {
        var flat: [GrammarTerminal] = []
        var currentAbsSlot = 0
        let measureLength = slotsPerBeat * beatsPerMeasure
        // 对齐 Grammar.swift strongBeatsPerMeasure
        let strongBeatsPerMeasure = beatsPerMeasure <= 3 ? 1 : (beatsPerMeasure % 2 == 0 ? 2 : (beatsPerMeasure % 3 == 0 ? 3 : 1))
        let timeBetweenStrongBeats = measureLength / strongBeatsPerMeasure

        func isOnBeat(_ slot: Int) -> Bool { slot % slotsPerBeat == 0 }
        func isStrongBeat(_ slot: Int) -> Bool { slot % timeBetweenStrongBeats == 0 }

        for t in terminals {
            if t.type == .slope, let notes = t.slopeNotes {
                for n in notes {
                    // slope 内子终端：拍位过滤（expandSymbol 未覆盖 slope 内部）
                    var resolvedType = n.type
                    if n.type == .approach && (isOnBeat(currentAbsSlot) || isStrongBeat(currentAbsSlot)) {
                        resolvedType = .chord
                        #if DEBUG
                        dprint("  [SLOPE-A2C] downbeat filter: approach→chord absSlot=\(currentAbsSlot) onBeat=\(isOnBeat(currentAbsSlot)) strong=\(isStrongBeat(currentAbsSlot))")
                        #endif
                    }
                    flat.append(GrammarTerminal(type: resolvedType, durationSlots: n.durationSlots,
                                                 isDotted: n.isDotted, tuplet: n.tuplet,
                                                 slopeMin: t.minSlope, slopeMax: t.maxSlope))
                    currentAbsSlot += n.actualDuration
                }
            } else {
                flat.append(t)
                currentAbsSlot += t.actualDuration
            }
        }
        return flat
    }

}

// MARK: - 预定义的 Grammar 策略

extension GrammarStrategy {

    /// 纯和弦音 — 无任何后置处理
    static let chord: GrammarStrategy = {
        let g = GrammarStrategy(grammarFileName: "chord", displayName: "Grammar - Chord Tone")
        g.enableApproachNotes = false; g.enableSyncopation = false
        return g
    }()

    /// 色彩音 — 趋近音+切分
    static let color: GrammarStrategy = {
        let g = GrammarStrategy(grammarFileName: "color", displayName: "Grammar - Color Tone")
        g.enableApproachNotes = true; g.enableSyncopation = true
        return g
    }()

    /// Charlie Parker — 所有后置处理全开
    static let charlieParker: GrammarStrategy = {
        let g = GrammarStrategy(grammarFileName: "Bebop", displayName: "Master - Bebop")
        g.enableApproachNotes = true; g.enableSyncopation = true
        return g
    }()
    
    // ── Master组: 追加风格 (BRICK+slope 架构, flattenSlopeTerminals 已覆盖) ──
    // Great Lick（greatMoments 文法）：下拉归入 Basic 组、显示名 Great Lick（生成配置不变）
    static let Lick: GrammarStrategy = {
        let g = GrammarStrategy(grammarFileName: "greatMoments", displayName: "Basic - Great Lick")
        g.enableApproachNotes = true; g.enableSyncopation = true
        return g
    }()
    static let ColemanHawkins: GrammarStrategy = {
        let g = GrammarStrategy(grammarFileName: "ColemanHawkins-Ballads", displayName: "Master - Ballad")
        g.enableApproachNotes = true; g.enableSyncopation = true
        return g
    }()
    static let LeeMorgan: GrammarStrategy = {
        let g = GrammarStrategy(grammarFileName: "Blues", displayName: "Master - Blues")
        g.enableApproachNotes = true; g.enableSyncopation = true
        return g
    }()
    /// Bill Evans — 钢琴风格, 大量琶音与和声色彩
    static let billEvans: GrammarStrategy = {
        let g = GrammarStrategy(grammarFileName: "BillEvans", displayName: "Master - Bill Evans")
        g.enableApproachNotes = true; g.enableSyncopation = true
        return g
    }()
    /// Joe Pass — 吉他风格, 大量slope线性走句
    static let joePass: GrammarStrategy = {
        let g = GrammarStrategy(grammarFileName: "JoePass", displayName: "Master - Joe Pass")
        g.enableApproachNotes = true; g.enableSyncopation = true
        return g
    }()

    // ── Master组: 2026-09 新增 5 位大师（文法与 Java 原版逐字节一致，整曲化后已离线回归）──
    /// Cannonball Adderley — 纯 START 平滑素材型
    static let cannonballAdderley: GrammarStrategy = {
        let g = GrammarStrategy(grammarFileName: "CannonballAdderley", displayName: "Master - Cannonball")
        g.enableApproachNotes = true; g.enableSyncopation = true
        return g
    }()
    /// Chet Baker — 冷爵士、以 START 平滑线条为主、BRICK 点缀
    static let chetBaker: GrammarStrategy = {
        let g = GrammarStrategy(grammarFileName: "ChetBaker", displayName: "Master - Chet Baker")
        g.enableApproachNotes = true; g.enableSyncopation = true
        return g
    }()
    /// John Coltrane — 大量成块乐句（整曲后 BRICK ~46%）
    static let johnColtrane: GrammarStrategy = {
        let g = GrammarStrategy(grammarFileName: "JohnColtrane", displayName: "Master - Coltrane")
        g.enableApproachNotes = true; g.enableSyncopation = true
        return g
    }()
    /// Miles Davis — 成块乐句与歌唱性线条兼具（整曲后 BRICK ~45%）
    static let milesDavis: GrammarStrategy = {
        let g = GrammarStrategy(grammarFileName: "MilesDavis", displayName: "Master - Miles")
        g.enableApproachNotes = true; g.enableSyncopation = true
        return g
    }()
    /// Red Garland — 钢琴风格、以 START 平滑素材为主、BRICK 少量点缀
    static let redGarland: GrammarStrategy = {
        let g = GrammarStrategy(grammarFileName: "RedGarland", displayName: "Master - Red Garland")
        g.enableApproachNotes = true; g.enableSyncopation = true
        return g
    }()

    /// Swing摇摆风格文法
    static let swing = GrammarStrategy(
        grammarFileName: "swing",
        displayName: "Grammar - 摇摆 Swing"
    )

    /// 每3~5小节随机切换Trend类型，创建TrendSegment注入给GrammarNoteConverter选音
    private func assignTrendSegment(chordBlocks: [ChordBlock], roadmap: JazzRoadmap) {
        let beatsPerMeasure = Double(metre.first ?? 4)
        let trendTypes: [any Trend] = [
            ArpeggioTrend(direction: 1, octaves: 2),
            AscendingTrend(stepSize: 2),
            DescendingTrend(stepSize: 2),
            ChromaticTrend(approachDirection: 1),
            DiatonicTrend(direction: 1),
            SkipTrend(minSkip: 3)
        ]
        var currentBeat: Double = 0
        var segmentChords: [String] = []
        segmentChords.reserveCapacity(8)
        var segmentKey: Key = .defaultKey
        var segmentType: (any Trend)? = trendTypes.randomElement()
        var remainingBeats = Double(Int.random(in: 3...5)) * beatsPerMeasure

        for chord in chordBlocks {
            if remainingBeats <= 0 || segmentType == nil {
                // 切换新Trend段: 提交上一个段
                if !segmentChords.isEmpty, let type = segmentType {
                    activeTrendSegment = TrendSegment(
                        name: type.name,
                        trend: type,
                        chordNames: segmentChords,
                        key: segmentKey,
                        pitchRange: 48...84,
                        transformWeights: weightsForTrend(type)
                    )
                }
                segmentChords.removeAll(keepingCapacity: true)
                segmentType = trendTypes.randomElement()
                remainingBeats = Double(Int.random(in: 3...5)) * beatsPerMeasure
                segmentKey = roadmap.key(at: currentBeat)
            }
            segmentChords.append(chord.name)
            currentBeat += chord.duration
            remainingBeats -= chord.duration
        }
        // 提交最后一个段
        if !segmentChords.isEmpty, let type = segmentType {
            activeTrendSegment = TrendSegment(
                name: type.name,
                trend: type,
                chordNames: segmentChords,
                key: segmentKey,
                pitchRange: 48...84,
                transformWeights: weightsForTrend(type)
            )
        }
    }

    /// P1-1: Trend类型→变换权重映射
    private func weightsForTrend(_ trend: any Trend) -> [String: Double] {
        if trend is ArpeggioTrend  { return ["arpeggioTransform": 0.8, "default": 0.2] }
        if trend is AscendingTrend  { return ["ascendingTransform": 0.8, "chromaticPassing": 0.3] }
        if trend is DescendingTrend { return ["descendingTransform": 0.8, "chromaticPassing": 0.3] }
        if trend is ChromaticTrend  { return ["chromaticPassing": 0.9, "enclosureTransform": 0.4] }
        if trend is DiatonicTrend   { return ["diatonicPassing": 0.7, "neighborTone": 0.3] }
        if trend is SkipTrend       { return ["skipTransform": 0.8, "approachTransform": 0.4] }
        return [:]
    }
}
