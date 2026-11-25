import Foundation

// MARK: - SubstitutionDictionary — 和弦动态替换字典 (P0-5)
// 仅4种基础替换, 风格自适应概率, 不可变设计

struct SubstitutionDictionary {

    enum SubstitutionType: String {
        case tritoneSubstitution  // 三全音替代 V7 ↔ bII7
        case secondaryDominant    // 次属七 V/X → X的属七
        case backdoorProgression  // 后门进行 bVII7 → I
        case modalInterchange     // 调式互换 bVI-bVII-I
    }

    // MARK: - 概率表

    static let styleProbabilities: [String: Double] = [
        "swing":  0.15,
        "bebop":  0.30,
        "ballad": 0.05,
    ]

    // MARK: - 音高辅助

    /// 根音名→半音索引
    private static let rootPC: [String: Int] = [
        "C":0,"C#":1,"Db":1,"D":2,"D#":3,"Eb":3,"E":4,
        "F":5,"F#":6,"Gb":6,"G":7,"G#":8,"Ab":8,"A":9,"A#":10,"Bb":10,"B":11
    ]

    /// 半音索引→根音名 (用b记号)
    private static let pcToFlat: [Int: String] = [
        0:"C",1:"Db",2:"D",3:"Eb",4:"E",5:"F",6:"Gb",
        7:"G",8:"Ab",9:"A",10:"Bb",11:"B"
    ]

    /// 从和弦名中提取根音名和品质
    private static func parseChord(_ name: String) -> (root: String, quality: String) {
        let rootStr = String(name.prefix { $0.isLetter && $0.isUppercase || $0 == "#" || $0 == "b" })
        let qualityStr = String(name.dropFirst(rootStr.count))
        return (rootStr, qualityStr)
    }

    /// 判断是否为属七和弦
    private static func isDominant7(_ name: String) -> Bool {
        let q = parseChord(name).quality
        // 属七: 以7/9/11/13开头且不是maj7后缀
        return (q.hasPrefix("7") || q.hasPrefix("9") || q.hasPrefix("11") || q.hasPrefix("13"))
            && !name.lowercased().contains("maj")
    }

    /// 判断是否为小七和弦
    private static func isMinor7(_ name: String) -> Bool {
        let l = name.lowercased()
        return l.contains("m7") && !l.contains("m7b5")
    }

    // MARK: - 主入口

    /// 和弦替换, 返回新数组 (绝对不修改原数组)
    /// - Parameters:
    ///   - chordBlocks: 原始和弦块数组
    ///   - style: 爵士风格名 (swing/bebop/ballad/default)
    /// - Returns: 替换后的新和弦块数组
    static func resolve(chordBlocks: [ChordBlock], style: String = "default") -> [ChordBlock] {
        let probability = styleProbabilities[style] ?? 0.10
        var result = chordBlocks.map { $0 }  // 副本

        for i in 0..<result.count {
            guard Double.random(in: 0...1) < probability else { continue }
            let chord = result[i]

            // 1. 三全音替代: 属七→上方三全音属七
            if isDominant7(chord.name) {
                let (root, quality) = parseChord(chord.name)
                if let pc = rootPC[root] {
                    let tritonePC = (pc + 6) % 12
                    let tritoneRoot = pcToFlat[tritonePC] ?? root
                    result[i].name = tritoneRoot + quality
                }
                continue
            }

            // 2. 次属七: ii前面→ii的属七 (i>0时检查前一个是m7)
            if i > 0 && isMinor7(result[i].name) {
                let (root, _) = parseChord(result[i].name)
                if let pc = rootPC[root] {
                    let sdPC = (pc + 7) % 12  // ii的属七 = 根音上纯五度
                    let sdRoot = pcToFlat[sdPC] ?? "G"
                    result[i-1].name = sdRoot + "7"
                }
                continue
            }

            // 3. 后门进行: I前面→bVII7 (i>0时前一个和弦替换为bVII7)
            if i > 0 && chord.name.lowercased().hasPrefix("c") && chord.name.lowercased().contains("maj") {
                let (root, _) = parseChord(chord.name)
                if let pc = rootPC[root] {
                    let bVII = (pc + 10) % 12  // I下方大二度
                    let bviiRoot = pcToFlat[bVII] ?? "Bb"
                    result[i-1].name = bviiRoot + "7"
                }
                continue
            }

            // 4. 调式互换: I前→bVI-bVII (需要前两个和弦都存在, i>=2)
            if i >= 2 && chord.name.lowercased().hasPrefix("c") && chord.name.lowercased().contains("maj") {
                let (root, _) = parseChord(chord.name)
                if let pc = rootPC[root] {
                    let bVI = pcToFlat[(pc + 8) % 12] ?? "Ab"
                    let bVII = pcToFlat[(pc + 10) % 12] ?? "Bb"
                    result[i-2].name = bVI + "maj7"
                    result[i-1].name = bVII + "7"
                }
            }
        }

        return result
    }
}
