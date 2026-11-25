//
//  JavaKeySpanModels.swift
//  RealimPro
//
//  J1（独立 Java 对齐 Roadmap 链）数据模型。
//  与现有 Swift 分析结果（AnalysisResult / tonalCenters / degreeLabel）完全分离，
//  互不写入、互不影响；现有链一行不动。
//

import Foundation

/// Java 对齐链的调性中心段（对应 Java RoadMap 的 KeySpan 呈现层，
/// RoadMapPanel.drawKeySpan:1151）。
/// J1 仅产出中心/调式/起止；终止式类型与砖块名在 J2（静态字典砖）补齐。
struct JavaKeySpan: Equatable {
    let rootPC: Int            // 调性中心根音 PC（0=C ... 11=B）
    let mode: String           // "Major" / "Minor" / "Dominant"
    let startBeat: Double
    var endBeat: Double
    var cadenceType: String?   // J2：终止式类型（Straight/Extended/Dropback/Launcher...）
    var brickName: String?     // J2：砖块名（Downwinder/Sidewinder...）

    var duration: Double { endBeat - startBeat }
}

/// 逐和弦完整标签（J2）：findKeys 产出 finalKey/finalMode；CYK 顶砖产出
/// brickKey/brickMode/brickType/brickName（对应 BatchHarness 的 sk/sm/tk/tm/tn/tbn）。
struct JavaChordLabel: Equatable {
    let chordIdx: Int
    let chordName: String
    let finalKey: Int        // sk：最终调性中心 PC
    let finalMode: String    // sm：最终调式
    let brickKey: Int        // tk：顶砖 key
    let brickMode: String    // tm：顶砖 mode
    let brickType: String    // tn：顶砖 type（裸和弦＝该和弦 mode）
    let brickName: String    // tbn：顶砖 dashed 名（裸和弦＝和弦名）
    // [J3 呈现层补充，不改算法] 以下字段仅用于五线谱 Key Sections 渲染
    let startBeat: Double       // 该和弦全局起点（拍，四分=1）
    let durationBeats: Double   // 时长（拍）
    let isSpanStart: Bool       // 是否调性段(span)首和弦（段首调性名只印一次）
    let isBrick: Bool           // 顶块是否为砖（false=裸和弦，不写砖名）
    let isBrickStart: Bool      // 是否砖连续段首（砖名只在砖起点印）
}

/// 独立 Java 对齐链的完整结果。
struct JavaRoadmapResult: Equatable {
    let spans: [JavaKeySpan]
    let chordLabels: [JavaChordLabel]   // J2：逐和弦完整标签
    let tonicPC: Int           // 歌曲显式主调（来自 KeyParser.parseKey）
    let songMode: String       // "Major" / "Minor"
}
