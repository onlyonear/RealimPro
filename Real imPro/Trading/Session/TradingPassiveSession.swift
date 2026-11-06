import Foundation

// MARK: - Trading / Session / Passive（第一档：Use Grammar 真响）
//
// 与 Active TradingSession 的区别：
//   · 电脑旋律在 start 时一次性预生成整圈（useGrammar），按 quantum 切片缓存；
//   · 电脑段到点直接播放预生成切片，不根据用户上一段实时生成；
//   · 用户段录音只用于记谱/回看，不回喂电脑（电脑是独奏，不是回应式）。
//
// 复用 Active 已验证的机制（结构对齐，独立类不继承，防旧 bug 回流）：
//   · clock/recorder/monitor/JazzMidiPlayer 同源
//   · input.onEvent 回听门控（isUserTurnSlot）+ 录音 handleEvent 分发
//   · 段边界进电脑段时 monitor.allNotesOff() 收挂音（fix158 同款）
//   · 累积谱 overlay / swing / 颜色 tag
//
// 本批只接 .grammar 引擎；.dl / .grammarAndTransform 为第二批预留，静默兜底。
final class TradingPassiveSession: TradingSessionProtocol {

    // MARK: - 配置

    struct Config {
        var bpm: Double = 120
        /// quantum（一个交替段）= barsPerTurn × slotsPerBar。沿用 UI 已选值。
        var barsPerTurn: Int = 4
        var countInBars: Int = 1
        var maxTurns: Int = 8
        var slotsPerBar: Int = TradingSettings.slotsPerBar4_4
        var grid: TradingQuantizeGrid = .eighth
        var inputLatencySlots: Int = 0
        var userStarts: Bool = true
        var monitorEnabled: Bool = true
        var clickEnabled: Bool = true
        var adaptive: Bool = true
        var swing: Bool = true
        var showOnDisplay: Bool = true
        var style: String = "sty:swing"
        var grammarFile: String = "chord"
        /// Transform 大师名（仅 grammarAndTransform 引擎使用）
        var transformMusician: String? = nil
        var passiveEngine: PassiveEngine = .grammar
        /// Live Notation：用户段逐小节实时上屏（false = 段末一次性，对齐 Java）
        var liveNotation: Bool = false
    }

    enum PassiveEngine {
        case dl                     // 第二批
        case grammar                // 本批唯一真响
        case grammarAndTransform    // 第二批
    }

    // MARK: - 对外（协议）

    private(set) var state: TradingSession.State = .idle
    private(set) var turnIndex: Int = -1
    private(set) var musicAnchorNs: UInt64 = 0

    var onStateChange: ((TradingSession.State, Int, Double) -> Void)?
    var onUserPhrase: ((UserPhrase, [GeneratedMeasure]) -> Void)?
    var onUserNote: ((Int, Int, Double) -> Void)?
    var onFinished: (() -> Void)?

    // MARK: - 内部

