// =====================================================================
// TermExplanationPopover.swift
// 点击 Key Section 术语后弹出的轻量解释卡片（不跳整页、不打断乐谱）。
// 纯展示、只读；含完整名称、通俗解释、可选和弦例子，以及"在词典中查看"入口。
// 全英文、面向音乐爱好者，无代码术语。
// =====================================================================
import SwiftUI

struct TermExplanationCard: View {
    let entry: TermEntry
    let onOpenGlossary: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "text.book.closed")
                    .foregroundColor(.brown)
                Text(entry.title)
                    .font(.system(size: 17, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }

            Text(entry.summary)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let example = entry.example, !example.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text(example)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.brown.opacity(0.10), in: Capsule())
            }

            Divider()

            HStack {
                Button {
                    onOpenGlossary()
                } label: {
                    Label("Open Glossary", systemImage: "book")
                        .font(.system(size: 14, weight: .semibold))
                }
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .padding(18)
    }
}
