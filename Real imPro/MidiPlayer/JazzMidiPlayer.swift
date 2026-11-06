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
    // [M2-5] 实时回听专用采样器（Trading 用户吹管的即时发声）。【懒挂载】默认 nil，
    // 仅 enableMonitor() 首次启用时才 attach/connect/loadSoundBank；普通播放不创建它、音频图不变。
    private var monitorSampler: AVAudioUnitSampler?
    // [M2-5] 回听音色是否真正就绪（sf2 加载成功才 true）。避免"节点挂着但没声"时探针误判绿。
    private var monitorReady = false
    private var playTask: Task<Void, Never>?
    private var segmentTask: Task<Void, Never>?   // [M2-8e] Trading 电脑轮单段旋律（不碰伴奏）
    private var vibratoTimer: DispatchSourceTimer?

    // [P3-c] 伴奏混音：UI 推子缓存 + 每轨"内容增益"（来源归一 × Java 席位）。
    // 节点最终音量 = 推子 × 内容增益；masterGain 固定 0dB，音量只走线性 .volume。
    // 轨道编号：0=sax 独奏 / 1=piano / 2=bass / 3=drum；推子默认 0.8 与 ContentView @State 一致。
    private var faderVolume: [Float] = [0.8, 0.8, 0.8, 0.8]
    private var faderMuted: [Bool] = [false, false, false, false]
    private var contentGain: [Float] = [1.0, 1.0, 1.0, 1.0]

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
    // [旧码封存 P3-c 20261011] 旧实现把线性音量误赋给 dB 单位的 masterGain（0.8 被当 +0.8dB≈110%）：
    //   func updateTrackVolume(track: Int, volume: Float, isMuted: Bool) {
    //       let finalVolume = isMuted ? 0.0 : max(0, min(1, volume))
    //       let target: AVAudioUnitSampler
    //       switch track { case 0: target = sampler; case 1: target = pianoSampler
    //                     case 2: target = bassSampler; case 3: target = drumSampler; default: return }
    //       target.volume = finalVolume
    //       target.masterGain = finalVolume   // ← dB 单位误用
    //   }
    func updateTrackVolume(track: Int, volume: Float, isMuted: Bool) {
        guard (0...3).contains(track) else { return }
        faderVolume[track] = max(0, min(1, volume))
        faderMuted[track] = isMuted
        applyTrackGain(track)
    }

    /// 重算单轨节点音量：静音=0；否则 = 推子 × 内容增益（线性振幅，钳 0...1）。masterGain 恒 0dB。
    private func applyTrackGain(_ track: Int) {
        let target: AVAudioUnitSampler
        switch track {
        case 0: target = sampler        // 萨克斯旋律
        case 1: target = pianoSampler   // 钢琴
        case 2: target = bassSampler    // 贝斯
        default: target = drumSampler   // 鼓
        }
        let v = faderMuted[track] ? 0.0 : max(0, min(1, faderVolume[track] * contentGain[track]))
        target.volume = v
        target.masterGain = 0.0   // dB 单位，0 = 单位增益；音量只走线性 .volume（修复旧码 dB 误用）
    }

    /// 四轨全部重算（开始播放/切换风格后调用）。
    private func applyAllTrackGains() {
        for t in 0...3 { applyTrackGain(t) }
    }

    /// [P3-c] 按风格来源设定伴奏内容增益并立即落到四个节点。
    /// 独奏(0)恒满席；手写风格伴奏 = trim（节点满增益，其 pattern 力度已烘焙主次，不套 Java 席位）；
    /// .sty 伴奏 = Java 席位 × 每小节能量自动归一系数（拉到手写基准；鼓另给编制补偿）。
    /// UI 推子与静音在 applyTrackGain 内相乘，View 无需改动。
    private func configureAccompanimentMix(style: String, track backing: BackingTrackData, measureCount: Int) {
        let measures = max(1, measureCount)
        let isSty = StyleEngine.shared.isStyStyle(style)

        // 每小节平均能量 Σvel²（velocity 双保险钳 1...127，非法值不进能量）
        func perMeasureEnergy(_ notes: [CompanionNote]) -> Double {
            let e = notes.reduce(0.0) { acc, n in
                let v = Double(max(1, min(127, Int(n.volume))))
                return acc + v * v
            }
            return e / Double(measures)
        }
        // 节点振幅归一系数 g = √(手写参考每小节能量 ÷ .sty 每小节能量)；鼓参考能量乘编制补偿²。
        // 钳 ≤1.0：只压低、不放大，避免稀疏织体被抬出噪声底。
        func norm(_ refTotal: Double, _ styPerMeasure: Double, boost: Float = 1.0) -> Float {
            let refPerM = refTotal / AccompanimentMix.refMeasures * Double(boost * boost)
            return Float(max(0, min(1.0, sqrt(refPerM / max(1, styPerMeasure)))))
        }

        // [P3-e] 手写专用归一：公式同 norm，但上限为 handGainCap（允许放大稀疏织体），下限 0。
        func normHand(_ refTotal: Double, _ styPerMeasure: Double, boost: Float = 1.0) -> Float {
            let refPerM = refTotal / AccompanimentMix.refMeasures * Double(boost * boost)
            return Float(max(0, min(Double(AccompanimentMix.handGainCap), sqrt(refPerM / max(1, styPerMeasure)))))
        }

        // [P3-e] 独奏(0)恒满席；伴奏三轨无论来源都按 Java 席位 × 每小节能量归一，使手写与 .sty 等响。
        var gain: [Float] = [
            AccompanimentMix.seatMelody * AccompanimentMix.trimMelody,   // 0 独奏恒满席
            1, 1, 1                                                       // 1/2/3 占位，下方按来源计算
        ]
        if isSty {
            // Java .sty：织体丰满，归一系数只压不放（g≤1），鼓另给编制补偿（P3-c 定稿，真机已验收，逐运算不变）。
            let gP = norm(AccompanimentMix.refPianoEnergy, perMeasureEnergy(backing.pianoNotes))
            let gB = norm(AccompanimentMix.refBassEnergy,  perMeasureEnergy(backing.bassNotes))
            let gD = norm(AccompanimentMix.refDrumEnergy,  perMeasureEnergy(backing.drumNotes),
                          boost: AccompanimentMix.drumEnsembleBoost)
            gain[1] = AccompanimentMix.seatPiano * gP * AccompanimentMix.trimPiano
            gain[2] = AccompanimentMix.seatBass  * gB * AccompanimentMix.trimBass
            gain[3] = AccompanimentMix.seatDrum  * gD * AccompanimentMix.trimDrum
        } else {
            // [P3-e] 手写：同席位/参考/鼓补偿逐轨归一；与 .sty 唯一差异是允许放大到 handGainCap，补偿稀疏老 pattern，
            //        使 Simple Shuffle / Simple Afro / Simple Bossa 三轨最终能量与所有 .sty 锁定到同一目标（等响）。
            let gP = normHand(AccompanimentMix.refPianoEnergy, perMeasureEnergy(backing.pianoNotes))
            let gB = normHand(AccompanimentMix.refBassEnergy,  perMeasureEnergy(backing.bassNotes))
            let gD = normHand(AccompanimentMix.refDrumEnergy,  perMeasureEnergy(backing.drumNotes),
                              boost: AccompanimentMix.drumEnsembleBoost)
            // [P3-c.2] 手写节点音量在归一基础上再乘专属响度补偿（AccompanimentMix.hand*Boost），末端钳 0...1 防削波。
            gain[1] = max(0, min(1, AccompanimentMix.seatPiano * gP * AccompanimentMix.trimPiano * AccompanimentMix.handPianoBoost))
            gain[2] = max(0, min(1, AccompanimentMix.seatBass  * gB * AccompanimentMix.trimBass  * AccompanimentMix.handBassBoost))
            gain[3] = max(0, min(1, AccompanimentMix.seatDrum  * gD * AccompanimentMix.trimDrum  * AccompanimentMix.handDrumBoost))
            // [旧码封存 P3-c.2 20261011] P3-e 手写节点音量无专属响度补偿（数学等响但稀疏织体听感偏弱）：
            // gain[1] = AccompanimentMix.seatPiano * gP * AccompanimentMix.trimPiano
            // gain[2] = AccompanimentMix.seatBass  * gB * AccompanimentMix.trimBass
            // gain[3] = AccompanimentMix.seatDrum  * gD * AccompanimentMix.trimDrum
        }
        // [旧码封存 P3-e 20261011] P3-c.1 手写曾用固定 trim=1.0（绕过调音台，致手写比 .sty 响约 3~10dB）：
        //   var gain = [ seatMelody*trimMelody, trimPiano, trimBass, trimDrum ]，且仅 if isSty 才归一、无 else 分支。
        // [旧码封存 P3-c.1 20261011] 更早手写误套固定 Java 席位（无逐曲归一/无鼓补偿，稀疏轨几乎听不到）：
        //   AccompanimentMix.seatPiano * AccompanimentMix.trimPiano,    // 0.315（钢琴 -10.8dB）
        //   AccompanimentMix.seatBass  * AccompanimentMix.trimBass,     // 0.472（贝 -7.3dB）
        //   AccompanimentMix.seatDrum  * AccompanimentMix.trimDrum      // 0.472（鼓 -7.3dB）
        contentGain = gain
        applyAllTrackGains()
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
        segmentTask?.cancel()
        segmentTask = nil
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
    // [P3-e] 默认 style 由已下架的手写 "swing" 改为 Java "sty:swing"（当前三处调用都显式传 rawValue，本默认值不可达；
    //        改之仅为闭环，避免日后有调用省略 style 时误入已下架的手写 basicSwing）。旧默认值封存：style: String = "swing"
    func playWithAccompaniment(solo: [GeneratedMeasure], bpm: Double = 130.0, style: String = "sty:swing", startMeasure: Int = 0,
                               externalAnchorNs: UInt64? = nil) {
        #if DEBUG
        dprint("🚀 playWithAccompaniment style=「\(style)」 BPM: \(bpm) startMeasure=\(startMeasure)")
        #endif
        stop()
        guard !solo.isEmpty else { return }
        startVibrato()
        
        timeLock.lock()
        _isPaused = false; _totalPausedTime = 0; pauseStartTime = 0
        // [M2-3] 外部锚点非 nil（Trading 会话传入）时，播放时钟与 TradingClock 共享同一主机时刻；
        //       nil（所有现有调用）时与改前逐字等价。两时钟同源已由 spike 实测（evidence_M2-3/spike_clock_domain.swift）。
        tempoAnchorEffectiveNs = externalAnchorNs ?? DispatchTime.now().uptimeNanoseconds
        tempoAnchorSlot = 0.0
        _currentBPM = max(40, min(300, bpm))
        timeLock.unlock()
        
        let startIndex = max(0, min(startMeasure, solo.count - 1))
        let remainingMeasures = solo.count - startIndex
        let realChords: [String] = solo[startIndex...].map { $0.chord }
        let spm = solo.first?.slotsPerMeasure ?? 480
        let chordSegments = Self.buildChordSegments(solo: solo, startIndex: startIndex, globalSpm: spm)
        // [P3-a] 先取按风格名猜测的默认 swing；generate 后若为 .sty（BackingTrackData 带文件头值）则覆盖，nil 回退默认。
        let baseProfile = Self.swingProfile(for: style)
        let backingTrack = AccompanimentGenerator.shared.generate(
            style: style, measureCount: remainingMeasures,
            chordSymbols: realChords, chordSegments: chordSegments, slotsPerMeasure: spm
        )
        let swing = SwingProfile(melody: backingTrack.melodySwing ?? baseProfile.melody,
                                 comp: backingTrack.compSwing ?? baseProfile.comp)

        // [P3-c] 按风格来源（手写 / .sty）设定伴奏三轨内容增益并立即落到节点
        // （修 masterGain dB 误用 + .sty 与手写响度拉平 + Java 主次摆位）。
        configureAccompanimentMix(style: style, track: backingTrack, measureCount: remainingMeasures)
        
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
    private func playSoloTrackWithGraces(solo: [GeneratedMeasure], startMeasure: Int, melodySwing: Double = 0.67,
                                         globalMeasureOffset: Int = 0) async {
        let startIndex = max(0, min(startMeasure, solo.count - 1))
        guard startIndex < solo.count else { return }

        // 连音持音兜底：记录 isTieStart 起音、尚未被同音高终点收掉的 MIDI；遇异音/休止/曲末强制止音，防长鸣
        var heldTieNotes = Set<UInt8>()

        // [M2-8e] 全局小节偏移：Trading 电脑轮传 N（这段在整首的物理起始小节），
        // 时钟从全局 slot N*480 起、高亮用全局小节号；现有调用传默认 0，行为逐字不变。
        var cumulativeBeat = Double(globalMeasureOffset) * 4.0
        // [M2-8e] 是否真的调度过时间点（含休止等待）。Trading 伴奏启动传 notes 空骨架，
        // 旋律 Task 瞬间遍历完，不应发结尾 ""（否则误触发"播放结束"）。
        var didSchedule = false

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
                didSchedule = true

                let globalMIndex = globalMeasureOffset + mIndex
                DispatchQueue.main.async { self.onNotePlay?("note-\(globalMIndex)-\(vIndex)") }

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

                // [M2-8e] 取消检查点：堵"safeSleep 已返回、主干 startNote 尚未执行"的微秒级挂音窗口
                if Task.isCancelled { return }

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
        // [M2-8e] 只有真的调度过音才发结束 ""；空骨架（Trading 伴奏启动）不发，避免误触发结束。
        if didSchedule && !Task.isCancelled { DispatchQueue.main.async { self.onNotePlay?("") } }
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

    // MARK: - [M2-8e] Trading 电脑轮：只放一段旋律（swing/高亮/滚动），不碰伴奏

    /// 电脑轮回应播放：measures=本轮 4 小节（局部坐标），globalStartMeasure=这 4 小节在整首的物理起始小节。
    /// 时钟锚点复用伴奏启动时的 tempoAnchor（=musicAnchor），safeSleep 用全局 slot 精确对齐电脑轮起点；
    /// 复用与其他链路完全相同的 swing/力度/延音/人味逻辑，回调同一个 onNotePlay → 高亮/自动滚动一致。
    /// 不调用 stop()、不重新生成伴奏，因此不会打断正在放的伴奏三轨。
    func playTradingSegment(measures: [GeneratedMeasure], globalStartMeasure: Int,
                            melodySwing: Double = 0.67) {
        segmentTask?.cancel()
        segmentTask = Task {
            await playSoloTrackWithGraces(solo: measures, startMeasure: 0,
                                          melodySwing: melodySwing,
                                          globalMeasureOffset: globalStartMeasure)
        }
    }

    // MARK: - 🎧 M2-5 实时回听（Trading 人声；独立采样器，懒挂到现有引擎）
    //
    // 设计决策（见 M2-3_5 逐 hunk 设计文档）：
    // 1) 不新建 AVAudioEngine：挂到现有 engine 的 mainMixer，共享已配置的 .playback 会话、
    //    后台音频、中断/路由处理与同一 reverb；
    // 2) 不复用旋律轨 sampler：避免 AI 旋律跨小节延音/tie 与回听互相 stopNote 串音；
    // 3) 懒挂载：未启用前节点不存在，普通播放音频图与改前逐节点一致；engine 运行时
    //    attach/connect/loadSoundBank 已由 spike 实测不打断现有播放（evidence_M2-3/spike_dynamic_attach.swift）。
    // 回听走 USB MIDI→采样器发声，不触碰麦克风，故音频会话保持 .playback 不变。
    //
    // 【线程】attach/connect 属音频图结构变更，必须在主线程。
    // 约定：enableMonitor 期望直接在主线程调用（DEBUG 探针、M2-6 会话建立都在主线程）。
    // 下方 main.sync 只是兜底，仅在"非主线程调用"时转主线程；切勿在主线程阻塞等待一个
    // 又会反过来 sync 主线程的后台任务（经典 main.sync 死锁），正常主线程调用不会触发。
    func enableMonitor(program: UInt8 = 66, bankMSB: UInt8 = 121, bankLSB: UInt8 = 0) {
        if !Thread.isMainThread {
            DispatchQueue.main.sync {
                self.enableMonitor(program: program, bankMSB: bankMSB, bankLSB: bankLSB)
            }
            return
        }
        if monitorSampler != nil { return }
        let m = AVAudioUnitSampler()
        engine.attach(m)
        engine.connect(m, to: engine.mainMixerNode, format: nil)
        // 音色加载失败：detach 刚挂的节点（detach 会自动移除其连接），不保留"无音色节点"，
        // monitorSampler 保持 nil ⇒ isMonitorEnabled/isMonitorReady 均为 false，探针会判红而不是误绿。
        guard let bankURL = Bundle.main.url(forResource: "ChoriumRevA", withExtension: "sf2") else {
            engine.detach(m)
            #if DEBUG
            dprint("⚠️ 回听：未找到 ChoriumRevA.sf2")
            #endif
            return
        }
        do {
            try m.loadSoundBankInstrument(at: bankURL, program: program,
                                          bankMSB: bankMSB, bankLSB: bankLSB)
        } catch {
            engine.detach(m)
            #if DEBUG
            dprint("⚠️ 回听音色加载失败: \(error.localizedDescription)")
            #endif
            return
        }
        m.volume = 0.9
        monitorSampler = m
        monitorReady = true
    }

    /// 回听 note on/off。由 TradingMonitor 在 CoreMIDI 回调线程直接调用；
    /// AVAudioUnitSampler.startNote/stopNote 为线程安全接口，可在任意线程调用（无需切主线程，延迟最低）。
    func monitorNoteOn(pitch: UInt8, velocity: UInt8, channel: UInt8 = 0) {
        monitorSampler?.startNote(pitch, withVelocity: max(1, min(127, velocity)), onChannel: channel)
    }

    func monitorNoteOff(pitch: UInt8, channel: UInt8 = 0) {
        monitorSampler?.stopNote(pitch, onChannel: channel)
    }

    /// 会话停止时收掉所有回听延音（遍历 16 通道——note-on 用事件自带通道，
    /// 键盘若不在 ch0 发声，只停 ch0 会留下挂音）。不卸载节点：未触发 startNote 的
    /// instrument sampler 输出数字静音，不改变其它轨混音；运行时 detach 需断图，风险大于收益。
    func monitorAllNotesOff() {
        guard let m = monitorSampler else { return }
        for ch: UInt8 in 0..<16 {
            for note: UInt8 in 0...127 { m.stopNote(note, onChannel: ch) }
        }
    }

    /// 回听节点是否已挂载（DEBUG 探针 / 会话状态用）。
    var isMonitorEnabled: Bool { monitorSampler != nil }

    /// 回听音色是否真正就绪（探针必须同时断言此项，防止"挂着没声"判绿）。
    var isMonitorReady: Bool { monitorReady }

    // MARK: - 🥁 M2-6 数拍点击（独立的打击乐采样器，懒挂载）
    //
    // 为什么单独挂一个：现有 drumSampler 是伴奏鼓组的，共用会在 stop() 时被清掉、
    // 也会和伴奏抢同一通道。数拍是"舞台上的鼓棒"，必须独立、稳定。
    // 音色取 GM 打击乐组（bankMSB 120，与 drumSampler 同库），边击(37)/闭合踩镲(42)。
    private var clickSampler: AVAudioUnitSampler?
    private var clickReady = false

    /// 启用数拍点击（首次调用懒挂载；音频图变更，必须主线程）
    func enableClick() {
        if !Thread.isMainThread {
            DispatchQueue.main.sync { self.enableClick() }
            return
        }
        if clickSampler != nil { return }
        let m = AVAudioUnitSampler()
        engine.attach(m)
        engine.connect(m, to: engine.mainMixerNode, format: nil)
        guard let bankURL = Bundle.main.url(forResource: "ChoriumRevA", withExtension: "sf2") else {
            engine.detach(m)
            #if DEBUG
            dprint("⚠️ 数拍：未找到 ChoriumRevA.sf2")
            #endif
            return
        }
        do {
            try m.loadSoundBankInstrument(at: bankURL, program: 0, bankMSB: 120, bankLSB: 0)
        } catch {
            engine.detach(m)
            #if DEBUG
            dprint("⚠️ 数拍音色加载失败: \(error.localizedDescription)")
            #endif
            return
        }
        m.volume = 0.85
        clickSampler = m
        clickReady = true
    }

    /// 敲一下。accent = 小节第一拍（边击，更亮更响）；其余用闭合踩镲。
    /// 线程安全：可从任意线程调用（数拍定时器在专用队列上）。
    func click(accent: Bool = false) {
        guard let m = clickSampler else { return }
        let note: UInt8 = accent ? 37 : 42
        let vel: UInt8 = accent ? 115 : 78
        m.startNote(note, withVelocity: vel, onChannel: 9)
        // 40ms 后松键：踩镲样本本身很短，松键只是让采样器别一直挂着这个音
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.05) {
            m.stopNote(note, onChannel: 9)
        }
    }

    /// 数拍采样器是否就绪（探针用）
    var isClickReady: Bool { clickReady }

    #if DEBUG
    /// [M2-3] 仅探针用：读回实际生效的播放锚点，用于**精确**验证与 TradingClock 共享同一 T0（零测量噪声）。
    var debugAnchorNs: UInt64 { tempoAnchorEffectiveNs }
    #endif
}
