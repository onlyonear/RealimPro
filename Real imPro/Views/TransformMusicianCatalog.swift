// =====================================================================
// TransformMusicianCatalog.swift  [Hunk10 / ② Guide Tone & Transform]
// 仅【UI 展示】用的乐手有序目录：给调音台乐手 Menu 提供顺序与显示名。
// 不参与任何加载/缓存（那是 TransformMusicianRegistry 的职责，二者解耦）。
// id 与 Bundle 内 TransformTables/<id>.tsv 一一对应（共 26，My 为默认并置顶）。
// 大师专名不做本地化（按既有约定）。
// =====================================================================
import Foundation

enum TransformMusicianCatalog {

    /// 调音台乐手 Menu 顺序（My 默认置顶，其余字母序）
    static let allMusicians: [String] = [
        "My",
        "BillEvans", "BobBerg", "CedarWalton", "CharlieParker", "CliffordBrown",
        "ColemanHawkins", "DizzyGillespie", "FreddieHubbard", "JackieMcLean",
        "JimmyHeath", "JoeHenderson", "JoeLovano", "JohnColtrane", "KennyGarrett",
        "LeeMorgan", "LesterYoung", "MilesDavis", "NickBrignola", "PaulDesmond",
        "RedGarland", "RichPerry", "StanGetz", "TomHarrell", "VincentHerring",
        "WesMontgomery"
    ]

    /// 驼峰按大写分词：BillEvans -> "Bill Evans"（单词 My 原样）
    static func displayName(_ id: String) -> String {
        id.replacingOccurrences(of: "([a-z0-9])([A-Z])",
                                with: "$1 $2", options: .regularExpression)
    }

    /// 收起胶囊短名：多词取"首字母. 其余"（BillEvans -> "B. Evans"），单词原样（My）
    static func shortLabel(_ id: String) -> String {
        let words = displayName(id).components(separatedBy: " ")
        guard words.count > 1, let first = words.first, !first.isEmpty else { return id }
        return "\(first.prefix(1)). " + words.dropFirst().joined(separator: " ")
    }
}
