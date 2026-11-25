//
//  JavaDiatonic.swift
//  RealimPro
//
//  J2（独立 Java 对齐 Roadmap 链）忠实「调内判定 + findKeys」。
//  对应 Java：
//    · PostProcessor.diatonicChordCheck（PostProcessor.java:859）
//    · PostProcessor.findKeys（PostProcessor.java:149）
//
//  与生产 PostProcessorFull.diatonicSets（粗集，sus/纯属七都归 dominant 在 interval5
//  过度放行）的区别：本文件把 sus4 与纯属七【分开】（新增 .sus 细质量），仅服务独立链，
//  不碰生产 diatonicSets。
//

import Foundation

enum JavaDiatonic {

    /// 细质量（sus 独立；对应 FK.Quality）。
    enum Quality: Hashable {
        case major, minor, minor7, halfDim, dominant, sus, diminished, other
    }

    /// Advisor 家族串 → 细质量。
    static func quality(fromFamily family: String) -> Quality {
        switch family {
        case "dominant":            return .dominant
        case "sus4":                return .sus
        case "minor7":              return .minor7
        case "major", "augmented":  return .major
        case "minor":               return .minor
        case "half-diminished":     return .halfDim
        case "diminished":          return .diminished
        default:                    return .other
        }
    }

    // MARK: - 调内集合（按 My.dictionary 的 diatonic 三表，sus 与纯属七分开）

    static let diatonicSets: [String: [Int: Set<Quality>]] = [
        "Major": [
            0: [.major],
            2: [.minor, .minor7, .halfDim],
            4: [.minor, .minor7],
            5: [.major],
            7: [.dominant],
            9: [.minor, .minor7],
            11: [.diminished, .halfDim]
        ],
        "Minor": [
            0: [.minor],
            2: [.halfDim],
            3: [.major],
            5: [.minor, .minor7, .major],
            7: [.dominant, .minor7],
            8: [.major],
            9: [.halfDim],
            10: [.dominant],
            11: [.diminished]
        ],
        "Dominant": [
            0: [.dominant, .sus],
            2: [.minor, .minor7],
            4: [.diminished, .halfDim],
            5: [.major, .sus],
            7: [.sus],
            9: [.minor, .minor7],
            10: [.major]
        ]
    ]

    // MARK: - equiv 等价质量集合（My.dictionary 的 6 条 equiv 规则，去根音归一）

    /// Java diatonicChordCheck 先经 equiv 把输入和弦映射到代表和弦（cSym）；
    /// 不在任一 equiv 类的质量（cSym==null）一律不调内（PostProcessor.java:887-929）。
    /// 粗 family 会把它们错误折叠（如 7b5→dominant、maj7→major、67→major、susb9→sus），
    /// 故查表前先按精确质量串做这道闸门。数据转录自 My.dictionary，剔除下划线内部编码。
    static let equivQualities: Set<String> = [
        "", "13", "13#11", "13#4", "13#9", "13#9#11", "13+4", "13b5", "13b9",
        "13b9#11", "6", "69", "69#11", "7", "7#11", "7#4", "7#5#9", "7#9", "7+",
        "7+4", "7alt", "7b5b9", "7b9", "7b9#11", "7b9b13", "7b9sus", "7b9sus4",
        "7sus", "7sus4", "7sus4b9", "9", "9#11", "9#4", "9+", "9+4", "9b13",
        "9b5", "9sus", "9sus4", "Dominant", "M", "M13", "M13#11", "M6", "M69",
        "M69#11", "M7", "M7#11", "M9", "M9#11", "Maj13#11", "Maj7", "Maj7#11",
        "Maj9", "Maj9#11", "Major", "add2", "add9", "dim", "dim7", "m", "m#5",
        "m+", "m11", "m11b5", "m13", "m6", "m69", "m7", "m7b5", "m9", "m9b5",
        "mM7", "mb6", "minor", "o", "o7", "oM7", "sus", "sus2", "sus4"
    ]

    /// 调内判定（PostProcessor.diatonicChordCheck 等价）。
    /// - diminished 一律放行（减和弦可作任意调的经过/导音）。
    /// - 不在 equiv 等价类的质量（cSym==null）一律不调内。
    static func diatonicCheck(leaf: JavaCYKParser.JLeaf, key: Int, mode: String) -> Bool {
        let q = quality(fromFamily: leaf.family)
        if q == .diminished { return true }
        if q == .other { return false }
        // 等价类闸门：精确质量不在 equiv（Java cSym=null）→ 不调内。
        if !equivQualities.contains(leaf.rawQuality) { return false }
        let interval = ((leaf.root - key) % 12 + 12) % 12
        guard let set = diatonicSets[mode] else { return false }
        return set[interval]?.contains(q) ?? false
    }

    // MARK: - doesResolve

