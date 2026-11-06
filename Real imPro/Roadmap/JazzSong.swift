import Foundation

// MARK: - 爵士标准曲数据模型
struct JazzSong: Identifiable, Hashable, Codable {
    let id: UUID
    let title: String
    let composer: String
    let style: String
    let tempo: Int
    let key: String
    let timeSignature: String  // 拍号，如 "4/4", "3/4", "6/8"
    let measures: [[String]]  // 按小节组织的和弦，每个小节可能有多个和弦
    let measureDurations: [[Double]]  // 每个和弦的时值（拍数），和 measures 一一对应
    let sectionMarkers: [Int: String]  // 🌟 段落标记：[小节索引: 段落名，如 "A", "B", "C"]
    var hasMixedTimeSignature: Bool = false
    
    // MARK: - 自定义初始化器（确保参数顺序明确，避免编译器推断问题）
    init(id: UUID = UUID(), title: String, composer: String, style: String, tempo: Int, key: String, timeSignature: String = "4/4", measures: [[String]], measureDurations: [[Double]] = [], sectionMarkers: [Int: String] = [:], hasMixedTimeSignature: Bool = false) {
        self.id = id
        self.title = title
        self.composer = composer
        self.style = style
        self.tempo = tempo
        self.key = key
        self.timeSignature = timeSignature
        self.measures = measures
        self.sectionMarkers = sectionMarkers
        self.hasMixedTimeSignature = hasMixedTimeSignature
        
        // 如果没有传入时值，自动计算平均分配作为兜底
        if measureDurations.isEmpty {
            var defaultDurations: [[Double]] = []
            let beatsPerMeasure = Double(timeSignature.split(separator: "/").first.flatMap { Int($0) } ?? 4)
            for measure in measures {
                let count = measure.count
                defaultDurations.append(Array(repeating: beatsPerMeasure / Double(count), count: count))
            }
            self.measureDurations = defaultDurations
        } else {
            self.measureDurations = measureDurations
        }
    }
    
    // 向后兼容：展平的和弦序列
    var chordProgression: [String] {
        measures.flatMap { $0 }
    }
    
    // 向后兼容：每个小节取第一个和弦（用于简单展示）
    var firstChordPerMeasure: [String] {
        measures.map { $0.first ?? "" }
    }
}

// MARK: - 小节映射（弱起/前置空小节 → 内容栏偏移）
// [2026-09-23 弱起对齐补丁·新增] 本枚举为纯新增，不改动任何既有类型/逻辑。
enum SongMeasureMap {
    /// 显示小节开头，连续「整小节没有任何非空和弦」的小节数（弱起小节数量）。
    /// 这些小节在构建 roadmap 时被跳过（ContentView.swift Guide 路径 guard !cleanChord.isEmpty，
    /// 非 Guide 路径过滤空/NC），故引擎生成栏与级数分析项相对「显示小节」整体后移该数量。
    /// 引擎内整流按 roadmap 工作、不受影响；只有「生成后的显示切分」与「级数渲染」需按此偏移取值。
    /// 注意：只统计真正的空字符串小节；"NC"/"N.C." 在 Guide 路径会被保留并占用 roadmap 时长，不在此列。
    static func leadingPickupCount(_ measures: [[String]]) -> Int {
        var n = 0
        for mc in measures {
            let hasChord = mc.contains {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if hasChord { break }
            n += 1
        }
        return n
    }
}

// MARK: - 播放列表模型
struct JazzPlaylist: Identifiable, Codable {
    let id = UUID()
    let name: String
    var songs: [JazzSong]
}

// MARK: - 内置示例歌曲
extension JazzPlaylist {
    static let demoSong = JazzSong(
        title: "Demo",
        composer: "",
        style: "Medium Up Swing",
        tempo: 140,
        key: "C",
        timeSignature: "4/4",
        measures: [
            // === A段（1-8小节）===
            ["Am7"],
            ["Dm7"],
            ["G7"],
            ["Cmaj7"],
            ["Fmaj7"],
            ["B7"],
            ["Emaj7"],
            ["Emaj7"],          // × 单小节反复

            // === B段（9-16小节）===
            ["Em7"],
            ["Am7"],
            ["D7"],
            ["Gmaj7"],
            ["Cmaj7"],
            ["F#7"],
            ["Bmaj7"],
            ["Bmaj7"],          // × 单小节反复

            // === C段（17-24小节）===
            ["C#m7"],
            ["F#7"],
            ["Bmaj7"],
            ["Bmaj7"],          // × 单小节反复
            ["Bbm7"],
            ["Eb7"],
            ["Abmaj7"],
            ["E7b13"],

            // === D段（25-36小节）===
            ["Am7"],
            ["Dm7"],
            ["G7"],
            ["Cmaj7"],
            ["Fmaj7"],
            ["Fm7"],
            ["Em7"],
            ["Ebdim7"],
            ["Dm7"],
            ["G7"],
            ["Cmaj7"],
            ["Bm7b5", "E7b9"],
        ],
        sectionMarkers: [0: "A", 8: "B", 16: "C", 24: "D"]
    )

    static let demoPlaylist = JazzPlaylist(
        name: "My Songs",
        songs: [demoSong]
    )
}
