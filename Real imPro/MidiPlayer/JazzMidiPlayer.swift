import Foundation
import AVFAudio
import UIKit

// MARK: - 智能 Swing MIDI 播放管理器 (支持 16分、三连音与非线性律动)
class JazzMidiPlayer {
    static let shared = JazzMidiPlayer()
    
    private var engine = AVAudioEngine()
    private var sampler = AVAudioUnitSampler()      // 旋律轨 → Tenor Sax
    private var bassSampler = AVAudioUnitSampler()
    private var drumSampler = AVAudioUnitSampler()
    private var pianoSampler = AVAudioUnitSampler()  // 钢琴伴奏 → Grand Piano
    private var playTask: Task<Void, Never>?
    private var vibratoTimer: DispatchSourceTimer?

    // ── 音频会话（中断/路由变化）处理 ──
    /// 外部音频事件（来电中断/耳机拔出等）导致播放状态变化时的回调，供 UI 同步按钮状态
    var onExternalPlaybackChange: ((_ isPlaying: Bool, _ isPaused: Bool) -> Void)?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var wasPlayingBeforeInterruption = false

    private let timeLock = NSLock()
    private var _isPaused: Bool = false
    private var pauseStartTime: UInt64 = 0
    private var _totalPausedTime: UInt64 = 0

    private var tempoAnchorEffectiveNs: UInt64 = 0
    private var tempoAnchorSlot: Double = 0.0
    private var _currentBPM: Double = 120.0

    var onNotePlay: ((String) -> Void)?
    
    init() {
        configureAudioSession()   // 先配好音频会话类别与中断/路由监听，再启动引擎
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        // 1. 将所有乐器节点挂载到引擎
        engine.attach(sampler)
        engine.attach(bassSampler)
        engine.attach(drumSampler)
        engine.attach(pianoSampler)
        
        // 2. 将它们连接到主混音器
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        engine.connect(bassSampler, to: engine.mainMixerNode, format: nil)
        engine.connect(drumSampler, to: engine.mainMixerNode, format: nil)
        engine.connect(pianoSampler, to: engine.mainMixerNode, format: nil)
        
        // 4. 断开默认直连，插入混响——所有乐器共享同一空间
        engine.disconnectNodeOutput(engine.mainMixerNode)
        let reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(.mediumRoom)
        reverb.wetDryMix = 22
        engine.attach(reverb)
        engine.connect(engine.mainMixerNode, to: reverb, format: nil)
        engine.connect(reverb, to: engine.outputNode, format: nil)
        
        // 3. 分别为它们加载专属的乐器采样
        if let bankURL = Bundle.main.url(forResource: "ChoriumRevA", withExtension: "sf2") {
        //if let bankURL = Bundle.main.url(forResource: "NitroFont", withExtension: "sf2") {
            do {
                //dprint("🎵 开始加载 ChoriumRevA SoundFont 音色库...")
                try sampler.loadSoundBankInstrument(at: bankURL, program: 66, bankMSB: 121, bankLSB: 0)
                //dprint("✅ 旋律音色 (Tenor Sax) 加载成功！")
                
                try bassSampler.loadSoundBankInstrument(at: bankURL, program: 32, bankMSB: 121, bankLSB: 0)
                //dprint("✅ 贝斯音色加载成功！")
                
                try drumSampler.loadSoundBankInstrument(at: bankURL, program: 0, bankMSB: 120, bankLSB: 0)
                //dprint("✅ 鼓组音色加载成功！")
                
                try pianoSampler.loadSoundBankInstrument(at: bankURL, program: 0, bankMSB: 121, bankLSB: 0)
                //dprint("✅ 钢琴音色 (Grand Piano) 加载成功！")
            } catch {
                #if DEBUG
                dprint("❌ 音色加载致命失败: \(error.localizedDescription)")
                #endif
            }
        } else {
            #if DEBUG
            dprint("❌ 找不到 ChoriumRevA.sf2 文件！")
            #endif
        }
        
        try? engine.start()
    }
    
    // MARK: - 🎛️ 调音台音量/静音控制
    func updateTrackVolume(track: Int, volume: Float, isMuted: Bool) {
        let finalVolume = isMuted ? 0.0 : max(0, min(1, volume))
        let target: AVAudioUnitSampler
        switch track {
        case 0: target = sampler        // 萨克斯旋律
        case 1: target = pianoSampler   // 钢琴
        case 2: target = bassSampler    // 贝斯
        case 3: target = drumSampler    // 鼓
        default: return
        }
        target.volume = finalVolume
        target.masterGain = finalVolume
    }