    /// 属和弦 a 是否解决到 b（(a.root+5)%12 == b.root）。
    /// 对齐 Java PostProcessor.doesResolve(ChordBlock,Block):964——只看 root 差，不判 family；
    /// 故 Bbm7 这类 minor7 和弦只要 root 满足五度关系同样成立（2117 实测）。
    static func doesResolve(_ a: JavaCYKParser.JLeaf, _ b: JavaCYKParser.JLeaf) -> Bool {
        return ((b.root - a.root) % 12 + 12) % 12 == 5
    }

    // MARK: - findKeys（PostProcessor.findKeys；反向 KeySpan 合并）

    struct Span {
        var key: Int
        var mode: String
        var startIdx: Int
        var endIdx: Int
    }

    static func span(from block: JavaCYKParser.JTopBlock) -> Span {
        switch block {
        case .chord(let leaf):
            return Span(key: leaf.root, mode: leaf.mode,
                        startIdx: leaf.idx, endIdx: leaf.idx + 1)
        case .brick(_, _, let mode, let key, let startIdx, let endIdx, _):
            return Span(key: key, mode: mode, startIdx: startIdx, endIdx: endIdx)
        }
    }

    /// 在 CYK 解（已 findLaunchers）上反向合并出最终逐段 key/mode。
    /// 对齐 Java PostProcessor.findKeys：approach 砖解决到下一块时，会把【砖自身 mode】
    /// 改成下一块首和弦 mode（PostProcessor.java:277），故以 inout 同步改写 blocks，
    /// 使顶砖 mode（tm）与 KeySpan mode（sm）一致。
    static func findKeys(_ blocks: inout [JavaCYKParser.JTopBlock]) -> [Span] {
        guard !blocks.isEmpty else { return [] }
        let n = blocks.count
        var current = span(from: blocks[n - 1])
        var keymap: [Span] = []

        for i in stride(from: n - 2, through: 0, by: -1) {
            // 段尾块：强制开新 KeySpan（PostProcessor.java:202），跳过调内合并。
            if blocks[i].isSectionEnd {
                let entry = current
                keymap.insert(entry, at: 0)
                current = span(from: blocks[i])
                switch blocks[i] {
                case .chord(let leaf):
                    // 调内于刚落盘的 entry，则沿用 entry 的 key/mode（:217）
                    if diatonicCheck(leaf: leaf, key: entry.key, mode: entry.mode) {
                        current.key = entry.key
                        current.mode = entry.mode
                    }
                case .brick(let bName, let type, _, let brickKey,
                            let startIdx, let endIdx, let leaves):
                    // approach/launcher 解决到下一块：mode 取 cSecond（:233-242）
                    if (type == "Approach" || type == "Launcher"),
                       let last = leaves.last,
                       doesResolve(last, blocks[i + 1].firstLeaf) {
                        let nm = blocks[i + 1].firstLeaf.mode
                        // 对齐 Java：只改写砖自身 mode（thisBlock.setMode）；
                        // current 已在上方用旧 mode 构造，Java 不回写 current，故保持。
                        blocks[i] = .brick(name: bName, type: type, mode: nm, key: brickKey,
                                           startIdx: startIdx, endIdx: endIdx, leaves: leaves)
                    }
                }
                continue
            }
            switch blocks[i] {
            case .brick(let bName, let type, let brickMode, let brickKey,
                        let startIdx, let endIdx, let leaves):
                if current.key == brickKey && current.mode == brickMode {
                    current.startIdx = startIdx
                } else if leaves.count == 1, let last = leaves.last,
                          diatonicCheck(leaf: last, key: current.key, mode: current.mode) {
                    current.startIdx = startIdx
                } else if type == "Approach",
                          let last = leaves.last,
                          doesResolve(last, blocks[i + 1].firstLeaf) {
                    let nm = blocks[i + 1].firstLeaf.mode
                    // 砖自身 mode 同步改写（Java thisBlock.setMode）
                    blocks[i] = .brick(name: bName, type: type, mode: nm, key: brickKey,
                                       startIdx: startIdx, endIdx: endIdx, leaves: leaves)
                    // 对齐 Java：current 只吸收时长（startIdx 前移），
                    // current 自身 key/mode 保持不变（Java 无 current.setMode）。
                    current.startIdx = startIdx
                } else {
                    keymap.insert(current, at: 0)
                    current = span(from: blocks[i])
                }
            case .chord(let leaf):
                // Java Chord 分支：调内吸收，否则开新段（无主调锚定）。
                if diatonicCheck(leaf: leaf, key: current.key, mode: current.mode) {
                    current.startIdx = leaf.idx
                } else {
                    keymap.insert(current, at: 0)
                    current = span(from: blocks[i])
                }
            }
        }
        keymap.insert(current, at: 0)
        return keymap
    }
}