    private let clock = TradingClock()
    private let recorder = TradingRecorder()
    private let queue = DispatchQueue(label: "trading.passive.session", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var clickTimer: DispatchSourceTimer?
    // [Live Notation] 逐小节上屏机制（照搬 Active turnEvents 重放模式）
    private var turnEvents: [(pitch: Int, velocity: Int, isOn: Bool, slot: Double)] = []
    private let eventsQueue = DispatchQueue(label: "trading.passive.events")
    private var shownBars = 0
    private var progressTimer: Timer?
    private var roadmap: [GeneratedMeasure] = []
    private var input: TradingMIDIInput?
    private var monitor: TradingMonitor?
    private var running = false

    /// 预生成的整圈电脑 solo（绝对 slot 从 0 起，覆盖整圈 roadmap 长度）。
    private var precomputedSolo: [TradingSlotNote] = []
    /// 每段长度（slot）= quantum
    private var turnLength: Int { config.barsPerTurn * config.slotsPerBar }
    private var countInSlots: Int { config.countInBars * config.slotsPerBar }
    private var turnStart: Double { Double(turnIndex) * Double(turnLength) }
    private var turnStartAbsolute: Int { countInSlots + turnIndex * turnLength }

    private var config: Config

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - 启停

    func start(roadmap: [GeneratedMeasure],
               input: TradingMIDIInput?,
               monitor: TradingMonitor?) {
        let setup = { [weak self] in
            guard let self, !self.running else { return }
            self.roadmap = roadmap
            if self.config.showOnDisplay {
                TradingDisplay.shared.reset(roadmap: roadmap)
            }
            self.input = input
            self.monitor = monitor
            self.running = true
            self.turnIndex = -1
            self.setState(.idle, turn: -1, start: 0)

            // ① 预生成整圈电脑 solo（只 .grammar 真响；其余静默）
            self.precomputedSolo = self.generateEntireSolo()

            // ② 起伴奏 + 数拍（结构对齐 Active）
            let player = JazzMidiPlayer.shared
            player.onNotePlay = { noteId in
                TradingDisplay.shared.setHighlight(noteId)
            }
            let anchor = TradingHostClock.nowNanos() &+ 500_000_000
            let countInNs = UInt64(Double(self.countInSlots) * TradingClock.nsPerSlot(bpm: self.config.bpm))
            let musicAnchor = anchor &+ countInNs
            self.musicAnchorNs = musicAnchor

            if self.config.clickEnabled, self.config.countInBars > 0 {
                player.enableClick()
                self.scheduleClicks(from: anchor)
            }
            player.playWithAccompaniment(solo: roadmap,
                                         bpm: self.config.bpm,
                                         style: self.config.style,
                                         startMeasure: 0,
                                         externalAnchorNs: musicAnchor)

            // ③ 会话时钟
            self.clock.start(bpm: self.config.bpm, anchorNs: anchor, countInSlots: self.countInSlots)

            // ④ 回听采样器
            player.enableMonitor(program: 66)
            if self.config.monitorEnabled, let m = monitor { m.start() }

            // ⑤ MIDI 分发：回听门控 + 录音
            input?.onEvent = { [weak self] ev in
                guard let self, !self.clock.isPaused else { return }
                if self.config.monitorEnabled, self.monitor != nil {
                    if ev.isNoteOn {
                        if self.isUserTurnSlot(ev.hostTimeNs) {
                            self.monitor?.feed(ev)
                        }
                    } else {
                        self.monitor?.feed(ev)
                    }
                }
                self.queue.async { self.handleEvent(ev) }
            }

            // ⑥ 25ms 轮询
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now() + 0.05, repeating: 0.025, leeway: .milliseconds(2))
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            self.timer = t
        }
        if Thread.isMainThread { setup() } else { DispatchQueue.main.async(execute: setup) }
    }

    func pause() {
        queue.async { [weak self] in
            guard let self, self.running, !self.clock.isPaused else { return }
            self.clock.pause()
            DispatchQueue.main.async {
                JazzMidiPlayer.shared.pause()
                if self.config.monitorEnabled {
                    JazzMidiPlayer.shared.monitorAllNotesOff()
                }
            }
        }
    }

    func resume() {
        queue.async { [weak self] in
            guard let self, self.running, self.clock.isPaused else { return }
            self.clock.resume()
            DispatchQueue.main.async { JazzMidiPlayer.shared.resume() }
        }
    }

    func stop() {
        queue.async { [self] in
            self.teardown(finishCurrent: true)
        }
    }

    // MARK: - 预生成整圈 solo

