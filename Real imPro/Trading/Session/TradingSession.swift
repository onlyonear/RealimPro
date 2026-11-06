import Foundation

// MARK: - Trading / Session / 会话状态机（M2-6）
//
// 纯新增文件：不修改任何现有文件。只使用已经存在的公开接口：
//   TradingClock        —— 与播放器共享同一锚点（M2-3 已验证同源）
//   TradingRecorder     —— 把一轮演奏落成 UserPhrase
//   PhraseToMeasures    —— 把 UserPhrase 翻成 [GeneratedMeasure]（M2-4）
//   TradingMonitor      —— 实时回听（M2-5）
//   JazzMidiPlayer      —— 播放伴奏（playWithAccompaniment + externalAnchorNs）
//
// M2-7 已接入电脑回应（一期：Repeat / Repeat and Rectify，见 TradingResponder）：
//   电脑轮到点由高精度定时器触发 → 读上一轮用户乐句 → 生成回应 → 绝对锚点播放。
//   界面（M2-8）仍未做；其余 6 种回应模式二期。
//
// 时间轴（关键）：
//   · 播放器锚点 = 会话锚点 = clock 的 anchorNs（三者同一个数，M2-3 已证同源）。
//   · clock.start(countInSlots: 数拍小节数 × 每小节 slot) 让 session slot 0 = 用户第一轮开始，
//     数拍期间 currentSlot 为负 —— 伴奏照常在放，只是"还没轮到你"。
//   · 第 n 轮 = [n·turnLen, (n+1)·turnLen)，n 偶数是用户、奇数是电脑（谁先由 whoStarts 决定）。

final class TradingSession: TradingSessionProtocol {

    // MARK: - 配置

    struct Config {
        /// 会话内锁定的速度
        var bpm: Double = 120
        /// 每轮小节数（trading fours = 4）
        var barsPerTurn: Int = 4
        /// 数拍小节数（0 = 不数拍）。数拍期间伴奏在响、但不算任何人的轮次。
        var countInBars: Int = 1
        /// 总轮数（含电脑轮）
        var maxTurns: Int = 4
        /// 每小节 slot（4/4 = 480，3/4 = 360）
        var slotsPerBar: Int = TradingSettings.slotsPerBar4_4
        /// 量化档
        var grid: TradingQuantizeGrid = .eighth
        /// 输入延迟补偿（slot）
        var inputLatencySlots: Int = 0
        /// 谁先开始
        var userStarts: Bool = true
        /// 是否实时回听
        var monitorEnabled: Bool = true
        /// 数拍是否敲 click（"嗒嗒嗒嗒"）；关掉则只有乐队、不敲
        var clickEnabled: Bool = true
        /// [M2-1b] 自适应网格：每拍自己选细分（十六分与三连可共存）。关掉则用 grid 单网格。
        var adaptive: Bool = true
        /// [Swing 开关] 开着：1~2 音的拍一律写普通八分（爵士惯例，不再靠猜）
        var swing: Bool = true
        /// 是否把本轮结果推到五线谱。回放用的第二遍必须关掉，否则会用"空录音"把谱面抹成休止。
        var showOnDisplay: Bool = true
        /// 伴奏风格
        var style: String = "sty:swing"
        /// [M2-7] 电脑回应模式（开机默认 Repeat and Rectify）
        var responseMode: TradingResponseMode = .repeatAndRectify
        /// [M2-9] Use Grammar 语法文件（默认 "chord"）
        var grammarFile: String = "chord"
        /// [M2-9] Use Transform 大师表（nil → My 兜底）
        var transformMusician: String? = nil
        /// Live Notation：用户段逐小节实时上屏（false = 段末一次性，对齐 Java）
        var liveNotation: Bool = false
        /// [M2-9] Modify 分支（nil=生产真随机；DEBUG 对拍注入 0/1/2/3）
        var modifyChoice: Int? = nil
    }

    enum State: String {
        case idle, countIn, userTurn, computerTurn, finished
        var label: String {
            switch self {
            case .idle:         return "空闲"
            case .countIn:      return "数拍中"
            case .userTurn:     return "轮到你"
            case .computerTurn: return "轮到电脑"
            case .finished:     return "已结束"
            }
        }
    }

