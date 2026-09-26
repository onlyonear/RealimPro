import Foundation

// MARK: - 方向常量（严格对齐 Java GuideLineGenerator）
private enum GuideToneDirection {
    static let noPreference = 0
    static let ascending = 1
    static let descending = -1
}

// MARK: - P1-2 线条走向枚举 (消除 ASCENDING/DESCENDING 未定义报错)
enum LineDirection {
    case ascending, descending
}
private let ASCENDING  = GuideToneDirection.ascending
private let DESCENDING = GuideToneDirection.descending

// MARK: - 音程常量
private enum Interval {
    static let same = 0
    static let halfStep = 1
    static let wholeStep = 2
    static let min3rd = 3
    static let maj3rd = 4
    static let tritone = 6
    static let octave = 12
}

// MARK: 贪心引导音策略
class ImproVisorOriginalGuideToneStrategy: JazzImproStrategy {
    let name = "贪心引导音线"
    
    // MARK: - 常量
    private let middleOfRange = 60      // 音域中心点 MIDI
    var lowLimit: Int = 40              // 音域下限 MIDI（可配置）
    var highLimit: Int = 84             // 音域上限 MIDI（可配置）
    private let boundaryThreshold = 1   // 边界反向阈值：半音以内触发反向
    
    // 🌟 分级距离评分表：[同音, 半音, 全音, 小三度, 大三度, 三全音及以上]
    private let distanceScores = [1, 1, 1, 2, 2, 3]
    
    // 🌟 方向评分矩阵
    // 行索引 = 方向偏好 + 1（descending→0, noPreference→1, ascending→2）
    // 列索引 = 实际移动方向（down→0, same→1, up→2）
    private let directionScores: [[Int]] = [
        [0, 0, 1],  // descending：下行好(0)，同音(0)，上行不好(1)
        [0, 0, 0],  // noPreference：都可以
        [1, 0, 0]   // ascending：上行好(0)，同音(0)，下行不好(1)
    ]
    
    // MARK: - 配置参数
    var direction: Int = GuideToneDirection.noPreference
    var startDegree: String = "3"       // 起始音级：1, 3, 5, 7
    var maxDuration: Int = 240          // 最大音符时长（slots），默认 2拍 = 二分音符
    var allowColor: Bool = false        // 是否允许色彩音
    var alwaysDisallowSame: Bool = false // 是否始终禁止同音重复
    var contour: String? = nil          // 轮廓控制字符串（1=上, 0=下）
    
    // 🌟 保存用户原始方向偏好，每个段落开始时重置
    private var originalDirection: Int = GuideToneDirection.noPreference
    
    // MARK: - JazzImproStrategy 协议实现
    func generateSolo(for roadmap: JazzRoadmap) -> [PhysicalNote] {
        let chords = roadmap.flattenRoadmap()
        guard !chords.isEmpty else { return [] }
        
        // 转换为内部和弦信息格式
        let chordInfos = chords.map { ChordInfo(name: $0.name, durationSlots: Int(Double($0.duration) * Double(JazzGuideToneEngine.slotsPerBeat)), isSectionStart: $0.isSectionStart) }
        
        // 调用核心算法
        return makeGuideLine(chordInfos: chordInfos)
    }
    
    // MARK: - 🌟 核心入口：makeGuideLine
    private func makeGuideLine(chordInfos: [ChordInfo]) -> [PhysicalNote] {
        // 🌟 保存用户原始方向，每个段落开始时重置（与一致）
        originalDirection = direction
        return oneGuideLine(chordInfos: chordInfos, startDegree: startDegree)
    }
    
