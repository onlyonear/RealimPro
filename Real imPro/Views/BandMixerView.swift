import SwiftUI

// [旧码封存 P3-b 20261011] P3-a 的 DEBUG 临时项已转正（Release 也编译）并并入正式 Swing 子菜单；
//   原枚举为扁平 7 个手写 case，外加临时调试项，且无 displayName / 分组：
//     #if DEBUG
//     // [P3-a 临时] 真机直听 Java swing.sty；rawValue 即 styleId，经 selectedStyle.rawValue 透传到 Hunk B 前置分支。
//     case stySwing = "sty:swing"
//     #endif
//   下方手写 7 个 case（swing/ballad/blues/afro/bossa/waltz/latin）的 rawValue 严格保持不变
//   （AccompanimentGenerator 靠 rawValue 小写匹配手写风格）；「Simple X」改名只体现在 displayName。
enum MixerDisplayMode: String, CaseIterable {
    // —— 手写风格（rawValue 即生成器识别的 styleId，严禁修改；显示名走 displayName）——
    // [P3-e] 真机听感下架，旧码封存（AccompanimentGenerator 内对应字符串分支保留为“不可达存档”，
    //        导入旧曲经 matchStyleMode 自动映射同族 Java 版，不会再走到这些手写分支）：
    // case swing  = "Swing"     // 原 Simple Swing（默认风格已迁移到 .stySwing，见 ContentView）
    // case ballad = "Ballad"    // 原 Simple Ballad
    // case waltz  = "Waltz"     // 原 Simple Waltz
    // case latin  = "Latin"     // 原 Simple Latin
    // [P3-f] 下架最后三个手写（Simple Shuffle/Afro/Bossa），菜单统一为 Java .sty、彻底消除响度差异；
    //        旧码封存（AccompanimentGenerator/JazzMidiPlayer 内字符串分支保留为不可达存档，导入经 matchStyleMode 映射同族 Java）：
    // case blues  = "Shuffle"   // 原 Simple Shuffle
    // case afro   = "Afro"      // 原 Simple Afro
    //case bebop  = "Bebop"
    // case bossa  = "Bossa"     // 原 Simple Bossa

