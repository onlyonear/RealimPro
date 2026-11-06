import SwiftUI

// MARK: - Trading / Settings Card（M2-10 UI 接入）
//
// Trading 设置面板：只保留"怎么对话"的参数，不包含 Start / Stop（传输控制统一到工具栏）。
// 内容：谁先、主动/被动（被动置灰预留）、三种回应方式单选、条件下拉（语法 / 乐手）、数拍。
// 会话运行中所有控件置灰，避免"改了设置不生效"的误解。
struct TradingSettingsCard: View {

    @ObservedObject var coordinator: TradingCoordinator
    @ObservedObject var iapManager: IAPManager
    @ObservedObject private var midiStatus = MIDIStatusMonitor.shared
    @Binding var showPaywall: Bool

    /// 运行中置灰
    private var locked: Bool { coordinator.isRunning }

    /// Grammar File 仅在 Use Grammar 模式可点（运行中额外置灰）
    private var grammarInteractive: Bool {
        !locked && (
            coordinator.responseMode == .useGrammar
            || (coordinator.uiMode == .passive &&
                (coordinator.passiveEngine == .grammar || coordinator.passiveEngine == .grammarAndTransform))
        )
    }
    /// Musician 仅在 Use Transform 模式可点（运行中额外置灰）
    private var musicianInteractive: Bool {
        !locked && (
            coordinator.responseMode == .useTransform
            || (coordinator.uiMode == .passive && coordinator.passiveEngine == .grammarAndTransform)
        )
    }

    /// Use Grammar 可选文法（顺序与 Grammar 组一致：3 基础 + 9 大师）
    private static let grammarAlgos: [ContentView.ImproAlgorithmType] = [
        .chordExercise, .colorTone, .Lick,
        .LeeMorgan, .charlieParker, .billEvans, .joePass,
        .johnColtrane, .milesDavis, .cannonballAdderley, .chetBaker, .redGarland
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // MARK: Who Goes First
            HStack {
                sectionHeader("Who Goes First")
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(midiStatus.statusText == "No MIDI device" ? Color.red : Color.green)
                        .frame(width: 7, height: 7)
                    Text(midiStatus.statusText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            Picker("", selection: $coordinator.userStarts) {
                Text("You").tag(true)
                Text("RealimPro").tag(false)
            }
            .pickerStyle(.segmented)
            .disabled(locked)

            // MARK: Trade Length（每段几小节，1/2/4/8/12/16，默认4）
            sectionHeader("Trade Length")
            Picker("", selection: $coordinator.barsPerTurn) {
                Text("1").tag(1)
                Text("2").tag(2)
                Text("4").tag(4)
                Text("8").tag(8)
                Text("12").tag(12)
                Text("16").tag(16)
            }
            .pickerStyle(.segmented)
            .disabled(locked)

            // MARK: Mode（Active / Passive 可切换）
            sectionHeader("Mode")
            HStack(spacing: 10) {
                Button { coordinator.uiMode = .active } label: {
                    modeChip("Active", active: coordinator.uiMode == .active)
                }
                Button {
                    coordinator.uiMode = .passive
                    // 一刀切：切到 Passive 时若不是 .useGrammar（本批唯一真响），全部落过去
                    if coordinator.responseMode != .useGrammar {
                        coordinator.responseMode = .useGrammar
                    }
                } label: {
                    modeChip("Passive", active: coordinator.uiMode == .passive)
                }
            }
            .disabled(locked)

            // MARK: Response（三选一；Passive 下只显示 Grammar 系，DL 与 Grammar&Transform 灰态）
            sectionHeader("Response")
            VStack(spacing: 8) {
                switch coordinator.uiMode {
                case .active:
                    responseRow(.modifyAndRectify, "Modify and Rectify")
                    responseRow(.useGrammar, "Use Grammar")
                    responseRow(.useTransform, "Use Transform")
                case .passive:
                    passiveEngineRow(.dl, "Use Deep Learning")
                    passiveEngineRow(.grammar, "Use Grammar")
                    passiveEngineRow(.grammarAndTransform, "Use Grammar & Transform")
                }
            }
            .disabled(locked)

            // MARK: 两个下拉常驻：能否选择由当前 Response 模式决定（见各自 .disabled）
            grammarMenu
            musicianMenu

            // MARK: Count In
            HStack {
                Text("Count In")
                    .font(.system(size: 14, weight: .medium))
                Spacer(minLength: 0)
                Toggle("", isOn: $coordinator.countIn)
                    .labelsHidden()
                    .disabled(locked)
            }
            .frame(height: 36)

            // MARK: Live Notation（逐小节实时上屏，默认关=段末一次性对齐 Java）
            HStack {
                Text("Live Notation")
                    .font(.system(size: 14, weight: .medium))
                Spacer(minLength: 0)
                Toggle("", isOn: $coordinator.liveNotation)
                    .labelsHidden()
                    .disabled(locked)
            }
            .frame(height: 36)
        }
        .padding(20)
    }

    // MARK: - 组件

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
    }

