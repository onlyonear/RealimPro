import Foundation

// MARK: - Pattern 基础骨架
// 所有伴奏 Pattern 的抽象基类。定义时长、权重等公共属性。
// 后续 DrumPattern/BassPattern/ChordPattern 均继承此基类。

class Pattern {
    /// 此 Pattern 在单个循环内的总时长 (单位: slots, 1拍=120slots)
    /// 子类复写此方法返回各自的具体时长
    var durationSlots: Int { return 0 }
    
    /// 权重 — 同一风格中多个候选 Pattern 被选中的概率
    var weight: Float = 10.0
}
