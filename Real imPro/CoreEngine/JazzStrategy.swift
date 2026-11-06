import Foundation

// MARK: - 1. 即兴策略协议 (为未来扩展留出无限可能的算法接口)
protocol JazzImproStrategy {
    var name: String { get }
    /// 根据 Roadmap 的和弦走向，生成物理音符线
    func generateSolo(for roadmap: JazzRoadmap) -> [PhysicalNote]
}

// MARK: - 2. 纯粹、不跑调的极简引导音线条算法 (大师地基)
class GuideToneLineStrategy: JazzImproStrategy {
    let name = "Guide Tone (极简骨干线)"
    
    func generateSolo(for roadmap: JazzRoadmap) -> [PhysicalNote] {
        var finalSoloLine: [PhysicalNote] = []
        let chords = roadmap.flattenRoadmap()
        
        var lastMidiPitch = 64
        
        for chordBlock in chords {
            let chordDurationSlots = Int(Double(chordBlock.duration) * Double(JazzGuideToneEngine.slotsPerBeat))
            let chordTones = getGuideTonesForChord(chordName: chordBlock.name)
            
            var optimalPitch = lastMidiPitch
            var minDistance = 999
            
            for pitch in chordTones {
                let distance = abs(pitch - lastMidiPitch)
                if distance < minDistance {
                    minDistance = distance
                    optimalPitch = pitch
                }
            }
            
            let longNote = PhysicalNote(midiPitch: optimalPitch, durationSlots: chordDurationSlots)
            finalSoloLine.append(longNote)
            lastMidiPitch = optimalPitch
        }
        return finalSoloLine
    }
    
    private func getGuideTonesForChord(chordName: String) -> [Int] {
        let cleanName = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootPC = getRootPC(cleanName)
        
        var thirdInterval = 4
        if cleanName.contains("m") && !cleanName.contains("maj") { thirdInterval = 3 }
        if cleanName.contains("dim") || cleanName.contains("ø") { thirdInterval = 3 }
        
        var seventhInterval = 10
        if cleanName.contains("maj") || cleanName.contains("M7") { seventhInterval = 11 }
        if cleanName.contains("dim") && !cleanName.contains("ø") { seventhInterval = 9 }
        
        let thirdPC = (rootPC + thirdInterval) % 12
        let seventhPC = (rootPC + seventhInterval) % 12
        
        var validPitches: [Int] = []
        for octave in [48, 60, 72] {
            let tPitch = thirdPC + octave
            let sPitch = seventhPC + octave
            if tPitch >= 55 && tPitch <= 79 { validPitches.append(tPitch) }
            if sPitch >= 55 && sPitch <= 79 { validPitches.append(sPitch) }
        }
        return validPitches.isEmpty ? [60] : validPitches
    }
    
    private func getRootPC(_ name: String) -> Int {
        let chars = Array(name)
        guard !chars.isEmpty else { return 0 }
        var rootStr = String(chars[0]).uppercased()
        if chars.count > 1 && (chars[1] == "#" || chars[1] == "b") { rootStr.append(chars[1]) }
        let pcMap: [String: Int] = ["C": 0, "C#": 1, "Db": 1, "D": 2, "Eb": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "Ab": 8, "A": 9, "Bb": 10, "B": 11]
        return pcMap[rootStr] ?? 0
    }
}

// MARK: - 3. 爵士标准二分律动 (贪心算法，仅限 3/7 音)
class TwoFeelGuideToneStrategy: JazzImproStrategy {
    let name = "Two-Feel Guide Tone (3/7音交替线)"
    
    func generateSolo(for roadmap: JazzRoadmap) -> [PhysicalNote] {
        var finalSoloLine: [PhysicalNote] = []
        let chords = roadmap.flattenRoadmap()
        var lastMidiPitch = 64
        
        for chordBlock in chords {
            let chordDurationSlots = Int(Double(chordBlock.duration) * Double(JazzGuideToneEngine.slotsPerBeat))
            let halfDuration = chordDurationSlots / 2
            
            let thirdPitches = getSpecificGuideTones(chordName: chordBlock.name, isThird: true)
            let seventhPitches = getSpecificGuideTones(chordName: chordBlock.name, isThird: false)
            
            let bestThirdA = getClosestPitch(targetPitches: thirdPitches, referencePitch: lastMidiPitch)
            let bestSeventhA = getClosestPitch(targetPitches: seventhPitches, referencePitch: bestThirdA)
            let costA = abs(bestThirdA - lastMidiPitch) + abs(bestSeventhA - bestThirdA)
            
            let bestSeventhB = getClosestPitch(targetPitches: seventhPitches, referencePitch: lastMidiPitch)
            let bestThirdB = getClosestPitch(targetPitches: thirdPitches, referencePitch: bestSeventhB)
            let costB = abs(bestSeventhB - lastMidiPitch) + abs(bestThirdB - bestSeventhB)
            
            var note1Pitch = 0
            var note2Pitch = 0
            
            if costA <= costB {
                note1Pitch = bestThirdA
                note2Pitch = bestSeventhA
            } else {
                note1Pitch = bestSeventhB
                note2Pitch = bestThirdB
            }
            
            finalSoloLine.append(PhysicalNote(midiPitch: note1Pitch, durationSlots: halfDuration))
            finalSoloLine.append(PhysicalNote(midiPitch: note2Pitch, durationSlots: chordDurationSlots - halfDuration))
            lastMidiPitch = note2Pitch
        }
        return finalSoloLine
    }
    