    private func modeChip(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(.system(size: 13, weight: active ? .semibold : .medium))
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(active ? Color.accentColor.opacity(0.14) : Color.gray.opacity(0.08))
            .foregroundColor(active ? .accentColor : .secondary)
            .clipShape(Capsule())
    }

    /// Passive 下第二批选项的固定灰态行（空心圆 + "Soon" 角标，不可选、无选中态）。
    private func passiveDisabledRow(title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "circle")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(.secondary)
            Spacer()
            Text("Soon")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(height: 36)
        .opacity(0.5)
    }

    private func passiveEngineRow(_ engine: TradingPassiveSession.PassiveEngine, _ title: String) -> some View {
        let selected = (coordinator.passiveEngine == engine)
        return Button {
            coordinator.passiveEngine = engine
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                Text(title)
                    .font(.system(size: 14, weight: selected ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundColor(selected ? .accentColor : .primary)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(selected ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(locked)
    }

    private func responseRow(_ mode: TradingResponseMode, _ title: String) -> some View {
        let selected = coordinator.responseMode == mode
        return Button {
            coordinator.responseMode = mode
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                Text(title)
                    .font(.system(size: 14, weight: selected ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundColor(selected ? .accentColor : .primary)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(selected ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: Grammar File 下拉（付费文法加锁）
    private var grammarMenu: some View {
        HStack {
            Text("Grammar File")
                .font(.system(size: 14, weight: .medium))
            Spacer(minLength: 0)
            Menu {
                ForEach(Self.grammarAlgos, id: \.self) { algo in
                    Button {
                        if algo.isPaidGrammar, !iapManager.isPurchased {
                            showPaywall = true
                        } else {
                            coordinator.grammarFile = algo.grammarFileName
                        }
                    } label: {
                        HStack {
                            Text(algo.rawValue)
                            if algo.isPaidGrammar, !iapManager.isPurchased {
                                Image(systemName: "lock.fill").font(.caption2)
                            }
                            if algo.grammarFileName == coordinator.grammarFile {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentGrammarLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Color.gray.opacity(0.12))
                .clipShape(Capsule())
            }
            .disabled(!grammarInteractive)
            .opacity(grammarInteractive ? 1 : 0.4)
        }
        .frame(height: 36)
    }

    private var currentGrammarLabel: String {
        Self.grammarAlgos.first { $0.grammarFileName == coordinator.grammarFile }?.rawValue
            ?? coordinator.grammarFile
    }

    // MARK: Musician 下拉（26 个，My 默认；本批不加付费锁）
    private var musicianMenu: some View {
        HStack {
            Text("Musician")
                .font(.system(size: 14, weight: .medium))
            Spacer(minLength: 0)
            Menu {
                ForEach(TransformMusicianCatalog.allMusicians, id: \.self) { id in
                    Button {
                        coordinator.transformMusician = (id == "My") ? nil : id
                    } label: {
                        HStack {
                            Text(TransformMusicianCatalog.displayName(id))
                            if currentMusicianId == id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(TransformMusicianCatalog.displayName(currentMusicianId))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Color.gray.opacity(0.12))
                .clipShape(Capsule())
            }
            .disabled(!musicianInteractive)
            .opacity(musicianInteractive ? 1 : 0.4)
        }
        .frame(height: 36)
    }

    private var currentMusicianId: String {
        coordinator.transformMusician ?? "My"
    }
}
