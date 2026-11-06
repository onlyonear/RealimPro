//
//  MotifTransform.swift
//  RealimPro
//
//  ThemeWeaver（主题发展）M0：6 个动机“纯变形”，无随机（随机选择在 Engine 里做完，
//  把“移多少/方向/倍数/拍数”当参数传入），便于 L0 与 Java 逐音对拍。
//
//  蓝本（活路径 myGenerateSolo L4890 → adjustTheme L5257；旧 generateSolo L4694 为死代码不搬）：
//    ├ Transpose → ShiftPitchesCommand  Note.shiftPitch = pitch+n（Note.java:633）
//    ├ Invert    → extractInverse       MelodyPart.java:1590（排序去重→秩镜像）
//    ├ Reverse   → extractReverse       MelodyPart.java:1542（按 slot 倒序）
//    ├ Expand    → setSize(len*n) + extractTimeWarped(1562) + altPasteOver（尾 Rest15 被 MIN 截掉）
//    ├ Side Slip → sideslip()           ThemeWeaver.java:5529（与 BarLineShift 顺序耦合）
//    └ Bar Line Shift → barLineShift()  ThemeWeaver.java:5622
//
//  Java MelodyPart 是“稀疏 slot 网格（只在音头放 Unit，延音位置为 null）”，且 setUnit 会
//  按相邻 Unit 重算时值；Swift MelodyPart 是“密集音符列表（休止 midiPitch=-1）”。
//  内部 _SlotGrid 逐位复刻 imp.data.Part/MelodyPart 的网格算法（含时值簿记），以保证逐音一致。
//

import Foundation

enum MotifTransform {

    // MARK: - 网格层（_SlotGrid 进出；权威长度=grid.size，末音 rv 允许溢出，等价 Java 稀疏 Part）
    /// 倒影（网格层）
    static func gInverted(_ g: _SlotGrid) -> _SlotGrid {
        var ordered: [Int] = []
        for p in g.pitchesInSlotOrder() where p != PhysicalNote.restPitch {
            var insertAt = ordered.count
            var found = false
            for idx in 0..<ordered.count {
                if p < ordered[idx] { insertAt = idx; found = false; break }
                if ordered[idx] == p { found = true; break }
            }
            if !found { ordered.insert(p, at: insertAt) }
        }
        let n = ordered.count
        var out = _SlotGrid()
        for (pitch, rv) in g.occupiedInOrder() {
            if pitch == PhysicalNote.restPitch { out.appendUnit(pitch, rv) }
            else if let j = ordered.firstIndex(of: pitch) { out.appendUnit(ordered[n - 1 - j], rv) }
        }
        return out
    }

    /// 逆行（网格层）
    static func gReversed(_ g: _SlotGrid) -> _SlotGrid {
        var out = _SlotGrid()
        for (pitch, rv) in g.occupiedInOrder().reversed() { out.appendUnit(pitch, rv) }
        return out
    }

    /// Expand 活路径（网格层）：setSize(len*n) 拉伸末音 → 在拉伸网格上 ×n → altPasteOver；
    /// 返回网格 size=原长×n，但末音 rv 可溢出（Java 真实 quirk）。
    static func gExpanded(_ g: _SlotGrid, by n: Int) -> _SlotGrid {
        let origLen = g.size
        var dest = g
        dest.setSize(origLen * n)
        var warped = _SlotGrid()
        for i in 0..<(origLen * n) {
            if let p = dest.pitch[i] {
                let w = dest.rv[i] * n
                if w > 0 { warped.appendUnit(p, w) }
            }
        }
        warped.appendUnit(PhysicalNote.restPitch, 15)
        dest.altPasteOver(warped, at: 0)
        assert(dest.size == origLen * n, "Expand 网格 size 必须 = 原长×n")
        return dest
    }

    /// 整体平移（网格层）：越界返回 false 且不改（对齐 ShiftPitchesCommand 回滚）
    @discardableResult
    static func gShift(_ g: inout _SlotGrid, semitones: Int,
                       minMidi: Int = 0, maxMidi: Int = 128) -> Bool {
        for i in 0..<g.size {
            if let p = g.pitch[i], p != PhysicalNote.restPitch {
                if p + semitones < minMidi || p + semitones > maxMidi { return false }
            }
        }
        g.shiftAll(semitones, startIndex: 0, stopIndex: g.size - 1, minMidi: minMidi, maxMidi: maxMidi)
        return true
    }

