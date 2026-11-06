import Foundation

// MARK: - Trading / Diagnostics / 探针启动器
//
// 用途：让**外部命令**（`devicectl` 的启动环境变量）能唤起 M1 验收探针。
//
// 【为什么必须有这么一个"调用点"】
//   · Swift 不允许 `+load` 之类的启动自动钩子（实测编译器直接报错 "not permitted by Swift"）；
//   · 命令行调试器需要在设备上手工起 debugserver 转发端口，在本机不可行；
//   · Swift 中没有任何"零调用点也能自动执行"的官方机制。
//   因此需要一个极小的调用点（1 行），加在 App 入口 `Views/ImprolyzeApp.swift` 的 `init()` 里。
//   ⚠️ 那一行属于**集成点 #1b**，**必须用户书面批准后才加**。本文件只是把逻辑准备好。
//
// 【Release 安全性】
//   DEBUG  ：读环境变量 TRADING_PROBE，有值才动作；无值（日常运行）什么都不做。
//   Release：整个实现体被 `#if DEBUG` 剔掉，只剩一个空函数，保证调用点始终能编译；
//            上架包内不含任何探针逻辑。

#if DEBUG

import UIKit

enum TradingProbeLauncher {

    /// 在 App 启动时调用；只有设置了环境变量 `TRADING_PROBE` 才动作。
    /// 例：`TRADING_PROBE=scan` / `capture` / `groove` / `delta` / `all`
    static func checkLaunchEnvironment() {
        let env = ProcessInfo.processInfo.environment

        // 兼容两种触发方式：环境变量（devicectl -e）或启动参数（Xcode 的 Arguments）
        var command: String? = env["TRADING_PROBE"]
        let args = ProcessInfo.processInfo.arguments
        if command == nil, let i = args.firstIndex(of: "-tradingProbe"), i + 1 < args.count {
            command = args[i + 1]
        }
        guard let cmd = command, !cmd.isEmpty else { return }

        // 量化网格可选：TRADING_PROBE_GRID = 8 | 16 | tri | none
        if let g = env["TRADING_PROBE_GRID"] {
            switch g.lowercased() {
            case "16", "sixteenth": TradingMIDIDebugProbe.gridOverride = .sixteenth
            case "tri", "triplet":  TradingMIDIDebugProbe.gridOverride = .tripletEighth
            case "none":            TradingMIDIDebugProbe.gridOverride = .none
            default:                TradingMIDIDebugProbe.gridOverride = .eighth
            }
            print("[TRADING-PROBE] 量化网格已设为：\(TradingMIDIDebugProbe.gridOverride.displayName)")
        }

        print("[TRADING-PROBE] 启动触发命中：\(cmd)")
        let delay = Double(env["TRADING_PROBE_DELAY"] ?? "") ?? 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            tradingProbe(cmd)
        }
    }
}

#else

/// Release：空实现（编译器会内联成空操作）。调用点因此无需 `#if`，上架包内无探针逻辑。
enum TradingProbeLauncher {
    static func checkLaunchEnvironment() { }
}

#endif