    // MARK: - 对外

    private(set) var state: State = .idle
    private(set) var turnIndex: Int = -1
    /// 乐队/第一轮开始的主机时刻（纳秒）——供注入器等外部对齐用
    private(set) var musicAnchorNs: UInt64 = 0

    // [M2-6b-2] 滞后逐小节上屏：缓存本轮已收事件，按"已封闭的小节"重放给记谱层
    private var turnEvents: [(pitch: Int, velocity: Int, isOn: Bool, slot: Double)] = []
    private let eventsQueue = DispatchQueue(label: "trading.session.events")
    private var progressTimer: Timer?
    private var shownBars = 0

    var config: Config
    /// 状态变化（主线程回调）：(新状态, 轮次序号, 该轮起始 slot)
    var onStateChange: ((State, Int, Double) -> Void)?
    /// 用户一轮结束（主线程回调）：(乐句, 记谱小节)
    var onUserPhrase: ((UserPhrase, [GeneratedMeasure]) -> Void)?
    /// 用户轮内每收到一个 note-on（会话队列回调）：(音高, 力度, 本轮相对 slot)
    var onUserNote: ((Int, Int, Double) -> Void)?
    /// 会话结束（主线程回调）
    var onFinished: (() -> Void)?

    // MARK: - 内部

    private let clock = TradingClock()
    private let recorder = TradingRecorder()
    private let queue = DispatchQueue(label: "trading.session", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var clickTimer: DispatchSourceTimer?
    private var roadmap: [GeneratedMeasure] = []
    private var input: TradingMIDIInput?
    private var monitor: TradingMonitor?
    private var running = false
    /// [M2-7] 上一轮用户乐句（电脑轮据此生成回应）
    private var lastUserPhrase: UserPhrase?
    /// [M2-7] 电脑轮精确触发定时器（deadline = 电脑轮起点）
    private var computerTurnTimer: DispatchSourceTimer?

    /// 本轮长度（slot）
    private var turnLength: Int { config.barsPerTurn * config.slotsPerBar }
    /// 数拍长度（slot）
    private var countInSlots: Int { config.countInBars * config.slotsPerBar }
    /// 本轮起点（session 相对 slot，0 = 第一轮开始）
    private var turnStart: Double { Double(turnIndex) * Double(turnLength) }
    /// 本轮起点（整曲绝对 slot，用于 UserPhrase.startSlot 与伴奏对位）
    private var turnStartAbsolute: Int { countInSlots + turnIndex * turnLength }

    init(config: Config = Config()) {
        self.config = config
    }

    // [D-P6] 探针：释放时打印一次，用于与 teardown 日志对照判断异步拆除是否被跳过（DEBUG-only）
    deinit {
        dprint("[D-P6] deinit released running=\(running) state=\(state.rawValue) turnIndex=\(turnIndex)")
    }

    // MARK: - 启停

    /// 开始一次会话。
    /// - Parameters:
    ///   - roadmap: 伴奏和弦谱（`notes` 可为空；只要 `chord`/`chordSlots` 正确）。
    ///              长度必须够覆盖「全部轮次」（roadmap[0] 锚在"乐队进"，数拍 click 在它之前，不占 roadmap 小节）。
    ///   - input: 已连好键盘的输入源（nil = 不录音，只跑时间轴）
    ///   - monitor: 回听（nil = 不回听）
    func start(roadmap: [GeneratedMeasure],
               input: TradingMIDIInput? = nil,
               monitor: TradingMonitor? = nil) {
        let setup = { [weak self] in
            guard let self, !self.running else { return }
            self.roadmap = roadmap
            // [M2-8d] 铺完整累积谱：和弦/段落/chordSlots 常驻，旋律轨先按 chordSlots 分段休止+挂和弦字母。
            // 受 showOnDisplay 门控（回放第二遍 showOnDisplay=false 时不铺、不覆盖）。
            if self.config.showOnDisplay {
                TradingDisplay.shared.reset(roadmap: roadmap)
            }
            self.input = input
            self.monitor = monitor
            self.running = true
            self.turnIndex = -1
            self.setState(.idle, turn: -1, start: 0)

            // 1) 起伴奏 + 数拍：先敲 countInBars 小节 click，乐队在 click 结束处进
            //    （用户明确要求"嗒嗒嗒嗒"；伴奏当数拍容易混淆）
            let player = JazzMidiPlayer.shared
            // [M2-8f] 绑定逐音回调 → 累积谱高亮（onNotePlay 已在主线程触发）。
            // 闭包只更新 TradingDisplay 高亮、不碰 ContentView 的 isPlaying，所以电脑轮结尾的 ""
            // 只清高亮，不会被误判为"整曲结束"而把播放状态置 false。
            player.onNotePlay = { noteId in
                TradingDisplay.shared.setHighlight(noteId)
            }
            let anchor = TradingHostClock.nowNanos() &+ 500_000_000          // click 起点
            let countInNs = UInt64(Double(self.countInSlots) * TradingClock.nsPerSlot(bpm: self.config.bpm))
            let musicAnchor = anchor &+ countInNs                            // 乐队 / 第一轮起点
            self.musicAnchorNs = musicAnchor

            if self.config.clickEnabled, self.config.countInBars > 0 {
                player.enableClick()                                          // 主线程：懒挂载打击乐采样器
                self.scheduleClicks(from: anchor)
            }

            player.playWithAccompaniment(solo: roadmap,
                                         bpm: self.config.bpm,
                                         style: self.config.style,
                                         startMeasure: 0,
                                         externalAnchorNs: musicAnchor)

            // 2) 会话时钟：锚点取 click 起点，countInSlots 让 slot 0 正好落在乐队进来的那一刻
            self.clock.start(bpm: self.config.bpm, anchorNs: anchor, countInSlots: self.countInSlots)

            // 3) 萨克斯采样器（电脑回应与回听共用）：无条件确保存在（enableMonitor 幂等，主线程）。
            //    回听开关只控制"是否转发用户实时弹奏"，不影响电脑轮回应发声。
            player.enableMonitor(program: 66)
            if self.config.monitorEnabled, let m = monitor { m.start() }

            // 4) MIDI fan-out：录音（只在用户轮）+ 回听（也只在用户轮，电脑轮不与回应叠加）
            input?.onEvent = { [weak self] ev in
                guard let self, !self.clock.isPaused else { return }  // 暂停时不回听、不录音
                // [fix158] 回听转发：note-on 仅"用户轮"（电脑轮静音，避免与电脑回应叠加）；
                // note-off 不受轮次门控、始终转发——它只负责收掉此前已发出的音，
                // 否则跨边界长音的 note-off 落电脑轮会被丢弃，导致回听采样器挂音。
                // 只读 clock（带锁）与会话内恒定的 config/turnLength，CoreMIDI 线程安全。
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

            // 5) 25ms 轮询时钟（只决定"轮次"，音频由播放器自己的绝对时刻驱动）
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now() + 0.05, repeating: 0.025, leeway: .milliseconds(2))
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            self.timer = t
        }
        if Thread.isMainThread { setup() } else { DispatchQueue.main.async(execute: setup) }
    }

    /// 手动停止（不回调 onFinished）
    func stop() {
        // [weakfix 20261102] 强引用保证 teardown 一定执行：coordinator.stop() 调本方法后会立刻
        // teardownLocal() 把 session 置 nil。若用 [weak self]，闭包执行时 session 可能已被释放、
        // teardown 整体跳过（headless 2000 次 weak 版 95%+ 跳过，strong 版 0 跳过）。
        // 一次性 queue 任务不被 self 持有，强引用不会形成循环引用（与本文件 :209 handleEvent 派发同构），
        // 闭包执行完即释放对 self 的强引用。
        queue.async { self.teardown(finishCurrent: true) }
    }

    // MARK: - 暂停 / 恢复（M2-10）

    /// 暂停：冻结时钟、取消电脑轮定时器、挂起进度上屏，并挂起播放器；收掉回听防挂音。
    func pause() {
        queue.async { [weak self] in
            guard let self, self.running, !self.clock.isPaused else { return }
            self.clock.pause()
            self.computerTurnTimer?.cancel()
            self.computerTurnTimer = nil
            self.progressTimer?.invalidate()
            DispatchQueue.main.async {
                JazzMidiPlayer.shared.pause()
                if self.config.monitorEnabled {
                    JazzMidiPlayer.shared.monitorAllNotesOff()
                }
            }
        }
    }

    /// 恢复：时钟解冻、用户轮重挂电脑轮定时器、播放器恢复。
    func resume() {
        queue.async { [weak self] in
            guard let self, self.running, self.clock.isPaused else { return }
            self.clock.resume()
            if self.state == .userTurn {
                self.scheduleComputerTurn()
            }
            DispatchQueue.main.async { JazzMidiPlayer.shared.resume() }
        }
    }

    // MARK: - 事件

    private func handleEvent(_ ev: TradingMIDIEvent) {
        guard running else { return }
        let absolute = clock.slot(atNs: ev.hostTimeNs)
        // 正拍容差：真人起音常常比拍点早十几毫秒（尤其从数拍进乐队那一拍），
        // 3 slot(12.5ms) 不够 → 实测丢掉第一个音、小节开头变成休止。放到 15 slot(62ms)。
        let tol = 15.0
        // [D-P4] 边界补录是否触发（DEBUG-only 探针，不改变任何数据）
        var dBoundary = false

        // [边界补录] 轮询 25ms 才切状态，正拍第一个音常常"早于切换"到达而被丢掉。
        // 这里按事件自己的时间戳判断：若它已经落在某个用户轮里，就立即切过去再收。
        if state != .userTurn, ev.isNoteOn {
            let idx = Int(floor((absolute + tol) / Double(turnLength)))
            let isUser = (idx % 2 == 0) == config.userStarts
            if idx >= 0, idx < config.maxTurns, isUser, idx != turnIndex {
                beginTurn(idx)
                dBoundary = true
            }
        }

        guard state == .userTurn else {
            dprint("[D-P4] blocked-by-state \(ev.isNoteOn ? "ON" : "OFF") pitch=\(ev.pitch) absolute=\(String(format: "%.1f", absolute)) state=\(state.rawValue) boundary=\(dBoundary)")
            return
        }
        if ev.isNoteOn {
            dprint("[D-P4] note-on accepted pitch=\(ev.pitch) absolute=\(String(format: "%.1f", absolute)) boundary=\(dBoundary)")
        }
        // 录音器要的是「本轮相对 slot」；clock 给的是「会话相对 slot」——必须减掉本轮起点。
        // （TradingRecorder 内部把 raw slot 夹在 [0, turnLength)，不减会把整轮音挤到末尾。）
        var relative = absolute - turnStart
        if ev.isNoteOn, relative < 0, relative > -tol { relative = 0 }
        if ev.isNoteOn {
            // 越过本轮末尾的 note-on 丢弃（否则会被夹成一枚假音）
            #if DEBUG
            if relative < 0 {
                print("[TRADING-SESSION] 丢弃过早的 note-on：relative=\(String(format: "%.1f", relative)) slot（约 \(Int(-relative * 4.17)) ms 早）")
            }
            #endif
            guard relative >= 0, relative < Double(turnLength) else { return }
        } else {
            // note-off 仍要送达，才能把最后一个音收干净（夹到本轮末尾）
            guard relative >= 0 else { return }
        }
        eventsQueue.sync {
            turnEvents.append((pitch: ev.pitch, velocity: ev.velocity, isOn: ev.isNoteOn, slot: relative))
        }
        recorder.handleRaw(pitch: ev.pitch,
                           velocity: ev.velocity,
                           isNoteOn: ev.isNoteOn,
                           rawSlot: min(relative, Double(turnLength)))
        if ev.isNoteOn { onUserNote?(ev.pitch, ev.velocity, relative) }
    }

    // MARK: - 轮询

    private func tick() {
        guard running else { return }
        let s = clock.currentSlot()

        // 数拍：slot < 0
        if s < 0 {
            if state != .countIn, turnIndex < 0 { setState(.countIn, turn: -1, start: 0) }
            return
        }

        let idx = Int(floor(s / Double(turnLength)))
        if idx >= config.maxTurns {
            dprint("[D-P2] tick s=\(String(format: "%.1f", s)) idx=\(idx) >= maxTurns=\(config.maxTurns) -> finish")
            finish()
            return
        }
        if idx != turnIndex {
            dprint("[D-P2] tick s=\(String(format: "%.1f", s)) idx=\(idx) turnIndex=\(turnIndex) -> beginTurn(\(idx))")
            beginTurn(idx)
        }
        // [Live Notation] 仅开关开启时逐小节上屏，关闭时段末一次性（对齐 Java）
        if config.liveNotation {
            progressTick()
        }
    }

    private func beginTurn(_ idx: Int) {
        guard idx != turnIndex else {
            dprint("[D-P3] beginTurn(\(idx)) idempotent-skip turnIndex=\(turnIndex)")
            return
        }   // [P2-3] 幂等：三个入口都已判断，此处双保险
        let oldState = state
        // 上一轮若是用户轮，先收尾
        if state == .userTurn { finalizeUserTurn() }

        turnIndex = idx
        let isUser = (idx % 2 == 0) == config.userStarts
        dprint("[D-P3] beginTurn(\(idx)) oldState=\(oldState.rawValue) isUser=\(isUser) -> \(isUser ? "userTurn" : "computerTurn")")

        if isUser {
            recorder.begin(startSlot: turnStartAbsolute,
                           lengthSlots: turnLength,
                           quantizeGrid: config.grid,
                           inputLatencySlots: config.inputLatencySlots,
                           slotsPerBar: config.slotsPerBar,
                           adaptive: config.adaptive,
                           forceSwing: config.swing)
            eventsQueue.sync { turnEvents.removeAll(keepingCapacity: true) }
            shownBars = 0
            // [M2-7] 为紧随其后的电脑轮挂精确定时器；清空上一轮乐句
            lastUserPhrase = nil
            scheduleComputerTurn()
            // [Live Notation] 开启时逐小节上屏
            if config.liveNotation {
                let t = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
                    self?.progressTick()
                }
                progressTimer = t
            }
            setState(.userTurn, turn: idx, start: turnStart)
        } else {
            // 进入此分支时 turnIndex 已推进、用户轮已由函数开头收尾（lastUserPhrase 已就位）
            // [fix158] 兜底收掉用户轮残留的回听音（双保险：即使 note-off 因任何原因未到达，也不挂进电脑轮）。
            self.monitor?.allNotesOff()
            setState(.computerTurn, turn: idx, start: turnStart)
            performComputerTurn()
        }
    }

