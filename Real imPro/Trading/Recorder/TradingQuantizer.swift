import Foundation

// MARK: - Trading / Recorder / 量化器
//
// M1 · 纯新增 · 纯函数式（无状态、可单测）
//
// 对应 Java:
//   src/imp/gui/Notate.java:23995-24003  snapRecordingSlotsToIndex / snapRecordingSlotsToDuration
//   src/imp/midi/MidiRecorder.java:224,241,244,331（三个吸附调用点）
//
// 【语义定义（M1 明确写下，M2 用真机 A/B 校准）】
// Java 的 `snapSlotsToIndex/Duration` 依赖一个 quantum 表（`getRecordingQuantizationIndex()`），
// 该表读取自 UI 对话框，源码内未见完整定义。M1 采用**最近格吸附**并给出可证明的性质：
//   |命中偏差| ≤ grid/2 （由构造保证）→ "偏差中位数 ≤ 1 格" 天然成立。

struct TradingQuantizer: Equatable {

    /// 一格多少 slot（0 或 1 表示"不量化"）
    let gridSlots: Int

    /// 最短音长（slot），默认 1 格
    let minimumSlots: Int

    init(grid: TradingQuantizeGrid) {
        if grid == .none {
            self.gridSlots = 1
            self.minimumSlots = 1
        } else {
            self.gridSlots = grid.gridSlots
            self.minimumSlots = grid.gridSlots
        }
    }

    init(gridSlots: Int, minimumSlots: Int? = nil) {
        let g = max(1, gridSlots)
        self.gridSlots = g
        self.minimumSlots = max(1, minimumSlots ?? g)
    }

    // MARK: - 吸附

    /// 起音吸附：到**最近**格
    func snapStart(_ rawSlot: Int) -> Int {
        guard gridSlots > 1 else { return rawSlot }
        let q = Double(rawSlot) / Double(gridSlots)
        return Int((q).rounded()) * gridSlots
    }

    /// 时值吸附：**向上取整（ceil）**到格的整数倍，且不小于 `minimumSlots`
    ///
    /// M2-1 对齐 Java `Notate.ceilToMultiple()`（Notate.java:24036/24110）；
    /// Java 原注释明确 "duration uses ceil where index uses round"（Notate.java:24024）。
    /// 原 M1 误用四舍五入：把"按住略久的八分"记短，随后补一个本不该有的休止，
    /// 连奏的两个音之间会被硬塞休止符（实测场景 A/B，见 M2-1 报告）。
    /// 起点 snapStart 保持无参 rounded()：实测它对正数即 half-up，与 Java Math.round 一致。
    /// 【刻意不做 Java 的"粗网格择优"】实测它在人手抖动下把三连音往直拍拽
    /// （±25ms 8/9、±50ms 丢音，且只在 20↔30/30↔40/40↔60 交界生效）；
    /// 本端硬件时间戳准（中位 4.9ms），只吸附用户选定网格。回归锁见
    /// TradingPhraseLab.runQuantizerGuards()。
    func snapDuration(_ rawSlots: Int) -> Int {
        guard gridSlots > 1 else { return max(minimumSlots, rawSlots) }
        let cells = max(1, Int((Double(rawSlots) / Double(gridSlots)).rounded(.up)))
        return max(minimumSlots, cells * gridSlots)
    }

    /// 吸附偏差（slot，带符号：吸附后 − 原始）
    func deviation(rawSlot: Int) -> Int {
        snapStart(rawSlot) - rawSlot
    }

    /// 吸附偏差（以"格"为单位，便于验收统计）
    func deviationInCells(rawSlot: Int) -> Double {
        Double(deviation(rawSlot: rawSlot)) / Double(gridSlots)
    }
}
