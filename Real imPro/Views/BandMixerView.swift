import SwiftUI

enum MixerDisplayMode: String, CaseIterable {
    case swing  = "Swing"
    case ballad = "Ballad"
    case blues  = "Shuffle"
    case afro   = "Afro"
    //case bebop  = "Bebop"
    case bossa  = "Bossa"
    case waltz  = "Waltz"
    case latin  = "Latin"
}

// MARK: - 乐队混音总控台 (Apple Pro 高级简约版 + 折叠机制)
struct BandMixerView: View {
    @Binding var saxVolume: Float
    @Binding var pianoVolume: Float
    @Binding var bassVolume: Float
    @Binding var drumVolume: Float
    @Binding var saxMuted: Bool
    @Binding var pianoMuted: Bool
    @Binding var bassMuted: Bool
    @Binding var drumMuted: Bool
    @Binding var selectedStyle: MixerDisplayMode
    @Binding var isExpanded: Bool
    let isPlaying: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                VStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: 36, height: 5)
                        .padding(.top, 8)
                        .padding(.bottom, isExpanded ? 12 : 8)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                HStack(spacing: 16) {
                    HStack(spacing: 16) {
                        MixerTrackView(title: "SAX", icon: "wind", volume: $saxVolume, isMuted: $saxMuted)
                        MixerTrackView(title: "PIANO", icon: "pianokeys", volume: $pianoVolume, isMuted: $pianoMuted)
                        MixerTrackView(title: "BASS", icon: "guitars", volume: $bassVolume, isMuted: $bassMuted)
                        MixerTrackView(title: "DRUM", icon: "circle.grid.cross", volume: $drumVolume, isMuted: $drumMuted)
                    }
                    .padding(.trailing, 4)
                    
                    Divider()
                        .frame(height: 60)
                        .background(Color.gray.opacity(0.3))
                    
                    VStack(spacing: 10) {
                        Image(systemName: "dial.low")
                            .font(.system(size: 20, weight: .light))
                            .foregroundColor(isPlaying ? .accentColor : .primary.opacity(0.7))
                        
                        Menu {
                            ForEach(MixerDisplayMode.allCases, id: \.self) { style in
                                Button {
                                    selectedStyle = style
                                } label: {
                                    Text(style.rawValue.capitalized)
                                    if selectedStyle == style {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(selectedStyle.rawValue.uppercased())
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                    .frame(width: 80)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .clipped()
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 15, x: 0, y: 8)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
    }
}

// MARK: - 🎚️ 单个极简轨道组件
struct MixerTrackView: View {
    let title: String
    let icon: String
    @Binding var volume: Float
    @Binding var isMuted: Bool
    
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .kerning(0.8)
            }
            .foregroundColor(isMuted ? .gray.opacity(0.6) : .secondary)
            
            Slider(value: $volume, in: 0...1)
                .tint(isMuted ? .gray.opacity(0.2) : .primary)
                .disabled(isMuted)
                .animation(.easeInOut(duration: 0.2), value: isMuted)
            
            Button(action: {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isMuted.toggle()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(isMuted ? Color.red.opacity(0.15) : Color.gray.opacity(0.1))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isMuted ? .red : .primary.opacity(0.8))
                }
            }
            .buttonStyle(.plain)
        }
    }
}
