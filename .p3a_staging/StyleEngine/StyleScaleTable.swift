import Foundation

// MARK: - StyleScaleTable
// 给贝斯渲染器提供「根音 + 和弦音 + 首选音阶」。
// 根音 / canonical form 复用 App 内权威的 ChordSymbolMapper（斜杠和弦只取本体）；
// 每个 form 的首选音阶取自出厂词汇 Original.voc 中该 chord form 的 scales 块第一项（实测）：
//   大/大七/大六 → major(Ionian)；小七/九/十一/十三 → dorian；小六/小大七 → melodic minor；
//   属七/九 → mixolydian；自然 13 / #11 / b5 → lydian dominant；属 #5 → whole tone；
//   b9/#9/b13(altered) → altered；半减 m7b5 → locrian #2；减七 → half-whole diminished；
//   大增(#5) → lydian augmented；小增 → aeolian。
// 罕见 / 未识别 form 退化为只用和弦音（Java 无音阶时同样退回随机和弦音）。

struct StyleHarmony: Equatable {
    let rootPC: Int            // 根音 pitch class（相对 C，0–11）
    let chordTones: [Int]      // 相对根的和弦音半音（一个八度内，含根 0）
    let scale: [Int]?          // 首选音阶相对根半音（一个八度内、升序、含根 0）；nil = 退化为和弦音
}

enum StyleScaleTable {

    static func resolve(_ chordName: String) -> StyleHarmony? {
        guard let r = ChordSymbolMapper.resolve(chordName) else { return nil }
        let pc = ((r.rise % 12) + 12) % 12
        let suffix = String(r.canonical.dropFirst())   // 去掉根名字母 "C"
        let h = classify(suffix)
        return StyleHarmony(rootPC: pc, chordTones: h.tones, scale: h.scale)
    }

    // 各音阶（相对根半音，一个八度）
    private static let ionian   = [0, 2, 4, 5, 7, 9, 11]
    private static let dorian   = [0, 2, 3, 5, 7, 9, 10]
    private static let melMinor = [0, 2, 3, 5, 7, 9, 11]
    private static let aeolian  = [0, 2, 3, 5, 7, 8, 10]
    private static let mixo     = [0, 2, 4, 5, 7, 9, 10]
    private static let lydDom   = [0, 2, 4, 6, 7, 9, 10]
    private static let lydian   = [0, 2, 4, 6, 7, 9, 11]
    private static let lydAug   = [0, 2, 4, 6, 8, 9, 11]
    private static let wholeTone = [0, 2, 4, 6, 8, 10]
    private static let altered  = [0, 1, 3, 4, 6, 8, 10]
    private static let locrianSharp2 = [0, 2, 3, 5, 6, 8, 10]
    private static let locrian  = [0, 1, 3, 5, 6, 8, 10]
    private static let dimHW    = [0, 1, 3, 4, 6, 7, 9, 10]

    private struct H { let tones: [Int]; let scale: [Int]? }

    // swiftlint:disable:next function_body_length
    private static func classify(_ s: String) -> H {
        // —— 特殊单音 / 无调 ——
        if s == "Bass" || s == "Note" { return H(tones: [0], scale: nil) }
        if s == "Blues" { return H(tones: [0, 4, 7], scale: nil) }

        // —— 减 / 半减 ——
        if s.contains("o") { return H(tones: [0, 3, 6, 9], scale: dimHW) }
        if s.contains("m7b5") || s.contains("m9b5") {
            return H(tones: [0, 3, 6, 10], scale: locrianSharp2)
        }

        // —— 小大七 / 小六（melodic minor 系）——
        if s.hasPrefix("mM") { return H(tones: [0, 3, 7, 11], scale: melMinor) }
        if s.hasPrefix("m6") { return H(tones: [0, 3, 7, 9], scale: melMinor) }

        // —— 小三和弦家族 ——
        if s.hasPrefix("m") {
            if s.contains("#5") {
                let tones = s.contains("7") ? [0, 3, 8, 10] : [0, 3, 8]
                return H(tones: tones, scale: aeolian)
            }
            if s.contains("b5") { return H(tones: [0, 3, 6, 10], scale: locrian) }
            let hasSeventh = s.contains("7") || s.contains("9") || s.contains("11") || s.contains("13")
            return H(tones: hasSeventh ? [0, 3, 7, 10] : [0, 3, 7], scale: dorian)
        }

        // —— sus 挂留（在大 / 属常规判定前）——
        if s.contains("sus") {
            let dominant = s.first?.isNumber == true || s.contains("7") || s.contains("13")
            if dominant {
                return H(tones: [0, 5, 7, 10], scale: mixo)
            }
            if s.contains("24") { return H(tones: [0, 2, 5, 7], scale: ionian) }
            if s.contains("2") { return H(tones: [0, 2, 7], scale: ionian) }
            return H(tones: [0, 5, 7], scale: ionian)
        }

        // —— 属七家族（canonical 以 7/9/11/13 开头）——
        if s.first?.isNumber == true {
            // quartal C4 / power C5
            if s == "4" { return H(tones: [0, 5, 10], scale: nil) }
            if s == "5" { return H(tones: [0, 7], scale: nil) }

            if s.contains("b9") || s.contains("#9") || s.contains("b13") || s.lowercased().contains("alt") {
                return H(tones: [0, 4, 7, 10], scale: altered)
            }
            if s.contains("#5") { return H(tones: [0, 4, 8, 10], scale: wholeTone) }
            if s.contains("#11") || s.contains("b5") || s.contains("13") {
                return H(tones: [0, 4, 7, 10], scale: lydDom)
            }
            return H(tones: [0, 4, 7, 10], scale: mixo)
        }

        // —— 大三和弦家族（M 前缀，含裸 C → CM）——
        if s.hasPrefix("M") || s.isEmpty {
            if s.contains("#5") {
                let tones = s.contains("7") ? [0, 4, 8, 11] : [0, 4, 8]
                return H(tones: tones, scale: lydAug)
            }
            if s.contains("#11") { return H(tones: [0, 4, 7, 11], scale: lydian) }
            if s.contains("6") { return H(tones: [0, 4, 7, 9], scale: ionian) }
            if s.contains("7") || s.contains("9") || s.contains("13") {
                return H(tones: [0, 4, 7, 11], scale: ionian)
            }
            return H(tones: [0, 4, 7], scale: ionian)
        }

        // —— 兜底：大三和弦、无音阶 ——
        return H(tones: [0, 4, 7], scale: nil)
    }
}
