import Foundation

/// MusicXML `<harmony>` → App 和弦显示串。
/// 策略：先用 music21 同款"简写 figure 后缀 + degree token"构造，再过一遍与
/// `chord_norm.py _norm_body` 等价的有序规则表，得到与离线管线逐字一致的结果
/// （含 `maj7`、`add 9`、`alter #9` 这类静态表未收的原样串，交由 V17 计数）。
struct MXDegree {
    enum Kind: String { case add, alter, subtract
        init?(_ raw: String?) {
            switch raw?.lowercased() {
            case "add": self = .add
            case "alter": self = .alter
            case "subtract": self = .subtract
            default: return nil
            }
        }
    }
    var kind: Kind
    var alter: Int
    var value: Int
}

struct MXHarmony {
    var rootStep: String?
    var rootAlter: Int = 0
    var kind: String
    var bassStep: String?
    var bassAlter: Int = 0
    var degrees: [MXDegree] = []
}

enum MusicXMLChordMapper {

    /// 无法解析根音/kind 时返回 nil（调用方按 V17 处理）。
    static func display(_ h: MXHarmony) -> String? {
        guard let root = h.rootStep else { return "N.C." }
        guard let base = baseAbbreviation(h.kind) else { return nil }

        var suffix = base
        for d in h.degrees {
            let acc = accidentalString(d.alter)
            switch d.kind {
            case .add:      suffix += " add \(acc)\(d.value)"
            case .alter:    suffix += " alter \(acc)\(d.value)"
            case .subtract: suffix += " sub \(acc)\(d.value)"
            }
        }
        suffix = suffix.trimmingCharacters(in: .whitespaces)
        suffix = normalizeBody(suffix)

        let rootSpell = root + accidentalString(h.rootAlter)
        let body = rootSpell + suffix

        // 显式低音与根音同音（含等拼写）时不写转位斜杠（music21 figure 口径：Bb/Bb → Bb）
        if let b = h.bassStep, !(b == h.rootStep && h.bassAlter == h.rootAlter) {
            return body + "/" + b + accidentalString(h.bassAlter)
        }
        return body
    }

    /// ChordSymbolMapper.resolve 是否能识别（仅用于 M1 命中率统计 / V17）。
    static func resolvable(_ display: String) -> Bool {
        return ChordSymbolMapper.resolve(display) != nil
    }

    private static func accidentalString(_ alter: Int) -> String {
        if alter > 0 { return String(repeating: "#", count: alter) }
        if alter < 0 { return String(repeating: "b", count: -alter) }
        return ""
    }

    /// MusicXML `<kind>` → music21 figure 基础缩写。
    static func baseAbbreviation(_ kind: String) -> String? {
        switch kind {
        case "major":              return ""
        case "minor":              return "m"
        case "augmented":          return "+"
        case "diminished":         return "dim"
        case "diminished-seventh": return "o7"
        case "half-diminished":    return "m7b5"
        case "dominant":           return "7"
        case "dominant-ninth":     return "9"
        case "dominant-11th":      return "11"
        case "dominant-13th":      return "13"
        case "major-seventh":      return "maj7"
        case "major-ninth":        return "M9"
        case "major-11th":         return "M11"
        case "major-13th":         return "M13"
        case "minor-seventh":      return "m7"
        case "minor-ninth":        return "m9"
        case "minor-11th":         return "m11"
        case "minor-13th":         return "m13"
        case "minor-major-seventh", "major-minor": return "mM7"
        case "minor-sixth":        return "m6"
        case "major-sixth":        return "6"
        case "suspended-fourth":   return "sus"
        case "suspended-second":   return "sus2"
        case "augmented-seventh":  return "7+"
        case "power":              return "power"
        default:                  return nil
        }
    }

    /// 与 chord_norm.py `_norm_body` 有序规则等价（首条命中即返回）。
    static func normalizeBody(_ s: String) -> String {
        let rules: [(String, String)] = [
            ("^M13 alter #11$", "M13#11"),
            ("^maj7 add #11$", "M7#11"),
            ("^M7 add #11$", "M7#11"),
            ("^mM7 add 9 add 11$", "mM9"),
            ("^mM7 add 9$", "mM9"),
            ("^sus alter b5 add 7$", "7sus4"),
            ("^sus add 7 add 9$", "9sus4"),
            ("^sus add 7$", "7sus4"),
            ("^sus$", "sus4"),
            ("^7 add #9$", "7#9"),
            ("^7 add b9$", "7b9"),
            ("^7 add #11$", "7#11"),
            ("^7 add b13$", "7b13"),
            ("^7 alter #5$", "7#5"),
            ("^7 alter b5$", "7b5"),
            ("^7\\+$", "7#5"),
            ("^9 add #11$", "9#11"),
            ("^6 add 9$", "M69"),
            ("^m7 alter b5$", "m7b5"),
            ("^m7b5$", "m7b5"),
            ("^o7$", "o7"),
            ("^°7$", "o7"),
            ("^dim7$", "o7"),
            ("^[o°]$", "o"),
            ("^dim$", "o"),
        ]
        for (pat, rep) in rules {
            if let r = try? NSRegularExpression(pattern: pat),
               r.firstMatch(in: s, range: NSRange(location: 0, length: s.utf16.count)) != nil {
                return rep
            }
        }
        return s
    }
}
