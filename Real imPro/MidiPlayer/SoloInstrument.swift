import Foundation

/// Solo 主音色（调音台第一轨）。7 项对应 ChoriumRevA.sf2 中已核实的 GM program，
/// 统一 bankMSB 121 / bankLSB 0。仅依赖 Foundation；显示名/图标名以字符串返回，由 View 层渲染。
enum SoloInstrument: String, CaseIterable, Identifiable {
    case piano
    case guitar
    case altoSax
    case tenorSax
    case trumpet
    case trombone
    case baritoneSax

    var id: String { rawValue }

    /// GM melodic program number（sf2 预设名已核实）。
    var program: UInt8 {
        switch self {
        case .piano:       return 0    // Yamaha Grand Piano
        case .guitar:      return 26   // Jazz Guitar
        case .altoSax:     return 65   // Alto Sax
        case .tenorSax:    return 66   // Tenor Sax
        case .trumpet:     return 56   // Trumpet
        case .trombone:    return 57   // Trombone
        case .baritoneSax: return 67   // Baritone Sax
        }
    }

    var bankMSB: UInt8 { 121 }
    var bankLSB: UInt8 { 0 }

    /// 用户可见全名（英文 UI，不本地化）。
    var displayName: String {
        switch self {
        case .piano:       return "Piano"
        case .guitar:      return "Guitar"
        case .altoSax:     return "Alto Sax"
        case .tenorSax:    return "Tenor Sax"
        case .trumpet:     return "Trumpet"
        case .trombone:    return "Trombone"
        case .baritoneSax: return "Baritone Sax"
        }
    }

    /// 调音台窄标签（全大写）。
    var shortLabel: String {
        switch self {
        case .piano:       return "PIANO"
        case .guitar:      return "GTR"
        case .altoSax:     return "ALTO"
        case .tenorSax:    return "TENOR"
        case .trumpet:     return "TRP"
        case .trombone:    return "TBN"
        case .baritoneSax: return "BARI"
        }
    }

    /// SF Symbol 名。SF Symbols 无更细的管乐/铜管符号，三个萨克斯共用 wind、
    /// 小号与长号共用 horn；细分靠文字标签。
    var icon: String {
        switch self {
        case .piano:                              return "pianokeys"
        case .guitar:                             return "guitars"
        case .altoSax, .tenorSax, .baritoneSax:   return "wind"
        case .trumpet, .trombone:                 return "horn"
        }
    }
}
