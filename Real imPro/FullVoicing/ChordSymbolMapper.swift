import Foundation

// MARK: - 和弦符号 -> (canonical 根形式, findRise)。对齐 Java Chord.makeChord + getChordForm(same 闭包) + PitchClass.findRise。
enum ChordSymbolMapper {
    struct Resolved: Equatable { let canonical: String; let rise: Int }

    /// 输入如 "Bbmaj7" / "Dm7b5" / "Gb7" / "C#m7" / "Ebm7/Db"(斜杠和弦取斜杠前本体, bass 不参与 voicing);
    /// 输出静态表根形式名 + 有符号 rise。
    static func resolve(_ name: String) -> Resolved? {
        // 斜杠和弦 X/Y: voicing 只看本体 X(对齐 Java Chord 解析, 斜杠后是 bass)
        let body = name.components(separatedBy: "/").first ?? name
        let t = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let chars = Array(t)
        guard !chars.isEmpty else { return nil }
        var rootLen = 1
        if chars.count > 1 && (chars[1] == "#" || chars[1] == "b") { rootLen = 2 }
        let rootSpell = String(chars[0..<rootLen]).lowercased()
        let suffix = String(chars[rootLen...])
        guard let rise = ChordFormMaps.rootRise[rootSpell] else { return nil }
        guard let canon = canonical(forSuffix: suffix) else { return nil }
        return Resolved(canonical: canon, rise: rise)
    }

    /// "C" + 后缀 -> 根形式; 依次尝试原写法、全小写(生成表已含两种 key)。
    static func canonical(forSuffix suffix: String) -> String? {
        let key = "C" + suffix
        if let c = ChordFormMaps.aliasToCanonical[key] { return c }
        if let c = ChordFormMaps.aliasToCanonical[key.lowercased()] { return c }
        return nil
    }
}
