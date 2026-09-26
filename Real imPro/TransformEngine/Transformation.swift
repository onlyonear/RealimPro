import Foundation

extension TransformEngine {
    /// 单条匹配替换规则，新增guardCondition守卫条件
    struct Transformation {
        /// 匹配守卫表达式 nil=无条件匹配
        var guardCondition: String?
        var isEnabled: Bool
        var weight: Double
        /// 模板序列（相对音高轮廓匹配基准）
        var matchTemplate: [NoteChordPair]
        /// 每条音符对应替换表达式
        var replaceExpressions: [String]
        
        init(
            guardCondition: String? = nil,
            isEnabled: Bool = true,
            weight: Double = 1.0,
            matchTemplate: [NoteChordPair] = [],
            replaceExpressions: [String] = []
        ) {
            self.guardCondition = guardCondition
            self.isEnabled = isEnabled
            self.weight = weight
            self.matchTemplate = matchTemplate
            self.replaceExpressions = replaceExpressions
        }
        
        /// 深拷贝同步复制守卫条件
        func copy() -> Self {
            let copiedMatch = matchTemplate.map { $0.copy() }
            return Transformation(
                guardCondition: self.guardCondition,
                isEnabled: self.isEnabled,
                weight: self.weight,
                matchTemplate: copiedMatch,
                replaceExpressions: self.replaceExpressions
            )
        }
        
        // MARK: 完整原版匹配逻辑：1.长度一致 2.休止对齐 3.相对音高轮廓匹配 4.时值足够长 5.guard守卫表达式求值通过
        func matches(segment: [NoteChordPair]) -> Bool {
            guard segment.count == matchTemplate.count else { return false }
            let count = segment.count
            
            // 步骤1：休止/非休止严格对齐
            for i in 0..<count {
                let sRest = segment[i].note.midiPitch == -1
                let tRest = matchTemplate[i].note.midiPitch == -1
                guard sRest == tRest else { return false }
            }
            
            // 步骤2：相对音高轮廓匹配（模板首音为基准，相对偏移一致）
            let tFirstPitch = matchTemplate.first!.note.midiPitch
            let sFirstPitch = segment.first!.note.midiPitch
            for i in 0..<count {
                let tOff = matchTemplate[i].note.midiPitch - tFirstPitch
                let sOff = segment[i].note.midiPitch - sFirstPitch
                guard tOff == sOff else { return false }
            }
            
            // 步骤3：时值检查 - 待匹配音符的时值必须 >= 模板音符的时值
            // 避免短音符被匹配到长音符的变换规则，防止音符过密
            for i in 0..<count {
                let templateDur = matchTemplate[i].note.durationSlots
                let segmentDur = segment[i].note.durationSlots
                guard segmentDur >= templateDur else { return false }
            }
            
            // 步骤4：存在守卫条件则求值校验，返回0直接匹配失败
            guard let guardExpr = guardCondition else { return true }
            var frame = Evaluate.TransformFrame()
            // 🌟 新增：动态注入当前片段的变量 (n1, n2, n3...)
            for (idx, ncp) in segment.enumerated() {
                frame.setVar(name: "n\(idx + 1)", value: Double(ncp.note.midiPitch))
            }
            let guardVal = Evaluate.shared.evaluate(guardExpr, frame: &frame, ncp: segment.first)
            return guardVal != 0
        }
        
        // MARK: 执行替换，智能分配时值（装饰音短，主音长）
        func applyReplace(segment: [NoteChordPair], frame: inout Evaluate.TransformFrame) -> [NoteChordPair] {
            // 动态注入当前片段的变量 (n1, n2, n3...)
            for (idx, ncp) in segment.enumerated() {
                frame.setVar(name: "n\(idx + 1)", value: Double(ncp.note.midiPitch))
            }
            
            // 计算原始总时值
            let originalTotalDuration = segment.reduce(0) { $0 + $1.getDuration() }
            let matchCount = segment.count
            let replaceCount = replaceExpressions.count
            
            // 计算每个新音符的音高
            //print("=== 应用替换规则: \(replaceExpressions) ===")
            //print("原音高n1=\(segment.first?.note.midiPitch ?? 0)")
            var newPitches: [Int] = []
            for expr in replaceExpressions {
                let rawPitch = Int(Evaluate.shared.evaluate(expr, frame: &frame, ncp: segment.first))
                //print("  表达式\(expr) → 计算结果pitch=\(rawPitch)")
                let pitch = rawPitch > 20 ? rawPitch : (segment.first?.note.midiPitch ?? 60)
                newPitches.append(pitch)
            }
            //print("替换后音高数组: \(newPitches)")
            
            // 最小时值保护：30 slots = 十六分音符
            let minDuration = 30
            
            // ==========================================
            // 时值分配: 两种模式 — 均分 / 经过音(2→N)
            // 不区分邻音/波音/倚音, 全部统一均分, 避免碎片时值
            // ==========================================
            var durations: [Int] = []
            
            if matchCount >= 2 && replaceCount >= 3 {
                // 2→N: 经过音 — 从两个原音各借一点时值
                let dur1 = segment[0].getDuration()
                let dur2 = segment[1].getDuration()
                let passingDur = max(minDuration, Swift.min(dur1, dur2) / 4)
                let newDur1 = max(minDuration, dur1 - passingDur / 2)
                let newDur2 = max(minDuration, dur2 - passingDur / 2)
                let base: [Int] = [newDur1, passingDur, newDur2]
                durations = base
                // 额外替换音(>3)均分剩余
                if replaceCount > 3 {
                    let used = newDur1 + passingDur + newDur2
                    let remaining = originalTotalDuration - used
                    let extraPerDur = max(minDuration, remaining / (replaceCount - 3))
                    for _ in 3..<replaceCount { durations.append(extraPerDur) }
                }
                // 最后位吃掉余数
                let assigned = durations.dropLast().reduce(0, +)
                durations[durations.count - 1] = max(minDuration, originalTotalDuration - assigned)
                
            } else {
                // 所有1→N: 均分, 最后位吃余数
                let perDur = max(minDuration, originalTotalDuration / replaceCount)
                durations = Array(repeating: perDur, count: replaceCount)
                let assigned = durations.dropLast().reduce(0, +)
                durations[replaceCount - 1] = max(minDuration, originalTotalDuration - assigned)
            }
            
            // 构建结果
            var output: [NoteChordPair] = []
            var currentSlot = segment[0].slot  // 从第一个源音符的 slot 开始
            for idx in 0..<replaceCount {
                // 安全处理音高：-1是休止符，其他音高>=0，防止负数导致崩溃
                var safePitch = newPitches[idx]
                if safePitch < -1 {
                    safePitch = -1  // 小于-1的都视为休止符
                }
                
                let newNote = PhysicalNote(
                    midiPitch: safePitch,
                    durationSlots: durations[idx]
                )
                
                let sourceNcp = segment[min(idx, segment.count - 1)]
                let newNcp = NoteChordPair(
                    note: newNote,
                    chord: sourceNcp.chord,
                    slot: currentSlot,  // ✅ 修复：使用正确的 slot 位置
                    transformVar: sourceNcp.transformVar
                )
                output.append(newNcp)
                currentSlot += durations[idx]  // 累加当前音符的时值
            }
            
            return output
        }
    }
}
