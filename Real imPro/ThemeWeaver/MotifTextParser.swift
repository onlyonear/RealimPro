//
//  MotifTextParser.swift
//  RealimPro
//
//  ThemeWeaver M5：动机粘贴文本解析 / 音名 ↔ MIDI（纯 Foundation，可独立对拍，不依赖 SwiftUI）。
//  规则：每个音符 = 音名 + 时值两个 token，如 "C4 8"、"Eb4 16t"、"R 4."。
//

import Foundation

enum MotifTextParser {

    /// 音名（含升降与八度）→ MIDI；非法返回 nil。C4 = 60
    static func noteNameToMIDI(_ token: String) -> Int? {
        let s = token.trimmingCharacters(in: .whitespaces)
        guard let first = s.first, first.isLetter else { return nil }
        let letterMap: [Character: Int] = ["C":0,"D":2,"E":4,"F":5,"G":7,"A":9,"B":11]
        guard let base = letterMap[Character(first.uppercased())] else { return nil }
        var idx = s.index(after: s.startIndex)
        var alter = 0
        // 升降号可叠加（## / bb），也兼容 b/#
        while idx < s.endIndex {
            let ch = s[idx]
            if ch == "#" || ch == "♯" { alter += 1 }
            else if ch == "b" || ch == "♭" { alter -= 1 }
            else if ch.isNumber { break }
            else { return nil }
            idx = s.index(after: idx)
        }
        guard idx < s.endIndex, let oct = Int(s[idx...]) else { return nil }
        return 12 * (oct + 1) + base + alter
    }

    /// 调名（如 "C"、"Bb"、"F#"）→ 主音 PC 0-11；非法回 0
    static func noteNameToPC(_ name: String) -> Int {
        guard let m = noteNameToMIDI(name + "4") else { return 0 }
        return ((m % 12) + 12) % 12
    }

    /// MIDI → 显示音名（如 60 → "C4"）
    static func midiToName(_ midi: Int) -> String {
        let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        let pc = ((midi % 12) + 12) % 12
        let oct = midi / 12 - 1
        return names[pc] + "\(oct)"
    }

    struct ParseResult { let notes: [PhysicalNote]; let errors: [String] }

    /// 解析粘贴文本；错误逐条返回，绝不静默丢弃
    static func parse(_ text: String, minPitch: Int = 60, maxPitch: Int = 82) -> ParseResult {
        let units = text
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0.isWhitespace || $0 == "\n" })
            .map(String.init)
        var notes: [PhysicalNote] = []
        var errors: [String] = []
        var i = 0
        while i < units.count {
            let pitchTok = units[i]
            let isRest = pitchTok.uppercased() == "R" || pitchTok.uppercased() == "REST"
            guard i + 1 < units.count else {
                errors.append("\(pitchTok): " + NSLocalizedString("缺少时值", comment: ""))
                i += 1; continue
            }
            let rhythmTok = units[i+1]
            let rhythm = parseRhythm(rhythmTok)
            guard let slots = rhythm.slots else {
                errors.append("\(pitchTok) \(rhythmTok): " + NSLocalizedString("无法识别的时值", comment: ""))
                i += 2; continue
            }
            if isRest {
                notes.append(PhysicalNote(midiPitch: -1, durationSlots: slots, tuplet: rhythm.tuplet))
            } else if let midi = noteNameToMIDI(pitchTok) {
                if midi < minPitch || midi > maxPitch {
                    errors.append("\(pitchTok): " + String(format: NSLocalizedString("音高超出 %d–%d", comment: ""), minPitch, maxPitch))
                } else {
                    notes.append(PhysicalNote(midiPitch: midi, durationSlots: slots, tuplet: rhythm.tuplet))
                }
            } else {
                errors.append("\(pitchTok): " + NSLocalizedString("无法识别的音名", comment: ""))
            }
            i += 2
        }
        return ParseResult(notes: notes, errors: errors)
    }

    static func parseRhythm(_ token: String) -> (slots: Int?, tuplet: Int?) {
        var s = token.lowercased()
        var tuplet: Int? = nil
        var dotted = false
        if s.hasSuffix("t") { tuplet = 3; s = String(s.dropLast()) }
        if s.hasSuffix(".") { dotted = true; s = String(s.dropLast()) }
        guard let den = Int(s), den > 0, 480 % den == 0 else { return (nil, nil) }
        var slots = 480 / den
        if dotted { slots = slots * 3 / 2 }
        if tuplet != nil { slots = slots * 2 / 3 }
        return (slots, tuplet)
    }
}
