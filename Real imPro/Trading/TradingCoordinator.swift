import Foundation
import SwiftUI
import Combine

// MARK: - Trading / Coordinator（M2-10 UI 接入）
//
// 界面与 TradingSession 之间的协调层（ObservableObject）：
//   · 组装并持有 session / MIDI 输入 / 实时回听；
//   · 把会话状态桥接成 SwiftUI 可观察的 @Published 状态；
//   · 暴露设置面板需要的参数绑定；
//   · 传输控制（start/pause/resume/stop）由工具栏调用。
//
// 线程：所有 @Published 仅在主线程更新（session 的 onStateChange / onFinished 已保证主线程）。
// 所有回调闭包统一 [weak self]，避免 coordinator 与 session 之间的循环引用。
@MainActor
final class TradingCoordinator: ObservableObject {

    // MARK: 会话状态（只读，驱动工具栏三键与面板置灰）

    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var phase: TradingSession.State = .idle
    @Published private(set) var turnIndex = -1

    // MARK: 面板参数（运行中置灰）

    @Published var userStarts = true
    @Published var countIn = true
    @Published var responseMode: TradingResponseMode = .modifyAndRectify
    @Published var grammarFile = "chord"
    @Published var transformMusician: String? = nil
    @Published var barsPerTurn = 4
    @Published var uiMode: TradingUIMode = .active
    /// Live Notation：用户弹奏时逐小节实时上屏（默认 false = 段末一次性，对齐 Java）
    @Published var liveNotation = false
    /// Passive 引擎选择（grammar / grammarAndTransform）
    @Published var passiveEngine: TradingPassiveSession.PassiveEngine = .grammar

    /// MIDI 输入设备连接状态（UI 显示用）
    @Published private(set) var midiDeviceSummary: String = "No MIDI device"

    /// Active / Passive 会话模式（Passive 第一档仅 Use Grammar 真响）。
    enum TradingUIMode { case active, passive }

    // MARK: 内部持有

    private var session: (any TradingSessionProtocol)?
    private var input: TradingMIDIInput?
    private var monitor: TradingMonitor?

    // MARK: 生命周期

    /// 启动一次 Trading 会话。
    /// - Parameters:
    ///   - roadmap: 伴奏和弦谱（当前 generatedSolo）
    ///   - bpm: 工具栏全局速度（启动时锁定）
    ///   - slotsPerBar: 每小节 slot（4/4=480，3/4=360）
    func start(roadmap: [GeneratedMeasure], bpm: Int, slotsPerBar: Int) {
        guard !isRunning, !roadmap.isEmpty else { return }   // [fix157] 空 roadmap 不启动，杜绝空白卡死

        let input = TradingMIDIInput()
        input.start()
        input.onDevicesChanged = { [weak self] devices in
            let connected = devices.filter { !$0.isOffline }
            if connected.isEmpty {
                self?.midiDeviceSummary = "No MIDI device"
            } else {
                self?.midiDeviceSummary = connected.map(\.name).joined(separator: ", ")
            }
        }
        // 初始化：start() 时设备已在线，不会触发 setup-changed 通知，手动刷一次 UI
        input.onDevicesChanged?(input.availableDevices())
        let monitor = TradingMonitor(program: 66)

        let maxTurns = max(1, roadmap.count / barsPerTurn)   // 覆盖整首：36 小节 / 4 = 9 轮

        let session: any TradingSessionProtocol
        switch uiMode {
        case .active:
            let config = TradingSession.Config(
                bpm: Double(bpm),
                barsPerTurn: barsPerTurn,
                countInBars: countIn ? 1 : 0,
                maxTurns: maxTurns,
                slotsPerBar: slotsPerBar,
                userStarts: userStarts,
                clickEnabled: countIn,
                responseMode: responseMode,
                grammarFile: grammarFile,
                transformMusician: transformMusician,
                liveNotation: liveNotation)
            session = TradingSession(config: config)
        case .passive:
            let cfg = TradingPassiveSession.Config(
                bpm: Double(bpm),
                barsPerTurn: max(1, barsPerTurn),
                countInBars: countIn ? 1 : 0,
                maxTurns: max(1, roadmap.count / max(1, barsPerTurn)),
                slotsPerBar: slotsPerBar,
                userStarts: userStarts,
                clickEnabled: countIn,
                grammarFile: grammarFile,
                transformMusician: transformMusician,
                passiveEngine: passiveEngine,
                liveNotation: liveNotation)
            session = TradingPassiveSession(config: cfg)
        }

        session.onStateChange = { [weak self] newPhase, idx, _ in
            self?.phase = newPhase
            self?.turnIndex = idx
        }
        session.onFinished = { [weak self] in
            self?.handleFinished()
        }
        session.start(roadmap: roadmap, input: input, monitor: monitor)

        self.session = session
        self.input = input
        self.monitor = monitor
        self.isRunning = true
        self.isPaused = false
    }

    /// 暂停：时钟、伴奏、电脑回应、回听一起冻结。
    func pause() {
        guard isRunning, !isPaused else { return }
        session?.pause()
        isPaused = true
    }

    /// 恢复：从暂停位置精确接着走。
    func resume() {
        guard isRunning, isPaused else { return }
        session?.resume()
        isPaused = false
    }

    /// 手动停止：终止会话并清回原谱。
    func stop() {
        guard isRunning else { return }
        session?.stop()
        teardownLocal()
        TradingDisplay.shared.clearHighlight()
    }

    // MARK: 私有

    /// 自然结束：保留累积谱面，只复位运行状态。
    private func handleFinished() {
        teardownLocal()
    }

    private func teardownLocal() {
        monitor?.stop()
        input?.stop()
        session = nil
        input = nil
        monitor = nil
        isRunning = false
        isPaused = false
        phase = .idle
        turnIndex = -1
    }
}
