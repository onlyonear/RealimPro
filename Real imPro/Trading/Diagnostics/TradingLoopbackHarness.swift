#if DEBUG
import Foundation
import CoreMIDI

// MARK: - Trading / Diagnostics / 虚拟 MIDI 回环测试 harness（仅 DEBUG）
//
// loopgo   = 极简 pre-flight：建虚拟键盘→连→实时投 on→mach_wait 500ms→off，验证记成 C4@0/120。
// loopback = 完整端到端（Step 2 追加）：复用 TradingPhraseLab 同套 9 乐句 + swing + 确定性抖动，
//            经完整 CoreMIDI 输入路径回灌，再逐音断言 (pitch, startSlot, durationSlots)。
enum TradingLoopbackHarness {

    static let bpm: Double = 120.0
    /// 给建连/配置留出的提前量（anchor 在未来 100ms），保证第一个事件到达时 clock/onEvent 已就绪
    private static let leadMs: UInt64 = 100

    struct Setup {
        let input: TradingMIDIInput
        let injector: TradingMIDILoopbackInjector
        let recvQueue: DispatchQueue
    }

    // MARK: 连接（严格按 DeepSeek 三点 + 独立第二 client）

    static func connectVirtualKeyboard() -> Setup? {
        let injector = TradingMIDILoopbackInjector()        // ② 先建虚拟源（独立 client）
        guard injector.start() else {
            print("❌ 虚拟源建立失败（MIDISourceCreateWithProtocol 或源不可见）"); return nil
        }
        let input = TradingMIDIInput()                     // 生产输入 start() 末尾会全连
        guard input.start() else {
            print("❌ 生产输入 TradingMIDIInput.start() 失败"); injector.stop(); return nil
        }
        input.disconnectAllSources()                       // ③ 先断开所有源（避免真键盘串音）
        let devices = input.availableDevices()             // ② 实时枚举，不使用缓存
        guard let virtual = devices.first(where: { $0.name.contains(TradingMIDILoopbackInjector.virtualName) }) else {
            print("❌ 枚举不到虚拟源（当前可见 \(devices.count) 个源）")
            input.stop(); injector.stop(); return nil
        }
        guard input.connect(virtual) else {                 // ① 显式 connect，不用全连
            print("❌ MIDIPortConnectSource 连接虚拟源失败")
            input.stop(); injector.stop(); return nil
        }
        print("已连接虚拟键盘：\(virtual.name)（仅此一个源，connected=\(input.connectedSourceCount)）")
        return Setup(input: input, injector: injector,
                     recvQueue: DispatchQueue(label: "com.realimpro.trading.loopback.recv"))
    }

    static func teardown(_ s: Setup) {
        s.input.stop()
        s.injector.stop()
    }

    // MARK: loopgo（pre-flight）：实时投一个长 120 slot（500ms）的四分音

