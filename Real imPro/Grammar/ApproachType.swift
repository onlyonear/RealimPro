import Foundation

// MARK: - ApproachType — 趋近音类型扩展 (P1-3)
// 4种趋近音: 上趋近/下趋近/双趋近/环绕音

enum ApproachType {
    case none
    case above           // 上趋近: 上方半音下行
    case below           // 下趋近: 下方半音上行
    case doubleApproach  // 双趋近: 两个连续半音→目标音
    case enclosure       // 环绕音: 上全音+下半音包围目标

    /// 生成趋近音MIDI列表 (按时间顺序)
    func generateApproachNotes(targetPitch: Int) -> [Int] {
        switch self {
        case .none:           return []
        case .above:          return [targetPitch + 1]
        case .below:          return [targetPitch - 1]
        case .doubleApproach: return [targetPitch - 2, targetPitch - 1]
        case .enclosure:      return [targetPitch + 2, targetPitch - 1]
        }
    }
}

extension ApproachType {

    /// 随机选择趋近类型 (等概率4种)
    static func random() -> ApproachType {
        let types: [ApproachType] = [.above, .below, .doubleApproach, .enclosure]
        return types.randomElement()!
    }
}