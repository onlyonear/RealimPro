// =====================================================================
// TermGlossary.swift
// 完整术语词典页：NavigationStack + 搜索框 + ScrollView。
// 结构对齐 MixerHelpSheet；分"功能家族"与"常见术语"两组，可搜索。
// 纯展示、只读。全英文、面向音乐爱好者，无代码术语。
// =====================================================================
import SwiftUI

struct TermGlossary: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    var highlightedTerm: String? = nil

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(overview)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if filteredSpecific.isEmpty && filteredFamilies.isEmpty {
                            Text("No terms match \"\(searchText)\".")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .padding(.top, 24)
                        }

                        if !filteredSpecific.isEmpty {
                            sectionHeader("Common Terms")
                            ForEach(filteredSpecific) { entry in
                                TermRow(entry: entry).id(entry.term)
                            }
                        }

                        if !filteredFamilies.isEmpty {
                            sectionHeader("Harmony Families")
                            ForEach(filteredFamilies) { entry in
                                TermRow(entry: entry).id(entry.term)
                            }
                        }
                    }
                    .padding(20)
                }
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "Search terms")
                .onAppear {
                    if let target = highlightedTerm {
                        // 等搜索栏布局完成后再滚动定位
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            withAnimation { proxy.scrollTo(target, anchor: .center) }
                        }
                    }
                }
            }
            .navigationTitle("Glossary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var overview: String {
        "These labels describe what the harmony is doing in each Key Section. Common terms cover specific bricks you will see often; harmony families explain the broader functions. When a brick has no entry of its own, the app explains it by its family."
    }

    private var filteredSpecific: [TermEntry] {
        filter(TermGlossaryData.specificEntries)
    }

    private var filteredFamilies: [TermEntry] {
        filter(TermGlossaryData.familyEntries)
    }

    private func filter(_ entries: [TermEntry]) -> [TermEntry] {
        let key = searchText.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return entries }
        return entries.filter {
            $0.title.localizedCaseInsensitiveContains(key) || $0.summary.localizedCaseInsensitiveContains(key)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.brown)
            .textCase(.uppercase)
            .padding(.top, 4)
    }
}

private struct TermRow: View {
    let entry: TermEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(entry.title)
                    .font(.system(size: 14, weight: .semibold))
                if entry.isFamily {
                    Text("Family")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
            Text(entry.summary)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let example = entry.example, !example.isEmpty {
                Text(example)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.brown)
            }
        }
        .padding(.vertical, 4)
    }
}
