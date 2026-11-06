import Foundation

// MARK: - StyleSExpression
// 原版 .sty 伴奏型文件的 S-表达式（Lisp 风格）最小解析器。
// 对齐 Java Style.java 的 tokenize / parse：.sty 顶层为若干 (section ...) 嵌套表。
// 纯文本解析，无 UI、无引擎依赖，可被 StyleParser 与测试探针共用。

indirect enum StyleSex: Equatable {
    case atom(String)
    case list([StyleSex])

    var asAtom: String? { if case .atom(let v) = self { return v }; return nil }
    var asList: [StyleSex]? { if case .list(let v) = self { return v }; return nil }
}

enum StyleSExpression {

    /// 解析整段文本，返回顶层表达式序列（.sty 通常只有一个 (style ...)）。
    static func parse(_ text: String) -> [StyleSex] {
        let tokens = tokenize(text)
        var pos = 0
        var forms: [StyleSex] = []
        while pos < tokens.count {
            if let (form, next) = parseTokens(tokens, from: pos) {
                forms.append(form)
                pos = next
            } else {
                pos += 1
            }
        }
        return forms
    }

    /// 词法切分：`(` `)` 为独立 token；`;` 起到行尾为注释；双引号字符串整体为一个 token；其余按空白切 atom。
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inComment = false
        var inString = false

        func flush() {
            if !current.isEmpty { tokens.append(current); current = "" }
        }

        for ch in text {
            if inString {
                current.append(ch)
                if ch == "\"" { inString = false; flush() }
                continue
            }
            if ch == "\"" {
                flush(); inString = true; current.append(ch); continue
            }
            if ch == "\n" || ch == "\r" {
                inComment = false; flush(); continue
            }
            if inComment { continue }
            if ch == ";" {
                flush(); inComment = true; continue
            }
            if ch == "(" || ch == ")" {
                flush(); tokens.append(String(ch))
            } else if ch.isWhitespace {
                flush()
            } else {
                current.append(ch)
            }
        }
        flush()
        return tokens
    }

    private static func parseTokens(_ tokens: [String], from start: Int) -> (StyleSex, Int)? {
        guard start < tokens.count else { return nil }
        var i = start
        if tokens[i] == "(" {
            i += 1
            var items: [StyleSex] = []
            while i < tokens.count && tokens[i] != ")" {
                if let (sub, next) = parseTokens(tokens, from: i) {
                    items.append(sub); i = next
                } else {
                    i += 1
                }
            }
            if i < tokens.count { i += 1 }   // 吃掉右括号
            return (.list(items), i)
        } else if tokens[i] == ")" {
            return nil
        } else {
            return (.atom(tokens[i]), i + 1)
        }
    }
}