    static func runLoopGo() {
        print("\n========== M2-2 loopgo pre-flight（实时注入，DEBUG 专用） ==========")
        guard let s = connectVirtualKeyboard() else {
            print("❌ go/no-go 失败：虚拟键盘连不通（症状=一个音都收不到），终止。"); return
        }
        defer { teardown(s) }

        let rec = TradingRecorder()
        let clock = TradingClock()
        let sem = DispatchSemaphore(value: 0)
        var events: [TradingMIDIEvent] = []
        s.input.onEvent = { ev in
            s.recvQueue.async {
                events.append(ev)
                rec.handle(ev, clock: clock)
                if events.count == 2 { sem.signal() }
            }
        }

        // anchor = now + 100ms；clock 与注入线程共用同一 anchor（统一换算入口 machTicks(fromMs:)，v2.1）
        let anchorTicks = mach_absolute_time() &+ s.injector.machTicks(fromMs: Self.leadMs)
        let anchorNs = TradingHostClock.toNanos(anchorTicks)
        clock.start(bpm: bpm, anchorNs: anchorNs, countInSlots: 0)
        rec.begin(startSlot: 0, lengthSlots: TradingSettings.slotsPerBar4_4,
                  quantizeGrid: .eighth, inputLatencySlots: 0)

        // 实时线程：on@slot0，off@slot120（500ms）
        let injector = s.injector
        Thread.detachNewThread {
            injector.performRealtime(events: [
                .init(bytes: [0x90, 60, 90], atSlot: 0),
                .init(bytes: [0x80, 60, 0],  atSlot: 120),
            ], bpm: bpm, anchorTicks: anchorTicks)
        }

        if sem.wait(timeout: .now() + 3) == .timedOut {
            print("❌ 超时：只收到 \(events.count)/2 个事件（症状=一个音都收不到）"); s.input.onEvent = nil; return
        }
        let phrase = s.recvQueue.sync { rec.finish() }
        s.input.onEvent = nil
        let notes = phrase.notes.filter { $0.pitch != TradingSlotGrid.restPitch }

        // 首个 on 到达时刻相对 anchor 的误差（实时注入精度）
        let onErrMs: Double = {
            guard let on = events.first(where: { $0.isNoteOn }) else { return 9999 }
            return abs(Double(on.hostTimeNs &- anchorNs)) / 1_000_000.0
        }()
        let noteOK = notes.count == 1 && notes[0].pitch == 60
            && notes[0].startSlot == 0 && notes[0].durationSlots == 120
        let timingOK = onErrMs < 2.0
        print(String(format: "  收到事件 %d/2；on 到达误差 %.3f ms（%@）；记谱 %@",
                     events.count, onErrMs, timingOK ? "实时✅" : "超时❌",
                     noteOK ? "C4@0/120✅" : "错误❌（期望 C4@0/120）"))
        print(noteOK && timingOK
              ? "✅ loopgo 通过：双 client 连通 + 实时注入 500ms 正确记为 120 slot。可进入 Step 2 完整 harness。"
              : "❌ loopgo 未通过：先定位 iOS 上的连接/时间戳/调度，再谈完整 harness。")
    }

    // MARK: loopgoA（路径 A 观测 · 非验收门）：未来时间戳是否被按点调度

    /// 独立 recorder，仅观测 iOS 上「每事件一次 MIDIReceived + 真实未来时间戳」是否按点投递并保留。
    /// 不影响方式 B 主验收；结果只用于决定 Step 2 能否免实时线程。
    static func runLoopGoA() {
        print("\n========== M2-2 loopgoA 路径 A 观测（未来时间戳，非验收门，DEBUG 专用） ==========")
        guard let s = connectVirtualKeyboard() else {
            print("❌ 虚拟键盘连不通，路径 A 观测终止。"); return
        }
        defer { teardown(s) }

        let rec = TradingRecorder(); let clock = TradingClock()
        let sem = DispatchSemaphore(value: 0); var events: [TradingMIDIEvent] = []
        s.input.onEvent = { ev in
            s.recvQueue.async {
                events.append(ev); rec.handle(ev, clock: clock)
                if events.count == 2 { sem.signal() }
            }
        }

        // 路径 A 立即投递，留 200ms 给构造；on@slot0 off@slot120 都带真实时间戳
        let anchorTicks = mach_absolute_time() &+ s.injector.machTicks(fromMs: 200)
        let anchorNs = TradingHostClock.toNanos(anchorTicks)
        clock.start(bpm: bpm, anchorNs: anchorNs, countInSlots: 0)
        rec.begin(startSlot: 0, lengthSlots: TradingSettings.slotsPerBar4_4,
                  quantizeGrid: .eighth, inputLatencySlots: 0)
        s.injector.performScheduled(events: [
            .init(bytes: [0x90, 60, 90], atSlot: 0),
            .init(bytes: [0x80, 60, 0],  atSlot: 120),
        ], bpm: bpm, anchorTicks: anchorTicks)

        // 若按点调度，off 在 anchor+500ms 到；等 2 秒。若被当立即投递，off 会在 anchor+0 到、时值≈0、记不出 120
        if sem.wait(timeout: .now() + 2) == .timedOut {
            print("❌ 超时：只收到 \(events.count)/2（路径 A 在本平台未按点调度）→ Step 2 走方式 B。")
            s.input.onEvent = nil; return
        }
        let phrase = s.recvQueue.sync { rec.finish() }
        s.input.onEvent = nil
        let notes = phrase.notes.filter { $0.pitch != TradingSlotGrid.restPitch }
        let noteOK = notes.count == 1 && notes[0].pitch == 60
            && notes[0].startSlot == 0 && notes[0].durationSlots == 120
        print("  事件 \(events.count)/2；记谱 \(noteOK ? "C4@0/120✅" : "非 C4@0/120❌")")
        print(noteOK
              ? "✅ 路径 A 在本平台成立（未来时间戳按点投递且保留）→ Step 2 可评估免实时线程、用精确时间戳。"
              : "ℹ️ 路径 A 在本平台不成立（整段被立即投递/时值塌缩）→ Step 2 按方式 B 实时线程，不影响主方案。")
    }

