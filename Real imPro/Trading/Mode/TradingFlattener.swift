//
//  TradingFlattener.swift
//  Real imPro
//
//  M2-9: Use Transform 前置 —— flattenByResolution
//  1:1 移植 Impro-Visor Java:
//    TransformLearning.flattenByResolution (TransformLearning.java:145)
//      - 按 resolution 分段（闭区间 [slot, slot+resolution-1]）
//      - getNotesInResolution: extract(slot, slot+resolution-1, true, true)
//        （fudgeStart/fudgeEnding：跨段长音在段边界处切开）
//      - getAverageNote: 非休止音高总和 / 非休止音数（整数除法）；
//        时值 = 段内所有音（含休止）时值之和；全休止 → Rest
//      - newMelody = copy；pasteOver(flattenedPart, start)（只覆盖完整段，尾巴保留原音）
//      - RectifyPitchesCommand(chord=true, color=false, approach=false, merge=false)
//      - concatRepeatPitches（默认 false）→ MergeSameNotesCommand
//
//  纯算法（仅 Foundation），不 import AVFoundation / UIKit / SwiftUI，可 headless 对拍。
//

import Foundation

enum TradingFlattener {

    /// 1:1 移植 TransformLearning.flattenByResolution。
    /// - Parameters:
    ///   - notes: 旋律（密集 slot 音符，无需预排序，内部按 startSlot 排序）
    ///   - chords: 和弦块（覆盖整个旋律区间，slot 相对本轮起点）
    ///   - resolution: 分段分辨率（slot，默认 120 = 1 拍）
    ///   - startSlot: flatten 起始 slot
    ///   - endSlot: flatten 结束 slot（闭区间）
    ///   - concatRepeatPitches: 是否合并相邻同音（默认 false，对齐 Use Transform）
    ///   - toneSet: 由和弦名返回音集合（注入，便于 headless 喂 Java 集合 / 生产用 ChordQuality）
    /// - Returns: flatten 后的密集 slot 音符（总时值与输入一致）
    static func flattenByResolution(
        notes: [TradingSlotNote],
        chords: [TradingChordBlock],
        resolution: Int = 120,
        startSlot: Int,
        endSlot: Int,
        concatRepeatPitches: Bool = false,
        toneSet: (String) -> TradingToneSet
    ) -> [TradingSlotNote] {
        precondition(resolution > 0, "resolution 必须为正")
        precondition(endSlot >= startSlot, "endSlot 必须 >= startSlot")

        let ordered = notes.sorted { $0.startSlot < $1.startSlot }

        // ── 1. 分段 → 平均音（flattenedPart 从空开始，连续追加）──
        var flattened: [TradingSlotNote] = []
        var cursor = startSlot
        // 完整段条件：segStart + resolution - 1 <= endSlot
        for segStart in stride(from: startSlot, through: endSlot - resolution + 1, by: resolution) {
            let segEnd = segStart + resolution - 1
            let segNotes = notesInResolution(notes: ordered, segStart: segStart, segEnd: segEnd)
            let avg = averageNote(segNotes: segNotes, startSlot: cursor)
            flattened.append(avg)
            cursor += avg.durationSlots
        }

        let flattenedTotal = flattened.reduce(0) { $0 + $1.durationSlots }
        // 不变量：每个完整段总时值 = resolution，故 flattened 总时长 = 段数 * resolution
        assert(flattenedTotal == flattened.count * resolution,
               "flatten 段总时值不守恒：\(flattenedTotal) vs \(flattened.count * resolution)")

        // ── 2. newMelody = copy；pasteOver 从 startSlot 覆盖完整段区间（尾巴保留原音）──
        var newMelody = pasteOver(
            base: ordered,
            replacement: flattened,
            replaceStart: startSlot,
            replacementTotal: flattenedTotal
        )

        // ── 3. chord-only rectify [startSlot, endSlot]（spell-only，无 color/approach，不 merge）──
        rectifyChordOnly(
            notes: &newMelody,
            chords: chords,
            startSlot: startSlot,
            endSlot: endSlot,
            toneSet: toneSet
        )

        // ── 4. concat（默认 false）：区间内合并相邻同音（含相邻休止）──
        if concatRepeatPitches {
            newMelody = mergeSameNotes(notes: newMelody,
                                       startSlot: startSlot,
                                       endSlot: endSlot)
        }

        // 不变量：输出总时值与输入一致（若输入铺满 [startSlot,endSlot]）
        let inputTotal = ordered.reduce(0) { $0 + $1.durationSlots }
        let outputTotal = newMelody.reduce(0) { $0 + $1.durationSlots }
        assert(inputTotal == outputTotal,
               "flatten 前后总时值不守恒：\(inputTotal) vs \(outputTotal)")

        return newMelody
    }
}

