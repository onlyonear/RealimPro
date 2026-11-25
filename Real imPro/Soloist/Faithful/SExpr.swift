import Foundation

/// 最小 S 表达式：原子（符号/整数）或列表。等价 Java polya.Polylist 的结构。
enum SExpr {
    case symbol(String)
    case number(Int)
    case list([SExpr])

    /// 列表元素（非列表返回 nil）
    var items: [SExpr]? {
        if case .list(let a) = self { return a }
        return nil
    }
    /// 符号字符串
    var sym: String? {
        if case .symbol(let s) = self { return s }
        return nil
    }
    /// 整数
    var num: Int? {
        if case .number(let n) = self { return n }
        return nil
    }
}

/// 把 mObjData 文本解析成 SExpr 列表序列（顶层可能有多个并列的 (...)）。
enum SExprParser {
    static func parse(_ text: String) -> [SExpr] {
        var tokens = tokenize(text)
        var result: [SExpr] = []
        while !tokens.isEmpty {
            let (v, rest) = readFrom(tokens)
            tokens = rest
            result.append(v)
        }
        return result
    }

    private static func tokenize(_ s: String) -> [String] {
        var out: [String] = []
        var i = s.startIndex
        var buf = ""
        func flush() { if !buf.isEmpty { out.append(buf); buf = "" } }
        while i < s.endIndex {
            let c = s[i]
            if c == "(" || c == ")" {
                flush()
                out.append(String(c))
            } else if c.isWhitespace {
                flush()
            } else {
                buf.append(c)
            }
            i = s.index(after: i)
        }
        flush()
        return out
    }

    private static func readFrom(_ tokens: [String]) -> (SExpr, [String]) {
        guard let first = tokens.first else { return (.list([]), []) }
        if first == "(" {
            var rest = Array(tokens.dropFirst())
            var elems: [SExpr] = []
            while rest.first != ")" {
                let (v, next) = readFrom(rest)
                elems.append(v)
                rest = next
            }
            return (.list(elems), Array(rest.dropFirst())) // 去掉 ")"
        }
        let atom: SExpr = Int(first).map { .number($0) } ?? .symbol(first)
        return (atom, Array(tokens.dropFirst()))
    }
}