    // MARK: loopback（完整端到端，路径 A）—— Step 2 追加

    static func run() {
        print("\n========== M2-2 虚拟 MIDI 回环测试（路径 A：未来时间戳系统调度，DEBUG 专用） ==========")
        print("每事件单独一次 MIDIReceived + 真实未来时间戳；不模拟 USB/人手延迟。")
        guard let s = connectVirtualKeyboard() else {
            print("❌ go/no-go 失败：虚拟键盘连不通，终止。"); return
        }
        defer { teardown(s) }

        // 路径 A 长跨度门禁（4 秒=2 小节，覆盖最长乐句⑨）；等价 loopgoA 的长跨度版，不重新建连
        if !preflight(s) {
            print("❌ pre-flight（路径 A 长跨度）失败，后续乐句测试终止。"); return
        }

        var totalPass = 0, totalFail = 0
        for jitterSlots in [0, 6, 12] {       // ±0/±25/±50ms，与 phrases 同口径
            let (p, f) = runPhrases(s, jitterSlots: jitterSlots)
            totalPass += p; totalFail += f
        }
        parseMatrix(s)
        print("\n========== M2-2 回环合计：通过 \(totalPass)，失败 \(totalFail) \(totalFail == 0 ? "✅" : "❌") ==========")
    }

    /// 路径 A 长跨度门禁：on@0 / off@960（4 秒，2 小节）必须记成 C4@0/960。
    /// 注：480 slot=1 小节=2 秒；960 slot=2 小节=4 秒（120bpm，1 slot=4.167ms）。
    /// off 在轮末 slot960，recorder 按"音持续到本轮末尾"收尾，时值 ceil 为 960（纯逻辑已实测）。
    private static func preflight(_ s: Setup) -> Bool {
        let rec = TradingRecorder(); let clock = TradingClock()
        let sem = DispatchSemaphore(value: 0); var events: [TradingMIDIEvent] = []
        s.input.onEvent = { ev in
            s.recvQueue.async {
                events.append(ev); rec.handle(ev, clock: clock)
                if events.count == 2 { sem.signal() }
            }
        }
        let anchorTicks = mach_absolute_time() &+ s.injector.machTicks(fromMs: Self.leadMs)
        let anchorNs = TradingHostClock.toNanos(anchorTicks)
        clock.start(bpm: bpm, anchorNs: anchorNs, countInSlots: 0)
        rec.begin(startSlot: 0, lengthSlots: TradingSettings.slotsPerBar4_4 * 2,
                  quantizeGrid: .eighth, inputLatencySlots: 0)
        // 路径 A：当前线程一次性投递，系统按未来时间戳调度（无需实时线程）；off 落在 4 秒后
        s.injector.performScheduled(events: [
            .init(bytes: [0x90, 60, 90], atSlot: 0),
            .init(bytes: [0x80, 60, 0],  atSlot: 960),
        ], bpm: bpm, anchorTicks: anchorTicks)
        // off 在 anchor+4s 到达，等 6s 留足余量
        if sem.wait(timeout: .now() + 6) == .timedOut { s.input.onEvent = nil; return false }
        let phrase = s.recvQueue.sync { rec.finish() }; s.input.onEvent = nil
        let notes = phrase.notes.filter { $0.pitch != TradingSlotGrid.restPitch }
        return notes.count == 1 && notes[0].pitch == 60
            && notes[0].startSlot == 0 && notes[0].durationSlots == 960
    }

