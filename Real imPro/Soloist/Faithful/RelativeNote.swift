import Foundation

// MARK: X 结构（makeRelativeNote）：确定性音阶度数，不消耗随机源
// 形如 (X degree duration)，degree 为整数或带 b/# 前缀，duration 为裸时值字符串
// family → (degree 2...7) 半音偏移表（与 Java 2596-2777 一致）
private let FAMILY_DEGREE_OFFSET: [String: [Int: Int]] = [
    "major":           [2:2, 3:4, 4:5, 5:7, 6:9, 7:11],
    "minor":           [2:2, 3:3, 4:5, 5:7, 6:9, 7:11],
    "minor7":          [2:2, 3:3, 4:5, 5:7, 6:9, 7:10],
    "dominant":        [2:2, 3:4, 4:5, 5:7, 6:9, 7:10],
    "half-diminished": [2:2, 3:3, 4:5, 5:7, 6:9, 7:10],
    "diminished":      [2:2, 3:3, 4:5, 5:6, 6:8, 7:9],
    "augmented":       [2:2, 3:4, 4:5, 5:8, 6:9, 7:10],
]

/// 判断是否为 X 结构（list，长度 3，首元素 "X"）
func isScaleDegree(_ expr: SExpr) -> Bool {
    guard let items = expr.items, items.count == 3, items.first?.sym == "X" else {
        return false
    }
    return true
}

/// 复刻 makeRelativeNote，返回 (pitch, rhythmValue)
func makeRelativeNote(_ expr: SExpr, chord: Chord2) -> (pitch: Int, rhythmValue: Int) {
    let items = expr.items!
    let root = chord.root + 60
    var pitch = root
    var degreeValue = 1

    // 解析第二个元素（整数或带 b/# 的字符串）
    let second = items[1]
    if let n = second.num {
        degreeValue = n
    } else if var s = second.sym {
        while let c = s.first, c == "b" || c == "#" {
            if c == "b" { pitch -= 1 } else { pitch += 1 }
            s.removeFirst()
        }
        degreeValue = Int(s) ?? 1
    }

    // 八度调整（Java 口径：负向每次 +8，正向每次 -7）
    var octaveAdjustment = 0
    while degreeValue < 0 {
        octaveAdjustment -= 1
        degreeValue += 8
    }
    while degreeValue > 7 {
        octaveAdjustment += 1
        degreeValue -= 7
    }

    // family 映射
    let table = FAMILY_DEGREE_OFFSET[chord.family] ?? FAMILY_DEGREE_OFFSET["major"]!
    if let off = table[degreeValue] { pitch += off }

    pitch += octaveAdjustment * 12

    // 第三个元素为时值（裸数字字符串）
    let durationString: String
    if let n = items[2].num { durationString = String(n) } else { durationString = items[2].sym ?? "8" }
    let duration = Duration2.getDuration(durationString)
    return (pitch, duration)
}
