// =====================================================================
// MixerHelpSheet.swift
// 调音台（Band Mixer）问号帮助页：纯展示，只读，不回写任何状态。
// 结构对齐 ModeHelpSheet（NavigationStack + ScrollView + 顶部总述 + 分条），
// 全英文、面向音乐爱好者，无任何代码术语。
// =====================================================================
import SwiftUI

struct MixerHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(overviewText)
                        .font(.system(size: 14))
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    ForEach(optionRows, id: \.title) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title)
                                .font(.system(size: 14, weight: .semibold))
                            Text(row.desc)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("About the Mixer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var overviewText: String {
        "The mixer lets you balance the four instruments and shape how the solo is decorated. The controls on the right — Transform, the star, and the two menus below — work together to add tasteful embellishment to your melody without changing its length."
    }

    private var optionRows: [(title: String, desc: String)] {
        [
            ("Transform — what it does",
             "Transform turns on melodic embellishment. Once enabled, the app reworks the solo it already generated, adding passing notes, turns and graceful decorations so the line sounds more alive. It never changes how long the melody lasts — the same amount of time is simply filled with more expressive notes."),
            ("When you can turn on Transform",
             "Transform is available in the GuideTone and Grammar modes. In Learning and Trading modes it is dimmed and unavailable, because those modes generate their lines in their own way."),
            ("The star next to Transform",
             "The star is the color-tone switch. When it is off, embellishment stays within the safe notes of each chord, giving a clean, conservative sound. When it is on, the app may keep richer color notes (upper extensions such as 9ths, 11ths and 13ths) for a fuller, more sophisticated sound."),
            ("When the star can be tapped",
             "The star only lights up in GuideTone or Grammar, and only after Transform is switched on. While Transform is off, or in Learning and Trading modes, the star stays dimmed and cannot be tapped."),
            ("The MY menu — whose style is used",
             "MY chooses which player's style guides the embellishment. The default, My, is a general set of classic decorations (turns, grace notes, arpeggios) that suit any tune. The other choices are named jazz masters, each with a personal vocabulary of embellishments. If a chosen style is ever unavailable, the app gently falls back to the default My style. This list is not the same as the Grammar player list. It holds 26 choices focused purely on embellishment, while Grammar offers a wider set of players for generating the melody itself. Some names appear in both, but each list also contains players the other does not."),
            ("The CONSERV menu — how wide the color palette goes",
             "CONSERV controls how far color notes reach, and it only becomes active when the star is switched on. Conservative (Conserv) uses natural upper extensions sparingly for a tasteful, safe richness. Extended (Ext) opens up a wider palette with more extended and altered tones for a bolder, more modern color.")
        ]
    }
}
