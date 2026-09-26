// =====================================================================
// TransformRuleTable.swift
// ② Guide Tone & Transform（T1，路线 B）规则表模型与紧凑 TSV 解析。
//
// TSV 由 audit 的 Java 权威导出器 TransformTableGold 离线生成（语义与 Java 自身
// 解析器同源），26 个乐手学习库全量内置在 Bundle 的 TransformTables/ 下，运行时由
// TransformMusicianRegistry 按乐手懒加载、解析成这里的 [GSub]。
//
// 行格式（制表符分隔）：
//   SUB  <name> <type=motif|embellishment> <weight> <enabled>
//   TR   <desc> <weight> <enabled> <src 空格连接> <guard> <target...>
//
// 关键（F15）：每条 SUB/TR 在解析时赋【行身份 id】。学习库中同名(desc)但目标体不同的
// 多条 Transformation 是不同对象，去重必须按 id（等价 Java 按对象引用 removeAll），
// 不能按描述字符串塌缩。
// =====================================================================

import Foundation

extension TransformEngine {

    /// 单条变换原语（对应 Java Transformation）
    struct GTrans {
        let id: Int
        let desc: String
        let weight: Int
        let enabled: Bool
        let src: [String]
        let guardExpr: String
        let targets: [String]

        /// Java Transformation.changesFirstNote：多源且首个 target 恰为首个源变量 → false
        func changesFirstNote() -> Bool {
            if src.count > 1 && targets.first == src.first { return false }
            return true
        }
    }

    /// 一组变换（对应 Java Substitution）
    struct GSub {
        let id: Int
        let name: String
        let type: String          // motif / embellishment
        let weight: Int
        let enabled: Bool
        let trans: [GTrans]
    }

    /// 紧凑 TSV 文本 → 规则表（纯函数，便于离线/测试复用）
    static func parseTransformTable(_ text: String) -> [GSub] {
        var subs: [GSub] = []
        var curTrans: [GTrans] = []
        var subId = 0
        var trId = 0

        func flush() {
            guard !subs.isEmpty else { return }
            let last = subs[subs.count - 1]
            subs[subs.count - 1] = GSub(id: last.id, name: last.name, type: last.type,
                                        weight: last.weight, enabled: last.enabled, trans: curTrans)
        }

        for raw in text.components(separatedBy: "\n") {
            if raw.hasPrefix("SUB") {
                flush()
                let f = raw.components(separatedBy: "\t")
                guard f.count >= 5 else { continue }
                subs.append(GSub(id: subId, name: f[1], type: f[2],
                                 weight: Int(f[3]) ?? 1, enabled: f[4] == "true", trans: []))
                subId += 1
                curTrans = []
            } else if raw.hasPrefix("TR") {
                let f = raw.components(separatedBy: "\t")
                guard f.count >= 7 else { continue }
                // 0:TR 1:desc 2:weight 3:enabled 4:src 5:guard 6...:targets
                let src = f[4].components(separatedBy: " ").filter { !$0.isEmpty }
                let targets = Array(f.dropFirst(6))
                curTrans.append(GTrans(id: trId, desc: f[1], weight: Int(f[2]) ?? 1,
                                       enabled: f[3] == "true", src: src,
                                       guardExpr: f[5], targets: targets))
                trId += 1
            }
        }
        flush()
        return subs
    }
}
