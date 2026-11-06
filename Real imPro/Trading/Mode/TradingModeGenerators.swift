//
//  TradingModeGenerators.swift
//  Real imPro
//
//  M2-9: Trading 三个新模式的"前置生成"（引擎交互），每个返回一整轮 [TradingSlotNote]。
//    Modify and Rectify : 变形（MotifTransform）→ ALL_TONES 整流
//    Use Grammar        : GrammarStrategy 生成（内部已整流）→ 铺满 / removeRepeated
//    Use Transform      : flatten（TradingFlattener）→ 加花（JavaAlignedTransformEngine）
//                         → ALL_TONES 整流
//
//  架构（审核意见①）：整流统一收敛在 TradingResponder（rectifyAllTones），引擎交互放本文件；
//  本文件不做渲染/播放（下游全复用 M2-8）。
//

import Foundation

enum TradingModeGenerators {

    /// 电脑轮和弦块总时值（slot）。
    static func totalSlots(of chords: [TradingChordBlock]) -> Int {
        guard let last = chords.last else { return 0 }
        return last.startSlot + last.durationSlots
    }

    // MARK: - Modify and Rectify

    /// 对用户乐句做一次"镜子变形"（choice 指定），再按 ALL_TONES 整流。
    /// - Parameters:
    ///   - userNotes: 用户乐句（密集 slot 音符）
    ///   - responseChords: 电脑轮和弦块
    ///   - choice: 0=倒影，1=逆行，2=先倒影后逆行，3=原样（生产真随机，对拍注入）
    ///   - toneSet: 由和弦名返回音集合
    static func modifyAndRectify(
        userNotes: [TradingSlotNote],
        responseChords: [TradingChordBlock],
        choice: Int,
        toneSet: (String) -> TradingToneSet
    ) -> [TradingSlotNote] {
        let ordered = userNotes.sorted { $0.startSlot < $1.startSlot }
        var melody = TradingModeBridge.melodyPart(from: ordered)

        switch choice {
        case 0:
            // 倒影
            melody = MotifTransform.inverted(melody)
        case 1:
            // 逆行
            melody = MotifTransform.reversed(melody)
        case 2:
            // 先倒影后逆行（顺序对齐 Java modifySolo case2：invertSolo() → reverseSolo()）
            melody = MotifTransform.inverted(melody)
            melody = MotifTransform.reversed(melody)
        default:
            // 原样（3 或其它）
            break
        }

        let modified = TradingModeBridge.slotNotes(from: melody)
        // 完整 ALL_TONES 整流（rectify → InPlace merge → removeRepeated），
        // 复用已对拍的 repeatAndRectify 回应核心（与 Java rectifySolo + getResponse 同口径）。
        return TradingResponder.respond(
            notes: modified,
            responseChords: responseChords,
            mode: .repeatAndRectify,
            toneSet: toneSet)
    }

    // MARK: - Use Grammar

    /// 不看用户具体音高，只看这 4 小节和声，用内置风格语法生成一句全新乐句。
    /// - Parameters:
    ///   - responseChords: 电脑轮和弦块
    ///   - grammarFile: 语法文件名（默认 "chord"）
    ///   - bpm: 速度
    static func useGrammar(
        responseChords: [TradingChordBlock],
        grammarFile: String,
        bpm: Int = 120
    ) -> [TradingSlotNote] {
        let total = totalSlots(of: responseChords)

        // 底层路径（对齐 Java generateFromGrammar）：
        //   Grammar.run（整曲展开）→ GrammarNoteConverter.convert（音高，rooted）
        //   → TradingResponder 整流（纯 My.voc；绕过 Swift 额外的 smoothLargeLeaps）
        let g = Grammar(grammarFile: grammarFile)
        g.slotsPerBeat = 120
        g.beatsPerMeasure = 4
        g.measureOffset = 0
        g.brickOverflowMode = .keepTruncate

        let cbs = TradingModeBridge.chordBlocks(from: responseChords)
        var cur = 0
        var sched: [(startSlot: Int, block: ChordBlock)] = []
        for (tb, cb) in zip(responseChords, cbs) {
            sched.append((startSlot: cur, block: cb))
            cur += tb.durationSlots
        }
        g.setChordSchedule(sched)

        let terms = g.run(startSlot: 0, numSlots: total)

        ChordQuality.activePalette = .full
        OctavePlacementMode.active = .rooted
        let roadmap = TradingModeBridge.roadmap(from: responseChords, title: "Trading Turn", tempo: bpm)
        let raw = GrammarNoteConverter.convert(
            abstractMelody: terms,
            roadmap: roadmap,
            grammarParameters: g.masterParameters,
            beatsPerMeasure: 4)

        let rawSlotNotes = TradingModeBridge.slotNotes(from: raw)
        return TradingResponder.respond(
            notes: rawSlotNotes,
            responseChords: responseChords,
            mode: .repeatAndRectify,
            toneSet: { TradingChordToneSet.toneSet(chordName: $0) })
    }

    // MARK: - Use Transform

    /// 先把用户乐句压扁成每拍骨干音，再用大师加花规则表装饰，最后按 ALL_TONES 整流。
    /// - Parameters:
    ///   - userNotes: 用户乐句
    ///   - responseChords: 电脑轮和弦块
    ///   - musician: 大师表 id（nil → My 兜底）
    ///   - rngMode: 随机模式（生产真洗牌，对拍固定种子）
    ///   - toneSet: 由和弦名返回音集合
    static func useTransform(
        userNotes: [TradingSlotNote],
        responseChords: [TradingChordBlock],
        musician: String?,
        rngMode: TransformRandomMode,
        toneSet: (String) -> TradingToneSet
    ) -> [TradingSlotNote] {
        let total = totalSlots(of: responseChords)
        let ordered = userNotes.sorted { $0.startSlot < $1.startSlot }

        // STEP 1: flatten（四分分辨率，内部已含 chord-only 整流，concat=false）
        let flattened = TradingFlattener.flattenByResolution(
            notes: ordered,
            chords: responseChords,
            resolution: 120,
            startSlot: 0,
            endSlot: total - 1,
            concatRepeatPitches: false,
            toneSet: toneSet)

        // STEP 2: 转 NCP（chordTimeline 精确边界）
        let timeline = TradingModeBridge.chordTimeline(from: responseChords)
        let ncps = TradingModeBridge.ncps(from: flattened, chordTimeline: timeline)

        // STEP 3: 加花（大师表缺失回退 My）
        let table = TransformMusicianRegistry.tableWithFallback(musician) ?? []
        let transformed = TransformEngine.JavaAlignedTransformEngine.apply(
            to: ncps,
            table: table,
            mode: rngMode,
            chordTimeline: timeline)

        // STEP 4: 回 slotNotes
        let decorated = TradingModeBridge.slotNotes(from: transformed)

        // STEP 5: 完整 ALL_TONES 整流（rectify → InPlace merge → removeRepeated），
        // 复用已对拍的 repeatAndRectify 回应核心（与 Java rectifySolo + getResponse 同口径）。
        return TradingResponder.respond(
            notes: decorated,
            responseChords: responseChords,
            mode: .repeatAndRectify,
            toneSet: toneSet)
    }
}
