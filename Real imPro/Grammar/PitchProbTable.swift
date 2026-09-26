//
//  PitchProbTable.swift
//  Real imPro
//
//  P0-3a: 移植 Java LickGen.fillProbs + getRandomNote 音级概率选音模型
//
//  原版位置:
//    - fillProbs: LickGen.java:960-1076
//    - accumulateProbs: LickGen.java:1080-1095
//    - getRandomNote: LickGen.java:3522-3599
//
//  核心逻辑:
//    1. fillProbs: 为每个和弦计算 12 音级概率表 (scale→chord→color 累加, 后写覆盖)
//    2. getRandomNote: 在概率表中加权随机选音, 受双向音程范围 [minStep, maxStep] 约束
//

import Foundation

struct PitchProbTable {
    
    // MARK: - 默认权重 (对齐 Java LickGen.java:94-98)
    static let defaultChordToneWeight: Double = 0.7
    static let defaultColorToneWeight: Double = 0.2
    static let defaultScaleToneWeight: Double = 0.1
    
    // MARK: - fillProbs: 计算单个和弦的 12 音级概率表
    /// 对齐 Java LickGen.fillProbs (L960-1076)
    /// - Parameters:
    ///   - chordName: 和弦名 (如 "Cmaj7", "Dm7", "G7")
    ///   - chordToneWeight: 和弦音权重 (默认 0.7)
    ///   - colorToneWeight: 色彩音权重 (默认 0.2)
    ///   - scaleToneWeight: 音阶音权重 (默认 0.1)
    /// - Returns: 长度为 12 的概率数组, 索引 0=C, 1=C#, ..., 11=B
    static func fillProbs(
        chordName: String,
        chordToneWeight: Double = defaultChordToneWeight,
        colorToneWeight: Double = defaultColorToneWeight,
        scaleToneWeight: Double = defaultScaleToneWeight,
        chordToneDecayRate: Double = 0.0  // P0-4b: 对齐 Java L964 死参数, 传入但未使用
    ) -> [Double] {
        var p = [Double](repeating: 0.0, count: 12)
        
        let cleanName = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootPC = GrammarNoteConverter.getRootPC(cleanName)
        let quality = ChordQuality(chordName: cleanName)
        
        // 对齐 Java accumulateProbs 调用顺序 (L1047-1049): scale → chord → color
        // 后写覆盖, color 权重压过 chord 压过 scale
        let scaleIntervals = quality.scaleIntervals
        let chordIntervals = quality.chordIntervals
        let colorIntervals = quality.colorIntervals(for: cleanName)
        
        accumulateProbs(intervals: scaleIntervals, rootPC: rootPC, categoryProb: scaleToneWeight, p: &p)
        accumulateProbs(intervals: chordIntervals, rootPC: rootPC, categoryProb: chordToneWeight, p: &p)
        accumulateProbs(intervals: colorIntervals, rootPC: rootPC, categoryProb: colorToneWeight, p: &p)
        
        return p
    }
    
    // MARK: - accumulateProbs: 累加一类音的概率
    /// 对齐 Java LickGen.accumulateProbs (L1080-1095)
    /// p[ns.getSemitones()] += noteProb * categoryProb
    private static func accumulateProbs(
        intervals: [Int],
        rootPC: Int,
        categoryProb: Double,
        p: inout [Double]
    ) {
        for interval in intervals {
            let semitone = (rootPC + interval) % 12
            p[semitone] += categoryProb  // noteProb 默认为 1.0 (文法未指定单音概率时)
        }
    }
    
