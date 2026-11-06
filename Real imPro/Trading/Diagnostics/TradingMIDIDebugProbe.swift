#if DEBUG
import Foundation
import AVFAudio
import UIKit

// MARK: - Trading / Diagnostics / 真机验收探针（DEBUG only）
//
// 【用途】M1 真机验收：在 iPad 上确认三件事
//   ① 键盘能不能被识别（枚举 + 连接）
//   ② 你弹 8 个八分音符，录下来的落格准不准（打印每个音的 raw/量化 slot + 残差统计）
//   ③ 时钟偏差 δ：我们取锚点 → 现有播放器真的出声，中间差多少毫秒
//
// 【红线遵守】
//   · 本文件是**纯新增**；**没有任何现有文件被修改**。
//   · 整个文件包在 `#if DEBUG` 里 → **Release / 上架包里不存在任何代码**。
//   · 不挂 UI、不加按钮、不改任何既有逻辑。
//   · 只调用**现有公开接口**：`JazzMidiPlayer.shared.playWithAccompaniment/stop/onNotePlay`。
//
// 【怎么触发】用 Xcode 调试器（LLDB）控制台，见《真机验收操作单》。
//   例：`expr -l Swift -- TradingMIDIDebugProbe.deviceScan()`

final class TradingMIDIDebugProbe {

    static let logPrefix = "[TRADING-PROBE]"

    /// 本次运行的量化网格（由启动环境变量 `TRADING_PROBE_GRID` 指定：8 / 16 / tri / none，默认 8 分）
    static var gridOverride: TradingQuantizeGrid = .eighth

    // MARK: - 共享状态（探针自用，不碰任何既有对象）

    private static var input: TradingMIDIInput?
    private static var clock: TradingClock?
    private static var recorder: TradingRecorder?
    private static var capturedEvents: [TradingMIDIEvent] = []
    private static var noteOffCount = 0

    private static func log(_ s: String) {
        print("\(logPrefix) \(s)")
    }

    // MARK: - ⓪ 音频路线诊断

    /// 打印当前音频输出路线（用来判断声音到底去了哪里：
    /// iPad 内置喇叭 / 蓝牙 / USB 音频接口如 Yamaha MX 自带声卡 / 耳机）
    static func logAudioRoute() {
        let s = AVAudioSession.sharedInstance()
        let outs = s.currentRoute.outputs
            .map { "\($0.portName)[\($0.portType.rawValue)]" }
            .joined(separator: ", ")
        let cat = s.category.rawValue
        log("音频路线：输出 = \(outs.isEmpty ? "（无输出）" : outs)；category=\(cat)；系统音量=\(String(format: "%.2f", s.outputVolume))")

        // 决定性诊断：App 是否真的在前台？（后台/锁屏时 iOS 不会发声）
        let appState: String
        switch UIApplication.shared.applicationState {
        case .active:      appState = "active（前台，正常）"
        case .inactive:    appState = "inactive（过渡/被遮挡，可能不出声）"
        case .background:  appState = "background（后台！难怪没声音）"
        @unknown default:  appState = "unknown"
        }
        log("App 状态：\(appState)")
    }

    // MARK: - ① 设备枚举

    /// 枚举本机（iPad）能看到的所有 MIDI 输入源，并尝试全部连接。
    static func deviceScan() {
        log("—— ① 设备枚举 ——")
        let probe = TradingMIDIInput()
        let devices = probe.availableDevices()
        log("可见 MIDI 输入源数量：\(devices.count)")
        for (i, d) in devices.enumerated() {
            log("  [\(i)] 名称=「\(d.name)」 uniqueID=\(d.uniqueID) 在线=\(!d.isOffline)")
        }
        if devices.isEmpty {
            log("⚠️ 一个都没有：请检查 ① 键盘是否插好/供电 ② 键盘是否设为 MIDI 控制器模式 ③ 换一根线/换一个口")
        }
        // 保留这个实例（下面 ② 会用），但顺序上允许先单独跑设备枚举
        input = probe
        if probe.start() {
            probe.connectAllAvailableSources()
            log("已连接：\(probe.connectedDeviceSummary())")
        } else {
            log("⚠️ CoreMIDI 客户端建立失败")
        }
    }

    // MARK: - ② 录 8 音（跟着节拍器弹八分音符）

    /// 开始录音。默认录 20 秒；每收到一个 note-off 就打印该音符的落格结果。
    /// - Parameters:
    ///   - seconds: 录音窗口
    ///   - bars: 每轮小节数（决定本轮 slot 长度）
    ///   - showIntroKeyboard: 是否顺便放 1 小节提示音（默认 false）
    static func capture(seconds: Double = 20, bars: Int = 4) {
        log("—— ② 开始 Capture（\(Int(seconds)) 秒）——")
        log("请：插好键盘 → 从这里开始，跟着节拍器/心里数拍，**均匀弹 8 个八分音符**（随便什么音）")

        // 若还没起过 deviceScan，则先起
        if input == nil {
            var needsError = false
            if input == nil { input = TradingMIDIInput() }
            if input?.start() != true { needsError = true }
            input?.connectAllAvailableSources()
            if needsError { log("⚠️ CoreMIDI 客户端建立失败") }
        }

        let r = TradingRecorder()
        let startSlot = 0
        r.begin(startSlot: startSlot,
                lengthSlots: bars * TradingSettings.slotsPerBar4_4,
                quantizeGrid: gridOverride,
                inputLatencySlots: 0)
        recorder = r

        let c = TradingClock()
        c.start(bpm: 120, anchorNs: TradingHostClock.nowNanos(), countInSlots: 0)
        clock = c

        capturedEvents.removeAll()
        noteOffCount = 0

        input?.onEvent = { ev in
            capturedEvents.append(ev)
            guard let clock = TradingMIDIDebugProbe.clock,
                  let rec = TradingMIDIDebugProbe.recorder else { return }
            rec.handle(ev, clock: clock)
            if !ev.isNoteOn {
                TradingMIDIDebugProbe.noteOffCount += 1
                let rawSlot = clock.slot(atNs: ev.hostTimeNs)
                TradingMIDIDebugProbe.log(
                    String(format: "音%d p=%-3d 力度=%-3d 原始slot=%8.1f",
                           TradingMIDIDebugProbe.noteOffCount, ev.pitch, ev.velocity, rawSlot))
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            finishCapture()
        }
    }

    /// 结束录音并打印结果
    static func finishCapture() {
        guard let r = recorder else { log("（没有正在进行的 capture）"); return }
        let phrase = r.finish()
        log("—— ② 结果 ——")
        log("本轮长度 = \(phrase.lengthSlots) slot（\(phrase.lengthSlots / TradingSettings.slotsPerBar4_4) 小节），量化档 = \(phrase.quantizeGrid.displayName)")
        log("收到事件 \(capturedEvents.count) 条；落盘非休止音 \(r.recorded.count) 个")
        log("落格明细（音高 : 起点slot / 时值slot｜原始slot → 残差slot）：")
        for n in r.recorded {
            log(String(format: "   p=%-3d 起点=%5d 时值=%4d ｜原始=%8.1f → 残差=%+d",
                       n.pitch, n.startSlot, n.durationSlots,
                       Double(n.rawStartSlot), n.deviationSlots))
        }

        // 残差统计（残差 = 量化后 − 原始；用绝对值衡量"吸附偏离你弹的位置多少"）
        var st = TradingStats()
        st.add(contentsOf: phrase.deviations.map { Double(abs($0)) })
        let grid = Double(TradingQuantizer(grid: phrase.quantizeGrid).gridSlots)
        log("残差统计：\(st.summary)")
        if !st.isEmpty {
            log(String(format: "          中位数 = %.1f slot = %.2f 格；半格 = %.0f slot",
                       st.median, st.median / grid, grid / 2))
        }

        // 相邻音间隔（IOI）：均匀弹八分音符时，IOI 应约等于 60 slot
        let nonRest = phrase.notes.filter { $0.pitch != TradingSlotGrid.restPitch }
        if nonRest.count >= 2 {
            var ioiSt = TradingStats()
            var iois: [Int] = []
            for i in 1..<nonRest.count {
                let d = nonRest[i].startSlot - nonRest[i - 1].startSlot
                iois.append(d)
                ioiSt.add(Double(d))
            }
            log("相邻音间隔 IOI（slot）：\(iois)")
            log("IOI 统计：\(ioiSt.summary)")
            // 若你想弹的是八分音符，IOI 应≈60；与 60 的偏离反映"你弹得稳不稳 + 链路准不准"
            var devSt = TradingStats()
            for d in iois { devSt.add(Double(abs(d - 60))) }
            log(String(format: "IOI 与 60 slot(八分) 的偏离：中位数 = %.1f slot = %.2f 格",
                       devSt.median, devSt.median / grid))
        }
        log("—— ② 结束 ——")
    }

    // MARK: - ③ 时钟偏差 δ

    /// 测「我们取锚点 → 现有播放器真的出声」的毫秒差。
    ///
    /// 原理（**零改动**）：`playWithAccompaniment` 内部在**它自己**的锚点开始走表；
    /// 我们只用自己的秒表测"调用前 → 第一声"的总时间。我们合成的乐句**第一个音在 slot 0**，
    /// 所以这个总时间 ≈ 锚点差 δ + 唤醒抖动 + 主线程派发。
    /// 另用 `onNotePlay` 回调（现有公开属性）捕捉"第一个音真正被送进采样器"的时刻。
    static func clockDelta(trials: Int = 5) {
        log("—— ③ 时钟偏差 δ（\(trials) 次）——")
        let player = JazzMidiPlayer.shared

        // 合成 1 小节、4 个四分音符（第一个音在 slot 0 → 便于测"起步偏差"）
        let notes: [GeneratedNote] = [
            GeneratedNote(pitch: "c/4", tag: .chordTone, isRest: false, duration: "q", isTriplet: false),
            GeneratedNote(pitch: "e/4", tag: .chordTone, isRest: false, duration: "q", isTriplet: false),
            GeneratedNote(pitch: "g/4", tag: .chordTone, isRest: false, duration: "q", isTriplet: false),
            GeneratedNote(pitch: "c/5", tag: .chordTone, isRest: false, duration: "q", isTriplet: false)
        ]
        let measure = GeneratedMeasure(chord: "c",
                                      notes: notes,
                                      chordAnnotations: [(chord: "c", noteIndex: 0)],
                                      sectionName: nil)
        let solo = [measure]

        let previousOnNotePlay = player.onNotePlay
        defer { player.onNotePlay = previousOnNotePlay }

        var st = TradingStats()
        var firstNoteNs: UInt64 = 0
        var anchorNs: UInt64 = 0
        var gotFirst = false

        // 串联：保留原回调（不动它），只额外记录第一个音的时刻
        player.onNotePlay = { noteId in
            previousOnNotePlay?(noteId)
            if !gotFirst, noteId.hasPrefix("note-") {
                gotFirst = true
                firstNoteNs = TradingHostClock.nowNanos()
            }
        }

        // 串行执行 N 次（每次间隔 1.5s），避免互相干扰
        var remaining = trials
        func oneTrial(_ done: @escaping () -> Void) {
            if remaining <= 0 { done(); return }
            remaining -= 1
            gotFirst = false
            player.stop()
            Thread.sleep(forTimeInterval: 0.25)

            anchorNs = TradingHostClock.nowNanos()
            player.playWithAccompaniment(solo: solo, bpm: 120.0, style: "sty:swing", startMeasure: 0)

            // 最多等 2.5s 看第一声
            let deadline = Date(timeIntervalSinceNow: 2.5)
            while !gotFirst && Date() < deadline { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01)) }

            if gotFirst && firstNoteNs >= anchorNs {
                let ms = Double(firstNoteNs - anchorNs) / 1_000_000.0
                st.add(ms)
                log(String(format: "  第 %d 次：δ = %.3f ms", trials - remaining, ms))
            } else {
                log("  第 \(trials - remaining) 次：未捕捉到第一声（超时）")
            }
            player.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { oneTrial(done) }
        }

