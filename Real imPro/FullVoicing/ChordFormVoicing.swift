import Foundation

// MARK: - 给定规范形式名 + 根音, 产出候选 voicing（对齐 ChordForm.getVoicings / generateVoicings）
enum ChordFormVoicing {

    /// 词库模板候选: 按 type 过滤 + 按 root 转调。对齐 ChordForm.getVoicings(root,key,type) L976。
    /// - requestType: .open/.closed/.all(any 通配, 不过滤)
    static func libraryCandidates(form: String, rootRise: Int, requestType: JazzVoicingType) -> [VoicingPlacer.Candidate] {
        guard let fv = JazzVoicingTemplates.byForm[form] else { return [] }
        var out: [VoicingPlacer.Candidate] = []
        for t in fv.templates {
            // Java: type 非 any 且模板 type 不匹配 -> 跳过 (all/shout 在请求 open 时同样被跳过)
            if requestType != .all && t.type != requestType { continue }
            out.append(VoicingPlacer.Candidate(
                notes: VoicingPlacer.transpose(t.notes, rootRise),
                ext:   VoicingPlacer.transpose(t.ext, rootRise)))
        }
        return out
    }

    /// 兜底: priority 去根音 -> 取前5 -> 全排列 -> 单调化。对齐 ChordForm.generateVoicings L870。
    static func generatedCandidates(form: String, rootRise: Int) -> [VoicingPlacer.Candidate] {
        guard let fv = JazzVoicingTemplates.byForm[form] else { return [] }
        let rootPc = ((rootRise % 12) + 12) % 12
        // priority 转 root, enhDrop 去掉与根音等音(pc 相同)者, 保序
        var spell = fv.priority.map { $0 + rootRise }.filter { (($0 % 12) + 12) % 12 != rootPc }
        spell = Array(spell.prefix(5))                       // PRIORITY_PREFIX_MAX = 5
        return permutations(spell).map { VoicingPlacer.Candidate(notes: monotonize($0), ext: []) }
    }

    /// 排列单调化: 保留首音, 后续音若低于前一音则逐八度抬到 >= 前一音。对齐 L909-921。
    private static func monotonize(_ p: [Int]) -> [Int] {
        guard var last = p.first else { return p }
        var v = p
        for i in 1..<v.count {
            while v[i] < last { v[i] += 12 }
            last = v[i]
        }
        return v
    }

    /// 逐字对应 ChordForm.permutations (Polylist cons/reverse 语义):
    /// newList.reverse().cons(x).reverse() 净效果 = 末尾 append; permutes.cons 头插 = insert(at:0)。
    static func permutations(_ L: [Int]) -> [[Int]] {
        if L.isEmpty { return [] }
        if L.count == 1 { return [L] }
        let first = L[0]
        let rest = permutations(Array(L.dropFirst()))
        var permutes: [[Int]] = []
        for list in rest {
            for j in 0...list.count {
                var newList: [Int] = []
                for k in 0..<j { newList.append(list[k]) }
                newList.append(first)
                for k in (j + 1)..<(list.count + 1) { newList.append(list[k - 1]) }   // 半开区间: j=count 时零次执行, 对齐 Java for
                permutes.insert(newList, at: 0)   // cons 头插, 顺序必须与 Java 一致
            }
        }
        return permutes
    }
}
