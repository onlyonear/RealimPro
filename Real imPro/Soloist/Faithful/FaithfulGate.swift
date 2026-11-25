import Foundation

// MARK: - 三态与回退原因（对齐施工方案 §8.2）

enum FaithfulFallbackReason: Equatable {
    case noResource                  // 该 algorithm 无 K3 资源
    case unsupportedTimeSignature    // 拍号 != 4/4（含 targetMeasures<=0）
    case mixedMeter                  // 混合拍
    case beatsMismatch               // roadmapBeats != targetMeasures×4
    case unsupportedSize             // 资源可加载，但无此小节数 outline
    case loadFailed                  // K3 资源加载失败
}

enum FaithfulGateState: Equatable {
    case disabled                                   // 灰 · Using Grammar
    case fallback(reason: FaithfulFallbackReason)   // 琥珀 · Will Use Grammar + 原因
    case hit(resource: String, measures: Int)       // 绿 · Soloist Enabled
}

struct FaithfulContext: Equatable {
    let targetMeasures: Int     // 已扣除弱起空小节
    let roadmapBeats: Double
    let timeSignature: String
    let hasMixedMeter: Bool
}

/// 资源探针结果
fileprivate enum ResourceProbe: Equatable {
    case loadFailed
    case unsupportedSize
    case hit
}

enum FaithfulSettings {
    /// 勾选状态持久化键，默认 false；与现有设置体系独立，不复用旧 soloistFeatureEnabled
    static let enabledKey = "faithfulSoloistEnabled"
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
}

enum FaithfulGate {
    static let supportedTimeSignature = "4/4"

    /// 生产装配（新）：基于用户显式选定的单个 resource 评估，UI 与 worker 共用此入口。
    /// 判定规则与 6 类回退原因完全不变，仅资源来源改为用户选定的单个 resource。
    static func evaluate(enabled: Bool,
                         resource: String,
                         context: FaithfulContext) -> FaithfulGateState {
        evaluateCore(enabled: enabled, resources: [resource], context: context,
                     probe: Self.probe)
    }

    /// 纯判定核心（与工程外 TDD 验证过的 FaithfulGateCore 同口径）
    fileprivate static func evaluateCore(enabled: Bool,
                                         resources: [String],
                                         context: FaithfulContext,
                                         probe: (String, Int) -> ResourceProbe) -> FaithfulGateState {
        guard enabled else { return .disabled }
        guard !resources.isEmpty else { return .fallback(reason: .noResource) }
        guard !context.hasMixedMeter else { return .fallback(reason: .mixedMeter) }
        guard context.timeSignature == supportedTimeSignature,
              context.targetMeasures > 0 else {
            return .fallback(reason: .unsupportedTimeSignature)
        }
        let expectedBeats = Double(context.targetMeasures) * 4.0
        guard abs(context.roadmapBeats - expectedBeats) < 1e-6 else {
            return .fallback(reason: .beatsMismatch)
        }
        for resource in resources {
            switch probe(resource, context.targetMeasures) {
            case .hit:             return .hit(resource: resource, measures: context.targetMeasures)
            case .unsupportedSize: continue
            case .loadFailed:      continue
            }
        }
        let anyLoadFailed = resources.contains {
            probe($0, context.targetMeasures) == .loadFailed
        }
        return .fallback(reason: anyLoadFailed ? .loadFailed : .unsupportedSize)
    }

    /// 真实 K3 探针：加载失败 / 无该尺寸 outline / 命中
    fileprivate static func probe(resource: String, measures: Int) -> ResourceProbe {
        guard let corpus = try? K3Corpus.load(bundleResource: resource) else { return .loadFailed }
        return corpus.outlines.contains { $0.measures == measures } ? .hit : .unsupportedSize
    }
}

// MARK: - UI 预览（从 JazzSong 计算，与 worker 非 guide 路径同口径）

enum FaithfulPreview {
    static func context(for song: JazzSong) -> FaithfulContext {
        let roadmap = JazzRoadmap(title: song.title, tempo: song.tempo)
        // 保留 NC 占位（对齐 Java 小节守恒），与 worker Faithful 路径同一口径
        for block in FaithfulChordPlan.blocksKeepingNoChord(from: song) {
            roadmap.append(block: block)
        }
        let pickup = SongMeasureMap.leadingPickupCount(song.measures)
        return FaithfulContext(
            targetMeasures: song.measures.count - pickup,
            roadmapBeats: roadmap.totalDuration,
            timeSignature: song.timeSignature,
            hasMixedMeter: song.hasMixedTimeSignature)
    }
}
