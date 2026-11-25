//
//  SoloistFirstStrategy.swift
//  Real imPro · Soloist 运行时（K2-7 生产接入）
//
//  "自动优先 / 静默回退"包装策略（对齐 Java Notate:22387 的回退精神）：
//  - 曲式命中该大师语料的白名单 → 走 soloist（大师真实乐句）
//  - 未命中 / 加载失败 / 安全层拒绝 → 静默回退 grammar，用户无感
//  - App 不提供 "Use Soloist" 勾选框（原版那个开关在本工程不存在，且原版因指纹 bug 永远失效）
//

import Foundation

final class SoloistFirstStrategy: JazzImproStrategy {
    let name: String

    private let grammar: JazzImproStrategy
    private let runtimes: [SoloistRuntime]
    private let targetMeasures: Int

    init(name: String,
         grammar: JazzImproStrategy,
         runtimes: [SoloistRuntime],
         targetMeasures: Int) {
        self.name = name
        self.grammar = grammar
        self.runtimes = runtimes
        self.targetMeasures = targetMeasures
    }

    func generateSolo(for roadmap: JazzRoadmap) -> [PhysicalNote] {
        // K2-7c：从 roadmap 按拍长累加建"slot → 和弦"表（roadmap 已剔除空/NC 弱起，天然对齐）
        let harmonicContext = SoloistHarmonicContext(roadmap: roadmap)
        for runtime in runtimes {
            let generator = SoloistMelodyGenerator(runtime: runtime)
            let runner = SoloistSafeRunner(generator: generator)
            if case .solo(let notes) = runner.run(targetMeasures: targetMeasures,
                                                  rng: SystemSoloistRNG(),
                                                  harmonicContext: harmonicContext) {
                return notes
            }
        }
        // 静默回退：soloist 未命中/失败都走这里，调用方与用户无感
        return grammar.generateSolo(for: roadmap)
    }
}

// MARK: - 装配

enum SoloistIntegration {

    /// 4/4 拍每小节 480 slot；本批 soloist 语料全部按 4/4 录制
    static let supportedTimeSignature = "4/4"

    /// 总开关（暂停期间默认关闭）：未显式启用时，所有曲式一律回退 grammar。
    /// 重新启用：UserDefaults.standard.set(true, forKey: SoloistIntegration.featureEnabledKey)
    static let featureEnabledKey = "soloistFeatureEnabled"
    static var isFeatureEnabled: Bool {
        UserDefaults.standard.bool(forKey: featureEnabledKey)
    }

    /// 有可用语料时返回"自动优先"包装策略，否则原样返回 grammar（行为与接入前完全一致）
    ///
    /// - Parameters:
    ///   - targetMeasures: 引擎需要产出的内容小节数（已扣除弱起空小节）
    ///   - roadmapBeats:    roadmap 实际总拍长。必须与 targetMeasures×4 完全一致才启用，
    ///                      保证 soloist 产出 slot 总数与既有排版/播放切分口径一致。
    static func wrapIfAvailable(grammar: JazzImproStrategy,
                                algorithm: ContentView.ImproAlgorithmType,
                                targetMeasures: Int,
                                roadmapBeats: Double,
                                timeSignature: String,
                                hasMixedMeter: Bool) -> JazzImproStrategy {
        // 总开关：暂停 soloist 期间直接回退 grammar，不进入白名单/加载逻辑
        guard isFeatureEnabled else { return grammar }

        guard !hasMixedMeter,
              timeSignature == supportedTimeSignature,
              targetMeasures > 0 else { return grammar }

        // 4/4 每小节 4 拍；roadmap 因空/NC 小节被跳过而变短时，宁可回退 grammar 也不产出错位 solo
        let expectedBeats = Double(targetMeasures) * 4.0
        guard abs(roadmapBeats - expectedBeats) < 1e-6 else { return grammar }

        var loaded: [SoloistRuntime] = []
        for basename in SoloistCorpusCatalog.resourceBasenames(for: algorithm) {
            guard let rt = SoloistRuntimeStore.runtime(basename: basename) else { continue }
            guard rt.effectiveSizes.contains(targetMeasures) else { continue }
            loaded.append(rt)
        }
        guard !loaded.isEmpty else { return grammar }

        return SoloistFirstStrategy(
            name: "\(grammar.name) + Soloist",
            grammar: grammar,
            runtimes: loaded,
            targetMeasures: targetMeasures)
    }
}