    // MARK: - 单线生成：oneGuideLine（核心算法）
    /// 🌟 与原版完全一致：每个段落开始时重置方向，重新生成首音
    private func oneGuideLine(chordInfos: [ChordInfo], startDegree: String) -> [PhysicalNote] {
        var result: [PhysicalNote] = []
        var currentDirection = direction
        var lastPitch: Int? = nil
        
        for (i, chord) in chordInfos.enumerated() {
            // 🌟 判断是否是段落开始（第一个和弦也是段落开始）
            let isSectionStart = chord.isSectionStart || i == 0
            
            // 🌟 段落开始：重置方向为用户原始方向，重新生成首音
            if isSectionStart {
                currentDirection = originalDirection
                let first = firstNote(chord: chord, startDegree: startDegree, currentDirection: currentDirection)
                lastPitch = first
            }
            
            // 轮廓模式覆盖方向（在生成音符之前）
            if let contour = contour, i < contour.count {
                let contourChar = Array(contour)[i]
                currentDirection = (contourChar == "1") ? GuideToneDirection.ascending : GuideToneDirection.descending
            }
            
            // 生成当前和弦的音符（可能被分割成多段）
            let notes: [PhysicalNote]
            if isSectionStart {
                // 🌟 段落开始：强制使用 firstNote 的结果作为第一个音（与原版一致）
                let (firstNotes, finalDir) = notesToAdd(chord: chord, lastPitch: lastPitch!, currentDirection: currentDirection, firstSegmentPitch: lastPitch!)
                // 直接覆盖第一个音的音高，确保是 firstNote 的结果
                var adjustedNotes = firstNotes
                if !adjustedNotes.isEmpty {
                    let firstNotePitch = lastPitch!
                    adjustedNotes[0] = PhysicalNote(
                        midiPitch: firstNotePitch,
                        durationSlots: adjustedNotes[0].durationSlots
                    )
                    if i == 0 {
                        #if DEBUG
                        print("✅ 乐曲开始首音: \(midiToNoteName(firstNotePitch)) (MIDI \(firstNotePitch))")
                        #endif
                    } else {
                        #if DEBUG
                        print("✅ 段落开始首音: \(midiToNoteName(firstNotePitch)) (MIDI \(firstNotePitch))")
                        #endif
                    }
                }
                notes = adjustedNotes
                currentDirection = finalDir
            } else {
                // 非段落开始：正常生成
                let (generatedNotes, finalDir) = notesToAdd(chord: chord, lastPitch: lastPitch!, currentDirection: currentDirection)
                notes = generatedNotes
                currentDirection = finalDir
            }
            result.append(contentsOf: notes)
            
            // 更新 lastPitch 为最后一个音
            if let last = notes.last {
                lastPitch = last.midiPitch
            }
        }
        
        return result
    }

    // MARK: - P1-2 双线导音 twoGuideLine ( /\/\ 波浪交替)

    /// 双波浪交替导音: 每个和弦生成两个音, 交替线条
    /// - Parameters:
    ///   - chordInfos: 和弦序列
    ///   - startDegree1: 线1起始音级
    ///   - startDegree2: 线2起始音级
    ///   - alternating: true=/\/\交替, false=////同向双层
    func twoGuideLine(chordInfos: [ChordInfo],
                      startDegree1: String = "3",
                      startDegree2: String = "7",
                      alternating: Bool = true) -> [PhysicalNote] {
        var result: [PhysicalNote] = []
        var dir1 = direction
        var dir2 = direction
        var lastPitch1: Int? = nil
        var lastPitch2: Int? = nil
        var currentLine = 1  // 1=线1, 2=线2

        for (i, chord) in chordInfos.enumerated() {
            let isSectionStart = chord.isSectionStart || i == 0

            if isSectionStart {
                dir1 = originalDirection; dir2 = originalDirection
                lastPitch1 = firstNote(chord: chord, startDegree: startDegree1, currentDirection: dir1)
                lastPitch2 = firstNote(chord: chord, startDegree: startDegree2, currentDirection: dir2)
            }

            if let contour = contour, i < contour.count {
                let c = Array(contour)[i]
                dir1 = (c == "1") ? ASCENDING : DESCENDING
                if alternating { dir2 = (c == "1") ? DESCENDING : ASCENDING }
                else { dir2 = dir1 }
            }

            // 交替输出: 每小节内线1→线2交替
            if currentLine == 1, let p1 = lastPitch1 {
                let (notes, finalDir) = notesToAdd(chord: chord, lastPitch: p1, currentDirection: dir1)
                result.append(contentsOf: notes); dir1 = finalDir
                if let last = notes.last { lastPitch1 = last.midiPitch }
                currentLine = 2
            } else if currentLine == 2, let p2 = lastPitch2 {
                let (notes, finalDir) = notesToAdd(chord: chord, lastPitch: p2, currentDirection: dir2)
                result.append(contentsOf: notes); dir2 = finalDir
                if let last = notes.last { lastPitch2 = last.midiPitch }
                currentLine = 1
            }
        }
        return result
    }
    
