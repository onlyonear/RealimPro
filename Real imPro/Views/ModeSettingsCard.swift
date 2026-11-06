//
//  ModeSettingsCard.swift
//  RealimPro
//
//  顶部 Settings 按钮弹出的上下文设置卡片：随当前模式（Guide / Basic / Master / Learning）切换内容。
//  色彩宽度全绑全局 colorModeRaw；本文件只做 UI 与接线，不含任何生成逻辑。
//

import SwiftUI

// MARK: - MIDI 音名（本文件内使用）
func modeSettingsNoteName(of midi: Int) -> String {
    let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    return names[midi % 12] + "\(midi / 12 - 1)"
}

// MARK: - 顶层卡片
struct ModeSettingsCard: View {
    let group: ContentView.ImproAlgorithmGroup
    let options: [ContentView.ImproAlgorithmType]
    @Binding var selectedAlgorithm: ContentView.ImproAlgorithmType
    @Binding var guideDirection: Int
    @Binding var guideStartDegree: String
    @Binding var guideMaxDuration: Int
    @Binding var guideLow: Int
    @Binding var guideHigh: Int
    @Binding var pendingMasterAlgorithm: ContentView.ImproAlgorithmType?
    @Binding var showPaywall: Bool
    @ObservedObject var iapManager: IAPManager
    @ObservedObject var coordinator: TradingCoordinator
    // [旧码封存 P2.3b] overlay 自定义卡片无系统 dismiss，Done 改走 onClose：
    // @Environment(\.dismiss) private var dismiss
    let onClose: () -> Void

    // [P2.3b] Guide 的 Range 子页在卡片内联呈现（不全屏）
    @State private var showRange = false
    @State private var showHelp = false

    private var title: String {
        switch group {
        // [旧码封存 P2.3c] case .guide:    return "Guide Settings"   // 标题与顶栏模式名 GuideTone 对齐
        case .guide:    return "GuideTone Settings"
        case .grammar:  return "Grammar Settings"   // [P2 20261009] 原 Basic Grammar / Master Grammar 两卡合并
        case .learning: return "Learning Settings"
        case .trading:  return "Trading Settings"
        // [旧码封存 P2] case .basic:  return "Basic Grammar"
        // [旧码封存 P2] case .master: return "Master Grammar"
        }
    }

    // [P2.3b] 内联 Range 页时标题/卡片宽度随页变化
    private var navTitle: String {
        (group == .guide && showRange) ? "Choose Range" : title
    }
    private var cardWidth: CGFloat {
        (group == .guide && showRange) ? 480 : 400
    }

