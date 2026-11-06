// =====================================================================
// MelodyTransformAdapter.swift
// ③ 内置 Classic Jazz【原曲旋律】加花适配层（M3，20260915）。
//
// 定位：Transform 通用内核的【第三个输入源】。前两个：
//   - guide  PhysicalNote 引导音线 → GuideTransformBridge
//   - grammar 具体音终端     → GrammarStrategy 的 .grammarWithTransform
//   本文件把【内置原曲旋律 [GeneratedMeasure]】接进【同一套】Java 对齐内核
//   （TransformEngine.JavaAlignedTransformEngine），不重写任何替换算法。
//
// 流水线（严格对齐 Java：已有旋律 = TransformFrame.applySubstitutionsToPart(MelodyPart,ChordPart)）：
//   GeneratedNote 旋律
//     → 时值字母换算 slot（四分=120，附点×1.5，三连×2/3；休止 midi=-1）+ 音名 "C/4"→midi
//     → LightPostProcessor.mergeTies（复用现有 Part.mergeTies 等价：相邻同音合、休止断链，
//        同时消化 isTieStart/isTieEnd 延音线为真实音长）
//     → PhysicalNote.batchToNCP（全局绝对 startSlot）
//     → JavaAlignedTransformEngine.apply（传入 M2/F26 精确 chordTimeline，换和弦处无音头也挂对）
//     → 整流 rectcolor = rectifyGuideSpellOnly(colorMode:.full)：
//        无时长闸 + G1 My.voc spell+color + 等距优先向上吸附 + 相邻非休止同音合并。
//        【不用】grammar 的 rectifyAllBeats（其正拍30/反拍60 时长闸是 grammar 产品偏离，
//        会在旋律长音上误吸附；Java RectifyPitchesCommand 趋近豁免无闸，已坐实）。
//     → （出端）按原小节预算切回 [GeneratedMeasure]，供未来 UI/渲染复用。
//
// 纪律（本轮）：
//   - 总开关 enableMelodyTransform 默认【false】，且本文件【无任何生产调用方】→ 当前生产不可达；
//     ContentView 选内置曲直接铺原旋律的旧路径（onChange(of: selectedSong) → builtinLibrary.melody）
//     一行未动。未来接线、默认乐手、是否默认开、UI 入口均另行单独立项报批。
//   - 不做任何自研听感增强（不做"只在长音加花/全局时长门/限跳/平滑"）：引擎对每音试，
//     长短完全由各乐手规则自带的 duration>= 门决定（= 原版行为）；听感靠换乐手。
//   - 旋律音域用其自身（整流按每个音就近吸附），不套 guide 的 [60,79]。
//   - 3/4 华尔兹（每小节 360 slot）为第二批，本文件按传入小节预算处理、未专门对拍。
// =====================================================================

import Foundation

enum MelodyTransformAdapter {

    /// 总开关（内部总闸）：
    // [方案21 封存 20260915] "Melody 第4组/在原旋律上加花"已下线（恢复 Guide/Basic/Master 三组从和声生成
    // + 五线谱 Original⇄Solo 对照）。本文件加花入口（embellish/embellishPhysical/originalPhysical/
    // prepareMergedPhysical/rebuildMeasures）保留不删、生产无任何调用方，且本总闸=false 使 embellishPhysical
    // 恒返 nil；audit 探针可临时置 true 继续对拍。仅保留时值/音名工具与 transposeMeasures（R3 增强）供 Original 转调。
    static var enableMelodyTransform = false

    // MARK: - 时值字母 → slot（四分=120，绝对基准，与拍号无关）

    /// 字母时值（w/hr/h/hd/q/qd/qr/8/8d/8r/16/32…，r=休止后缀、d=附点）→ 基础 slot；
    /// 三连音再 ×2/3。与对拍探针 melody_to_scenario 完全同一口径。
    static func tokenSlots(_ token: String, isTriplet: Bool) -> Int {
        var t = token
        if t.hasSuffix("r") { t = String(t.dropLast()) }      // 休止后缀（isRest 已给，时值相同）
        var dotted = false
        if t.hasSuffix("d") { dotted = true; t = String(t.dropLast()) }
        var base: Int
        switch t {
        case "w":  base = 480
        case "h":  base = 240
        case "q":  base = 120
        case "8":  base = 60
        case "16": base = 30
        case "32": base = 15
        default:   base = 120                                // 防御：未知按四分
        }
        if dotted { base = base * 3 / 2 }
        return isTriplet ? base * 2 / 3 : base
    }