    // —— [P3-b] Java .sty 伴奏型（rawValue = "sty:"+资源名，经前置分支交 StyleEngine）——
    // Swing 11
    case stySwing          = "sty:swing"
    case stySwingBackbeat  = "sty:swing-backbeat"
    case stySwingSquare    = "sty:swing-square-comp"
    case stySwingSub       = "sty:swing-substitute"
    case styBarryHarris    = "sty:swing-BarryHarris"
    case styBobbyTimmons   = "sty:swing-BobbyTimmons"
    case styBudPowell      = "sty:swing-BudPowell"
    case styHoraceSilver   = "sty:swing-HoraceSilver"
    case styRedGarland     = "sty:swing-RedGarland"
    case stySonnyClark     = "sty:swing-SonnyClark"
    case styTadDameron     = "sty:swing-TadDameron"
    // Shuffle 4（P3-b.1 下架 shuffle-light）
    case styShuffle        = "sty:shuffle"
    case styCloppety       = "sty:shuffle-cloppety"
    // P3-b.1 下架（真机听感），旧码封存：case styShuffleLight   = "sty:shuffle-light"
    case styBoogie1        = "sty:boogie-shuffle-1"
    case styBoogie2        = "sty:boogie-shuffle-2"
    // Rock 11（P3-b.1 下架 rock-triplet / rock-triplet-2，folk-rock 保留）
    case styRock50s        = "sty:rock-50s"
    case styRock68         = "sty:rock-6-8"
    case styRockBrushes    = "sty:rock-brushes"
    case styRockCalypso    = "sty:rock-calypso"
    case styRockHeavyEven  = "sty:rock-heavy-even"
    case styRockLight      = "sty:rock-light"
    case styRockLightEven  = "sty:rock-light-even"
    case styRockMedium     = "sty:rock-medium"
    case styRockMediumEven = "sty:rock-medium-even"
    case styRockSlow       = "sty:rock-slow"
    // P3-b.1 下架（真机听感），旧码封存：
    // case styRockTriplet    = "sty:rock-triplet"
    // case styRockTriplet2   = "sty:rock-triplet-2"
    case styFolkRock       = "sty:folk-rock"
    // Latin 10
    case styLatin          = "sty:latin"
    case styLatin23        = "sty:latin-2-3-son-clave"
    case styLatin32        = "sty:latin-3-2-son-clave"
    case styLatinEnhanced  = "sty:latin-enhanced"
    case styLatinFast      = "sty:latin-fast"
    case styLatinNew       = "sty:latin-new"
    case styLatinPedal1    = "sty:latin-pedal-bass-1"
    case styLatinPedal2    = "sty:latin-pedal-bass-2"
    case styLatinPlain     = "sty:latin-plain"
    case styLatinGuiro     = "sty:latin-with-guiro"
    // Funk 2
    case styFunk           = "sty:funk"
    case styFunkDisco      = "sty:funk-disco"
    // Blues 2（[P3-e] blues-clair 真机听感下架）
    case styPopBlues       = "sty:pop-blues"
    case stySenorBlues     = "sty:senor-blues"
    // [P3-e 下架] case styBluesClair     = "sty:blues-clair"
    // Two-beat / Tango（顶层单项）
    case styTwoBeat        = "sty:two-beat"
    case styTango          = "sty:tango"
    // [P3-d] Ballad 1 / Bossa 3 / Waltz 2（均 3/4）/ African 2（4/4 三连音）；[P3-e] waltz-chopin、african-slow 真机听感下架
    case styBallad           = "sty:ballad"
    case styBossa            = "sty:bossa"
    case styBossaA           = "sty:bossaA"
    case styBossaB           = "sty:bossaB"
    case styWaltz            = "sty:waltz"
    // [P3-e 下架] case styWaltzChopin      = "sty:waltz-chopin"
    case styWaltzParisienne  = "sty:waltz-parisienne"
    case styAfrican          = "sty:african"
    // [P3-e 下架] case styAfricanSlow      = "sty:african-slow"
    case styAfrican3         = "sty:african3"

