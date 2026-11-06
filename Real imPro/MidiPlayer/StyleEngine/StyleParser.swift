import Foundation

// MARK: - StyleParser
// 把 .sty 的 S-表达式解析为 ParsedStyle。识别的 section / 关键字对齐 Style.java:238-247：
//   标量：name / swing / comp-swing / voicing-type / bass-high / bass-low / bass-base / chord-high / chord-low
//   段落：(bass-pattern (weight) (rules ...))、(drum-pattern (weight) (drum n name X.. R.. V..) …)、
//         (chord-pattern (weight) (rules ...) [(push x)])
// 时值合计规则照搬探针 v1（已 ALL PASS）：X/R/音名占时值，V 音量、U/D 方向不占，(push) 单独提取不计入长度。

enum StyleParser {

    static func parse(text: String) -> ParsedStyle? {
        let forms = StyleSExpression.parse(text)
        guard let styleList = forms.first(where: { $0.asList?.first?.asAtom == "style" })?.asList else {
            // 容错：有的文件顶层直接是若干段，取第一个含多元素的 list
            guard let any = forms.first(where: { $0.asList != nil })?.asList else { return nil }
            return build(from: any)
        }
        return build(from: styleList)
    }

    private static func build(from styleList: [StyleSex]) -> ParsedStyle {
        var globals: [String: String] = [:]
        var bassPatterns: [StylePattern] = []
        var drumPatterns: [StyleDrumPattern] = []
        var chordPatterns: [StylePattern] = []

        for node in styleList {
            guard let seg = node.asList, let head = seg.first?.asAtom else { continue }
            switch head {
            case "bass-pattern":
                if let p = parseMelodicPattern(seg, isBass: true) { bassPatterns.append(p) }
            case "chord-pattern":
                if let p = parseMelodicPattern(seg, isBass: false) { chordPatterns.append(p) }
            case "drum-pattern":
                if let p = parseDrumPattern(seg) { drumPatterns.append(p) }
            default:
                // 标量键值：(swing 0.67)、(bass-high c) …
                if seg.count >= 2, let v = seg[1].asAtom { globals[head] = v }
            }
        }

        func dbl(_ key: String, _ fallback: Double) -> Double {
            guard let s = globals[key], let v = Double(s) else { return fallback }
            return v
        }
        func note(_ key: String, _ fallback: Int) -> Int {
            guard let s = globals[key], let m = StyleNoteName.midi(s) else { return fallback }
            return m
        }
        func str(_ key: String, _ fallback: String) -> String {
            guard let s = globals[key] else { return fallback }
            return s.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }

        // Java/Style 默认摇摆 2/3；swing.sty 显式写 0.67。音域缺省给 swing.sty 同值作安全兜底。
        return ParsedStyle(
            name: str("name", "style"),
            melodySwing: dbl("swing", 0.67),
            compSwing: dbl("comp-swing", dbl("swing", 0.67)),
            voicingType: str("voicing-type", "open"),
            bassLow: note("bass-low", 43),
            bassHigh: note("bass-high", 60),
            bassBase: note("bass-base", 40),
            chordLow: note("chord-low", 50),
            chordHigh: note("chord-high", 69),
            bassPatterns: bassPatterns,
            drumPatterns: drumPatterns,
            chordPatterns: chordPatterns
        )
    }

    // MARK: bass / chord pattern

    private static func parseMelodicPattern(_ seg: [StyleSex], isBass: Bool) -> StylePattern? {
        var weight = 0.0
        var ruleTrees: [StyleSex] = []
        var length = 0
        var push = 0

        for sub in seg.dropFirst() {
            guard let q = sub.asList, let key = q.first?.asAtom else { continue }
            switch key {
            case "rules":
                ruleTrees = Array(q.dropFirst())
                length = isBass ? bassRuleSlots(ruleTrees) : percRuleSlots(ruleTrees)
            case "weight":
                if let v = q.dropFirst().first?.asAtom, let wv = Double(v) { weight = wv }
            case "push":
                if let e = q.dropFirst().first { push = StyleDuration.slots(e) }
            default:
                break
            }
        }
        guard !ruleTrees.isEmpty else { return nil }
        return StylePattern(weight: weight, ruleTrees: ruleTrees,
                            lengthSlots: length, pushSlots: push)
    }