    /// slot → 字母时值（出端还原用）；isTriplet 由 PhysicalNote.tuplet 判定。
    private static func slotToken(_ slots: Int, tuplet: Int) -> (token: String, triplet: Bool) {
        let triplet = (tuplet == 3)
        let base = triplet ? slots * 3 / 2 : slots
        let map: [Int: String] = [480:"w", 360:"hd", 240:"h", 180:"qd", 120:"q",
                                  90:"8d", 60:"8", 45:"16d", 30:"16", 15:"32"]
        return (map[base] ?? "q", triplet)
    }

    // MARK: - 音名 "C/4" → MIDI（与 ContentView.midiNumber 同语义，独立小解析避免跨层依赖 View）

    static func midiNumber(from pitch: String) -> Int? {
        let parts = pitch.split(separator: "/")
        guard parts.count == 2 else { return nil }
        let name = String(parts[0]).lowercased()
        let octave = Int(parts[1]) ?? 4
        let noteMap: [String: Int] = [
            "c":0,"c#":1,"db":1,"d":2,"d#":3,"eb":3,"e":4,
            "f":5,"f#":6,"gb":6,"g":7,"g#":8,"ab":8,"a":9,"a#":10,"bb":10,"b":11
        ]
        guard let pc = noteMap[name] else { return nil }
        return (octave + 1) * 12 + pc
    }

    /// MIDI → "名/八度"（出端；黑键默认用升号，与内置库常见写法一致）。
    /// 等价于 preferSharps:true 的一行委托（保留旧签名，既有调用拼写不变）。
    private static func pitchName(from midi: Int) -> String {
        pitchName(from: midi, preferSharps: true)
    }

    /// MIDI → "名/八度"，按目标调选择升/降拼写（方案19 转调跟随：转调到降号调时五线谱拼写正确）。
    static func pitchName(from midi: Int, preferSharps: Bool) -> String {
        let sharp = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        let flat  = ["C","Db","D","Eb","E","F","Gb","G","Ab","A","Bb","B"]
        let names = preferSharps ? sharp : flat
        let pc = ((midi % 12) + 12) % 12
        let octave = midi / 12 - 1
        return "\(names[pc])/\(octave)"
    }

    /// 和弦符号归一：Java 不认 ø/Ø 半减（返回 null 会整体错位），统一 m7b5；Swift 两侧同族。
    private static func normalizeChord(_ s: String) -> String {
        s.replacingOccurrences(of: "ø7", with: "m7b5")
         .replacingOccurrences(of: "Ø7", with: "m7b5")
    }

    // MARK: - 原旋律物理化（圆点关：只 flatten + mergeTies，不进引擎、不整流）
    // [方案21 封存] 原旋律加花线下线，本函数无生产调用方；保留供未来立项与 audit 对拍，勿在生产接线。

    /// 把内置原旋律展平为全局 PhysicalNote 并 mergeTies（消化 isTieStart/End 与相邻同音/休止断链）。
    /// 不做任何加花/整流，供 ContentView worker 在 TRANSFORM 圆点关时复用【同一套】Phase2/Phase3 排版，
    /// 保证原旋律与加花结果的 tie/triplet/符头渲染完全同源。（方案19 M-1，新增）
    static func originalPhysical(_ measures: [GeneratedMeasure], slotsPerBeat: Int = 120) -> [PhysicalNote] {
        _ = slotsPerBeat  // 与 embellishPhysical 对齐签名；时值换算只依赖四分=120 常量
        return prepareMergedPhysical(measures)
    }

