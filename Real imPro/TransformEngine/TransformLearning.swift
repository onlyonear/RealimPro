import Foundation

extension TransformEngine {
    /// 对标原版 TransformLearning：自动从旋律提取动机、生成变换规则（离线学习工具，非实时生成必需）
    struct TransformLearning {
        static let shared = Self()
        private init() {}
        
        /// 最小动机长度（音符个数）
        var minMotifLength: Int = 2
        /// 最大动机长度
        var maxMotifLength: Int = 4
        /// 片段打分阈值，低于该分数丢弃
        var scoreThreshold: Double = 0.4
        /// 打分权重配置
        var priorityWeight: Double = 1.0
        var beatWeight: Double = 1.0
        var durationWeight: Double = 1.0
        
        // MARK: 主入口：整段旋律学习，输出一组新Substitution
        func learnSubstitutions(
            melody: [NoteChordPair],
            chords: [ChordBlock],
            metre: [Int] = [4,4]
        ) -> [Substitution] {
            var outputSubs: [Substitution] = []
            let scorer = Scorer(
                priorityWeight: priorityWeight,
                beatWeight: beatWeight,
                durationWeight: durationWeight,
                metre: metre
            )
            
            // 遍历所有起止位置，截取不同长度候选动机
            for start in 0..<melody.count {
                for len in minMotifLength...maxMotifLength {
                    let end = start + len
                    guard end <= melody.count else { continue }
                    let segment = Array(melody[start..<end])
                    let segScore = scorer.score(trend: segment)
                    guard segScore >= scoreThreshold else { continue }
                    
                    // 生成一条以自身为匹配模板、空替换的基础变换
                    let newTrans = Transformation(
                        guardCondition: nil,
                        isEnabled: true,
                        weight: segScore * 10,
                        matchTemplate: segment.map{$0.copy()},
                        replaceExpressions: []
                    )
                    
                    // 新建归属本组的替换分组
                    var sub = Substitution()
                    sub.name = "learned-motif-\(start)-\(len)"
                    sub.subType = "motif"
                    // 修复：Double → Int 强制转换
                    sub.weight = Int(segScore * 10)
                    sub.addTransformation(newTrans)
                    outputSubs.append(sub)
                }
            }
            return outputSubs
        }
        
        /// 将学习得到的规则合并进已有变换引擎
        mutating func mergeLearnedIntoTransform(
            transform: inout Transform,
            newSubs: [Substitution]
        ) {
            for sub in newSubs {
                if sub.subType == "motif" {
                    transform.addMotifSubstitution(sub)
                } else {
                    transform.addEmbellishmentSubstitution(sub)
                }
            }
        }
        
        /// 为单个动机生成八度上移变奏规则示例（典型学习后拓展变换）
        func createOctaveUpVariant(originalSub: Substitution) -> Substitution {
            var octSub = originalSub.copy()
            octSub.name += "-octave-up"
            for idx in octSub.transformations.indices {
                let trans = octSub.transformations[idx]
                var newReplace: [String] = []
                for _ in trans.matchTemplate {
                    newReplace.append("(+ pitch 12)")
                }
                octSub.transformations[idx].replaceExpressions = newReplace
            }
            return octSub
        }
        
        /// 生成八度下移变体
        func createOctaveDownVariant(originalSub: Substitution) -> Substitution {
            var octSub = originalSub.copy()
            octSub.name += "-octave-down"
            for idx in octSub.transformations.indices {
                let trans = octSub.transformations[idx]
                var newReplace: [String] = []
                for _ in trans.matchTemplate {
                    newReplace.append("(- pitch 12)")
                }
                octSub.transformations[idx].replaceExpressions = newReplace
            }
            return octSub
        }
    }
}
