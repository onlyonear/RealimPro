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
    print("=== \(title) (home tonic=\(tonicPC)) ===")
    for measure in result.measures {
        let parts = measure.chordAnalyses.map { "\($0.chord)[tc=\($0.tonalCenterPC),\($0.functionLabel)]" }.joined(separator: " ")
        print("  \(parts)")
    }
}

// All The Things You Are 关键片段 (全曲 Ab 调, tonicPC=8)
dump("Gbm7-B7-Emaj7 (E大调 ii-V-I, 但全曲Ab调)",
     buildRoadmap([("Gbm7",4),("B7",4),("Emaj7",4)]),
     tonicPC: 8, mode: .major)

dump("Am7-D7-Gmaj7 (G大调 ii-V-I, 但全曲Ab调)",
     buildRoadmap([("Am7",4),("D7",4),("Gmaj7",4)]),
     tonicPC: 8, mode: .major)

// 对照: 用户最初验收用例 (C大调)
dump("Am7-Dm7-G7-Cmaj7 (C大调 vi-ii-V-I)",
     buildRoadmap([("Am7",4),("Dm7",4),("G7",4),("Cmaj7",4)]),
     tonicPC: 0, mode: .major)
