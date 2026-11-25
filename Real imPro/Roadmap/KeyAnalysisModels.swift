import Foundation

// MARK: - 调性分析数据模型 (独立模块，不侵入 GeneratedMeasure)
// 由 TonalAnalyzer.swift 迁移而来, 供 PostProcessorFull 与渲染层消费。

/// 单个和弦的调性分析结果
struct ChordAnalysis: Equatable {
    let chord: String           // 和弦名，如 "Dm7"
    let functionLabel: String   // 一级级数，如 "ii", "V", "I" (相对该和弦的调性中心)
    let tonalCenterPC: Int      // 调性中心 pitch class (0=C ... 11=B)
    let colorHex: String        // 色块颜色（不含透明度，透明度由渲染层控制）
    let beatStart: Double       // 在小节内的起始拍（0-based）
    let beatDuration: Double    // 持续拍数
}

/// 单个小节的调性分析结果
struct MeasureAnalysis: Equatable {
    let chordAnalyses: [ChordAnalysis]
}

/// 整首乐曲的调性分析结果
struct AnalysisResult: Equatable {
    let measures: [MeasureAnalysis]
}

// MARK: - 调号解析工具 (由 TonalAnalyzer.parseKey 迁移而来)

/// 调号 / 根音解析工具。
enum KeyParser {

    /// 从调号字符串解析主音 pitch class 和调式
    /// - Parameter key: 如 "C", "Dm", "Eb", "F#m"
    /// - Returns: (tonicPC, mode)
    static func parseKey(_ key: String) -> (tonicPC: Int, mode: JazzMode) {
        let rootStr = String(key.prefix { $0.isLetter && $0.isUppercase || $0 == "#" || $0 == "b" })
        let tonicPC = rootPC(from: rootStr)
        let mode: JazzMode = (key.hasSuffix("m") || key.hasSuffix("-")) ? .minor : .major
        return (tonicPC, mode)
    }

    /// 根音名 → pitch class
    static func rootPC(from rootStr: String) -> Int {
        switch rootStr {
        case "C": return 0
        case "C#", "Db": return 1
        case "D": return 2
        case "D#", "Eb": return 3
        case "E": return 4
        case "F": return 5
        case "F#", "Gb": return 6
        case "G": return 7
        case "G#", "Ab": return 8
        case "A": return 9
        case "A#", "Bb": return 10
        case "B": return 11
        default: return 0
        }
    }
}