    /// Side Slip（网格层）
    static func gSideSlipped(_ g: _SlotGrid, originalLength: Int, semitones: Int,
                             priorBarLineShift: Bool, shiftForwardBy: Int) -> _SlotGrid {
        var grid = g
        var slipPart: _SlotGrid
        var adjusted: _SlotGrid
        let start: Int
        if priorBarLineShift {
            start = grid.size / 2 - shiftForwardBy
            slipPart = grid.extract(start, grid.size)
            adjusted = grid.extract(0, start)
            adjusted.setSize(adjusted.size)
        } else {
            slipPart = grid
            adjusted = grid
            start = grid.size
        }
        slipPart.shiftAll(semitones, startIndex: 0, stopIndex: originalLength, minMidi: 0, maxMidi: 128)
        adjusted.setSize(adjusted.size + slipPart.size)
        adjusted.pasteSlots(slipPart, at: start)
        return adjusted
    }

    /// Bar Line Shift（网格层）
    static func gBarLineShifted(_ g: _SlotGrid, numBeats: Int, baseShiftPerBeat: Int,
                                forward: Bool, priorSideSlip: Bool) -> _SlotGrid {
        let grid = g
        var secondHalf: _SlotGrid
        let start: Int
        if priorSideSlip {
            start = grid.size / 2
            secondHalf = grid.extract(start, grid.size)
        } else {
            secondHalf = grid
            start = grid.size
        }
        let shiftForwardBy = baseShiftPerBeat * numBeats
        var adjusted = grid
        if forward {
            var addRest = _SlotGrid(capacity: shiftForwardBy + start)
            addRest.pasteSlots(secondHalf, at: shiftForwardBy)
            adjusted.setSize(start + addRest.size)
            adjusted.pasteSlots(addRest, at: start)
        } else {
            let shiftBackTo = start - shiftForwardBy
            adjusted.setSize(start + secondHalf.size)
            adjusted.pasteSlots(secondHalf, at: shiftBackTo)
        }
        return adjusted
    }

    // MARK: - MelodyPart 公开包装（M0 对拍用；无溢出时 dense totalSlots==grid.size）
    static func inverted(_ m: MelodyPart) -> MelodyPart { gInverted(_SlotGrid(m)).toMelodyPart() }
    static func reversed(_ m: MelodyPart) -> MelodyPart { gReversed(_SlotGrid(m)).toMelodyPart() }

    // MARK: - ③a TimeWarp 原始变形：每音时值 ×num/denom（整除），末尾补 Rest15（=extractTimeWarped）
    static func timeWarped(_ m: MelodyPart, num: Int, denom: Int = 1) -> MelodyPart {
        precondition(num != 0 && denom != 0, "timeWarp num/denom must be nonzero")
        var out = _SlotGrid()
        for (pitch, rv) in _SlotGrid(m).occupiedInOrder() {
            let warped = (rv * num) / denom
            if warped <= 0 { continue }
            out.appendUnit(pitch, warped)
        }
        out.appendUnit(PhysicalNote.restPitch, 15)
        return out.toMelodyPart()
    }

    // MARK: - ③b Expand 活路径（MelodyPart 包装；网格层见 gExpanded）
    static func expanded(_ m: MelodyPart, by n: Int) -> MelodyPart {
        gExpanded(_SlotGrid(m), by: n).toMelodyPart()
    }

    // MARK: - ④ Shift 整体平移半音（=ShiftPitchesCommand.doShift，边界 [0,128]，越界整体作废）
    static func shifted(_ m: MelodyPart, semitones: Int,
                        minMidi: Int = 0, maxMidi: Int = 128) -> MelodyPart? {
        var g = _SlotGrid(m)
        guard gShift(&g, semitones: semitones, minMidi: minMidi, maxMidi: maxMidi) else { return nil }
        return g.toMelodyPart()
    }

    static func sideSlipped(_ m: MelodyPart,
                            originalLength: Int,
                            semitones: Int,
                            priorBarLineShift: Bool,
                            shiftForwardBy: Int) -> MelodyPart {
        gSideSlipped(_SlotGrid(m), originalLength: originalLength, semitones: semitones,
                     priorBarLineShift: priorBarLineShift, shiftForwardBy: shiftForwardBy).toMelodyPart()
    }