// MARK: - 段内取音（extract 闭区间，含跨段长音切分）

private extension TradingFlattener {

    /// 移植 getNotesInResolution：取旋律覆盖 [segStart, segEnd]（闭区间）的所有音，
    /// 跨段长音在段边界处切开（音头在段前、延音跨进段内的从段首截取；
    /// 音头在段内、延音超出段尾的截断到段尾）。
    /// - Returns: 段内音（pitch / 段内时值 / isRest），按 slot 顺序
    static func notesInResolution(
        notes: [TradingSlotNote],
        segStart: Int,
        segEnd: Int
    ) -> [(pitch: Int, dur: Int, isRest: Bool)] {
        var out: [(pitch: Int, dur: Int, isRest: Bool)] = []
        for n in notes {
            let nEnd = n.startSlot + n.durationSlots - 1
            let oStart = max(n.startSlot, segStart)
            let oEnd = min(nEnd, segEnd)
            if oStart <= oEnd {
                out.append((n.pitch, oEnd - oStart + 1, n.isRest))
            }
        }
        // notes 已按 startSlot 排序，遍历顺序即 slot 顺序；段首跨段音 startSlot 最小，排在最前。
        return out
    }

    /// 移植 getAverageNote：非休止音高总和 / 非休止音数（整数除法向下取整）；
    /// 时值 = 段内所有音（含休止）时值之和；全休止 → Rest。
    /// 注：段和弦在本步骤不使用（Java 中已注释，整流统一在更高层 Rectify 完成）。
    static func averageNote(
        segNotes: [(pitch: Int, dur: Int, isRest: Bool)],
        startSlot: Int
    ) -> TradingSlotNote {
        var totalPitch = 0
        var totalDuration = 0
        var totalNotes = 0
        for sn in segNotes {
            if !sn.isRest {
                totalPitch += sn.pitch
                totalNotes += 1
            }
            totalDuration += sn.dur
        }
        if totalNotes != 0 {
            let averagePitch = totalPitch / totalNotes  // Java 整数除法（向零取整）
            return TradingSlotNote(pitch: averagePitch, startSlot: startSlot,
                                   durationSlots: totalDuration, isRest: false)
        } else {
            return TradingSlotNote(pitch: -1, startSlot: startSlot,
                                   durationSlots: totalDuration, isRest: true)
        }
    }
}

// MARK: - pasteOver（区间替换，尾巴保留）

private extension TradingFlattener {

    /// 移植 Part.pasteOver（Part.java:1543）：稀疏 slot 级，replacement 完全占据
    /// [replaceStart, replaceStart+replacementTotal) 区间（含休止替换）；区间外保留原音。
    /// 音头在区间内、延音超出区间尾的音整体被替换（不在区间后"复活"）；
    /// 音头在区间前、延音跨进区间的音保留其前段（截到 replaceStart-1）。
    static func pasteOver(
        base: [TradingSlotNote],
        replacement: [TradingSlotNote],
        replaceStart: Int,
        replacementTotal: Int
    ) -> [TradingSlotNote] {
        let replaceEnd = replaceStart + replacementTotal - 1
        var before: [TradingSlotNote] = []
        var after: [TradingSlotNote] = []

        for n in base {
            let nEnd = n.startSlot + n.durationSlots - 1
            if nEnd < replaceStart {
                // 完整在区间前
                before.append(n)
            } else if n.startSlot > replaceEnd {
                // 完整在区间后（音头在区间后）
                after.append(n)
            } else if n.startSlot < replaceStart {
                // 跨前边界：保留前段 [startSlot, replaceStart-1]
                before.append(TradingSlotNote(
                    pitch: n.pitch,
                    startSlot: n.startSlot,
                    durationSlots: replaceStart - n.startSlot,
                    isRest: n.isRest
                ))
            }
            // 音头在区间 [replaceStart, replaceEnd] 内的音全部丢弃（被 replacement 替换）
        }

        var result = before
        result += replacement
        result += after
        result.sort { $0.startSlot < $1.startSlot }
        return result
    }
}

