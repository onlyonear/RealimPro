import Foundation

extension TransformEngine {
    /// 对应原版Substitution：同一类风格变换集合（如布鲁斯装饰、切分动机），内置多条Transformation加权随机选择
    struct Substitution {
        /// 分组名称（如mordent、chromatic-passing）
        var name: String
        /// 类型：motif动机 / embellishment装饰音
        var subType: String
        /// 整体分组权重
        var weight: Int
        /// 是否启用本组变换
        var enabled: Bool
        /// 本组内所有单条变换规则
        var transformations: [Transformation]
        /// 是否发生修改（用于保存标识）
        private(set) var hasChanged: Bool
        
        init(
            name: String = "identity",
            subType: String = "motif",
            weight: Int = 1,
            enabled: Bool = true,
            transformations: [Transformation] = []
        ) {
            self.name = name
            self.subType = subType
            self.weight = weight
            self.enabled = enabled
            self.transformations = transformations
            self.hasChanged = false
        }
        
        /// 完整深拷贝
        func copy() -> Self {
            let copiedTrans = transformations.map { $0.copy() }
            return Substitution(
                name: self.name,
                subType: self.subType,
                weight: self.weight,
                enabled: self.enabled,
                transformations: copiedTrans
            )
        }
        
        // MARK: 规则增删合并逻辑
        mutating func addTransformation(_ trans: Transformation) {
            var existsIndex: Int?
            for (idx, t) in transformations.enumerated() {
                if t.isEnabled == trans.isEnabled
                   && t.matchTemplate == trans.matchTemplate
                   && t.replaceExpressions == trans.replaceExpressions {
                    existsIndex = idx
                    break
                }
            }
            if let idx = existsIndex {
                var merged = transformations.remove(at: idx)
                merged.weight += trans.weight
                transformations.insert(merged, at: idx)
            } else {
                transformations.append(trans)
            }
            hasChanged = true
        }
        
        /// 清空重复变换，合并权重
        mutating func clean() {
            var uniqueList: [Transformation] = []
            for t in transformations {
                var match = false
                for i in 0..<uniqueList.count {
                    let u = uniqueList[i]
                    if u.isEnabled == t.isEnabled
                       && u.matchTemplate.count == t.matchTemplate.count
                       && u.matchTemplate == t.matchTemplate
                       && u.replaceExpressions == t.replaceExpressions {
                        uniqueList[i].weight += t.weight
                        match = true
                        break
                    }
                }
                if !match {
                    uniqueList.append(t)
                }
            }
            transformations = uniqueList
            hasChanged = true
        }
        
        /// 缩放本组所有变换权重
        mutating func scaleTransWeights(scale: Double) {
            guard scale != 1.0 else { return }
            for i in transformations.indices {
                let w = Double(transformations[i].weight) * scale
                transformations[i].weight = w // 修复：Transformation.weight是Double，直接赋值浮点结果
            }
            hasChanged = true
        }
        
        /// 获取本组总权重
        func getTotalWeight() -> Double {
            transformations.reduce(0.0) { $0 + $1.weight }
        }
        
        /// 获取本组所有变换的最大匹配长度
        func maxMatchLength() -> Int {
            transformations.map { $0.matchTemplate.count }.max() ?? 0
        }
        
        /// 找到在给定片段中实际匹配的长度
        func findMatchLength(in segment: [NoteChordPair]) -> Int {
            for t in transformations {
                guard t.isEnabled else { continue }
                if t.matches(segment: segment) {
                    return t.matchTemplate.count
                }
            }
            return 0
        }
        
        // MARK: 核心执行：对一段旋律尝试随机匹配变换
        /// - Parameters:
        ///   melody: 原始旋律片段（只读，内部操作副本）
        ///   chords: 当前和弦序列
        ///   startSlot: 起始位置
        ///   enforceDuration: 是否强制总时值不变
        /// - Returns: 变换后全新旋律，匹配失败返回nil
        func apply(
            melody: [NoteChordPair],
            chords: [ChordBlock],
            startSlot: Int,
            enforceDuration: Bool
        ) -> [NoteChordPair]? {
            guard enabled, !transformations.isEmpty else { return nil }
            
            // 内层仅按顺序找第一个匹配的transformation, 不重复加权
            for t in transformations {
                guard t.isEnabled else { continue }
                let matchLen = t.matchTemplate.count
                guard melody.count >= matchLen else { continue }
                
                let matchSegment = Array(melody.prefix(matchLen))
                guard t.matches(segment: matchSegment) else { continue }
                
                var frame = Evaluate.TransformFrame()
                let result = t.applyReplace(segment: matchSegment, frame: &frame)
                
                // 时值校验
                if enforceDuration {
                    let originTotal = matchSegment.reduce(0) { $0 + $1.getDuration() }
                    let newTotal = result.reduce(0) { $0 + $1.getDuration() }
                    if originTotal != newTotal { continue }
                }
                
                return result
            }
            return nil
        }
        
        /// 构造identity空变换（原样返回音符，不做修改）
        static func makeIdentity(type: String) -> Substitution {
            Self(name: "identity-\(type)", subType: type, weight: 1)
        }
    }
}
