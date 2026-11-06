import Foundation

// MARK: - Trading / Recorder / 实时录音器
//
// M1 · 纯新增 · **不依赖也不修改** 现有代码
//
// 对应 Java: src/imp/midi/MidiRecorder.java（单音线录音 + tick→slot 换算 + 双重延迟补偿）
//   · 单音线语义（新音自动收掉前音）      :210-258, 307-344
//   · 空档补休止                          :231-234
//   · 起音/时值分别吸附                    :224,241,244,331
//   · actualIndex = index − insertionOffset :299-303
//   · tickToSlots(duration) = 120 × d / resolution  :355-361（= 1 slot : 4 tick）
//
// 【M1 的明确语义（与 Java 的差异已登记）】
// 1) Java 在 note-on 时就写一个占位音，note-off 时重写为真实时值；**M1 在 note-off 才落盘**
//    （更直观、可单测；听感无关，因为落盘只影响数据不影响发声）。
// 2) 一轮结束时若仍有音未松开，按"本轮末尾"收尾（Java 无此处理，会留下无时长音）。

/// 录音器。**纯逻辑**：输入是"已换算好的 raw slot"，因此可在没有音频/没有 CoreMIDI 的环境里做真值测试。
final class TradingRecorder {

    /// 一条已落盘的录音结果
    struct RecordedNote {
        let pitch: Int
        let startSlot: Int      // 相对本轮起点
        let durationSlots: Int
        let velocity: Int
        let rawStartSlot: Int   // 吸附前（用于偏差统计）
        let deviationSlots: Int // 吸附后 − 吸附前
    }

    private(set) var recorded: [RecordedNote] = []

    private var grid = TradingSlotGrid()
    private var turnLength: Int = 0
    private var quantizer = TradingQuantizer(grid: .eighth)
    private var inputLatencySlots: Int = 0
    private var slotsPerBar: Int = TradingSettings.slotsPerBar4_4

    // 单音线状态
    private var isNotePlaying = false
    private var pendingPitch = 0
    private var pendingVelocity = 0
    private var pendingRawStart = 0
    private var pendingQuantStart = 0
    private var cursorSlot = 0        // 已落下内容的末尾（相对本轮起点）
    private var deviations: [Int] = []
    private var rawNoteCount = 0

    /// 事件缓冲：**先入队，到 finish() 时按时间排序再处理**。
    /// 原因：真实演奏/抖动会让"到达顺序"与"时间顺序"不一致；若边到边处理，
    /// 后一个音的时间戳更早时会吃掉前一个音（乐句级测试已实测到丢音）。
    private var pendingEvents: [(pitch: Int, velocity: Int, isNoteOn: Bool, rawSlot: Int)] = []

    // MARK: - 生命周期

    /// 开始一轮录音。
    /// - Parameters:
    ///   - startSlot: 本轮在整曲时间轴上的起始 slot（仅记录，用于组装）
    ///   - lengthSlots: 本轮长度
    ///   - quantizeGrid: 量化档（已拍板默认 .eighth）
    ///   - inputLatencySlots: 输入链路延迟补偿（slot）
    func begin(startSlot: Int,
               lengthSlots: Int,
               quantizeGrid: TradingQuantizeGrid = .eighth,
               inputLatencySlots: Int = 0,
               slotsPerBar: Int = TradingSettings.slotsPerBar4_4,
               adaptive: Bool = false,
               forceSwing: Bool = false) {
        self.grid = TradingSlotGrid(capacity: max(1, lengthSlots))
        self.turnLength = max(1, lengthSlots)
        self.quantizer = TradingQuantizer(grid: quantizeGrid)
        self.adaptive = adaptive
        self.forceSwing = forceSwing
        self.beatPatterns = []
        self.inputLatencySlots = max(0, inputLatencySlots)
        self.slotsPerBar = slotsPerBar
        self.currentStartSlot = startSlot
        self.isNotePlaying = false
        self.pendingPitch = 0
        self.pendingVelocity = 0
        self.pendingRawStart = 0
        self.pendingQuantStart = 0
        self.cursorSlot = 0
        self.deviations.removeAll(keepingCapacity: true)
        self.recorded.removeAll(keepingCapacity: true)
        self.pendingEvents.removeAll(keepingCapacity: true)
        self.rawNoteCount = 0
    }

    private var currentStartSlot = 0

    /// [M2-1b] 自适应网格：每拍独立选细分（关闭时走 M1 的单网格行为）
    private var adaptive = false
    /// [Swing 开关] 强制把 1~2 音拍写成普通八分
    private var forceSwing = false
    /// [M2-1b] 每拍选中的格宽（slot）；空 = 未启用
    private var beatPatterns: [[Int]] = []

