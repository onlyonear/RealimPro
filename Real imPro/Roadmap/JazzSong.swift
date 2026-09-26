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
