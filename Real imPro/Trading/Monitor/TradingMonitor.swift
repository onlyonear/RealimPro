import Foundation

// MARK: - Trading / Monitor / 实时回听（M2-5）
//
// 纯新增文件：不修改 MidiPlayer 的播放逻辑、录音逻辑，也不抢占 MIDI 输入分发。
//
// 职责边界（只有"发声"）：
//   · 把 TradingMIDIInput 收到的音符事件原样转发给 JazzMidiPlayer 的回听采样器；
//   · 不参与记谱时间戳——记谱仍由 TradingRecorder 走 TradingMIDIEvent.hostTimeNs(hostTime)，
//     回听只是"让用户听见自己刚吹的音"。
//
// 为什么不在这里直接占用 input.onEvent：
//   TradingMIDIInput.onEvent 是单一闭包，录音器（TradingRecorder）也要挂它，直接赋值会互相覆盖。
//   做多播订阅要改已冻结的 M1 输入类。故本类只暴露 start/feed/stop，由 M2-6 会话层在
//   同一个 onEvent 闭包里做 fan-out：
//       input.onEvent = { ev in
//           recorder.handle(ev, clock: clock)   // 记谱（hostTime 时间戳）
//           monitor.feed(ev)                    // 回听（本类，仅发声）
//       }
//   M2-3 阶段没有会话状态机，本类唯一调用方是 DEBUG 探针（人工/注入器喂事件）。
final class TradingMonitor {

    /// 音色默认 Tenor Sax（与旋律轨一致：program 66 / bankMSB 121 / bankLSB 0）。
    private let program: UInt8
    private(set) var isRunning = false
    #if DEBUG
    /// [M2-7 门禁探针 G3] 真正转发到回听采样器的 note-on 次数（纯计数，Release 剥净）。
    private(set) var debugFeedNoteOnCount = 0
    #endif

    init(program: UInt8 = 66) {
        self.program = program
    }

    /// 启用回听：首次会懒挂载回听采样器（音频图变更由 JazzMidiPlayer.enableMonitor 保证在主线程）。
    func start() {
        guard !isRunning else { return }
        isRunning = true
        JazzMidiPlayer.shared.enableMonitor(program: program)
    }

    /// 转发一个实时 MIDI 事件用于发声（CoreMIDI 回调线程调用，转发即返回，不做计算）。
    func feed(_ event: TradingMIDIEvent) {
        guard isRunning else { return }
        let p = UInt8(max(0, min(127, event.pitch)))
        let ch = UInt8(event.channel & 0x0F)
        if event.isNoteOn {
            #if DEBUG
            debugFeedNoteOnCount += 1
            #endif
            let v = UInt8(max(1, min(127, event.velocity)))
            JazzMidiPlayer.shared.monitorNoteOn(pitch: p, velocity: v, channel: ch)
        } else {
            JazzMidiPlayer.shared.monitorNoteOff(pitch: p, channel: ch)
        }
    }

    /// 停止回听：收掉所有通道延音（不卸载音频节点）。
    func stop() {
        guard isRunning else { return }
        isRunning = false
        JazzMidiPlayer.shared.monitorAllNotesOff()
    }

    /// [fix158] 轮次切换兜底：收掉所有回听延音（不卸载音频节点、不改变 isRunning）。
    /// 与 stop() 的区别：stop() 会把 isRunning 置 false；本方法仅静音，会话继续、回听仍可用。
    func allNotesOff() {
        guard isRunning else { return }
        JazzMidiPlayer.shared.monitorAllNotesOff()
    }
}
