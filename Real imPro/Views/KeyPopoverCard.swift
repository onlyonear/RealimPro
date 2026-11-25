import SwiftUI

// MARK: - 调号选择卡片（参考 iRealPro 12 调网格，大小调分流）
/// 大调（key 不带 m/-）：偏降号 12 个（C, Db, D, Eb, E, F, Gb, G, Ab, A, Bb, B）
/// 小调（key 带 m/-）：偏升号 12 个（Cm, C#m, Dm, Ebm, Em, Fm, F#m, Gm, G#m, Am, Bbm, Bm）
struct KeyPopoverCard: View {
    @Binding var selectedKey: String
    
    // 大调 12 个调（偏降号，与 iRealPro 一致）
    let majorKeys: [String] = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
    
    // 小调 12 个调（偏升号，带 m 后缀）
    let minorKeys: [String] = ["Cm", "C#m", "Dm", "Ebm", "Em", "Fm", "F#m", "Gm", "G#m", "Am", "Bbm", "Bm"]
    
    // 判断当前是否为小调（兼容 m 和 - 两种后缀）
    private var isMinor: Bool {
        selectedKey.hasSuffix("m") || selectedKey.hasSuffix("-")
    }
    
    // 当前显示的调列表（大调 or 小调）
    private var displayKeys: [String] {
        isMinor ? minorKeys : majorKeys
    }
    
    // 高亮匹配：兼容旧 "-" 格式（如 A- 对应 Am）
    private func isHighlighted(_ key: String) -> Bool {
        if selectedKey == key { return true }
        // 兼容旧 "-" 格式：A- 匹配 Am
        if isMinor {
            let normalized = selectedKey.hasSuffix("-") 
                ? String(selectedKey.dropLast()) + "m" 
                : selectedKey
            return normalized == key
        }
        return false
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // 12 个调，3 行 4 列（无标题，避免 popover 截断）
            VStack(spacing: 10) {
                keyRow(Array(displayKeys.prefix(4)))
                keyRow(Array(displayKeys[4...7]))
                keyRow(Array(displayKeys.suffix(4)))
            }
        }
        .padding(20)
    }
    
    // 一行 4 个调按钮
    private func keyRow(_ keys: [String]) -> some View {
        HStack(spacing: 10) {
            ForEach(keys, id: \.self) { key in
                Button {
                    selectedKey = key
                } label: {
                    Text(key)
                        .font(.system(size: 16, weight: isHighlighted(key) ? .bold : .regular))
                        .frame(width: 52, height: 44)
                        .background(isHighlighted(key) ? Color.accentColor : Color.secondary.opacity(0.1))
                        .foregroundColor(isHighlighted(key) ? .white : .primary)
                        .cornerRadius(8)
                }
            }
        }
    }
}
