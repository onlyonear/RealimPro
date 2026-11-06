import Foundation

// MARK: - 音名拼写工具（处理等音正确拼写）
/// 解决 G#/Ab、F#/Gb 等等音的正确拼写问题
/// 根据和弦的根音和性质，确定每个构成音应该用升号还是降号
struct NoteSpelling {
    
    // MARK: - 升号调和降号调的音名
    /// 升号体系的音名（用于升号调）
    private static let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    
    /// 降号体系的音名（用于降号调）
    private static let flatNames = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
    
    // MARK: - 判断根音是升号调还是降号调
    /// 根据根音判断应该用升号体系还是降号体系
    static func useSharps(forRoot root: String) -> Bool {
        // 升号调的根音：C, G, D, A, E, B, F#
        // 降号调的根音：F, Bb, Eb, Ab, Db, Gb
        let sharpRoots = ["C", "G", "D", "A", "E", "B", "F#", "C#", "G#", "D#", "A#"]
        let flatRoots = ["F", "Bb", "Eb", "Ab", "Db", "Gb", "Cb"]
        
        if sharpRoots.contains(root) {
            return true
        } else if flatRoots.contains(root) {
            return false
        }
        
        // 默认：有 b 的根音用降号体系，其他用升号体系
        return !root.contains("b")
    }
    
    // MARK: - 提取根音
    /// 从和弦名中提取根音（字母 + 升降号）
    static func extractRoot(from chordName: String) -> String {
        var root = ""
        let chars = Array(chordName)
        
        // 第一个字符必须是大写字母（根音）
        guard !chars.isEmpty, chars[0].isUppercase else { return "C" }
        root.append(chars[0])
        
        // 第二个字符可能是 # 或 b（升降号）
        if chars.count > 1 {
            if chars[1] == "#" || chars[1] == "b" {
                root.append(chars[1])
            }
        }
        
        return root
    }
    
    // MARK: - 获取单个音符的正确拼写
    /// 给定 MIDI 音高和当前和弦，返回正确的音名拼写
    static func spellNote(midiPitch: Int, chordName: String) -> String {
        let root = extractRoot(from: chordName)
        let useSharp = useSharps(forRoot: root)
        
        let pc = midiPitch % 12
        
        if useSharp {
            return sharpNames[pc]
        } else {
            return flatNames[pc]
        }
    }
}

