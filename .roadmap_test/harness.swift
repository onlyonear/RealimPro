import Foundation

// ─────────────────────────────────────────────────────────────
// 批量调性分析 harness
// 用法:
//   ./harness songs.txt        — 读文件（每行一个 irealb:// URL）
//   cat songs.txt | ./harness  — 从 stdin 读
// 输出: 每首歌的和弦序列 + (级数, 调性中心PC/音名)，供理论标注对比
// ─────────────────────────────────────────────────────────────

func pcName(_ pc: Int) -> String {
    switch ((pc % 12) + 12) % 12 {
    case 0: return "C"
    case 1: return "Db"
    case 2: return "D"
    case 3: return "Eb"
    case 4: return "E"
    case 5: return "F"
    case 6: return "Gb"
    case 7: return "G"
    case 8: return "Ab"
    case 9: return "A"
    case 10: return "Bb"
    case 11: return "B"
    default: return "?"
    }
}

// 从命令行文件参数或 stdin 读取 URL 列表
func loadURLs() -> [String] {
    var lines: [String] = []
    let args = CommandLine.arguments
    if args.count > 1 {
        // 读文件（每个参数一个文件）
        for path in args.dropFirst() {
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                lines.append(contentsOf: content.components(separatedBy: .newlines))
            } else {
                // 参数本身可能是 URL
                lines.append(path)
            }
        }
    } else {
        // 从 stdin 读
        var buffer = ""
        while let line = readLine() { buffer += line + "\n" }
        lines = buffer.components(separatedBy: .newlines)
    }
    return lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
}

// 分析单首歌，输出结果
func analyzeSong(_ url: String) {
    guard let song = IRealProParser.parse(url: url) else {
        print("⚠️  解析失败: \(url.prefix(60))...")
        return
    }

    // 调号 → 主调
    let keyInfo = KeyParser.parseKey(song.key)
    let beatsPerMeasure = Double(song.timeSignature.first?.wholeNumberValue ?? 4)

    // 构造 JazzRoadmap（复用 ContentView 逻辑）
    let roadmap = JazzRoadmap(title: song.title, tempo: song.tempo)
    for (measureIndex, measureChords) in song.measures.enumerated() {
        let measureDurations = measureIndex < song.measureDurations.count ? song.measureDurations[measureIndex] : [beatsPerMeasure]
        let pairs = zip(measureChords, measureDurations)
            .filter { chord, _ in
                let clean = chord.trimmingCharacters(in: .whitespacesAndNewlines)
                return !clean.isEmpty && clean != "NC" && clean != "N.C."
            }
        for (chordName, duration) in pairs {
            let cleanChord = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
            let isSectionStart = song.sectionMarkers[measureIndex] != nil
            roadmap.append(block: ChordBlock(name: cleanChord, duration: duration, isSectionStart: isSectionStart))
        }
    }

    let result = PostProcessorFull.analyze(
        roadmap: roadmap,
        tonicPC: keyInfo.tonicPC,
        mode: keyInfo.mode,
        beatsPerMeasure: beatsPerMeasure
    )

    // 输出
    print("")
    print("════════════════════════════════════════════════════════")
    print("🎵 \u{22}\(song.title)\u{22} — \(song.composer)")
    print("   调号=\(song.key) (主调 \(pcName(keyInfo.tonicPC)) \(keyInfo.mode == .minor ? "小调" : "大调"))  拍号=\(song.timeSignature)  速度=\(song.tempo)")
    print("════════════════════════════════════════════════════════")

    var mi = 0
    for measure in result.measures {
        mi += 1
        let sectionTag = song.sectionMarkers[mi - 1].map { " [\($0)]" } ?? ""
        let parts = measure.chordAnalyses.map { a in
            "\(a.chord)[\(a.functionLabel),tc=\(pcName(a.tonalCenterPC))]"
        }.joined(separator: " ")
        print("M\(mi)\(sectionTag): \(parts)")
    }
}

// ── 主入口 ──
@main
struct Harness {
    static func main() {
        let urls = loadURLs()
        print("📋 共 \(urls.count) 首歌")
        for url in urls {
            analyzeSong(url)
        }
        print("")
        print("✅ 分析完成")
    }
}
