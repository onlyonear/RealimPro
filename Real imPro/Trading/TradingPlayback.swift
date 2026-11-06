import Foundation

// MARK: - Trading / Playback / 谱面回放（M2-6f）
//
// 用途：把"最终画到五线谱上的" `[GeneratedMeasure]` 按已知速度重新弹一遍，
//       让演奏者做"我吹的 / 谱上画的 / 现在听到的"三者对照。
//
// 实现：一条 2ms 的 DispatchSourceTimer 追赶事件表（不用 Task.sleep，避免累积漂移）；
//       声音走现有的回听采样器（Tenor Sax, program 66），不新建 AVAudioEngine。
//
// 注意：这是"回放对照"，不是演出级调度；2ms 轮询的抖动 ~±1 slot（4ms）对听觉无影响。

final class TradingPlayback {

    static let shared = TradingPlayback()

    #if DEBUG
    /// [M2-7 门禁探针 G2/G4] stop() 被调用次数（play 内部会先 stop，探针按时序区分；纯计数，Release 剥净）。
    static private(set) var debugStopCount = 0
    #endif

    private var timer: DispatchSourceTimer?
    private var events: [(ns: UInt64, pitch: UInt8, vel: UInt8, on: Bool)] = []
    private var cursor = 0
    private var t0: UInt64 = 0
    private var onDone: (() -> Void)?

    private init() {}

    // MARK: 演奏

    /// - Parameters:
    ///   - measures: 谱面数据（`PhraseToMeasures.convert` 的产物）
    ///   - bpm: 与录制时一致的速度
    ///   - leadMs: 预备时间（默认 600ms，避免第一拍被吞）
    func play(measures: [GeneratedMeasure], bpm: Double, leadMs: UInt64 = 600,
              completion: (() -> Void)? = nil) {
        let t0 = TradingHostClock.nowNanos() &+ leadMs &* 1_000_000
        startPlayback(measures, bpm: bpm, t0: t0, completion: completion)
    }

    /// [M2-7] 绝对锚点播放：t0 由会话时钟给出（电脑轮起点），让回应与伴奏对齐。
    func play(measures: [GeneratedMeasure], bpm: Double, absoluteAnchorNs: UInt64,
              completion: (() -> Void)? = nil) {
        startPlayback(measures, bpm: bpm, t0: absoluteAnchorNs, completion: completion)
    }

