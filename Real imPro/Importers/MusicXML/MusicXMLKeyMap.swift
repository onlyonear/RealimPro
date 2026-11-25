import Foundation

/// MusicXML `<key><fifths>/<mode>` → App 调名字符串。
/// 输出大调主音或 "主音m"，再交给现有 `getVexflowKey`（渲染层）转 VexFlow 调号。
/// 对应设计稿 §5.1。
enum MusicXMLKeyMap {
    // fifths -7 ... +7
    static let major: [String] =
        ["Cb", "Gb", "Db", "Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#"]
    static let minor: [String] =
        ["Abm", "Ebm", "Bbm", "Fm", "Cm", "Gm", "Dm", "Am", "Em", "Bm",
         "F#m", "C#m", "G#m", "D#m", "A#m"]

    /// - Parameters:
    ///   - fifths: 调号升降号数（-7...7）
    ///   - mode: "minor"/"major"（缺省按大调）
    static func keyName(fifths: Int, mode: String?) -> String {
        let isMinor = (mode?.lowercased() == "minor")
        let table = isMinor ? minor : major
        let idx = fifths + 7
        guard (0..<15).contains(idx) else { return "C" }
        return table[idx]
    }
}
