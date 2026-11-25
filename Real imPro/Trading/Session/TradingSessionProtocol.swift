import Foundation

// MARK: - TradingSessionProtocol
// 抽象 Active/Passive 两种会话的共同接口，供 TradingCoordinator 持有。
// State 枚举复用 TradingSession.State（idle/countIn/userTurn/computerTurn/finished），
// Passive 段语义一致：userTurn=用户演奏段，computerTurn=电脑独奏段。
protocol TradingSessionProtocol: AnyObject {
    var state: TradingSession.State { get }
    var turnIndex: Int { get }
    var musicAnchorNs: UInt64 { get }

    var onStateChange: ((TradingSession.State, Int, Double) -> Void)? { get set }
    var onUserPhrase: ((UserPhrase, [GeneratedMeasure]) -> Void)? { get set }
    var onUserNote: ((Int, Int, Double) -> Void)? { get set }
    var onFinished: (() -> Void)? { get set }

    // input/monitor 可选，与 Active TradingSession.start 签名严格一致
    func start(roadmap: [GeneratedMeasure],
               input: TradingMIDIInput?,
               monitor: TradingMonitor?)
    func pause()
    func resume()
    func stop()
}
