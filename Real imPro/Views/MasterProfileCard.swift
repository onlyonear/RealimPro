//
//  MasterProfileCard.swift
//  Real imPro · 大师头像介绍卡（设置卡底部展示组件，纯 UI、不含生成逻辑）
//
//  左：72×72 正圆徽章（clipShape(Circle()) + 黑色描边 + 极细阴影）。
//  右：粗体标题（完整人名 + 生卒）+ 生平/风格正文（最多 5 行），与头像顶部对齐。
//  暖米色头像被收进圆形轮廓，呈徽章/硬币感，避免在白色面板上形成方形“补丁”。
//

import SwiftUI

struct MasterProfileCard: View {
    let profile: MasterProfile

    // 头像徽章尺寸
    private let badgeSize: CGFloat = 72
    private let strokeWidth: CGFloat = 2
    // 头像与文字间距；内容区宽 360，故文字块宽 = 360 - 72 - 12 = 276
    private let gap: CGFloat = 12

    var body: some View {
        HStack(alignment: .top, spacing: gap) {

            // 正圆徽章
            Image(profile.avatarImageName)
                .resizable()
                .scaledToFill()
                .frame(width: badgeSize, height: badgeSize)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(Color.black, lineWidth: strokeWidth)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 1.5, x: 0, y: 1)

            // 标题 + 正文
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(profile.bio)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }
}
