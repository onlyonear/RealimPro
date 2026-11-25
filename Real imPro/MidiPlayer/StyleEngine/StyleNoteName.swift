import Foundation

// MARK: - StyleNoteName
// .sty 音名 ↔ MIDI。对齐 Java NoteSymbol.java:50-89：
// 中央 c = MIDI 60（octave 0）；每个 '-' 降一个八度、每个 '+' 升一个八度。
// 例：g-- = G2(43)、e-- = E2(40)、c = C4(60)、a = A4(69)、d- = D3(50)。
// 用于读取 .sty 文件头的 bass-low / bass-base / bass-high / chord-low / chord-high。

enum StyleNoteName {
    private static let pitchClass: [String: Int] = [
        "c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11
    ]

    /// 解析如 "c"、"g--"、"d-"、"c+"、"c#-" 的音名为 MIDI 号。
    /// .sty 音域参数只用自然音名 + 八度符号；这里仍兼容单个 #/b 变音记号。
    static func midi(_ note: String) -> Int? {
        var t = note.lowercased().trimmingCharacters(in: .whitespaces)
        guard let first = t.first, let pc = pitchClass[String(first)] else { return nil }
        t.removeFirst()

        var semi = pc
        if t.hasPrefix("#") { semi += 1; t.removeFirst() }
        else if t.hasPrefix("b") { semi -= 1; t.removeFirst() }

        var octave = 0
        for ch in t {
            if ch == "-" { octave -= 1 }
            else if ch == "+" { octave += 1 }
        }
        return 60 + octave * 12 + semi
    }
}
