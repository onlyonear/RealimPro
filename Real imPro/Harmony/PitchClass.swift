import Foundation

// MARK: - PitchClass — 统一半音索引系统 (P0 · 约80行)
// 封装0~11半音索引, 消除全局 midiPitch % 12 硬编码
// 等音转换 (Eb↔D#), 音名字符串↔索引双向映射

struct PitchClass: Equatable, Hashable, Comparable {

    /// 半音索引 0=C, 1=C#/Db, 2=D, ..., 11=B
    let index: Int

    // MARK: - 初始化

    init(index: Int) {
        self.index = ((index % 12) + 12) % 12  // normalize
    }

    init(midiPitch: Int) {
        self.init(index: midiPitch % 12)
    }

    /// 从音名字符串解析 ("C", "C#", "Db", "Eb", ...)
    init(noteName: String) {
        self.index = PitchClass.indexFromName(noteName)
    }

    // MARK: - 音名↔索引

    /// 标准爵士记谱音名 (用b不用# 优先: 如 Eb 不用 D#)
    var preferredName: String {
        PitchClass.preferredNames[index]
    }

    /// 升号记法 (#)
    var sharpName: String {
        PitchClass.sharpNames[index]
    }

    /// 降号记法 (b)
    var flatName: String {
        PitchClass.flatNames[index]
    }

    /// 音名字符串 → 半音索引
    static func indexFromName(_ name: String) -> Int {
        let clean = name.trimmingCharacters(in: .whitespaces).uppercased()
        if let idx = nameToIndex[clean] { return idx }
        // fallback: 取首字母
        let base: [Character: Int] = ["C":0,"D":2,"E":4,"F":5,"G":7,"A":9,"B":11]
        var idx = base[clean.first ?? "C"] ?? 0
        if clean.contains("#") { idx += 1 }
        if clean.contains("B") && clean.count > 1 { idx -= 1 }
        return ((idx % 12) + 12) % 12
    }

    // MARK: - 等音判断

    /// 是否等音 (例: Eb↔D#)
    static func enharmonic(_ a: PitchClass, _ b: PitchClass) -> Bool {
        a.index == b.index
    }

    /// 获取等音对照 (如 Eb→[D#], Gb→[F#])
    var enharmonicNames: [String] {
        var result = [preferredName]
        let sharp = PitchClass.sharpNames[index]
        let flat  = PitchClass.flatNames[index]
        let alt = preferredName == sharp ? flat : sharp
        if alt != preferredName { result.append(alt) }
        return result
    }

    // MARK: - 音程计算

    func interval(to other: PitchClass) -> Int {
        (other.index - index + 12) % 12
    }

    func transposed(by semitones: Int) -> PitchClass {
        PitchClass(index: index + semitones)
    }

    // MARK: - 协议

    static func < (lhs: PitchClass, rhs: PitchClass) -> Bool { lhs.index < rhs.index }

    // MARK: - 静态常量表

    private static let preferredNames = [
        "C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"
    ]
    private static let sharpNames = [
        "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"
    ]
    private static let flatNames = [
        "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"
    ]
    private static let nameToIndex: [String: Int] = [
        "C":0, "C#":1, "DB":1, "D":2, "D#":3, "EB":3,
        "E":4, "F":5, "F#":6, "GB":6, "G":7, "G#":8, "AB":8,
        "A":9, "A#":10, "BB":10, "B":11
    ]
}

// MARK: - MIDI扩展

extension Int {
    /// MIDI音高 → PitchClass
    var pitchClass: PitchClass { PitchClass(midiPitch: self) }
}
