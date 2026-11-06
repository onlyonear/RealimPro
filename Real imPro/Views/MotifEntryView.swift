//
//  MotifEntryView.swift
//  RealimPro
//
//  ThemeWeaver M5：动机录入页（点音符 + 文本粘贴）。
//  · 纯输入视图：产出 [PhysicalNote] 回写 Binding，不直接调用生成引擎。
//  · iPad 全尺寸横竖屏自适应（GeometryReader + horizontalSizeClass）。
//  · 文案统一 NSLocalizedString 中文 key，英文由 en.lproj 映射；用户可见处不出现 "Java"。
//  · 音域限 ThemeWeaver 硬域 60–82，越界键禁用；粘贴错误逐条标红、绝不静默丢弃。
//

import SwiftUI

// MARK: - 录入视图
struct MotifEntryView: View {
    @Binding var notes: [PhysicalNote]
    let beatsPerMeasure: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize

    // 时值选择（分母 → slots）
    private struct Dur: Identifiable { let id = UUID(); let label: String; let slots: Int }
    private let durations: [Dur] = [
        Dur(label: "𝅝", slots: 480), Dur(label: "𝅗𝅥", slots: 240), Dur(label: "♩", slots: 120),
        Dur(label: "♪", slots: 60), Dur(label: "♬", slots: 30)
    ]
    @State private var selectedSlots = 120
    @State private var dotted = false
    @State private var triplet = false
    @State private var insertRest = false
    @State private var draft: [PhysicalNote] = []
    @State private var pasteText: String = ""
    @State private var parseErrors: [String] = []

    private let minPitch = 60
    private let maxPitch = 82

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let wide = (hSize == .regular) && geo.size.width > 600
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        pianoStrip
                        rhythmBar
                        entryList(wide: wide)
                        pasteSection
                        footerSummary
                    }
                    .padding(wide ? 24 : 16)
                    .frame(maxWidth: wide ? 720 : .infinity)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(NSLocalizedString("编辑动机", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("清空", comment: "")) { draft.removeAll() }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button(NSLocalizedString("撤销", comment: "")) { if !draft.isEmpty { draft.removeLast() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("完成", comment: "")) {
                        notes = draft
                        dismiss()
                    }
                    .disabled(draft.isEmpty)
                }
            }
            .onAppear { if draft.isEmpty { draft = notes } }   // 以当前自动动机为起点可改
        }
    }

    // 音域内琴键（点音高追加；越界不渲染=禁用）
    private var pianoStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("点音符录入", comment: "")).font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(minPitch...maxPitch, id: \.self) { midi in
                        Button {
                            let slots = effectiveSlots()
                            let pitch = insertRest ? -1 : midi
                            draft.append(PhysicalNote(midiPitch: pitch, durationSlots: slots))
                        } label: {
                            Text(MotifTextParser.midiToName(midi))
                                .font(.caption2.weight(.medium))
                                .frame(width: 30, height: 44)
                                .background(isBlackKey(midi) ? Color(white: 0.2) : Color(white: 0.95))
                                .foregroundColor(isBlackKey(midi) ? .white : .black)
                                .cornerRadius(6)
                        }
                    }
                }
            }
        }
    }

    private var rhythmBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("时值", comment: "")).font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                ForEach(durations) { d in
                    Button { selectedSlots = d.slots } label: {
                        Text(d.label).frame(width: 34, height: 30)
                            .background(selectedSlots == d.slots ? Color.accentColor : Color.gray.opacity(0.15))
                            .foregroundColor(selectedSlots == d.slots ? .white : .primary)
                            .cornerRadius(6)
                    }
                }
                Toggle(NSLocalizedString("附点", comment: ""), isOn: $dotted).toggleStyle(.button)
                    .buttonStyle(.bordered)
                Toggle(NSLocalizedString("三连音", comment: ""), isOn: $triplet).toggleStyle(.button)
                    .buttonStyle(.bordered)
                Toggle(NSLocalizedString("休止", comment: ""), isOn: $insertRest).toggleStyle(.button)
                    .buttonStyle(.bordered)
            }
        }
    }

    private func entryList(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(format: NSLocalizedString("已录 %d 音 · %d slots", comment: ""),
                        draft.count, totalSlots()))
                .font(.caption).foregroundColor(.secondary)
            let columns = [GridItem(.adaptive(minimum: wide ? 110 : 90), spacing: 8)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(Array(draft.enumerated()), id: \.offset) { idx, n in
                    HStack {
                        Text(n.isRest ? NSLocalizedString("休止", comment: "") : MotifTextParser.midiToName(n.midiPitch))
                        Spacer()
                        Text(rhythmLabel(n.durationSlots)).foregroundColor(.secondary).font(.caption)
                        Button { draft.remove(at: idx) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Color.gray.opacity(0.10)).cornerRadius(6)
                }
            }
        }
    }

    private var pasteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("粘贴音符", comment: "")).font(.subheadline.weight(.semibold))
            Text("C4 8, D4 16, R 8, E4 8t").font(.caption).foregroundColor(.secondary)
            TextEditor(text: $pasteText)
                .font(.system(.body, design: .monospaced))
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
            HStack {
                Button(NSLocalizedString("解析并填入", comment: "")) {
                    let r = MotifTextParser.parse(pasteText, minPitch: minPitch, maxPitch: maxPitch)
                    parseErrors = r.errors
                    if !r.notes.isEmpty { draft.append(contentsOf: r.notes) }
                }.buttonStyle(.bordered)
                if !parseErrors.isEmpty {
                    Text(parseErrors.joined(separator: "  "))
                        .font(.caption).foregroundColor(.red)
                }
            }
        }
    }

    private var footerSummary: some View {
        Text(String(format: NSLocalizedString("动机长度 %d / 小节 %d slots", comment: ""),
                    totalSlots(), beatsPerMeasure * 120))
            .font(.caption).foregroundColor(.secondary)
    }

    // MARK: helpers
    private func effectiveSlots() -> Int {
        var s = selectedSlots
        if dotted { s = s * 3 / 2 }
        if triplet { s = s * 2 / 3 }
        return s
    }
    private func totalSlots() -> Int { draft.reduce(0) { $0 + $1.durationSlots } }
    private func isBlackKey(_ midi: Int) -> Bool { [1,3,6,8,10].contains(((midi % 12)+12)%12) }
    private func rhythmLabel(_ slots: Int) -> String {
        switch slots {
        case 480: return "1"
        case 240: return "2"
        case 360: return "2."
        case 120: return "4"
        case 180: return "4."
        case 60: return "8"
        case 90: return "8."
        case 40: return "8t"
        case 30: return "16"
        case 20: return "16t"
        default: return "\(slots)"
        }
    }
}
