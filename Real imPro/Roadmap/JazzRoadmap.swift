import Foundation

// MARK: - 乐曲宏观调度层 (对应 Java 的 RoadMap.java)
/// 管理整首乐曲的结构、时间轴，并将所有的基础模型与解析引擎串联起来
class JazzRoadmap {
    var title: String
    var tempo: Int // BPM (每分钟节拍数)

    // 乐曲的结构骨架：包含普通的和弦(ChordBlock)和打包好的语块(Brick)
    private(set) var blocks: [JazzBlock] = []

    // 阶段2(P1): 调性区间链 (自动从和弦序列解析)
    private(set) var keyMap: [KeySpan] = []
    
    init(title: String = "Untitled Jazz Piece", tempo: Int = 120) {
        self.title = title
        self.tempo = tempo
    }
    
    /// 向乐曲中添加一个小节或一段语块
    func append(block: JazzBlock) {
        blocks.append(block)
    }
    
    /// 获取整首乐曲的总物理节拍长度
    var totalDuration: Double {
        return blocks.reduce(0.0) { $0 + $1.duration }
    }

    /// 阶段2(P1): 从当前和弦序列自动解析调性链
    /// P0-2: 使用 PostProcessorFull.analyze 完整流程 (findKeys + 3 修正 pass)
    /// 替换简化版 KeySpanFactory.build
    func buildKeyMap(beatsPerMeasure: Int = 4) {
        let chords = flattenRoadmap()
        guard !chords.isEmpty else { keyMap = []; return }
        
        // P0-2: 推断全曲主调 (简单实现: 取最后一个和弦的根音和调式)
        let tonicPC = inferTonicPC(from: chords)
        let songMode = inferSongMode(from: chords)
        
        // 调用 PostProcessorFull.analyze 完整流程 (含 findKeys + resolveDominantLaunchers + resolveBorrowedMajors + resolveMinorTonics)
        let analysis = PostProcessorFull.analyze(
            roadmap: self,
            tonicPC: tonicPC,
            mode: songMode,
            beatsPerMeasure: Double(beatsPerMeasure)
        )
        
        // 从 AnalysisResult 提取所有 ChordAnalysis
        // 注意: measures 数组本身保持全局顺序, flatMap 后不要 sorted
        // (ChordAnalysis.beatStart 是小节内相对拍, 不能用于全局排序)
        let allAnalyses = analysis.measures.flatMap { $0.chordAnalyses }
        
        // 用 beatDuration 累加得到全局绝对拍, 聚合连续相同 tonalCenterPC 的和弦为 KeySpan
        keyMap = aggregateToKeySpans(analyses: allAnalyses, songMode: songMode)
    }
    
    /// 从和弦序列推断全曲主调根音 PC (简单实现: 取最后一个和弦的根音)
    /// 后续 P1 可优化: 从用户输入的调性获取, 或分析和弦进行推断
    private func inferTonicPC(from chords: [ChordBlock]) -> Int {
        if let lastChord = chords.last {
            return lastChord.chordRootPC()
        }
        return 0  // 默认 C
    }
    
    /// 从和弦序列推断全曲主调调式 (简单实现: 最后一个和弦是 minor 则 .minor, 否则 .major)
    private func inferSongMode(from chords: [ChordBlock]) -> JazzMode {
        if let lastChord = chords.last {
            return lastChord.findModeFromQuality()
        }
        return .major
    }
    
    /// 将 [ChordAnalysis] 聚合为 [KeySpan]
    /// 连续相同 tonalCenterPC 的和弦合并为一个 KeySpan
    /// 注意: 用 beatDuration 累加得到全局绝对拍, 不要用小节内相对的 beatStart
    private func aggregateToKeySpans(analyses: [ChordAnalysis], songMode: JazzMode) -> [KeySpan] {
        guard !analyses.isEmpty else { return [] }
        
        var spans: [KeySpan] = []
        var currentBeat = 0.0  // 全局绝对拍, 用 beatDuration 累加
        var curPC = analyses[0].tonalCenterPC
        var curStart = 0.0
        
        for a in analyses {
            if a.tonalCenterPC != curPC {
                // 调性中心变化, 终结当前 KeySpan, 开新的
                spans.append(KeySpan(
                    startBeat: curStart,
                    endBeat: currentBeat,
                    rootPC: curPC,
                    mode: songMode,  // 简化: 全曲用 songMode, 临时转调 P1 优化
                    isTemporary: false
                ))
                curPC = a.tonalCenterPC
                curStart = currentBeat
            }
            currentBeat += a.beatDuration  // 累加得到全局拍
        }
        // 加入最后一个
        spans.append(KeySpan(
            startBeat: curStart,
            endBeat: currentBeat,
            rootPC: curPC,
            mode: songMode,
            isTemporary: false
        ))
        
        return spans
    }
    
    /// 将整首曲子各种复杂的嵌套结构（如 AABA段落、二五一砖块）彻底展平为线性的和弦序列
    func flattenRoadmap() -> [ChordBlock] {
        return blocks.flatMap { $0.flatten() }
    }
    
    // MARK: - 时间槽定位
    /// 告诉引擎：在全局的第 `beat` 拍，到底正在播放哪一个具体和弦？
    func getChordAtBeat(_ targetBeat: Double) -> ChordBlock? {
        // 防止越界
        guard targetBeat >= 0 && targetBeat < totalDuration else { return nil }
        
        var currentBeatAccumulator: Double = 0
        let linearChords = flattenRoadmap()
        
        for chord in linearChords {
            // 如果目标节拍刚好落在这个和弦的持续时间内
            if targetBeat >= currentBeatAccumulator && targetBeat < (currentBeatAccumulator + chord.duration) {
                return chord
            }
            currentBeatAccumulator += chord.duration
        }
        return nil
    }
}
// MARK: - 辅助：根据小节内和弦数量自动分配每个和弦的拍数（4/4拍）
/// 前短后长原则：前面的和弦变化快（时值短），后面的和弦稳定（时值长）
func allocateChordDurations(chordCount: Int, totalBeats: Double = 4.0) -> [Double] {
    guard chordCount > 0 else { return [] }
    
    switch chordCount {
    case 1:
        return [totalBeats]
    case 2:
        let half = totalBeats / 2.0
        return [half, half]
    case 3:
        return [1.0, 1.0, totalBeats - 2.0]
    case 4:
        return Array(repeating: 1.0, count: 4)
    case 5...8:
        let eighthCount = 2 * chordCount - 8
        let quarterCount = chordCount - eighthCount
        var durations: [Double] = Array(repeating: 0.5, count: eighthCount)
        durations.append(contentsOf: Array(repeating: 1.0, count: quarterCount))
        return durations
    default:
        let eighthDuration = 0.5
        var durations = Array(repeating: eighthDuration, count: chordCount - 1)
        let lastDuration = totalBeats - Double(chordCount - 1) * eighthDuration
        durations.append(max(lastDuration, eighthDuration))
        return durations
    }
}
