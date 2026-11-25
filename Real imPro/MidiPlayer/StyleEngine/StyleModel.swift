import Foundation

// MARK: - StyleModel
// .sty 解析后的内存模型（与播放无关的纯数据）。三轨 pattern 中：
// - bass / chord 保留原始规则 S-表达式子树（ruleTrees），交给各自 Renderer 按本轨规则码展开；
// - drum 规则最简单（鼓名 + X/R/V 平铺），在解析期直接展开成 StyleDrumHit。

/// bass / chord 共用的一条 pattern。
struct StylePattern {
    let weight: Double            // 同小节多句时的加权抽取权重（Java getPattern）
    let ruleTrees: [StyleSex]     // (rules ...) 去掉包裹后的规则 token（B4、C8、X2+4+8、V90、(X 3 4.) …）
    let lengthSlots: Int          // 规则总时值（X/R/音名占时值；V 音量、U/D 方向不占）
    let pushSlots: Int            // 句首抢拍量（仅 chord 的 (push x)，bass 通常 0）
}

/// 鼓单件的一次敲击（或休止占位）。
struct StyleDrumHit {
    let onsetSlots: Int
    let durationSlots: Int
    let velocity: UInt8
    let isRest: Bool
}

/// 一件鼓的一整条规则（同名鼓在一小节内的全部击点）。
struct StyleDrumRule {
    let drumName: String
    let hits: [StyleDrumHit]
}

/// 一条鼓 pattern（含若干件鼓）。
struct StyleDrumPattern {
    let weight: Double
    let rules: [StyleDrumRule]
    let lengthSlots: Int
}

/// 一个解析完成的 .sty 风格。
struct ParsedStyle {
    let name: String
    let melodySwing: Double       // 文件头 (swing)，旋律摇摆比
    let compSwing: Double         // 文件头 (comp-swing)，伴奏摇摆比
    let voicingType: String       // open / closed（钢琴排簿方式）
    let bassLow: Int              // 以下均为 MIDI
    let bassHigh: Int
    let bassBase: Int
    let chordLow: Int
    let chordHigh: Int
    let bassPatterns: [StylePattern]
    let drumPatterns: [StyleDrumPattern]
    let chordPatterns: [StylePattern]
}
