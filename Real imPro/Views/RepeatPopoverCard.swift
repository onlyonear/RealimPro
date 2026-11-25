import SwiftUI

// MARK: - Repeat 重复次数选择卡片（参考 iRealPro）
/// 大数字 + -/重置/+ 按钮 + 滑块，取值 1–5，默认 1
struct RepeatPopoverCard: View {
    @Binding var repeatCount: Int

    var body: some View {
        VStack(spacing: 16) {
            // 标题 + 大数字
            VStack(spacing: 4) {
                Text("Repeat")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("\(repeatCount)x")
                    .font(.system(size: 48, weight: .light))
            }

            // - 按钮 / 重置图标 / + 按钮
            HStack(spacing: 24) {
                Button {
                    if repeatCount > 1 { repeatCount -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(repeatCount > 1 ? .accentColor : .gray)
                }
                .disabled(repeatCount <= 1)

                Button {
                    repeatCount = 1
                } label: {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.accentColor)
                }

                Button {
                    if repeatCount < 5 { repeatCount += 1 }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(repeatCount < 5 ? .accentColor : .gray)
                }
                .disabled(repeatCount >= 5)
            }

            // 滑块
            Slider(value: Binding(
                get: { Double(repeatCount) },
                set: { repeatCount = Int($0) }
            ), in: 1...5, step: 1)
            .tint(.accentColor)
        }
        .padding(24)
    }
}
