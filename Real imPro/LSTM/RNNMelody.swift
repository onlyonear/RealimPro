//
//  RNNMelody.swift
//  RealimPro
//
//  LSTM P0 —— 把逐步 token（每个时间步 = 10 slots）解码成音符，口径对齐
//  DataPartIO.addToMelodyPart（:148-187）。纯 Foundation，可在独立 harness 测试。
//

import Foundation

/// 中性音符（不依赖 App 的 PhysicalNote）。midiPitch = -1 表示休止。
struct RNNNote: Equatable {
    let midiPitch: Int
    let durationSlots: Int
}

enum RNNMelody {
    static let slotsPerStep = 10

    /// tokens：每步一个，取值 -1(休止) / -2(延音) / 否则为 MIDI 音高。
    static func decode(tokens: [Int]) -> [RNNNote] {
        guard !tokens.isEmpty else { return [] }

        var notes: [RNNNote] = []

        // 首步（Java:152-158）：首步若是延音，按休止处理
        var noteValue: Int
        if tokens[0] == -2 { noteValue = -1 } else { noteValue = tokens[0] }
        var duration = 1

        var index = 1
        while index < tokens.count {
            let next = tokens[index]
            // 延音，或"当前休止且下一步也是休止" → 时值 +1
            if next == -2 || (noteValue == -1 && next == -1) {
                duration += 1
            } else {
                // 收尾输出当前音
                emit(notes: &notes, value: noteValue, duration: duration)
                noteValue = next
                duration = 1
            }
            index += 1
        }
        // 最后一个音
        emit(notes: &notes, value: noteValue, duration: duration)
        return notes
    }

    private static func emit(notes: inout [RNNNote], value: Int, duration: Int) {
        notes.append(RNNNote(midiPitch: value, durationSlots: duration * slotsPerStep))
    }
}