    /// 贝斯规则总时值：B/C/S/A/N/R/= 与嵌套 (X degree dur) 占时值；V 音量、U/D 方向不占。
    static func bassRuleSlots(_ trees: [StyleSex]) -> Int {
        var total = 0
        for tk in trees {
            if let items = tk.asList {
                // (X degree duration [modifier])
                if items.first?.asAtom == "X", items.count >= 3, let dur = items[2].asAtom {
                    total += StyleDuration.slots(dur)
                }
            } else if let s = tk.asAtom {
                let lead = String(s.prefix(1))
                if lead == "V" || lead == "U" || lead == "D" { continue }
                if s.count >= 2 { total += StyleDuration.slots(String(s.dropFirst())) }
            }
        }
        return total
    }

    /// 鼓 / 钢琴规则总时值：X/R 占时值，V 不占；嵌套表（如 push）不计入。
    static func percRuleSlots(_ trees: [StyleSex]) -> Int {
        var total = 0
        for tk in trees {
            guard let s = tk.asAtom else { continue }
            let lead = String(s.prefix(1))
            if lead == "V" { continue }
            if (lead == "X" || lead == "R") && s.count >= 2 {
                total += StyleDuration.slots(String(s.dropFirst()))
            }
        }
        return total
    }

    // MARK: drum pattern

    private static func parseDrumPattern(_ seg: [StyleSex]) -> StyleDrumPattern? {
        var weight = 0.0
        var rules: [StyleDrumRule] = []
        var length = 0

        for sub in seg.dropFirst() {
            guard let q = sub.asList, let key = q.first?.asAtom else { continue }
            if key == "drum", q.count >= 2, let name = q[1].asAtom {
                // [旧码封存 P3-b 20261011] 原实现只认平铺鼓件 (drum NAME X4 R4 …)，遇大师风格的嵌套
                //   (drum NAME (name )(rules X4 …)) 会把子表全部跳过、鼓件 hits 为空（鼓哑然）：
                // let tokens = Array(q.dropFirst(2))
                // let hits = expandDrumHits(tokens)
                // rules.append(StyleDrumRule(drumName: name, hits: hits))
                // let l = percRuleSlots(tokens)
                // if l > length { length = l }
                //
                // [P3-b G1] 兼容两种鼓件写法（对齐 Java DrumRuleRep.java:376-561）：
                //  · 平铺：(drum Ride_Cymbal_1 X4 R4 V50 …)（swing.sty）
                //  · 嵌套：(drum Ride_Cymbal_1 (name ) (rules X4 R4 …))（8 位大师风格）
                // 嵌套时取 (rules …) 子表内 token；否则取平铺 atom（顺带跳过 (name) 等子表）。
                // (use NAME) 具名规则引用：全 styles 目录 0 文件使用，本期不实现。
                let rest = Array(q.dropFirst(2))
                let tokens: [StyleSex]
                if let rulesList = rest.first(where: { $0.asList?.first?.asAtom == "rules" })?.asList {
                    tokens = Array(rulesList.dropFirst())
                } else {
                    tokens = rest.filter { $0.asAtom != nil }
                }
                let hits = expandDrumHits(tokens)
                rules.append(StyleDrumRule(drumName: name, hits: hits))
                let l = percRuleSlots(tokens)
                if l > length { length = l }
            } else if key == "weight", let v = q.dropFirst().first?.asAtom, let wv = Double(v) {
                weight = wv
            }
        }
        guard !rules.isEmpty else { return nil }
        return StyleDrumPattern(weight: weight, rules: rules, lengthSlots: length)
    }

    /// 展开一件鼓的 X/R/V 序列为带绝对起点的击点。X 无前置 V 时默认力度 127（Java DrumPattern.java:318）。
    static func expandDrumHits(_ trees: [StyleSex]) -> [StyleDrumHit] {
        var hits: [StyleDrumHit] = []
        var onset = 0
        var velocity: UInt8 = 127   // Java DrumPattern.java:318 localVolume 默认 127
        for tk in trees {
            guard let s = tk.asAtom else { continue }
            let lead = String(s.prefix(1))
            if lead == "V", let v = Int(String(s.dropFirst())) {
                velocity = UInt8(max(1, min(127, v)))
            } else if (lead == "X" || lead == "R") && s.count >= 2 {
                let dur = StyleDuration.slots(String(s.dropFirst()))
                hits.append(StyleDrumHit(onsetSlots: onset, durationSlots: dur,
                                        velocity: velocity, isRest: lead == "R"))
                onset += dur
            }
        }
        return hits
    }
}
