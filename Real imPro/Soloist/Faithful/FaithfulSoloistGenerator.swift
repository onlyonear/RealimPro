import Foundation

/// 真复刻门面（工程内）：从 Bundle 的 K3 资源生成与 Java 理论逐音 1:1 的 solo。
/// P2 阶段默认不可达——不被任何现有用户路径调用，P3 才经 SoloistIntegration 门控接入 UI。
/// 任何未命中（资源缺失 / 无此小节 outline / 数据异常）均返回 nil，由上层静默回退 grammar，绝不崩溃。
struct FaithfulNote: Equatable {
    let pitch: Int          // MIDI 音高；休止符为 -1
    let rhythmValue: Int    // 稀疏 slot 时值
    let isRest: Bool
}

enum FaithfulSoloistGenerator {

    /// 生成真复刻 solo。
    /// - Parameters:
    ///   - resource: K3 资源名（不含扩展名），对应大师文件名
    ///   - numMeasures: 目标小节数
    ///   - seed: 生产种子（同种子可重放）
    /// - Returns: 逐音结果；未命中返回 nil（上层回退 grammar）
    static func generate(resource: String, numMeasures: Int, seed: Int64,
                         chordBlocks: [ChordBlock],
                         minPitch: Int = 54, maxPitch: Int = 84) -> [FaithfulNote]? {
        do {
            // 真实和弦 -> 每小节计划（失败返回 nil 回退，不崩）
            guard let plan = FaithfulChordPlan.make(
                blocks: chordBlocks, numMeasures: numMeasures) else { return nil }
            let corpus = try K3Corpus.load(bundleResource: resource)
            // 对齐 Java generateSoloFromOutline：发声后无条件执行 mergeTies（跨小节同音合并），
            // 故 skipMergeTies=false（对拍 9/9 逐音 1:1 坐实）。
            let result = try FaithfulBuildSolo.build(
                corpus: corpus, numMeasures: numMeasures, seed: seed,
                chordPlan: plan,
                minPitch: minPitch, maxPitch: maxPitch, skipMergeTies: false)
            return result.notes.notes.map {
                FaithfulNote(pitch: $0.pitch, rhythmValue: $0.rhythmValue, isRest: $0.isRest)
            }
        } catch {
            // 资源/小节未命中或数据异常：优雅回退，不崩溃
            return nil
        }
    }

    /// 该资源是否支持指定小节数（供 P3 三态徽章判定，P2 仅提供能力，不接 UI）
    static func supportsMeasure(resource: String, numMeasures: Int) -> Bool {
        guard let corpus = try? K3Corpus.load(bundleResource: resource) else { return false }
        return corpus.outlines.contains { $0.measures == numMeasures }
    }
}