// MARK: - chord-only Rectify（RectifyPitchesCommand 单 chord 开关）

private extension TradingFlattener {

    /// 移植 RectifyPitchesCommand（chord=true, color=false, approach=false, merge=false）：
    /// 区间内，不在当前和弦 spell（和弦音）的音一律就近移动到最近和弦音（平局向上）；
    /// 不检查/保留色彩音、不检查趋近音、不合并；NOCHORD 原样保留。
    static func rectifyChordOnly(
        notes: inout [TradingSlotNote],
        chords: [TradingChordBlock],
        startSlot: Int,
        endSlot: Int,
        toneSet: (String) -> TradingToneSet
    ) {
        let blockTones: [TradingToneSet?] = chords.map { $0.isNoChord ? nil : toneSet($0.name) }

        for i in notes.indices {
            var cur = notes[i]
            if cur.isRest { continue }
            if cur.startSlot < startSlot || cur.startSlot > endSlot { continue }

            guard let bi = blockIndex(forSlot: cur.startSlot, in: chords) else { continue }
            guard let set = blockTones[bi] else { continue }  // NOCHORD：原样保留

            // 目标集合 = spell（和弦音），不含 color
            if set.spellPC.contains(pitchClass(cur.pitch)) {
                continue
            }
            // approachTones=false：无趋近分支，直接就近移动到 spell
            cur.pitch = closestPitch(originalPitch: cur.pitch, targetPC: set.spellPC)
            notes[i] = cur
        }
    }

    static func pitchClass(_ midi: Int) -> Int {
        let r = midi % 12
        return r < 0 ? r + 12 : r
    }

    /// 找包含 slot 的和弦块下标（最后一个 startSlot <= slot 的块）。
    static func blockIndex(forSlot slot: Int, in blocks: [TradingChordBlock]) -> Int? {
        var found: Int? = nil
        for (i, b) in blocks.enumerated() {
            if b.startSlot <= slot {
                found = i
            } else {
                break
            }
        }
        return found
    }

    /// 移植 Note.getClosestMatch：按 +1,-1,+2,-2... 累积搜索，等距时上方优先。
    static func closestPitch(originalPitch: Int, targetPC: Set<Int>) -> Int {
        var pitch = originalPitch
        var step = 0
        while !targetPC.contains(pitchClass(pitch)) {
            step += 1
            if step % 2 == 0 {
                pitch -= step
            } else {
                pitch += step
            }
        }
        return pitch
    }
}

// MARK: - MergeSameNotes（concat 分支）

private extension TradingFlattener {

    /// 移植 MergeSameNotesCommand（MergeSameNotesCommand.java:113）：区间内合并相邻同音
    /// （Java REST=-1，故相邻实音同音合并、相邻休止合并、音↔休止不合并）。
    /// 密集表示下与 removeRepeatedNotes 语义一致（合并后保留一个音、时值累加）。
    static func mergeSameNotes(
        notes: [TradingSlotNote],
        startSlot: Int,
        endSlot: Int
    ) -> [TradingSlotNote] {
        let inRange = notes.filter { $0.startSlot >= startSlot && $0.startSlot <= endSlot }
        let before = notes.filter { $0.startSlot < startSlot }
        let after = notes.filter { $0.startSlot > endSlot }

        var merged: [TradingSlotNote] = []
        for cur in inRange {
            if let last = merged.last,
               last.isRest == cur.isRest && last.pitch == cur.pitch {
                merged[merged.count - 1].durationSlots += cur.durationSlots
            } else {
                merged.append(cur)
            }
        }

        var result = before
        result += merged
        result += after
        result.sort { $0.startSlot < $1.startSlot }
        return result
    }
}
