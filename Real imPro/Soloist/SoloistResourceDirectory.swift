//
//  SoloistResourceDirectory.swift
//  Real imPro · 真复刻 Soloist 资源目录（UI 与 worker 共用的单一事实源）
//
//  描述 11 个已打包 K3 资源：语料类型、可用小节数、回退同名 grammar。
//  判定口径与 K3 outlines 逐字一致；本文件只做静态描述，不含任何生成逻辑。
//

import Foundation

// MARK: - 语料类型

enum SoloistCorpusType: String {
    case normal
    case motif
}

// MARK: - 资源描述

struct SoloistResourceDescriptor: Identifiable, Equatable {
    let resource: String                       // K3 资源基名（Bundle 资源名）
    let corpusType: SoloistCorpusType
    let enabledSizes: [Int]                    // 已排序、去重
    let fallbackAlgorithm: ContentView.ImproAlgorithmType   // 回退同名 grammar

    var id: String { resource }

    /// 括号小节数文本，如 "50" 或 "12/31/32/63"
    var sizesLabel: String {
        enabledSizes.map(String.init).joined(separator: "/")
    }

    /// 下拉完整标签，如 "ArtPepper (50 bars)"
    var menuLabel: String {
        "\(resource) (\(sizesLabel) \(NSLocalizedString("小节", comment: "")))"
    }

    /// 大师友好名：去 Motif 后缀、驼峰按大写拆空格，如 "CliffordBrownMotif" → "Clifford Brown"
    var displayName: String {
        let base = resource.hasSuffix("Motif") ? String(resource.dropLast("Motif".count)) : resource
        let pieces = base.unicodeScalars.map { scalar -> String in
            CharacterSet.uppercaseLetters.contains(scalar) ? " \(scalar)" : String(scalar)
        }
        return pieces.joined().trimmingCharacters(in: .whitespaces)
    }

    func supports(measures: Int) -> Bool {
        enabledSizes.contains(measures)
    }
}

// MARK: - 目录

enum SoloistResourceDirectory {
    /// 用户选择持久化键（String，存 resource 基名）
    static let selectedResourceKey = "selectedSoloistResource"
    static let defaultResource = "CharlieParker"
    /// 免费橱窗大师（用户可免费体验其 Soloist 生成效果），其余 10 个为付费
    static let freeResource = "BillEvans"
    static func isFree(_ resource: String) -> Bool { resource == freeResource }

    /// 11 个已打包 K3 资源（平铺，不按大师合并）
    static let descriptors: [SoloistResourceDescriptor] = [
        SoloistResourceDescriptor(resource: "ArtPepper", corpusType: .normal,
                                  enabledSizes: [50], fallbackAlgorithm: .artPepper),
        SoloistResourceDescriptor(resource: "BillEvans", corpusType: .normal,
                                  enabledSizes: [32], fallbackAlgorithm: .billEvans),
        SoloistResourceDescriptor(resource: "BudPowell", corpusType: .normal,
                                  enabledSizes: [34], fallbackAlgorithm: .budPowell),
        SoloistResourceDescriptor(resource: "CannonballAdderley", corpusType: .normal,
                                  enabledSizes: [40], fallbackAlgorithm: .cannonballAdderley),
        SoloistResourceDescriptor(resource: "CharlieParker", corpusType: .normal,
                                  enabledSizes: [12, 31, 32, 63], fallbackAlgorithm: .charlieParker),
        SoloistResourceDescriptor(resource: "CharlieParkerMotif", corpusType: .motif,
                                  enabledSizes: [11, 12, 29, 30, 31, 32, 60],
                                  fallbackAlgorithm: .charlieParker),
        SoloistResourceDescriptor(resource: "ChetBaker", corpusType: .normal,
                                  enabledSizes: [110], fallbackAlgorithm: .chetBaker),
        SoloistResourceDescriptor(resource: "CliffordBrownMotif", corpusType: .motif,
                                  enabledSizes: [9, 12], fallbackAlgorithm: .cliffordBrown),
        SoloistResourceDescriptor(resource: "JoePass", corpusType: .normal,
                                  enabledSizes: [64], fallbackAlgorithm: .joePass),
        SoloistResourceDescriptor(resource: "LeeMorgan", corpusType: .normal,
                                  enabledSizes: [32, 38], fallbackAlgorithm: .LeeMorgan),
        SoloistResourceDescriptor(resource: "RedGarland", corpusType: .normal,
                                  enabledSizes: [32, 60], fallbackAlgorithm: .redGarland)
    ]

    /// 用户当前选择（带合法性校验；非法/缺失回退默认）
    static var selectedResource: String {
        let stored = UserDefaults.standard.string(forKey: selectedResourceKey) ?? defaultResource
        return descriptor(for: stored) != nil ? stored : defaultResource
    }

    /// 免费资源置顶的展示顺序（下拉与徽章网格共用，保证两处顺序完全一致）：
    /// 免费项在前，其余保持 descriptors 原始顺序。
    static var ordered: [SoloistResourceDescriptor] {
        let free = descriptors.filter { isFree($0.resource) }
        let rest = descriptors.filter { !isFree($0.resource) }
        return free + rest
    }

    static func setSelectedResource(_ resource: String) {
        guard descriptor(for: resource) != nil else { return }
        UserDefaults.standard.set(resource, forKey: selectedResourceKey)
    }

    static func descriptor(for resource: String) -> SoloistResourceDescriptor? {
        descriptors.first { $0.resource == resource }
    }
}
