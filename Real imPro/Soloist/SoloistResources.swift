//
//  SoloistResources.swift
//  Real imPro · Soloist 运行时（K2-7 生产接入）
//
//  负责两件事：
//  1) 算法 → 语料文件映射（每位大师只挂自己那份；CharlieParker 的 12 小节走 Motif 版）
//  2) 从 App Bundle 加载 *-soloist.json，并做进程内缓存（生成在后台线程，加锁）
//
//  打包口径（十二审裁决，保守白名单）：
//  - 12 位大师本人语料全部打包；CharlieParkerMotif 仅作 12 小节 blues 补充源
//  - 每份文件内写死 verifiedSizes，不在名单内的小节数运行期永不启用
//  - JohnColtrane / MilesDavis / WayneShorter 的 verifiedSizes 为空 → 永远回退 grammar
//

import Foundation

// MARK: - 算法 → 语料

/// ImproAlgorithmType 是 ContentView 的嵌套类型，这里起别名保持签名简洁
typealias SoloistAlgorithm = ContentView.ImproAlgorithmType

enum SoloistCorpusCatalog {

    /// 返回该算法可用的语料基名（按尝试顺序）
    static func resourceBasenames(for algorithm: SoloistAlgorithm) -> [String] {
        switch algorithm {
        case .artPepper:            return ["ArtPepper"]
        case .billEvans:            return ["BillEvans"]
        case .budPowell:            return ["BudPowell"]
        case .cannonballAdderley:   return ["CannonballAdderley"]
        // 12 小节 blues 用 Motif 版（本人版 12 尺寸实测 5.29% 超阈，Motif 1.19% 通过）
        case .charlieParker:        return ["CharlieParker", "CharlieParkerMotif"]
        case .chetBaker:            return ["ChetBaker"]
        case .joePass:              return ["JoePass"]
        case .LeeMorgan:            return ["LeeMorgan"]
        case .redGarland:           return ["RedGarland"]
        // 三位本批无通过曲式（十二审裁决：全部回退 grammar）
        case .johnColtrane:         return ["JohnColtrane"]
        case .milesDavis:           return ["MilesDavis"]
        case .wayneShorter:         return ["WayneShorter"]
        // 基础组 / Lick / LSTM 组无 soloist 语料
        default:                    return []
        }
    }
}

// MARK: - 加载（带缓存）

enum SoloistRuntimeStore {

    private static let lock = NSLock()
    private static var cache: [String: SoloistRuntime] = [:]
    private static var misses: Set<String> = []

    /// 加载一份语料（成功/失败都会被记住，避免反复读盘）
    static func runtime(basename: String) -> SoloistRuntime? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[basename] { return cached }
        if misses.contains(basename) { return nil }
        guard let loaded = load(basename: basename) else {
            misses.insert(basename)
            return nil
        }
        cache[basename] = loaded
        return loaded
    }

    /// 该算法在目标曲式下是否有可启用的语料（不加载全部数据也能判，用于门控）
    static func hasVerifiedRuntime(for algorithm: SoloistAlgorithm,
                                   targetMeasures: Int) -> Bool {
        for basename in SoloistCorpusCatalog.resourceBasenames(for: algorithm) {
            if let rt = runtime(basename: basename),
               rt.effectiveSizes.contains(targetMeasures) {
                return true
            }
        }
        return false
    }

    private static func load(basename: String) -> SoloistRuntime? {
        if let url = Bundle.main.url(forResource: "\(basename)-soloist",
                                     withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let rt = try? SoloistRuntimeLoader.load(jsonData: data) {
            return rt
        }
        #if DEBUG
        // 构建机兜底：工程资源目录（与 Bundle 内容一致，含白名单字段）
        let devPath = "/Users/onlyonear/Desktop/Improlyze/Real imPro/soloist_runtime/\(basename)-soloist.json"
        if FileManager.default.fileExists(atPath: devPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: devPath)),
           let rt = try? SoloistRuntimeLoader.load(jsonData: data) {
            return rt
        }
        #endif
        return nil
    }
}