    // [P3-b] 用户可见名（全英文）。手写三套加 Simple 前缀置顶；rawValue 不参与显示。
    var displayName: String {
        switch self {
        // 手写（[P3-e]+[P3-f] 七个手写 Simple 已全部下架，旧码封存；Style 菜单仅保留 Java .sty 项）
        // case .swing:  return "Simple Swing"
        // [P3-f] case .blues:  return "Simple Shuffle"
        // case .latin:  return "Simple Latin"
        // [P3-d] 手写保留项加 Simple 前缀（[P3-e] ballad 已下架、旧码封存）：
        // case .ballad: return "Simple Ballad"
        // [P3-f] case .afro:   return "Simple Afro"
        // [P3-f] case .bossa:  return "Simple Bossa"
        // case .waltz:  return "Simple Waltz"
        // Swing
        case .stySwing:         return "Swing"
        case .stySwingBackbeat: return "Backbeat"
        case .stySwingSquare:   return "Square Comp"
        case .stySwingSub:      return "Substitute"
        case .styBarryHarris:   return "Barry Harris"
        case .styBobbyTimmons:  return "Bobby Timmons"
        case .styBudPowell:     return "Bud Powell"
        case .styHoraceSilver:  return "Horace Silver"
        case .styRedGarland:    return "Red Garland"
        case .stySonnyClark:    return "Sonny Clark"
        case .styTadDameron:    return "Tadd Dameron"
        // Shuffle
        case .styShuffle:      return "Shuffle"
        case .styCloppety:     return "Cloppety Shuffle"
        // P3-b.1 下架，旧码封存：case .styShuffleLight: return "Light Shuffle"
        case .styBoogie1:      return "Boogie Shuffle 1"
        case .styBoogie2:      return "Boogie Shuffle 2"
        // Rock
        case .styRock50s:        return "50s Rock"
        case .styRock68:         return "Rock 6/8"
        case .styRockBrushes:    return "Rock Brushes"
        case .styRockCalypso:    return "Calypso Rock"
        case .styRockHeavyEven:  return "Heavy Even Rock"
        case .styRockLight:      return "Light Rock"
        case .styRockLightEven:  return "Light Even Rock"
        case .styRockMedium:     return "Medium Rock"
        case .styRockMediumEven: return "Medium Even Rock"
        case .styRockSlow:       return "Slow Rock"
        // P3-b.1 下架，旧码封存：
        // case .styRockTriplet:    return "Triplet Rock"
        // case .styRockTriplet2:   return "Triplet Rock 2"
        case .styFolkRock:       return "Folk Rock"
        // Latin
        case .styLatin:         return "Latin"
        case .styLatin23:       return "2-3 Son Clave"
        case .styLatin32:       return "3-2 Son Clave"
        case .styLatinEnhanced: return "Enhanced Latin"
        case .styLatinFast:     return "Fast Latin"
        case .styLatinNew:      return "New Latin"
        case .styLatinPedal1:   return "Pedal Bass 1"
        case .styLatinPedal2:   return "Pedal Bass 2"
        case .styLatinPlain:    return "Plain Latin"
        case .styLatinGuiro:    return "Latin with Guiro"
        // Funk / Blues / Two-beat / Tango
        case .styFunk:       return "Funk"
        case .styFunkDisco:  return "Disco Funk"
        case .styPopBlues:   return "Pop Blues"
        case .stySenorBlues: return "Señor Blues"
        // [P3-e 下架] case .styBluesClair: return "Blues Clair"
        case .styTwoBeat:    return "Two Beat"
        case .styTango:      return "Tango"
        // [P3-d] Ballad / Bossa / Waltz / Afro 子菜单
        case .styBallad:           return "Ballad"
        case .styBossa:            return "Bossa"
        case .styBossaA:           return "Bossa A"
        case .styBossaB:           return "Bossa B"
        case .styWaltz:            return "Waltz"
        // [P3-e 下架] case .styWaltzChopin:      return "Chopin Waltz"
        case .styWaltzParisienne:  return "Parisienne Waltz"
        case .styAfrican:          return "African"
        // [P3-e 下架] case .styAfricanSlow:      return "African Slow"
        case .styAfrican3:         return "African Triplet"
        }
    }
}

// [P3-b] 二级菜单分组数据（SwiftUI Menu 嵌套子菜单用）
struct StyleMenuSection: Identifiable {
    let id: String
    let title: String
    let items: [MixerDisplayMode]
}

extension MixerDisplayMode {
    /// 六个子菜单（Simple 手写项各自置顶）。
    static let groupedSections: [StyleMenuSection] = [
        StyleMenuSection(id: "swing", title: "Swing", items: [
            // [P3-e 下架] 首位原为手写 .swing（Simple Swing），旧行封存：.swing, .stySwing, .stySwingBackbeat, .stySwingSquare, .stySwingSub,
            .stySwing, .stySwingBackbeat, .stySwingSquare, .stySwingSub,
            .styBarryHarris, .styBobbyTimmons, .styBudPowell,
            .styHoraceSilver, .styRedGarland, .stySonnyClark, .styTadDameron
        ]),
        StyleMenuSection(id: "shuffle", title: "Shuffle", items: [
            // P3-b.1 下架 Light Shuffle，旧码封存：.blues, .styShuffle, .styShuffleLight, .styCloppety, .styBoogie1, .styBoogie2
            // [P3-f] 下架手写 Simple Shuffle（.blues），旧行封存：.blues, .styShuffle, .styCloppety, .styBoogie1, .styBoogie2
            .styShuffle, .styCloppety, .styBoogie1, .styBoogie2
        ]),
        StyleMenuSection(id: "rock", title: "Rock", items: [
            .styRock50s, .styRock68, .styRockBrushes, .styRockCalypso, .styRockHeavyEven,
            .styRockLight, .styRockLightEven, .styRockMedium, .styRockMediumEven,
            // P3-b.1 下架两个 Triplet Rock，旧码封存：.styRockSlow, .styRockTriplet, .styRockTriplet2, .styFolkRock
            .styRockSlow, .styFolkRock
        ]),
        StyleMenuSection(id: "latin", title: "Latin", items: [
            // [P3-e 下架] 首位原为手写 .latin（Simple Latin），旧行封存：.latin, .styLatin, .styLatinEnhanced, .styLatinFast, .styLatinNew,
            .styLatin, .styLatinEnhanced, .styLatinFast, .styLatinNew,
            .styLatinPlain, .styLatinGuiro, .styLatin23, .styLatin32,
            .styLatinPedal1, .styLatinPedal2
        ]),
        StyleMenuSection(id: "funk", title: "Funk", items: [
            .styFunk, .styFunkDisco
        ]),
        StyleMenuSection(id: "blues", title: "Blues", items: [
            // [P3-e 下架 .styBluesClair，旧行封存：.styPopBlues, .stySenorBlues, .styBluesClair
            .styPopBlues, .stySenorBlues
        ])
    ]