    deinit {
        if let obs = interruptionObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = routeChangeObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = backgroundObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = foregroundObserver { NotificationCenter.default.removeObserver(obs) }
    }

    // MARK: - 音频会话（中断 / 路由变化）

    /// 配置 AVAudioSession 为音乐播放类别，并注册中断与路由变化监听。
    /// 不改变任何播放逻辑，只保证来电/闹钟/Siri/拔耳机等场景下不崩、不卡死、状态可恢复。
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .playback：音乐播放类别——支持中断、不被静音键静音；后台播放需 Info.plist 另配 audio 模式
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("⚠️ [AudioSession] 配置失败: \(error.localizedDescription)")
        }

        // 中断：来电、闹钟、Siri、其他 App 抢占音频
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }

        // 路由变化：耳机拔出/插入、蓝牙连接/断开
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }

        // App 进入后台（切主屏幕/切换其他 App）：真暂停，避免"停声但播放位置仍在后台推进、切回来跳音"
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleEnterBackground()
        }

        // App 回到前台：只保活引擎，绝不自动恢复播放（保持暂停，由用户手动点播放）
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleBecomeActive()
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            // 只在实际播放中才暂停；已暂停/已停止不动
            wasPlayingBeforeInterruption = (playTask != nil && !_isPaused)
            if wasPlayingBeforeInterruption {
                pause()
                onExternalPlaybackChange?(false, true)   // 与用户点暂停同语义
            }
        case .ended:
            // 中断结束：若引擎被系统停了，先重启保活（但不自动播放）
            if !engine.isRunning { try? engine.start() }
            // 按需求：中断结束后一律不自动续播。任务仍在→保持暂停态等用户手动点播放；任务已被用户停止→停止态
            let stillAlive = playTask != nil && !(playTask!.isCancelled)
            onExternalPlaybackChange?(false, stillAlive)
            wasPlayingBeforeInterruption = false
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        // 仅处理"旧设备不可用"（典型：耳机/蓝牙拔出），避免突然公放或无声
        guard reason == .oldDeviceUnavailable else { return }

        let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
        let hadHeadphones = previousRoute?.outputs.contains {
            $0.portType == .headphones || $0.portType == .headsetMic ||
            $0.portType == .bluetoothA2DP || $0.portType == .bluetoothHFP
        } ?? false

        // 之前在播放、且之前走耳机/蓝牙，拔出后暂停（iOS 音乐 App 标准行为）
        if hadHeadphones && playTask != nil && !_isPaused {
            pause()
            onExternalPlaybackChange?(false, true)
        }
    }

    /// App 进入后台（切主屏幕/切换其他 App）：若正在播放则真暂停，冻结播放位置。
    /// 不主动暂停的话，引擎虽被系统停声，但播放时钟仍在后台推进、音符被无声跳过，切回来会跳段。
    private func handleEnterBackground() {
        if playTask != nil && !_isPaused {
            pause()
            onExternalPlaybackChange?(false, true)
        }
    }

    /// App 回到前台：只确保音频引擎可用，绝不自动恢复播放（保持暂停，由用户手动点播放）。
    private func handleBecomeActive() {
        if !engine.isRunning { try? engine.start() }
    }


    /// 实时调整播放速度（播放过程中也可调用，下一个音符立即生效）
    func setTempo(_ bpm: Double) {
        let newBpm = max(40, min(300, bpm))
        timeLock.lock()
        if newBpm == _currentBPM { timeLock.unlock(); return }
        if tempoAnchorEffectiveNs != 0 {
            let now = DispatchTime.now().uptimeNanoseconds
            var paused = _totalPausedTime
            if _isPaused { paused += (now - pauseStartTime) }
            let effectiveNow = now > paused ? now - paused : 0
            if effectiveNow > tempoAnchorEffectiveNs {
                let elapsedNs = effectiveNow - tempoAnchorEffectiveNs
                let oldSlotNs = (60.0 / _currentBPM) / 120.0 * 1_000_000_000.0
                tempoAnchorSlot += Double(elapsedNs) / oldSlotNs
                tempoAnchorEffectiveNs = effectiveNow
            }
        }
        _currentBPM = newBpm
        timeLock.unlock()
    }
    func pause() {
        timeLock.lock()
        if !_isPaused { _isPaused = true; pauseStartTime = DispatchTime.now().uptimeNanoseconds }
        timeLock.unlock()
        for midi: UInt8 in 0...127 {
            sampler.stopNote(midi, onChannel: 0); pianoSampler.stopNote(midi, onChannel: 0)
            bassSampler.stopNote(midi, onChannel: 0); drumSampler.stopNote(midi, onChannel: 0)
        }
        stopVibrato()
    }
    func resume() {
        timeLock.lock()
        if _isPaused { _totalPausedTime += (DispatchTime.now().uptimeNanoseconds - pauseStartTime); _isPaused = false }
        timeLock.unlock()
        startVibrato()
    }
    func stop() {
        playTask?.cancel()
        playTask = nil
        stopVibrato()
        timeLock.lock()
        _isPaused = false; _totalPausedTime = 0; pauseStartTime = 0
        tempoAnchorEffectiveNs = 0; tempoAnchorSlot = 0.0
        timeLock.unlock()
        for midi: UInt8 in 0...127 {
            sampler.stopNote(midi, onChannel: 0); pianoSampler.stopNote(midi, onChannel: 0)
            bassSampler.stopNote(midi, onChannel: 0); drumSampler.stopNote(midi, onChannel: 0)
        }
    }

    // MARK: - 🎵 萨克斯颤音
    private func startVibrato() {
        vibratoTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .global())
        let sampleRate: Double = 32
        let frequency: Double = 5.0
        let depth: Double = 35
        var phase: Double = 0
        timer.schedule(deadline: .now(), repeating: 1.0 / (frequency * sampleRate))
        timer.setEventHandler { [weak self] in
            phase += 2.0 * .pi / sampleRate
            let value = UInt8((depth * (sin(phase) + 1.0) / 2.0).rounded())
            self?.sampler.sendController(1, withValue: value, onChannel: 0)
        }
        timer.resume()
        vibratoTimer = timer
    }

    private func stopVibrato() {
        vibratoTimer?.cancel()
        vibratoTimer = nil
        sampler.sendController(1, withValue: 0, onChannel: 0)
    }

    // MARK: - ⏱️ 微秒级时基轮询引擎
    private func safeSleep(to absoluteSlot: Double) async throws {
        while true {
            if Task.isCancelled { throw CancellationError() }
            timeLock.lock()
            let isP = _isPaused; let b = _currentBPM
            let aNs = tempoAnchorEffectiveNs; let aSlot = tempoAnchorSlot
            let now = DispatchTime.now().uptimeNanoseconds
            var paused = _totalPausedTime
            if _isPaused { paused += (now - pauseStartTime) }
            timeLock.unlock()
            if isP {
                try await Task.sleep(nanoseconds: 50_000_000)
                continue
            }
            let slotNs = (60.0 / b) / 120.0 * 1_000_000_000.0
            let remaining = max(0.0, absoluteSlot - aSlot)
            let targetEffectiveNs = aNs + UInt64(remaining * slotNs)
            let targetNs = targetEffectiveNs + paused
            if targetNs <= now { break }
            try await Task.sleep(nanoseconds: min(targetNs - now, 15_000_000))
        }
    }

    private func convertPitchToMidi(pitch: String) -> UInt8 {
        // 兼容 VexFlow 格式 (例如 "F/4", "Eb/5") 以及老格式 ("c")
        let clean = pitch.replacingOccurrences(of: " 前导", with: "").lowercased()
        let components = clean.split(separator: "/")
        
        let noteName = String(components.first ?? "c")
        // 如果没有标注八度，默认给 4 (中央C所在八度)
        let octave = components.count > 1 ? (Int(components[1]) ?? 4) : 4
        
        // 基础半音偏移 (以 C = 0 为基准)
        let baseNotes: [String: UInt8] = [
            "c": 0, "c#": 1, "db": 1, "d": 2, "d#": 3, "eb": 3,
            "e": 4, "f": 5, "f#": 6, "gb": 6, "g": 7, "g#": 8,
            "ab": 8, "a": 9, "a#": 10, "bb": 10, "b": 11
        ]
        
        let baseMidi = baseNotes[noteName] ?? 0
        // 标准 MIDI 算法：(八度 + 1) * 12 + 半音数 (例如 C/4 = 5 * 12 + 0 = 60)
        return UInt8((octave + 1) * 12) + baseMidi
    }
    // MARK: - 🎷 风格化 Swing（对齐原版 Impro-Visor .sty：旋律 swing 与伴奏 comp-swing 分离）
    /// swingRatio 含义：一拍内「第二个八分音符」的起点占一拍的比例。
    /// 0.5 = 直拍 even 8ths；0.67 = 标准爵士 2:1 摇摆；0.55 = 极轻微推移。
    private struct SwingProfile { let melody: Double; let comp: Double }

    /// 数值取自原版 styles/*.sty：
    /// swing=swing.sty、ballad=ballad.sty、shuffle=shuffle.sty、afro=african.sty、
    /// bossa=bossa.sty、waltz=爵士华尔兹 waltz.sty、latin=latin-new.sty；未知风格回退 swing。
    /// 把 solo（从 startIndex 起）展平成「和弦段」序列：一小节一个和弦=一段(整小节)，
    /// 一小节多个和弦=多段(各占其拍数)。伴奏时间线从 0 开始，故段起点用相对 j*globalSpm。
    private static func buildChordSegments(solo: [GeneratedMeasure], startIndex: Int, globalSpm: Int) -> [ChordSegment] {
        var segs: [ChordSegment] = []
        let count = solo.count - startIndex
        for j in 0..<count {
            let m = solo[startIndex + j]
            let barLen = m.slotsPerMeasure
            let barStart = j * globalSpm
            let cs = m.chordSlots
            if cs.isEmpty {
                segs.append(ChordSegment(chord: m.chord, startSlot: barStart, durationSlots: barLen))
            } else {
                for (k, item) in cs.enumerated() {
                    let segStart = barStart + item.startSlot
                    let segEnd = k + 1 < cs.count ? barStart + cs[k + 1].startSlot : barStart + barLen
                    segs.append(ChordSegment(chord: item.chord, startSlot: segStart, durationSlots: max(0, segEnd - segStart)))
                }
            }
        }
        return segs
    }

    private static func swingProfile(for style: String) -> SwingProfile {
        switch style.lowercased() {
        case "ballad":  return SwingProfile(melody: 0.55, comp: 0.60)
        case "shuffle": return SwingProfile(melody: 0.67, comp: 0.55)
        case "afro":    return SwingProfile(melody: 0.50, comp: 0.50)
        case "bossa":   return SwingProfile(melody: 0.55, comp: 0.50)
        case "waltz":   return SwingProfile(melody: 0.67, comp: 0.67)
        case "latin":   return SwingProfile(melody: 0.55, comp: 0.50)
        default:        return SwingProfile(melody: 0.67, comp: 0.67) // swing 及未知
        }
    }

    /// 伴奏时间轴的 swing 弯曲（120 slots = 1 拍）。
    /// 把平直网格 [0, 0.5, 1] 分段线性映射为 [0, S, 1]：拍头不动、反拍八分推后到 S、拍尾守恒。
    /// S=0.5 时为恒等映射（完全直拍）；函数单调递增，事件顺序不颠倒、每拍总时长守恒。
    private func swingWarpBeat(_ slot: Double, ratio S: Double) -> Double {
        let beats = slot / 120.0
        let beatIndex = floor(beats)
        var pos = beats - beatIndex
        if pos < 0 { pos = 0 }
        let warped: Double = pos <= 0.5 ? pos * (2.0 * S) : S + (pos - 0.5) * 2.0 * (1.0 - S)
        return (beatIndex + warped) * 120.0
    }

    // MARK: - 🌟 伴奏播放核心模块

    /// 伴奏模式的总开关（替代原本的 playSolo 被 View 调用）
    func playWithAccompaniment(solo: [GeneratedMeasure], bpm: Double = 130.0, style: String = "swing", startMeasure: Int = 0) {
        #if DEBUG
        dprint("🚀 playWithAccompaniment style=「\(style)」 BPM: \(bpm) startMeasure=\(startMeasure)")
        #endif
        stop()
        guard !solo.isEmpty else { return }
        startVibrato()
        
        timeLock.lock()
        _isPaused = false; _totalPausedTime = 0; pauseStartTime = 0
        tempoAnchorEffectiveNs = DispatchTime.now().uptimeNanoseconds
        tempoAnchorSlot = 0.0
        _currentBPM = max(40, min(300, bpm))
        timeLock.unlock()
        
        let startIndex = max(0, min(startMeasure, solo.count - 1))
        let remainingMeasures = solo.count - startIndex
        let realChords: [String] = solo[startIndex...].map { $0.chord }
        let spm = solo.first?.slotsPerMeasure ?? 480
        let chordSegments = Self.buildChordSegments(solo: solo, startIndex: startIndex, globalSpm: spm)
        let swing = Self.swingProfile(for: style)
        let backingTrack = AccompanimentGenerator.shared.generate(
            style: style, measureCount: remainingMeasures,
            chordSymbols: realChords, chordSegments: chordSegments, slotsPerMeasure: spm
        )
        
        playTask = Task {
            async let playBass:  () = playCompanionTrack(backingTrack.bassNotes,  trackName: "🎸 贝斯", compSwing: swing.comp)
            async let playDrum:  () = playCompanionTrack(backingTrack.drumNotes,  trackName: "🥁 鼓组", compSwing: swing.comp)
            async let playPiano: () = playCompanionTrack(backingTrack.pianoNotes, trackName: "🎹 钢琴", compSwing: swing.comp)
            async let playMelody: () = playSoloTrackWithGraces(solo: solo, startMeasure: startMeasure, melodySwing: swing.melody)
            _ = await (playBass, playDrum, playPiano, playMelody)
        }
    }
    private func playCompanionTrack(_ notes: [CompanionNote], trackName: String, compSwing: Double = 0.67) async {
        guard !notes.isEmpty else { return }
        struct MidiEvent { let absoluteSlot: Double; let pitch: UInt8; let volume: UInt8; let channel: UInt8 }
        
        var events: [MidiEvent] = []
        for note in notes {
            // 伴奏 comp-swing：note-on / note-off 同步弯曲，反拍音自然变短、正拍音自然变长
            let onSlot  = swingWarpBeat(Double(note.startSlot), ratio: compSwing)
            let offSlot = swingWarpBeat(Double(note.startSlot + note.durationSlots), ratio: compSwing)
            events.append(MidiEvent(absoluteSlot: onSlot,  pitch: note.midiPitch, volume: note.volume, channel: note.channel))
            events.append(MidiEvent(absoluteSlot: offSlot, pitch: note.midiPitch, volume: 0, channel: note.channel))
        }
        events.sort { $0.absoluteSlot == $1.absoluteSlot ? $0.volume < $1.volume : $0.absoluteSlot < $1.absoluteSlot }
        
        for event in events {
            let grooveOffset = trackName == "🥁 鼓组"
                ? Double.random(in: -0.5...0.5)
                : Double.random(in: -1.2...1.2)
            do { try await safeSleep(to: event.absoluteSlot + grooveOffset) } catch { return }
            let sampler: AVAudioUnitSampler = trackName == "🥁 鼓组" ? drumSampler
                                            : trackName == "🎸 贝斯" ? bassSampler : pianoSampler
            if event.volume > 0 {
                let jitter = trackName == "🎹 钢琴" ? Int.random(in: -3...3) : Int.random(in: -2...2)
                let vel = UInt8(max(0, min(127, Int(event.volume) + jitter)))
                sampler.startNote(event.pitch, withVelocity: vel, onChannel: event.channel)
            }
            else { sampler.stopNote(event.pitch, onChannel: event.channel) }
        }
    }
    private func playSoloTrackAsync(solo: [GeneratedMeasure], startMeasure: Int) async {
        let startIndex = max(0, min(startMeasure, solo.count - 1))
        guard startIndex < solo.count else { return }

        // 连音持音兜底：记录 isTieStart 起音、尚未被同音高终点收掉的 MIDI；遇异音/休止/曲末强制止音，防长鸣
        var heldTieNotes = Set<UInt8>()
        
        var cumulativeBeat = 0.0
        
        for mIndex in startIndex..<solo.count {
            let measure = solo[mIndex]
            var currentBeatPosition = 0.0
            
            for (vIndex, note) in measure.notes.enumerated() {
                if Task.isCancelled { return }
                
                var mathDuration = 0.0; var playDuration = 0.0; var isUpbeat = false; var velocity: UInt8 = 75
                
                let parts = note.duration.components(separatedBy: "_t")
                let rawDur = parts[0]
                let tupletVal = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
                let cleanDur = rawDur.replacingOccurrences(of: "r", with: "").replacingOccurrences(of: "d", with: "")
                let hasDot = rawDur.contains("d")
                
                switch cleanDur {
                case "w": mathDuration = 4.0; velocity = 80
                case "h": mathDuration = 2.0; velocity = 80
                case "q": mathDuration = 1.0; velocity = 80
                case "8": mathDuration = 0.5; velocity = 75
                case "16": mathDuration = 0.25; velocity = 72
                case "32": mathDuration = 0.125; velocity = 68
                default: mathDuration = 0.5
                }
                if hasDot { mathDuration *= 1.5 }
                if tupletVal == 3 { mathDuration *= (2.0 / 3.0); velocity = 75 }
                else if tupletVal == 5 { mathDuration *= (4.0 / 5.0); velocity = 75 }
                else if note.isTriplet { mathDuration *= (2.0 / 3.0); velocity = 75 }
                playDuration = mathDuration
                
                let isSwing = cleanDur == "8" && !hasDot && tupletVal == 0 && !note.isTriplet
                if isSwing {
                    let positionInBeat = currentBeatPosition.truncatingRemainder(dividingBy: 1.0)
                    if positionInBeat < 0.1 || positionInBeat > 0.9 { playDuration = 0.67; velocity = 75 }
                    else { playDuration = 0.33; isUpbeat = true; velocity = 82 }
                }
                
                let appliedOffset = (isSwing && isUpbeat) ? 0.17 : 0.0
                let physicalStartBeat = cumulativeBeat + currentBeatPosition + appliedOffset
                let startSlot = physicalStartBeat * 120.0
                
                let grooveOffset = Double.random(in: -1.2...1.2)
                do { try await safeSleep(to: startSlot + grooveOffset) } catch { return }
                
                DispatchQueue.main.async { self.onNotePlay?("note-\(mIndex)-\(vIndex)") }
                
                let isFirstInMeasure = currentBeatPosition.truncatingRemainder(dividingBy: 4.0) < 0.1
                if isFirstInMeasure { velocity = min(127, velocity + 2) }
                
                if !note.isRest {
                    let midiNumber = convertPitchToMidi(pitch: note.pitch)
                    // 坏连音线兜底：连音只能延续到紧邻的同音高事件；若遇到的是别的音，先收掉残留持音，避免长鸣
                    let staleHeld = heldTieNotes.filter { $0 != midiNumber }
                    for h in staleHeld { sampler.stopNote(h, onChannel: 0) }
                    heldTieNotes.subtract(staleHeld)
                    if !note.isTieEnd { let j = Int.random(in: -3...3); sampler.startNote(midiNumber, withVelocity: UInt8(max(0, min(127, Int(velocity) + j))), onChannel: 0) }
                    
                    if note.isTieStart {
                        heldTieNotes.insert(midiNumber)
                        let endSlot = (physicalStartBeat + mathDuration) * 120.0
                        do { try await safeSleep(to: endSlot) } catch { return }
                    } else {
                        heldTieNotes.remove(midiNumber)
                        let sustainRatio = playDuration >= 0.5 ? 0.90 : 0.80
                        let sustainEndSlot = (physicalStartBeat + playDuration * sustainRatio) * 120.0
                        do { try await safeSleep(to: sustainEndSlot) } catch { return }
                        sampler.stopNote(midiNumber, onChannel: 0)
                        let releaseEndSlot = (physicalStartBeat + playDuration) * 120.0
                        do { try await safeSleep(to: releaseEndSlot) } catch { return }
                    }
                } else {
                    // 休止符意味着未闭合的连音被打断：强制收掉残留持音
                    for h in heldTieNotes { sampler.stopNote(h, onChannel: 0) }
                    heldTieNotes.removeAll()
                    let endSlot = (physicalStartBeat + mathDuration) * 120.0
                    do { try await safeSleep(to: endSlot) } catch { return }
                }
                currentBeatPosition += mathDuration
            }
            cumulativeBeat += currentBeatPosition
        }
        // 曲末兜底：收掉所有未闭合的连音持音，防止自然结束后仍长鸣
        for h in heldTieNotes { sampler.stopNote(h, onChannel: 0) }
        heldTieNotes.removeAll()
        if !Task.isCancelled { DispatchQueue.main.async { self.onNotePlay?("") } }
    }

    // MARK: - 倚音播放版solo（只添加，不修改 playSoloTrackAsync）
    private func playSoloTrackWithGraces(solo: [GeneratedMeasure], startMeasure: Int, melodySwing: Double = 0.67) async {
        let startIndex = max(0, min(startMeasure, solo.count - 1))
        guard startIndex < solo.count else { return }

        // 连音持音兜底：记录 isTieStart 起音、尚未被同音高终点收掉的 MIDI；遇异音/休止/曲末强制止音，防长鸣
        var heldTieNotes = Set<UInt8>()

        var cumulativeBeat = 0.0

        for mIndex in startIndex..<solo.count {
            let measure = solo[mIndex]
            var currentBeatPosition = 0.0

            for (vIndex, note) in measure.notes.enumerated() {
                if Task.isCancelled { return }

                var mathDuration = 0.0; var playDuration = 0.0; var isUpbeat = false; var velocity: UInt8 = 75

                let parts = note.duration.components(separatedBy: "_t")
                let rawDur = parts[0]
                let tupletVal = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
                let cleanDur = rawDur.replacingOccurrences(of: "r", with: "").replacingOccurrences(of: "d", with: "")
                let hasDot = rawDur.contains("d")

                switch cleanDur {
                case "w": mathDuration = 4.0; velocity = 80
                case "h": mathDuration = 2.0; velocity = 80
                case "q": mathDuration = 1.0; velocity = 80
                case "8": mathDuration = 0.5; velocity = 75
                case "16": mathDuration = 0.25; velocity = 72
                case "32": mathDuration = 0.125; velocity = 68
                default: mathDuration = 0.5
                }
                if hasDot { mathDuration *= 1.5 }
                if tupletVal == 3 { mathDuration *= (2.0 / 3.0); velocity = 75 }
                else if tupletVal == 5 { mathDuration *= (4.0 / 5.0); velocity = 75 }
                else if note.isTriplet { mathDuration *= (2.0 / 3.0); velocity = 75 }
                playDuration = mathDuration

                let isSwing = cleanDur == "8" && !hasDot && tupletVal == 0 && !note.isTriplet
                if isSwing {
                    let positionInBeat = currentBeatPosition.truncatingRemainder(dividingBy: 1.0)
                    // 风格化：正拍八分占 melodySwing，反拍八分占 1-melodySwing（0.67 时等价旧的 0.67/0.33）
                    if positionInBeat < 0.1 || positionInBeat > 0.9 { playDuration = melodySwing; velocity = 75 }
                    else { playDuration = 1.0 - melodySwing; isUpbeat = true; velocity = 82 }
                }

                // 反拍八分起点从数学位置 0.5 推后到 melodySwing（0.67 时等价旧的 0.17）；0.5 直拍时为 0
                let appliedOffset = (isSwing && isUpbeat) ? (melodySwing - 0.5) : 0.0
                let physicalStartBeat = cumulativeBeat + currentBeatPosition + appliedOffset
                let startSlot = physicalStartBeat * 120.0

                let grooveOffset = Double.random(in: -1.2...1.2)
                do { try await safeSleep(to: startSlot + grooveOffset) } catch { return }

                DispatchQueue.main.async { self.onNotePlay?("note-\(mIndex)-\(vIndex)") }

                // 主干音真正进入的拍位置（有倚音则整体后移倚音窗口）；默认等于物理起点(含人味微移)
                var mainStartBeat = physicalStartBeat + grooveOffset / 120.0
                var graceWindowBeats = 0.0
                // ── 倚音播放（按拍比例、走音乐时钟 safeSleep；占多少就从主干扣多少，严格守恒不拖拍）──
                // tie 右端音符不触发倚音——延音中不应插入装饰音；本次不改力度，倚音力度维持 50
                if !note.isTieEnd, !note.graceNotes.isEmpty {
                    let graces = note.graceNotes.filter { !$0.isRest }
                    if !graces.isEmpty {
                        // 单个倚音占主干发声时长 18%，并以 0.12 拍(≈32分附点)为上限，避免慢板长主干上倚音拖沓
                        let graceEach = min(playDuration * 0.18, 0.12)
                        var gCursor = mainStartBeat
                        for grace in graces {
                            let gp = convertPitchToMidi(pitch: grace.pitch)
                            sampler.startNote(gp, withVelocity: 50, onChannel: 0)
                            do { try await safeSleep(to: (gCursor + graceEach * 0.8) * 120.0) } catch { return }
                            sampler.stopNote(gp, onChannel: 0)
                            gCursor += graceEach   // 余下 20% 作为倚音之间的小间隔
                            do { try await safeSleep(to: gCursor * 120.0) } catch { return }
                        }
                        graceWindowBeats = graceEach * Double(graces.count)
                        mainStartBeat += graceWindowBeats
                        // 严格守恒：从主干发声时长等额扣除倚音窗口
                        playDuration -= graceWindowBeats
                        if playDuration < 0.02 { playDuration = 0.02 }
                    }
                }

                if !note.isRest {
                    let midiNumber = convertPitchToMidi(pitch: note.pitch)
                    // 坏连音线兜底：连音只能延续到紧邻的同音高事件；若遇到的是别的音，先收掉残留持音，避免长鸣
                    let staleHeld = heldTieNotes.filter { $0 != midiNumber }
                    for h in staleHeld { sampler.stopNote(h, onChannel: 0) }
                    heldTieNotes.subtract(staleHeld)
                    if !note.isTieEnd { let j = Int.random(in: -3...3); sampler.startNote(midiNumber, withVelocity: UInt8(max(0, min(127, Int(velocity) + j))), onChannel: 0) }

                    if note.isTieStart {
                        heldTieNotes.insert(midiNumber)
                        // 守恒：主干起点后移了倚音窗口，时长等额缩短，结束点与无倚音时一致
                        let endSlot = (mainStartBeat + mathDuration - graceWindowBeats) * 120.0
                        do { try await safeSleep(to: endSlot) } catch { return }
                    } else {
                        heldTieNotes.remove(midiNumber)
                        // 短音(<半拍)发声比例 0.80→0.92：更连、起振更完整、快速经过音更易听清；长音维持 0.90
                        let sustainRatio = playDuration >= 0.5 ? 0.90 : 0.92
                        let sustainEndSlot = (mainStartBeat + playDuration * sustainRatio) * 120.0
                        do { try await safeSleep(to: sustainEndSlot) } catch { return }
                        sampler.stopNote(midiNumber, onChannel: 0)
                        let releaseEndSlot = (mainStartBeat + playDuration) * 120.0
                        do { try await safeSleep(to: releaseEndSlot) } catch { return }
                    }
                } else {
                    // 休止符意味着未闭合的连音被打断：强制收掉残留持音
                    for h in heldTieNotes { sampler.stopNote(h, onChannel: 0) }
                    heldTieNotes.removeAll()
                    let endSlot = (mainStartBeat + mathDuration) * 120.0
                    do { try await safeSleep(to: endSlot) } catch { return }
                }
                currentBeatPosition += mathDuration
            }
            cumulativeBeat += currentBeatPosition
        }
        // 曲末兜底：收掉所有未闭合的连音持音，防止自然结束后仍长鸣
        for h in heldTieNotes { sampler.stopNote(h, onChannel: 0) }
        heldTieNotes.removeAll()
        if !Task.isCancelled { DispatchQueue.main.async { self.onNotePlay?("") } }
    }

    // MARK: - 倚音版总控（只添加，不修改 playWithAccompaniment）
    func playWithAccompanimentAndGraces(solo: [GeneratedMeasure], bpm: Double = 130.0, style: String = "swing", startMeasure: Int = 0) {
        stop()
        guard !solo.isEmpty else { return }
        startVibrato()

        timeLock.lock()
        _isPaused = false; _totalPausedTime = 0; pauseStartTime = 0
        tempoAnchorEffectiveNs = DispatchTime.now().uptimeNanoseconds
        tempoAnchorSlot = 0.0
        _currentBPM = max(40, min(300, bpm))
        timeLock.unlock()

        let startIndex = max(0, min(startMeasure, solo.count - 1))
        let remainingMeasures = solo.count - startIndex
        let realChords: [String] = solo[startIndex...].map { $0.chord }
        let spm = solo.first?.slotsPerMeasure ?? 480
        let chordSegments = Self.buildChordSegments(solo: solo, startIndex: startIndex, globalSpm: spm)
        let backingTrack = AccompanimentGenerator.shared.generate(
            style: style, measureCount: remainingMeasures,
            chordSymbols: realChords, chordSegments: chordSegments, slotsPerMeasure: spm
        )

        playTask = Task {
            async let playBass:  () = playCompanionTrack(backingTrack.bassNotes,  trackName: "🎸 贝斯")
            async let playDrum:  () = playCompanionTrack(backingTrack.drumNotes,  trackName: "🥁 鼓组")
            async let playPiano: () = playCompanionTrack(backingTrack.pianoNotes, trackName: "🎹 钢琴")
            async let playMelody: () = playSoloTrackWithGraces(solo: solo, startMeasure: startMeasure)
            _ = await (playBass, playDrum, playPiano, playMelody)
        }
    }
}
