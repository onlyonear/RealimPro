import SwiftUI

struct NoteColorLegendView: View {
    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                LegendItem(color: .black, label: "Chord")
                    .gridColumnAlignment(.leading)
                LegendItem(color: Color(red: 0.055, green: 0.486, blue: 0.420), label: "Color")
                    .gridColumnAlignment(.leading)
            }
            GridRow {
                LegendItem(color: .blue, label: "Approach")
                LegendItem(color: .red, label: "Avoid")
            }
        }
        .font(.caption2)
        .foregroundColor(.secondary)
        .opacity(0.85)
        .padding(12)
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .offset(x: 0.5)
            Text(label)
        }
    }
}
