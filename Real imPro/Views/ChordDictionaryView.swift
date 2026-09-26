import SwiftUI
import UIKit

// MARK: - 和弦音 / 色彩音字典页
// 从五线谱主界面「屏幕右边缘向左滑」呼出。
// 设计原则：表格内容【不手抄】——遍历代码中 ChordQuality 的 16 种品质，
// 和弦音取 chordIntervals、两档色彩音取 colorIntervals(for:palette:)，
// 与 Solo 生成 / 屏幕着色所用音集严格同源，代码改了这里自动同步、不会遗漏。
struct ChordDictionaryView: View {
    /// 由外层 ContentView 绑定，用于「完成 / 左边缘向右滑」关闭
    @Binding var isPresented: Bool

    // 半音(距根音) → 延伸音级数记号（色彩音使用 9/11/13 延伸体系）
    private static let colorDegreeName: [Int: String] = [
        0: "1", 1: "b9", 2: "9", 3: "#9", 4: "3", 5: "11",
        6: "#11", 7: "5", 8: "b13", 9: "13", 10: "b7", 11: "7"
    ]
    // 级数记号 → 半音，仅用于 DEBUG 断言，保证「和弦音标签」与 chordIntervals 严格一致
    private static let degreeToSemitone: [String: Int] = [
        "1": 0, "b9": 1, "9": 2, "#9": 3, "b3": 3, "3": 4, "11": 5,
        "4": 5, "#11": 6, "b5": 6, "5": 7, "#5": 8, "b13": 8,
        "6": 9, "13": 9, "b7": 10, "7": 11, "2": 2
    ]

    // 乐理标准的「和弦音」级数标签（固定；减七七音按用户要求写作 6 而非 bb7）
    private static func chordDegreeLabels(_ q: ChordQuality) -> [String] {
        switch q {
        case .major7:         return ["1", "3", "5", "7"]
        case .minor7:         return ["1", "b3", "5", "b7"]
        case .dominant7:      return ["1", "3", "5", "b7"]
        case .halfDiminished: return ["1", "b3", "b5", "b7"]
        case .diminished7:    return ["1", "b3", "b5", "6"]   // bb7 等音写作 6
        case .augmented7:     return ["1", "3", "#5", "b7"]
        case .minorMajor7:    return ["1", "b3", "5", "7"]
        case .alt:            return ["1", "3", "b5", "#5", "b7"]
        case .sus4:           return ["1", "4", "5"]
        case .sus2:           return ["1", "2", "5"]
        case .sevenSus4:      return ["1", "4", "5", "b7"]
        case .majorSevenSus4: return ["1", "4", "5", "7"]   // 【新增】大七挂四
        case .add9:           return ["1", "3", "5", "9"]
        case .six:            return ["1", "3", "5", "6"]
        case .minorSix:       return ["1", "b3", "5", "6"]
        case .diminishedTriad:return ["1", "b3", "b5"]
        case .augmentedTriad: return ["1", "3", "#5"]
        }
    }

    // 音阶级数记号 → 半音，仅用于 DEBUG 断言，保证「音阶级数」与 scaleIntervals 严格一致
    private static let scaleDegreeToSemitone: [String: Int] = [
        "1": 0, "b2": 1, "2": 2, "b3": 3, "3": 4, "4": 5,
        "b5": 6, "#4": 6, "5": 7, "b6": 8, "#5": 8, "6": 9, "b7": 10, "7": 11
    ]

    // 每种品质的「首选音阶」（对齐 Java My.voc firstScale，即给乐手看的第一层音阶；
    // 不是生成器内部按 family 的级数换算表 scaleDegreeSemitones）。音阶名为爵士通用专名，保持英文。
    private static func scaleInfo(_ q: ChordQuality) -> (name: String, degrees: [String]) {
        switch q {
        case .major7, .sus2, .add9, .six, .majorSevenSus4:
            return ("Ionian", ["1","2","3","4","5","6","7"])
        case .minor7:
            return ("Dorian", ["1","2","b3","4","5","6","b7"])
        case .dominant7, .sevenSus4:
            return ("Mixolydian", ["1","2","3","4","5","6","b7"])
        case .halfDiminished:
            return ("Locrian #2", ["1","2","b3","4","b5","b6","b7"])
        case .diminished7, .diminishedTriad:
            return ("Diminished (W-H)", ["1","2","b3","4","b5","b6","6","7"])
        case .augmented7:
            return ("Whole Tone", ["1","2","3","#4","#5","b7"])
        case .augmentedTriad:
            return ("Lydian Augmented", ["1","2","3","#4","#5","6","7"])
        case .minorMajor7, .minorSix:
            return ("Melodic Minor", ["1","2","b3","4","5","6","7"])
        case .alt:
            return ("Super Locrian", ["1","b2","b3","3","b5","b6","b7"])
        case .sus4:
            return ("Minor 6 Pentatonic", ["1","b3","4","5","6"])
        }
    }