    private func getSpecificGuideTones(chordName: String, isThird: Bool) -> [Int] {
        let cleanName = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootPC = getRootPC(cleanName)
        
        var interval = 0
        if isThird {
            interval = 4
            if cleanName.contains("m") && !cleanName.contains("maj") { interval = 3 }
            if cleanName.contains("dim") || cleanName.contains("ø") { interval = 3 }
        } else {
            interval = 10
            if cleanName.contains("maj") || cleanName.contains("M7") { interval = 11 }
            if cleanName.contains("dim") && !cleanName.contains("ø") { interval = 9 }
        }
        
        let targetPC = (rootPC + interval) % 12
        var validPitches: [Int] = []
        for octave in [48, 60, 72] {
            let pitch = targetPC + octave
            if pitch >= 55 && pitch <= 79 { validPitches.append(pitch) }
        }
        return validPitches.isEmpty ? [60] : validPitches
    }
    
    private func getClosestPitch(targetPitches: [Int], referencePitch: Int) -> Int {
        var bestPitch = referencePitch
        var minDistance = 999
        for pitch in targetPitches {
            let dist = abs(pitch - referencePitch)
            if dist < minDistance {
                minDistance = dist
                bestPitch = pitch
            }
        }
        return bestPitch
    }
    
    private func getRootPC(_ name: String) -> Int {
        let chars = Array(name)
        guard !chars.isEmpty else { return 0 }
        var rootStr = String(chars[0]).uppercased()
        if chars.count > 1 && (chars[1] == "#" || chars[1] == "b") { rootStr.append(chars[1]) }
        let pcMap: [String: Int] = ["C": 0, "C#": 1, "Db": 1, "D": 2, "Eb": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "Ab": 8, "A": 9, "Bb": 10, "B": 11]
        return pcMap[rootStr] ?? 0
    }
}

// MARK: - 4. 🏆 全局动态规划最优声部算法 
class GlobalOptimalGuideToneStrategy: JazzImproStrategy {
    let name = "Global Optimal Two-Feel (全局动态规划 1,3,5,7)"
    
    // DP 的状态节点
    struct DPState {
        let cost: Int
        let prevPitch: Int?
    }
    