    // MARK: - 首音生成：firstNote
    /// 🌟 ：先尝试指定度数，验证失败则降级为最高优先级音
    private func firstNote(chord: ChordInfo, startDegree: String, currentDirection: Int) -> Int {
        let chordTones = getChordTones(chord: chord)
        
        // 尝试找指定度数的音
        let degreeIndex = degreeToIndex(startDegree)
        if degreeIndex >= 0 && degreeIndex < chordTones.count {
            let pc = chordTones[degreeIndex]
            return closestToMiddle(pitchClass: pc, direction: currentDirection)
        }
        
        // 降级：用最高优先级的和弦音（即第一个，因为 getChordTones 按优先级排序）
        guard let firstPc = chordTones.first else { return middleOfRange }
        return closestToMiddle(pitchClass: firstPc, direction: currentDirection)
    }
    
    // MARK: - 找离中间最近的八度：closestToMiddle
    /// 在音域范围内寻找离 middleOfRange 最近的目标音（确保音级正确）
    private func closestToMiddle(pitchClass: Int, direction: Int) -> Int {
        let pc = pitchClass % 12
        
        // 从中间往下找（不低于 lowLimit）
        var below: Int? = nil
        var pitch = middleOfRange
        while pitch >= lowLimit {
            if pitch % 12 == pc {
                below = pitch
                break
            }
            pitch -= 1
        }
        
        // 从中间往上找（不高于 highLimit）
        var above: Int? = nil
        pitch = middleOfRange
        while pitch <= highLimit {
            if pitch % 12 == pc {
                above = pitch
                break
            }
            pitch += 1
        }
        
        // 根据找到的结果选择最合适的
        switch (below, above) {
        case (let b?, let a?):
            // 上下都找到了，按方向偏好选择
            if direction == GuideToneDirection.ascending {
                return b  // 上行偏好：选低的，方便往上走
            } else if direction == GuideToneDirection.descending {
                return a  // 下行偏好：选高的，方便往下走
            } else {
                // 无偏好：选离中间更近的
                let distBelow = middleOfRange - b
                let distAbove = a - middleOfRange
                return distBelow <= distAbove ? b : a
            }
        case (let b?, nil):
            return b  // 只有下方有
        case (nil, let a?):
            return a  // 只有上方有
        case (nil, nil):
            // 音域范围内完全没有这个音级（极端窄音域才会出现）
            // 降级：返回离中间更近的边界音
            return abs(middleOfRange - lowLimit) <= abs(highLimit - middleOfRange) ? lowLimit : highLimit
        }
    }
    
    private func closestBelowMiddle(pitchClass: Int) -> Int {
        var pitch = middleOfRange
        while pitch % 12 != pitchClass % 12 {
            pitch -= 1
        }
        return max(pitch, lowLimit)
    }
    
    private func closestAboveMiddle(pitchClass: Int) -> Int {
        var pitch = middleOfRange
        while pitch % 12 != pitchClass % 12 {
            pitch += 1
        }
        return min(pitch, highLimit)
    }
    
    // MARK: - 后续音生成：nextNote（贪心核心）
    private func nextNote(chord: ChordInfo, lastPitch: Int, currentDirection: Int, disallowSame: Bool) -> Int {
        let candidates = closestChordTones(chord: chord, lastPitch: lastPitch)
        return bestNote(candidates: candidates, chord: chord, lastPitch: lastPitch, currentDirection: currentDirection, disallowSame: disallowSame)
    }
    
    // MARK: - 找最近的和弦音：closestChordTones
    private func closestChordTones(chord: ChordInfo, lastPitch: Int) -> [Int] {
        let chordTones = getChordTones(chord: chord)
        return chordTones.map { getClosest(pitchClass: $0, lastPitch: lastPitch, direction: direction) }
    }
    
