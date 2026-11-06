import Foundation

func buildRoadmap(_ chords: [(String, Double)], sectionStarts: Set<Int> = []) -> JazzRoadmap {
    let r = JazzRoadmap(title: "test")
    for (i, (name, dur)) in chords.enumerated() {
        r.append(block: ChordBlock(name: name, duration: dur, isSectionStart: sectionStarts.contains(i)))
    }
    return r
}

func dump(_ title: String, _ r: JazzRoadmap, tonicPC: Int, mode: JazzMode) {
    let result = PostProcessorFull.analyze(roadmap: r, tonicPC: tonicPC, mode: mode, beatsPerMeasure: 4.0)
    print("=== \(title) ===")
    for measure in result.measures {
        let parts = measure.chordAnalyses.map { "\($0.chord)[tc=\($0.tonalCenterPC),\($0.functionLabel)]" }.joined(separator: " ")
        print("  \(parts)")
    }
}

// ── 3 个确认的 bug ──
dump("BUG1 ii-V后接非tonic: Dm7-G7-Ebmaj7 (应 Dm7=ii G7=V in C)",
     buildRoadmap([("Dm7",4),("G7",4),("Ebmaj7",4)]), tonicPC: 0, mode: .major)

dump("BUG2 ii-V of V: Am7-D7-G7-Cmaj7 (Am7-D7 应归 G 的 ii-V)",
     buildRoadmap([("Am7",4),("D7",4),("G7",4),("Cmaj7",4)]), tonicPC: 0, mode: .major)

dump("BUG3 turnaround: Cmaj7-Am7-Dm7-G7 (Am7 应 vi in C)",
     buildRoadmap([("Cmaj7",4),("Am7",4),("Dm7",4),("G7",4)]), tonicPC: 0, mode: .major)

// ── 循环 ii-V 回归 (核心 bug) ──
dump("回归 循环 ii-V: Am7...Bm7b5-E7b9 (应 iiø-V7alt in A, Am7 保持 vi)",
     buildRoadmap([("Am7",4),("Dm7",4),("G7",4),("Cmaj7",4),("Bm7b5",2),("E7b9",2)]), tonicPC: 0, mode: .major)

// ── 替代属七 (route A' 新增, 局部规则) ──
dump("替代 tritone sub: Dm7-Db7-Cmaj7 (Db7 应 bII7 in C)",
     buildRoadmap([("Dm7",4),("Db7",4),("Cmaj7",4)]), tonicPC: 0, mode: .major)

dump("替代 backdoor: Fm7-Bb7-Cmaj7 (Bb7 应 bVII7 in C)",
     buildRoadmap([("Fm7",4),("Bb7",4),("Cmaj7",4)]), tonicPC: 0, mode: .major)

dump("替代 次级属七 VI7: Em7-A7-Dm7-G7-Cmaj7 (A7 应 VI7 in C)",
     buildRoadmap([("Em7",4),("A7",4),("Dm7",4),("G7",4),("Cmaj7",4)]), tonicPC: 0, mode: .major)

// ── 副属链 + 小调 iiø-V (用户报告) ──
dump("副属链+iiø-V: Em7b5-A7b9-Dm7-G7-C6-A7-D7-G7 (应 iiø-Valt-ii-V-I-VI7-II7-V)",
     buildRoadmap([("Em7b5",2),("A7b9",2),("Dm7",4),("G7",4),("C6",4),("A7",4),("D7",4),("G7",4)]), tonicPC: 0, mode: .major)

// ── IV7 借用 (用户报告: Bb7 应 IV7 of F, 不是独立 Bb 调 I) ──
dump("IV7借用: Gm7-C7-Fmaj7-Bb7-Em7-A7 (应 ii-V-I-IV7-ii-V)",
     buildRoadmap([("Gm7",4),("C7",4),("Fmaj7",4),("Bb7",4),("Em7",4),("A7",4)]), tonicPC: 5, mode: .major)

// ── IV7 借用回归 (确保优先级 1 优先, 不误伤 V-I / backdoor) ──
dump("IV7回归 V-I优先: Fmaj7-C7-Fmaj7 (C7 应 V in F, 不是 G 的 IV7)",
     buildRoadmap([("Fmaj7",4),("C7",4),("Fmaj7",4)]), tonicPC: 5, mode: .major)

dump("IV7回归 backdoor不误伤: Fm7-Bb7-Cmaj7 (Bb7 应 bVII7 in C, 前面是 minor 不触发 IV7)",
     buildRoadmap([("Fm7",4),("Bb7",4),("Cmaj7",4)]), tonicPC: 0, mode: .major)

// ── 回归用例 ──
dump("回归 连续 iiø-V-i: Bm7b5-E7b9-Am7 (应 iiø-V7alt-I)",
     buildRoadmap([("Bm7b5",2),("E7b9",2),("Am7",4)]), tonicPC: 9, mode: .minor)

dump("回归 连续 ii-V-I: Am7-D7-Gmaj7 (应 ii-V-I in G)",
     buildRoadmap([("Am7",4),("D7",4),("Gmaj7",4)]), tonicPC: 7, mode: .major)

dump("回归 vi-ii-V-I: Am7-Dm7-G7-Cmaj7 (应 vi-ii-V-I in C)",
     buildRoadmap([("Am7",4),("Dm7",4),("G7",4),("Cmaj7",4)]), tonicPC: 0, mode: .major)

dump("回归 maj7大写: Gbm7-B7-Emaj7 (应 ii-V-I in E)",
     buildRoadmap([("Gbm7",4),("B7",4),("Emaj7",4)]), tonicPC: 8, mode: .major)

dump("回归 多组转调: Dm7-G7-Cmaj7-Cm7-F7-Bbmaj7 (两组 ii-V-I)",
     buildRoadmap([("Dm7",4),("G7",4),("Cmaj7",4),("Cm7",4),("F7",4),("Bbmaj7",4)]), tonicPC: 0, mode: .major)

// ── Demo 完整序列 ──
let demoChords: [(String, Double)] = [
    ("Am7",4),("Dm7",4),("G7",4),("Cmaj7",4),("Fmaj7",4),("B7",4),("Emaj7",4),("Emaj7",4),
    ("Em7",4),("Am7",4),("D7",4),("Gmaj7",4),("Cmaj7",4),("F#7",4),("Bmaj7",4),("Bmaj7",4),
    ("C#m7",4),("F#7",4),("Bmaj7",4),("Bmaj7",4),("Bbm7",4),("Eb7",4),("Abmaj7",4),("E7b13",4),
    ("Am7",4),("Dm7",4),("G7",4),("Cmaj7",4),("Fmaj7",4),("Fm7",4),("Em7",4),("Ebdim7",4),
    ("Dm7",4),("G7",4),("Cmaj7",4),("Bm7b5",2),("E7b9",2),
]
dump("Demo 完整序列 (末尾 Bm7b5-E7b9 应 iiø-V7alt)",
     buildRoadmap(demoChords, sectionStarts: [0, 8, 16, 24]), tonicPC: 0, mode: .major)