    /// 当前事件应使用的格宽
    /// 本拍的格线（绝对 slot，含拍末）——半拍混合时格宽不一致，只能按界线吸附
    private func gridLines(at rawSlot: Int) -> [Int] {
        let i = max(0, min(rawSlot / TradingAdaptiveQuantizer.slotsPerBeat, beatPatterns.count - 1))
        let base = i * TradingAdaptiveQuantizer.slotsPerBeat
        var out: [Int] = []
        var acc = 0
        for w in beatPatterns[i] { out.append(base + acc); acc += w }
        out.append(base + acc)                     // 拍末 = 下一拍起点
        return out
    }

    private func smallestCell(at rawSlot: Int) -> Int {
        let i = max(0, min(rawSlot / TradingAdaptiveQuantizer.slotsPerBeat, beatPatterns.count - 1))
        return max(1, beatPatterns[i].min() ?? 60)
    }

    /// 起点吸附（round，与 M1 的 half-up 同义）
    private func snapStartAdaptive(_ raw: Int) -> Int {
        // 拍点附近 15 slot（≈62ms）内直接吸到拍点：否则三连格会把它吸到 20，
        // 使这一拍开头空出一格、谱面第一个十六分变成休止。
        let safeRaw = max(0, raw)
        let beatStart = (safeRaw / TradingAdaptiveQuantizer.slotsPerBeat) * TradingAdaptiveQuantizer.slotsPerBeat
        let intoBeat = safeRaw - beatStart
        if adaptive, !beatPatterns.isEmpty {
            // 拍点前 15 slot（≈62ms）→ 归到**下一拍**的拍点（抢拍/先现不应落到上一拍末尾）
            if intoBeat >= TradingAdaptiveQuantizer.slotsPerBeat - 15 {
                return min(beatStart + TradingAdaptiveQuantizer.slotsPerBeat, turnLength - 1)
            }
            // 拍点后 15 slot → 吸到本拍拍点
            if intoBeat <= 15 { return min(beatStart, turnLength - 1) }
        }
        guard adaptive, !beatPatterns.isEmpty else {
            let g = quantizer.gridSlots
            let v = Int((Double(raw) / Double(g)).rounded()) * g
            return min(max(0, v), turnLength - 1)
        }
        var best = raw
        var bd = Int.max
        for l in gridLines(at: raw) { let d = abs(raw - l); if d < bd { bd = d; best = l } }
        return min(max(0, best), turnLength - 1)
    }

    /// 时值取整（ceil，与 M1 同义）
    private func snapDurationAdaptive(_ dur: Int, at rawSlot: Int) -> Int {
        guard adaptive, !beatPatterns.isEmpty else {
            let g = quantizer.gridSlots
            return max(g, Int(ceil(Double(dur) / Double(g))) * g)
        }
        let g = smallestCell(at: rawSlot)
        return max(g, Int(ceil(Double(dur) / Double(g))) * g)
    }

    // MARK: - 事件入口（两个：真实链路 / 纯测试）

    /// 真实链路：用时钟把 CoreMIDI 事件的时间戳换算成 slot。
    func handle(_ event: TradingMIDIEvent, clock: TradingClock) {
        let raw = clock.slot(atNs: event.hostTimeNs)
        handleRaw(pitch: event.pitch,
                  velocity: event.velocity,
                  isNoteOn: event.isNoteOn,
                  rawSlot: raw)
    }

    /// 纯入口：直接给"相对本轮的 raw slot"（可为 Double，内部四舍五入）。
    func handleRaw(pitch: Int, velocity: Int, isNoteOn: Bool, rawSlot: Double) {
        let adjusted = rawSlot - Double(inputLatencySlots)      // 延迟补偿（Java: :299-303）
        handleRawSlot(pitch: pitch,
                      velocity: velocity,
                      isNoteOn: isNoteOn,
                      rawSlot: Int(adjusted.rounded()))
    }

    /// 纯入口（整数版）：**只入队**，到 `finish()` 时按时间排序后再处理。
    func handleRawSlot(pitch: Int, velocity: Int, isNoteOn: Bool, rawSlot: Int) {
        guard turnLength > 0 else { return }
        pendingEvents.append((pitch: pitch, velocity: velocity, isNoteOn: isNoteOn, rawSlot: rawSlot))
        if isNoteOn { rawNoteCount += 1 }
    }

