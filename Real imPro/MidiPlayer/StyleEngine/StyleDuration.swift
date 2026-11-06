import Foundation

// MARK: - StyleDuration
// .sty 时值表达式 → Style 时间轴 slots（全音符 = 480 = 4/4 一小节，1 拍 = 120）。
// 对齐 Java Duration.java:201-240（Java 内部 WHOLE=1920，是这里的 4 倍，公式同构：先乘后除保证整数）。
//
// 规则：
// - 裸数字 = 音符分母：4→四分(120)、8→八分(60)、16→十六分(30)、2→二分(240)、1→全(480)；
// - "/k" 连音：slots = whole*(k-1)/(n*k)，故 8/3=40、4/3=80、16/3=20、64/3=5（全部整除）；
// - "." 附点：每点在前一次增量上折半累加，4.=180、2.=360；
// - "+" 相加：2+4=360、4+8=180、1+1+1+1=1920（钢琴 4 小节长句）、4/3+16+64/3=115。
//
// .sty 规则里的时值几乎总是紧凑字符串 token（如 X2+4+8、R8、push 8/3、(X 3 4.) 内的 "4."），
// 故以字符串解析为主；另提供 StyleSex 重载以兼容 ( + ... ) / ( n / k ) 的表写法。

enum StyleDuration {
    static let whole = 480

    static func slots(_ token: String) -> Int {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        return trimmed
            .split(separator: "+", omittingEmptySubsequences: false)
            .map { single(String($0)) }
            .reduce(0, +)
    }

    private static func single(_ raw: String) -> Int {
        var str = raw.trimmingCharacters(in: .whitespaces)
        var dots = 0
        while str.hasSuffix(".") { str.removeLast(); dots += 1 }

        var numStr = str
        var denominator = 1
        if let range = str.firstIndex(of: "/") {
            numStr = String(str[str.startIndex..<range])
            denominator = Int(str[str.index(after: range)...]) ?? 1
        }
        let numerator = max(1, Int(numStr) ?? 1)

        var s = whole
        if denominator > 1 { s *= (denominator - 1) }
        var duration = s / (numerator * denominator)

        // 附点：第一点加原值一半，第二点再加四分之一……
        var increment = duration
        for _ in 0..<dots {
            increment /= 2
            duration += increment
        }
        return duration
    }

    static func slots(_ sex: StyleSex) -> Int {
        switch sex {
        case .atom(let a):
            return slots(a)
        case .list(let items):
            guard let head = items.first?.asAtom else { return 0 }
            if head == "+" {
                return items.dropFirst().reduce(0) { $0 + slots($1) }
            }
            if head == "/", items.count >= 3,
               let n = items[1].asAtom, let k = items[2].asAtom {
                return slots("\(n)/\(k)")
            }
            // 兜底：表内若直接包了一个时值 atom
            return items.compactMap { $0.asAtom }.map { slots($0) }.first ?? 0
        }
    }
}
