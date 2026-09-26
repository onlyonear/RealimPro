import Foundation

// MARK: - KeySpan — 调性区间链 (阶段2 P1)
// 用于调性感知: 延伸音适配 / 临时转调 / 多调性平滑切换

struct KeySpan: Equatable {
    /// 区间开始 (拍数, 0-based)
    let startBeat: Double
    /// 区间结束 (拍数, exclusive)
    let endBeat: Double
    /// 主调根音 pitch class (0=C, 1=C#, ... 11=B)
    let rootPC: Int
    /// 调式 (major / minor / dominant)
    let mode: JazzMode
    /// 是否为临时转调 (secondary dominant / modal interchange)
    let isTemporary: Bool

    /// 判断一个拍数是否在此调性区间内
    func contains(beat: Double) -> Bool {
        beat >= startBeat && beat < endBeat
    }

    /// 获取此调性的延伸音偏移 (转调时调整延伸音白名单)
    var colorOffset: Int {
        isTemporary ? 0 : 0  // 临时转调不偏移, 由调用方自行适配
    }
}

// MARK: - KeySpan 工厂: 从和弦序列自动检测调性链
// 基于和弦根音+质量分析, 按小节自动切分生成 KeySpan 区间

enum KeySpanFactory {
    /// 从 ChordBlock 序列生成 KeySpan 链
    /// - Parameters:
    ///   - chords: 展平后的和弦序列
    ///   - tempo: BPM (用于拍数→时间映射)
    ///   - beatsPerMeasure: 每小节拍数 (默认4)
    /// - Returns: 调性区间链
    static func build(from chords: [ChordBlock],
                      tempo _: Int = 120,
                      beatsPerMeasure: Int = 4) -> [KeySpan] {
        guard !chords.isEmpty else { return [] }

        var spans: [KeySpan] = []
        var currentBeat: Double = 0
        var measureStartBeat: Double = 0
        var measureRoots: [Int] = []
        var measureModes: [JazzMode] = []
        var beatCount: Double = 0

        for (index, chord) in chords.enumerated() {
            let rootPC = KeySpanFactory.rootPC(from: chord.name)
            let mode = chord.findModeFromQuality()

            measureRoots.append(rootPC)
            measureModes.append(mode)
            beatCount += chord.duration

            currentBeat += chord.duration

            // 小节边界: 每 beatsPerMeasure 拍切分一个 KeySpan
            if beatCount >= Double(beatsPerMeasure) || index == chords.count - 1 {
                // 取本节最频繁的根音/调式
                let dominantRoot = mostFrequent(measureRoots) ?? 0
                let dominantMode = mostFrequent(measureModes) ?? .major

                let span = KeySpan(
                    startBeat: measureStartBeat,
                    endBeat: currentBeat,
                    rootPC: dominantRoot,
                    mode: dominantMode,
                    isTemporary: false  // 后续可基于邻域分析标记临时转调
                )
                spans.append(span)

                measureStartBeat = currentBeat
                measureRoots = []
                measureModes = []
                beatCount = 0
            }
        }

        // 合并相邻同主调的 KeySpan (平滑长时间稳定段落)
        return mergeAdjacent(spans)
    }

    // MARK: - 内部辅助

    /// 从和弦名提取根音 pitch class (0-11)
    static func rootPC(from chordName: String) -> Int {
        let rootStr = chordName.prefix { c in
            c.isLetter && c.isUppercase || c == "#" || c == "b"
        }
        switch String(rootStr) {
        case "C": return 0;   case "C#", "Db": return 1
        case "D": return 2;   case "D#", "Eb": return 3
        case "E": return 4;   case "F": return 5
        case "F#", "Gb": return 6; case "G": return 7
        case "G#", "Ab": return 8; case "A": return 9
        case "A#", "Bb": return 10; case "B": return 11
        default: return 0
        }
    }

    /// 合并相邻同主调的 KeySpan
    private static func mergeAdjacent(_ spans: [KeySpan]) -> [KeySpan] {
        guard spans.count > 1 else { return spans }
        var result: [KeySpan] = []
        var current = spans[0]
        for next in spans.dropFirst() {
            if next.rootPC == current.rootPC && next.mode == current.mode {
                current = KeySpan(
                    startBeat: current.startBeat,
                    endBeat: next.endBeat,
                    rootPC: current.rootPC,
                    mode: current.mode,
                    isTemporary: current.isTemporary
                )
            } else {
                result.append(current)
                current = next
            }
        }
        result.append(current)
        return result
    }

    /// 数组中出现最频繁的元素
    private static func mostFrequent<T: Hashable>(_ array: [T]) -> T? {
        var counts: [T: Int] = [:]
        for item in array { counts[item, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}

// MARK: - KeyMap 查询工具

extension Array where Element == KeySpan {
    /// 按拍数查找当前 KeySpan
    func keySpan(at beat: Double) -> KeySpan? {
        first { $0.contains(beat: beat) }
    }

    /// 按和弦索引查找 KeySpan (便捷)
    func keySpan(for chordIndex: Int, chordDuration: Double = 4.0) -> KeySpan? {
        keySpan(at: Double(chordIndex) * chordDuration)
    }
}