    private struct CDItem: Identifiable {
        let id = UUID()
        let symbol: String          // 显示用通用和弦符号（国际通用，不本地化）
        let representative: String  // 喂给 ChordQuality(chordName:) 的代表和弦
        let quality: ChordQuality
        var chordDegrees: [String] { ChordDictionaryView.chordDegreeLabels(quality) }
        var scaleInfo: (name: String, degrees: [String]) { ChordDictionaryView.scaleInfo(quality) }
        func colorDegrees(_ palette: ColorPaletteMode) -> [String] {
            ChordQuality(chordName: representative)
                .colorIntervals(for: representative, palette: palette)
                .compactMap { colorDegreeName[$0] }
        }
    }
    private struct CDSection: Identifiable {
        let id = UUID()
        let titleKey: String
        let items: [CDItem]
    }

    // 展示顺序：常见 → 不常见；属七变化音按用户要求拆成独立行，紧跟基础 C7。
    private static let sections: [CDSection] = {
        func item(_ symbol: String, _ rep: String, _ q: ChordQuality) -> CDItem {
            #if DEBUG
            // 强校验 1：代表和弦名必须被解析为预期品质（防止符号写错导致整行错误）
            let parsed = ChordQuality(chordName: rep)
            assert(String(describing: parsed) == String(describing: q),
                   "ChordDictionary: \(rep) 解析为 \(parsed)，预期 \(q)")
            // 强校验 2：和弦音级数标签的半音集合必须等于 chordIntervals（防止乐理标签写错）
            let labelSemi = Set(chordDegreeLabels(q).compactMap { degreeToSemitone[$0] })
            let codeSemi = Set(q.chordIntervals)
            assert(labelSemi == codeSemi, "ChordDictionary: \(rep) 和弦音标签 \(labelSemi) 与代码 \(codeSemi) 不一致")
            // 强校验 3：首选音阶级数的半音集合必须等于 scaleIntervals（防止音阶标签写错）
            let info = scaleInfo(q)
            let scaleLabelSemi = Set(info.degrees.compactMap { scaleDegreeToSemitone[$0] })
            let scaleCodeSemi = Set(q.scaleIntervals)
            assert(scaleLabelSemi == scaleCodeSemi,
                   "ChordDictionary: \(rep) 音阶 \(info.name) \(info.degrees) 半音 \(scaleLabelSemi) 与 scaleIntervals \(scaleCodeSemi) 不一致")
            #endif
            return CDItem(symbol: symbol, representative: rep, quality: q)
        }
        return [
            CDSection(titleKey: "核心三和弦与七和弦", items: [
                item("Cmaj7", "CM7", .major7),
                item("Cm7", "Cm7", .minor7),
                item("C7", "C7", .dominant7),
                item("C6", "C6", .six),
                item("Cm6", "Cm6", .minorSix),
                item("Cadd9", "Cadd9", .add9)
            ]),
            CDSection(titleKey: "属七变化音", items: [
                item("C7b9", "C7b9", .dominant7),
                item("C7#9", "C7#9", .dominant7),
                item("C7#11", "C7#11", .dominant7),
                item("C7b13", "C7b13", .dominant7)
            ]),
            CDSection(titleKey: "挂留和弦", items: [
                item("Csus4", "Csus4", .sus4),
                item("C7sus4", "C7sus4", .sevenSus4),
                item("Csus2", "Csus2", .sus2)
            ]),
            CDSection(titleKey: "小调色彩", items: [
                item("CmM7", "CmM7", .minorMajor7),
                item("Cm7b5", "Cm7b5", .halfDiminished)
            ]),
            CDSection(titleKey: "减 · 增 · 变化", items: [
                item("Co7", "Co7", .diminished7),
                item("Co", "Co", .diminishedTriad),
                item("Caug", "Caug", .augmentedTriad),
                item("Caug7", "Caug7", .augmented7),
                item("C7alt", "C7alt", .alt)
            ])
        ]
    }()

    // 五列比例（Chord / Chord Tones / Conservative / Extended / Scale），表头与行共用以严格对齐
    // Scale 列内容较短，把宽度让给最长的 Extended，保证变化音串不换行
    private let columnFractions: [CGFloat] = [0.11, 0.14, 0.24, 0.27, 0.24]

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let wide = geo.size.width >= 680
                // 列宽统一口径：外层 20 边距 + 卡片内 14 内边距，表头与卡片内列严格对齐
                let tableWidth = geo.size.width - 40 - 28
                VStack(spacing: 0) {
                    if wide {
                        headerRow(width: tableWidth)
                            .padding(.horizontal, 34)
                            .padding(.top, 14)
                            .padding(.bottom, 6)
                    } else {
                        Color.clear.frame(height: 8)
                    }
                    ScrollView {
                        LazyVStack(spacing: wide ? 10 : 12) {
                            ForEach(Self.sections) { section in
                                sectionHeader(section.titleKey, wide: wide)
                                ForEach(section.items) { item in
                                    if wide {
                                        wideRow(item, width: tableWidth)
                                    } else {
                                        narrowCard(item)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, wide ? 20 : 14)
                    }
                }
                .background(Color(.systemGroupedBackground))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(NSLocalizedString("和弦音与色彩音", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("完成", comment: "")) {
                        withAnimation(.easeInOut(duration: 0.22)) { isPresented = false }
                    }
                    .fontWeight(.semibold)
                }
            }
            // 左边缘向右滑 → 关闭（与「右边缘向左滑呼出」对称）
            .overlay(alignment: .leading) {
                EdgePanProxy(edge: .left) {
                    withAnimation(.easeInOut(duration: 0.22)) { isPresented = false }
                }
                .frame(width: 22)
                .allowsHitTesting(true)
            }
        }
    }