    /// 顶层单项。
    static let standaloneStyles: [MixerDisplayMode] = [.styTwoBeat, .styTango]
    // [旧码封存 P3-d 20261011] Ballad/Bossa/Waltz/Afro 由顶层平铺单项改为二级嵌套子菜单（见 preservedSections）：
    // /// 保留的手写风格（P3-d 前置于菜单末尾平铺）。
    // static let preservedStyles: [MixerDisplayMode] = [.ballad, .bossa, .waltz, .afro]
    // [P3-d] 四个保留手写风格的二级子菜单（手写 Simple 项置顶，其后为 Java .sty 原版）。
    static let preservedSections: [StyleMenuSection] = [
        // [P3-e] Simple Ballad 下架，本组仅剩 Java Ballad 一项 → 由菜单体自动拍平为顶层项（见 H6）
        StyleMenuSection(id: "ballad", title: "Ballad", items: [
            // [P3-e 下架手写] .ballad,
            .styBallad
        ]),
        StyleMenuSection(id: "bossa", title: "Bossa", items: [
            // [P3-f] 下架手写 Simple Bossa（.bossa），旧行封存：.bossa, .styBossa, .styBossaA, .styBossaB
            .styBossa, .styBossaA, .styBossaB
        ]),
        StyleMenuSection(id: "waltz", title: "Waltz", items: [
            // [P3-e 下架] .waltz（手写 Simple Waltz）、.styWaltzChopin（真机听感不佳），旧行封存：
            // .waltz, .styWaltz, .styWaltzChopin, .styWaltzParisienne
            .styWaltz, .styWaltzParisienne
        ]),
        StyleMenuSection(id: "afro", title: "Afro", items: [
            // [P3-e 下架 .styAfricanSlow（仅 Ride 镲、真机听感不佳），旧行封存：.afro, .styAfrican, .styAfricanSlow, .styAfrican3
            // [P3-f] 下架手写 Simple Afro（.afro），旧行封存：.afro, .styAfrican, .styAfrican3
            .styAfrican, .styAfrican3
        ])
    ]
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
    // [方案21 20260915]（旧，已封存）isColorDotEligible=当前组是否允许 Color 圆点；该布尔在 P2 被下方 group 取代。
    //   COLOR 下拉本身始终可点、作用不变。原 melody 用的 embellishLocked 已随 Melody 组下线删除。
    @Binding var guideColorEnabled: Bool
    // [Guide 双色彩 20261002] Guide 骨架（线条本身）色彩：独立于加花，默认关（对齐 Java Guide 面板 Allow Color Tones 出厂关）
    @Binding var guideLineColorEnabled: Bool
    // [Grammar Color 圆点 20260925] Basic/Master 整流色彩开关（默认 true，保持 grammar 默认听感）。
    @Binding var grammarColorEnabled: Bool
    // [LSTM P2] Learning 整流色彩开关（独立键，默认 false=spell-only）
    @Binding var lstmColorEnabled: Bool
    // [LSTM P2] 当前算法组（嵌套于 ContentView；取代旧布尔 isColorDotEligible）：右栏据此分流色彩键、Learning 置灰 TRANSFORM
    let group: ContentView.ImproAlgorithmGroup
    let isPlaying: Bool

