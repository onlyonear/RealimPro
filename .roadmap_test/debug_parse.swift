import Foundation

// 调试：打印 iReal Pro 解析的原始结果
@main
struct DebugParse {
    static func main() {
        // 从 stdin 读 URL（避免命令行长 URL 触发 shell 限制）
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        let url = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") } ?? ""
        guard !url.isEmpty, let song = IRealProParser.parse(url: url) else {
            print("解析失败（未读到 URL）")
            return
        }
        print("title: \(song.title)")
        print("key: \(song.key)")
        print("timeSignature: \(song.timeSignature)")
        print("tempo: \(song.tempo)")
        print("rawChords: \(song.rawChords)")
        print("")
        print("measures (\(song.measures.count) 小节):")
        for (i, m) in song.measures.enumerated() {
            let dur = i < song.measureDurations.count ? song.measureDurations[i] : []
            print("M\(i+1): \(m)  dur=\(dur)")
        }
        print("")
        print("sectionMarkers: \(song.sectionMarkers)")
    }
}
