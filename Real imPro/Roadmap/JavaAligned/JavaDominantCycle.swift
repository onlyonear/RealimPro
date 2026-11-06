//
//  JavaDominantCycle.swift
//  RealimPro
//
//  J1：从 M1 验证过的原型抽出——属→属 / 属→主「圈五链」反向传播 + 曲尾回绕。
//  对应 Java PostProcessor.findLaunchers 的 Dominant Cycle / 圈五链 / 循环回绕
//  （PostProcessor.java:440 / 489-499 / 565-579）。
//
//  前提：输入 centers 来自「干净 findKeys」（独立属和弦保留本地调，未被压扁到主调）。
//  M1 已在该前提下验证 Blues 12/12、Rhythm Changes 桥段有效，此处直接复用规则。
//

import Foundation

enum JavaDominantCycle {

    /// ii 质量类：minor(纯小) / minor7 / halfDim(iiø)。
    static func isII(_ c: PostProcessorFull.AnalysisChord) -> Bool {
        c.qualityClass == .minor || c.qualityClass == .minor7 || c.qualityClass == .halfDim
    }

    /// 在 findKeys 产出的逐和弦中心上，叠加圈五链与回绕。
    /// - Parameters:
    ///   - chords: 逐和弦分析序列（含 rootPC/qualityClass）
    ///   - centers: findKeys 产出的逐和弦中心 PC
    /// - Returns: 叠加后的逐和弦中心 PC
    static func apply(chords: [PostProcessorFull.AnalysisChord],
                      centers: [Int]) -> [Int] {
        let n = chords.count
        guard n >= 2 else { return centers }
        var jc = centers

        // ── 圈五链反向传播：当前属、下一个根音 == 当前根音+5，则当前中心取后一个中心 ──
        //   例 D7→G7(key=C)、A7→D7→G7(key=C)
        for i in stride(from: n - 2, through: 0, by: -1) {
            let c = chords[i]
            guard c.qualityClass == .dominant else { continue }
            let nx = chords[i + 1]
            guard nx.rootPC == (c.rootPC + 5) % 12 else { continue }
            // 排除 ii-V of V：前一是它的 ii（root=v+7）时它是 ii-V 的 V，不属圈链
            if i > 0, isII(chords[i - 1]),
               chords[i - 1].rootPC == (c.rootPC + 7) % 12 { continue }
            jc[i] = jc[i + 1]
        }

        // ── 曲尾回绕：最后一个属和弦按第一个块判定（Java :495-498）──
        //   圈五方向（首根==末根+5）则取「即时目标」(末根+5)，不沿整链。
        if let last = chords.last, last.qualityClass == .dominant,
           chords[0].rootPC == (last.rootPC + 5) % 12 {
            jc[n - 1] = (last.rootPC + 5) % 12
        }

        return jc
    }
}
