import Foundation

//
//  TradingTokens.swift
//  M2-8 渲染层：Trading 时值 / 音高纯转换工具（与播放、音频引擎完全无关的纯函数）。
//
//  说明：
//  - slots(of:) 与 midi(from:) 由原 TradingPlayback 中的同名静态方法逐字提取（单一实现）。
//  - TradingNoteTagger（颜色标注）与 TradingPlayback（回放排程）共用本文件。
//  - M2-8e 改造回放时，TradingPlayback 内部的同名副本将删除并改为引用本类型，避免两份漂移。
//

enum TradingTokens {

    /// 时值串 → slot（四分音符=120，与 PhraseToMeasures 的编码一一对应；`_t3` 取 2/3）。
    /// 休止符 `r` 后缀不影响前缀匹配；三连休止形如 `8r_t3` 也正确解析。
    static func slots(of duration: String) -> Int {
        let t = duration
        var base = 120
        if t.contains("_t3") {
            if t.hasPrefix("w") { base = 480 }
            else if t.hasPrefix("hd") { base = 360 }
            else if t.hasPrefix("h") { base = 240 }
            else if t.hasPrefix("qd") { base = 180 }
            else if t.hasPrefix("q") { base = 120 }
            else if t.hasPrefix("8d") { base = 90 }
            else if t.hasPrefix("8") { base = 60 }
            else if t.hasPrefix("16d") { base = 45 }
            else if t.hasPrefix("16") { base = 30 }
            else if t.hasPrefix("32") { base = 15 }
            return max(1, base * 2 / 3)
        }
        if t.hasPrefix("wr") { return 480 }
        if t.hasPrefix("hd") { base = 360 }
        else if t.hasPrefix("h") { base = 240 }
        else if t.hasPrefix("qd") { base = 180 }
        else if t.hasPrefix("q") { base = 120 }
        else if t.hasPrefix("8d") { base = 90 }
        else if t.hasPrefix("8") { base = 60 }
        else if t.hasPrefix("16d") { base = 45 }
        else if t.hasPrefix("16") { base = 30 }
        else if t.hasPrefix("32") { base = 15 }
        else if t.hasPrefix("w") { base = 480 }
        return base
    }

    /// 标准 slot → 整段休止符 token（与 MusicXMLQuantizer.REST_NAME 及
    /// ContentView.getExactVexFlowDuration(isRest:) 的标准档输出逐字一致）。
    /// 和弦骨架按 `chunkStandards` 贪心分块后，每个 chunk 恒为这里的标准 key，
    /// 故可直接查表，无需复刻 ContentView 那套含连音档的完整 switch。
    /// 4/4 整小节=480→wr、3/4=360→hdr、2/4=240→hr。
    static let restTokenForSlot: [Int: String] = [
        480: "wr", 360: "hdr", 240: "hr", 180: "qdr", 120: "qr",
        90: "8dr", 60: "8r", 45: "16dr", 30: "16r", 15: "32r"
    ]

    /// 记谱 pitch 字符串（如 "C/4"、"Bb/3"）→ MIDI 音高。
    static func midi(from pitch: String) -> UInt8? {
        let parts = pitch.split(separator: "/")
        guard parts.count == 2, let oct = Int(parts[1]) else { return nil }
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let name = String(parts[0])
        let idx: Int
        if let k = names.firstIndex(of: name) {
            idx = k
        } else if let v = ["Db": 1, "Eb": 3, "Gb": 6, "Ab": 8, "Bb": 10][name] {
            idx = v
        } else {
            return nil
        }
        return UInt8(max(0, min(127, (oct + 1) * 12 + idx)))
    }
}