    // [旧码封存 P2.3b] 原外壳为系统 NavigationStack，由 ContentView .sheet(formSheet) 呈现，
    //   iPad 上卡宽/高固定偏大、内容两行却上下空旷：
    //   NavigationStack { Group { switch group {…} }.navigationTitle(title)
    //       .navigationBarTitleDisplayMode(.inline)
    //       .toolbar { ToolbarItem(placement:.confirmationAction){ Button("Done"){ dismiss() }… } } }
    var body: some View {
        VStack(spacing: 0) {
            // 自绘标题栏：标题居中、右上 Done；Range 内联页左上出现返回
            ZStack {
                Text(navTitle)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Button { showHelp = true } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 17))
                            .foregroundColor(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if group == .guide && showRange {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { showRange = false }
                        } label: {
                            Image(systemName: "chevron.backward")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                    Button("Done") { onClose() }.fontWeight(.semibold)
                }
            }
            .frame(height: 52)
            .padding(.horizontal, 20)
            .sheet(isPresented: $showHelp) {
                ModeHelpSheet(group: group)
            }

            Divider()

            Group {
                switch group {
                case .guide:
                    if showRange {
                        RangeKeyboardPage(low: $guideLow, high: $guideHigh,
                                          onDone: { withAnimation(.easeInOut(duration: 0.25)) { showRange = false } })
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        GuideSettingsCard(onChooseRange: {
                            withAnimation(.easeInOut(duration: 0.25)) { showRange = true }
                        },
                                          direction: $guideDirection,
                                          startDegree: $guideStartDegree,
                                          maxDuration: $guideMaxDuration,
                                          low: $guideLow, high: $guideHigh)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                case .grammar:
                    // [P2] 单一 Grammar 卡：3 基础 + 9 大师同一下拉，逐行按 isPaidGrammar 加锁
                    GrammarSettingsCard(options: options,
                                        selectedAlgorithm: $selectedAlgorithm,
                                        pendingMasterAlgorithm: $pendingMasterAlgorithm,
                                        showPaywall: $showPaywall,
                                        iapManager: iapManager)
                case .learning:
                    // [P1 补充 20261009] Model 选择带付费锁（同 Grammar 付费行/旧第二下拉）
                    LearningSettingsCard(selectedAlgorithm: $selectedAlgorithm,
                                         pendingMasterAlgorithm: $pendingMasterAlgorithm,
                                         showPaywall: $showPaywall,
                                         iapManager: iapManager)
                case .trading:
                    TradingSettingsCard(coordinator: coordinator,
                                       iapManager: iapManager,
                                       showPaywall: $showPaywall)
                }
                // [旧码封存 P2] case .basic, .master:
                //     GrammarSettingsCard(group: group, options: options,
                //                         selectedAlgorithm: $selectedAlgorithm,
                //                         pendingMasterAlgorithm: $pendingMasterAlgorithm,
                //                         showPaywall: $showPaywall, iapManager: iapManager)
            }
        }
        .frame(width: cardWidth)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.easeInOut(duration: 0.25), value: showRange)
    }
}

// MARK: - Allow Color Tones 行（圆点 + 宽度控件）
struct AllowColorRow: View {
    @Binding var isOn: Bool
    @Binding var widthRaw: String
    let widthInteractive: Bool
    // [P2.3] 色彩音「就地帮助」：点开纯色彩音说明页（showsLicensesButton:false，无左上致谢）
    @State private var showHelp = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isOn.toggle() }
            } label: {
                Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(isOn ? .accentColor : .secondary)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text("Allow Color Tones")
                .font(.system(size: 14, weight: .medium))
            // [P2.3] 问号帮助按钮：随时可点（不随色彩开关置灰）
            Button {
                showHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            ColorWidthMenu(raw: $widthRaw, interactive: widthInteractive)
        }
        .frame(height: 34)
        // [P2.3] 全屏呈现《Chord & Color Tones》纯色彩音表；右上 Done 关闭回到设置卡（ChordDictionaryView 自带 NavigationStack/完成/左缘关闭）
        .fullScreenCover(isPresented: $showHelp) {
            ChordDictionaryView(isPresented: $showHelp, showsLicensesButton: false)
        }
    }
}

// MARK: - Conserv / Ext 宽度 Menu
struct ColorWidthMenu: View {
    @Binding var raw: String
    let interactive: Bool