    // [Guide 双色彩 20261002] Guide 拆两道独立色彩：骨架(线条) / 加花(✧)；grammar/learning 维持单色彩。
    private var isGuideGroup: Bool { group == .guide }   // true=Guide
    private var isLearning: Bool { group == .learning }  // [LSTM P2] Learning=LSTM
    private var isTrading: Bool { group == .trading }    // [M2-10] Trading=实时轮流
    /// Transform 引擎对 Learning（LSTM）与 Trading（实时轮流）均不作用
    private var transformBlocked: Bool { isLearning || isTrading }

    /* [旧码封存 P1 20261009] 主 COLOR 圆点与宽度下拉的色彩绑定辅助；
       色彩开关已迁入各模式设置卡片，宽度全绑全局 colorModeRaw：
    // ① 主 COLOR 圆点＝线条/骨架色彩：Guide→guideLineColorEnabled；Learning→lstmColorEnabled；Basic/Master→grammarColorEnabled。
    private var lineColorBinding: Binding<Bool> {
        if isGuideGroup { return $guideLineColorEnabled }
        if isLearning { return $lstmColorEnabled }
        return $grammarColorEnabled
    }
    // 主 COLOR 圆点恒可点（Guide 不再依赖 TRANSFORM；grammar/learning 本就恒可点）。
    private var lineColorIsOn: Bool { lineColorBinding.wrappedValue }

    // ② Conserv/Ext 宽度下拉服务的色彩：Guide→加花✧(guideColorEnabled)；Learning→lstmColorEnabled；Basic/Master→grammarColorEnabled。
    private var widthColorBinding: Binding<Bool> {
        if isGuideGroup { return $guideColorEnabled }
        if isLearning { return $lstmColorEnabled }
        return $grammarColorEnabled
    }
    private var widthColorIsOn: Bool { widthColorBinding.wrappedValue }
    */

    // ③ [P1.5] 加花色彩 ✝：Guide 与 Grammar(Basic/Master) 均可用（Learning 除外）；TRANSFORM 点亮才可点；绑 guideColorEnabled。
    // [旧码封存 P1.5] // ③ 加花色彩 ✧（仅 Guide）：TRANSFORM 点亮才可点；绑 guideColorEnabled。
    // [旧码封存 P1.5] private var embellishInteractive: Bool { isGuideGroup && enableTransform }
    private var embellishInteractive: Bool { !transformBlocked && enableTransform }
    private var embellishIsOn: Bool { guideColorEnabled }

    // [旧码封存 P1 20261009] 宽度下拉可点条件（宽度 Menu 已迁入设置卡片）：
    // private var widthMenuInteractive: Bool {
    //     isGuideGroup ? (embellishInteractive && embellishIsOn) : widthColorIsOn
    // }
    // [P1] Guide 卡宽度可点 = guideLineColorEnabled || (TRANSFORM && ✝)，其余=各自色彩键（见 ModeSettingsCard）
    /// [LSTM P2] TRANSFORM（加花）对 Learning 不作用：LSTM 独立于 Transform 引擎。
    private var transformInteractive: Bool { !transformBlocked }
    // [旧码封存 P1 20261009] 调音台不再持有宽度键（宽度 Menu 迁入设置卡片）：
    // @AppStorage("colorModeRaw") private var colorModeRaw: String = ColorPaletteMode.conservative.rawValue
    // [P1.5] Transform 最终整流色彩宽度（调音台胶囊；仅 TRANSFORM+✝ 生效）
    @AppStorage("transformWidthRaw") private var transformWidthRaw: String = ColorPaletteMode.conservative.rawValue
    // Q4 八度放置盲听档【2026-09-06 定稿封存】：曾提供 Smooth(就近上一音) / Leaps(锚定根音=对齐原版) 两档 A/B，
    // 真机盲听后 Smooth 听感更佳、放弃 Leaps；生成链已在 ContentView 固定 .smooth。下方状态与 OCTAVE Menu 一并注释保留，
    // 日后想再对比：取消本处与 Menu 的注释，并恢复 ContentView 的 octaveModeRaw/@AppStorage、octaveRaw 传参与注入即可。
    // @AppStorage("octaveModeRaw") private var octaveModeRaw: String = OctavePlacementMode.smooth.rawValue
    // 整曲化已定稿：原临时盲听档 @AppStorage("grammarSegmentModeRaw") 已随 PHRASE Menu 一并移除，
    // 生成链固定 wholeSong；GrammarStrategy.GrammarSegmentMode 枚举保留作内部回退，UI 不再暴露。
    // 钢琴和声档位菜单已下线、系统默认 Full；下面这行封存，恢复 VOICING Menu 时启用。
    // @AppStorage("pianoVoicingModeRaw") private var pianoVoicingModeRaw: String = PianoVoicingMode.full.rawValue

