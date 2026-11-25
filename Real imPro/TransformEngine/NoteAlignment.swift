import Foundation

/// 单个音符的"结构签名"：刻意不含 pitch。
/// 转调只改 pitch，故同小节转调前后的结构签名完全一致。
struct NoteStructure: Equatable {
    let isRest: Bool
    let duration: String
    let isTriplet: Bool
}

enum NoteAlignment {
    /// 展开小节内音符下标 -> 原始小节内音符下标。
    /// 在结构签名层面做循环偏移匹配（兼容历史"弱起旋转"，offset=0 即恒等对齐）。
    /// 安全守卫：
    ///   1) 两边均非空；
    ///   2) 音符数量必须相等 —— 否则模运算会让短序列在长序列上"循环对上"造成错高亮。
    /// 无法可靠对齐时返回空字典，由调用方安全降级为"不高亮"。
    static func indexMap(expanded: [NoteStructure], raw: [NoteStructure]) -> [Int: Int] {
        guard !expanded.isEmpty, !raw.isEmpty,
              expanded.count == raw.count else { return [:] }
        for offset in 0..<raw.count {
            var ok = true
            for (v, es) in expanded.enumerated() {
                let ri = (v + offset) % raw.count
                if raw[ri] != es { ok = false; break }
            }
            if ok {
                var dict: [Int: Int] = [:]
                for v in expanded.indices { dict[v] = (v + offset) % raw.count }
                return dict
            }
        }
        return [:]
    }
}