    private func generateEntireSolo() -> [TradingSlotNote] {
        switch config.passiveEngine {
        case .grammar:
            let blocks = entireChordBlocks()
            guard !blocks.isEmpty else { return [] }
            return TradingModeGenerators.useGrammar(
                responseChords: blocks,
                grammarFile: config.grammarFile,
                bpm: Int(config.bpm))
        case .grammarAndTransform:
            // 对齐 Java：先 grammar 生成整圈 solo，再过 Transform 加花
            let blocks = entireChordBlocks()
            guard !blocks.isEmpty else { return [] }
            let grammarSolo = TradingModeGenerators.useGrammar(
                responseChords: blocks,
                grammarFile: config.grammarFile,
                bpm: Int(config.bpm))
            guard !grammarSolo.isEmpty else { return [] }
            return TradingModeGenerators.useTransform(
                userNotes: grammarSolo,
                responseChords: blocks,
                musician: config.transformMusician,
                rngMode: .deterministic,
                toneSet: { TradingChordToneSet.toneSet(chordName: $0) })
        case .dl:
            // 对齐 Java LSTMGen.generateTrading：逐段生成电脑段，用户段补休止（1:1）
            let blocks = entireChordBlocks()
            guard !blocks.isEmpty else { return [] }
            let spb = config.slotsPerBar
            let turnBars = config.barsPerTurn
            let totalSegments = (roadmap.count + turnBars - 1) / turnBars

            var allNotes: [TradingSlotNote] = []
            for segIdx in 0..<totalSegments {
                let segStartBar = segIdx * turnBars
                let segEndBar = min(segStartBar + turnBars, roadmap.count)
                let segStartSlot = segStartBar * spb
                let segEndSlot = segEndBar * spb
                let isUserSeg = (segIdx % 2 == 0) == config.userStarts

                if isUserSeg {
                    // 用户段：显式补休止符（对齐 Java accumMelody.addNote(makeRest)）
                    allNotes.append(TradingSlotNote(pitch: -1,
                                                    startSlot: segStartSlot,
                                                    durationSlots: segEndSlot - segStartSlot,
                                                    isRest: true))
                    continue
                }

                // 电脑段：取该轮 TradingChordBlock，逐段独立生成（等价 Java reload+reset）
                let segBlocks = blocks.filter { blk in
                    blk.startSlot >= segStartSlot && blk.startSlot < segEndSlot
                }
                guard !segBlocks.isEmpty else { continue }

                let segRoadmap = TradingModeBridge.roadmap(
                    from: segBlocks,
                    title: "Passive DL Segment",
                    tempo: Int(config.bpm))
                let strategy = LSTMStrategy(modelName: "combination")
                let physicalNotes = strategy.generateSolo(for: segRoadmap)
                guard !physicalNotes.isEmpty else { continue }

                // offset 到全局位置拼接
                let segNotes = TradingModeBridge.slotNotes(from: physicalNotes)
                for note in segNotes {
                    allNotes.append(TradingSlotNote(
                        pitch: note.pitch,
                        startSlot: note.startSlot + segStartSlot,
                        durationSlots: note.durationSlots,
                        isRest: note.isRest))
                }
            }
            return allNotes
        }
    }

    /// 整圈和弦块（每小节一个 block，含 chordSlots），用于 useGrammar 预生成。
    private func entireChordBlocks() -> [TradingChordBlock] {
        var blocks: [TradingChordBlock] = []
        let spb = config.slotsPerBar
        for (i, m) in roadmap.enumerated() {
            let barBase = i * spb
            if m.chordSlots.isEmpty {
                blocks.append(TradingChordBlock(name: m.chord,
                                                startSlot: barBase, durationSlots: spb))
                continue
            }
            for (ci, cs) in m.chordSlots.enumerated() {
                let start = barBase + cs.startSlot
                let end = ci + 1 < m.chordSlots.count
                    ? barBase + m.chordSlots[ci + 1].startSlot
                    : barBase + spb
                blocks.append(TradingChordBlock(name: cs.chord,
                                                startSlot: start, durationSlots: max(1, end - start)))
            }
        }
        return blocks
    }

    // MARK: - 轮询

    private func tick() {
        guard running else { return }
        let s = clock.currentSlot()
        if s < 0 {
            if state != .countIn, turnIndex < 0 {
                setState(.countIn, turn: -1, start: 0)
            }
            return
        }
        let idx = Int(floor(s / Double(turnLength)))
        if idx >= config.maxTurns {
            finish()
            return
        }
        if idx != turnIndex {
            beginTurn(idx)
        }
        // [Live Notation] 仅开关开启时逐小节上屏（与 Active tick 同构）
        if config.liveNotation {
            progressTick()
        }
    }