    // MARK: - 🌟 找最近八度的音：getClosest（核心逻辑）
    /// 注意：每个和弦音只返回 1 个候选（最近的那个八度），不是两个！
    private func getClosest(pitchClass: Int, lastPitch: Int, direction: Int) -> Int {
        let pc = pitchClass % 12
        let lastPc = lastPitch % 12
        
        // 计算上行和下行的距离
        var distUp = (pc - lastPc + 12) % 12
        var distDown = (lastPc - pc + 12) % 12
        
        // 处理同音情况
        if distUp == 0 {
            distUp = 12
            distDown = 12
        }
        
        var resultPitch: Int
        
        if distUp < distDown {
            // 上行更近
            resultPitch = lastPitch + distUp
        } else if distDown < distUp {
            // 下行更近
            resultPitch = lastPitch - distDown
        } else {
            // 三全音平局：用方向偏好打破
            if direction == GuideToneDirection.ascending {
                resultPitch = lastPitch + distUp
            } else if direction == GuideToneDirection.descending {
                resultPitch = lastPitch - distDown
            } else {
                // 无偏好时默认向上（原版行为）
                resultPitch = lastPitch + distUp
            }
        }
        
        // 超出音域则移八度
        while resultPitch < lowLimit {
            resultPitch += 12
        }
        while resultPitch > highLimit {
            resultPitch -= 12
        }
        
        return resultPitch
    }
    
    // MARK: - 选最优音：bestNote
    /// 🌟 与完全一致：先按总分排序，分数相同按和弦音优先级排序
    private func bestNote(candidates: [Int], chord: ChordInfo, lastPitch: Int, currentDirection: Int, disallowSame: Bool) -> Int {
        var bestPitch = candidates[0]
        var minScore = Int.max
        var minPriority = Int.max
        
        for pitch in candidates {
            let totalScore = score(pitch: pitch, lastPitch: lastPitch, currentDirection: currentDirection, disallowSame: disallowSame)
            let priority = priorityIndex(of: pitch, chord: chord)
            
            // 分数更低 → 更好
            // 分数相同 → 优先级更高（数值更小）更好
            if totalScore < minScore || (totalScore == minScore && priority < minPriority) {
                minScore = totalScore
                minPriority = priority
                bestPitch = pitch
            }
        }
        
        return bestPitch
    }
    
    // MARK: - 评分：score
    /// 🌟 与完全一致：distanceScore + directionScore
    private func score(pitch: Int, lastPitch: Int, currentDirection: Int, disallowSame: Bool) -> Int {
        return distanceScore(pitch: pitch, lastPitch: lastPitch, disallowSame: disallowSame) + directionScore(pitch: pitch, lastPitch: lastPitch, currentDirection: currentDirection)
    }
    
    // MARK: - 距离分：distanceScore
    /// 🌟 与完全一致：同音时如果 disallowSame 则返回 Int.max（最差）
    private func distanceScore(pitch: Int, lastPitch: Int, disallowSame: Bool = false) -> Int {
        let interval = abs(pitch - lastPitch)
        
        // 同音时：如果禁止同音或全局禁止同音，返回最大分值
        if interval == 0 {
            if disallowSame || alwaysDisallowSame {
                return Int.max
            }
        }
        
        let lastIndex = distanceScores.count - 1
        if interval <= lastIndex && interval >= 0 {
            return distanceScores[interval]
        } else {
            // 超出数组范围，用最后一个值（三全音及以上同一档）
            return distanceScores[lastIndex]
        }
    }
    
    // MARK: - 方向分：directionScore
    /// 🌟 与原版完全一致：根据方向偏好和实际移动方向查表评分
    private func directionScore(pitch: Int, lastPitch: Int, currentDirection: Int) -> Int {
        // 计算实际移动方向：-1=下行, 0=同音, 1=上行
        let movementDirection: Int
        if pitch > lastPitch {
            movementDirection = 1      // 上行
        } else if pitch < lastPitch {
            movementDirection = -1     // 下行
        } else {
            movementDirection = 0      // 同音
        }
        
        // 方向偏好：-1=下行偏好, 0=无偏好, 1=上行偏好
        let preference = currentDirection
        
        // 查表（与原版完全一致的索引方式）
        // 行：preference + 1（把 -1/0/1 映射到 0/1/2）
        // 列：movementDirection + 1（把 -1/0/1 映射到 0/1/2）
        return directionScores[preference + 1][movementDirection + 1]
    }
    
