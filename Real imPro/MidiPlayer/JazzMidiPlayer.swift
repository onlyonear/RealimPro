import Foundation
import AVFAudio

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

    private let timeLock = NSLock()
    private var _isPaused: Bool = false
    private var pauseStartTime: UInt64 = 0
    private var _totalPausedTime: UInt64 = 0

    private var tempoAnchorEffectiveNs: UInt64 = 0
    private var tempoAnchorSlot: Double = 0.0
    private var _currentBPM: Double = 120.0

    var onNotePlay: ((String) -> Void)?
    
    init() {
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
                //print("🎵 开始加载 ChoriumRevA SoundFont 音色库...")
                try sampler.loadSoundBankInstrument(at: bankURL, program: 66, bankMSB: 121, bankLSB: 0)
                //print("✅ 旋律音色 (Tenor Sax) 加载成功！")
                
                try bassSampler.loadSoundBankInstrument(at: bankURL, program: 32, bankMSB: 121, bankLSB: 0)
                //print("✅ 贝斯音色加载成功！")
                
                try drumSampler.loadSoundBankInstrument(at: bankURL, program: 0, bankMSB: 120, bankLSB: 0)
                //print("✅ 鼓组音色加载成功！")
                
                try pianoSampler.loadSoundBankInstrument(at: bankURL, program: 0, bankMSB: 121, bankLSB: 0)
                //print("✅ 钢琴音色 (Grand Piano) 加载成功！")
            } catch {
                #if DEBUG
                print("❌ 音色加载致命失败: \(error.localizedDescription)")
                #endif
            }
        } else {
            #if DEBUG
            print("❌ 找不到 ChoriumRevA.sf2 文件！")
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
    // MARK: - 🌟 伴奏播放核心模块
    
    /// 伴奏模式的总开关（替代原本的 playSolo 被 View 调用）
    func playWithAccompaniment(solo: [GeneratedMeasure], bpm: Double = 130.0, style: String = "swing", startMeasure: Int = 0) {
        #if DEBUG
        print("🚀 playWithAccompaniment style=「\(style)」 BPM: \(bpm) startMeasure=\(startMeasure)")
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
        let backingTrack = AccompanimentGenerator.shared.generate(
            style: style, measureCount: remainingMeasures,
            chordSymbols: realChords, slotsPerMeasure: spm
        )
        
        playTask = Task {
            async let playBass:  () = playCompanionTrack(backingTrack.bassNotes,  trackName: "🎸 贝斯")
            async let playDrum:  () = playCompanionTrack(backingTrack.drumNotes,  trackName: "🥁 鼓组")
            async let playPiano: () = playCompanionTrack(backingTrack.pianoNotes, trackName: "🎹 钢琴")
            async let playMelody: () = playSoloTrackWithGraces(solo: solo, startMeasure: startMeasure)
            _ = await (playBass, playDrum, playPiano, playMelody)
        }
    }
    private func playCompanionTrack(_ notes: [CompanionNote], trackName: String) async {
        guard !notes.isEmpty else { return }
        struct MidiEvent { let absoluteSlot: Double; let pitch: UInt8; let volume: UInt8; let channel: UInt8 }
        
        var events: [MidiEvent] = []
        for note in notes {
            events.append(MidiEvent(absoluteSlot: Double(note.startSlot), pitch: note.midiPitch, volume: note.volume, channel: note.channel))
            events.append(MidiEvent(absoluteSlot: Double(note.startSlot + note.durationSlots), pitch: note.midiPitch, volume: 0, channel: note.channel))
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
                    if !note.isTieEnd { let j = Int.random(in: -3...3); sampler.startNote(midiNumber, withVelocity: UInt8(max(0, min(127, Int(velocity) + j))), onChannel: 0) }
                    
                    if note.isTieStart {
                        let endSlot = (physicalStartBeat + mathDuration) * 120.0
                        do { try await safeSleep(to: endSlot) } catch { return }
                    } else {
                        let sustainRatio = playDuration >= 0.5 ? 0.90 : 0.80
                        let sustainEndSlot = (physicalStartBeat + playDuration * sustainRatio) * 120.0
                        do { try await safeSleep(to: sustainEndSlot) } catch { return }
                        sampler.stopNote(midiNumber, onChannel: 0)
                        let releaseEndSlot = (physicalStartBeat + playDuration) * 120.0
                        do { try await safeSleep(to: releaseEndSlot) } catch { return }
                    }
                } else {
                    let endSlot = (physicalStartBeat + mathDuration) * 120.0
                    do { try await safeSleep(to: endSlot) } catch { return }
                }
                currentBeatPosition += mathDuration
            }
            cumulativeBeat += currentBeatPosition
        }
        if !Task.isCancelled { DispatchQueue.main.async { self.onNotePlay?("") } }
    }

    // MARK: - 倚音播放版solo（只添加，不修改 playSoloTrackAsync）
    private func playSoloTrackWithGraces(solo: [GeneratedMeasure], startMeasure: Int) async {
        let startIndex = max(0, min(startMeasure, solo.count - 1))
        guard startIndex < solo.count else { return }

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

                // ── 倚音播放（主干音前快速触发，时长守恒）──
                // tie 右端音符不触发倚音——延音中不应插入装饰音
                if !note.isTieEnd, !note.graceNotes.isEmpty {
                    let graces = note.graceNotes.filter { !$0.isRest }
                    for grace in graces {
                        let gp = convertPitchToMidi(pitch: grace.pitch)
                        sampler.startNote(gp, withVelocity: 50, onChannel: 0)
                        try? await Task.sleep(nanoseconds: 40_000_000)
                        sampler.stopNote(gp, onChannel: 0)
                        try? await Task.sleep(nanoseconds: 10_000_000)
                    }
                    // 从主干音 sustain 中扣除倚音耗时（~50ms/个 ≈ 0.05拍）
                    playDuration -= Double(graces.count) * 0.05
                    if playDuration < 0.02 { playDuration = 0.02 }
                }

                if !note.isRest {
                    let midiNumber = convertPitchToMidi(pitch: note.pitch)
                    if !note.isTieEnd { let j = Int.random(in: -3...3); sampler.startNote(midiNumber, withVelocity: UInt8(max(0, min(127, Int(velocity) + j))), onChannel: 0) }

                    if note.isTieStart {
                        let endSlot = (physicalStartBeat + mathDuration) * 120.0
                        do { try await safeSleep(to: endSlot) } catch { return }
                    } else {
                        let sustainRatio = playDuration >= 0.5 ? 0.90 : 0.80
                        let sustainEndSlot = (physicalStartBeat + playDuration * sustainRatio) * 120.0
                        do { try await safeSleep(to: sustainEndSlot) } catch { return }
                        sampler.stopNote(midiNumber, onChannel: 0)
                        let releaseEndSlot = (physicalStartBeat + playDuration) * 120.0
                        do { try await safeSleep(to: releaseEndSlot) } catch { return }
                    }
                } else {
                    let endSlot = (physicalStartBeat + mathDuration) * 120.0
                    do { try await safeSleep(to: endSlot) } catch { return }
                }
                currentBeatPosition += mathDuration
            }
            cumulativeBeat += currentBeatPosition
        }
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
        let backingTrack = AccompanimentGenerator.shared.generate(
            style: style, measureCount: remainingMeasures,
            chordSymbols: realChords, slotsPerMeasure: spm
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
