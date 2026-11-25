import Foundation

//
//  TradingNoteTagger.swift
//  M2-8 渲染层：给 Trading 一轮（N 小节）的 GeneratedNote 补音乐属性 tag
//  （和弦音 / 色彩音 / 趋近音 / 外音），让用户吹的与电脑回应的音符在五线谱上
//  呈现与其他链路一致的颜色。纯函数、无副作用；只调用 Grammar 的 ChordQuality /
//  getRootPC（复用，不修改 Grammar 任何逻辑）。
//
//  判定规则与 ContentView 渲染层「非 A 终端声学分支」(ContentView:1752-1774) 对齐：
//    1. 和弦音 chordIntervals 命中          → .chordTone（黑，最高优先）
//    2. 色彩音 colorIntervals 命中          → .colorTone（绿）
//    3. 与「下一非休止音」差半音、且下一音在【当前和弦】为 chord/color：
//         自身为 color → .colorTone（色彩优先，绿>蓝）；否则 → .approachNote（蓝）
//    4. 其余                                → .foreignTone（红）
//  休止符保持 .unknown（不渲染符头）。
//
//  范围（v2.1 定稿）：
//  - 小节内位置用 TradingTokens.slots(of:) 从 duration 流累积（与记谱严格互逆，含三连/附点/休止）。
//  - 生效和弦取「最后一个 startSlot ≤ 该音起点」的 chordSlot（与 ContentView:1704-1708 一致）。
//  - 「下一非休止音」只跳过休止符、含 tieEnd（tieEnd 是真音），可跨小节但【不跨轮次】：
//    tagger 一次只处理本轮 N 小节；第 N 小节末指向下一轮的趋近，因下一轮此刻尚未生成，
//    保守不标（电脑轮 Rectify 尾音基本已落目标和弦，影响极小）。
//  - 趋近判色所用和弦与 ContentView:1761 相同，取【当前音】的生效和弦（不跨和弦）；
//    ContentView 注释 1758 已说明这是渲染层现状（Java Rectify 回应算法用下一音位置和弦，属另一条链路）。
//

enum TradingNoteTagger {

    /// 对一轮 N 小节打 tag；palette 默认 .full（与 Rectify usable=spell∪color、ChordToneSet 同源）。
    static func tag(_ bars: [GeneratedMeasure], palette: ColorPaletteMode = .full) -> [GeneratedMeasure] {
        var out = bars

        // 1) 展平本轮全部小节（不跨轮次）：记录小节序号、小节内序号、是否休止、midi、生效和弦。
        struct E { let bar: Int; let idx: Int; let isRest: Bool; let midi: Int; let chord: String }
        var flat: [E] = []
        for (bi, m) in bars.enumerated() {
            var cursor = 0
            for (ni, n) in m.notes.enumerated() {
                let chord = activeChord(for: m, noteStartSlot: cursor)
                let midi: Int = n.isRest ? -1 : Int(TradingTokens.midi(from: n.pitch) ?? 0xFF)
                flat.append(E(bar: bi, idx: ni, isRest: n.isRest, midi: midi, chord: chord))
                cursor += TradingTokens.slots(of: n.duration)
            }
        }

        // 2) 逐音判定（含 tieEnd；休止符不参与）。
        for (fi, e) in flat.enumerated() where !e.isRest && e.midi >= 0 && e.midi < 0x80 {
            let ground = classify(e.midi, e.chord, palette)
            var result = ground
            if ground != .chordTone {
                // 下一非休止音：只跳休止、含 tieEnd（midi≥0），在本轮范围内向后找。
                if let next = flat[(fi + 1)...].first(where: { !$0.isRest && $0.midi >= 0 && $0.midi < 0x80 }),
                   abs(next.midi - e.midi) == 1 {
                    // 对齐 ContentView:1761：用【当前音】的生效和弦判定下一音。
                    let nextTag = classify(next.midi, e.chord, palette)
                    if nextTag == .chordTone || nextTag == .colorTone {
                        result = (ground == .colorTone) ? .colorTone : .approachNote
                    }
                }
            }
            out[e.bar].notes[e.idx].tag = result
        }

        // 3) 重算每个小节的和弦标签 chordAnnotations（M2-8c P0）：
        //    填入真实旋律后，和弦字母必须挂到正确的音符上（复刻 ContentView:1688-1691）。
        //    纯函数 TradingChordSkeleton.reannotate 与上面的小节内 cursor 推进同源。
        return out.map { m in
            GeneratedMeasure(
                chord: m.chord,
                notes: m.notes,
                chordAnnotations: TradingChordSkeleton.reannotate(notes: m.notes,
                                                                  chordSlots: m.chordSlots),
                sectionName: m.sectionName,
                slotsPerMeasure: m.slotsPerMeasure,
                chordSlots: m.chordSlots)
        }
    }

    /// 某小节在 noteStartSlot 处生效的和弦：最后一个 startSlot ≤ noteStartSlot 的 chordSlot；
    /// chordSlots 为空时回退主和弦 chord。
    static func activeChord(for m: GeneratedMeasure, noteStartSlot s: Int) -> String {
        guard !m.chordSlots.isEmpty else { return m.chord }
        var chosen = m.chordSlots[0].chord
        for cs in m.chordSlots {
            if s >= cs.startSlot { chosen = cs.chord } else { break }
        }
        return chosen
    }

    /// 单个音相对某和弦的基础分类（等价 ContentView.detectMusicTheoryTag:4583-4599，
    /// 根音统一用 GrammarNoteConverter.getRootPC，已 headless 对拍 Java）。
    static func classify(_ midi: Int, _ chordName: String, _ palette: ColorPaletteMode) -> MusicTheoryTag {
        guard !chordName.isEmpty, midi >= 0 else { return .chordTone }
        let quality = ChordQuality(chordName: chordName)
        let root = GrammarNoteConverter.getRootPC(chordName)
        let pc = ((midi % 12) + 12) % 12
        let chordPCs = Set(quality.chordIntervals.map { ($0 + root) % 12 })
        if chordPCs.contains(pc) { return .chordTone }
        let colorPCs = Set(quality.colorIntervals(for: chordName, palette: palette).map { ($0 + root) % 12 })
        if colorPCs.contains(pc) { return .colorTone }
        return .foreignTone
    }
}