    var body: some View {
        Menu {
            ForEach(ColorPaletteMode.allCases, id: \.self) { mode in
                Button { raw = mode.rawValue } label: {
                    HStack {
                        Text(mode.label)
                        if raw == mode.rawValue { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                // [旧码封存 P2.3] 胶囊原用缩写 shortLabel（Conserv/Ext），三卡统一改完整词（rawValue/绑定键不变）：
                // Text((ColorPaletteMode(rawValue: raw) ?? .conservative).shortLabel)
                Text((ColorPaletteMode(rawValue: raw) ?? .conservative).label)   // [P2.3] 完整词 Conservative / Extended
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 10).frame(height: 28)
            .background(Color.gray.opacity(0.12)).clipShape(Capsule()).contentShape(Capsule())
        }
        .disabled(!interactive)
        .opacity(interactive ? 1 : 0.4)
    }
}

// MARK: - 通用「标题 + 胶囊 Menu」行
struct LabeledMenuRow: View {
    let title: String
    @Binding var selection: Int
    let options: [(label: String, value: Int)]

    private var currentLabel: String { options.first { $0.value == selection }?.label ?? "" }

    var body: some View {
        HStack {
            Text(title).font(.system(size: 14, weight: .medium))
            Spacer(minLength: 0)
            Menu {
                ForEach(options, id: \.value) { opt in
                    Button { selection = opt.value } label: {
                        HStack {
                            Text(opt.label)
                            if selection == opt.value { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Text(currentLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(Color.gray.opacity(0.12)).clipShape(Capsule())
            }
        }
        .frame(height: 36)
    }
}

// MARK: - Guide 设置卡
struct GuideSettingsCard: View {
    let onChooseRange: () -> Void   // [P2.3b] Range 子页改为卡片内联呈现（外壳 showRange）
    @Binding var direction: Int
    @Binding var startDegree: String
    @Binding var maxDuration: Int
    @Binding var low: Int
    @Binding var high: Int

    // [旧码封存 P1.5] 以下两项仅用于旧「宽度共管」逻辑，宽度现只管骨架：
    // @AppStorage("guideColorEnabled") private var embellishColor = false
    // @AppStorage("transformEnabled") private var transform = false
    @AppStorage("guideLineColorEnabled") private var lineColor = false
    // [P1.5] Guide 骨架宽度独立键
    @AppStorage("guideSkeletonWidthRaw") private var widthRaw = ColorPaletteMode.conservative.rawValue

    // [P1.5] 宽度可点：仅骨架色彩开（✝ 宽度已归调音台胶囊）
    // [旧码封存 P1.5] // 宽度可点：骨架色彩开 或（TRANSFORM 开且 ✝ 开）
    // [旧码封存 P1.5] private var widthInteractive: Bool { lineColor || (transform && embellishColor) }
    private var widthInteractive: Bool { lineColor }

    var body: some View {
        VStack(spacing: 12) {
            AllowColorRow(isOn: $lineColor, widthRaw: $widthRaw,
                          widthInteractive: widthInteractive)
            LabeledMenuRow(title: "Direction", selection: $direction, options: [
                (label: "No Preference", value: 0),
                (label: "Ascending", value: 1),
                (label: "Descending", value: -1)
            ])
            VStack(alignment: .leading, spacing: 6) {
                Text("Start on Scale Degree")
                    .font(.system(size: 14, weight: .medium))
                Picker("", selection: $startDegree) {
                    ForEach(["1", "3", "5", "7"], id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            LabeledMenuRow(title: "Max Note Duration", selection: $maxDuration, options: [
                (label: "No Preference", value: 0),
                (label: "Whole", value: 480),
                (label: "Half", value: 240),
                (label: "Quarter", value: 120)
            ])
            HStack {
                Text("Range").font(.system(size: 14, weight: .medium))
                Spacer(minLength: 0)
                // [旧码封存 P2.3b] 原为 NavigationLink push RangeKeyboardPage，现改卡片内联（onChooseRange）：
                // NavigationLink { RangeKeyboardPage(low: $low, high: $high) } label: { … } .buttonStyle(.plain)
                Button(action: onChooseRange) {
                    HStack(spacing: 4) {
                        Text("\(modeSettingsNoteName(of: low)) – \(modeSettingsNoteName(of: high))")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(Color.gray.opacity(0.12)).clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 36)
        }
        .padding(20)
    }
}

// MARK: - Range 键盘子页（[P2.3b] 纯 −/+ 输入、键盘只读；范围对齐原版 A2-C7、最小八度）
struct RangeKeyboardPage: View {
    @Binding var low: Int
    @Binding var high: Int
    let onDone: () -> Void

    // [P2.3b] 对齐 Java RangeChooser treble 档：可点范围 A2(45)-C7(96)、最小跨度 12（一个八度）
    private let loLimit = 45    // A2
    private let hiLimit = 96    // C7
    private let minSpan = 12
    private let displayStart = 45   // A2
    private let displayEnd = 96     // C7

    private func isWhite(_ midi: Int) -> Bool {
        [0, 2, 4, 5, 7, 9, 11].contains(midi % 12)
    }

    // 端点约束：low ∈ [A2, high-12]，high ∈ [low+12, C7]
    private func adjustLow(_ d: Int) {
        let n = low + d
        if n >= loLimit && n <= high - minSpan { low = n }
    }
    private func adjustHigh(_ d: Int) {
        let n = high + d
        if n <= hiLimit && n >= low + minSpan { high = n }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Use the + and − buttons to set your playing range.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 28) {
                endpointColumn(note: modeSettingsNoteName(of: low),
                               canDown: low > loLimit,
                               canUp: low < high - minSpan,
                               onDown: { adjustLow(-1) }, onUp: { adjustLow(1) })
                Text("–")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundColor(.secondary)
                endpointColumn(note: modeSettingsNoteName(of: high),
                               canDown: high > low + minSpan,
                               canUp: high < hiLimit,
                               onDown: { adjustHigh(-1) }, onUp: { adjustHigh(1) })
            }

            keyboard
                .frame(height: 190)

            HStack {
                Button {
                    low = 60; high = 79   // Reset 回默认 C4-G5（同时写持久化键）
                } label: {
                    Text("Reset").fontWeight(.medium)
                }
                Spacer()
                Button("Done") { onDone() }
                    .fontWeight(.semibold)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        // [旧码封存 P2.3b] 内联页标题由卡片外壳统一提供，移除：
        // .navigationTitle("Choose Range").navigationBarTitleDisplayMode(.inline)
    }

    private func endpointColumn(note: String, canDown: Bool, canUp: Bool,
                                onDown: @escaping () -> Void, onUp: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            RepeatingButton(icon: "plus.circle.fill", enabled: canUp, step: onUp)
            Text(note)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .frame(minWidth: 78)
            RepeatingButton(icon: "minus.circle.fill", enabled: canDown, step: onDown)
        }
    }

    private var keyboard: some View {
        GeometryReader { geo in
            let whites = (displayStart...displayEnd).filter { isWhite($0) }
            let whiteWidth = geo.size.width / CGFloat(whites.count)
            ZStack(alignment: .topLeading) {
                HStack(spacing: 1) {
                    ForEach(whites, id: \.self) { midi in
                        keyView(midi, isBlack: false)
                            .frame(width: whiteWidth, height: geo.size.height)
                    }
                }
                ForEach((displayStart...displayEnd).filter { !isWhite($0) }, id: \.self) { midi in
                    let preceding = CGFloat(whites.filter { $0 < midi }.count)
                    keyView(midi, isBlack: true)
                        .frame(width: whiteWidth * 0.62, height: geo.size.height * 0.62)
                        .offset(x: preceding * whiteWidth + whiteWidth - whiteWidth * 0.31)
                }
            }
        }
    }

    // [P2.3b] 只读琴键：不响应触摸；区间高亮、端点实心、C 键标音名
    private func keyView(_ midi: Int, isBlack: Bool) -> some View {
        let inRange = midi >= low && midi <= high
        let isEnd = midi == low || midi == high
        return Rectangle()
            .fill(inRange
                  ? (isEnd ? Color.accentColor
                           : Color.accentColor.opacity(isBlack ? 0.8 : 0.32))
                  : (isBlack ? Color.black : Color.white))
            .border(Color.gray.opacity(0.3), width: 0.5)
            .overlay(alignment: .bottom) {
                if !isBlack && midi % 12 == 0 {   // 标记 C3/C4/C5/C6/C7
                    Text(modeSettingsNoteName(of: midi))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(inRange ? Color.white : Color.secondary)
                        .padding(.bottom, 2)
                        .allowsHitTesting(false)
                }
            }
            .allowsHitTesting(false)   // 整个键盘只读
    }
}

// [P2.3b] 长按连发按钮：点按一次 step；按住 0.35s 后每 0.09s 连发；disabled 置灰；热区 44
struct RepeatingButton: View {
    let icon: String
    let enabled: Bool
    let step: () -> Void
    @State private var timer: Timer?
    @State private var didLongPress = false

    var body: some View {
        Button {
            if !didLongPress { step() }   // 长按抬手时不再补一次单点
        } label: {
            Image(systemName: icon)
                .font(.system(size: 30))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .onLongPressGesture(minimumDuration: 0.35, maximumDistance: .infinity, perform: {
            didLongPress = true
            start()
        }, onPressingChanged: { pressing in
            if pressing == false {
                stop()
                DispatchQueue.main.async { didLongPress = false }
            }
        })
        .onDisappear { stop() }
    }

    private func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { _ in step() }
    }
    private func stop() { timer?.invalidate(); timer = nil }
}

/*
 [旧码封存 P2.3b] 旧 RangeKeyboardPage：点键输入（先 low 后 high 轮换）、窗口 C2(36)-C7(96) 比原版宽、
   仅校验跨度<12 无 A2/C7 硬边界、无 C 标记、靠 NavigationLink push + @Environment dismiss。完整保留：

// MARK: - Range 键盘子页
struct RangeKeyboardPage_OLD_P23B: View {
    @Binding var low: Int
    @Binding var high: Int
    @State private var workingLow: Int?
    @State private var workingHigh: Int?
    @State private var nextIsLow = true
    @State private var invalid = false
    @Environment(\.dismiss) private var dismiss

    private let displayStart = 36   // C2
    private let displayEnd = 96     // C7

    private var instruction: String {
        if invalid { return "Minimum span is one octave. Please reselect." }
        if workingLow == nil { return "Tap the lowest note of your range." }
        return "Now tap the highest note of your range."
    }

    private func isWhite(_ midi: Int) -> Bool {
        [0, 2, 4, 5, 7, 9, 11].contains(midi % 12)
    }

    private func handleTap(_ midi: Int) {
        invalid = false
        if nextIsLow {
            workingLow = midi
            workingHigh = nil
            nextIsLow = false
        } else {
            workingHigh = midi
            nextIsLow = true
            guard let l = workingLow, let h = workingHigh else { return }
            let a = min(l, h), b = max(l, h)
            if b - a < 12 {
                invalid = true
            } else {
                low = a
                high = b
            }
        }
    }

    private func inWorkingRange(_ midi: Int) -> Bool {
        let l = workingLow ?? low
        let h = workingHigh ?? high
        return midi >= l && midi <= h
    }

    var body: some View {
        VStack(spacing: 18) {
            Text(instruction)
                .font(.system(size: 13))
                .foregroundColor(invalid ? .red : .secondary)
                .multilineTextAlignment(.center)
            Text("\(modeSettingsNoteName(of: workingLow ?? low)) – \(modeSettingsNoteName(of: workingHigh ?? high))")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            keyboard
                .frame(height: 190)
            HStack {
                Button {
                    workingLow = 60
                    workingHigh = 79
                    invalid = false
                    low = 60
                    high = 79
                } label: {
                    Text("Reset").fontWeight(.medium)
                }
                Spacer()
                Button {
                    guard let l = workingLow, let h = workingHigh, !invalid else { return }
                    low = min(l, h)
                    high = max(l, h)
                    dismiss()
                } label: {
                    Text("Done").fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .disabled(workingLow == nil || workingHigh == nil || invalid)
            }
        }
        .padding(20)
        .navigationTitle("Choose Range")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var keyboard: some View {
        GeometryReader { geo in
            let whites = (displayStart...displayEnd).filter { isWhite($0) }
            let whiteWidth = geo.size.width / CGFloat(whites.count)
            ZStack(alignment: .topLeading) {
                HStack(spacing: 1) {
                    ForEach(whites, id: \.self) { midi in
                        keyButton(midi, isBlack: false)
                            .frame(width: whiteWidth, height: geo.size.height)
                    }
                }
                ForEach((displayStart...displayEnd).filter { !isWhite($0) }, id: \.self) { midi in
                    let preceding = CGFloat(whites.filter { $0 < midi }.count)
                    keyButton(midi, isBlack: true)
                        .frame(width: whiteWidth * 0.62, height: geo.size.height * 0.62)
                        .offset(x: preceding * whiteWidth + whiteWidth - whiteWidth * 0.31)
                }
            }
        }
    }

    private func keyButton(_ midi: Int, isBlack: Bool) -> some View {
        Button {
            handleTap(midi)
        } label: {
            Rectangle()
                .fill(inWorkingRange(midi)
                      ? Color.accentColor.opacity(isBlack ? 0.85 : 0.35)
                      : (isBlack ? Color.black : Color.white))
                .border(Color.gray.opacity(0.3), width: 0.5)
        }
        .buttonStyle(.plain)
    }
}
*/


// MARK: - Grammar 设置卡（[P2] 合并 Basic/Master；3 基础免费 + 9 大师付费，逐行加锁）
// [旧码封存 P2] // MARK: - Basic / Master Grammar 设置卡
struct GrammarSettingsCard: View {
    // [旧码封存 P2] 合并前按组区分 Basic/Master：let group: ContentView.ImproAlgorithmGroup
    let options: [ContentView.ImproAlgorithmType]
    @Binding var selectedAlgorithm: ContentView.ImproAlgorithmType
    @Binding var pendingMasterAlgorithm: ContentView.ImproAlgorithmType?
    @Binding var showPaywall: Bool
    @ObservedObject var iapManager: IAPManager

    @AppStorage("grammarColorEnabled") private var grammarColor = false
    // [P1.5] Grammar 源宽度独立键（Basic/Master 共用）
    // [旧码封存 P1.5] @AppStorage("colorModeRaw") private var widthRaw = ColorPaletteMode.conservative.rawValue
    @AppStorage("grammarWidthRaw") private var widthRaw = ColorPaletteMode.conservative.rawValue

    // [旧码封存 P2.3] 原 Grammar 卡为 VStack(spacing:16){ 两行 }.padding(20) 顶部排列，大卡内垂直空旷；标签原为 Text("Grammar")：
    // var body: some View { VStack(spacing: 16) { AllowColorRow(…); HStack { Text("Grammar") … Menu … }.frame(height:36) }.padding(20) }
    // [旧码封存 P2.3b] P2.3 备选大卡布局（formSheet 撑满、Spacer 上下居中、blurb 沉底、仅 .padding(.top,20) 丢水平边距）：
    // var body: some View { VStack(spacing:0){ Spacer(minLength:16); VStack(spacing:16){ AllowColorRow;
    //     HStack{ Text("Grammar File") … Menu … }.frame(height:36) }; Spacer(minLength:16);
    //     Text(ModeBlurb…).padding(.horizontal,20).padding(.bottom,20) }
    //     .frame(maxWidth:.infinity, maxHeight:.infinity).padding(.top,20) }
    // [P2.3b] 紧凑顺排：四边 padding(20)、去 Spacer/撑满；第②行 leading 32 对齐 Allow 的 A；blurb 紧跟
    var body: some View {
        VStack(spacing: 16) {
            AllowColorRow(isOn: $grammarColor, widthRaw: $widthRaw,
                          widthInteractive: grammarColor)
            HStack {
                Text("Grammar File").font(.system(size: 14, weight: .medium))
                Spacer(minLength: 0)
                Menu {
                    ForEach(options, id: \.self) { algo in
                        Button {
                            // [P2] 逐行付费判定：该行是大师文法且未购 → 挂 pending + 弹付费墙；基础语法/已购正常切换
                            // [旧码封存 P2] if group == .master && !iapManager.isPurchased {
                            if algo.isPaidGrammar && !iapManager.isPurchased {
                                pendingMasterAlgorithm = algo
                                showPaywall = true
                            } else {
                                selectedAlgorithm = algo
                            }
                        } label: {
                            HStack {
                                Text(algo.rawValue)
                                // [旧码封存 P2] if group == .master && !iapManager.isPurchased {
                                if algo.isPaidGrammar && !iapManager.isPurchased {
                                    Image(systemName: "lock.fill").font(.caption2)
                                }
                                if algo == selectedAlgorithm {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedAlgorithm.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(Color.gray.opacity(0.12)).clipShape(Capsule())
                }
            }
            .frame(height: 36)
            .padding(.leading, 32)   // [P2.3b] 圆圈24+间距8：与 Allow Color Tones 的 A 对齐
            Text(ModeBlurb.text(for: selectedAlgorithm))
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .padding(20)
    }
}

// MARK: - Learning 设置卡
struct LearningSettingsCard: View {
    @Binding var selectedAlgorithm: ContentView.ImproAlgorithmType
    // [P1 补充 20261009] Model 付费锁：与 GrammarSettingsCard 同构（未购点选→pending+paywall，选项旁 lock.fill）
    @Binding var pendingMasterAlgorithm: ContentView.ImproAlgorithmType?
    @Binding var showPaywall: Bool
    @ObservedObject var iapManager: IAPManager

    @AppStorage("lstmColorEnabled") private var lstmColor = false
    // [P1.5] Learning 源宽度独立键
    // [旧码封存 P1.5] @AppStorage("colorModeRaw") private var widthRaw = ColorPaletteMode.conservative.rawValue
    @AppStorage("learningWidthRaw") private var widthRaw = ColorPaletteMode.conservative.rawValue

    // Learning 仅两个模型，顺序承接旧第二下拉
    private let modelOptions: [ContentView.ImproAlgorithmType] = [.combination, .greatMoments]

    // [旧码封存 P2.3] 原 Learning 卡为 VStack(spacing:20){ 两行 }.padding(20) 顶部排列，大卡内垂直空旷：
    // var body: some View { VStack(spacing: 20) { AllowColorRow(…); HStack { Text("Model") … Menu … }.frame(height:36) }.padding(20) }
    // [旧码封存 P2.3b] P2.3 备选大卡布局（formSheet 撑满、Spacer 上下居中、blurb 沉底、仅 .padding(.top,20) 丢水平边距）：
    // var body: some View { VStack(spacing:0){ Spacer(minLength:16); VStack(spacing:16){ AllowColorRow;
    //     HStack{ Text("Model") … Menu … }.frame(height:36) }; Spacer(minLength:16);
    //     Text(ModeBlurb…).padding(.horizontal,20).padding(.bottom,20) }
    //     .frame(maxWidth:.infinity, maxHeight:.infinity).padding(.top,20) }
    // [P2.3b] 紧凑顺排：四边 padding(20)、去 Spacer/撑满；第②行 leading 32 对齐 Allow 的 A；blurb 紧跟
    var body: some View {
        VStack(spacing: 16) {
            AllowColorRow(isOn: $lstmColor, widthRaw: $widthRaw,
                          widthInteractive: lstmColor)
            HStack {
                Text("Model")
                    .font(.system(size: 14, weight: .medium))
                Spacer(minLength: 0)
                Menu {
                    ForEach(modelOptions, id: \.self) { algo in
                        Button {
                            if !iapManager.isPurchased {
                                // 未购：不切换，挂 pending 并弹付费墙（与 Master 卡/旧下拉一致）
                                pendingMasterAlgorithm = algo
                                showPaywall = true
                            } else {
                                selectedAlgorithm = algo
                            }
                        } label: {
                            HStack {
                                Text(algo.rawValue)
                                if !iapManager.isPurchased {
                                    Image(systemName: "lock.fill").font(.caption2)
                                }
                                if algo == selectedAlgorithm && iapManager.isPurchased {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedAlgorithm.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(Color.gray.opacity(0.12)).clipShape(Capsule())
                }
            }
            .frame(height: 36)
            .padding(.leading, 32)   // [P2.3b] 圆圈24+间距8：与 Allow Color Tones 的 A 对齐
            Text(ModeBlurb.text(for: selectedAlgorithm))
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .padding(20)
    }
}

// MARK: - [P2.3] 语法/模型底部静态说明（ModeBlurb）
// 只讲命名 / 来源、零输出承诺；静态映射、不读取引擎。穷尽 switch（无 default）：未来 ImproAlgorithmType 新增 case 时编译器强制在此补文案。
enum ModeBlurb {
    static func text(for algo: ContentView.ImproAlgorithmType) -> String {
        switch algo {
        case .chordExercise:       return "Chord tones with approach notes"
        case .colorTone:           return "Chord tones with selected color tones"
        case .Lick:                return "A set of classic bebop licks"
        case .LeeMorgan:           return "Grammar named after Lee Morgan"
        case .charlieParker:       return "Grammar named after Charlie Parker"
        case .billEvans:           return "Grammar named after Bill Evans"
        case .joePass:             return "Grammar named after Joe Pass"
        case .cannonballAdderley:  return "Grammar named after Cannonball Adderley"
        case .chetBaker:          return "Grammar named after Chet Baker"
        case .johnColtrane:       return "Grammar named after John Coltrane"
        case .milesDavis:         return "Grammar named after Miles Davis"
        case .redGarland:         return "Grammar named after Red Garland"
        case .combination:        return "A neural model trained on many jazz masters"
        case .greatMoments:       return "A neural model trained on selected jazz solos"
        }
    }
}

// MARK: - 链路帮助说明 Sheet
struct ModeHelpSheet: View {
    let group: ContentView.ImproAlgorithmGroup
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(generateLogicText)
                        .font(.system(size: 14))
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    ForEach(optionRows, id: \.title) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title)
                                .font(.system(size: 14, weight: .semibold))
                            Text(row.desc)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle(helpTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var helpTitle: String {
        switch group {
        case .guide:    return "About GuideTone"
        case .grammar:  return "About Grammar"
        case .learning: return "About Learning"
        case .trading:  return "About Trading"
        default:        return "About"
        }
    }

    private var generateLogicText: String {
        switch group {
        case .guide:
            return "GuideTone builds a smooth melody by connecting chord guide tones (3rds and 7ths) with stepwise motion. It creates a logical, voice-leading skeleton that sounds like a natural jazz line."
        case .grammar:
            return "Grammar generates solos using rule-based phrase patterns, similar to how sentences are constructed from grammar rules. Choose a grammar file to match a style or player."
        case .learning:
            return "Learning uses a neural network trained on thousands of jazz solos. Choose a model to generate phrases in a particular stylistic direction."
        case .trading:
            return "Trading is call-and-response improvisation: you play a phrase, the app responds. Active mode alternates turns; Passive mode lets the app generate continuous solos."
        default:
            return ""
        }
    }

    private var optionRows: [(title: String, desc: String)] {
        switch group {
        case .guide:
            return [
                ("Allow Color Tones", "Add upper extensions (9ths, 11ths, 13ths) for richer sound. Conservative uses them sparingly; Extravagant uses more."),
                ("Direction", "Preferred melodic direction: ascending, descending, or no preference."),
                ("Start on Scale Degree", "Which chord tone the first note lands on: 1 (root), 3 (third), 5 (fifth), or 7 (seventh)."),
                ("Max Note Duration", "Longest allowed note value. Prevents the melody from holding notes too long."),
                ("Range", "The note range your instrument plays in. Keep it comfortable for your sax or piano.")
            ]
        case .grammar:
            return [
                ("Allow Color Tones", "Add upper extensions for richer sound. Conservative = sparse; Extravagant = dense."),
                ("Grammar File", "Which grammar pattern set to use. Chord+App is the basic set; named artists (e.g. Charlie Parker) are premium styles.")
            ]
        case .learning:
            return [
                ("Allow Color Tones", "Add upper extensions for richer sound. Conservative = sparse; Extravagant = dense."),
                ("Model", "Which neural network model to use. Combination blends multiple styles; Great Moments emphasizes classic bebop lines.")
            ]
        case .trading:
            return [
                ("Who Goes First", "Whether you or the app plays the first phrase."),
                ("Trade Length", "How many bars each person plays per turn."),
                ("Mode", "Active = you and app alternate. Passive = app generates continuously, you listen along."),
                ("Response (Active)", "How the app responds: Modify and Rectify alters your line, Use Grammar generates from rules, Use Transform applies style changes."),
                ("Response (Passive)", "Use Deep Learning = neural net solo; Use Grammar = rule-based solo; Use Grammar & Transform = rules plus style overlay."),
                ("Grammar File", "Which pattern set is used when a Grammar response is selected."),
                ("Musician", "Which player style the Transform engine emulates."),
                ("Count In", "Play a 4-bar count-in before trading starts."),
                ("Live Notation", "Show the generated solo on staff notation in real time.")
            ]
        default:
            return []
        }
    }
}
