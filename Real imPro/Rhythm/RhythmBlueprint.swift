import Foundation

// MARK: - RhythmBlueprint — 风格律动蓝图 + 三连音概率
// 纯数据结构, 供 GrammarStrategy.generateSolo() 查询后传入 GuideTone/Generator 参数

struct RhythmBlueprint {

    // ═══════════════════════════════════════════════════════════
    // 风格律动密度表 (0.0 = 极稀长音, 1.0 = 极密)
    // ═══════════════════════════════════════════════════════════

    enum JazzStyle: String, CaseIterable {
        case bebop      // 高速比波普: 高密度+三连音
        case swing      // 摇摆中速: 中等密度
        case ballad     // 抒情慢板: 低密度+长音
        case bossa      // Bossa Nova: 中等+切分
        case latin      // Latin/Afro-Cuban: 中等偏高
        case cool       // Cool Jazz: 中低密度
        case hardBop    // Hard Bop: 高密度
        case modal      // Modal: 低密度+长音
    }

    private static let styleTable: [JazzStyle: (density: Double, tripletProb: Double, restProb: Double)] = [
        .bebop:    (0.85, 0.35, 0.05),
        .swing:    (0.55, 0.20, 0.10),
        .ballad:   (0.20, 0.05, 0.15),
        .bossa:    (0.45, 0.10, 0.08),
        .latin:    (0.60, 0.15, 0.08),
        .cool:     (0.35, 0.08, 0.12),
        .hardBop:  (0.75, 0.30, 0.06),
        .modal:    (0.25, 0.05, 0.15)
    ]

    // ═══════════════════════════════════════════════════════════
    // 查询入口
    // ═══════════════════════════════════════════════════════════

    /// 根据风格返回 (maxDuration: 最长音符slot数, tripletProbability: 三连音概率)
    static func guideToneParams(for style: JazzStyle, tempo: Int = 120) -> (maxDuration: Int, tripletProbability: Double) {
        guard let entry = styleTable[style] else {
            return (240, 0.10)  // 默认2拍=二分音符, 10%三连音
        }

        // 密度→最长音符: 密度高→音符短, 密度低→音符长
        let density = entry.density
        let maxDur: Int
        switch density {
        case ..<0.3:  maxDur = 480   // 4拍=全音符 (ballad/modal)
        case ..<0.5:  maxDur = 360   // 3拍 (cool/bossa)
        case ..<0.7:  maxDur = 240   // 2拍=二分音符 (swing/latin)
        default:      maxDur = 120   // 1拍=四分音符 (bebop/hardBop)
        }

        // tempo修正: 高速tempo缩短最长音符
        let tempoFactor = Double(tempo) / 120.0
        let adjustedMaxDur = Int(Double(maxDur) / tempoFactor)

        return (
            maxDuration: max(60, adjustedMaxDur),
            tripletProbability: entry.tripletProb
        )
    }

    /// 返回完整的风格参数元组
    static func params(for style: JazzStyle) -> (density: Double, tripletProb: Double, restProb: Double) {
        let entry = styleTable[style] ?? (0.5, 0.1, 0.1)
        return (entry.density, entry.tripletProb, entry.restProb)
    }

    /// 按tempo自动推断最接近的风格 (基于BPM范围)
    static func inferStyle(tempo: Int) -> JazzStyle {
        switch tempo {
        case ..<70:   return .ballad
        case ..<95:   return .modal
        case ..<120:  return .cool
        case ..<150:  return .swing
        case ..<190:  return .bossa
        case ..<230:  return .hardBop
        default:      return .bebop
        }
    }
}
