//
//  ThemeGrammarFallback.swift
//  RealimPro
//
//  ThemeWeaver M2：空当窗回落 grammar 生成器（纯新增，不改任何现有文件）。
//  对齐 Java ThemeWeaver.generateFromGrammar(:5694) → LickGen.fillMelody：
//  对【全局子区间 start..start+windowSlots】独立跑一次 Grammar.run（不是整曲切片），
//  再走 GrammarNoteConverter.convert 的 M2 增量重载（全局 slot 查和弦 + 音域窗 + 首音参考）。
//

import Foundation

struct ThemeGrammarFallbackGenerator {

    let grammar: Grammar
    let roadmap: JazzRoadmap
    /// 全局和弦排程（整曲化定稿：setChordSchedule 全局查和弦）
    let schedule: [(startSlot: Int, block: ChordBlock)]
    let baseParameters: [String: Any]
    let beatsPerMeasure: Int
    /// ThemeWeaver 硬音域（默认 60...82，区别 grammar Solo 的 58–82；最终值，覆盖文法文头）
    let hardPitchRange: ClosedRange<Int>

    init(grammar: Grammar,
         roadmap: JazzRoadmap,
         schedule: [(startSlot: Int, block: ChordBlock)],
         baseParameters: [String: Any],
         beatsPerMeasure: Int,
         hardPitchRange: ClosedRange<Int> = 60...82) {
        self.grammar = grammar
        self.roadmap = roadmap
        self.schedule = schedule
        self.baseParameters = baseParameters
        self.beatsPerMeasure = beatsPerMeasure
        self.hardPitchRange = hardPitchRange
    }

    /// 供 ThemeWeaverEngine.grammarFallback 闭包调用
    func make(globalStart: Int,
              windowSlots: Int,
              pitchWindow: ClosedRange<Int>?,
              seedLastPitch: Int?) -> MelodyPart? {
        // 硬要求②：±6 pitchWindow 是“音高范围窗”；这里另外覆盖的是【步长/跳跃/避重复】标量，
        // 对应 Java ThemeWeaver.java:106-119 的 minInterval=0/maxInterval=6/leapProb=0.2/avoidRepeats=true。
        var params = baseParameters
        params["min-interval"] = 0
        params["max-interval"] = 6
        params["leap-prob"] = 0.2
        params["avoid-repeats"] = true

        // 每次空当窗都把全局和弦排程装回去，再对全局子区间独立 run（硬要求③）。
        // 注意 Grammar.run 的 numSlots 是【绝对终点】而非长度（accumulateTerminals 用 totalSlots-currentSlot），
        // 故全局子区间 [globalStart, globalStart+windowSlots] 要传绝对终点 globalStart+windowSlots。
        grammar.alignJavaFiveSegment = true
        grammar.brickOverflowMode = .keepTruncate
        grammar.setChordSchedule(schedule)
        grammar.measureOffset = 0
        let terms = grammar.run(startSlot: globalStart, numSlots: globalStart + windowSlots)

        // D-M2-3：空当窗不注入 Trend 池（_pendingTrendSegment 保持 nil，对齐真机 transform 默认关）
        let notes = GrammarNoteConverter.convert(
            abstractMelody: terms,
            roadmap: roadmap,
            grammarParameters: params,
            beatsPerMeasure: beatsPerMeasure,
            globalStartSlot: globalStart,           // 全局 slot 查和弦/判强拍
            hardPitchRange: hardPitchRange,         // 硬要求①：60–82 最终值，覆盖文法文头 58–82
            pitchWindow: pitchWindow,               // 上一段尾音 ±6（上下界已在引擎分别 clamp）
            seedLastPitch: seedLastPitch            // D-M2-2(a)：夹取后窗中心
        )
        return MelodyPart(notes)
    }
}
