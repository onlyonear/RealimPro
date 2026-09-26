//
//  ImprolyzeApp.swift
//  Improlyze
//
//  Created by OnlyOnear on 2026/6/16.
//

import SwiftUI
#if DEBUG
import UIKit

// P1 验证用（仅 DEBUG）：由启动参数 -landscape 临时把方向锁成横屏，
// 便于在无法经 DeviceHub 旋转模拟器时截取横屏图。Release 下本类与适配点整体剔除。
final class DebugOrientationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        if ProcessInfo.processInfo.arguments.contains("-landscape") {
            return .landscape
        }
        return .all
    }

    // P1 验证用：用 iOS16+ 的 requestGeometryUpdate 把全屏 App 程序化转到横屏，
    // 绕开 Xcode 26 DeviceHub 已移除旋转菜单、simctl 无方向接口的限制。仅 DEBUG。
    @MainActor
    static func forceLandscapeIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-landscape") else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(
            UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .landscapeRight)
        ) { _ in }
        scene.windows.first(where: { $0.isKeyWindow })?
            .rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}
#endif

@main
struct ImprolyzeApp: App {
    @StateObject private var iap = IAPManager.shared
    #if DEBUG
    @UIApplicationDelegateAdaptor(DebugOrientationDelegate.self) private var orientationDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(iap)
        }
    }
}
