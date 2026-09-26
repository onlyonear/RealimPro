import SwiftUI

enum MixerDisplayMode: String, CaseIterable {
    case swing  = "Swing"
    case ballad = "Ballad"
    case blues  = "Shuffle"
    case afro   = "Afro"
    //case bebop  = "Bebop"
    case bossa  = "Bossa"
    case waltz  = "Waltz"
    case latin  = "Latin"
}

// 钢琴和声(voicing)档位：Simple=现有固定 shell(3+7+9) / Full=对齐原版的完整规则 voicing(词库模板+声部连接+兜底)
// 与 ChordPatternExtractor 共用同一持久化键 "pianoVoicingModeRaw"
enum PianoVoicingMode: String, CaseIterable {
    case simple
    case full
    var label: String {
        switch self {
        case .simple: return "Simple (Shell)"
        case .full:   return "Full Voicing"
        }
    }
    var shortLabel: String {
        switch self {
        case .simple: return "Simple"
        case .full:   return "Full"
        }
    }
}

// MARK: - 乐队混音总控台 (Apple Pro 高级简约版 + 折叠机制)
struct BandMixerView: View {
    @Binding var saxVolume: Float
    @Binding var pianoVolume: Float
    @Binding var bassVolume: Float
    @Binding var drumVolume: Float
    @Binding var saxMuted: Bool
    @Binding var pianoMuted: Bool
    @Binding var bassMuted: Bool
    @Binding var drumMuted: Bool
    @Binding var selectedStyle: MixerDisplayMode
    @Binding var isExpanded: Bool
    // [Hunk10] Transform 加花总开关 + 所选乐手（由 ContentView @AppStorage 绑定，guide/grammar 两链共用）
    @Binding var enableTransform: Bool
    @Binding var selectedTransformMusician: String
    // [Guide Color 圆点 20260914] Guide 整流色彩档开关；
    // [方案21 20260915] isColorDotEligible=当前组是否允许 Color 圆点（恢复为仅 Guide；Basic/Master 置灰）；
    //   COLOR 下拉本身始终可点、作用不变。原 melody 用的 embellishLocked 已随 Melody 组下线删除。
    @Binding var guideColorEnabled: Bool
    let isColorDotEligible: Bool
    let isPlaying: Bool
    // D4：色彩音池档位（与 ContentView 生成处共用同一持久化键）
    // 注：整流(Rectify)已固定为全拍对齐，不再在调音台显示；逻辑仍保留在 GrammarLickGlue/LightPostProcessor
    @AppStorage("colorModeRaw") private var colorModeRaw: String = ColorPaletteMode.conservative.rawValue
    // Q4 八度放置盲听档【2026-09-06 定稿封存】：曾提供 Smooth(就近上一音) / Leaps(锚定根音=对齐原版) 两档 A/B，
    // 真机盲听后 Smooth 听感更佳、放弃 Leaps；生成链已在 ContentView 固定 .smooth。下方状态与 OCTAVE Menu 一并注释保留，
    // 日后想再对比：取消本处与 Menu 的注释，并恢复 ContentView 的 octaveModeRaw/@AppStorage、octaveRaw 传参与注入即可。
    // @AppStorage("octaveModeRaw") private var octaveModeRaw: String = OctavePlacementMode.smooth.rawValue
    // 整曲化已定稿：原临时盲听档 @AppStorage("grammarSegmentModeRaw") 已随 PHRASE Menu 一并移除，
    // 生成链固定 wholeSong；GrammarStrategy.GrammarSegmentMode 枚举保留作内部回退，UI 不再暴露。
    // 钢琴和声档位菜单已下线、系统默认 Full；下面这行封存，恢复 VOICING Menu 时启用。
    // @AppStorage("pianoVoicingModeRaw") private var pianoVoicingModeRaw: String = PianoVoicingMode.full.rawValue
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                VStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: 36, height: 5)
                        .padding(.top, 8)
                        .padding(.bottom, isExpanded ? 12 : 8)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                HStack(spacing: 16) {
                    HStack(spacing: 16) {
                        MixerTrackView(title: "SAX", icon: "wind", volume: $saxVolume, isMuted: $saxMuted)
                        MixerTrackView(title: "PIANO", icon: "pianokeys", volume: $pianoVolume, isMuted: $pianoMuted)
                        MixerTrackView(title: "BASS", icon: "guitars", volume: $bassVolume, isMuted: $bassMuted)
                        MixerTrackView(title: "DRUM", icon: "circle.grid.cross", volume: $drumVolume, isMuted: $drumMuted)
                    }
                    .padding(.trailing, 4)
                    
                    Divider()
                        .frame(height: 60)
                        .background(Color.gray.opacity(0.3))
                    
                    VStack(spacing: 10) {
                        // [布局调整 2026-09-14] 删除顶部 dial.low 旋钮图标，改为与 COLOR/TRANSFORM 同风格的 STYLE 小标签（9pt bold rounded secondary）
                        Text("STYLE")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)

                        Menu {
                            ForEach(MixerDisplayMode.allCases, id: \.self) { style in
                                Button {
                                    selectedStyle = style
                                } label: {
                                    Text(style.rawValue.capitalized)
                                    if selectedStyle == style {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(selectedStyle.rawValue.uppercased())
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)

                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity)   // 撑满外层 110 列，与 COLOR、乐手菜单等宽等高
                            .frame(height: 30)   // [布局调整 2026-09-14] 44→30，与 COLOR、乐手菜单等高
                            .background(Color.gray.opacity(0.12))
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                        }

                        // 整流(Rectify)已固定为"全拍对齐原版"，调音台不再显示切换入口。
                        // 三档逻辑(Off/Strong Beats/All Beats)完整保留在 GrammarLickGlue.swift，
                        // 日后调试：改 ContentView 里 grammarStrategy.rectifyMode 的赋值即可。

                        // 色彩音池档位：Conservative=基础色彩 / Extended=扩展(全量延伸变化音)，用于 A/B 听感对比
                        // [Guide Color 圆点 20260914] COLOR 标签前内嵌圆点：仅 Guide 且 TRANSFORM 点亮时可点，
                        // 其余置灰(.disabled+opacity0.4)。圆点不新增可见文案（COLOR 沿用现有英文字面量），下拉始终可点。
                        HStack(spacing: 4) {
                            Button {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    guideColorEnabled.toggle()
                                }
                            } label: {
                                Image(systemName: guideColorEnabled ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(guideColorEnabled ? .accentColor : .secondary)
                                    .frame(width: 18, height: 18)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            // [方案21] 可用=Guide 且 TRANSFORM 点亮（恢复 guide-only）
                            .disabled(!(isColorDotEligible && enableTransform))
                            .opacity((isColorDotEligible && enableTransform) ? 1 : 0.4)
                            Text("COLOR")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                            Spacer(minLength: 0)
                        }
                        .frame(height: 14)
                        Menu {
                            ForEach(ColorPaletteMode.allCases, id: \.self) { mode in
                                Button {
                                    colorModeRaw = mode.rawValue
                                } label: {
                                    Text(mode.label)
                                    if colorModeRaw == mode.rawValue {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text((ColorPaletteMode(rawValue: colorModeRaw) ?? .conservative).shortLabel.uppercased())
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity)   // P2c：固定宽度=撑满外层80列，与上方伴奏模式菜单等宽、不随 Conserv/Ext 长短变化
                            .frame(height: 30)
                            .background(Color.gray.opacity(0.12))
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                        }

                        // [Hunk10] Transform 加花：圆点总开关（circle / largecircle.fill.circle）。
                        // [布局调整 2026-09-14] 乐手 Menu 改为常驻：圆点关时置灰(.disabled+opacity0.4)不可选，点亮后才可点。默认关（ContentView @AppStorage=false）。
                        HStack(spacing: 4) {
                            Button {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    enableTransform.toggle()
                                }
                            } label: {
                                Image(systemName: enableTransform ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(enableTransform ? .accentColor : .secondary)
                                    .frame(width: 20, height: 20)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            // [方案21] 原 embellishLocked 置灰已删：TRANSFORM 圆点恒可点（回到 T2 定稿态）
                            Text(NSLocalizedString("变换加花", comment: "").uppercased())
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .foregroundColor(.secondary)
                            Spacer(minLength: 0)
                        }
                        .frame(height: 18)

                        // [布局调整 2026-09-14] 乐手 Menu 常驻（不再 if enableTransform）：
                        // 圆点关时 .disabled(true).opacity(0.4) 置灰不可选，点亮后才可点；右栏加宽到 110 后保持 10pt 清晰（minScale 0.85，不再压到 0.5）。
                        Menu {
                            ForEach(TransformMusicianCatalog.allMusicians, id: \.self) { m in
                                Button {
                                    selectedTransformMusician = m
                                } label: {
                                    HStack {
                                        Text(TransformMusicianCatalog.displayName(m))
                                        if selectedTransformMusician == m { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(TransformMusicianCatalog.shortLabel(selectedTransformMusician).uppercased())
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity)   // 撑满 110 列，与 STYLE/COLOR 胶囊等宽等高
                            .frame(height: 30)
                            .background(Color.gray.opacity(0.12))
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                        }
                        .disabled(!enableTransform)   // [方案21] 圆点关置灰（去掉 embellishLocked）
                        .opacity(enableTransform ? 1 : 0.4)

                        // Q4 八度放置盲听档【2026-09-06 定稿封存，UI 不再显示】：
                        // 曾提供 SMOOTH(贴着上一音就近选八度,平滑/小跳) 与 LEAPS(锚定和弦根音=对齐原版,大跳/有棱角)；
                        // 真机盲听后 Smooth 听感更佳、放弃 Leaps，生成链固定 .smooth（见 ContentView/GrammarNoteConverter 的 Q4 注释）。
                        // 以下 Menu 完整保留，恢复 A/B 时连同上方 @AppStorage(octaveModeRaw) 与 ContentView 注入一起取消注释即可。
                        // Text("OCTAVE")
                        //     .font(.system(size: 8, weight: .bold, design: .rounded))
                        //     .foregroundColor(.secondary)
                        // Menu {
                        //     ForEach(OctavePlacementMode.allCases, id: \.self) { mode in
                        //         Button {
                        //             octaveModeRaw = mode.rawValue
                        //         } label: {
                        //             Text(mode.label)
                        //             if octaveModeRaw == mode.rawValue {
                        //                 Image(systemName: "checkmark")
                        //             }
                        //         }
                        //     }
                        // } label: {
                        //     HStack(spacing: 4) {
                        //         Text((OctavePlacementMode(rawValue: octaveModeRaw) ?? .smooth).shortLabel.uppercased())
                        //             .font(.system(size: 10, weight: .bold, design: .rounded))
                        //             .lineLimit(1)
                        //             .minimumScaleFactor(0.7)
                        //         Image(systemName: "chevron.up.chevron.down")
                        //             .font(.system(size: 8, weight: .bold))
                        //     }
                        //     .foregroundColor(.primary)
                        //     .padding(.horizontal, 8)
                        //     .frame(maxWidth: .infinity)
                        //     .frame(height: 30)
                        //     .background(Color.gray.opacity(0.12))
                        //     .clipShape(Capsule())
                        //     .contentShape(Capsule())
                        // }

                        // 整曲化已定稿（2026-09-05）：临时 PHRASE 盲听档（Whole/Segmented）已移除，
                        // 生成链固定 wholeSong（整曲一次 run）。如需临时 A/B，可在 GrammarStrategy 改 GrammarSegmentMode。

                        // 钢琴和声档位 VOICING 菜单已下线（2026-09-05 听感确认后默认 Full）。
                        // Simple(固定 shell) 路径在 ChordPatternExtractor 内封存保留，PianoVoicingMode 枚举保留；
                        // 日后调试若要 A/B，可恢复此 Menu，或直接在 UserDefaults 写 "pianoVoicingModeRaw"="simple"。
                    }
                    .frame(width: 110)   // [布局调整 2026-09-14] 右栏 80→110，左四轨 slider 自然压窄（静音钮 44 不变）
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .clipped()
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 15, x: 0, y: 8)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
    }
}

// MARK: - 🎚️ 单个极简轨道组件
struct MixerTrackView: View {
    let title: String
    let icon: String
    @Binding var volume: Float
    @Binding var isMuted: Bool
    
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .kerning(0.8)
            }
            .foregroundColor(isMuted ? .gray.opacity(0.6) : .secondary)
            
            Slider(value: $volume, in: 0...1)
                .tint(isMuted ? .gray.opacity(0.2) : .primary)
                .disabled(isMuted)
                .animation(.easeInOut(duration: 0.2), value: isMuted)
            
            Button(action: {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isMuted.toggle()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(isMuted ? Color.red.opacity(0.15) : Color.gray.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isMuted ? .red : .primary.opacity(0.8))
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
        }
    }
}