    /// 步骤1（embellishPhysical 与 originalPhysical 共用，纯抽取、行为不变）：
    /// 展平原旋律 → PhysicalNote（休止 -1）→ mergeTies 合延音线/相邻同音（休止断链）。
    // [方案21 封存] 随原旋律加花线一并封存（无生产调用方）；transposeMeasures 不依赖它。
    private static func prepareMergedPhysical(_ measures: [GeneratedMeasure]) -> [PhysicalNote] {
        var raw: [PhysicalNote] = []
        for m in measures {
            for gn in m.notes {
                let dur = tokenSlots(gn.duration, isTriplet: gn.isTriplet)
                let midi: Int
                if gn.isRest { midi = -1 }
                else { midi = midiNumber(from: gn.pitch) ?? -1 }  // 解析不出按休止防御（不应发生）
                raw.append(PhysicalNote(midiPitch: midi, durationSlots: dur))
            }
        }
        return LightPostProcessor.mergeTies(raw)
    }

    // MARK: - 主入口（出 PhysicalNote，全局绝对 slot）
    // [方案21 封存] 原旋律加花主入口，生产无调用方且 enableMelodyTransform=false 恒返 nil；保留供 audit 对拍。

    /// 对一条内置原曲旋律施加选定乐手的变换加花。
    /// - 总开关关闭时返回 nil（调用方应据此走"原样铺旋律"旧路径）。
    /// - Parameters:
    ///   - measures: 内置库原始小节（音名 + 时值字母 + tie 标记）
    ///   - chordBlocks: 与该旋律同一 roadmap 的和弦块（duration 单位=拍）
    ///   - musician: 乐手表 id（TransformTables/<id>.tsv），缺省回退 My
    ///   - mode: 生产 .randomized(SystemTransformRNG()) 真洗牌；对拍可 .deterministic / 注种子
    ///   - rectifyColorMode: [方案19] 整流三态。.off=spell-only（产品默认，对齐 Java 出厂 colorBox 不勾）；
    ///       .conservative=spell+自然9/11/13；.full=spell+全 color（=Java colorBox 勾选，30 例金标准档）。
    ///       默认 .full 仅为保持 M3 探针既有调用逐字不变；ContentView 接线按 Color 圆点显式传 .off/.conservative/.full。
    ///   - onTableMiss: G1 整流词表未命中回调（统计用，可空）
    static func embellishPhysical(_ measures: [GeneratedMeasure],
                                  chordBlocks: [ChordBlock],
                                  musician: String = TransformMusicianRegistry.defaultMusician,
                                  mode: TransformRandomMode = .randomized(SystemTransformRNG()),
                                  slotsPerBeat: Int = 120,
                                  rectifyColorMode: GuideRectifyColorMode = .full,
                                  onTableMiss: ((String) -> Void)? = nil) -> [PhysicalNote]? {
        guard enableMelodyTransform else { return nil }
        guard !measures.isEmpty, !chordBlocks.isEmpty else { return nil }

        // 归一后的和弦块（引擎 + 整流 + 精确时间线都用它）
        let normBlocks = chordBlocks.map { ChordBlock(name: normalizeChord($0.name), duration: $0.duration) }

        // 1) 展平原旋律 → PhysicalNote（休止 -1），再 mergeTies 合延音线/相邻同音（休止断链）
        let merged = prepareMergedPhysical(measures)

        // 2) 精确和弦时间线（M2/F26）：按和弦时值累加起始 slot，换和弦处无音头也挂对
        var timeline: [(start: Int, chord: ChordBlock)] = []
        var cAccum = 0
        for cb in normBlocks {
            timeline.append((cAccum, cb))
            cAccum += Int(Double(cb.duration) * Double(slotsPerBeat))
        }

        // 3) PhysicalNote → NCP（全局绝对时间轴，内部同样按 chordBlocks 算 chordStartSlots）
        let ncps = PhysicalNote.batchToNCP(guideToneLine: merged,
                                           chordBlocks: normBlocks,
                                           slotsPerBeat: slotsPerBeat)

        // 4) 同一套 Java 对齐内核（与 guide/grammar 共用），显式传精确 chordTimeline
        let table = TransformMusicianRegistry.tableWithFallback(musician) ?? []
        let transformed = TransformEngine.JavaAlignedTransformEngine.apply(
            to: ncps, table: table, mode: mode, chordTimeline: timeline)
        let phys = transformed.map {
            PhysicalNote(midiPitch: $0.note.midiPitch,
                         durationSlots: $0.note.durationSlots,
                         tuplet: $0.note.tuplet,
                         terminalType: $0.note.terminalType)
        }

        // 5) rectcolor：guide 整流（无时长闸 + G1 spell/color + 等距向上 + 相邻同音合并）；
        //    色彩档位由 rectifyColorMode 决定（.off spell-only / .conservative / .full）。
        return LightPostProcessor.rectifyGuideSpellOnly(
            phys, chordBlocks: normBlocks, slotsPerBeat: slotsPerBeat,
            colorMode: rectifyColorMode, onTableMiss: onTableMiss)
    }

