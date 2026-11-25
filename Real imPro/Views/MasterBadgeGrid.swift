//
//  MasterBadgeGrid.swift
//  Real imPro · 大师徽章网格选择器（纯 UI 交互，不含任何生成逻辑）
//
//  本文件分两部分：
//  1) MasterSelection：把现有下拉菜单里的两条选择判据逐字提取为共享方法，下拉与网格同源调用。
//  2) MasterBadgeGrid / 徽章单元：点击底部大师徽章后弹出的"全员花名册"网格。
//
//  红线：不改变 solo 生成链路与付费墙逻辑；本文件只做选择接线与展示，判据与原下拉完全一致。
//

import SwiftUI

// MARK: - 共享选择判据（提取自原下拉，判断条件一字不改）

enum MasterSelection {

    /// Grammar 选择（源自 GrammarAlgorithmMenu.grammarButton）：
    /// 付费大师且未购 → 记录 pending + 弹付费墙（选中不变）；否则直接切换。
    static func chooseGrammar(_ algo: ContentView.ImproAlgorithmType,
                              isPurchased: Bool,
                              selectedAlgorithm: Binding<ContentView.ImproAlgorithmType>,
                              pendingMasterAlgorithm: Binding<ContentView.ImproAlgorithmType?>,
                              showPaywall: Binding<Bool>) {
        if algo.isPaidGrammar && !isPurchased {
            pendingMasterAlgorithm.wrappedValue = algo
            showPaywall.wrappedValue = true
        } else {
            selectedAlgorithm.wrappedValue = algo
        }
    }

    /// Soloist 选择（源自 SoloistResourceMenu 按钮）：
    /// 付费资源且未购 → 只弹付费墙并 return（无 pending，选中与持久化都不变）；
    /// 否则持久化 + 更新当前绑定。
    static func chooseSoloist(_ descriptor: SoloistResourceDescriptor,
                              isPurchased: Bool,
                              showPaywall: Binding<Bool>,
                              selectedResource: Binding<String>) {
        let free = SoloistResourceDirectory.isFree(descriptor.resource)
        if !free && !isPurchased {
            showPaywall.wrappedValue = true
            return
        }
        SoloistResourceDirectory.setSelectedResource(descriptor.resource)
        selectedResource.wrappedValue = descriptor.resource
    }
}

// MARK: - 视觉辅助（图标映射）

enum BadgeVisual {
    /// 乐器分组 → SF Symbol。管乐无专属符号，统一用 wind；Basic 用 music.note。
    static func iconName(for group: String?) -> String {
        switch group {
        case "Piano":  return "pianokeys"
        case "Guitar": return "guitars"
        case .some:    return "wind"
        case .none:    return "music.note"
        }
    }
}

// MARK: - 徽章网格弹出层

struct MasterBadgeGrid: View {
    let useSoloist: Bool
    let grammarGroups: [ContentView.OptionGroup]
    let soloistOrdered: [SoloistResourceDescriptor]

    @Binding var selectedAlgorithm: ContentView.ImproAlgorithmType
    @Binding var selectedResource: String
    @Binding var pendingMasterAlgorithm: ContentView.ImproAlgorithmType?
    @Binding var showPaywall: Bool
    @ObservedObject var iapManager: IAPManager
    let onClose: () -> Void

    // 固定 4 列，保证对称、等大
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    private var gridTitle: String {
        useSoloist
            ? NSLocalizedString("Choose a Soloist", comment: "")
            : NSLocalizedString("Choose a Grammar", comment: "")
    }

    var body: some View {
        ZStack {
            // 半透明遮罩（点击关闭）
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            // 居中卡片，宽度自适应、上限 600
            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if useSoloist {
                            soloistSection
                        } else {
                            grammarSection
                        }
                    }
                    .padding(16)
                }
            }
            .frame(maxWidth: 600, maxHeight: 620)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 8)
            .padding(24)
        }
    }

    private var header: some View {
        HStack {
            Text(gridTitle)
                .font(.system(size: 16, weight: .bold))
            Spacer()
            Button {
                onClose()
            } label: {
                Text(NSLocalizedString("Done", comment: ""))
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: Grammar（分组 + 对称网格）
    private var grammarSection: some View {
        ForEach(grammarGroups) { group in
            VStack(alignment: .leading, spacing: 8) {
                if let name = group.displayName {
                    Text(name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.secondary)
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(group.items, id: \.self) { algo in
                        grammarCell(algo)
                    }
                }
            }
        }
    }

    private func grammarCell(_ algo: ContentView.ImproAlgorithmType) -> some View {
        let profile = MasterProfileDirectory.profile(for: algo)
        let locked = algo.isPaidGrammar && !iapManager.isPurchased
        let selected = algo == selectedAlgorithm
        return Button {
            MasterSelection.chooseGrammar(algo,
                                          isPurchased: iapManager.isPurchased,
                                          selectedAlgorithm: $selectedAlgorithm,
                                          pendingMasterAlgorithm: $pendingMasterAlgorithm,
                                          showPaywall: $showPaywall)
        } label: {
            BadgeVStack(imageName: profile.avatarImageName,
                        name: algo.rawValue,
                        group: algo.instrumentGroup,
                        locked: locked,
                        selected: selected,
                        freeText: nil)
        }
        .buttonStyle(.plain)
    }

    // MARK: Soloist（单组，免费置顶）
    private var soloistSection: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(soloistOrdered) { d in
                soloistCell(d)
            }
        }
    }

    private func soloistCell(_ d: SoloistResourceDescriptor) -> some View {
        let profile = MasterProfileDirectory.profile(for: d.fallbackAlgorithm)
        let free = SoloistResourceDirectory.isFree(d.resource)
        let locked = !free && !iapManager.isPurchased
        let selected = d.resource == selectedResource
        return Button {
            MasterSelection.chooseSoloist(d,
                                          isPurchased: iapManager.isPurchased,
                                          showPaywall: $showPaywall,
                                          selectedResource: $selectedResource)
        } label: {
            BadgeVStack(imageName: profile.avatarImageName,
                        name: d.displayName,
                        group: d.fallbackAlgorithm.instrumentGroup,
                        locked: locked,
                        selected: selected,
                        freeText: free ? NSLocalizedString("Free", comment: "") : nil)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 徽章单元（头像 + 名字 + 乐器，Grammar/Soloist 共用）

private struct BadgeVStack: View {
    let imageName: String
    let name: String
    let group: String?
    let locked: Bool
    let selected: Bool
    let freeText: String?

    private let avatarSize: CGFloat = 64

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: avatarSize, height: avatarSize)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(selected ? Color.accentColor : Color.black,
                                        lineWidth: selected ? 3 : 2)
                    )
                    .opacity(locked ? 0.55 : 1.0)

                // 未解锁小锁（右下角）
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.black.opacity(0.75)))
                        .offset(x: avatarSize / 2 - 6, y: avatarSize / 2 - 6)
                }

                // 选中对勾（左上角）
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                        .background(Circle().fill(Color.white))
                        .offset(x: -(avatarSize / 2 - 8), y: -(avatarSize / 2 - 8))
                }
            }
            .frame(width: avatarSize, height: avatarSize)

            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            // 乐器图标 + 乐器名（Basic 组显示 Basic）
            HStack(spacing: 2) {
                Image(systemName: BadgeVisual.iconName(for: group))
                    .font(.system(size: 8))
                Text(group ?? NSLocalizedString("Basic", comment: ""))
                    .font(.system(size: 8))
            }
            .foregroundColor(.secondary)
            .lineLimit(1)

            // 免费标识
            if let freeText {
                Text(freeText)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.green)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
