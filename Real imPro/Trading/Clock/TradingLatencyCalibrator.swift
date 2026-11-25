import Foundation

// MARK: - Trading / Clock / 延迟校准与锚点探针
//
// M1 · 纯新增 · 不依赖任何现有类型
//
// 用途一：统计"输入→落格"的偏差（录音链路质量）
// 用途二（§2.2.1）：测量 Trading 时钟锚点与现有伴奏锚点之间的偏差 Δ
//
// 对应 Java: src/imp/midi/MidiLatencyMeasurementTool.java（延迟测量工具思路）

/// 一组时间/偏差样本的统计量
struct TradingStats {
    private(set) var samples: [Double] = []

    mutating func add(_ v: Double) { samples.append(v) }
    mutating func add(contentsOf vs: [Double]) { samples.append(contentsOf: vs) }
    mutating func reset() { samples.removeAll() }

    var count: Int { samples.count }
    var isEmpty: Bool { samples.isEmpty }

    var mean: Double {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / Double(samples.count)
    }

    var median: Double {
        guard !samples.isEmpty else { return 0 }
        let s = samples.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    /// P95（线性插值）
    var p95: Double {
        guard !samples.isEmpty else { return 0 }
        let s = samples.sorted()
        if s.count == 1 { return s[0] }
        let pos = 0.95 * Double(s.count - 1)
        let lo = Int(floor(pos)), hi = Int(ceil(pos))
        let frac = pos - Double(lo)
        return s[lo] * (1 - frac) + s[hi] * frac
    }

    var maxValue: Double { samples.max() ?? 0 }
    var minValue: Double { samples.min() ?? 0 }

    var summary: String {
        guard !isEmpty else { return "（无样本）" }
        return String(format: "n=%d 中位数=%.3f 均值=%.3f P95=%.3f 最大=%.3f",
                      count, median, mean, p95, maxValue)
    }
}

/// 锚点偏差探针（§2.2.1）
///
/// 现状约束：现有 `playWithAccompaniment` 在内部自设 anchor（`JazzMidiPlayer.swift:513`），
/// 调用方**无法**传入或读取。因此只能测"**包住调用**的时间差"，得到 Δ 的**上界**。
///
/// 判定门限（用户 M1 批准函 + 设计 §2.2.1）：
///   Δ 中位数 ≤ 5 ms 且 P95 ≤ 15 ms  → 独立锚点足够，**不新增集成点**
///   否则 → 把"暴露/传入伴奏 anchor"并入集成点 #2 的 α 方法
enum TradingAnchorProbe {

    /// 判定门限
    static let medianThresholdMs: Double = 5.0
    static let p95ThresholdMs: Double = 15.0

    /// 记录一次"我们取锚点 → 调用伴奏启动 → 返回"的括号时间（纳秒）
    struct Bracket {
        let ourAnchorNs: UInt64     // 我们取锚点的时刻（紧接着调用伴奏）
        let callReturnedNs: UInt64  // 伴奏启动调用返回的时刻
        /// Δ 上界（毫秒）：伴奏锚点在 [ourAnchor, callReturned] 之间，
        /// 因此 |Δ| ≤ (callReturned − ourAnchor)，且 Δ ≥ 0（它在我们之后取）
        var deltaUpperBoundMs: Double { Double(callReturnedNs - ourAnchorNs) / 1_000_000.0 }
    }

    /// 判定结论
    enum Verdict: Equatable {
        case independentAnchorSufficient
        case needAnchorExposure
        case insufficientSamples

        var text: String {
            switch self {
            case .independentAnchorSufficient:
                return "独立锚点足够（Δ 波动在门限内）→ M2 沿用，不新增集成点"
            case .needAnchorExposure:
                return "Δ 偏大/抖动 → 需把「暴露或传入伴奏 anchor」并入集成点 #2 的 α 方法"
            case .insufficientSamples:
                return "样本不足，无法判定"
            }
        }
    }

    /// 用括号样本做判定
    static func verdict(brackets: [Bracket]) -> Verdict {
        guard brackets.count >= 3 else { return .insufficientSamples }
        var st = TradingStats()
        for b in brackets { st.add(b.deltaUpperBoundMs) }
        if st.median <= medianThresholdMs && st.p95 <= p95ThresholdMs {
            return .independentAnchorSufficient
        }
        return .needAnchorExposure
    }

    /// 生成人类可读报告
    static func report(brackets: [Bracket]) -> String {
        guard !brackets.isEmpty else { return "（无样本）" }
        var st = TradingStats()
        for b in brackets { st.add(b.deltaUpperBoundMs) }
        return """
        Δ 上界统计（毫秒，样本 \(st.count)）：\(st.summary)
        判定门限：中位数 ≤ \(medianThresholdMs)ms 且 P95 ≤ \(p95ThresholdMs)ms
        结论：\(verdict(brackets: brackets).text)
        """
    }
}
