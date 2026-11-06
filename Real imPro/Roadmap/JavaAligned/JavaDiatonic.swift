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

    /// 调内判定（PostProcessor.diatonicChordCheck 等价）。
    /// - diminished 一律放行（减和弦可作任意调的经过/导音）。
    static func diatonicCheck(leaf: JavaCYKParser.JLeaf, key: Int, mode: String) -> Bool {
        let q = quality(fromFamily: leaf.family)
        if q == .diminished { return true }
        if q == .other { return false }
        let interval = ((leaf.root - key) % 12 + 12) % 12
        guard let set = diatonicSets[mode] else { return false }
        return set[interval]?.contains(q) ?? false
    }

    // MARK: - doesResolve

    /// 属和弦 a 是否解决到 b（(a.root+5)%12 == b.root）。
    static func doesResolve(_ a: JavaCYKParser.JLeaf, _ b: JavaCYKParser.JLeaf) -> Bool {
        return a.family == "dominant" && ((b.root - a.root) % 12 + 12) % 12 == 5
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
                        blocks[i] = .brick(name: bName, type: type, mode: nm, key: brickKey,
                                           startIdx: startIdx, endIdx: endIdx, leaves: leaves)
                        current.mode = nm
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
                    current.mode = nm
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
