import Foundation

// MARK: - Trading / Model / 稀疏 slot 网格
//
// M1 · 纯新增 · 自持实现（零耦合）
//
// 【与设计文档的一处偏差，已登记】
// 设计文档 §1 计划"优先转发 ThemeWeaver/MotifTransform.swift:193 的 `_SlotGrid`（internal）"。
// M1 决定**先自持实现**，理由：
//   1) `_SlotGrid` 的写入口（`setUnit`）语义面向 ThemeWeaver 的装配流程，未验证"任意 index 写入 + 休止"；
//   2) M1 要求"零风险、可独立验证"，自持实现不引入任何跨模块假设；
//   3) 接口刻意与 `_SlotGrid`/Java `Part` 对齐，M2 可平滑切换（届时以只读探针先验证 `_SlotGrid` 的写行为）。
// 该偏差不影响 M1 验收标准。

/// 稀疏 slot 网格：每个 slot 要么是"音头"（`pitch[i] != nil`），要么是"延音/空"（nil）。
///
/// 语义对齐 Java `imp.data.Part` / `MelodyPart`：
/// - 休止符 = 音头且 `pitch == -1`（`PhysicalNote.restPitch` 约定一致，`MotifTransform.swift:187-189`）
/// - `rv[i]` 表示从该音头起持续多少 slot（仅音头位有意义）
/// - `size` = 网格已铺开的 slot 数，**等于乐句总时值**
struct TradingSlotGrid {

    /// 休止音高（与 CoreEngine / ThemeWeaver 约定一致）
    static let restPitch: Int = -1

    /// 音头数组：nil = 延音/空
    private(set) var pitch: [Int?]

    /// 时值数组：仅音头位有意义
    private(set) var rv: [Int]

    var size: Int { pitch.count }
    var isEmpty: Bool { pitch.isEmpty }

    // MARK: - 构造

    init() {
        pitch = []
        rv = []
    }

    init(capacity: Int) {
        let n = max(0, capacity)
        pitch = Array(repeating: nil, count: n)
        rv = Array(repeating: 0, count: n)
    }

    // MARK: - 铺开

    private mutating func grow(to n: Int) {
        while pitch.count < n {
            pitch.append(nil)
            rv.append(0)
        }
    }

    /// 在指定 slot 写入一个音头。`slots` 为该音的持续时值。
    /// - 若该位置已有音头，则**覆盖**（并保留其原有尾部语义：不清理旧 rv 覆盖范围，由调用方保证顺序写入，
    ///   与 Java `Part.setUnit` 的做法一致）。
    mutating func setUnit(at index: Int, pitch p: Int, slots: Int) {
        guard index >= 0, slots > 0 else { return }
        grow(to: index + slots)

        // 【根因修复】新音头若落在前一个音的延音区间内，把前一个音的 rv 缩短到 index。
        // 单音线里只有 index 之前最近的音头可能延音跨过 index；不截断则它的 rv 仍指向
        // 被覆盖区间，noteList 汇总时值会超过网格实际长度（下游回应被撑成 5 小节）。
        if index < pitch.count {
            var k = index - 1
            while k >= 0 {
                if pitch[k] != nil, rv[k] > 0 {
                    if k + rv[k] > index { rv[k] = index - k }
                    break
                }
                k -= 1
            }
        }

        // 清掉被覆盖区间内的旧音头（避免出现"嵌套音头"）
        if index < pitch.count {
            let old = rv[index]
            if pitch[index] != nil, old > 0 {
                var k = index + 1
                let end = min(index + old, pitch.count)
                while k < end {
                    pitch[k] = nil
                    rv[k] = 0
                    k += 1
                }
            }
        }
        pitch[index] = p
        rv[index] = slots
    }

    /// 在网格末尾追加一个音头（顺序摆放）
    mutating func appendUnit(_ p: Int, slots: Int) {
        setUnit(at: pitch.count, pitch: p, slots: slots)
    }

    // MARK: - 查询（对齐 Java Part.getPrevIndex / unitRhythmValue）

    func getPrevIndex(_ i: Int) -> Int {
        var k = i - 1
        while k >= 0 {
            if pitch[k] != nil { return k }
            k -= 1
        }
        return -1
    }

    func getNextIndex(_ i: Int) -> Int {
        var k = i + 1
        while k < size {
            if pitch[k] != nil { return k }
            k += 1
        }
        return size
    }

    func unitRhythmValue(_ i: Int) -> Int {
        guard i >= 0, i < size, pitch[i] != nil else { return 0 }
        return getNextIndex(i) - i
    }

    /// 音头序列（按 slot 顺序）：(pitch, startSlot, durationSlots)
    /// 对应 Java `MelodyPart.getNoteList()`
    func noteList() -> [(pitch: Int, startSlot: Int, durationSlots: Int)] {
        var out: [(Int, Int, Int)] = []
        var i = 0
        while i < size {
            if let p = pitch[i] {
                out.append((p, i, rv[i]))
            }
            i += 1
        }
        return out
    }

    /// 非休止音个数
    var noteCount: Int {
        pitch.reduce(0) { acc, p in
            guard let p = p, p != Self.restPitch else { return acc }
            return acc + 1
        }
    }

    // MARK: - 导出

    /// 转为 `[(midiPitch, durationSlots)]` 的**密集**序列（对齐 `PhysicalNote` 的字段形状）。
    /// ⚠️ 本方法**不 import 任何现有类型**，只产出纯数据，供 M2 装配时再映射。
    func denseNotes() -> [(midiPitch: Int, durationSlots: Int)] {
        noteList().map { (midiPitch: $0.pitch, durationSlots: $0.durationSlots) }
    }

    /// 调试用文本：`p:slots` 序列，休止写作 `R`
    func debugText() -> String {
        noteList().map { $0.pitch == Self.restPitch ? "R:\($0.durationSlots)" : "\($0.pitch):\($0.durationSlots)" }
            .joined(separator: " ")
    }
}
