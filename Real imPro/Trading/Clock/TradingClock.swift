import Foundation

// MARK: - Trading / Clock / 主时钟
//
// M1 · 纯新增 · 不依赖任何现有类型
//
// 语义对齐 Java:
//   src/imp/midi/MidiSynth.java:306-326  getSlot() = floor(120 × tickPos / 480) − countInOffset
//   src/imp/midi/MidiSynth.java:284-299  setSlot() = setTickPosition(slot × ppqn / BEAT)
//
// 【与现有播放器的关系 —— §2.2.1 隐藏耦合】
// 现有 `JazzMidiPlayer.playWithAccompaniment` 在**内部**自设 private anchor
// （MidiPlayer/JazzMidiPlayer.swift:513 `tempoAnchorEffectiveNs = DispatchTime.now()...`），
// 不接受外部传入、也无法读取。因此本时钟是**独立锚点**：两者之间存在一个未知偏差 Δ。
// M1 只提供测量工具（TradingAnchorProbe）与门限判定，**不改任何现有代码**。

/// Trading 的 slot 时钟。纯算术 + 单调时钟，不含任何定时器/回调。
///
/// 0 点定义：**count-in 结束、音乐正文第 0 slot 的时刻**。
/// 因此 count-in 期间 `currentSlot()` 为**负值**（对齐"乐手在数拍时还没进正式演奏"的语义）。
final class TradingClock {

    /// 1 拍 = 120 slot（对齐 imp/Constants.java:48）
    static let slotsPerBeat: Double = 120.0

    private let lock = NSLock()

    // 锚点
    private var anchorNs: UInt64 = 0
    private var bpm: Double = 120.0
    private var countInSlots: Int = 0

    // 暂停
    private var paused = false
    private var pauseStartNs: UInt64 = 0
    private var totalPausedNs: UInt64 = 0

    private var running = false

    // MARK: - 生命周期

    /// 起算。
    /// - Parameters:
    ///   - bpm: 会话内**锁定**的 Tempo（用户已拍板）
    ///   - anchorNs: 锚点主机时间（纳秒）。务必用**同一次** `TradingHostClock.nowNanos()` 取值，
    ///               并在紧接着启动伴奏，以最小化 §2.2.1 的 Δ。
    ///   - countInSlots: 数拍长度（slot）；0 = 不数拍
    func start(bpm: Double, anchorNs: UInt64, countInSlots: Int = 0) {
        lock.lock(); defer { lock.unlock() }
        self.bpm = max(20, min(400, bpm))
        self.anchorNs = anchorNs
        self.countInSlots = max(0, countInSlots)
        self.totalPausedNs = 0
        self.pauseStartNs = 0
        self.paused = false
        self.running = true
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        running = false
        paused = false
        totalPausedNs = 0
    }

    /// 暂停（对齐现有"后台真暂停"语义：暂停期间**时钟不走**）
    func pause() {
        lock.lock(); defer { lock.unlock() }
        guard running, !paused else { return }
        paused = true
        pauseStartNs = TradingHostClock.nowNanos()
    }

    func resume() {
        lock.lock(); defer { lock.unlock() }
        guard running, paused else { return }
        let now = TradingHostClock.nowNanos()
        if now > pauseStartNs { totalPausedNs &+= (now - pauseStartNs) }
        pauseStartNs = 0
        paused = false
    }

    /// 是否处于暂停（只读，供 session 输入守卫与状态判断）
    var isPaused: Bool {
        lock.lock(); defer { lock.unlock() }
        return paused
    }

    // MARK: - 换算

    /// 每个 slot 多少纳秒：`(60 / bpm) / 120 × 1e9`
    /// （与现有播放器同一公式：MidiPlayer/JazzMidiPlayer.swift:414）
    var nsPerSlot: Double {
        lock.lock(); defer { lock.unlock() }
        return Self.nsPerSlot(bpm: bpm)
    }

    static func nsPerSlot(bpm: Double) -> Double {
        (60.0 / max(1, bpm)) / slotsPerBeat * 1_000_000_000.0
    }

    private func effectiveElapsedNs(now: UInt64) -> Double {
        var pausedNs = totalPausedNs
        if paused, pauseStartNs > 0, now > pauseStartNs {
            pausedNs &+= (now - pauseStartNs)
        }
        guard now > anchorNs, now - anchorNs > pausedNs else { return 0 }
        return Double(now - anchorNs - pausedNs)
    }

    /// 当前 slot（可为负 = count-in 中）
    func currentSlot(now: UInt64? = nil) -> Double {
        lock.lock(); defer { lock.unlock() }
        guard running else { return 0 }
        let t = now ?? TradingHostClock.nowNanos()
        let elapsed = effectiveElapsedNs(now: t)
        return elapsed / Self.nsPerSlot(bpm: bpm) - Double(countInSlots)
    }

    /// 任意主机时间对应多少 slot（录音用它把"事件发生时刻"换算成 slot）
    func slot(atNs ns: UInt64) -> Double {
        lock.lock(); defer { lock.unlock() }
        guard running else { return 0 }
        let elapsed = effectiveElapsedNs(now: ns)
        return elapsed / Self.nsPerSlot(bpm: bpm) - Double(countInSlots)
    }

    /// slot → 主机时间（失败返回 anchorNs）。
    /// 含暂停时长，与 currentSlot / slot(atNs:) 互逆（M2-10 暂停修正）。
    func ns(atSlot slot: Double) -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        guard running else { return anchorNs }
        let e = (slot + Double(countInSlots)) * Self.nsPerSlot(bpm: bpm)
        var pausedNs = totalPausedNs
        if paused, pauseStartNs > 0 {
            let now = TradingHostClock.nowNanos()
            if now > pauseStartNs { pausedNs &+= (now - pauseStartNs) }
        }
        return anchorNs &+ pausedNs &+ UInt64(max(0, e))
    }

    // MARK: - 便捷换算

    /// 拍 → slot
    static func slots(forBeats beats: Double) -> Int {
        Int((beats * slotsPerBeat).rounded())
    }

    /// slot 落在第几小节（0 基）
    static func barIndex(atSlot slot: Double, slotsPerBar: Int) -> Int {
        guard slotsPerBar > 0 else { return 0 }
        return Int(floor(slot / Double(slotsPerBar)))
    }

    /// 当前是否处于 count-in
    var isCountingIn: Bool {
        currentSlot() < 0
    }

    /// 调试快照
    func snapshot() -> String {
        let s = currentSlot()
        return String(format: "slot=%.1f bpm=%.1f countIn=%d%@", s, bpm, countInSlots, paused ? " [暂停]" : "")
    }
}