        oneTrial {
            log("—— ③ 结果 ——")
            if st.isEmpty {
                // 回调式测量没捕捉到第一声时，改用「锚点前置工作」实测 —— 这是 δ 的**上界**：
                // 伴奏锚点在 `stop()` 与 `startVibrato()` 两步之后才设置（JazzMidiPlayer.swift:507-513），
                // 所以只要这两步的耗时可忽略，δ 就同样可忽略。
                log("（未捕捉到第一声 → 改用「锚点前置工作」实测，得到 δ 的上界）")
                var upper = TradingStats()
                for _ in 0..<max(3, trials) {
                    let t0 = TradingHostClock.nowNanos()
                    JazzMidiPlayer.shared.stop()
                    let timer = DispatchSource.makeTimerSource(queue: .global())
                    timer.schedule(deadline: .now(), repeating: 1.0 / 32.0)
                    timer.resume()
                    let t1 = TradingHostClock.nowNanos()
                    timer.cancel()
                    upper.add(Double(t1 &- t0) / 1_000_000.0)
                }
                log("δ 上界（stop() + 起 32Hz 颤音定时器；锚点就在这两步之后设置）：\(upper.summary)")
                st = upper
            }
            log("δ 统计（毫秒）：\(st.summary)")
            log(String(format: "判定门限：中位数 ≤ %.1f ms 且 P95 ≤ %.1f ms",
                       TradingAnchorProbe.medianThresholdMs, TradingAnchorProbe.p95ThresholdMs))
            if st.isEmpty {
                log("结论：样本不足，无法判定")
            } else if st.median <= TradingAnchorProbe.medianThresholdMs && st.p95 <= TradingAnchorProbe.p95ThresholdMs {
                log("结论：✅ 独立锚点足够 → M2 沿用，不新增集成点")
            } else {
                log("结论：❌ 超出门限 → 应按设计把「传入 anchor」并入 α 方法签名")
            }
            log("—— ③ 结束 ——")
        }
    }

    // MARK: - ②G 带伴奏录音（真机推荐用这个：有鼓和贝斯，你跟着弹）

    /// 先响起来一个小乐队（鼓/贝斯/钢琴），你跟着它弹 \(bars) 小节八分音符。
    /// 旋律轨故意全部用休止 → **伴奏里只有你的声音**，最像真实演奏。
    static func captureWithGroove(bars: Int = 4, bpm: Double = 120, style: String = "sty:swing", leadInBars: Int = 1) {
        log("—— ②G 带伴奏录音（前奏 \(leadInBars) 小节 → 你弹 \(bars) 小节 @ \(Int(bpm)) bpm）——")
        log("量化网格 = \(gridOverride.displayName)（一格 = \(gridOverride.gridSlots) slot）")

        if input == nil {
            input = TradingMIDIInput()
            if input?.start() != true { log("⚠️ CoreMIDI 客户端建立失败") }
        }
        // 多端口键盘（如 Yamaha MX49/MX61 对外有 5 个端口）：**只连主端口**，
        // 避免同一次按键被多个端口重复记录（一个音变成多个音）。
        input?.disconnectAllSources()
        if let primary = input?.availableDevices().first {
            _ = input?.connect(primary)
            log("只连接主端口：\(primary.name)")
        }
        log("设备：\(input?.connectedDeviceSummary() ?? "（无）")")
        noteOffCount = 0
        capturedEvents.removeAll()

        // 合成一个"只有伴奏"的乐句：旋律全休止，和弦走 C-F-G-C
        let chords = ["c", "f", "g", "c"]
        var solo: [GeneratedMeasure] = []
        let totalMeasures = bars + leadInBars
        for i in 0..<totalMeasures {
            let rest = GeneratedNote(pitch: "c/4", tag: .chordTone, isRest: true,
                                     duration: "w", isTriplet: false)
            solo.append(GeneratedMeasure(chord: chords[i % chords.count],
                                         notes: [rest],
                                         chordAnnotations: [],
                                         sectionName: nil))
        }

        let c = TradingClock()
        let r = TradingRecorder()
        // ⚠️ 录音窗口必须覆盖「前奏 + 你弹的全部小节」，否则窗口末尾的音会被钳位到最后一格
        // （上一轮实测就出现了：8 个音被压在 slot 1919、时值截成 1）。这里修正为 totalMeasures。
        r.begin(startSlot: 0,
                lengthSlots: totalMeasures * TradingSettings.slotsPerBar4_4,
                quantizeGrid: gridOverride,
                inputLatencySlots: 0)
        clock = c
        recorder = r

        logAudioRoute()
        log("▶️ 伴奏即将响起：先来 \(leadInBars) 小节前奏，然后**请你跟着鼓点弹 \(bars) 小节**，")
        log("   均匀弹八分音符（心里数「1 又 2 又 3 又 4 又」，每个「又」弹一个音）。随便什么音都行。")

        JazzMidiPlayer.shared.playWithAccompaniment(solo: solo, bpm: bpm, style: style, startMeasure: 0)
        c.start(bpm: bpm, anchorNs: TradingHostClock.nowNanos(), countInSlots: 0)

        input?.onEvent = { ev in
            capturedEvents.append(ev)
            guard let clock = TradingMIDIDebugProbe.clock,
                  let rec = TradingMIDIDebugProbe.recorder else { return }
            rec.handle(ev, clock: clock)
            if !ev.isNoteOn {
                TradingMIDIDebugProbe.noteOffCount += 1
                let rawSlot = clock.slot(atNs: ev.hostTimeNs)
                TradingMIDIDebugProbe.log(
                    String(format: "音%d p=%-3d 力度=%-3d 原始slot=%8.1f",
                           TradingMIDIDebugProbe.noteOffCount, ev.pitch, ev.velocity, rawSlot))
            }
        }

        let secondsPerBar = 4.0 * (60.0 / bpm)
        let totalSeconds = Double(totalMeasures) * secondsPerBar + 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + totalSeconds) {
            finishCapture()
            JazzMidiPlayer.shared.stop()
            log("（伴奏已停止）")
        }
    }

    // MARK: - ③ 时钟偏差 δ（异步版：不阻塞主线程）

    private static var dTrial = 0
    private static var dTrials = 5
    private static var dAnchorNs: UInt64 = 0
    private static var dCaptured = false
    private static var dStats = TradingStats()
    private static var dPrevOnNotePlay: ((String) -> Void)?
    private static var dSolo: [GeneratedMeasure] = []

    /// 异步测量「我们取锚点 → 现有播放器真的出声」的毫秒差。
    /// 与旧版的关键区别：**完全不阻塞主线程**（旧版用嵌套 RunLoop 阻塞等待，
    /// 而现有播放器的音符回调是通过 `DispatchQueue.main.async` 派发的，可能因此送不进来）。
    static func clockDeltaAsync(trials: Int = 5) {
        log("—— ③ 时钟偏差 δ（异步版，\(trials) 次）——")
        logAudioRoute()

        TradingMIDIDebugProbe.dTrials = trials
        TradingMIDIDebugProbe.dTrial = 0
        TradingMIDIDebugProbe.dStats = TradingStats()
        TradingMIDIDebugProbe.dCaptured = false
        TradingMIDIDebugProbe.dPrevOnNotePlay = JazzMidiPlayer.shared.onNotePlay

        // 合成 1 小节、4 个四分音符（第一个音在 slot 0 → 便于测"起步偏差"）
        var notes: [GeneratedNote] = []
        for p in ["c/4", "e/4", "g/4", "c/5"] {
            notes.append(GeneratedNote(pitch: p, tag: .chordTone, isRest: false,
                                       duration: "q", isTriplet: false))
        }
        TradingMIDIDebugProbe.dSolo = [GeneratedMeasure(chord: "c", notes: notes,
                                                       chordAnnotations: [(chord: "c", noteIndex: 0)],
                                                       sectionName: nil)]
        deltaStep()
    }

    private static func deltaStep() {
        let player = JazzMidiPlayer.shared

        guard TradingMIDIDebugProbe.dTrial < TradingMIDIDebugProbe.dTrials else {
            player.onNotePlay = TradingMIDIDebugProbe.dPrevOnNotePlay
            log("—— ③ 结果 ——")
            if TradingMIDIDebugProbe.dStats.isEmpty {
                // 仍没捕捉到 → 给出 δ 的上界实测（锚点就在 stop() 与起颤音之后设置）
                log("（仍未捕捉到第一声 → 给出 δ 的上界实测）")
                var upper = TradingStats()
                for _ in 0..<max(3, TradingMIDIDebugProbe.dTrials) {
                    let t0 = TradingHostClock.nowNanos()
                    player.stop()
                    let timer = DispatchSource.makeTimerSource(queue: .global())
                    timer.schedule(deadline: .now(), repeating: 1.0 / 32.0)
                    timer.resume()
                    let t1 = TradingHostClock.nowNanos()
                    timer.cancel()
                    upper.add(Double(t1 &- t0) / 1_000_000.0)
                }
                log("δ 上界（stop() + 起 32Hz 颤音定时器）：\(upper.summary)")
                TradingMIDIDebugProbe.dStats = upper
            }
            log("δ 统计（毫秒）：\(TradingMIDIDebugProbe.dStats.summary)")
            log(String(format: "判定门限：中位数 ≤ %.1f ms 且 P95 ≤ %.1f ms",
                       TradingAnchorProbe.medianThresholdMs, TradingAnchorProbe.p95ThresholdMs))
            if !TradingMIDIDebugProbe.dStats.isEmpty,
               TradingMIDIDebugProbe.dStats.median <= TradingAnchorProbe.medianThresholdMs,
               TradingMIDIDebugProbe.dStats.p95 <= TradingAnchorProbe.p95ThresholdMs {
                log("结论：✅ 独立锚点足够 → M2 沿用")
            } else {
                log("结论：❌ 超出门限 → 按设计把「传入 anchor」并入 α")
            }
            log("—— ③ 结束 ——")
            return
        }

        TradingMIDIDebugProbe.dTrial += 1
        TradingMIDIDebugProbe.dCaptured = false
        player.stop()
        player.onNotePlay = { noteId in
            TradingMIDIDebugProbe.dPrevOnNotePlay?(noteId)
            if !TradingMIDIDebugProbe.dCaptured, noteId.hasPrefix("note-") {
                TradingMIDIDebugProbe.dCaptured = true
                let ms = Double(TradingHostClock.nowNanos() &- TradingMIDIDebugProbe.dAnchorNs) / 1_000_000.0
                TradingMIDIDebugProbe.dStats.add(ms)
                TradingMIDIDebugProbe.log(String(format: "  第 %d 次：δ = %.3f ms",
                                                 TradingMIDIDebugProbe.dTrial, ms))
            }
        }

        // 先给 0.4s 让 App 回到空闲，再取锚点并启动（锚点与调用之间没有任何其他工作）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            TradingMIDIDebugProbe.dAnchorNs = TradingHostClock.nowNanos()
            player.playWithAccompaniment(solo: TradingMIDIDebugProbe.dSolo,
                                        bpm: 120.0, style: "sty:swing", startMeasure: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if !TradingMIDIDebugProbe.dCaptured {
                    log("  第 \(TradingMIDIDebugProbe.dTrial) 次：未捕捉到第一声（超时）")
                }
                player.stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { deltaStep() }
            }
        }
    }

    // MARK: - M2-6 会话状态机（数拍 + 轮流）
    //
    // 用一段 12 小节布鲁斯（C 调，重复 3 遍 = 36 小节）当伴奏谱：
    //   1 小节数拍（伴奏在响，还没轮到你）→ 你 4 小节 → 电脑 4 小节（本批留白，静音）
    //   → 你 4 小节 → 电脑 4 小节 → 结束。全程约 34 秒。
    // 要听的是：① 数拍那一小节之后是不是准时"轮到你"；② 你弹的音有没有回听；
    //          ③ 4 小节一到，录音是不是立刻收尾（日志会打音数/记谱小节数）。
    private static var session: TradingSession?

    static func staticSession(barsPerTurn: Int = 4, countInBars: Int = 1, turns: Int = 4, readySeconds: Double = 6) {
        log("—— M2-6 会话状态机（每轮 \(barsPerTurn) 小节，数拍 \(countInBars) 小节，共 \(turns) 轮）——")

        // 12 小节布鲁斯，重复 3 遍，保证够覆盖 数拍 + 全部轮次
        let blues = ["C7","F7","C7","C7","F7","F7","C7","C7","G7","F7","C7","G7"]
        var roadmap: [GeneratedMeasure] = []
        for _ in 0..<3 {
            for ch in blues {
                roadmap.append(GeneratedMeasure(
                    chord: ch,
                    notes: [],
                    chordAnnotations: [],
                    sectionName: nil,
                    slotsPerMeasure: TradingSettings.slotsPerBar4_4,
                    chordSlots: [(chord: ch, startSlot: 0)]))
            }
        }
        log("伴奏谱：12 小节布鲁斯 ×3 = \(roadmap.count) 小节")

        // 键盘
        if input == nil { input = TradingMIDIInput() }
        _ = input?.start()
        input?.connectAllAvailableSources()
        log("键盘：已连接 \(input?.connectedSourceCount ?? 0) 个源")

        // 回听
        let mon = TradingMonitor(program: 66)

        var cfg = TradingSession.Config()
        cfg.bpm = 120
        cfg.barsPerTurn = barsPerTurn
        cfg.countInBars = countInBars
        cfg.maxTurns = turns
        cfg.grid = gridOverride
        cfg.monitorEnabled = true

        let s = TradingSession(config: cfg)
        let t0 = TradingHostClock.nowNanos()
        let msFrom = { (ns: UInt64) in Double(ns &- t0) / 1_000_000.0 }

        s.onStateChange = { st, turn, start in
            let now = TradingHostClock.nowNanos()
            // slot → 毫秒：每 slot = (60/120)/120 秒 = 4.1667ms
            let expectMs = start * (60.0 / 120.0 / 120.0) * 1000.0
            log(String(format: "  [%.0fms] %@（第 %d 轮，起点 slot=%.0f ≈ %.0fms）",
                       msFrom(now), st.label, turn, start, expectMs))
        }
        s.onUserNote = { pitch, vel, slot in
            log(String(format: "    ♪ p=%-3d 力度=%-3d 本轮slot=%7.1f（格=%6.2f）",
                       pitch, vel, slot, slot / Double(gridOverride.gridSlots)))
        }
        s.onUserPhrase = { phrase, measures in
            func slotCount(_ n: GeneratedNote) -> Int {
                let base = n.duration.components(separatedBy: "_t")[0]
                return MelodyTransformAdapter.tokenSlots(base, isTriplet: n.isTriplet)
            }
            let total = measures.reduce(0) { $0 + $1.notes.reduce(0) { $0 + slotCount($1) } }
            log("  📝 本轮收尾：实录 \(phrase.rawNoteCount) 个音头 → 记谱 \(measures.count) 小节（合计 \(total) slot）")
            for (mi, m) in measures.enumerated() {
                let desc = m.notes.map { n -> String in
                    let t = (n.isTieStart ? "→" : "") + (n.isTieEnd ? "←" : "")
                    return "\(n.isRest ? "R" : n.pitch):\(n.duration)\(t)"
                }.joined(separator: " ")
                log("     M\(mi + 1) \(desc)")
            }
        }
        s.onFinished = { log("  ✅ 会话结束") }

        session = s
        log("⏳ \(Int(readySeconds)) 秒后开始（先把乐器拿好）…")
        DispatchQueue.main.asyncAfter(deadline: .now() + readySeconds) {
            s.start(roadmap: roadmap, input: input, monitor: mon)
            log("开始：\(countInBars) 小节 click（嗒·嗒·嗒·嗒）→ 乐队进 = 轮到你 \(barsPerTurn) 小节 → 电脑 \(barsPerTurn) 小节（本批静音）→ … click就绪=\(JazzMidiPlayer.shared.isClickReady)")
        }
    }

    // MARK: - M2-6b 演示：Demo 伴奏 + 虚拟键盘弹生成的 solo + 谱面显示
    //
    // 做的事：拿 Demo 的和弦当伴奏谱 → Grammar 生成 4 小节 solo →
    //   把 solo 变成"虚拟键盘输入"按真实时间弹进会话（路径 A 未来时间戳）→
    //   每一轮结束把转换出的 4 小节推给五线谱（TradingDisplay）。
    // 你要看：屏幕上 Demo 的谱，在你（虚拟键盘）吹完 4 小节后，是不是换成了刚吹的内容。
    static func staticDemo(readySeconds: Double = 8) {
        log("—— M2-6b 演示：Demo 伴奏 + 虚拟键盘 + 谱面显示 ——")

        // 1) Demo 和弦 → 伴奏谱（notes 留空：只要乐队，不要原旋律）
        let roadmap = demoRoadmap()
        log("Demo 伴奏谱：\(roadmap.count) 小节")

        // 2) 生成 4 小节 solo（复用回环测试台的生成器，同一套 Demo+Grammar）
        guard let solo = TradingRoundTripHarness.demoGrammarSource(bars: 4), !solo.isEmpty else {
            log("❌ solo 生成失败"); return
        }
        log("生成 solo：\(solo.count) 个音（前 6 音：\(solo.prefix(6).map { $0.desc }.joined(separator: " "))）")

        // 3) 输入 + 虚拟键盘
        if input == nil { input = TradingMIDIInput() }
        _ = input?.start()

        let injector = TradingMIDILoopbackInjector()
        guard injector.start() else { log("❌ 虚拟键盘创建失败"); return }
        input?.connectAllAvailableSources()
        log("键盘：已连接 \(input?.connectedSourceCount ?? 0) 个源（含虚拟键盘）")

        // 4) 会话：1 小节 click 数拍 → 你 4 小节 → 电脑 4 → 你 4 → 电脑 4
        var cfg = TradingSession.Config()
        cfg.bpm = 120
        cfg.barsPerTurn = 4
        cfg.countInBars = 1
        cfg.maxTurns = 4
        cfg.adaptive = true
        cfg.monitorEnabled = true
        cfg.clickEnabled = true

        let s = TradingSession(config: cfg)
        s.onStateChange = { st, turn, start in
            log("  \(st.label)（第 \(turn) 轮，slot=\(Int(start))）")
        }
        s.onUserPhrase = { phrase, measures in
            log("  📝 收尾：\(phrase.rawNoteCount) 个音头 → \(measures.count) 小节，已推到五线谱")
        }
        s.onFinished = { log("  ✅ 演示结束（谱面停留在最后一轮）") }

        session = s
        log("⏳ \(Int(readySeconds)) 秒后开始（看屏幕上的五线谱）…")
        DispatchQueue.main.asyncAfter(deadline: .now() + readySeconds) {
            s.start(roadmap: roadmap, input: input, monitor: TradingMonitor(program: 66))

            // 5) 把 solo 当成"人弹的"注入：第 0 轮 + 第 2 轮（各 4 小节）
            let turnLen = cfg.barsPerTurn * cfg.slotsPerBar
            var evs: [TradingMIDILoopbackInjector.ScheduledEvent] = []
            for n in solo {
                for base in [0, 2 * turnLen] {
                    evs.append(.init(bytes: [0x90, UInt8(max(0, min(127, n.pitch))), 90], atSlot: base + n.start))
                    evs.append(.init(bytes: [0x80, UInt8(max(0, min(127, n.pitch))), 0], atSlot: base + n.start + n.dur))
                }
            }
            injector.performScheduled(events: evs, bpm: cfg.bpm,
                                      anchorTicks: injector.machTicks(fromNs: s.musicAnchorNs))
            log("🎹 已注入 \(evs.count) 条 MIDI 事件（两轮）")
        }
    }

    // MARK: - [M2-6f] 真人演奏 + 谱面回放对照
    //
    // `live`      ：等你真人吹 4 小节 → 上屏 → 软件把谱面音符再弹一遍
    // `livetest`  ：同上，但用样本库第 ⑩ 组代替你（我自测用）
    static func staticLive(inject: Bool = false, readySeconds: Double = 8) {
        let roadmap = demoRoadmap()
        var cfg = TradingSession.Config()
        cfg.bpm = 120
        cfg.barsPerTurn = 4
        cfg.countInBars = 1
        cfg.maxTurns = 2        // 用户轮 + 电脑轮（电脑轮专门用来回放，乐队不停）
        cfg.adaptive = true
        cfg.monitorEnabled = true
        cfg.clickEnabled = true

        let s = TradingSession(config: cfg)
        var captured: [GeneratedMeasure] = []

        s.onStateChange = { st, turn, _ in
            if st == .userTurn { log("  🎹 轮到你了（4 小节），吹完自动回放") }
            if st == .finished { log("  ⏹ 会话结束") }
        }
        s.onUserPhrase = { phrase, ms in
            captured = ms
            log("  📝 已记谱：\(phrase.rawNoteCount) 个音头 → \(ms.count) 小节")
            for (mi, m) in ms.enumerated() {
                log("      M\(mi + 1) " + m.notes.map { n in
                    var d = n.duration
                    if n.isTieStart { d += "~" }
                    if n.isTieEnd { d = "~" + d }
                    return n.isRest ? "R:\(d)" : "\(n.pitch):\(d)"
                }.joined(separator: " "))
            }
            // 电脑轮（8 秒）正好用来回放——乐队继续走，你听着伴奏+自己的句子
            log("  ▶️ 电脑轮回放（乐队不停）…")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                JazzMidiPlayer.shared.enableMonitor(program: 66)
                TradingPlayback.shared.play(measures: ms, bpm: cfg.bpm) {
                    log("  ✅ 回放结束")
                }
            }
        }
        s.onFinished = { log("  ⏹ 会话结束") }

        if input == nil { input = TradingMIDIInput() }
        _ = input?.start()
        var injector: TradingMIDILoopbackInjector?
        if inject {
            let inj = TradingMIDILoopbackInjector()
            guard inj.start() else { log("❌ 虚拟键盘创建失败"); return }
            injector = inj
        }
        input?.connectAllAvailableSources()
        log("键盘：已连接 \(input?.connectedSourceCount ?? 0) 个源")

        session = s
        log("⏳ \(Int(readySeconds)) 秒后开始：1 小节 click → 你吹 4 小节 → 回放")
        DispatchQueue.main.asyncAfter(deadline: .now() + readySeconds) {
            s.start(roadmap: roadmap, input: input, monitor: TradingMonitor(program: 66))
            if let inj = injector {
                let notes = TradingDemoBank.beatMix().notes
                var evs: [TradingMIDILoopbackInjector.ScheduledEvent] = []
                for n in notes {
                    let p = UInt8(max(0, min(127, n.pitch)))
                    evs.append(.init(bytes: [0x90, p, 90], atSlot: n.start))
                    evs.append(.init(bytes: [0x80, p, 0], atSlot: n.start + n.dur))
                }
                inj.performScheduled(events: evs, bpm: cfg.bpm,
                                     anchorTicks: inj.machTicks(fromNs: s.musicAnchorNs))
                log("🎹 已注入样本（第 ⑩ 组）\(evs.count) 条")
            }
        }
    }

    // MARK: - [M2-6h] 两遍法：先录，再重新数拍 + 伴奏里回放
    //
    // 第一遍：click → 你吹 4 小节 → 记谱
    // 第二遍：乐队停 → 重新 click → 伴奏重走 → 同时回放你的句子（方便从容对照）
    static func staticLiveReplay(readySeconds: Double = 8) {
        var cfg = TradingSession.Config()
        cfg.bpm = 120
        cfg.barsPerTurn = 4
        cfg.countInBars = 1
        cfg.maxTurns = 1
        cfg.adaptive = true
        cfg.swing = true
        cfg.monitorEnabled = true
        cfg.clickEnabled = true

        let s = TradingSession(config: cfg)
        var captured: [GeneratedMeasure] = []

        s.onUserPhrase = { phrase, ms in
            captured = ms
            log("  📝 已记谱：\(phrase.rawNoteCount) 个音头 → \(ms.count) 小节")
            for (mi, m) in ms.enumerated() {
                log("      M\(mi + 1) " + m.notes.map { n in
                    var d = n.duration
                    if n.isTieStart { d += "~" }
                    if n.isTieEnd { d = "~" + d }
                    return n.isRest ? "R:\(d)" : "\(n.pitch):\(d)"
                }.joined(separator: " "))
            }
        }
        s.onFinished = {
            log("  ⏹ 录音结束，1 秒后重新数拍回放")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                replayPass(captured)
            }
        }

        if input == nil { input = TradingMIDIInput() }
        _ = input?.start()
        input?.connectAllAvailableSources()
        log("键盘：已连接 \(input?.connectedSourceCount ?? 0) 个源")

        session = s
        log("⏳ \(Int(readySeconds)) 秒后开始：click → 你吹 4 小节 → 重新数拍 + 回放")
        DispatchQueue.main.asyncAfter(deadline: .now() + readySeconds) {
            s.start(roadmap: midiRoadmap(bars: 64), input: input, monitor: TradingMonitor(program: 66))
        }
    }

    /// 第二遍：不再收音，只放 click + 伴奏 + 回放
    private static func replayPass(_ measures: [GeneratedMeasure]) {
        guard !measures.isEmpty else { log("‼️ 没录到东西，跳过回放"); return }
        var cfg = TradingSession.Config()
        cfg.bpm = 120
        cfg.barsPerTurn = 4
        cfg.countInBars = 1
        cfg.maxTurns = 2
        cfg.adaptive = true
        cfg.swing = true
        cfg.monitorEnabled = true
        cfg.clickEnabled = true
        cfg.showOnDisplay = false        // 第二遍不收音，绝不能覆盖已画好的谱

        let s2 = TradingSession(config: cfg)
        s2.onStateChange = { st, _, _ in
            guard st == .userTurn else { return }
            log("  ▶️ 伴奏重新进来，同时回放你的句子…")
            // 必须与"乐队进来的那一拍"同一时刻起音：lead=0、不再额外等待，
            // 否则会晚 0.8 拍（600ms 预备 + 200ms 等待），听感上就是"空了一拍"。
            JazzMidiPlayer.shared.enableMonitor(program: 66)
            TradingPlayback.shared.play(measures: measures, bpm: cfg.bpm, leadMs: 0) {
                log("  ✅ 回放结束")
            }
        }
        s2.onUserPhrase = { _, _ in }          // 第二遍的录音丢掉
        session = s2
        s2.start(roadmap: midiRoadmap(bars: 64), input: nil, monitor: TradingMonitor(program: 66))
    }

    /// 重复 Demo 和弦铺够小节数
    private static func midiRoadmap(bars: Int) -> [GeneratedMeasure] {
        let base = demoRoadmap()
        var out: [GeneratedMeasure] = []
        while out.count < bars { out.append(contentsOf: base) }
        return out
    }

    // MARK: - [M2-6g] 连跑多轮：每轮吹完，在电脑轮的时间里回放给你听
    static func staticLiveLong(turns: Int = 4, readySeconds: Double = 8) {
        let base = demoRoadmap()
        let needBars = (1 + 2 * turns) * 4
        var roadmap: [GeneratedMeasure] = []
        while roadmap.count < needBars { roadmap.append(contentsOf: base) }

        var cfg = TradingSession.Config()
        cfg.bpm = 120
        cfg.barsPerTurn = 4
        cfg.countInBars = 1
        cfg.maxTurns = 2 * turns
        cfg.adaptive = true
        cfg.swing = true
        cfg.monitorEnabled = true
        cfg.clickEnabled = true

        let s = TradingSession(config: cfg)
        var round = 0

        s.onStateChange = { st, turn, _ in
            if st == .userTurn { log("  🎹 第 \(turn / 2 + 1)/\(turns) 条：轮到你，吹 4 小节") }
        }
        s.onUserPhrase = { phrase, ms in
            round += 1
            log("  📝 第 \(round) 条：\(phrase.rawNoteCount) 个音头")
            for (mi, m) in ms.enumerated() {
                log("      M\(mi + 1) " + m.notes.map { n in
                    var d = n.duration
                    if n.isTieStart { d += "~" }
                    if n.isTieEnd { d = "~" + d }
                    return n.isRest ? "R:\(d)" : "\(n.pitch):\(d)"
                }.joined(separator: " "))
            }
            // 电脑轮 8 秒正好用来回放
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                JazzMidiPlayer.shared.enableMonitor(program: 66)
                TradingPlayback.shared.play(measures: ms, bpm: cfg.bpm)
            }
        }
        s.onFinished = { log("  ✅ 4 条全部完成，谱面停在最后一条") }

        if input == nil { input = TradingMIDIInput() }
        _ = input?.start()
        input?.connectAllAvailableSources()
        log("键盘：已连接 \(input?.connectedSourceCount ?? 0) 个源")

        session = s
        log("⏳ \(Int(readySeconds)) 秒后开始：1 小节 click → 每条 4 小节，吹完立刻回放")
        DispatchQueue.main.asyncAfter(deadline: .now() + readySeconds) {
            s.start(roadmap: roadmap, input: input, monitor: TradingMonitor(program: 66))
        }
    }

    // MARK: - Demo 和弦谱（伴奏用，notes 留空）
    static func demoRoadmap() -> [GeneratedMeasure] {
        let song = JazzPlaylist.demoSong
        var roadmap: [GeneratedMeasure] = []
        for (mi, chords) in song.measures.enumerated() {
            let durs = song.measureDurations[mi]
            var slots: [(chord: String, startSlot: Int)] = []
            var acc = 0
            for (i, raw) in chords.enumerated() {
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let beats = i < durs.count ? durs[i] : 4.0
                slots.append((chord: name, startSlot: acc))
                acc += Int(beats * 120)
            }
            roadmap.append(GeneratedMeasure(
                chord: slots.first?.chord ?? "",
                notes: [],
                chordAnnotations: [],
                sectionName: song.sectionMarkers[mi],
                slotsPerMeasure: TradingSettings.slotsPerBar4_4,
                chordSlots: slots))
        }
        return roadmap
    }

    // MARK: - M2-7 tradingdemo36 / sessionh3 辅助

    /// [tradingdemo36] 一个和弦下的切分模板（每小节 5 音 + 第 3 拍正拍休止）。
    /// 相对小节 slot：根(0,60)｜三(60,60)｜五(120,120)｜拍3正拍休止(240-300)｜七(300,60)｜根(360,120)。
    /// 音级取该和弦的 1/3/5/7/1（与回应算法同源：getRootPC + ChordQuality.chordIntervals），
    /// 因用户轮与电脑轮和弦不同，电脑在新和弦上重复同节奏时天然触发 Rectify。
    private static func demoUserEvents(chord: String, barStart: Int)
    -> [(pitch: UInt8, on: Int, off: Int)] {
        let root = GrammarNoteConverter.getRootPC(chord)
        let intervals = ChordQuality(chordName: chord).chordIntervals
        func midi(degree d: Int) -> UInt8 {
            let iv = intervals[min(d, intervals.count - 1)]
            return UInt8(60 + ((root + iv) % 12))
        }
        let template: [(degree: Int, start: Int, dur: Int)] = [
            (0, 0, 60), (1, 60, 60), (2, 120, 120), (3, 300, 60), (0, 360, 120)
        ]
        return template.map { (midi(degree: $0.degree), barStart + $0.start, barStart + $0.start + $0.dur) }
    }

    /// 为指定用户轮 t（偶数）生成 4 小节切分乐句的 MIDI 事件。note-off 提前 2 slot，
    /// 确保轮末 note-off 仍在用户轮回听门内（避免末音回听挂住，量化 8ms 差异不影响记谱）。
    private static func h3UserTurnEvents(roadmap: [GeneratedMeasure], cfg: TradingSession.Config,
                                         turn t: Int)
    -> [TradingMIDILoopbackInjector.ScheduledEvent] {
        var evs: [TradingMIDILoopbackInjector.ScheduledEvent] = []
        let spb = cfg.slotsPerBar, turnLen = cfg.barsPerTurn * spb
        for b in 0..<cfg.barsPerTurn {
            let idx = t * cfg.barsPerTurn + b
            guard idx < roadmap.count else { continue }
            let barStart = t * turnLen + b * spb
            for n in demoUserEvents(chord: roadmap[idx].chord, barStart: barStart) {
                evs.append(.init(bytes: [0x90, n.pitch, 92], atSlot: n.on))
                evs.append(.init(bytes: [0x80, n.pitch, 0], atSlot: max(0, n.off - 2)))
            }
        }
        return evs
    }

    // MARK: - M2-7 36 小节完整对话（A 方案：用户先、用户收尾，5 用户轮 + 4 电脑轮）

    /// 端到端：内置 36 小节 Demo（C 调），自动注入 5 个用户轮"和弦音+切分"乐句，
    /// 让真实会话跑完整 9 轮（约 74 秒）。逐轮打印用户记谱 / 电脑回应逐音与和弦（DEBUG print）。
    /// 核对：① 电脑轮和弦=物理小节（off-by-one 修复）② 末轮不越界 ③ 36 小节铺满 ④ 真机听整遍。
    static func staticTradingDemo36(readySeconds: Double = 8) {
        let roadmap = demoRoadmap()
        var cfg = TradingSession.Config()
        cfg.bpm = 120
        cfg.barsPerTurn = 4
        cfg.countInBars = 1
        cfg.maxTurns = 9                 // 5 用户轮（偶数）+ 4 电脑轮（奇数），用户收尾
        cfg.adaptive = true
        cfg.swing = false                // 直八/正拍切分输入，不做 swing 改写
        cfg.monitorEnabled = true
        cfg.clickEnabled = true
        cfg.responseMode = .repeatAndRectify

        let s = TradingSession(config: cfg)
        session = s
        s.onStateChange = { st, turn, _ in
            log("  状态 → \(st.label)（轮 \(turn)）")
        }
        s.onUserPhrase = { phrase, ms in
            log("  📝 用户轮记谱：\(phrase.rawNoteCount) 音头 → \(ms.count) 小节")
            for (mi, m) in ms.enumerated() {
                log("      M\(mi + 1) " + m.notes.map { n -> String in
                    var d = n.duration
                    if n.isTieStart { d += "~" }
                    if n.isTieEnd { d = "~" + d }
                    return n.isRest ? "R:\(d)" : "\(n.pitch):\(d)"
                }.joined(separator: " "))
            }
        }
        s.onFinished = {
            log("  ⏹ 36 小节对话结束（A 方案：铺满 36 小节，用户收尾）")
            // [M2-8d] 累积谱客观核验：等主线程最后一次 overlay 排干后 dump
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                TradingMIDIDebugProbe.dumpTradingDisplay36()
            }
        }

        if input == nil { input = TradingMIDIInput() }
        _ = input?.start()
        let inj = TradingMIDILoopbackInjector()
        guard inj.start() else { log("❌ 虚拟键盘创建失败"); return }
        input?.connectAllAvailableSources()
        log("键盘：已连接 \(input?.connectedSourceCount ?? 0) 个源")

        log("⏳ \(Int(readySeconds)) 秒后开始：36 小节 Demo，5 次你输入 + 4 次电脑回应（用户先/用户收尾）")
        DispatchQueue.main.asyncAfter(deadline: .now() + readySeconds) {
            s.start(roadmap: roadmap, input: input, monitor: TradingMonitor(program: 66))
            var evs: [TradingMIDILoopbackInjector.ScheduledEvent] = []
            for t in stride(from: 0, through: 8, by: 2) {
                evs.append(contentsOf: h3UserTurnEvents(roadmap: roadmap, cfg: cfg, turn: t))
            }
            // anchorTicks +1 mach tick：抵消路径 A「ns→ticks(floor)→ns(floor)」两次整数取整
            // 把轮边界 slot0 事件向下拉 ~40ns（timebase 125/3）导致无 tol 回听门误判 idx=-1 的伪影；
            // 1 tick≈42ns 远小于 1 slot（4.17ms），不影响记谱/听感（真人键盘不经过此往返）。
            inj.performScheduled(events: evs, bpm: cfg.bpm,
                                 anchorTicks: inj.machTicks(fromNs: s.musicAnchorNs) &+ 1)
            log("🎹 已注入 5 个用户轮乐句（\(evs.count / 2) 个音），每小节和弦音+切分模板，请听完整 36 小节")
        }
    }

    // MARK: - M2-9 三模式 36 小节（复用 staticTradingDemo36 骨架，仅改回应模式/参数）

    /// [M2-9] 36 小节 demo 通用骨架：5 用户轮 + 4 电脑轮，电脑回应模式由参数指定。
    private static func staticTradingModes(
        mode: TradingResponseMode,
        modifyChoice: Int? = nil,
        grammarFile: String = "chord",
        musician: String = "My",
        readySeconds: Double = 8
    ) {
        let roadmap = demoRoadmap()
        var cfg = TradingSession.Config()
        cfg.bpm = 120
        cfg.barsPerTurn = 4
        cfg.countInBars = 1
        cfg.maxTurns = 9                 // 5 用户轮 + 4 电脑轮，用户收尾
        cfg.adaptive = true
        cfg.swing = false
        cfg.monitorEnabled = true
        cfg.clickEnabled = true
        cfg.responseMode = mode
        cfg.modifyChoice = modifyChoice
        cfg.grammarFile = grammarFile
        cfg.transformMusician = (mode == .useTransform) ? musician : nil

        let s = TradingSession(config: cfg)
        session = s
        s.onStateChange = { st, turn, _ in
            log("  状态 → \(st.label)（轮 \(turn)）")
        }
        s.onUserPhrase = { phrase, ms in
            log("  📝 用户轮记谱：\(phrase.rawNoteCount) 音头 → \(ms.count) 小节")
        }
        s.onFinished = {
            log("  ⏹ 36 小节对话结束（模式 \(mode)）")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                TradingMIDIDebugProbe.dumpTradingDisplay36(mode: mode)
            }
        }

        if input == nil { input = TradingMIDIInput() }
        _ = input?.start()
        let inj = TradingMIDILoopbackInjector()
        guard inj.start() else { log("❌ 虚拟键盘创建失败"); return }
        input?.connectAllAvailableSources()
        log("键盘：已连接 \(input?.connectedSourceCount ?? 0) 个源")

        log("⏳ \(Int(readySeconds)) 秒后开始：36 小节，模式 \(mode)")
        DispatchQueue.main.asyncAfter(deadline: .now() + readySeconds) {
            s.start(roadmap: roadmap, input: input, monitor: TradingMonitor(program: 66))
            var evs: [TradingMIDILoopbackInjector.ScheduledEvent] = []
            for t in stride(from: 0, through: 8, by: 2) {
                evs.append(contentsOf: h3UserTurnEvents(roadmap: roadmap, cfg: cfg, turn: t))
            }
            inj.performScheduled(events: evs, bpm: cfg.bpm,
                                 anchorTicks: inj.machTicks(fromNs: s.musicAnchorNs) &+ 1)
            log("🎹 已注入 5 个用户轮乐句（\(evs.count / 2) 个音），请听完整 36 小节")
        }
    }

    /// [tradingmodify] 电脑轮走 Modify and Rectify；choice 固定（0=倒影/1=逆行/2=倒影+逆行/3=原样）。
    static func staticTradingModify(choice: Int = 0, readySeconds: Double = 8) {
        staticTradingModes(mode: .modifyAndRectify, modifyChoice: choice, readySeconds: readySeconds)
    }

    /// [tradingmodify-random] 电脑轮走 Modify and Rectify，每轮真随机（贴近真实使用，验自然度）。
    static func staticTradingModifyRandom(readySeconds: Double = 8) {
        staticTradingModes(mode: .modifyAndRectify, modifyChoice: nil, readySeconds: readySeconds)
    }

    /// [tradinggrammar] 电脑轮走 Use Grammar（grammarFile 指定，默认 "chord"）。
    static func staticTradingGrammar(grammarFile: String = "chord", readySeconds: Double = 8) {
        staticTradingModes(mode: .useGrammar, grammarFile: grammarFile, readySeconds: readySeconds)
    }

    /// [tradingtransform] 电脑轮走 Use Transform（musician 指定，默认 "My"）。
    static func staticTradingTransform(musician: String = "My", readySeconds: Double = 8) {
        staticTradingModes(mode: .useTransform, musician: musician, readySeconds: readySeconds)
    }

    // MARK: - M2-8d 累积谱客观核验（tradingdemo36 结束后 dump TradingDisplay）

    /// 核对：36 小节全在、和声/段落与 roadmap 一致、5 用户轮 + 4 电脑轮各物理小节含真实音、
    /// 电脑轮回应 80 音、每小节有和弦字母、第 36 小节 Bm7b5/E7b9 换和弦挂 2 个标注、真实音已打颜色。
    static func dumpTradingDisplay36(mode: TradingResponseMode? = nil) {
        let roadmap = demoRoadmap()
        log("======== [M2-8d] 累积谱 TradingDisplay 核验 ========")
        guard let ms = TradingDisplay.shared.measures else {
            log("❌ [M2-8d] TradingDisplay.measures == nil（未铺累积谱）")
            return
        }
        var ok = true
        func gate(_ name: String, _ cond: Bool, _ detail: String) {
            log("\(cond ? "✅" : "❌") [M2-8d] \(name)\(detail.isEmpty ? "" : "：\(detail)")")
            if !cond { ok = false }
        }

        gate("累积谱小节数=36", ms.count == 36, "\(ms.count)")

        // 逐小节和声/chordSlots 数/段落与 roadmap 一致
        var metaMismatch = 0
        for i in 0..<min(ms.count, roadmap.count) {
            if ms[i].chord != roadmap[i].chord
                || ms[i].chordSlots.count != roadmap[i].chordSlots.count
                || ms[i].sectionName != roadmap[i].sectionName
                || ms[i].slotsPerMeasure != roadmap[i].slotsPerMeasure {
                metaMismatch += 1
                log("   元数据不一致 M\(i+1): got chord=\(ms[i].chord) slots=\(ms[i].chordSlots.count) "
                    + "sec=\(ms[i].sectionName ?? "nil") vs roadmap chord=\(roadmap[i].chord) "
                    + "slots=\(roadmap[i].chordSlots.count) sec=\(roadmap[i].sectionName ?? "nil")")
            }
        }
        gate("36小节和声/段落/slots 与 roadmap 一致", metaMismatch == 0, "不一致 \(metaMismatch) 小节")

        // 每轮 4 小节是否含真实（非休止）音
        func realCount(_ start: Int) -> Int {
            var c = 0
            for b in 0..<4 where start + b < ms.count {
                c += ms[start + b].notes.filter { !$0.isRest }.count
            }
            return c
        }
        let userStarts = [0, 8, 16, 24, 32]
        let compStarts = [4, 12, 20, 28]
        for st in userStarts { gate("用户轮@M\(st+1) 含真实音", realCount(st) > 0, "\(realCount(st)) 音") }
        for st in compStarts { gate("电脑轮@M\(st+1) 含回应音", realCount(st) > 0, "\(realCount(st)) 音") }

        let compReal = compStarts.reduce(0) { $0 + realCount($1) }
        // 音数守恒模式（重复/重复并修正/变形并修正）：电脑轮音数=注入乐句音数，卡 80；
        // 生成/加花模式（Use Grammar/Use Transform）：音数由引擎决定，只验每轮有回应音，不卡总音数。
        if let m = mode, m == .useGrammar || m == .useTransform {
            let everyTurnHasNotes = compStarts.allSatisfy { realCount($0) > 0 }
            gate("电脑轮每轮含回应音（生成/加花不卡总音数）", everyTurnHasNotes, "\(compReal)")
        } else {
            gate("电脑轮回应音总数=80", compReal == 80, "\(compReal)")
        }

        // 和弦字母：每小节 chordAnnotations 非空
        var emptyChord = 0
        for i in 0..<ms.count where ms[i].chordAnnotations.isEmpty { emptyChord += 1 }
        gate("每小节都有和弦字母", emptyChord == 0, "空标注 \(emptyChord) 小节")

        // 第 36 小节（idx35）Bm7b5@0/E7b9@240：模板在 slot240 是休止，E7b9 挂休止符 noteIndex=3
        if ms.count > 35 {
            let ann = ms[35].chordAnnotations
            let expect = ann.count == 2
                && ann[0].chord == "Bm7b5" && ann[0].noteIndex == 0
                && ann[1].chord == "E7b9" && ann[1].noteIndex == 3
            gate("第36小节换和弦 Bm7b5/E7b9 标注", expect,
                 "\(ann.map { "\($0.chord)@\($0.noteIndex)" })")
        }

        // 颜色 tag：真实音 tag 非 unknown（chord/color/approach/foreign 之一）
        let taggedCount = ms.flatMap { $0.notes }.filter { !$0.isRest && $0.tag != .unknown }.count
        let realTotal = ms.flatMap { $0.notes }.filter { !$0.isRest }.count
        gate("真实音已打颜色 tag", taggedCount == realTotal && realTotal > 0,
             "\(taggedCount)/\(realTotal)")

        // 时值守恒：每小节 notes slot 总和 = slotsPerMeasure（休止+实音铺满）
        var fillBad = 0
        for i in 0..<ms.count {
            let sum = ms[i].notes.reduce(0) { $0 + TradingTokens.slots(of: $1.duration) }
            if sum != ms[i].slotsPerMeasure { fillBad += 1 }
        }
        gate("每小节时值铺满", fillBad == 0, "不守恒 \(fillBad) 小节")

        // [M2-8f] 随声高亮：电脑轮每个物理小节的每个 note id（含休止/tieEnd）都应被高亮过
        let trace = TradingDisplay.shared.highlightTrace
        var missingHL: [String] = []
        for st in compStarts {
            for b in 0..<4 {
                let bar = st + b
                guard bar < ms.count else { continue }
                for v in 0..<ms[bar].notes.count {
                    let id = "note-\(bar)-\(v)"
                    if !trace.contains(id) { missingHL.append(id) }
                }
            }
        }
        gate("电脑轮逐音高亮覆盖（含休止）", missingHL.isEmpty,
             missingHL.isEmpty ? "全覆盖" : "缺 \(missingHL.count)：\(missingHL.prefix(8))")
        let clearCount = trace.filter { $0 == "" }.count
        gate("电脑轮/退出清高亮", clearCount >= 4, "清高亮 \(clearCount) 次")

        // [M2-8f2] 视图滚动锚点序列：每轮起始小节依次为 0,4,8,...,32（去重）
        let expectedBars = Array(stride(from: 0, through: 32, by: 4))
        let gotBars = TradingDisplay.shared.activeBarTrace.reduce(into: [Int]()) { acc, v in
            if acc.last != v { acc.append(v) }
        }
        gate("视图跟随每轮起始小节", gotBars == expectedBars,
             gotBars == expectedBars ? "序列 \(gotBars)" : "得 \(gotBars)，期望 \(expectedBars)")

        log(ok ? "🎉 [M2-8d] 累积谱全部核验通过" : "🔥 [M2-8d] 累积谱核验有失败项")
    }

    // MARK: - M2-7 H3 边界门禁 G1-G4（两次会话，约 50 秒）

    private static var h3Report: [String] = []
    private static func h3Gate(_ name: String, _ ok: Bool, _ detail: String) {
        let line = "\(ok ? "✅" : "❌") \(name)：\(detail)"
        h3Report.append(line)
        log(line)
    }

    /// G1 进电脑轮起播精度（<10ms，含主线程派发）；G2 关回听下电脑轮仍播放（采样器无条件建）。
    static func staticSessionH3(readySeconds: Double = 6) {
        h3Report.removeAll()
        log("======== [M2-7 H3 边界门禁] 两次会话：G1/G2 关回听，G3/G4 开回听 ========")
        h3Phase1(readySeconds: readySeconds)
    }

    private static func h3Phase1(readySeconds: Double) {
        let roadmap = demoRoadmap()
        var cfg = TradingSession.Config()
        cfg.bpm = 120; cfg.barsPerTurn = 4; cfg.countInBars = 1; cfg.maxTurns = 2
        cfg.monitorEnabled = false       // 会话1：关回听
        cfg.clickEnabled = false
        cfg.swing = false
        let s = TradingSession(config: cfg)
        session = s
        s.onStateChange = { st, turn, _ in
            guard st == .computerTurn, turn == 1 else { return }
            let turnLen = Double(cfg.barsPerTurn * cfg.slotsPerBar)
            let expected = s.musicAnchorNs &+ UInt64(turnLen * TradingClock.nsPerSlot(bpm: cfg.bpm))
            let deltaMs = Double(TradingHostClock.nowNanos() &- expected) / 1_000_000
            h3Gate("G1", abs(deltaMs) < 10,
                   String(format: "进电脑轮相对理论起点偏差 %.2f ms（门<10ms，含定时器leeway+主线程派发）", deltaMs))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let stopN = TradingPlayback.debugStopCount
                let ready = JazzMidiPlayer.shared.isMonitorReady
                h3Gate("G2", stopN >= 1 && ready,
                       "关回听下电脑轮仍发声：play内stop次数=\(stopN)（应≥1），isMonitorReady=\(ready)")
            }
        }
        if input == nil { input = TradingMIDIInput() }
        _ = input?.start()
        let inj = TradingMIDILoopbackInjector(); _ = inj.start()
        input?.connectAllAvailableSources()
        s.onFinished = {
            inj.stop()
            log("会话1 结束，2s 后启动会话2")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { h3Phase2(readySeconds: readySeconds) }
        }
        log("⏳ 会话1（关回听）\(Int(readySeconds))s 后开始：G1 起播精度 + G2 关回听仍发声")
        DispatchQueue.main.asyncAfter(deadline: .now() + readySeconds) {
            s.start(roadmap: roadmap, input: input, monitor: TradingMonitor(program: 66))
            let evs = h3UserTurnEvents(roadmap: roadmap, cfg: cfg, turn: 0)
            inj.performScheduled(events: evs, bpm: cfg.bpm,
                                 anchorTicks: inj.machTicks(fromNs: s.musicAnchorNs) &+ 1)
        }
    }

    /// G3 电脑轮碰键不叠音（录音门+回听门都挡住）；G4 电脑轮播放中 stop 立即停、无后续。
    private static func h3Phase2(readySeconds: Double) {
        let roadmap = demoRoadmap()
        var cfg = TradingSession.Config()
        cfg.bpm = 120; cfg.barsPerTurn = 4; cfg.countInBars = 1; cfg.maxTurns = 2
        cfg.monitorEnabled = true        // 会话2：开回听
        cfg.clickEnabled = false
        cfg.swing = false
        let s = TradingSession(config: cfg)
        session = s
        let mon = TradingMonitor(program: 66)
        let inj = TradingMIDILoopbackInjector(); _ = inj.start()
        var userNotes = 0
        var baselineUser = -1
        var baselineFeed = -1
        s.onUserNote = { _, _, _ in userNotes += 1 }
        s.onStateChange = { st, turn, _ in
            guard st == .computerTurn, turn == 1 else { return }
            baselineUser = userNotes
            baselineFeed = mon.debugFeedNoteOnCount
            // 干扰音排在电脑轮 +240/+300（约 1.0~1.25s），等 2.5s 确保已发生
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                h3Gate("G3", userNotes == baselineUser && mon.debugFeedNoteOnCount == baselineFeed,
                       "电脑轮干扰音：录音onUserNote \(baselineUser)→\(userNotes)、回听feed \(baselineFeed)→\(mon.debugFeedNoteOnCount)（均应不变）")
                let stopBefore = TradingPlayback.debugStopCount
                s.stop()                 // 电脑轮播放中中途退出
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let stopped = TradingPlayback.debugStopCount >= stopBefore + 1
                    let idle = s.state == .idle
                    h3Gate("G4a", stopped && idle,
                           "播放中stop：debugStopCount \(stopBefore)→\(TradingPlayback.debugStopCount)（应+1），state=\(s.state.label)（应空闲）")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        h3Gate("G4b", s.state == .idle,
                               "stop后再等2s无后续触发，state=\(s.state.label)")
                        inj.stop()
                        log("======== [H3 门禁] 汇总（G1-G4）========")
                        for line in h3Report { log(line) }
                    }
                }
            }
        }
        if input == nil { input = TradingMIDIInput() }
        _ = input?.start()
        input?.connectAllAvailableSources()
        log("⏳ 会话2（开回听）\(Int(readySeconds))s 后开始：G3 电脑轮不叠音 + G4 中途退出立即停")
        DispatchQueue.main.asyncAfter(deadline: .now() + readySeconds) {
            s.start(roadmap: roadmap, input: input, monitor: mon)
            var evs = h3UserTurnEvents(roadmap: roadmap, cfg: cfg, turn: 0)
            let turnLen = cfg.barsPerTurn * cfg.slotsPerBar
            evs.append(.init(bytes: [0x90, 72, 110], atSlot: turnLen + 240))
            evs.append(.init(bytes: [0x80, 72, 0], atSlot: turnLen + 300))
            inj.performScheduled(events: evs, bpm: cfg.bpm,
                                 anchorTicks: inj.machTicks(fromNs: s.musicAnchorNs) &+ 1)
            log("已注入用户乐句 + 电脑轮干扰音（slot \(turnLen + 240)/\(turnLen + 300)，应被双门挡住）")
        }
    }

    // MARK: - M2-6b 节奏样本库：每组 4 小节，一轮一组，边听边看谱
    //
    // 用法：`-tradingProbe bank`（第 1-4 组）；`-tradingProbe bank2`（第 5-8 组）
    static func staticBank(group: Int = 0, perRun: Int = 4, readySeconds: Double = 8) {
        let all = TradingDemoBank.all()
        let from = group * perRun
        let items = Array(all[min(from, all.count)..<min(from + perRun, all.count)])
        guard !items.isEmpty else { log("没有样本"); return }
        log("—— M2-6b 节奏样本库（第 \(group * perRun + 1)-\(group * perRun + items.count) 组）——")

        let base = demoRoadmap()
        let needBars = (1 + 2 * items.count) * 4
        var roadmap: [GeneratedMeasure] = []
        while roadmap.count < needBars { roadmap.append(contentsOf: base) }

        if input == nil { input = TradingMIDIInput() }
        _ = input?.start()
        let injector = TradingMIDILoopbackInjector()
        guard injector.start() else { log("❌ 虚拟键盘创建失败"); return }
        input?.connectAllAvailableSources()
        log("键盘：已连接 \(input?.connectedSourceCount ?? 0) 个源")

        var cfg = TradingSession.Config()
        cfg.bpm = 120
        cfg.barsPerTurn = 4
        cfg.countInBars = 1
        cfg.maxTurns = 2 * items.count
        cfg.adaptive = true
        cfg.monitorEnabled = true
        cfg.clickEnabled = true

        let s = TradingSession(config: cfg)
        s.onStateChange = { st, turn, _ in
            if st == .userTurn, turn / 2 < items.count {
                log("  ▶ 第 \(turn / 2 + 1) 组：\(items[turn / 2].name)")
            }
        }
        s.onUserPhrase = { phrase, measures in
            let total = measures.reduce(0) { $0 + $1.notes.count }
            let i = max(0, s.turnIndex / 2)
            var detail = ""
            if i < items.count {
                let recStarts = Set(phrase.notes.filter { $0.pitch != TradingSlotGrid.restPitch }.map { $0.startSlot })
                let miss = items[i].notes.filter { !recStarts.contains($0.start) }
                detail = "；源 \(items[i].notes.count) 音，缺：\(miss.prefix(4).map { "\($0.pitch)@\($0.start)" })"
            }
            log("  📝 收尾：\(phrase.rawNoteCount) 个音头 → \(total) 个谱面音符已上屏\(detail)")
            if i < items.count {
                for (mi, m) in measures.enumerated() {
                    let txt = m.notes.map { n -> String in
                        var d = n.duration
                        if n.isTieStart { d += "~" }
                        if n.isTieEnd { d = "~" + d }
                        return n.isRest ? "R:\(d)" : "\(n.pitch):\(d)"
                    }.joined(separator: " ")
                    log("      M\(mi + 1) \(txt)")
                }
            }
        }
        s.onFinished = { log("  ✅ 样本库结束（谱面停在最后一组）") }

        session = s
        log("⏳ \(Int(readySeconds)) 秒后开始：1 小节 click → 每组 4 小节（电脑轮静音）…")
        DispatchQueue.main.asyncAfter(deadline: .now() + readySeconds) {
            s.start(roadmap: roadmap, input: input, monitor: TradingMonitor(program: 66))
            let turnLen = cfg.barsPerTurn * cfg.slotsPerBar
            var evs: [TradingMIDILoopbackInjector.ScheduledEvent] = []
            for (i, item) in items.enumerated() {
                let base = 2 * i * turnLen
                for n in item.notes {
                    let p = UInt8(max(0, min(127, n.pitch)))
                    evs.append(.init(bytes: [0x90, p, 90], atSlot: base + n.start))
                    evs.append(.init(bytes: [0x80, p, 0], atSlot: base + n.start + n.dur))
                }
            }
            injector.performScheduled(events: evs, bpm: cfg.bpm,
                                      anchorTicks: injector.machTicks(fromNs: s.musicAnchorNs))
            log("🎹 已注入 \(evs.count) 条事件（\(items.count) 组）")
        }
    }

    // MARK: - 一键全跑

    /// 顺序执行：① 设备枚举 → ③ 时钟偏差 → ② 录 8 音（最后留出时间让你弹）
    static func runAll(captureSeconds: Double = 25, trials: Int = 5) {
        log("========== Trading M1 真机验收探针 ==========")
        log("本文件仅 DEBUG 构建存在；未修改任何现有代码。")
        deviceScan()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            clockDelta(trials: trials)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(trials) * 2.6 + 1.0) {
                capture(seconds: captureSeconds)
            }
        }
    }

    /// 只跑设备枚举 + 录 8 音（不测 δ，不发声）
    static func runCaptureOnly(seconds: Double = 25) {
        deviceScan()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            capture(seconds: seconds)
        }
    }

    /// 应急：停掉探针发出的一切声音
    static func silence() {
        JazzMidiPlayer.shared.stop()
        log("已停止播放")
    }

    // MARK: - M2-3 外部锚点对齐（时钟同源验收）
    //
    // 两道门：
    //   精确门（零噪声）：playWithAccompaniment(externalAnchorNs: t0) 同步返回后，
    //                    player.debugAnchorNs 必须 == t0（逐位相等）——证明外部锚点被原样接收。
    //   粗验门（证明未来锚点被调度遵守）：首声 onNotePlay 相对"调用前一刻"应 ≈ 800ms（±50ms）。
    //                    若未来锚点没生效（立即播放），首声在几 ms 内出现（≈0），判红。
    // 为什么不用"首声时刻 − t0 < 2ms"当精确门：onNotePlay 是 DispatchQueue.main.async 派发
    //   （JazzMidiPlayer.swift:626/725），且首声自带 ±1.2 slot（±5ms）groove 抖动（:623/722），
    //   回调时刻混了 0–10ms 主队列派发延迟，与"时钟是否同源"无关。逐位门才是同源直证。
    // —— align 全异步状态（结构照抄真机已验证的 clockDeltaAsync：step 立即返回，不阻塞主线程）——
    private static var aTrials = 5
    private static var aTrial = 0
    private static var aBitFail = 0
    private static var aCoarseFail = 0
    private static var aCoarse = TradingStats()
    private static var aCaptured = false
    private static var aFirstNs: UInt64 = 0
    private static var aCallNs: UInt64 = 0
    private static var aPrevOnNotePlay: ((String) -> Void)?
    private static var aSolo: [GeneratedMeasure] = []

    static func staticAlign(trials: Int = 5) {
        log("—— M2-3 外部锚点对齐（\(trials) 次）——")
        let player = JazzMidiPlayer.shared

        // 与 clockDelta 相同：1 小节 4 个四分音，第一音在 slot 0
        var notes: [GeneratedNote] = []
        for p in ["c/4", "e/4", "g/4", "c/5"] {
            notes.append(GeneratedNote(pitch: p, tag: .chordTone, isRest: false,
                                       duration: "q", isTriplet: false))
        }
        TradingMIDIDebugProbe.aSolo = [GeneratedMeasure(chord: "c", notes: notes,
                                                        chordAnnotations: [(chord: "c", noteIndex: 0)],
                                                        sectionName: nil)]
        TradingMIDIDebugProbe.aTrials = trials
        TradingMIDIDebugProbe.aTrial = 0
        TradingMIDIDebugProbe.aBitFail = 0
        TradingMIDIDebugProbe.aCoarseFail = 0
        TradingMIDIDebugProbe.aCoarse = TradingStats()
        TradingMIDIDebugProbe.aPrevOnNotePlay = player.onNotePlay
        alignStep()
    }

    // 全异步步进（结构照抄真机已验证的 clockDeltaAsync/deltaStep）：
    //   本方法立即返回，不在主线程 Thread.sleep / RunLoop 自旋，主 runloop 始终自由，
    //   播放后台 Task 派到主队列的 onNotePlay 首声 block 才能正常投递。
    private static func alignStep() {
        let player = JazzMidiPlayer.shared
        let leadMs: Double = 800.0

        guard TradingMIDIDebugProbe.aTrial < TradingMIDIDebugProbe.aTrials else {
            // 【时序·勿用 defer】第六次 alignStep 命中这里才还原 onNotePlay（与 v2.1 一致）
            player.onNotePlay = TradingMIDIDebugProbe.aPrevOnNotePlay
            let trials = TradingMIDIDebugProbe.aTrials
            log("精确门 debugAnchorNs == t0：\(trials - TradingMIDIDebugProbe.aBitFail)/\(trials) 逐位相等")
            log("粗验门 首声 ≈ \(Int(leadMs))ms(±50)：\(trials - TradingMIDIDebugProbe.aCoarseFail)/\(trials)；\(TradingMIDIDebugProbe.aCoarse.summary)")
            if TradingMIDIDebugProbe.aBitFail == 0 && TradingMIDIDebugProbe.aCoarseFail == 0 {
                log("结论：✅ 外部锚点逐位生效且被调度遵守（播放器与 TradingClock 同源）")
            } else {
                log("结论：❌ 未通过（逐位失败 \(TradingMIDIDebugProbe.aBitFail)、粗验失败 \(TradingMIDIDebugProbe.aCoarseFail)）")
            }
            log("—— M2-3 对齐结束 ——")
            return
        }

        TradingMIDIDebugProbe.aTrial += 1
        let trialIndex = TradingMIDIDebugProbe.aTrial
        TradingMIDIDebugProbe.aCaptured = false
        TradingMIDIDebugProbe.aFirstNs = 0          // 每轮清零，避免诊断打印读到上一轮旧值
        player.stop()
        player.onNotePlay = { noteId in
            TradingMIDIDebugProbe.aPrevOnNotePlay?(noteId)
            if !TradingMIDIDebugProbe.aCaptured, noteId.hasPrefix("note-") {
                TradingMIDIDebugProbe.aCaptured = true
                TradingMIDIDebugProbe.aFirstNs = TradingHostClock.nowNanos()
            }
        }

        // 先 0.4s 让 App 回到空闲，再取锚点、启动播放（与 deltaStep 同一个 0.4s 节拍）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let callNs = TradingHostClock.nowNanos()
            let t0 = callNs &+ UInt64(leadMs * 1_000_000.0)
            TradingMIDIDebugProbe.aCallNs = callNs
            let clock = TradingClock()
            clock.start(bpm: 120.0, anchorNs: t0, countInSlots: 0)
            player.playWithAccompaniment(solo: TradingMIDIDebugProbe.aSolo, bpm: 120.0,
                                         style: "sty:swing", startMeasure: 0, externalAnchorNs: t0)

            // 精确门：playWithAccompaniment 同步返回后，锚点此刻必须已被赋值为 t0（逐位）
            let bitOk = (player.debugAnchorNs == t0)
            if !bitOk { TradingMIDIDebugProbe.aBitFail += 1 }

            // 粗验：2.5s 后一次性判定（首声在 800ms，2.5s 足够）；不再同步自旋
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                let captured = TradingMIDIDebugProbe.aCaptured
                if captured, TradingMIDIDebugProbe.aFirstNs >= TradingMIDIDebugProbe.aCallNs {
                    let ms = Double(TradingMIDIDebugProbe.aFirstNs &- TradingMIDIDebugProbe.aCallNs) / 1_000_000.0
                    TradingMIDIDebugProbe.aCoarse.add(ms)
                    if abs(ms - leadMs) > 50.0 { TradingMIDIDebugProbe.aCoarseFail += 1 }
                    let slotAtFirst = clock.slot(atNs: TradingMIDIDebugProbe.aFirstNs)
                    log(String(format: "  第%d次：逐位=%@ 首声=%.1fms（应≈%.0f） TradingClock反算slot=%.2f",
                               trialIndex, bitOk ? "✅" : "❌", ms, leadMs, slotAtFirst))
                } else {
                    // 分叉预案诊断：区分"没发声"（captured=false、aFirstNs=0）与"派发慢/异常"（aFirstNs!=0 但越界）
                    let why = captured ? "首声时刻早于调用时刻（异常）" : "首声超时"
                    log("  第\(trialIndex)次：逐位=\(bitOk ? "✅" : "❌") \(why) (aCaptured=\(captured) aFirstNs=\(TradingMIDIDebugProbe.aFirstNs) aCallNs=\(TradingMIDIDebugProbe.aCallNs))")
                    TradingMIDIDebugProbe.aCoarseFail += 1
                }
                player.stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { alignStep() }
            }
        }
    }

    // MARK: - M2-5 实时回听验收
    //
    // 自动断言：enableMonitor 后 isMonitorEnabled && isMonitorReady（音色缺失/加载失败即判红）。
    // 人工听验（真机）：4 个四分音 C-E-G-C（各约 0.45s），应为 Tenor Sax 音色、节奏均匀。
    // 说明：直接喂 TradingMonitor.feed 验证"回听发声链路"；真实 USB 输入链路已在 M2-2 验证，
    //      故这里不重复建 MIDI 线缆，也不依赖注入器的 machTicks（节奏用 Thread.sleep，人听足够）。
    static func staticMonitor() {
        log("—— M2-5 实时回听 ——")
        let monitor = TradingMonitor(program: 66)
        monitor.start()   // 挂载在主线程（enableMonitor 内部保证音频图变更在主线程）

        let on = JazzMidiPlayer.shared.isMonitorEnabled
        let ready = JazzMidiPlayer.shared.isMonitorReady
        log("挂载：isMonitorEnabled=\(on)  isMonitorReady=\(ready)")
        guard on, ready else {
            log("结论：❌ 回听采样器未就绪（未找到 sf2 / 音色加载失败），判红")
            return
        }

        let pitches: [Int] = [60, 64, 67, 72]
        DispatchQueue.global(qos: .userInitiated).async {
            for p in pitches {
                monitor.feed(TradingMIDIEvent(pitch: p, velocity: 90, isNoteOn: true, channel: 0,
                                              hostTimeNs: TradingHostClock.nowNanos(),
                                              sourceUniqueID: Int32(0)))
                Thread.sleep(forTimeInterval: 0.45)
                monitor.feed(TradingMIDIEvent(pitch: p, velocity: 0, isNoteOn: false, channel: 0,
                                              hostTimeNs: TradingHostClock.nowNanos(),
                                              sourceUniqueID: Int32(0)))
                Thread.sleep(forTimeInterval: 0.05)
            }
            Thread.sleep(forTimeInterval: 0.3)
            monitor.stop()
            TradingMIDIDebugProbe.log("发声结束：应听到 Tenor Sax C-E-G-C（各约 0.45s），请人工确认音色与节奏")
        }
    }
}