    private func beginTurn(_ idx: Int) {
        guard idx != turnIndex else { return }
        if state == .userTurn { finalizeUserTurn() }
        turnIndex = idx
        let isUser = (idx % 2 == 0) == config.userStarts

        if isUser {
            recorder.begin(startSlot: turnStartAbsolute,
                           lengthSlots: turnLength,
                           quantizeGrid: config.grid,
                           inputLatencySlots: config.inputLatencySlots,
                           slotsPerBar: config.slotsPerBar,
                           adaptive: config.adaptive,
                           forceSwing: config.swing)
            eventsQueue.sync { self.turnEvents.removeAll(keepingCapacity: true) }
            shownBars = 0
            if config.liveNotation {
                let t = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
                    self?.progressTick()
                }
                progressTimer = t
            }
            setState(.userTurn, turn: idx, start: turnStart)
        } else {
            // 段边界收挂音（fix158 同款）
            self.monitor?.allNotesOff()
            setState(.computerTurn, turn: idx, start: turnStart)
            playPrecomputedSlice(for: idx)
        }
    }

    /// 播放预生成 solo 中属于第 idx 电脑段的切片。
    private func playPrecomputedSlice(for segIdx: Int) {
        let segStart = segIdx * turnLength
        let segEnd = segStart + turnLength
        let slice: [TradingSlotNote] = precomputedSolo.compactMap { n in
            guard n.startSlot >= segStart, n.startSlot < segEnd else { return nil }
            // 段末音符截断：防止长音符延伸到下一段（如 Gmaj7 全音符拖到 F#7 小节）
            let clipped = min(n.durationSlots, segEnd - n.startSlot)
            return TradingSlotNote(pitch: n.pitch,
                                   startSlot: n.startSlot - segStart,
                                   durationSlots: clipped,
                                   isRest: n.isRest)
        }
        guard !slice.isEmpty else { return }

        var grid = TradingSlotGrid(capacity: turnLength)
        for n in slice {
            grid.setUnit(at: n.startSlot,
                         pitch: n.isRest ? TradingSlotGrid.restPitch : n.pitch,
                         slots: n.durationSlots)
        }
        let phrase = UserPhrase(
            grid: grid,
            startSlot: turnStartAbsolute,
            lengthSlots: turnLength,
            slotsPerBar: config.slotsPerBar,
            rawNoteCount: slice.filter { !$0.isRest }.count,
            deviations: [],
            quantizeGrid: config.grid,
            beatPatterns: [])
        let measures = PhraseToMeasures.convert(phrase: phrase, bars: barContexts(for: segIdx))
        let tagged = TradingNoteTagger.tag(measures)
        let globalStartBar = segIdx * config.barsPerTurn
        JazzMidiPlayer.shared.playTradingSegment(measures: tagged,
                                                 globalStartMeasure: globalStartBar)
        if config.showOnDisplay {
            let ms = tagged
            DispatchQueue.main.async {
                TradingDisplay.shared.overlay(turnBars: ms, physicalStartBar: globalStartBar)
            }
        }
    }

    // MARK: - 用户段收尾（只记谱，不回喂）

    private func finalizeUserTurn() {
        let phrase = recorder.finish(endRawSlot: turnLength)
        let measures = PhraseToMeasures.convert(phrase: phrase, bars: barContexts(for: turnIndex))
        let cb = onUserPhrase
        let show = config.showOnDisplay
        let startBar = turnIndex * config.barsPerTurn
        DispatchQueue.main.async {
            cb?(phrase, measures)
            if show {
                let tagged = TradingNoteTagger.tag(measures)
                TradingDisplay.shared.overlay(turnBars: tagged, physicalStartBar: startBar)
            }
        }
    }

    // MARK: - 事件门控（同 Active：只收用户段，电脑段丢弃）

    private func handleEvent(_ ev: TradingMIDIEvent) {
        guard running else { return }
        let absolute = clock.slot(atNs: ev.hostTimeNs)
        let tol = 15.0
        if state != .userTurn, ev.isNoteOn {
            let idx = Int(floor((absolute + tol) / Double(turnLength)))
            let isUser = (idx % 2 == 0) == config.userStarts
            if idx >= 0, idx < config.maxTurns, isUser, idx != turnIndex {
                beginTurn(idx)
            }
        }
        guard state == .userTurn else { return }
        var relative = absolute - turnStart
        if ev.isNoteOn, relative < 0, relative > -tol { relative = 0 }
        if ev.isNoteOn {
            guard relative >= 0, relative < Double(turnLength) else { return }
        } else {
            guard relative >= 0 else { return }
        }
        recorder.handleRaw(pitch: ev.pitch,
                           velocity: ev.velocity,
                           isNoteOn: ev.isNoteOn,
                           rawSlot: min(relative, Double(turnLength)))
        eventsQueue.sync {
            self.turnEvents.append((pitch: ev.pitch, velocity: ev.velocity,
                                   isOn: ev.isNoteOn, slot: relative))
        }
        if ev.isNoteOn { onUserNote?(ev.pitch, ev.velocity, relative) }
    }

    /// 某 MIDI 事件时刻是否落在用户段（CoreMIDI 线程调用；同 Active :533）。
    private func isUserTurnSlot(_ hostNs: UInt64) -> Bool {
        let s = clock.slot(atNs: hostNs)
        let idx = Int(floor(s / Double(turnLength)))
        guard idx >= 0, idx < config.maxTurns else { return false }
        return (idx % 2 == 0) == config.userStarts
    }

    // MARK: - 和弦元数据

    private func barContexts(for idx: Int) -> [PhraseToMeasures.BarContext] {
        let firstBar = idx * config.barsPerTurn
        var out: [PhraseToMeasures.BarContext] = []
        for b in 0..<config.barsPerTurn {
            let i = firstBar + b
            if i < roadmap.count {
                let m = roadmap[i]
                out.append(.init(chord: m.chord,
                                 chordSlots: m.chordSlots,
                                 sectionName: m.sectionName,
                                 slotsPerMeasure: m.slotsPerMeasure))
            } else {
                out.append(.init(chord: "", chordSlots: [], sectionName: nil,
                                 slotsPerMeasure: config.slotsPerBar))
            }
        }
        return out
    }

    // MARK: - Live Notation 逐小节上屏（照搬 Active turnEvents 重放机制）

    private func progressTick() {
        guard running, state == .userTurn, config.barsPerTurn > 1 else { return }
        let elapsed = clock.slot(atNs: TradingHostClock.nowNanos()) - turnStart
        let spb = Double(config.slotsPerBar)
        guard elapsed >= spb + 60 else { return }
        let complete = Int(floor((elapsed - 60) / spb))
        let target = min(config.barsPerTurn - 1, complete)
        guard target > shownBars else { return }
        shownBars = target
        pushPartial(bars: target)
    }

    private func pushPartial(bars: Int) {
        let upto = bars * config.slotsPerBar
        guard upto > 0 else { return }
        let r = TradingRecorder()
        r.begin(startSlot: 0, lengthSlots: upto, quantizeGrid: config.grid,
                 inputLatencySlots: 0, slotsPerBar: config.slotsPerBar, adaptive: config.adaptive,
                 forceSwing: config.swing)
        let events = eventsQueue.sync { turnEvents }
        for e in events {
            let s = Int(e.slot.rounded())
            guard s >= 0, s < upto else { continue }
            r.handleRawSlot(pitch: e.pitch, velocity: e.velocity, isNoteOn: e.isOn, rawSlot: s)
        }
        let ph = r.finish(endRawSlot: upto)
        let ctx = Array(barContexts(for: turnIndex).prefix(bars))
        let ms = PhraseToMeasures.convert(phrase: ph, bars: ctx)
        guard config.showOnDisplay else { return }
        let tagged = TradingNoteTagger.tag(ms)
        let startBar = turnIndex * config.barsPerTurn
        DispatchQueue.main.async {
            TradingDisplay.shared.overlay(turnBars: tagged, physicalStartBar: startBar)
        }
    }

    // MARK: - 结束/拆除

    private func finish() {
        if state == .userTurn { finalizeUserTurn() }
        teardown(finishCurrent: false)
        setState(.finished, turn: turnIndex, start: turnStart)
        let cb = onFinished
        DispatchQueue.main.async { cb?() }
    }

    private func teardown(finishCurrent: Bool) {
        if finishCurrent, state == .userTurn { finalizeUserTurn() }
        running = false
        timer?.cancel(); timer = nil
        clickTimer?.cancel(); clickTimer = nil
        progressTimer?.invalidate(); progressTimer = nil
        clock.stop()
        let m = monitor
        let monOn = config.monitorEnabled
        DispatchQueue.main.async {
            JazzMidiPlayer.shared.stop()
            JazzMidiPlayer.shared.onNotePlay = nil
            TradingDisplay.shared.clearHighlight()
            if monOn { m?.stop() }
        }
        input?.onEvent = nil
        if state != .finished { setState(.idle, turn: turnIndex, start: turnStart) }
    }

    private func setState(_ s: TradingSession.State, turn: Int, start: Double) {
        state = s
        let cb = onStateChange
        DispatchQueue.main.async { cb?(s, turn, start) }
    }

    // MARK: - 数拍 click

    private func scheduleClicks(from anchor: UInt64) {
        let beatsPerBar = max(1, config.slotsPerBar / 120)
        let total = config.countInBars * beatsPerBar
        guard total > 0 else { return }
        let beatSec = 60.0 / max(1, config.bpm)
        let now = TradingHostClock.nowNanos()
        let delay = anchor > now ? Double(anchor - now) / 1_000_000_000.0 : 0
        var k = 0
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + delay, repeating: beatSec, leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            if k >= total { self.clickTimer?.cancel(); self.clickTimer = nil; return }
            JazzMidiPlayer.shared.click(accent: (k % beatsPerBar) == 0)
            k += 1
        }
        t.resume()
        clickTimer = t
    }
}
