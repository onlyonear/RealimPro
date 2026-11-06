import Foundation

// MARK: - Trading / Recorder / 用户乐句
//
// M1 · 纯新增 · 用户乐句的容器（slot 网格 + 元数据）
//
// 对应 Java: MelodyPart（作为 `MidiRecorder.tradePart` 的落点，
//           见 src/imp/midi/MidiRecorder.java:271-274 setDestination + :283-305 setNote）

/// 用户在一轮里弹奏出的乐句。
struct UserPhrase {

    /// 网格（size = 本轮的 slot 长度，休止以 `TradingSlotGrid.restPitch` 记录）
    private(set) var grid: TradingSlotGrid

    /// 本轮起始的绝对 slot（在整曲时间轴上的位置）
    let startSlot: Int

    /// 本轮长度（slot）
    let lengthSlots: Int

    /// 每小节 slot 数（4/4 = 480）
    let slotsPerBar: Int

    /// 音符事件数（含被覆盖/合并前的原始计数，便于诊断）
    let rawNoteCount: Int

    /// 吸附偏差样本（slot，带符号），供 `TradingLatencyCalibrator` 统计
    let deviations: [Int]

    /// 量化档
    let quantizeGrid: TradingQuantizeGrid

    /// [M2-1b] 每拍实际使用的格宽（slot，60/30/40/20）；空 = 未启用自适应，按 quantizeGrid 走
    let beatPatterns: [[Int]]

    init(grid: TradingSlotGrid,
         startSlot: Int,
         lengthSlots: Int,
         slotsPerBar: Int,
         rawNoteCount: Int,
         deviations: [Int],
         quantizeGrid: TradingQuantizeGrid,
         beatPatterns: [[Int]] = []) {
        self.grid = grid
        self.startSlot = startSlot
        self.lengthSlots = lengthSlots
        self.slotsPerBar = slotsPerBar
        self.rawNoteCount = rawNoteCount
        self.deviations = deviations
        self.quantizeGrid = quantizeGrid
        self.beatPatterns = beatPatterns
    }

    var isEmpty: Bool { grid.noteCount == 0 }

    /// 音头序列（相对本轮起点的 slot）
    var notes: [(pitch: Int, startSlot: Int, durationSlots: Int)] { grid.noteList() }

    /// 是否**含休止**的地道乐句（诊断用）
    var hasRest: Bool { grid.noteList().contains { $0.pitch == TradingSlotGrid.restPitch } }

    /// 调试文本
    func debugText() -> String {
        let head = "UserPhrase @\(startSlot) len=\(lengthSlots) notes=\(grid.noteCount) grid=\(quantizeGrid.displayName)"
        return head + "\n  " + grid.debugText()
    }
}