    // MARK: - 边界反向检测：possibleDirectionSwitch
    private func possibleDirectionSwitch(lastPitch: Int, currentDir: Int) -> (switched: Bool, newDirection: Int) {
        if lastPitch >= highLimit - boundaryThreshold {
            // 碰到上边界，强制下行
            return (true, GuideToneDirection.descending)
        } else if lastPitch <= lowLimit + boundaryThreshold {
            // 碰到下边界，强制上行
            return (true, GuideToneDirection.ascending)
        }
        return (false, currentDir)
    }
    
    // MARK: - 时长分割：notesToAdd
    /// 🌟 与原版完全一致：每个分割音后都检查是否需要切换方向
    private func notesToAdd(chord: ChordInfo, lastPitch: Int, currentDirection: Int, firstSegmentPitch: Int? = nil) -> (notes: [PhysicalNote], finalDirection: Int) {
        var result: [PhysicalNote] = []
        var remainingSlots = chord.durationSlots
        var currentPitch = lastPitch
        var dir = currentDirection
        var isFirstSegment = true
        
        while remainingSlots > 0 {
            let segmentDuration: Int
            if maxDuration > 0 && remainingSlots > maxDuration {
                segmentDuration = maxDuration
            } else {
                segmentDuration = remainingSlots
            }
            
            // 计算这个分段的音高
            let pitch: Int
            if isFirstSegment && firstSegmentPitch != nil {
                // 第一段：直接使用传入的起始音（firstNote 的结果）
                pitch = firstSegmentPitch!
                currentPitch = pitch
            } else if isFirstSegment {
                // 第一段：用 nextNote 计算
                let disallow = alwaysDisallowSame
                pitch = nextNote(chord: chord, lastPitch: currentPitch, currentDirection: dir, disallowSame: disallow)
                currentPitch = pitch
            } else {
                // 后续段：强制禁止同音
                pitch = nextNote(chord: chord, lastPitch: currentPitch, currentDirection: dir, disallowSame: true)
                currentPitch = pitch
            }
            
            result.append(PhysicalNote(midiPitch: pitch, durationSlots: segmentDuration))
            remainingSlots -= segmentDuration
            isFirstSegment = false
            
            // 🌟 每个音后都检查是否需要切换方向（与原版一致）
            let (switched, newDir) = possibleDirectionSwitch(lastPitch: pitch, currentDir: dir)
            if switched {
                dir = newDir
            }
        }
        
        return (result, dir)
    }
    
    // MARK: - 获取和弦音：getChordTones
    /// 🌟 按优先级顺序返回：3音 > 7音 > 5音 > 根音 > 9音 > 13音 > 11音
    /// 与 chord.getPriority() 顺序一致
    private func getChordTones(chord: ChordInfo) -> [Int] {
        let rootPC = parseRootPitchClass(chord.name)
        var tones: [Int] = []
        
        // 判断和弦类型
        let name = chord.name
        let isMinor = name.contains("m") && !name.contains("maj") && !name.contains("M7") ||
                      name.contains("dim") || name.contains("ø")
        let isSus = name.contains("sus")
        let isSus2 = name.contains("sus2")
        let isSus4 = isSus && !isSus2  // sus 默认是 sus4
        let isMaj7 = name.contains("maj") || name.contains("M7") || name.contains("▲")
        let isDim7 = name.contains("dim7") || name.contains("o7")
        let isHalfDim = name.contains("ø") || name.contains("m7b5")
        let isAug = name.contains("aug") || name.contains("+")
        let isAlt = name.contains("alt")
        let isDom7 = !isMaj7 && !isDim7 && !isHalfDim && (name.contains("7") || isSus || isAlt)
        
        // 三音（优先级最高，最重要的引导音）
        // sus 和弦：三音被四度或二度替代
        if isSus2 {
            tones.append((rootPC + 2) % 12)  // sus2：大二度替代三音
        } else if isSus4 {
            tones.append((rootPC + 5) % 12)  // sus4：纯四度替代三音
        } else {
            let thirdInterval = isMinor ? 3 : 4
            tones.append((rootPC + thirdInterval) % 12)
        }
        
        // 七音（第二重要的引导音）
        // sus 和弦默认是属七（小七度），除非明确写了 maj7
        var seventhInterval: Int
        if isMaj7 {
            seventhInterval = 11  // 大七度
        } else if isDim7 {
            seventhInterval = 9   // 减七度
        } else if isHalfDim {
            seventhInterval = 10  // 小七度（半减七 = m7b5）
        } else if isDom7 || isSus || isAlt {
            seventhInterval = 10  // 小七度（属七）
        } else {
            // 三和弦：没有七音，但为了引导音线，我们还是加一个（默认属七）
            seventhInterval = 10
        }
        tones.append((rootPC + seventhInterval) % 12)
        
        // 五音
        var fifthInterval = 7
        if name.contains("dim") || name.contains("b5") || name.contains("ø") {
            fifthInterval = 6  // 减五度
        }
        if isAug || name.contains("#5") || name.contains("+5") {
            fifthInterval = 8  // 增五度
        }
        if isAlt {
            // alt 和弦默认 #5（常见变化）
            fifthInterval = 8
        }
        tones.append((rootPC + fifthInterval) % 12)
        
        // 根音（优先级最低的和弦音）
        tones.append(rootPC % 12)
        
        // 色彩音（按优先级：9 > 13 > 11）
        if allowColor {
            // 九音
            if name.contains("9") || isAlt || name.contains("add9") {
                var ninthInterval = 2
                if name.contains("b9") || isAlt {
                    ninthInterval = 1  // b9
                }
                if name.contains("#9") {
                    ninthInterval = 3  // #9
                }
                tones.append((rootPC + ninthInterval) % 12)
            }
            
            // 十三音
            if name.contains("13") || isAlt {
                var thirteenthInterval = 9
                if name.contains("b13") {
                    thirteenthInterval = 8  // b13
                }
                if name.contains("#13") {
                    thirteenthInterval = 10 // #13
                }
                tones.append((rootPC + thirteenthInterval) % 12)
            }
            
            // 十一音
            if name.contains("11") || name.contains("add11") {
                var eleventhInterval = 5
                if name.contains("#11") {
                    eleventhInterval = 6  // #11
                }
                tones.append((rootPC + eleventhInterval) % 12)
            }
        }
        
        return tones
    }
    
