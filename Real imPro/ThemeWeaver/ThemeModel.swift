//
//  ThemeModel.swift
//  RealimPro
//
//  ThemeWeaver M1：主题/概率档/编织配置数据模型。出厂默认值逐字抄自 Java ThemeWeaver
//  界面字段初值（D-2：先 1:1，再盲调），来源行号见各注释。
//

import Foundation

// MARK: - 主题（一段动机旋律 + 名字）
struct MotifTheme {
    var name: String
    var melody: MelodyPart
    init(name: String, melody: MelodyPart) {
        self.name = name
        self.melody = melody
    }
}

// MARK: - 单个主题的 7 个概率（对应 Java ThemeUse）
struct ThemeUseProb {
    var use: Double          // probUse：多主题间被选中的相对权重
    var transpose: Double
    var invert: Double
    var reverse: Double
    var expand: Double
    var sideslip: Double
    var barLineShift: Double

    /// Java 出厂默认（ThemeWeaver.java:132-138）：use=1.0，六个变形全 0
    /// （即出厂时主题原样出现，用户调高某变形概率才会变）
    static let javaDefault = ThemeUseProb(use: 1.0, transpose: 0.0, invert: 0.0,
                                          reverse: 0.0, expand: 0.0, sideslip: 0.0,
                                          barLineShift: 0.0)
}

// MARK: - 编织全局配置（全局概率/窗长/音域），默认值 1:1 抄 Java
struct ThemeWeaverConfig {
    var themeIntervalBeats: Int = 8        // themeIntervalTextField 默认 "8"（L1848）
    var slotsPerBeat: Int = 120           // Constants.BEAT
    var probUseTheme: Double = 0.5        // themeProbTextField 默认 "0.5"（L1872）；>rand 时用主题

    var probWholeToneTranspose: Double = 0.7   // 字段初值（L108）
    var probExpandBy3: Double = 0.5            // probExpandby2or3 JSlider 默认 50/100
    var probSlideUp: Double = 0.5              // probSlideUp 字段初值（L110）/滑杆 50
    var probForwardShift: Double = 0.5         // probShiftForwardorBackSlider 默认 50/100
    var shiftForwardByFinal: Int = 60          // 字段常量（L117，slots）

    // 侧滑距离档：半/全/小三度（L890/904/917 = 0.4/0.4/0.2，会归一化）
    var sideSlipHalf: Double = 0.4
    var sideSlipWhole: Double = 0.4
    var sideSlipThird: Double = 0.2

    var minPitch: Int = 60                 // ThemeWeaver 字段默认（L103-104）
    var maxPitch: Int = 82

    var windowSlots: Int { themeIntervalBeats * slotsPerBeat }
}