    // [P3-b] 二级菜单内的可选项（友好名 + 选中勾 + 轻触觉）。
    @ViewBuilder
    private func styleMenuButton(_ style: MixerDisplayMode) -> some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            selectedStyle = style
        } label: {
            Text(style.displayName)
            if selectedStyle == style {
                Image(systemName: "checkmark")
            }
        }
    }

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

                        // [旧码封存 P3-b 20261011] 原菜单扁平 ForEach(MixerDisplayMode.allCases)、胶囊显示 rawValue：
                        // Menu {
                        //     ForEach(MixerDisplayMode.allCases, id: \.self) { style in
                        //         Button { selectedStyle = style } label: {
                        //             Text(style.rawValue.capitalized)
                        //             if selectedStyle == style { Image(systemName: "checkmark") }
                        //         }
                        //     }
                        // } label: { Text(selectedStyle.rawValue.uppercased()) ... }
                        //
                        // [P3-b] 二级菜单：Swing/Shuffle/Rock/Latin/Funk/Blues 子菜单 + Two Beat/Tango 单项 + 保留手写。
                        Menu {
                            ForEach(MixerDisplayMode.groupedSections) { section in
                                Menu {
                                    ForEach(section.items, id: \.self) { style in
                                        styleMenuButton(style)
                                    }
                                } label: {
                                    Text(section.title)
                                }
                            }
                            Divider()
                            ForEach(MixerDisplayMode.standaloneStyles, id: \.self) { style in
                                styleMenuButton(style)
                            }
                            Divider()
                            // [旧码封存 P3-d 20261011] 原 4 个手写风格在此平铺为顶层单项：
                            // ForEach(MixerDisplayMode.preservedStyles, id: \.self) { style in
                            //     styleMenuButton(style)
                            // }
                            // [P3-d] Ballad/Bossa/Waltz/Afro 改为二级嵌套子菜单（点 Style → 分组 → 具体风格）：
                            // [旧码封存 P3-e] 原 preservedSections 一律套二级 Menu（Ballad 下架手写后仅剩一项，再套两层属冗余）：
                            // ForEach(MixerDisplayMode.preservedSections) { section in
                            //     Menu {
                            //         ForEach(section.items, id: \.self) { style in
                            //             styleMenuButton(style)
                            //         }
                            //     } label: {
                            //         Text(section.title)
                            //     }
                            // }
                            // [P3-e] 单项组（Ballad）直接拍平为顶层按钮；多项组（Bossa/Waltz/Afro）仍为二级子菜单：
                            ForEach(MixerDisplayMode.preservedSections) { section in
                                if section.items.count == 1, let only = section.items.first {
                                    styleMenuButton(only)
                                } else {
                                    Menu {
                                        ForEach(section.items, id: \.self) { style in
                                            styleMenuButton(style)
                                        }
                                    } label: {
                                        Text(section.title)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(selectedStyle.displayName.uppercased())   // [P3-b] 用友好名，不再用 rawValue
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)   // [P3-b] 长名（如 LATIN WITH GUIRO）在 110 胶囊内缩字兜底

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

                        /* [旧码封存 P1 20261009] 主 COLOR 圆点行；骨架/线条色彩开关已迁入各模式设置卡片：
                        // [Guide 双色彩 20261002] 主 COLOR 圆点＝骨架/线条色彩（全界面唯一「COLOR」单词）：
                        //   Guide 恒可点、独立于 TRANSFORM；关=spell-only（Java 出厂），开=骨架加全量色彩。
                        //   Conserv/Ext 宽度下拉移至 TRANSFORM 组（乐手下方），骨架无宽度档。
                        HStack(spacing: 4) {
                            Button {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    lineColorBinding.wrappedValue.toggle()
                                }
                            } label: {
                                Image(systemName: lineColorIsOn ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(lineColorIsOn ? .accentColor : .secondary)
                                    .frame(width: 18, height: 18)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            // 主 COLOR 恒可点（Guide 骨架色彩独立于 TRANSFORM）
                            Text("COLOR")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                            Spacer(minLength: 0)
                        }
                        .frame(height: 14)
                        */

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
                            // [LSTM P2] Learning 下 TRANSFORM 不作用、置灰；其余组恒可点（方案21）
                            .disabled(!transformInteractive)
                            .opacity(transformInteractive ? 1 : 0.4)
                            Text(NSLocalizedString("变换加花", comment: "").uppercased())
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .foregroundColor(.secondary)
                            Spacer(minLength: 0)
                            // [P1.5] 加花色彩 ✝：Guide 与 Grammar 均显示（Learning 除外），TRANSFORM 点亮才可点，绑 guideColorEnabled
                            // [旧码封存 P1.5] // [Guide 双色彩] 加花色彩 ✧：仅 Guide 显示，TRANSFORM 点亮才可点，绑 guideColorEnabled
                            // [旧码封存 P1.5] if isGuideGroup {
                            if !transformBlocked {
                                Button {
                                    let gen = UIImpactFeedbackGenerator(style: .light)
                                    gen.impactOccurred()
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        guideColorEnabled.toggle()
                                    }
                                } label: {
                                    Image(systemName: embellishIsOn ? "sparkles" : "sparkle")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(embellishIsOn ? .accentColor : .secondary)
                                        .frame(width: 18, height: 18)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(!embellishInteractive)
                                .opacity(embellishInteractive ? 1 : 0.4)
                            }
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
                        .disabled(!enableTransform || transformBlocked)   // [M2-10] Learning/Trading 恒置灰；其余组圆点关置灰
                        .opacity((enableTransform && !transformBlocked) ? 1 : 0.4)

                        // [P1.5a] Transform 最终色彩宽度胶囊：所有链路【常驻显示】；
                        //   Learning / TRANSFORM 关 / ✝ 关 三种情况均置灰不可点，
                        //   仅「非 Learning 且 TRANSFORM 开且 ✝ 开」可点。
                        // [旧码封存 P1.5a 20261009] 胶囊原仅非 Learning 且 TRANSFORM 点亮时出现：
                        // if !isLearning && enableTransform {
                        Menu {
                                ForEach(ColorPaletteMode.allCases, id: \.self) { mode in
                                    Button {
                                        transformWidthRaw = mode.rawValue
                                    } label: {
                                        HStack {
                                            Text(mode.label)
                                            if transformWidthRaw == mode.rawValue { Image(systemName: "checkmark") }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text((ColorPaletteMode(rawValue: transformWidthRaw) ?? .conservative).shortLabel.uppercased())
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .lineLimit(1).minimumScaleFactor(0.85)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .foregroundColor(.primary)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                                .background(Color.gray.opacity(0.12))
                                .clipShape(Capsule())
                                .contentShape(Capsule())
                            }
                            // [P1.5a] 旧条件 .disabled(!guideColorEnabled) / .opacity(guideColorEnabled ? 1 : 0.4) 已封存：
                            .disabled(transformBlocked || !enableTransform || !guideColorEnabled)
                            .opacity((!transformBlocked && enableTransform && guideColorEnabled) ? 1 : 0.4)

                        /* [旧码封存 P1 20261009] Conserv/Ext 宽度下拉；已迁入各模式设置卡片（全绑 colorModeRaw）：
                        // [Guide 双色彩 20261002] Conserv/Ext 宽度下拉（迁到乐手下方）：
                        //  Guide 服务加花✧，需 TRANSFORM 开且 ✧ 开才亮（关 TRANSFORM resident 置灰）；
                        //  Learning→lstmColor；Basic/Master→grammarColor（等价现状）。
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
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(Color.gray.opacity(0.12))
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                        }
                        .disabled(!widthMenuInteractive)
                        .opacity(widthMenuInteractive ? 1 : 0.4)
                        */

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
