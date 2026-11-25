import Foundation

// MARK: - 独立模块：拍号配置中心
struct MetreProfile {
    let name: String            // 例如 "4/4", "3/4", "12/8"
    let numBeats: Int           // VexFlow Voice 参数: 每小节几拍
    let beatValue: Int          // VexFlow Voice 参数: 以几分音符为一拍
    
    let slotsPerMeasure: Int    // 每小节总 Slots (1个四分音符 = 120 slots)
    let beatBoundaries: [Int]   // 强拍切割边界 (用于 GridQuantizer)
    
    let vfBeamGroupTicks: Double  // VexFlow 自动连符杠的判定区间 (比如 4/4 是 1024，6/8 是一组附点四分即 1536)
}

struct TimeSignatureManager {
    static func getProfile(for timeSignature: String) -> MetreProfile {
        switch timeSignature {
        case "3/4":
            return MetreProfile(
                name: "3/4", numBeats: 3, beatValue: 4,
                slotsPerMeasure: 360,
                beatBoundaries: [120, 240],
                vfBeamGroupTicks: 1024
            )
        case "6/8":
            return MetreProfile(
                name: "6/8", numBeats: 6, beatValue: 8,
                slotsPerMeasure: 360,
                beatBoundaries: [180],
                vfBeamGroupTicks: 1536
            )
        case "12/8":
            return MetreProfile(
                name: "12/8", numBeats: 12, beatValue: 8,
                slotsPerMeasure: 720,
                beatBoundaries: [180, 360, 540],
                vfBeamGroupTicks: 1536
            )
        case "5/4":
            return MetreProfile(
                name: "5/4", numBeats: 5, beatValue: 4,
                slotsPerMeasure: 600,
                beatBoundaries: [120, 240, 360, 480],
                vfBeamGroupTicks: 1024
            )
        case "6/4":
            return MetreProfile(
                name: "6/4", numBeats: 6, beatValue: 4,
                slotsPerMeasure: 720,
                beatBoundaries: [120, 240, 360, 480, 600],
                vfBeamGroupTicks: 1024
            )
        case "1/2":
            return MetreProfile(
                name: "1/2", numBeats: 1, beatValue: 2,
                slotsPerMeasure: 240,
                beatBoundaries: [],
                vfBeamGroupTicks: 2048
            )
        case "2/4":
            return MetreProfile(
                name: "2/4", numBeats: 2, beatValue: 4,
                slotsPerMeasure: 240,
                beatBoundaries: [120],
                vfBeamGroupTicks: 1024
            )
        default: // 默认 "4/4" 及兜底，与原代码写死的数值 100% 相同！
            return MetreProfile(
                name: "4/4", numBeats: 4, beatValue: 4,
                slotsPerMeasure: 480,
                beatBoundaries: [120, 240, 360],
                vfBeamGroupTicks: 1024
            )
        }
    }
}