    // MARK: 宽屏表头
    private func headerRow(width: CGFloat) -> some View {
        let titles = [
            NSLocalizedString("和弦", comment: ""),
            NSLocalizedString("和弦音", comment: ""),
            NSLocalizedString("保守色彩音", comment: ""),
            NSLocalizedString("扩展色彩音", comment: ""),
            NSLocalizedString("推荐音阶", comment: "")
        ]
        return HStack(spacing: 0) {
            ForEach(Array(titles.enumerated()), id: \.offset) { idx, title in
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: width * columnFractions[idx], alignment: .leading)
            }
        }
    }

    private func sectionHeader(_ key: String, wide: Bool) -> some View {
        Text(NSLocalizedString(key, comment: ""))
            .font(wide ? .subheadline.weight(.bold) : .footnote.weight(.bold))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }

    // MARK: 宽屏：一行五列
    private func wideRow(_ item: CDItem, width: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Text(item.symbol)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(width: width * columnFractions[0], alignment: .leading)
            degreeText(item.chordDegrees, color: .primary, font: .caption.monospacedDigit())
                .frame(width: width * columnFractions[1], alignment: .leading)
            degreeText(item.colorDegrees(.conservative), color: toneGreen.opacity(0.78), font: .caption.monospacedDigit())
                .frame(width: width * columnFractions[2], alignment: .leading)
            degreeText(item.colorDegrees(.full), color: toneGreen, font: .caption.monospacedDigit())
                .frame(width: width * columnFractions[3], alignment: .leading)
            scaleColumn(item.scaleInfo, width: width * columnFractions[4])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // 音阶列：音阶名（专名）+ 其级数，两行紧凑排列
    private func scaleColumn(_ info: (name: String, degrees: [String]), width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(info.name)
                .font(.caption.weight(.semibold))
                .foregroundColor(scaleColor)
                .fixedSize(horizontal: false, vertical: true)
            Text(info.degrees.joined(separator: " "))
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: width, alignment: .leading)
    }

    // MARK: 窄屏（竖屏/紧凑）：一张卡片多行字段
    private func narrowCard(_ item: CDItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.symbol)
                .font(.headline.monospacedDigit())
                .fontWeight(.semibold)
            narrowField(NSLocalizedString("和弦音", comment: ""), item.chordDegrees, .primary)
            narrowField(NSLocalizedString("保守色彩音", comment: ""), item.colorDegrees(.conservative), toneGreen.opacity(0.78))
            narrowField(NSLocalizedString("扩展色彩音", comment: ""), item.colorDegrees(.full), toneGreen)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(NSLocalizedString("推荐音阶", comment: ""))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 78, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.scaleInfo.name)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(scaleColor)
                    Text(item.scaleInfo.degrees.joined(separator: " "))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func narrowField(_ label: String, _ degrees: [String], _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: 78, alignment: .leading)
            degreeText(degrees, color: color)
        }
    }

    private func degreeText(_ degrees: [String], color: Color, font: Font = .subheadline.monospacedDigit()) -> some View {
        Text(degrees.joined(separator: "  "))
            .font(font)
            .foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    // 与谱面色彩音图例一致的墨绿
    private var toneGreen: Color { Color(red: 0.055, green: 0.486, blue: 0.420) }
    // 音阶列用克制深青蓝，与墨绿色彩音区分
    private var scaleColor: Color { Color(red: 0.10, green: 0.28, blue: 0.46) }
}

// MARK: - 屏幕边缘手势代理（只识别从屏幕边缘起手的拖动，避免与五线谱 WebView 内部滚谱冲突）
struct EdgePanProxy: UIViewRepresentable {
    let edge: UIRectEdge
    let onTriggered: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        let gesture = UIScreenEdgePanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:))
        )
        gesture.edges = edge
        view.addGestureRecognizer(gesture)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onTriggered) }

    final class Coordinator: NSObject {
        private let onTriggered: () -> Void
        init(_ onTriggered: @escaping () -> Void) { self.onTriggered = onTriggered }
        @objc func handle(_ gesture: UIScreenEdgePanGestureRecognizer) {
            // 仅在手势从边缘识别成功的瞬间触发一次，页面转场交给 SwiftUI 动画
            if gesture.state == .began { onTriggered() }
        }
    }
}