    // MARK: - getRandomNote: 加权随机选音
    /// 对齐 Java LickGen.getRandomNote (L3522-3599)
    /// - Parameters:
    ///   - prevPitch: 上一个音的 MIDI 音高
    ///   - minStep: 最小音程 (半音数, 正数)
    ///   - maxStep: 最大音程 (半音数, 正数)
    ///   - minPitch: 最低音高
    ///   - maxPitch: 最高音高
    ///   - probs: 12 音级概率表 (来自 fillProbs)
    /// - Returns: 选中的 MIDI 音高, 候选为空时返回 nil
    static func getRandomNote(
        prevPitch: Int,
        minStep: Int,
        maxStep: Int,
        minPitch: Int,
        maxPitch: Int,
        probs: [Double]
    ) -> Int? {
        var availPitches: [Int] = []
        var availProbs: [Double] = []
        var probSum: Double = 0.0
        
        // 遍历 12 音级
        for i in 0..<12 {
            guard probs[i] != 0 else { continue }
            
            // 从 minPitch 所在八度开始, 每次 +12, 直到 maxPitch
            var pitchToAdd = ((minPitch / 12) * 12) + i
            
            while pitchToAdd <= maxPitch {
                // 筛选音程在 [minStep, maxStep] 双向范围内的候选
                let inLowerRange = pitchToAdd >= prevPitch - maxStep && pitchToAdd <= prevPitch - minStep
                let inUpperRange = pitchToAdd >= prevPitch + minStep && pitchToAdd <= prevPitch + maxStep
                
                if pitchToAdd >= minPitch && (inLowerRange || inUpperRange) {
                    availPitches.append(pitchToAdd)
                    availProbs.append(probs[i])
                    probSum += probs[i]
                }
                pitchToAdd += 12
            }
        }
        
        guard !availPitches.isEmpty, probSum > 0 else { return nil }
        
        // 归一化概率
        for i in 0..<availProbs.count {
            availProbs[i] /= probSum
        }
        
        // 加权随机选音
        let rand = Double.random(in: 0..<1)
        var offset: Double = 0.0
        
        for i in 0..<availProbs.count {
            if rand >= offset && rand < offset + availProbs[i] {
                return availPitches[i]
            }
            offset += availProbs[i]
        }
        
        return availPitches.last
    }
    
    // MARK: - checkNote: 验证音高是否符合终端类型
    /// 对齐 Java LickGen.checkNote (L3328-3415)
    /// - Parameters:
    ///   - pitch: MIDI 音高
    ///   - terminalType: 终端类型
    ///   - chordName: 和弦名
    /// - Returns: 是否符合类型
    static func checkNote(
        pitch: Int,
        terminalType: GrammarTerminalType,
        chordName: String
    ) -> Bool {
        let cleanName = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootPC = GrammarNoteConverter.getRootPC(cleanName)
        let quality = ChordQuality(chordName: cleanName)
        let pitchPC = pitch % 12
        
        switch terminalType {
        case .chord:
            // C: 验证是否为和弦音
            return quality.chordIntervals.contains { (rootPC + $0) % 12 == pitchPC }
            
        case .color:
            // L: 验证是否为色彩音
            return quality.colorIntervals(for: cleanName).contains { (rootPC + $0) % 12 == pitchPC }
            
        case .scale:
            // S: 验证是否为音阶音
            return quality.scaleIntervals.contains { (rootPC + $0) % 12 == pitchPC }
            
        case .note:
            // H (Java T_NOTE): checkNote 直接 return true, 不做类型限制
            // 有效音池 = probs 中所有非零概率 = 和弦∪色彩∪音阶
            return true
            
        default:
            // 其他类型不验证
            return true
        }
    }

    // MARK: - 性能优化: checkNote Set 版本 (P0)
    /// 与 checkNote(pitch:terminalType:chordName:) 语义完全等价，
    /// 但使用预计算的音级 Set 做 O(1) 查找，避免每次重试都重新解析和弦。
    static func checkNote(
        pitch: Int,
        terminalType: GrammarTerminalType,
        chordPCSet: Set<Int>,
        colorPCSet: Set<Int>,
        scalePCSet: Set<Int>
    ) -> Bool {
        let pitchPC = pitch % 12
        switch terminalType {
        case .chord:  return chordPCSet.contains(pitchPC)
        case .color:  return colorPCSet.contains(pitchPC)
        case .scale:  return scalePCSet.contains(pitchPC)
        case .note:   return true   // H 终端不做类型限制
        default:      return true
        }
    }
}