    static func barLineShifted(_ m: MelodyPart,
                               numBeats: Int,
                               baseShiftPerBeat: Int,
                               forward: Bool,
                               priorSideSlip: Bool) -> MelodyPart {
        gBarLineShifted(_SlotGrid(m), numBeats: numBeats, baseShiftPerBeat: baseShiftPerBeat,
                        forward: forward, priorSideSlip: priorSideSlip).toMelodyPart()
    }
}

// MARK: - PhysicalNote 休止约定（与 CoreEngine 一致：midiPitch == -1 为休止）
extension PhysicalNote {
    static let restPitch: Int = -1
}

// MARK: - _SlotGrid：稀疏 slot 网格，逐位复刻 imp.data.Part / MelodyPart 相关算法
/// 稀疏 slot 网格（对齐 Java Part/MelodyPart 的 slot 簿记）。internal 以便 ThemeWeaverEngine 复用同一套装配语义。
struct _SlotGrid {
    /// 每个 slot：nil=延音/空；非 nil=该 slot 有音头（休止用 restPitch）。rv 与 pitch 对齐。
    var pitch: [Int?]
    var rv: [Int]
    var size: Int { pitch.count }

    init() { pitch = []; rv = [] }
    init(capacity c: Int) {
        let n = max(0, c)
        pitch = Array(repeating: nil, count: n); rv = Array(repeating: 0, count: n)
    }

    /// 密集 MelodyPart → 网格：按累计时值把每个 Unit 放音头，其余 slot 为 nil
    init(_ m: MelodyPart) {
        self.init()
        var cursor = 0
        for note in m.notes {
            grow(to: cursor + note.durationSlots)
            pitch[cursor] = note.midiPitch
            rv[cursor] = note.durationSlots
            cursor += note.durationSlots
        }
    }
    private mutating func grow(to n: Int) {
        while pitch.count < n { pitch.append(nil); rv.append(0) }
    }

    // ── 顺序追加（=Part.addUnit 的顺序摆放，rv 由调用方给定）──
    mutating func appendUnit(_ p: Int, _ rhythm: Int) {
        if rhythm <= 0 { return }
        let idx = pitch.count
        grow(to: idx + rhythm)
        pitch[idx] = p; rv[idx] = rhythm
    }

    func occupiedInOrder() -> [(pitch: Int, rv: Int)] {
        var out: [(Int, Int)] = []
        for i in 0..<size where pitch[i] != nil { out.append((pitch[i]!, rv[i])) }
        return out
    }
    func pitchesInSlotOrder() -> [Int] { occupiedInOrder().map { $0.pitch } }

    // ── Part.getPrevIndex / getNextIndex / getUnitRhythmValue ──
    func getPrevIndex(_ i: Int) -> Int {
        var k = i - 1
        while k >= 0 { if pitch[k] != nil { return k }; k -= 1 }
        return -1
    }
    func getNextIndex(_ i: Int) -> Int {
        var k = i + 1
        while k < size { if pitch[k] != nil { return k }; k += 1 }
        return size
    }
    func unitRhythmValue(_ i: Int) -> Int {
        if i >= size { return 0 }
        return getNextIndex(i) - i
    }

    // ── Part.delUnit ──
    mutating func delUnit(_ i: Int) {
        if i < 0 || i >= size || pitch[i] == nil { return }
        let removed = rv[i]
        pitch[i] = nil; rv[i] = 0
        let prev = getPrevIndex(i)
        if prev >= 0 { rv[prev] += removed }
        else { setUnit(0, PhysicalNote.restPitch, removed) } // 0 号不能空（MelodyPart 分支）
    }

    // ── Part.setUnit（含相邻时值簿记）──
    mutating func setUnit(_ i: Int, _ p: Int?, _ rhythmIn: Int? = nil) {
        guard i >= 0, i < size else { return }
        if p == nil { delUnit(i); return }
        if pitch[i] == nil {
            let gap = unitRhythmValue(i)
            let prev = getPrevIndex(i)
            if prev >= 0 { rv[prev] -= gap }
            pitch[i] = p; rv[i] = gap
        } else {
            pitch[i] = p
            if let r = rhythmIn { rv[i] = r }
        }
    }