    // MARK: - 度数转索引（对应 getChordTones 的优先级顺序）
    private func degreeToIndex(_ degree: String) -> Int {
        switch degree {
        case "3": return 0      // 三音，优先级最高
        case "7": return 1      // 七音，第二优先级
        case "5": return 2      // 五音，第三优先级
        case "1", "R": return 3 // 根音，第四优先级
        case "9": return 4      // 九音，色彩音
        case "13": return 5     // 十三音，色彩音
        case "11": return 6     // 十一音，色彩音
        default: return -1
        }
    }
    
    // MARK: - 查找音高在和弦音中的优先级索引
    /// 返回值越小，优先级越高（与priorityScore 逻辑一致）
    private func priorityIndex(of pitch: Int, chord: ChordInfo) -> Int {
        let pc = pitch % 12
        let chordTones = getChordTones(chord: chord)
        for (index, tone) in chordTones.enumerated() {
            if tone % 12 == pc {
                return index
            }
        }
        // 没找到（理论上不会发生），返回最低优先级
        return chordTones.count
    }
    
    // MARK: - 解析根音
    private func parseRootPitchClass(_ name: String) -> Int {
        let pcMap: [String: Int] = [
            "C": 0, "C#": 1, "Db": 1, "D": 2, "Eb": 3, "E": 4,
            "F": 5, "F#": 6, "G": 7, "Ab": 8, "A": 9, "Bb": 10, "B": 11
        ]
        let chars = Array(name)
        guard !chars.isEmpty else { return 0 }
        var rootStr = String(chars[0]).uppercased()
        if chars.count > 1, ["#", "b"].contains(chars[1]) {
            rootStr.append(chars[1])
        }
        return pcMap[rootStr] ?? 0
    }
}

// MARK: - 内部辅助结构体 (P1-5: internal→供GrammarStrategy双线导音调用)
struct ChordInfo {
    let name: String
    let durationSlots: Int
    let isSectionStart: Bool  // 🌟 新增：是否是段落开始
}
// MARK: - 调试辅助：MIDI 转音名
private func midiToNoteName(_ midi: Int) -> String {
    let noteNames = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "G#", "A", "Bb", "B"]
    let octave = (midi / 12) - 1
    let noteIndex = midi % 12
    return "\(noteNames[noteIndex])\(octave)"
}