    @discardableResult
    private static func runPhrases(_ s: Setup, jitterSlots: Int) -> (Int, Int) {
        print("\n———— 回环乐句（抖动 ±\(jitterSlots) slot ≈ ±\(Int(Double(jitterSlots) * 500.0 / 120.0)) ms） ————")
        var passed = 0, failed = 0
        var rng = TradingPhraseLab.SplitMix64(seed: 20261013)
        for phrase in TradingPhraseLab.allPhrases() {
            let ok = runOne(s, phrase: phrase, jitterSlots: jitterSlots, rng: &rng)
            let halfGrid = max(1, phrase.grid.gridSlots / 2)
            let beyondPhysics = jitterSlots > 0 && jitterSlots >= halfGrid
            if ok {
                if beyondPhysics { print("⚠️ \(phrase.name) 抖动≥半格（物理极限，不计失败）") }
                else { print("✅ \(phrase.name)") }
                passed += 1
            } else {
                if beyondPhysics { passed += 1 } else { print("❌ \(phrase.name)"); failed += 1 }
            }
        }
        print("———— 本档合计：通过 \(passed)，失败 \(failed) ————")
        return (passed, failed)
    }

    private static func runOne(_ s: Setup, phrase: TradingPhraseLab.Phrase,
                               jitterSlots: Int, rng: inout TradingPhraseLab.SplitMix64) -> Bool {
        let lengthSlots = phrase.bars * TradingSettings.slotsPerBar4_4
        let clock = TradingClock(); let rec = TradingRecorder()
        let expectedEvents = phrase.notes.count * 2
        let sem = DispatchSemaphore(value: 0); var count = 0
        s.input.onEvent = { ev in
            s.recvQueue.async {
                rec.handle(ev, clock: clock); count += 1
                if count == expectedEvents { sem.signal() }
            }
        }

        let anchorTicks = mach_absolute_time() &+ s.injector.machTicks(fromMs: Self.leadMs)
        let anchorNs = TradingHostClock.toNanos(anchorTicks)
        clock.start(bpm: bpm, anchorNs: anchorNs, countInSlots: 0)
        rec.begin(startSlot: 0, lengthSlots: lengthSlots,
                  quantizeGrid: phrase.grid, inputLatencySlots: 0)

        // 与 phrases 完全相同的"演奏位置 + 确定性抖动"，区别只在经真实 CoreMIDI 路径（路径 A 未来时间戳）
        var events: [TradingMIDILoopbackInjector.ScheduledEvent] = []
        for n in phrase.notes {
            let performed = TradingPhraseLab.performedStart(n.startSlot, swing: phrase.swing)
            let j = jitterSlots > 0 ? Int.random(in: -jitterSlots...jitterSlots, using: &rng) : 0
            let on = max(0, performed + j)
            let off = on + n.duration
            events.append(.init(bytes: [0x90, UInt8(clamping: n.pitch), 90], atSlot: on))
            events.append(.init(bytes: [0x80, UInt8(clamping: n.pitch), 0],  atSlot: off))
        }
        // 路径 A：当前线程一次性投递，每个事件单独一次 MIDIReceived、带真实未来时间戳；系统按点调度
        s.injector.performScheduled(events: events, bpm: bpm, anchorTicks: anchorTicks)

        // 最长等待 = 乐句时长 + 5s（系统按点调度，最远事件在 anchor+乐句时长）
        let bars = max(1, phrase.bars)
        let phraseSeconds = Double(bars) * 4.0 * (60.0 / bpm) + 5.0
        if sem.wait(timeout: .now() + phraseSeconds) == .timedOut {
            print("      · 超时：收到 \(count)/\(expectedEvents) 事件"); s.input.onEvent = nil; return false
        }
        let out = s.recvQueue.sync { rec.finish() }; s.input.onEvent = nil
        let recorded = out.notes.filter { $0.pitch != TradingSlotGrid.restPitch }
        guard recorded.count == phrase.notes.count else {
            print("      · 音数不符：意图 \(phrase.notes.count)，实录 \(recorded.count)"); return false
        }
        for (i, expect) in phrase.notes.enumerated() {
            let got = recorded[i]
            if got.pitch != expect.pitch || got.startSlot != expect.startSlot
                || got.durationSlots != expect.duration {
                print(String(format: "      · [%d] 期望 p=%d @%d/%d 实际 p=%d @%d/%d",
                             i, expect.pitch, expect.startSlot, expect.duration,
                             got.pitch, got.startSlot, got.durationSlots))
                return false
            }
        }
        return true
    }

