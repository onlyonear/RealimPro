import Foundation

// MARK: - Trading / Model / 设置与口径常量
//
// M1 · 纯新增 · 不依赖任何现有类型
// 默认值逐条抄 Java 常量（可行性报告 §4.2 已核实）

/// 量化精度档（用户已拍板：**默认 8 分格，且做成可调**）
enum TradingQuantizeGrid: String, CaseIterable, Identifiable {
    case sixteenthTriplet  // 十六分三连（20 slot）——Java quantum[] 表最细的一格
    case sixteenth      // 十六分（30 slot）
    case eighth         // 八分（60 slot）——默认
    case tripletEighth  // 八分三连（40 slot）
    case none           // 不量化（原样落格）

    var id: String { rawValue }

    /// 一格多少 slot（1 拍 = 120 slot）
    var gridSlots: Int {
        switch self {
        case .sixteenthTriplet: return 20
        case .sixteenth:     return 30
        case .eighth:        return 60
        case .tripletEighth: return 40
        case .none:          return 1
        }
    }

    var displayName: String {
        switch self {
        case .sixteenthTriplet: return "16 分三连"
        case .sixteenth:     return "16 分"
        case .eighth:        return "8 分"
        case .tripletEighth: return "三连"
        case .none:          return "不量化"
        }
    }
}

/// Trading 会话设置。
///
/// ⚠️ 用户已拍板（M1 批准函）：
/// - 量化默认 **8 分格**，可调；
/// - **Tempo / 每轮小节数在会话内锁定**（要改就停会话重开）——见 `isLockedDuringSession`。
struct TradingSettings {

    // MARK: 口径常量（对齐 Java imp/Constants.java:48,66-70）
    /// 1 拍 = 120 slot
    static let slotsPerBeat: Int = 120
    /// 4/4 一小节 = 480 slot
    static let slotsPerBar4_4: Int = 480

    // MARK: 默认值（对齐 ActiveTrading.java:89-92 / TradingDialog.java:531,567）
    /// 每轮小节数，默认 4（== trading fours）。Java: DEFAULT_TRADE_LENGTH
    var tradeBars: Int = 4
    /// 处理窗口（拍），默认 1.0。Java: TradingDialog.java:531 "Processing beats"
    var processingBeats: Double = 1.0
    /// 提前量（拍），默认 0。Java: TradingDialog.java:567 "Lead"
    var leadBeats: Double = 0.0
    /// 回应音量（百分比），默认 80。Java: DEFAULT_VOLUME
    var responseVolume: Int = 80
    /// 谁先开始，默认用户。Java: TradingDialog.java:226
    var userGoesFirst: Bool = true
    /// 数拍，默认开
    var countIn: Bool = true
    /// 循环，默认关
    var loop: Bool = false
    /// [M2-5] 实时回听（吹管即时出声），默认开。仅 Trading 会话读取；普通播放不使用。
    var monitorEnabled: Bool = true
    /// 量化档（已拍板默认 8 分）
    var quantize: TradingQuantizeGrid = .eighth

    // MARK: 延迟补偿（两个独立量，勿混；见可行性报告 §4.2）
    /// 输入链路延迟（毫秒）：由 `TradingLatencyCalibrator` 校准
    var inputLatencyMs: Double = 0
    /// 输出对齐偏差（slot）：对齐 Java ActiveTrading.java:560 的 slotDelay
    var outputLatencySlots: Int = 0

    // MARK: 派生量

    /// 每轮 slot 数
    var slotsPerTurn: Int { tradeBars * Self.slotsPerBar4_4 }

    /// 处理窗口（slot）
    var slotsForProcessing: Int {
        let v = Int((processingBeats * Double(Self.slotsPerBeat)).rounded())
        if v <= 0 { return 1 }                       // 对齐 ActiveTrading.setProcessTime 的下限保护
        if v > slotsPerTurn { return slotsPerTurn }  // 对齐上限保护（:185-191）
        return v
    }

    /// 输入延迟换算成 slot
    var inputLatencySlots: Int {
        guard inputLatencyMs > 0 else { return 0 }
        // slot = ms / (1 拍毫秒数) * 120 ；此处以 120bpm 为基准（会话内锁定 Tempo，见下）
        return max(0, Int((inputLatencyMs / 500.0 * Double(Self.slotsPerBeat)).rounded()))
    }

    /// 会话内锁定的量（用户已拍板）：非 nil 表示当前有会话在跑，禁止修改这些字段
    static func isLockedDuringSession(_ keyPath: KeyPath<TradingSettings, Int>) -> Bool {
        switch keyPath {
        case \TradingSettings.tradeBars: return true
        default: return false
        }
    }
}

/// 会话内的锁定项（用户已拍板：Tempo / 每轮小节数 会话内锁定）
enum TradingLockedParam: String, CaseIterable {
    case tempo
    case tradeBars

    var displayName: String {
        switch self {
        case .tempo:     return "Tempo"
        case .tradeBars: return "每轮小节数"
        }
    }

    /// 会话中尝试修改时的提示（不弹窗，只回传文案）
    var lockedHint: String {
        "「\(displayName)」在 Trading 会话中已锁定：请先停止 Trading，修改后重新开始。"
    }
}
