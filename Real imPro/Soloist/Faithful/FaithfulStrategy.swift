import Foundation

/// 真复刻策略：命中后用 FaithfulSoloistGenerator 生成与 Java 理论逐音 1:1 的音符线，
/// 再交回 worker 既有的后处理/排版/切片管线；运行期未命中则静默回退 grammar。
final class FaithfulStrategy: JazzImproStrategy {
    let name: String

    private let grammar: JazzImproStrategy
    private let resource: String
    private let targetMeasures: Int
    private let faithfulBlocks: [ChordBlock]   // 保留 NC 的 blocks（grammar 回退仍用原 roadmap）

    init(grammar: JazzImproStrategy, resource: String, targetMeasures: Int,
         faithfulBlocks: [ChordBlock]) {
        self.grammar = grammar
        self.resource = resource
        self.targetMeasures = targetMeasures
        self.faithfulBlocks = faithfulBlocks
        self.name = "Faithful \(resource)"
    }

    func generateSolo(for roadmap: JazzRoadmap) -> [PhysicalNote] {
        // 系统生产种子（Int64 全范围），记录可重放；理论对拍用固定种子
        let seed = Int64.random(in: Int64.min ... Int64.max)
        FaithfulSeedLog.record(seed)

        guard let notes = FaithfulSoloistGenerator.generate(
            resource: resource,
            numMeasures: targetMeasures,
            seed: seed,
            chordBlocks: faithfulBlocks) else {
            // 运行期未命中：静默回退，调用方与用户无感（grammar 口径用原 roadmap，不受 NC 影响）
            return grammar.generateSolo(for: roadmap)
        }

        return notes.map {
            PhysicalNote(midiPitch: $0.isRest ? -1 : $0.pitch,
                         durationSlots: $0.rhythmValue)
        }
    }
}

/// 最近一次真复刻生产种子（可重放，参照 TransformEngine.lastProductionSeed）
enum FaithfulSeedLog {
    static private(set) var lastFaithfulSeed: Int64 = 0

    static func record(_ seed: Int64) {
        lastFaithfulSeed = seed
    }
}