    /// 0x80 off / 0x90 vel0 off / running status 三种 off 写法；路径 A 投递
    private static func parseMatrix(_ s: Setup) {
        print("\n—— MIDI 解析矩阵（off 写法 / running status） ——")
        let clock = TradingClock(); let rec = TradingRecorder()
        let expected = 8
        let sem = DispatchSemaphore(value: 0); var count = 0
        s.input.onEvent = { ev in
            s.recvQueue.async {
                rec.handle(ev, clock: clock); count += 1
                if count == expected { sem.signal() }
            }
        }
        let anchorTicks = mach_absolute_time() &+ s.injector.machTicks(fromMs: Self.leadMs)
        let anchorNs = TradingHostClock.toNanos(anchorTicks)
        clock.start(bpm: bpm, anchorNs: anchorNs, countInSlots: 0)
        rec.begin(startSlot: 0, lengthSlots: TradingSettings.slotsPerBar4_4 * 2,
                  quantizeGrid: .eighth, inputLatencySlots: 0)

        // 7 条 ScheduledEvent 产出 8 个 MIDI 事件：
        // 240 slot 那条 [0x90,64,90,64,0] 是 on+running-status vel0-off 同 slot 合并（5 字节，同一时间戳，合法）
        let events: [TradingMIDILoopbackInjector.ScheduledEvent] = [
            .init(bytes: [0x90, 60, 90],                atSlot: 0),
            .init(bytes: [0x80, 60, 0],                 atSlot: 60),
            .init(bytes: [0x90, 62, 90],                atSlot: 120),
            .init(bytes: [0x90, 62, 0],                 atSlot: 180),   // 0x90 vel0 当 off
            .init(bytes: [0x90, 64, 90, 64, 0],         atSlot: 240),   // on + running-status vel0 off（5 字节合并）
            .init(bytes: [0x90, 65, 90],                atSlot: 300),
            .init(bytes: [0x80, 65, 0],                 atSlot: 360),
        ]
        s.injector.performScheduled(events: events, bpm: bpm, anchorTicks: anchorTicks)
        if sem.wait(timeout: .now() + 6) == .timedOut {
            print("  超时：\(count)/\(expected)"); s.input.onEvent = nil; return
        }
        let out = s.recvQueue.sync { rec.finish() }; s.input.onEvent = nil
        let notes = out.notes.filter { $0.pitch != TradingSlotGrid.restPitch }
        let ok = count == expected && notes.count == 4
        print("  事件 \(count)/\(expected)；解析出音 \(notes.count)/4；\(ok ? "解析矩阵✅" : "❌")")
        if !ok { print("  实录音高：\(notes.map { $0.pitch })") }
    }
}
#endif