    func generateSolo(for roadmap: JazzRoadmap) -> [PhysicalNote] {
        let chords = roadmap.flattenRoadmap()
        guard !chords.isEmpty else { return [] }
        
        // 1. 构建候选池网格 (每一拍有哪些可以踩的合法石头)
        var stepsCandidates: [[Int]] = []
        var durationMapping: [Int] = [] // 记录每一步的物理时值
        
        for chord in chords {
            let chordDurationSlots = Int(Double(chord.duration) * Double(JazzGuideToneEngine.slotsPerBeat))
            let halfDuration = chordDurationSlots / 2
            
            // 将候选池扩大到 [1音, 3音, 5音, 7音]
            let pitches = getAllChordTones(chordName: chord.name)
            
            // 强拍和次强拍都放入相同的候选池
            stepsCandidates.append(pitches)
            stepsCandidates.append(pitches)
            durationMapping.append(halfDuration)
            durationMapping.append(chordDurationSlots - halfDuration)
        }
        
        let totalSteps = stepsCandidates.count
        // DP 矩阵: dp[步数][当前音高] = 抵达这个状态的最小跳动代价及上一步音高
        var dp: [[Int: DPState]] = Array(repeating: [:], count: totalSteps)
        
        // 2. 初始化第 0 步 (起点)
        for pitch in stepsCandidates[0] {
            // 给起点一个轻微的惩罚，鼓励它从靠近中央 C (60) 的地方起跑
            let initialCost = abs(pitch - 60)
            dp[0][pitch] = DPState(cost: initialCost, prevPitch: nil)
        }
        
        // 3. 向前推进，计算全局最短路径 (Viterbi 算法核心)
        for i in 1..<totalSteps {
            let currentPitches = stepsCandidates[i]
            let prevPitches = stepsCandidates[i-1]
            
            // 🌟 核心修复：判断当前这一步，是在同一个和弦内移动，还是跨越到下一个新和弦？
            // 我们每小节切了 2 步，所以当 i 是奇数时，是同和弦内移动；偶数时，是跨和弦连接。
            let isSameChord = (i % 2 != 0)
            
            for currentPitch in currentPitches {
                var minCost = Int.max
                var bestPrevPitch: Int? = nil
                
                for prevPitch in prevPitches {
                    guard let prevState = dp[i-1][prevPitch] else { continue }
                    
                    let transitionCost = abs(currentPitch - prevPitch)
                    var penalty = 0
                    
                    if isSameChord {
                        // 【同一个和弦内部的游走】
                        if transitionCost == 0 {
                            penalty += 100 // 绝不原地踏步
                        }
                        if transitionCost > 12 {
                            penalty += transitionCost * 2
                        }
                    } else {
                        // 【跨越到下一个新和弦】
                        // 🌟 核心修复：跨小节绝对不能弹同音！会摧毁和弦交替的推动力
                        if transitionCost == 0 {
                            penalty += 80 // 跨小节同音是单线条/贝斯的灾难，重罚！
                        } else if transitionCost <= 2 {
                            penalty -= 10 // 半音/全音趋近（最完美的爵士粘合剂，如 7降3），重赏！
                        } else if transitionCost == 5 || transitionCost == 7 {
                            penalty -= 5  // 四度/五度跳跃（如 G7 -> Cmaj7 的根音进行），非常稳健，奖励！
                        } else if transitionCost > 5 {
                            penalty += (transitionCost * 3) // 其他无意义的大跳依然要克制
                        }
                    }
                    
                    let totalCost = prevState.cost + transitionCost + penalty
                    
                    if totalCost < minCost {
                        minCost = totalCost
                        bestPrevPitch = prevPitch
                    }
                }
                dp[i][currentPitch] = DPState(cost: minCost, prevPitch: bestPrevPitch)
            }
        }
        
        // 4. 从终点回溯寻找全局最优路径
        var bestFinalPitch = -1
        var minFinalCost = Int.max
        for (pitch, state) in dp[totalSteps - 1] {
            if state.cost < minFinalCost {
                minFinalCost = state.cost
                bestFinalPitch = pitch
            }
        }
        
        var optimalPath: [Int] = []
        var currentPitch = bestFinalPitch
        for i in stride(from: totalSteps - 1, through: 1, by: -1) {
            optimalPath.append(currentPitch)
            currentPitch = dp[i][currentPitch]!.prevPitch!
        }
        optimalPath.append(currentPitch) // 塞入第0步
        optimalPath.reverse()
        
        // 5. 将最优音高路径打包为物理音符序列
        var finalSoloLine: [PhysicalNote] = []
        for i in 0..<totalSteps {
            finalSoloLine.append(PhysicalNote(midiPitch: optimalPath[i], durationSlots: durationMapping[i]))
        }
        
        return finalSoloLine
    }
    
    // 获取和弦完整的 1, 3, 5, 7 物理音高集合
    private func getAllChordTones(chordName: String) -> [Int] {
        let cleanName = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootPC = getRootPC(cleanName)
        
        var thirdInt = 4
        if cleanName.contains("m") && !cleanName.contains("maj") { thirdInt = 3 }
        if cleanName.contains("dim") || cleanName.contains("ø") { thirdInt = 3 }
        
        var fifthInt = 7
        if cleanName.contains("dim") || cleanName.contains("ø") || cleanName.contains("b5") { fifthInt = 6 }
        if cleanName.contains("aug") || cleanName.contains("+") || cleanName.contains("#5") { fifthInt = 8 }
        
        var seventhInt = 10
        if cleanName.contains("maj") || cleanName.contains("M7") || cleanName.contains("▲") { seventhInt = 11 }
        if cleanName.contains("dim7") || cleanName.contains("o7") { seventhInt = 9 }
        if cleanName.contains("6") && !cleanName.contains("7") { seventhInt = 9 } // 6和弦给9
        
        let intervals = [0, thirdInt, fifthInt, seventhInt]
        var validPitches: [Int] = []
        
        for interval in intervals {
            let targetPC = (rootPC + interval) % 12
            // 限制在萨克斯/钢琴极度舒适的中央音区 (MIDI 53(F3) 到 77(F5))，保证旋律线不飘
            for octave in [48, 60, 72] {
                let pitch = targetPC + octave
                if pitch >= 53 && pitch <= 77 {
                    validPitches.append(pitch)
                }
            }
        }
        return validPitches.isEmpty ? [60] : validPitches.sorted()
    }
    
    private func getRootPC(_ name: String) -> Int {
        let chars = Array(name)
        guard !chars.isEmpty else { return 0 }
        var rootStr = String(chars[0]).uppercased()
        if chars.count > 1 && (chars[1] == "#" || chars[1] == "b") { rootStr.append(chars[1]) }
        let pcMap: [String: Int] = ["C": 0, "C#": 1, "Db": 1, "D": 2, "Eb": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "Ab": 8, "A": 9, "Bb": 10, "B": 11]
        return pcMap[rootStr] ?? 0
    }
}
