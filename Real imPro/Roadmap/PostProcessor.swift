import Foundation

// MARK: - PostProcessor — CYK后处理
// 对CYK解析出的TreeNode做: 区间切分/调性修正/brick连接点查找

struct PostProcessor {

    // MARK: - 将TreeNode按小节边界切分为 Brick (ChordBlock) 序列

    /// 从解析树提取Brick区间
    /// - Parameters:
    ///   - root: CYK解析根节点
    ///   - beatsPerMeasure: 每小节拍数
    /// - Returns: [(brickName, startBeat, endBeat)]
    static func extractBricks(from root: TreeNode,
                               beatsPerMeasure: Double = 4.0) -> [(name: String, start: Double, end: Double)] {
        var result: [(name: String, start: Double, end: Double)] = []
        extractBricksRecursive(root, result: &result)
        return result
    }

    private static func extractBricksRecursive(_ node: TreeNode,
                                                result: inout [(name: String, start: Double, end: Double)]) {
        if let brickName = node.brickName, !node.isLeaf {
            // 使用 chord 索引作为区间范围 (下游按索引查找和弦时长)
            result.append((name: brickName, start: Double(node.startIndex), end: Double(node.endIndex)))
        } else if node.isLeaf {
            return
        } else {
            for child in node.children {
                extractBricksRecursive(child, result: &result)
            }
        }
    }

    // MARK: - Brick连接点查找 (Joins)

    /// 查找两个相邻Brick之间的连接点类型
    /// - Returns: 连接类型字符串 (如 "V-I", "chromatic", "diatonic")
    static func findJoinType(brickA: String, brickB: String) -> String {
        // 常见爵士连接模式
        let joinPatterns: [(String, String, String)] = [
            ("ii", "V",  "ii-V"),
            ("ii-V", "I", "ii-V-I cadence"),
            ("V", "I",  "V-I authentic"),
            ("I", "IV", "I-IV plagal"),
        ]
        for (a, b, joinType) in joinPatterns {
            if brickA.contains(a) && brickB.contains(b) { return joinType }
        }
        return "diatonic"
    }

    // MARK: - 调性区间修正

    /// 按KeySpan链修正CYK解析出的Brick区间
    /// - Parameters:
    ///   - bricks: CYK解析出的Brick列表
    ///   - keySpans: KeySpan调性链
    /// - Returns: 修正后的Brick列表 (含调性注解)
    static func alignBricksWithKeys(
        bricks: [(name: String, start: Double, end: Double)],
        keySpans: [KeySpan]
    ) -> [(name: String, start: Double, end: Double, key: String)] {
        return bricks.map { brick in
            let midBeat = (brick.start + brick.end) / 2.0
            let matchedKey = keySpans.first { $0.contains(beat: midBeat) }
            let keyLabel = matchedKey.map { "\($0.rootPC):\($0.mode)" } ?? "C:major"
            return (name: brick.name, start: brick.start, end: brick.end, key: keyLabel)
        }
    }

    // MARK: - 展平: TreeNode→ChordBlock名称序列

    /// 将解析树展平回 ChordBlock 名称列表 (用于传递到下阶段生成)
    static func flattenToChordNames(_ root: TreeNode) -> [String] {
        root.flattenNames()
    }
}
