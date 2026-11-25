//
//  TradingResponder.swift
//  Real imPro
//
//  M2-7: Trading 电脑回应（纯算法，仅 Foundation）。
//  1:1 复刻 Impro-Visor Java:
//    Repeat            -> RepeatTRM  (getResponse: removeRepeatedNotes)
//    RepeatAndRectify  -> RepeatAndRectifyTRM
//                         rectifySolo(ALL_TONES) [RectifyPitchesCommand + removeRepeatedNotesInPlace]
//                         getResponse [removeRepeatedNotes]
//
//  本文件不 import AVFoundation / UIKit / SwiftUI，可单文件 swiftc headless 对拍。
//

import Foundation

// MARK: - 对外类型

/// Trading 回应模式（M2-9：新增 Modify / Use Grammar / Use Transform）
enum TradingResponseMode {
    case repeatMode
    case repeatAndRectify
    case modifyAndRectify
    case useGrammar
    case useTransform
}

/// 一个音符 / 休止（slot 级，与 Java MelodyPart 同构）
/// pitch 为 MIDI；休止 pitch 沿用 Java REST(-1)，并以 isRest 显式标记。
struct TradingSlotNote: Equatable {
    var pitch: Int
    var startSlot: Int
    var durationSlots: Int
    var isRest: Bool

    init(pitch: Int, startSlot: Int, durationSlots: Int, isRest: Bool) {
        self.pitch = pitch
        self.startSlot = startSlot
        self.durationSlots = durationSlots
        self.isRest = isRest
    }
}

/// 电脑轮一个和弦块（startSlot 相对电脑轮起点，持续到下一和弦）
struct TradingChordBlock {
    var name: String
    var startSlot: Int
    var durationSlots: Int

    init(name: String, startSlot: Int, durationSlots: Int) {
        self.name = name
        self.startSlot = startSlot
        self.durationSlots = durationSlots
    }

    /// Java Chord.isNOCHORD：无和弦段落（名字为空或 "N"）。
    var isNoChord: Bool {
        let t = name.trimmingCharacters(in: .whitespaces)
        return t.isEmpty || t == "N"
    }
}

/// 一个和弦的可用音集合（pitch class, 0-11）
/// usable = spell（和弦音） ∪ color（色彩音），对应 Java ALL_TONES。
struct TradingToneSet: Equatable {
    var rootPC: Int
    var spellPC: Set<Int>
    var colorPC: Set<Int>
    var usablePC: Set<Int>

    init(rootPC: Int, spellPC: Set<Int>, colorPC: Set<Int>) {
        self.rootPC = rootPC
        self.spellPC = spellPC
        self.colorPC = colorPC
        self.usablePC = spellPC.union(colorPC)
    }
}

// MARK: - 入口

/// 一轮电脑回应的额外参数（新模式用；默认值对齐生产，旧模式不读）。
struct TradingTurnContext {
    var grammarFile: String = "chord"        // Use Grammar 语法文件
    var modifyChoice: Int? = nil             // Modify 分支：nil=生产真随机，对拍注入 0/1/2/3
    var transformMusician: String? = nil     // Use Transform 大师表：nil→My 兜底
    var bpm: Int = 120
}

enum TradingResponder {

    /// 生成电脑回应。
    /// - Parameters:
    ///   - notes: 用户乐句（slot 级，无需预先排序）
    ///   - responseChords: 电脑轮和弦块（覆盖整个回应长度）
    ///   - mode: 回应模式
    ///   - toneSet: 由和弦名返回其音集合（注入，便于 headless 喂 Java 集合 / 生产用 ChordQuality）
    /// - Returns: 电脑回应 slot 乐句
    static func respond(
        notes: [TradingSlotNote],
        responseChords: [TradingChordBlock],
        mode: TradingResponseMode,
        toneSet: (String) -> TradingToneSet,
        context: TradingTurnContext = TradingTurnContext()
    ) -> [TradingSlotNote] {
        let ordered = notes.sorted { $0.startSlot < $1.startSlot }

        switch mode {
        case .repeatMode:
            // Repeat: 仅 getResponse（合并同音 + 休止），不看和弦。
            return removeRepeatedNotes(ordered)

        case .repeatAndRectify:
            // STEP 4: RectifyPitchesCommand（逐音修正，末尾 InPlace 合并同音）
            var work = ordered
            rectify(notes: &work, responseChords: responseChords, toneSet: toneSet)
            work = removeRepeatedNotesInPlace(work)
            // STEP 5: getResponse（副本版，再合并同音 + 休止）
            return removeRepeatedNotes(work)

        case .modifyAndRectify:
            // 生产真随机（0...3），对拍由 context.modifyChoice 注入
            let choice = context.modifyChoice ?? Int.random(in: 0...3)
            return TradingModeGenerators.modifyAndRectify(
                userNotes: ordered, responseChords: responseChords,
                choice: choice, toneSet: toneSet)

        case .useGrammar:
            return TradingModeGenerators.useGrammar(
                responseChords: responseChords,
                grammarFile: context.grammarFile, bpm: context.bpm)

        case .useTransform:
            return TradingModeGenerators.useTransform(
                userNotes: ordered, responseChords: responseChords,
                musician: context.transformMusician,
                rngMode: .randomized(SystemTransformRNG()),
                toneSet: toneSet)
        }
    }
}

