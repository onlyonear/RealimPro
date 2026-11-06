import Foundation

// 调试脚本：打印 A Foggy Day 每个和弦在 findKeys / resolveDominantLaunchers /
// resolveBorrowedMajors 三个阶段的调性中心变化，定位归调错误的根因。

@main
struct DebugKeys {
static func pcName(_ pc: Int) -> String {
    switch ((pc % 12) + 12) % 12 {
    case 0: return "C"; case 1: return "Db"; case 2: return "D"; case 3: return "Eb"
    case 4: return "E"; case 5: return "F"; case 6: return "Gb"; case 7: return "G"
    case 8: return "Ab"; case 9: return "A"; case 10: return "Bb"; case 11: return "B"
    default: return "?"
    }
}

static func main() {
let url = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "irealb://A%20Foggy%20Day=Gershwin%20George==Medium%20Swing=F==1r34LbKcu7A%7CQyX4F%5E7XX7%5EF%7CQyX96bB%7CQXy7%5EF%7CQyX96bB%7CQyyQ%7CE74Tv%2A%5B%209%2DAZD13XyD%207%2DAZL6%2DA%20%2DA%7CyQX7%5EFZL7C%207%2DG%7CQ13b9L%7CQyX%2DyX7%2DG%2D7%20C7b7D%7CQyX7%5EFA%2A%7B%5D7%20C%207%2DGZL7D%206FZL9XyQ%7CGZL9DF%207%2DCyQ%7CF6%5EF1NB%2A%5B%5DQyX7C%7CyQX7G%7CQyX7bA%7CQyX7XyQ%7CX7C%7CQ%2DC2NC%5E7XyQX7C%7CQyX7G%7CQyX7%7CDQyX7%2DA%7CQyX7bE%7CyQ%7D%5B%2AbBZL7C%2F7%2DGF7XyQFZLC%2F7%2DG%20C%2F7%5EFQ%7CyX7bE%7CQyX7%5EbB%7C%5E7%2FC%20%7CQyX7LZF%5E7%2FC%20D%2D7LZG%2D7%20C7LZF6XyQ%7CG%2D7%20C7%20Z%20==0=0==="

guard let song = IRealProParser.parse(url: url) else {
    print("解析失败"); return
}
let keyInfo = KeyParser.parseKey(song.key)
let beatsPerMeasure = Double(song.timeSignature.first?.wholeNumberValue ?? 4)
let tonicPC = keyInfo.tonicPC
let mode = keyInfo.mode

let roadmap = JazzRoadmap(title: song.title, tempo: song.tempo)
for (mi, measureChords) in song.measures.enumerated() {
    let durs = mi < song.measureDurations.count ? song.measureDurations[mi] : [beatsPerMeasure]
    let pairs = zip(measureChords, durs).filter { c, _ in
        let cl = c.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cl.isEmpty && cl != "NC" && cl != "N.C."
    }
    for (chordName, duration) in pairs {
        let clean = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSectionStart = song.sectionMarkers[mi] != nil
        roadmap.append(block: ChordBlock(name: clean, duration: duration, isSectionStart: isSectionStart))
    }
}

// 构建分析侧和弦（复制 analyze 逻辑）
let flat = roadmap.flattenRoadmap()
var chords: [PostProcessorFull.AnalysisChord] = []
for (idx, cb) in flat.enumerated() {
    let (rootPC, quality) = PostProcessorFull.parseRootQuality(cb.name)
    let isSectionEnd = (idx + 1 < flat.count) ? flat[idx + 1].isSectionStart : false
    chords.append(PostProcessorFull.AnalysisChord(
        name: cb.name, rootPC: rootPC,
        mode: PostProcessorFull.chordMode(ofQuality: quality),
        qualityClass: PostProcessorFull.qualityClass(ofQuality: quality),
        duration: cb.duration, isSectionEnd: isSectionEnd))
}

print("主调 \(pcName(tonicPC)) \(mode == .minor ? "小调" : "大调")，共 \(chords.count) 个和弦\n")

// 阶段 1: findKeys
let keySpans = PostProcessorFull.findKeys(chords, tonicPC: tonicPC)
print("── findKeys 输出的 KeySpan 链 ──")
for span in keySpans {
    print("  [\(span.startIdx)..<\(span.endIdx)) key=\(pcName(span.key)) mode=\(span.mode)")
}

var tonalCenters = Array(repeating: tonicPC, count: chords.count)
var keyModes = Array(repeating: mode == .minor ? "Minor" : "Major", count: chords.count)
for span in keySpans {
    if span.startIdx < span.endIdx {
        for idx in span.startIdx..<span.endIdx where idx < chords.count {
            tonalCenters[idx] = span.key
            keyModes[idx] = span.mode
        }
    }
}

print("\n── findKeys 后逐和弦 tonalCenter ──")
for (i, c) in chords.enumerated() {
    let sect = c.isSectionEnd ? " [段尾]" : ""
    print("  #\(String(format: "%2d", i)) \(c.name.padding(toLength: 8, withPad: " ", startingAt: 0)) root=\(pcName(c.rootPC)) \(c.qualityClass) -> tc=\(pcName(tonalCenters[i])) mode=\(keyModes[i])\(sect)")
}

// 阶段 2: resolveDominantLaunchers
PostProcessorFull.resolveDominantLaunchers(chords: chords, tonalCenters: &tonalCenters, keyModes: &keyModes, tonicPC: tonicPC, songMode: mode)
print("\n── resolveDominantLaunchers 后 ──")
for (i, c) in chords.enumerated() {
    print("  #\(String(format: "%2d", i)) \(c.name.padding(toLength: 8, withPad: " ", startingAt: 0)) -> tc=\(pcName(tonalCenters[i])) mode=\(keyModes[i])")
}

// 阶段 3: resolveBorrowedMajors
PostProcessorFull.resolveBorrowedMajors(chords: chords, tonalCenters: &tonalCenters, keyModes: &keyModes, tonicPC: tonicPC)
print("\n── resolveBorrowedMajors 后 ──")
for (i, c) in chords.enumerated() {
    print("  #\(String(format: "%2d", i)) \(c.name.padding(toLength: 8, withPad: " ", startingAt: 0)) -> tc=\(pcName(tonalCenters[i])) mode=\(keyModes[i])")
}

// 阶段 4: resolveMinorTonics (最终)
PostProcessorFull.resolveMinorTonics(chords: chords, tonalCenters: &tonalCenters, keyModes: &keyModes)
print("\n── resolveMinorTonics 后 (最终) ──")
for (i, c) in chords.enumerated() {
    let (_, q) = PostProcessorFull.parseRootQuality(flat[i].name)
    let label = PostProcessorFull.degreeLabel(rootPC: c.rootPC, family: flat[i].getChordFamily(), tonicPC: tonalCenters[i], mode: keyModes[i], quality: q)
    print("  #\(String(format: "%2d", i)) \(c.name.padding(toLength: 8, withPad: " ", startingAt: 0)) -> \(label.padding(toLength: 6, withPad: " ", startingAt: 0)) tc=\(pcName(tonalCenters[i])) mode=\(keyModes[i])")
}
}
}
