import Foundation

// MARK: - ChordForm — alt扩展音识别 + 和弦质量判定 (P1 · 约80行)
// 完善 b9/#9/#11/b13 alter延伸音识别规则, 补齐色彩音池精度

struct ChordForm {

    /// 检测某半音是否为和弦的 alter 延伸音
    static func isAlterTone(_ pitchClass: Int, for chordName: String) -> Bool {
        let rootPC = PitchClass(noteName: String(chordName.prefix {
            $0.isLetter && $0.isUppercase || $0 == "#" || $0 == "b"
        }))
        let targetInterval = (pitchClass - rootPC.index + 12) % 12
        let family = ChordBlock(name: chordName, duration: 0).getChordFamily()
        return ChordExtensionTonePool.tonesFor(family).contains(targetInterval)
            && !ChordExtensionTonePool.primaryTonesFor(family).contains(targetInterval)
    }

    /// 识别和弦名中的 alter 变音标记 (b9, #9, #11, b13, b5, #5)
    static func detectAlters(in chordName: String) -> [QualityCheck] {
        let lower = chordName.lowercased()
        var results: [QualityCheck] = []
        if lower.contains("b9")  { results.append(.flat9) }
        if lower.contains("#9")  { results.append(.sharp9) }
        if lower.contains("#11") { results.append(.sharp11) }
        if lower.contains("b13") { results.append(.flat13) }
        if lower.contains("b5")  { results.append(.flat5) }
        if lower.contains("#5")  { results.append(.sharp5) }
        if lower.contains("alt") { results.append(contentsOf: [.flat9, .sharp9, .sharp11, .flat13]) }
        return results
    }

    /// 从和弦名推断调式
    static func inferMode(from chordName: String) -> JazzMode {
        let normalized = chordName
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "♯", with: "#")
        let rawSuffix = String(normalized.drop {
            $0.isLetter && $0.isUppercase || $0 == "#" || $0 == "b"
        })
        let q = rawSuffix.lowercased()

        // 严格按最长/最特殊后缀优先匹配
        if q.contains("dim7") || q.contains("o7") { return .locrian }
        if q.contains("m7b5") || q.contains("ø")   { return .locrian }
        if q.contains("dim")                      { return .locrian }
        if q.contains("aug")  || q.contains("+")  { return .dominant }
        if q.contains("mmaj")                     { return .dorian }
        if q.contains("maj") || rawSuffix.contains("M7") { return .major }
        if q.contains("sus")                      { return .dominant }
        if rawSuffix.contains("m") && !q.contains("maj") { return .dorian }

        if q.contains("7") || q.contains("9") || q.contains("11") || q.contains("13") {
            return .dominant
        }
        return .major
    }

    /// 从和弦名 + brick 上下文推断调式
    static func inferMode(from chordName: String, contextBrick: String?) -> JazzMode {
        let base = inferMode(from: chordName)
        guard let brick = contextBrick else { return base }
        if brick.contains("Cadence") && base == .dorian { return .minor }
        return base
    }
}

// MARK: - QualityCheck 变音类型标记

enum QualityCheck {
    case flat9, sharp9, sharp11, flat13, flat5, sharp5
}

// MARK: - JazzMode 从和弦名推断

extension JazzMode {
    init(chordName: String) {
        self = ChordForm.inferMode(from: chordName)
    }
}

// MARK: - ChordDegree 音级标记

/// 和弦音等级分类 — 供 getChordTonesWithDegree() 使用
enum ChordDegree: String {
    case root       = "R"    // 根音
    case third      = "3rd"  // 三音
    case fourth     = "4th"  // 纯四度 (sus4 挂留)
    case fifth      = "5th"  // 五音
    case seventh    = "7th"  // 七音
    case ninth      = "9th"  // 九音
    case eleventh   = "11th" // 十一音
    case thirteenth = "13th" // 十三音
    case altered    = "Alt"  // 变音/无法归类
}
