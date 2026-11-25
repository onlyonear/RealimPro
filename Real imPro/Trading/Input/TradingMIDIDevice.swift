import Foundation
import CoreMIDI

// MARK: - Trading / Input / 设备模型
//
// M1 · 纯新增 · 只描述设备，不含任何连接逻辑

/// 一个可用的 MIDI 输入源。
///
/// 与 Java `javax.sound.midi.MidiDevice.Info` 对应的最小子集
/// （Java: src/imp/midi/MidiManager.java:264-298 getMidiInInfo/getInDeviceInfo）。
struct TradingMIDIDevice: Identifiable, Hashable {

    /// CoreMIDI 唯一 ID（`kMIDIPropertyUniqueID`）。同名设备用它可以区分。
    let uniqueID: Int32

    /// 显示名（`kMIDIPropertyDisplayName`）
    let name: String

    /// 是否离线（拔掉了 / 驱动掉了）
    let isOffline: Bool

    /// 端点引用（用于 `MIDIPortConnectSource`；不参与 Hashable）
    let endpoint: MIDIEndpointRef

    var id: Int32 { uniqueID }

    var isOnline: Bool { !isOffline }

    // MARK: Hashable（endpoint 不参与，避免端点复用造成误判）

    static func == (lhs: TradingMIDIDevice, rhs: TradingMIDIDevice) -> Bool {
        lhs.uniqueID == rhs.uniqueID && lhs.name == rhs.name && lhs.isOffline == rhs.isOffline
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(uniqueID)
        hasher.combine(name)
        hasher.combine(isOffline)
    }
}

extension TradingMIDIDevice {

    /// 尽力从端点读取显示名；读不到则给一个可读的兜底名。
    static func displayName(of endpoint: MIDIEndpointRef) -> String {
        if let s = stringProperty(endpoint, kMIDIPropertyDisplayName), !s.isEmpty {
            return s
        }
        if let s = stringProperty(endpoint, kMIDIPropertyName), !s.isEmpty {
            return s
        }
        return "MIDI 输入 #\(endpoint)"
    }

    /// 读取整型属性（默认 0）
    static func intProperty(_ obj: MIDIObjectRef, _ key: CFString) -> Int32 {
        var value: Int32 = 0
        let status = MIDIObjectGetIntegerProperty(obj, key, &value)
        return status == noErr ? value : 0
    }

    /// 读取字符串属性（失败返回 nil）
    static func stringProperty(_ obj: MIDIObjectRef, _ key: CFString) -> String? {
        var unmanaged: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(obj, key, &unmanaged)
        guard status == noErr, let value = unmanaged else { return nil }
        return value.takeRetainedValue() as String
    }
}