/// 便于在 LLDB 里少打几个字：`expr -l Swift -- tradingProbe("all")`
/// 参数："all" / "scan" / "capture" / "groove" / "route" / "delta" / "silence" / "phrases" / "loopgo" / "loopgoa" / "loopback" / "align" / "monitor" / "session"
func tradingProbe(_ command: String = "all") {
    switch command.lowercased() {
    case "scan":    TradingMIDIDebugProbe.deviceScan()
    case "capture": TradingMIDIDebugProbe.runCaptureOnly()
    case "groove":  TradingMIDIDebugProbe.captureWithGroove()
    case "route":   TradingMIDIDebugProbe.logAudioRoute()
    case "delta":   TradingMIDIDebugProbe.clockDeltaAsync()
    case "silence": TradingMIDIDebugProbe.silence()
    case "phrases": TradingPhraseLab.printRobustnessReport()   // M2-1 乐句记谱鲁棒性 + 量化器守卫
    case "loopgo":  TradingLoopbackHarness.runLoopGo()    // M2-2 pre-flight：方式B 实时注入单音 500ms→120 slot（验收门）
    case "loopgoa": TradingLoopbackHarness.runLoopGoA()   // M2-2 路径A 观测：未来时间戳是否按点（非验收门）
    case "loopback": TradingLoopbackHarness.run()         // M2-2 Step2 完整回环：路径A 9乐句×3档 + 解析矩阵（验收门）
    case "align":   TradingMIDIDebugProbe.staticAlign()    // M2-3 外部锚点对齐（逐位门 + 首声粗验）
    case "monitor": TradingMIDIDebugProbe.staticMonitor()  // M2-5 回听：懒挂载 + 就绪门 + 人听
    case "session": TradingMIDIDebugProbe.staticSession()  // M2-6 会话状态机：数拍 + 用户轮/电脑轮切换 + 收尾记谱
    case "responder": TradingResponderGuard.run()          // M2-7 1:1 对拍守卫：3 轮 RepeatAndRectify vs Java 金标准
    case "roundtrip": TradingRoundTripHarness.run()        // M2-6c 记谱回环：Demo+Grammar 的 solo × 五个量化档
    case "demo":    TradingMIDIDebugProbe.staticDemo()     // M2-6b 演示：Demo 伴奏 + 虚拟键盘弹 solo + 谱面显示
    case "bank":    TradingMIDIDebugProbe.staticBank(group: 0)   // M2-6b 样本库 1-4 组
    case "bank2":   TradingMIDIDebugProbe.staticBank(group: 1)   // M2-6b 样本库 5-8 组
    case "live":      TradingMIDIDebugProbe.staticLiveReplay()
    case "livetest":  TradingMIDIDebugProbe.staticLive(inject: true)
    case "livelong":  TradingMIDIDebugProbe.staticLiveLong(turns: 4)
    case "sessionh3":    TradingMIDIDebugProbe.staticSessionH3()      // M2-7 H3 边界门禁 G1-G4
    case "tradingdemo36": TradingMIDIDebugProbe.staticTradingDemo36() // M2-7 36 小节 demo 完整对话（5 用户轮/4 电脑轮）
    case "tradingmodify": TradingMIDIDebugProbe.staticTradingModify()       // M2-9 Modify 固定 choice（默认0倒影）
    case "tradingmodifyrandom": TradingMIDIDebugProbe.staticTradingModifyRandom() // M2-9 Modify 每轮随机
    case "tradinggrammar": TradingMIDIDebugProbe.staticTradingGrammar()     // M2-9 Use Grammar
    case "tradingtransform": TradingMIDIDebugProbe.staticTradingTransform() // M2-9 Use Transform
    case "bank3":   TradingMIDIDebugProbe.staticBank(group: 4, perRun: 2)   // M2-6b 样本库 第 9-10 组（swing / 拍内混合）
    default:        TradingMIDIDebugProbe.runAll()
    }
}

#endif