    private func startPlayback(_ measures: [GeneratedMeasure], bpm: Double,
                               t0: UInt64, completion: (() -> Void)?) {
        stop()

        let slotNs = TradingClock.nsPerSlot(bpm: bpm)
        var evs: [(UInt64, UInt8, UInt8, Bool)] = []

        // ① 先把整个谱面拉平成 (音高, 起, 止)，**跨小节连续计时**（之前每小节从 0 重算 → 全部挤在第一小节）
        // ② 同音 tie 链合并成一个长音，不在连音线处重新起音
        var abs = 0
        var chains: [(p: UInt8, start: Int, end: Int)] = []
        var openPitch: UInt8?
        var openStart = 0

        for m in measures {
            for n in m.notes {
                let d = Self.slots(of: n.duration)
                if n.isRest {
                    if let op = openPitch { chains.append((op, openStart, abs)); openPitch = nil }
                } else if let p = Self.midi(from: n.pitch) {
                    if let op = openPitch {
                        if op != p { chains.append((op, openStart, abs)) ; openPitch = p; openStart = abs }
                    } else {
                        openPitch = p; openStart = abs
                    }
                    if !n.isTieStart {
                        chains.append((p, openStart, abs + d))
                        openPitch = nil
                    }
                }
                abs += d
            }
        }
        if let op = openPitch { chains.append((op, openStart, abs)) }

        for c in chains where c.end > c.start {
            evs.append((UInt64(Double(c.start) * slotNs), c.p, 96, true))
            evs.append((UInt64(Double(c.end) * slotNs), c.p, 0, false))
        }
        let totalSlots = abs
        guard !evs.isEmpty else { return }
        evs.sort { $0.0 < $1.0 }

        events = evs.map { (ns: $0.0, pitch: $0.1, vel: $0.2, on: $0.3) }
        cursor = 0
        self.t0 = t0
        onDone = completion

        let q = DispatchQueue(label: "trading.playback")
        let t = DispatchSource.makeTimerSource(queue: q)
        t.schedule(deadline: .now() + .milliseconds(2), repeating: .milliseconds(2), leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()

        #if DEBUG
        print("[TRADING-PLAYBACK] 回放 \(evs.count) 个事件，\(totalSlots) slot（≈\(String(format: "%.1f", Double(totalSlots) * slotNs / 1e9)) 秒）")
        #endif
    }

    /// 停止回放并放开所有可能挂住的音
    func stop() {
        #if DEBUG
        Self.debugStopCount += 1
        #endif
        timer?.cancel()
        timer = nil
        if !events.isEmpty {
            for ch in 0..<16 {
                for p in 0...127 { JazzMidiPlayer.shared.monitorNoteOff(pitch: UInt8(p), channel: UInt8(ch)) }
            }
        }
        events.removeAll()
        cursor = 0
        onDone = nil
    }

    // MARK: 追赶

    private func tick() {
        let now = TradingHostClock.nowNanos()
        while cursor < events.count, t0 &+ events[cursor].ns <= now {
            let e = events[cursor]
            if e.on {
                JazzMidiPlayer.shared.monitorNoteOn(pitch: e.pitch, velocity: e.vel)
            } else {
                JazzMidiPlayer.shared.monitorNoteOff(pitch: e.pitch)
            }
            cursor += 1
        }
        if cursor >= events.count {
            let done = onDone
            stop()
            DispatchQueue.main.async { done?() }
        }
    }

    // MARK: 时值 / 音名

    /// 时值串 → slot（与 PhraseToMeasures 的编码一一对应；`_t3` 取 2/3）
    static func slots(of duration: String) -> Int {
        let t = duration
        var base = 120
        if t.contains("_t3") {
            if t.hasPrefix("w") { base = 480 }
            else if t.hasPrefix("hd") { base = 360 }
            else if t.hasPrefix("h") { base = 240 }
            else if t.hasPrefix("qd") { base = 180 }
            else if t.hasPrefix("q") { base = 120 }
            else if t.hasPrefix("8d") { base = 90 }
            else if t.hasPrefix("8") { base = 60 }
            else if t.hasPrefix("16d") { base = 45 }
            else if t.hasPrefix("16") { base = 30 }
            else if t.hasPrefix("32") { base = 15 }
            return max(1, base * 2 / 3)
        }
        if t.hasPrefix("wr") { return 480 }
        if t.hasPrefix("hd") { base = 360 }
        else if t.hasPrefix("h") { base = 240 }
        else if t.hasPrefix("qd") { base = 180 }
        else if t.hasPrefix("q") { base = 120 }
        else if t.hasPrefix("8d") { base = 90 }
        else if t.hasPrefix("8") { base = 60 }
        else if t.hasPrefix("16d") { base = 45 }
        else if t.hasPrefix("16") { base = 30 }
        else if t.hasPrefix("32") { base = 15 }
        else if t.hasPrefix("w") { base = 480 }
        return base
    }

    static func midi(from pitch: String) -> UInt8? {
        let parts = pitch.split(separator: "/")
        guard parts.count == 2, let oct = Int(parts[1]) else { return nil }
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let name = String(parts[0])
        let idx: Int
        if let k = names.firstIndex(of: name) {
            idx = k
        } else if let v = ["Db": 1, "Eb": 3, "Gb": 6, "Ab": 8, "Bb": 10][name] {
            idx = v
        } else {
            return nil
        }
        return UInt8(max(0, min(127, (oct + 1) * 12 + idx)))
    }
}
