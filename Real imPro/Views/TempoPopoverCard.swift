import SwiftUI

// MARK: - BPM 速度选择卡片（参考 iRealPro）
/// 大数字 + -/+ 按钮 + 滑块，步进 ±1
struct TempoPopoverCard: View {
    @Binding var tempo: Int
    
    var body: some View {
        VStack(spacing: 16) {
            // 标题 + 大数字
            VStack(spacing: 4) {
                Text("Tempo")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("\(tempo)")
                    .font(.system(size: 48, weight: .light))
            }
            
            // - 按钮 / 节拍器图标 / + 按钮
            HStack(spacing: 24) {
                Button {
                    if tempo > 40 { tempo -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.accentColor)
                }
                
                Image(systemName: "metronome")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)
                
                Button {
                    if tempo < 240 { tempo += 1 }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.accentColor)
                }
            }
            
            // 滑块
            Slider(value: Binding(
                get: { Double(tempo) },
                set: { tempo = Int($0) }
            ), in: 40...240, step: 1)
            .tint(.accentColor)
        }
        .padding(24)
    }
}