    /// 按时间顺序逐个处理（原 `handleRawSlot` 的主体）
    private func processEvent(pitch: Int, velocity: Int, isNoteOn: Bool, rawSlot: Int) {
        guard turnLength > 0 else { return }
        let clampedRaw = min(max(0, rawSlot), turnLength - 1)

        if isNoteOn {
            // 1) 若上一个音还在按 → 先收掉（单音线语义）
            if isNotePlaying {
                closePending(atRawSlot: clampedRaw)
            }
            // 2) 空档补休止（对齐 Java :231-234）
            let quantStart = snapStartAdaptive(clampedRaw)
            if quantStart > cursorSlot {
                grid.setUnit(at: cursorSlot, pitch: TradingSlotGrid.restPitch, slots: quantStart - cursorSlot)
                cursorSlot = quantStart
            }
            // 3) 记下待落盘的音
            isNotePlaying = true
            pendingPitch = pitch
            pendingVelocity = velocity
            pendingRawStart = clampedRaw
            pendingQuantStart = quantStart
        } else {
            guard isNotePlaying, pitch == pendingPitch else { return }
            closePending(atRawSlot: clampedRaw)
        }
    }

    /// 收掉正在按的音，落盘到网格
    private func closePending(atRawSlot rawOff: Int) {
        guard isNotePlaying else { return }
        isNotePlaying = false

        let duration = snapDurationAdaptive(max(1, rawOff - pendingRawStart), at: pendingRawStart)
        let start = min(pendingQuantStart, max(0, turnLength - 1))
        let dur = min(duration, turnLength - start)

        grid.setUnit(at: start, pitch: pendingPitch, slots: max(1, dur))
        cursorSlot = max(cursorSlot, start + max(1, dur))

        let dev = start - pendingRawStart
        deviations.append(dev)
        recorded.append(RecordedNote(pitch: pendingPitch,
                                     startSlot: start,
                                     durationSlots: max(1, dur),
                                     velocity: pendingVelocity,
                                     rawStartSlot: pendingRawStart,
                                     deviationSlots: dev))
    }

    // MARK: - 结束本轮

    /// 结束本轮，返回用户乐句。
    /// - Parameter endRawSlot: 本轮结束时刻（相对本轮的 raw slot）；默认本轮末尾
    func finish(endRawSlot: Int? = nil) -> UserPhrase {
        // ① 先按时间排序（同一时刻 **off 先于 on**，保证前一个音先收干净）
        //    这样结果与"事件到达顺序"无关，抖动导致的乱序不会再丢音。
        let ordered = pendingEvents.sorted { a, b in
            if a.rawSlot != b.rawSlot { return a.rawSlot < b.rawSlot }
            return (a.isNoteOn ? 1 : 0) < (b.isNoteOn ? 1 : 0)
        }
        pendingEvents.removeAll(keepingCapacity: true)
        // ② 自适应网格：先按整轮事件给每一拍选细分，再逐事件处理
        if adaptive && !ordered.isEmpty {
            let onsets = ordered.filter { $0.isNoteOn }.map { min(max(0, $0.rawSlot), turnLength - 1) }.sorted()
            let offsets = ordered.filter { !$0.isNoteOn }.map { min(max(0, $0.rawSlot), turnLength - 1) }.sorted()
            beatPatterns = TradingAdaptiveQuantizer.patternsFor(onsets: onsets, offsets: offsets, turnLength: turnLength, forceSwing: forceSwing)
        }
        // ③ 再逐事件处理
        for e in ordered {
            processEvent(pitch: e.pitch, velocity: e.velocity, isNoteOn: e.isNoteOn, rawSlot: e.rawSlot)
        }

        if isNotePlaying {
            closePending(atRawSlot: endRawSlot ?? turnLength)
        }
        // 把网格补齐到本轮长度（尾部为空 = 休止）
        if cursorSlot < turnLength {
            let pad = turnLength - cursorSlot
            grid.setUnit(at: cursorSlot, pitch: TradingSlotGrid.restPitch, slots: pad)
        }
        let phrase = UserPhrase(grid: grid,
                                startSlot: currentStartSlot,
                                lengthSlots: turnLength,
                                slotsPerBar: slotsPerBar,
                                rawNoteCount: rawNoteCount,
                                deviations: deviations,
                                quantizeGrid: quantizeGridOfCurrent,
                                beatPatterns: beatPatterns)
        return phrase
    }

    private var quantizeGridOfCurrent: TradingQuantizeGrid {
        switch quantizer.gridSlots {
        case 20: return .sixteenthTriplet
        case 30: return .sixteenth
        case 60: return .eighth
        case 40: return .tripletEighth
        default: return .none
        }
    }

    /// 实时诊断：已落盘音符数
    var recordedCount: Int { recorded.count }
}