    // ── Part.setSize：截断/补 nil，最后一个 Unit 时值对齐新长度 ──
    mutating func setSize(_ newSize: Int) {
        if newSize == size { return }
        var lastIdx = -1
        if newSize < size {
            pitch = Array(pitch.prefix(newSize)); rv = Array(rv.prefix(newSize))
        } else {
            grow(to: newSize)
        }
        for i in 0..<newSize where pitch[i] != nil { lastIdx = i }
        if lastIdx >= 0 { rv[lastIdx] = newSize - lastIdx }
    }

    // ── Part.pasteSlots：逐 slot 原始覆盖（null 也清空），自动增长；末尾修正前一 Unit 时值 ──
    mutating func pasteSlots(_ other: _SlotGrid, at index: Int) {
        grow(to: index + other.size)
        for i in 0..<other.size {
            pitch[index + i] = other.pitch[i]
            rv[index + i] = other.rv[i]
        }
        var prev = getPrevIndex(index)
        if prev == -1 { prev = 0 }
        if pitch[prev] != nil { rv[prev] = unitRhythmValue(prev) }
    }

    // ── Part.pasteOver：用 setUnit 覆盖 [index, min(size,index+incoming)) ──
    mutating func pasteOver(_ other: _SlotGrid, at index: Int) {
        var limit = size
        if index + other.size < limit { limit = index + other.size }
        var i = 0
        var j = index
        while j < limit {
            if let p = other.pitch[i] { setUnit(j, p, other.rv[i]) } else { setUnit(j, nil) }
            i += 1; j += 1
        }
    }

    // ── Part.altPasteOver：原始覆盖，limit 取 MIN（不超过目标当前长度）──
    mutating func altPasteOver(_ other: _SlotGrid, at index: Int) {
        var limit = size
        if index + other.size < limit { limit = index + other.size }
        var i = 0
        var j = index
        while j < limit {
            pitch[j] = other.pitch[i]
            rv[j] = other.rv[i]
            i += 1; j += 1
        }
    }

    // ── MelodyPart.extract(first,last)：闭区间；首 slot 空则补到下一音头的休止 ──
    func extract(_ first: Int, _ last: Int) -> _SlotGrid {
        var out = _SlotGrid()
        var i = first
        if i > last { return out }
        let safeLast = min(last, size - 1)
        if first < 0 || first >= size || pitch[first] == nil {
            var k = first + 1
            while k <= safeLast { if pitch[k] != nil { break }; k += 1 }
            if k > first { out.appendUnit(PhysicalNote.restPitch, k - first) }
            i = k
        }
        while i <= safeLast {
            if let p = pitch[i] { out.appendUnit(p, rv[i]) }
            i += 1
        }
        return out
    }

    // ── ShiftPitchesCommand.doShift：区间内非休止音整体平移，任一越界则全部回滚 ──
    mutating func shiftAll(_ shift: Int, startIndex: Int, stopIndex: Int, minMidi: Int, maxMidi: Int) {
        let lo = max(0, startIndex), hi = min(stopIndex, size - 1)
        if lo > hi { return }
        var outOfBounds = false
        for i in lo...hi {
            if let p = pitch[i], p != PhysicalNote.restPitch {
                if p + shift < minMidi || p + shift > maxMidi { outOfBounds = true }
            }
        }
        if outOfBounds { return }
        for i in lo...hi {
            if let p = pitch[i], p != PhysicalNote.restPitch { pitch[i] = p + shift }
        }
    }

    /// 网格 → 密集 MelodyPart（密集规范形）：按音头顺序产出；音头之间/首尾的空 slot
    /// （拼接可能产生的静默）显式补成休止，保证密集总时值 == 网格长度，逐音可与 Java 对齐。
    func toMelodyPart() -> MelodyPart {
        var out: [PhysicalNote] = []
        var cursor = 0
        for i in 0..<size {
            guard let p = pitch[i] else { continue }
            if i > cursor { out.append(PhysicalNote(midiPitch: PhysicalNote.restPitch, durationSlots: i - cursor)) }
            // 末音 rv 允许在网格层溢出（变形保真），但发声以 size 为界（对齐 Java Part 只在 [0,size) 发声）：
            // 夹到曲尾，保证密集表示时长和恒等于 size（总时长守恒，防末音溢出把整曲拉长）。
            let dur = min(rv[i], size - i)
            out.append(PhysicalNote(midiPitch: p, durationSlots: dur))
            cursor = i + dur
        }
        if cursor < size { out.append(PhysicalNote(midiPitch: PhysicalNote.restPitch, durationSlots: size - cursor)) }
        return MelodyPart(out)
    }
}