// MARK: - Rectify（RectifyPitchesCommand）

extension TradingResponder {

    private static func pitchClass(_ midi: Int) -> Int {
        let r = midi % 12
        return r < 0 ? r + 12 : r
    }

    /// 找包含 slot 的和弦块下标（最后一个 startSlot <= slot 的块）。
    private static func blockIndex(forSlot slot: Int, in blocks: [TradingChordBlock]) -> Int? {
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

    private static func rectify(
        notes: inout [TradingSlotNote],
        responseChords: [TradingChordBlock],
        toneSet: (String) -> TradingToneSet
    ) {
        // 预计算每个和弦块的音集合（NOCHORD 记为 nil）
        let blockTones: [TradingToneSet?] = responseChords.map { block in
            block.isNoChord ? nil : toneSet(block.name)
        }

        func tones(at slot: Int) -> (block: TradingChordBlock, set: TradingToneSet?)? {
            guard let idx = blockIndex(forSlot: slot, in: responseChords) else { return nil }
            return (responseChords[idx], blockTones[idx])
        }

        for i in notes.indices {
            var current = notes[i]
            if current.isRest { continue }

            guard let here = tones(at: current.startSlot) else { continue }
            // NOCHORD：原样保留
            guard let currentSet = here.set else { continue }

            // 下一 Unit（含休止）—— 对应 Java getNextIndex / getNextNote
            let nextPos = i + 1
            let nextNote: TradingSlotNote? = nextPos < notes.count ? notes[nextPos] : nil
            var nextSet: TradingToneSet?
            if let nn = nextNote, let entry = tones(at: nn.startSlot) {
                nextSet = entry.set
            }

            let pc = pitchClass(current.pitch)

            // 分支 1：当前音已在 usable（和弦音 / 色彩音），不动。
            if currentSet.usablePC.contains(pc) {
                continue
            }

            // 分支 2：半音趋近音 —— 下一音非休止、与当前音差 1 半音、且下一音在下一和弦集合中。
            if let nn = nextNote, !nn.isRest, let nset = nextSet,
               adjacentPitch(nn.pitch, current.pitch),
               nset.usablePC.contains(pitchClass(nn.pitch)) {
                continue
            }

            // 分支 3：就近移动（平局向上）。
            current.pitch = closestPitch(originalPitch: current.pitch, usablePC: currentSet.usablePC)
            notes[i] = current
        }
    }

    /// Java Note.adjacentPitch：绝对音高恰好差 1。
    private static func adjacentPitch(_ a: Int, _ b: Int) -> Bool {
        return a == b + 1 || a == b - 1
    }

    /// Java Note.getClosestMatch：按 +1,-1,+2,-2... 累积搜索，等距时上方优先。
    /// 返回绝对音高（pitch class 命中集合，拼写由数据源在渲染层处理）。
    private static func closestPitch(originalPitch: Int, usablePC: Set<Int>) -> Int {
        var pitch = originalPitch
        var step = 0
        while !usablePC.contains(pitchClass(pitch)) {
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

// MARK: - 重复音合并（两个版本）

extension TradingResponder {

    /// Java MelodyPart.removeRepeatedNotes（返回新副本）：
    /// 合并相邻同音非休止；合并相邻休止；音↔休止不合并。
    static func removeRepeatedNotes(_ notes: [TradingSlotNote]) -> [TradingSlotNote] {
        var result: [TradingSlotNote] = []
        guard let first = notes.first else { return result }

        var groupStart = first.startSlot
        var groupPitch = first.pitch
        var groupRest = first.isRest
        var duration = first.durationSlots

        func flush() {
            result.append(TradingSlotNote(
                pitch: groupPitch,
                startSlot: groupStart,
                durationSlots: duration,
                isRest: groupRest
            ))
        }

        for current in notes.dropFirst() {
            let merge: Bool
            if current.isRest && groupRest {
                merge = true
            } else if !current.isRest && !groupRest && current.pitch == groupPitch {
                merge = true
            } else {
                merge = false
            }

            if merge {
                duration += current.durationSlots
            } else {
                flush()
                groupStart = current.startSlot
                groupPitch = current.pitch
                groupRest = current.isRest
                duration = current.durationSlots
            }
        }
        flush()
        return result
    }

    /// Java MelodyPart.removeRepeatedNotesInPlace（原地）：
    /// 仅合并相邻同音非休止；不合并休止；休止会打断同音累积。
    static func removeRepeatedNotesInPlace(_ notes: [TradingSlotNote]) -> [TradingSlotNote] {
        var result: [TradingSlotNote] = []
        for current in notes {
            if current.isRest {
                result.append(current)
                continue
            }
            if let last = result.last, !last.isRest, last.pitch == current.pitch {
                result[result.count - 1].durationSlots += current.durationSlots
            } else {
                result.append(current)
            }
        }
        return result
    }
}