    // MARK: - 出端：PhysicalNote → 重建 [GeneratedMeasure]（未来 UI/渲染复用；本轮无调用方）
    // [方案21 封存] 随原旋律加花线封存（无生产调用方）。

    /// 按【原小节 slot 预算】把全局加花结果切回小节；和弦/段落等元数据沿用模板小节。
    /// 注：跨小节长音的 tieStart/tieEnd 切分属渲染细节，留待 UI 接线时与五线谱渲染一并处理（登记项）。
    static func rebuildMeasures(from notes: [PhysicalNote],
                                template measures: [GeneratedMeasure]) -> [GeneratedMeasure] {
        // 每小节 slot 预算（由原始字母时值累加；4/4=480、2/2 亦=480、3/4=360）
        var cumEnd = [Int]()
        var acc = 0
        for m in measures {
            var ms = 0
            for gn in m.notes { ms += tokenSlots(gn.duration, isTriplet: gn.isTriplet) }
            acc += ms
            cumEnd.append(acc)
        }
        var buckets: [[PhysicalNote]] = Array(repeating: [], count: measures.count)
        var mi = 0
        var cursor = 0
        for n in notes {
            while mi < measures.count - 1 && cursor >= cumEnd[mi] { mi += 1 }
            buckets[mi].append(n)
            cursor += n.durationSlots
        }
        return zip(measures, buckets).map { tmpl, mNotes in
            let gNotes: [GeneratedNote] = mNotes.map { pn in
                if pn.isRest {
                    return GeneratedNote(pitch: "C/4", tag: .unknown, isRest: true,
                                         duration: "q", isTriplet: false)
                }
                let tk = slotToken(pn.durationSlots, tuplet: pn.tuplet)
                return GeneratedNote(pitch: pitchName(from: pn.midiPitch), tag: .unknown,
                                     isRest: false, duration: tk.token, isTriplet: tk.triplet)
            }
            return GeneratedMeasure(chord: tmpl.chord, notes: gNotes,
                                    chordAnnotations: tmpl.chordAnnotations,
                                    sectionName: tmpl.sectionName,
                                    slotsPerMeasure: tmpl.slotsPerMeasure,
                                    chordSlots: tmpl.chordSlots)
        }
    }

    /// 一站式：原曲小节 → 加花后小节（总开关关时返回 nil）。未来 ContentView 新路径调用它；
    /// 当前【无调用方】，旧的"直接铺原旋律"路径不受影响。
    // [方案21 封存] 一站式加花入口，生产无调用方；保留供未来立项与 audit 对拍。
    static func embellish(_ measures: [GeneratedMeasure],
                          chordBlocks: [ChordBlock],
                          musician: String = TransformMusicianRegistry.defaultMusician,
                          mode: TransformRandomMode = .randomized(SystemTransformRNG()),
                          slotsPerBeat: Int = 120,
                          rectifyColorMode: GuideRectifyColorMode = .full,
                          onTableMiss: ((String) -> Void)? = nil) -> [GeneratedMeasure]? {
        guard let phys = embellishPhysical(measures, chordBlocks: chordBlocks, musician: musician,
                                           mode: mode, slotsPerBeat: slotsPerBeat,
                                           rectifyColorMode: rectifyColorMode, onTableMiss: onTableMiss)
        else { return nil }
        return rebuildMeasures(from: phys, template: measures)
    }

    // MARK: - 原旋律整体半音转调（方案21 R3：音符 + 三类和弦载体同步转）

