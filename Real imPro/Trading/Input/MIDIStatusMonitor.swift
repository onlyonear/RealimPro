import Foundation
import CoreMIDI
import SwiftUI
import Combine

/// 轻量级 MIDI 设备状态监视器（App 启动时即运行，不连接输入源）
/// 只负责枚举设备 + 监听热插拔变化，供 UI 显示连接状态。
final class MIDIStatusMonitor: ObservableObject {
    static let shared = MIDIStatusMonitor()

    @Published private(set) var statusText: String = "No MIDI device"

    private var client = MIDIClientRef()
    private var isRunning = false

    private init() {
        start()
    }

    func start() {
        guard !isRunning else { return }

        let notifyBlock: MIDINotifyBlock = { [weak self] notification in
            guard let self = self else { return }
            if notification.pointee.messageID == .msgSetupChanged {
                self.refresh()
            }
        }

        let status = MIDIClientCreateWithBlock("RealimPro MIDI Status" as CFString, &client, notifyBlock)
        guard status == noErr else { return }

        isRunning = true
        refresh()
    }

    private func refresh() {
        let count = MIDIGetNumberOfSources()
        var online: [String] = []
        for i in 0..<count {
            let endpoint = MIDIGetSource(i)
            guard endpoint != 0 else { continue }

            var isOffline: Int32 = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &isOffline)
            guard isOffline == 0 else { continue }

            var nameRef: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &nameRef)
            if let name = nameRef?.takeRetainedValue() as String? {
                online.append(name)
            }
        }

        DispatchQueue.main.async {
            self.statusText = online.isEmpty ? "No MIDI device" : online.joined(separator: ", ")
        }
    }
}
