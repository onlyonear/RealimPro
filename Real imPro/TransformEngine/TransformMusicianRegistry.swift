// =====================================================================
// TransformMusicianRegistry.swift
// ② Guide Tone & Transform（T1）乐手规则表【运行时懒加载】注册表。
//
// 体积策略（用户拍板）：26 个乐手学习库全量内置在 App Bundle（不做 ODR/按需下载），
// 但启动绝不把 26 张表读进内存——只有当（未来）UI 选中某乐手时才解析其【单文件】，
// 解析结果按 LRU 仅保留最近使用的若干张（默认 2），切换即释放更旧的表。
// My 为兜底默认表。
//
// 命令行探针无 Bundle.main 资源：可设置 resourceRootOverride 指向 audit 里的 tsv 目录。
// =====================================================================

import Foundation

enum TransformMusicianRegistry {

    /// 兜底默认乐手（手写规则表）
    static let defaultMusician = "My"
    /// Bundle 内子目录
    static let bundleSubdir = "TransformTables"
    /// LRU 同时驻留上限（KG/CP 单张解析后对象树约 MB 级，避免 26 张全驻留）
    static var lruCap = 2
    /// 诊断：最近一次【首次】解析耗时（秒），主线程卡顿则改后台解析
    static private(set) var lastParseSeconds: Double = 0
    /// 诊断：累计未命中后实际读盘解析次数
    static private(set) var loadCount = 0

    /// 命令行/测试覆盖：设置后从该绝对目录读 <musician>.tsv（生产运行时为 nil，走 Bundle.main）
    static var resourceRootOverride: String? = nil

    private static var tables: [String: [TransformEngine.GSub]] = [:]
    /// LRU 顺序，末尾为最近使用
    private static var order: [String] = []
    private static let lock = NSLock()

    /// 取某乐手表；找不到文件返回 nil（调用方回退默认表/不替换，不崩）
    static func table(for musician: String) -> [TransformEngine.GSub]? {
        lock.lock(); defer { lock.unlock() }
        let key = musician
        if let t = tables[key] {
            touch(key)
            return t
        }
        guard let text = loadText(key) else { return nil }
        let t0 = Date()
        let parsed = TransformEngine.parseTransformTable(text)
        lastParseSeconds = Date().timeIntervalSince(t0)
        loadCount += 1
        tables[key] = parsed
        order.append(key)
        evictIfNeeded()
        return parsed
    }

    /// 取表，缺失时回退默认乐手表；再缺返回 nil
    static func tableWithFallback(_ musician: String?) -> [TransformEngine.GSub]? {
        if let m = musician, let t = table(for: m) { return t }
        if musician != defaultMusician, let t = table(for: defaultMusician) { return t }
        return nil
    }

    static func clearCache() {
        lock.lock(); defer { lock.unlock() }
        tables.removeAll(); order.removeAll()
    }

    // MARK: - 私有

    private static func touch(_ key: String) {
        guard let idx = order.firstIndex(of: key) else { order.append(key); return }
        order.remove(at: idx); order.append(key)
    }

    private static func evictIfNeeded() {
        while order.count > lruCap, let oldest = order.first {
            order.removeFirst()
            tables.removeValue(forKey: oldest)
        }
    }

    private static func loadText(_ musician: String) -> String? {
        if let root = resourceRootOverride {
            let p = (root as NSString).appendingPathComponent("\(musician).tsv")
            return try? String(contentsOfFile: p, encoding: .utf8)
        }
        // 本工程用 Xcode 文件系统同步组，资源被平铺到 .app 根：优先平铺查找
        if let url = Bundle.main.url(forResource: musician, withExtension: "tsv") {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        // 兜底：若以后改成 folder reference（蓝色组），资源在 TransformTables/ 子目录
        if let url = Bundle.main.url(forResource: musician, withExtension: "tsv", subdirectory: bundleSubdir) {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        return nil
    }
}