    private func finalizeUserTurn() {
        progressTimer?.invalidate()
        progressTimer = nil
        let phrase = recorder.finish(endRawSlot: turnLength)
        // [M2-7] 保存给电脑轮（空乐句保持 nil，电脑轮自然静默）
        lastUserPhrase = phrase.isEmpty ? nil : phrase
        let measures = PhraseToMeasures.convert(phrase: phrase, bars: barContexts(for: turnIndex))
        let cb = onUserPhrase
        let show = config.showOnDisplay
        let startBar = turnIndex * config.barsPerTurn
        DispatchQueue.main.async {
            cb?(phrase, measures)
            if show {
                // [M2-8d] 累积谱：打颜色 tag + 重算和弦标注后，叠加到本轮物理小节（替换旧 show 整张替换）。
                let tagged = TradingNoteTagger.tag(measures)
                TradingDisplay.shared.overlay(turnBars: tagged, physicalStartBar: startBar)
            }
        }
    }

    // MARK: - [M2-7] 电脑回应

    /// 用户轮开始时调用：为"下一轮电脑轮"挂一次性高精度定时器（deadline = 电脑轮起点纳秒）。
    private func scheduleComputerTurn() {
        computerTurnTimer?.cancel()
        let nextIdx = turnIndex + 1
        guard nextIdx < config.maxTurns else { return }      // 后面没有电脑轮（末轮）
        let computerSlot = Double(nextIdx) * Double(turnLength)
        let anchorNs = clock.ns(atSlot: computerSlot)
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: DispatchTime(uptimeNanoseconds: anchorNs),
                   leeway: .milliseconds(2))
        t.setEventHandler { [weak self] in self?.onComputerTurnDeadline() }
        t.resume()
        computerTurnTimer = t
    }

    /// 定时器触发（session queue）：与 tick 同一判断，按 clock 计算当前轮次，避免重复/越界推进。
    private func onComputerTurnDeadline() {
        guard running else { return }
        let s = clock.currentSlot()
        let idx = Int(floor(s / Double(turnLength)))
        if idx >= 0, idx != turnIndex, idx < config.maxTurns {
            beginTurn(idx)
        }
    }

    /// 生成并播放电脑回应（仅由 beginTurn 电脑分支调用；此时 turnIndex/turnStart 已是电脑轮）。
    private func performComputerTurn() {
        // [fix 电脑先弹] 对齐 Java ActiveTrading.startTrading():760
        // 电脑先弹第一段（turnIndex==0 && !userStarts）没有用户乐句可回应，
        // 从 grammar solo 抽第一段播放，不是静默。后续轮次正常走 lastUserPhrase 回应链。
        if lastUserPhrase == nil, turnIndex == 0, !config.userStarts {
            playGrammarOpeningTurn()
            return
        }
        guard let phrase = lastUserPhrase else {
            return
        }

        // ① 用户乐句 → TradingSlotNote（休止 pitch = -1）
        let userNotes = phrase.notes.map {
            TradingSlotNote(pitch: $0.pitch, startSlot: $0.startSlot,
                            durationSlots: $0.durationSlots, isRest: $0.pitch < 0)
        }

        // ② 生成回应（responseChords = 电脑轮和弦；context 携带新模式参数）
        let turnContext = TradingTurnContext(
            grammarFile: config.grammarFile,
            modifyChoice: config.modifyChoice,
            transformMusician: config.transformMusician,
            bpm: Int(config.bpm))
        let response = TradingResponder.respond(
            notes: userNotes,
            responseChords: computerChordBlocks(),
            mode: config.responseMode,
            toneSet: { TradingChordToneSet.toneSet(chordName: $0) },
            context: turnContext
        )

        // ③ 合成乐句（复用用户网格/beatPatterns）→ 渲染（完整防重叠/tie/三连）
        let responsePhrase = makeSyntheticPhrase(response, template: phrase)
        let responseMeasures = PhraseToMeasures.convert(
            phrase: responsePhrase, bars: barContexts(for: turnIndex))
        let tagged = TradingNoteTagger.tag(responseMeasures)   // [M2-8d] 颜色 + 和弦标注

        // ④ 播放电脑回应：复用 JazzMidiPlayer 旋律轨（与其他链路同一段 swing/力度/延音代码），
        //    全局物理起始小节 = turnIndex*barsPerTurn；不重新生成伴奏、不打断伴奏。
        //    （M2-8f 才绑定 onNotePlay 让 ContentView 显示高亮/滚动；本批先让发声与 swing 对齐。）
        let globalStartBar = self.turnIndex * self.config.barsPerTurn
        JazzMidiPlayer.shared.playTradingSegment(measures: tagged,
                                                 globalStartMeasure: globalStartBar)

        // ⑤ 上屏（主线程）：累积谱叠加到电脑轮物理小节
        if config.showOnDisplay {
            let ms = tagged
            let startBar = self.turnIndex * self.config.barsPerTurn
            DispatchQueue.main.async {
                TradingDisplay.shared.overlay(turnBars: ms, physicalStartBar: startBar)
            }
        }
        #if DEBUG
        let chordNames = computerChordBlocks().map { $0.name }
        let compactChords = chordNames.reduce(into: [String]()) { acc, n in if acc.last != n { acc.append(n) } }
        print("[TRADING-SESSION] 电脑轮 \(turnIndex)：回应 \(response.filter { !$0.isRest }.count) 音，和弦 \(compactChords.joined(separator: " "))")
        let noteSeq = response.sorted { $0.startSlot < $1.startSlot }.map { n -> String in
            n.isRest ? "R@\(n.startSlot)" : "\(n.pitch)@\(n.startSlot)x\(n.durationSlots)"
        }.joined(separator: " ")
        print("[TRADING-SESSION] 电脑轮 \(turnIndex) 逐音：\(noteSeq)")
        #endif
    }

    /// [fix 电脑先弹] 电脑先弹第一段：从 grammar solo 抽第 0 个 quantum 播放。
    /// 对齐 Java ActiveTrading:760 `extractFromGrammarSolo(0, slotsPerTurn)`。
    private func playGrammarOpeningTurn() {
        let blocks = computerChordBlocks()
        guard !blocks.isEmpty else { return }
        let solo = TradingModeGenerators.useGrammar(
            responseChords: blocks,
            grammarFile: config.grammarFile,
            bpm: Int(config.bpm))
        let segStart = 0
        let segEnd = turnLength
        let slice = solo.compactMap { n -> TradingSlotNote? in
            guard n.startSlot >= segStart, n.startSlot < segEnd else { return nil }
            return TradingSlotNote(pitch: n.pitch,
                                   startSlot: n.startSlot - segStart,
                                   durationSlots: n.durationSlots,
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
        let measures = PhraseToMeasures.convert(phrase: phrase, bars: barContexts(for: turnIndex))
        let tagged = TradingNoteTagger.tag(measures)
        let globalStartBar = turnIndex * config.barsPerTurn
        JazzMidiPlayer.shared.playTradingSegment(measures: tagged,
                                                 globalStartMeasure: globalStartBar)
        if config.showOnDisplay {
            let ms = tagged
            let startBar = turnIndex * config.barsPerTurn
            DispatchQueue.main.async {
                TradingDisplay.shared.overlay(turnBars: ms, physicalStartBar: startBar)
            }
        }
    }

    /// 电脑轮和弦块：用每小节 chordSlots（支持小节内换和弦），startSlot 相对电脑轮起点。
    private func computerChordBlocks() -> [TradingChordBlock] {
        var blocks: [TradingChordBlock] = []
        let spb = config.slotsPerBar
        for (b, ctx) in barContexts(for: turnIndex).enumerated() {
            let barBase = b * spb
            if ctx.chordSlots.isEmpty {
                blocks.append(TradingChordBlock(name: ctx.chord,
                                                startSlot: barBase, durationSlots: spb))
                continue
            }
            for (ci, cs) in ctx.chordSlots.enumerated() {
                let start = barBase + cs.startSlot
                let end = ci + 1 < ctx.chordSlots.count
                    ? barBase + ctx.chordSlots[ci + 1].startSlot
                    : barBase + spb
                blocks.append(TradingChordBlock(name: cs.chord,
                                                startSlot: start, durationSlots: max(1, end - start)))
            }
        }
        return blocks
    }

    /// 回应 slot 音符写回网格 → 合成 UserPhrase（convert 只用相对网格，不吃 startSlot；
    /// startSlot 仍填电脑轮绝对位置以保持语义一致）。
    private func makeSyntheticPhrase(_ response: [TradingSlotNote],
                                     template: UserPhrase) -> UserPhrase {
        var grid = TradingSlotGrid(capacity: turnLength)
        for n in response {
            grid.setUnit(at: n.startSlot,
                         pitch: n.isRest ? TradingSlotGrid.restPitch : n.pitch,
                         slots: n.durationSlots)
        }
        return UserPhrase(
            grid: grid,
            startSlot: turnStartAbsolute,
            lengthSlots: turnLength,
            slotsPerBar: config.slotsPerBar,
            rawNoteCount: response.filter { !$0.isRest }.count,
            deviations: [],
            quantizeGrid: template.quantizeGrid,
            beatPatterns: template.beatPatterns)
    }

    /// [P1-2] 某 MIDI 事件时刻是否落在用户轮（CoreMIDI 线程调用；clock 带锁，config/turnLength 会话内恒定）。
    /// 无 tol：回听严格按事件时刻的轮次（回听不需要录音的边界补录，加 tol 会误吞轮末约 62ms 的回听）。
    private func isUserTurnSlot(_ hostNs: UInt64) -> Bool {
        let s = clock.slot(atNs: hostNs)
        let idx = Int(floor(s / Double(turnLength)))
        guard idx >= 0, idx < config.maxTurns else { return false }
        return (idx % 2 == 0) == config.userStarts
    }

    // MARK: - [M2-6b-2] 滞后逐小节上屏

    /// 每 0.4 秒检查：把"已经封闭"的小节先画出去（滞后约半拍到一拍，约 0.3~2 秒）。
    private func progressTick() {
        guard running, state == .userTurn, config.barsPerTurn > 1 else { return }
        let elapsed = clock.slot(atNs: TradingHostClock.nowNanos()) - turnStart
        let spb = Double(config.slotsPerBar)
        guard elapsed >= spb + 60 else { return }                 // 至少唱完 1 小节 + 半拍
        let complete = Int(floor((elapsed - 60) / spb))            // 已封闭小节数（保守半拍）
        let target = min(config.barsPerTurn - 1, complete)         // 最后一小节留给整轮收尾
        guard target > shownBars else { return }
        shownBars = target
        pushPartial(bars: target)
    }

    /// 用已收事件重放到第 bars 小节末，转成谱推给显示桥（不动正在录音的 recorder）
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
        let tagged = TradingNoteTagger.tag(ms)          // [M2-8d] 颜色 + 和弦标注
        #if DEBUG
        print("[TRADING-SESSION] 逐小节上屏：前 \(bars) 小节（\(tagged.reduce(0) { $0 + $1.notes.count }) 个符）")
        #endif
        let startBar = turnIndex * config.barsPerTurn
        DispatchQueue.main.async {
            // [M2-8d] 累积谱：只覆盖本轮前 bars 个物理小节，其余小节保持骨架/前几轮内容不动
            TradingDisplay.shared.overlay(turnBars: tagged, physicalStartBar: startBar)
        }
    }

    /// 从 roadmap 取本轮对应小节的和弦元数据
    private func barContexts(for idx: Int) -> [PhraseToMeasures.BarContext] {
        // [M2-7 修复 off-by-one] roadmap[0] 锚在"乐队进"(musicAnchor = clock slot 0)，数拍 click 在它之前
        // 独立播放、不占 roadmap 小节；本轮物理小节直接从 idx*barsPerTurn 起算。
        // 此前误加 countInBars，导致用户轮记谱标注与电脑轮 Rectify 取到的和弦整体晚 1 小节、末轮越界。
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

    private func finish() {
        if state == .userTurn { finalizeUserTurn() }
        teardown(finishCurrent: false)
        setState(.finished, turn: turnIndex, start: turnStart)
        let cb = onFinished
        DispatchQueue.main.async { cb?() }
    }

    private func teardown(finishCurrent: Bool) {
        dprint("[D-P6] teardown enter finishCurrent=\(finishCurrent) state=\(state.rawValue) turnIndex=\(turnIndex)")
        if finishCurrent, state == .userTurn { finalizeUserTurn() }
        running = false
        computerTurnTimer?.cancel(); computerTurnTimer = nil   // [M2-7] 取消电脑轮定时器
        timer?.cancel(); timer = nil
        clickTimer?.cancel(); clickTimer = nil
        progressTimer?.invalidate(); progressTimer = nil
        clock.stop()
        // 【线程】停播放器/停回听走主线程（音频节点操作不在串行队列上做）
        let m = monitor
        let monOn = config.monitorEnabled
        DispatchQueue.main.async {
            // JazzMidiPlayer.stop() 已 cancel segmentTask（电脑回应）并对 sampler 全通道松键，
            // 中途退出时回应立即停、不会继续响完（M2-7/P1-5 的同等覆盖）。
            JazzMidiPlayer.shared.stop()
            JazzMidiPlayer.shared.onNotePlay = nil   // [M2-8f] 解绑逐音回调，避免残留到普通播放
            TradingDisplay.shared.clearHighlight()   // [M2-8d] 清残留高亮；谱面保留（退出 Trading 模式时再 clear，留 M2-8 UI）
            if monOn { m?.stop() }
        }
        input?.onEvent = nil
        if state != .finished { setState(.idle, turn: turnIndex, start: turnStart) }
    }

    private func setState(_ s: State, turn: Int, start: Double) {
        state = s
        dprint("[D-P1] setState -> \(s.rawValue) turn=\(turn) start=\(String(format: "%.1f", start)) clockSlot=\(String(format: "%.1f", clock.currentSlot()))")
        let cb = onStateChange
        DispatchQueue.main.async { cb?(s, turn, start) }
    }

    // MARK: - 数拍 click

    /// 从 anchor 开始，按拍敲 `countInBars × 每小节拍数` 下（每小节第一拍加重）
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

    // MARK: - 诊断

    var statusLine: String {
        String(format: "%@ 轮%d slot=%.1f 速度=%.0f 每轮%d小节",
               state.label, turnIndex, turnStart, config.bpm, config.barsPerTurn)
    }
}
