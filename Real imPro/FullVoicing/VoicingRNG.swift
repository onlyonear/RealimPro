import Foundation

// MARK: - 并列候选的随机选择（对齐 findVoicingAndExtension.getRandomItem）。可注入固定 RNG 做逐音对标。
protocol VoicingRNG { func nextIndex(_ count: Int) -> Int }

struct SystemVoicingRNG: VoicingRNG {
    func nextIndex(_ count: Int) -> Int { count > 0 ? Int.random(in: 0..<count) : 0 }
}

/// 确定性 RNG: 永远取并列第一个。headless 对标 Java「取并列第一个」金标准时使用。
struct FixedVoicingRNG: VoicingRNG {
    func nextIndex(_ count: Int) -> Int { 0 }
}
