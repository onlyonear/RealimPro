import Foundation

// MARK: - 基础物理音符模型 (浓缩自 Java 的 Note.java 与 PitchClass.java)
struct PhysicalNote: Equatable {
    let midiPitch: Int      // 绝对 MIDI 音高 (例如 60 代表中央 C)
    let durationSlots: Int  // 持续的物理 Slot 长度 (1拍 = 120 slots)
    let tuplet: Int         // 连音类型：0=普通音符，3=三连音，5=五连音，7=七连音
    /// 保留 GrammarTerminalType 原始标记，避免 detectMusicTheoryTag 反推覆盖
    let terminalType: String?  // "C"/"L"/"S"/"H"/"A"/"X"/"Y"/"R" 或 nil
    // 自动根据durationSlots识别连音类型，支持自定义tuplet
    init(midiPitch: Int, durationSlots: Int, tuplet: Int? = nil, terminalType: String? = nil) {
        self.midiPitch = midiPitch
        self.durationSlots = durationSlots
        self.terminalType = terminalType
        
        if let customTuplet = tuplet {
            self.tuplet = customTuplet
        } else {
            // 三连音独有slots
            let tripletSlots: Set<Int> = [320, 160, 80, 40, 20, 10, 5]
            // 五连音独有slots
            let quintupletSlots: Set<Int> = [96, 72, 48, 24, 12]
            
            if tripletSlots.contains(durationSlots) {
                self.tuplet = 3
            } else if quintupletSlots.contains(durationSlots) {
                self.tuplet = 5
            } else {
                self.tuplet = 0
            }
        }
    }
    
    var isRest: Bool { return midiPitch == -1 }
}

// MARK: - 核心引导音生成引擎
class JazzGuideToneEngine {
    
    // 定义物理音序器的一拍对应的基本槽位数 (对应 Java 里的 Constants.BEAT = 120)
    static let slotsPerBeat = 120
    
    // 舒适音域的中心点 (对应 Java 源码中的 middleOfRange 逻辑，通常设为中央C附近，MIDI 60)
    private let middleOfRange = 60
    
    /// 核心算法：为给定的 Roadmap 生成平滑的 3音 或 7音 引导音旋律线
    /// - Parameters:
    ///   - roadmap: 咱们之前写好的宏观乐谱调度器
    ///   - degree: 期待生成的和弦度数 (3 代表三音线，7 代表七音线)
    /// - Returns: 一组可以直接交付给界面或物理发声器的物理音符序列
    func generateGuideLine(for roadmap: JazzRoadmap, targetDegree: Int) -> [PhysicalNote] {
        let linearChords = roadmap.flattenRoadmap()
        var generatedLine: [PhysicalNote] = []
        
        var lastMidiPitch: Int? = nil
        
        for chordBlock in linearChords {
            // 1. 获取当前和弦的根音物理半音值 (0-11，C=0, C#=1...)
            let rootPitchClass = getPitchClassOfRoot(chordName: chordBlock.name)
            
            // 2. 根据和弦性质（大、小、属），计算目标度数（3音或7音）距离根音的半音音程差
            let relativeInterval = getIntervalForDegree(chordName: chordBlock.name, degree: targetDegree)
            
            // 3. 计算目标音符的原始 PitchClass 基准音
            let targetPitchClass = (rootPitchClass + relativeInterval) % 12
            
            // 4. 【平滑算法】：寻找距离舒适区或上一个音最近的八度位置 (Voice Leading)
            let optimalMidiPitch = findClosestOctave(forTargetPC: targetPitchClass, comparingTo: lastMidiPitch)
            
            // 5. 按照当前和弦块在物理时间轴上的真实持续长度，生成物理音符
            // Java 源码里 duration 对应物理拍数，这里乘以一拍的 slots 得到绝对时值
            let physicalDuration = Int(Double(chordBlock.duration) * Double(JazzGuideToneEngine.slotsPerBeat))
            let note = PhysicalNote(midiPitch: optimalMidiPitch, durationSlots: physicalDuration)
            
            generatedLine.append(note)
            
            // 记录当前音高，作为下一个和弦平滑过渡的参考锚点
            lastMidiPitch = optimalMidiPitch
        }
        
        return generatedLine
    }
    
    // MARK: - 内部乐理算法工具箱
    
    /// 解析和弦文本符号的根音 (提取自 PitchClass.getPitchClass)
    private func getPitchClassOfRoot(chordName: String) -> Int {
        let cleanName = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return 0 }
        
        // 匹配前缀根音
        var rootStr = ""
        let chars = Array(cleanName)
        if chars.count > 0 { rootStr.append(chars[0]) }
        if chars.count > 1 && (chars[1] == "#" || chars[1] == "b") { rootStr.append(chars[1]) }
        
        let pcMap: [String: Int] = [
            "C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3,
            "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8,
            "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11
        ]
        
        return pcMap[rootStr] ?? 0
    }
    
    /// 根据和弦性质计算 3音 或 7音 的音程偏置 (提取自 ChordForm/ChordSymbol 基因)
    private func getIntervalForDegree(chordName: String, degree: Int) -> Int {
        let name = chordName.lowercased()
        
        if degree == 3 {
            // 【Bug 修复】：包含 m，但绝对不能包含 maj，否则会把 Cmaj7 误判为小调！
            let isMinor = (name.contains("m") && !name.contains("maj")) || 
                           name.contains("min") || 
                           name.contains("dim") || 
                           name.contains("ø")
            
            if isMinor {
                return 3 // 小调小三度
            }
            return 4 // 大调大三度
        } else if degree == 7 {
            if name.contains("maj7") || name.contains("m7plus") || name.contains("▲") {
                return 11 // 大七度
            }
            if name.contains("dim7") || name.contains("o7") {
                return 9  // 减七度
            }
            return 10 // 默认小七度
        }
        return 0
    }
    
    /// 核心过渡算法：寻找最平滑、音程起伏最小的八度绝对音高 (Voice Leading)
    private func findClosestOctave(forTargetPC targetPC: Int, comparingTo anchorMidi: Int?) -> Int {
        // 如果是全曲第一个音，参考舒适区中点（60）；否则参考上一个音符的绝对高度
        let referenceMidi = anchorMidi ?? middleOfRange
        
        var bestMidi = targetPC + 48 // 从低八度开始迭代推算
        var minDistance = Int.max
        
        // 在爵士乐常规音域（MIDI 48 到 84，即 3个八度跨度）内寻找最佳包络线
        for octaveOffset in stride(from: 48, to: 84, by: 12) {
            let currentTestMidi = targetPC + octaveOffset
            let distance = abs(currentTestMidi - referenceMidi)
            if distance < minDistance {
                minDistance = distance
                bestMidi = currentTestMidi
            }
        }
        return bestMidi
    }
}
