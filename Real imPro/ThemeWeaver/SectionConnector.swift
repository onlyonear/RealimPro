//
//  SectionConnector.swift
//  RealimPro
//
//  ThemeWeaver M3：接缝削峰 connectSections，1:1 逐字移植自 Java ThemeWeaver.java:5053-5209。
//  纯确定性、零随机。当相邻两段首尾音相差 ≥4 半音时，把 prev 尾若干音 / next 头若干音朝中间挪近。
//  三处 Java 原貌（quirk）刻意保留、不“修正”，并以 Q1/Q2/Q3 标注，G1 金标准逐音锁定：
//    Q1 两处 if(...); 空语句 → 首个 occupied 下标恒加入收集数组（即使该槽是休止）
//    Q2 next 下标收集循环上界误用 previous.size（而非 next.size）
//    Q3 prev 移位循环里误用 div1+=2（应为 div2），且重算丢符号 → div2 恒 4、prev 每音恒定移带符号的 d/4；
//       next 侧首步带符号、其后重算 d/div1 不再带符号（故方向会反），均照抄。
//

import Foundation

enum SectionConnector {

    /// 第一个被占用（pitch 非 nil，含休止）槽位；对应 Part.getFirstIndex
    private static func firstOccupied(_ g: _SlotGrid) -> Int? {
        for k in 0..<g.size where g.pitch[k] != nil { return k }
        return nil
    }
    /// i 之后第一个被占用槽（含休止），无则返回 size；对应 Part.getNextIndex
    private static func nextOccupied(_ g: _SlotGrid, _ i: Int) -> Int {
        var k = i + 1
        while k < g.size { if g.pitch[k] != nil { return k }; k += 1 }
        return g.size
    }
    private static func isPitched(_ g: _SlotGrid, _ k: Int) -> Bool {
        if let p = g.pitch[k], p != PhysicalNote.restPitch { return true }
        return false
    }
    private static func firstPitched(_ g: _SlotGrid) -> Int? {
        for k in 0..<g.size where isPitched(g, k) { return g.pitch[k] }
        return nil
    }
    private static func lastPitched(_ g: _SlotGrid) -> Int? {
        var k = g.size - 1
        while k >= 0 { if isPitched(g, k) { return g.pitch[k] }; k -= 1 }
        return nil
    }
    /// 对应 Note.shiftPitch：休止不动，其余整数半音平移
    private static func shift(_ g: inout _SlotGrid, _ k: Int, _ delta: Int) {
        guard let p = g.pitch[k], p != PhysicalNote.restPitch else { return }
        g.pitch[k] = p + delta
    }

    /// 逐字对应 Java connectSections：原地改 prev 尾/next 头后，拼接 prev+next 返回。
    static func connect(prev prevIn: _SlotGrid, next nextIn: _SlotGrid) -> _SlotGrid {
        let (prev, next) = shifted(prev: prevIn, next: nextIn)
        return concat(prev, next)
    }

    /// 只做削峰、分别返回改后的 prev / next（不拼接），供引擎按 Java L5036
    /// 把“改后 prev 尾”重贴回 prev 起点、把 next 贴到当前 i。
    static func shifted(prev prevIn: _SlotGrid, next nextIn: _SlotGrid) -> (_SlotGrid, _SlotGrid) {
        var prev = prevIn
        var next = nextIn

        // 门槛：两段都非空
        guard prev.size != 0, next.size != 0 else { return (prev, next) }
        guard let prevPitch = lastPitched(prev), let nextPitch = firstPitched(next) else { return (prev, next) }
        let difference = abs(prevPitch - nextPitch)
        guard difference >= 4 else { return (prev, next) }

        // ── 收集 prev 非休止下标（Q1：首 occupied 恒加入）──
        var previousIndices: [Int] = []
        if let fi = firstOccupied(prev) { _ = fi }   // 对齐 Java：条件判断（空语句），无副作用
        previousIndices.append(firstOccupied(prev)!)  // Q1：恒加入，即使是休止
        var pi = previousIndices.count
        while pi < prev.size {
            let ni = nextOccupied(prev, pi)
            if ni < prev.size, isPitched(prev, ni) { previousIndices.append(ni); pi = ni + 1 } else { pi += 1 }
        }

        // ── 收集 next 非休止下标 ──
        var nextIndices: [Int] = []
        nextIndices.append(firstOccupied(next)!)      // Q1：恒加入，即使是休止
        let nextInitial = nextIndices.count
        var ni2 = nextInitial
        while ni2 < prev.size {                       // Q2：上界误用 prev.size
            let nx = nextOccupied(next, ni2)
            if nx < next.size, isPitched(next, nx) { nextIndices.append(nx); ni2 = nx + 1 } else { ni2 += 1 }
        }

        var div1 = 4
        var nextMoveBy = difference / div1
        var div2 = 4
        var prevMoveBy = difference / div2
        if prevPitch > nextPitch {
            prevMoveBy = -1 * difference / div2
            nextMoveBy = difference / div1
        } else {
            prevMoveBy = difference / div2
            nextMoveBy = -1 * difference / div1
        }

        // next 从头向尾：首步带符号，之后 d/div1 重算（不再带符号——Java 原貌）
        for idx in nextIndices {
            if div1 <= abs(difference) {
                shift(&next, idx, nextMoveBy)
                div1 += 2
                nextMoveBy = difference / div1
            } else { break }
        }
        // prev 从尾向头：Q3 误用 div1+=2；div2 恒 4，prevMoveBy 重算=d/div2（方向符号在首步后同样不再重赋）。
        // quirk 补充：因循环判据用 div2（恒为 4，从不自增），而 4≤d 在 d≥4 门槛下恒真 → prev 侧永不 break，
        // 所有 prev 非休止音都会被移（与 next 侧 div1 递增到 >d 会 break 不同），此行为 1:1 保留、不修正。
        for idx in previousIndices.reversed() {
            if div2 <= abs(difference) {
                shift(&prev, idx, prevMoveBy)
                div1 += 2
                prevMoveBy = difference / div2
            } else { break }
        }

        return (prev, next)
    }

    /// solo = prev(0..) + next(prev.size..)，对应 Java 末尾两次 pasteSlots
    private static func concat(_ prev: _SlotGrid, _ next: _SlotGrid) -> _SlotGrid {
        var solo = _SlotGrid()
        solo.setSize(prev.size + next.size)
        solo.pasteSlots(prev, at: 0)
        solo.pasteSlots(next, at: prev.size)
        return solo
    }
}
