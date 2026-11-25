import Foundation
import CoreMIDI

// MARK: - Trading / Input / MIDI 直通生产装配
//
// 把核心 MIDIPassthroughEngine（无音频依赖、可独立测试）接到真实实现：
//   · 发声出口 JazzMonitorSounder → JazzMidiPlayer 的回听采样器；
//   · 输入源 TradingMIDIInput（CoreMIDI）声明满足 MIDIPassthroughInput；
//   · MIDIPassthrough.engine 为 App 常驻单例，首次访问即建立独立 client 并开始待命。

/// 生产发声适配器：包 JazzMidiPlayer 的回听采样器。
final class JazzMonitorSounder: MIDIMonitorSounding {
    func noteOn(pitch: UInt8, velocity: UInt8, channel: UInt8) {
        JazzMidiPlayer.shared.monitorNoteOn(pitch: pitch, velocity: velocity, channel: channel)
    }
    func noteOff(pitch: UInt8, channel: UInt8) {
        JazzMidiPlayer.shared.monitorNoteOff(pitch: pitch, channel: channel)
    }
    func allNotesOff() {
        JazzMidiPlayer.shared.monitorAllNotesOff()
    }
    func ensureReady() {
        JazzMidiPlayer.shared.enableMonitor()
    }
}

/// 声明 CoreMIDI 输入满足引擎所需协议（方法签名天然一致，无逻辑改动）。
extension TradingMIDIInput: MIDIPassthroughInput {}

/// 生产常驻入口。
enum MIDIPassthrough {

    /// 常驻引擎：首次访问即建立独立 CoreMIDI client 并开始待命（插入键盘即发声）。
    static let engine: MIDIPassthroughEngine = {
        let inp = TradingMIDIInput(clientName: "RealimPro Passthrough Input")
        let engine = MIDIPassthroughEngine(input: inp, sounder: JazzMonitorSounder())
        inp.start()
        // start() 时设备已在线不会触发 setup-changed，手动刷一次（含多端口去重与挂载）
        engine.refreshInitialDevices()
        return engine
    }()
}
