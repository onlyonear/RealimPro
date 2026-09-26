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
        // 注意: rawGrammar 模式下 substitutedBlocks 不参与生成 (convert 内部用 roadmap 原始和弦)
        let substitutedBlocks = SubstitutionDictionary.resolve(chordBlocks: chordBlocks, style: grammarFileName)

        // ⏱️ CYK#1: stampBrickTypes
        let perfCYK1 = CFAbsoluteTimeGetCurrent()
        // P0-2: CYK解析→标注brickType到每个ChordBlock (仅用于Grammar层, 不修改原始Roadmap)
        let annotatedBlocks = roadmap.stampBrickTypes()
        let perfCYK1Elapsed = (CFAbsoluteTimeGetCurrent() - perfCYK1) * 1000

        // P0-1 修复(方案A): rawGrammar 模式跳过 NCP 往返, 直接使用文法 terminals
        // 原因: batchToNCP→batchToTerminals 会丢失 scaleDegree 字符串 (X3/X5/X7 的级数信息),
        //       导致 getPitchFromScaleDegree 永远不被调用, X 终端退化为"从音阶就近选音"
        let outTerminals: [GrammarTerminal]
        // ⏱️ 文法展开 (含 CYK#2 parseBricks)
        let perfExpand = CFAbsoluteTimeGetCurrent()
        switch transformMode {
        case .rawGrammar:
            outTerminals = generateRawGrammarTerminalSequence(roadmap: roadmap, chordBlocks: annotatedBlocks)

        case .grammarWithTransform:
            let terminals = generateRawGrammarTerminalSequence(roadmap: roadmap, chordBlocks: annotatedBlocks)
            let preNCP = GrammarTerminal.batchToNCP(terminals: terminals, chordBlocks: substitutedBlocks, metre: metre)
            let ncpSequence = activeTransform.applyAllTransformations(ncpSequence: preNCP, chordBlocks: substitutedBlocks, metre: metre)
            outTerminals = TransformEngine.NoteChordPair.batchToTerminals(ncpSequence: ncpSequence)
        }
        let perfExpandElapsed = (CFAbsoluteTimeGetCurrent() - perfExpand) * 1000

        // 使用缓存的语法实例，避免重复解析
        let grammar = getGrammar()
        _pendingTrendSegment = activeTrendSegment  // P0-1: 注入Trend池桥接

        // ⏱️ 音高选择 (核心热路径)
        let perfPitch = CFAbsoluteTimeGetCurrent()
        let rawMelody = GrammarNoteConverter.convert(
            abstractMelody: outTerminals,
            roadmap: roadmap,
            grammarParameters: grammar.masterParameters,
            beatsPerMeasure: metre.first ?? 4
        )
        let perfPitchElapsed = (CFAbsoluteTimeGetCurrent() - perfPitch) * 1000

        // ── 胶水层后置处理: 音域钳位 + 大跳平滑 + 强拍rectify修正(弱拍保持自由) ──
        let perfPost = CFAbsoluteTimeGetCurrent()
        let postProcessed = LightPostProcessor.process(
            rawMelody,
            minPitch: grammar.masterParameters["min-pitch"] as? Int ?? 58,
            maxPitch: grammar.masterParameters["max-pitch"] as? Int ?? 82,
            chordBlocks: chordBlocks,
            slotsPerBeat: 120,
            beatsPerMeasure: metre.first ?? 4
        )
        let perfPostElapsed = (CFAbsoluteTimeGetCurrent() - perfPost) * 1000

        let perfTotalElapsed = (CFAbsoluteTimeGetCurrent() - perfTotal) * 1000
        // ⏱️ 性能分析日志
        dprint("⏱️ [PERF] generateSolo 总耗时: \(String(format: "%.1f", perfTotalElapsed))ms | " +
              "CYK#1(stamp): \(String(format: "%.1f", perfCYK1Elapsed))ms | " +
              "文法展开(含CYK#2): \(String(format: "%.1f", perfExpandElapsed))ms | " +
              "音高选择: \(String(format: "%.1f", perfPitchElapsed))ms | " +
              "后处理: \(String(format: "%.1f", perfPostElapsed))ms | " +
              "音符数: \(outTerminals.count)")

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
    static let Lick: GrammarStrategy = {
        let g = GrammarStrategy(grammarFileName: "greatMoments", displayName: "Master - Lick")
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