    /// 把【原旋律】小节整体平移 semitones 个半音：休止/时值/tie/triplet 原样保留，改音高拼写（含 graceNotes）；
    /// 【方案21 R3】同时把每小节 chord / chordAnnotations / chordSlots 的【根音】一并转，后缀与 noteIndex/startSlot
    /// 不变，修掉报告20"看原旋律转调后新调旋律+旧调和弦名/伴奏"的缺陷。semitones==0 原样返回，黑键拼写按 preferSharps。
    static func transposeMeasures(_ measures: [GeneratedMeasure], by semitones: Int,
                                  preferSharps: Bool) -> [GeneratedMeasure] {
        guard semitones != 0 else { return measures }
        func shiftPitch(_ p: String) -> String? {
            guard let m = midiNumber(from: p) else { return nil }
            return pitchName(from: m + semitones, preferSharps: preferSharps)
        }
        func shiftChord(_ c: String) -> String {
            transposeChordName(c, by: semitones, preferSharps: preferSharps)
        }
        return measures.map { mm in
            // GeneratedNote.pitch 为 let，整体重建（保留 tag/时值/tie/三连/倚音全部字段）
            let notes = mm.notes.map { note -> GeneratedNote in
                guard !note.isRest, let np = shiftPitch(note.pitch) else { return note }
                let shiftedGraces = note.graceNotes.map { gn -> GeneratedGraceNote in
                    guard !gn.isRest, let gp = shiftPitch(gn.pitch) else { return gn }
                    var g = gn; g.pitch = gp; return g   // GeneratedGraceNote.pitch 为 var
                }
                return GeneratedNote(pitch: np, tag: note.tag, isRest: note.isRest,
                                     duration: note.duration, isTriplet: note.isTriplet,
                                     isTieStart: note.isTieStart, isTieEnd: note.isTieEnd,
                                     graceNotes: shiftedGraces)
            }
            // R3：chord/chordAnnotations 为 let、chordSlots 为 var，整体重建 GeneratedMeasure；根音转、后缀/位置不变
            let anns = mm.chordAnnotations.map { (chord: shiftChord($0.chord), noteIndex: $0.noteIndex) }
            let slots = mm.chordSlots.map { (chord: shiftChord($0.chord), startSlot: $0.startSlot) }
            return GeneratedMeasure(chord: shiftChord(mm.chord), notes: notes,
                                    chordAnnotations: anns, sectionName: mm.sectionName,
                                    slotsPerMeasure: mm.slotsPerMeasure, chordSlots: slots)
        }
    }

    /// [方案21 R3] 自包含和弦根音转调（语义逐字对齐 ContentView.splitChord/transposeRoot，避免反向依赖 View）：
    /// 解析 1-2 字符根音（含 #/b）→ +semitones → 按 preferSharps 选升降拼写，后缀原样接回；
    /// 解析不出根音（NC/N.C. 等）原样返回；斜杠低音 C/E 只转主根音（与 ContentView.transposeChord 同既有口径）。
    private static func transposeChordName(_ chord: String, by semitones: Int, preferSharps: Bool) -> String {
        let t = chord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return chord }
        var rootEnd = t.index(after: t.startIndex)
        if t.count > 1 {
            let second = t[t.index(after: t.startIndex)]
            if second == "#" || second == "b" { rootEnd = t.index(t.startIndex, offsetBy: 2) }
        }
        let root = String(t[..<rootEnd])
        let suffix = String(t[rootEnd...])
        let rootMap: [String: Int] = ["C":0,"C#":1,"Db":1,"D":2,"D#":3,"Eb":3,"E":4,"F":5,
                                      "F#":6,"Gb":6,"G":7,"G#":8,"Ab":8,"A":9,"A#":10,"Bb":10,"B":11]
        guard let pc = rootMap[root] else { return chord }   // NC 等非和弦根音：原样
        let newPC = (pc + semitones + 12) % 12
        let sharpNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        let flatNames  = ["C","Db","D","Eb","E","F","Gb","G","Ab","A","Bb","B"]
        return (preferSharps ? sharpNames[newPC] : flatNames[newPC]) + suffix
    }
}
