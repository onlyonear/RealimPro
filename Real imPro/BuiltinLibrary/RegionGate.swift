//
//  RegionGate.swift
//  Real imPro
//
//  按 App Store 商店区（storefront）决定内置曲库可见范围。
//  纯离线：SKStorefront 为系统本地 API，不联网、不读隐私数据、不上报。
//
//  规则（法务分档）：
//  - global   ：所有地区可见。
//  - usOnly   ：仅美国 storefront 可见；到了 unlockDate 自动升为 global。
//  - 无法判断地区时：保守走 global only（不暴露 usOnly）。
//

import Foundation
import StoreKit

enum RegionGate {

    /// 当前是否为美国 App Store 商店区。
    /// 优先级：SKPaymentQueue.storefront（三字母国家码，如 "USA"）> 设备 Locale（两字母，如 "US"）。
    static var isUSStorefront: Bool {
        // 1) App Store 账号所在区（最准）
        if let code = SKPaymentQueue.default().storefront?.countryCode {
            return code == "USA" || code == "US"
        }
        // 2) 设备区域设置兜底
        if let region = Locale.current.region?.identifier {
            return region == "US"
        }
        // 3) 都拿不到：保守，按非美国处理
        return false
    }

    /// 某首内置歌在当前地区是否应显示。
    /// - Parameter tag: JSON 的 regionTag（"global" / "usOnly" / nil）
    /// - Parameter unlockDate: "YYYY-MM-DD"，usOnly 到该日期后升为 global
    static func isVisible(regionTag tag: String?, unlockDate: String?) -> Bool {
        let tier = (tag ?? "global").lowercased()
        if tier == "usonly" {
            // 到了解禁日，自动升为全球可见
            if let date = unlockDateDate(unlockDate), date <= Date() {
                return true
            }
            return isUSStorefront
        }
        // nil / "global" / 其他未知值：按全球可见
        return true
    }

    // MARK: - 私有

    private static func unlockDateDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}
