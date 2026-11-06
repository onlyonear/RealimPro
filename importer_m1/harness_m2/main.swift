import Foundation

let REF2 = "/Users/onlyonear/Desktop/Improlyze/importer_m1/ref2"
let MXL = "/Users/onlyonear/Desktop/video_shoot/jazz_songs/effendi/mxl_all"
let OUT = "/Users/onlyonear/Desktop/Improlyze/importer_m1/swift2"
try? FileManager.default.createDirectory(atPath: OUT, withIntermediateDirectories: true)
let fm = FileManager.default

func readJSON(_ path: String) -> [String: Any]? {
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
    return o
}

let manifestData = try Data(contentsOf: URL(fileURLWithPath: REF2 + "/_manifest.json"))
let manifest = try JSONSerialization.jsonObject(with: manifestData) as! [[String: Any]]

var mapMatch = 0, mapMismatch = 0, shouldBlockButOk = 0
var threwButShouldExpand: [(String, String)] = []
var gateOther: [(String, String)] = []
var blockCorrect = 0, blockWrongType: [(String, String, String)] = []
var mapMismatchList: [(String, [Int], [Int])] = []
var aggTotal = 0, aggMiss = 0
var aggMissKinds: [String: Int] = [:]

for entry in manifest {
    let file = entry["file"] as! String
    let status = entry["status"] as! String
    let base = (file as NSString).deletingPathExtension
    fputs(".. \(status) \(file)\n", stderr)
    let srcURL = URL(fileURLWithPath: MXL).appendingPathComponent(file)
    guard let src = try? Data(contentsOf: srcURL) else { print("SRC MISSING \(file)"); continue }

    let expectedBlock = status != "expand_ok" && status != "norepeat"
    var thrown: String?
    var res: MusicXMLImportResult?
    do {
        res = try MusicXMLImporter.importSong(data: src, fallbackTitle: base)
    } catch let e as MusicXMLImportError {
        thrown = e.description
    } catch {
        thrown = "\(error)"
    }

    if expectedBlock {
        if let t = thrown {
            // nav 必须报 navigation；multipart 必须报 multiPart；notexpandable 报 malformedRepeat
            let okType: Bool
            if status == "nav_block" { okType = t.contains("D.S") || t.contains("导航") }
            else if status == "multipart_block" { okType = t.contains("多 Part") }
            else { okType = t.contains("V8") }
            if okType { blockCorrect += 1 } else { blockWrongType.append((file, status, t)) }
        } else {
            shouldBlockButOk += 1
            print("!! SHOULD BLOCK BUT IMPORTED: \(file) (\(status))")
        }
        continue
    }

    // 期望可展开（music21 可展；但 App 仍可能因拍号/无和弦等其它闸门拦截）
    if let t = thrown {
        if t.contains("V8") {
            threwButShouldExpand.append((file, t))   // 反复相关失败，真问题
        } else {
            gateOther.append((file, t))               // 其它闸门（拍号/无和弦），与反复无关
        }
        continue
    }
    guard let r = res else { continue }

    // 比对 measureMap（黄金基准）
    if let golden = readJSON(REF2 + "/\(base).m2.json"),
       let gmap = golden["map"] as? [Int],
       let smap = r.diag["repeatMap"] as? [Int] {
        if smap == gmap { mapMatch += 1 } else {
            mapMismatch += 1
            mapMismatchList.append((file, gmap, smap))
        }
    }

    // 写输出供逐小节对拍
    let out: [String: Any] = ["file": file, "song": r.song, "diag": r.diag,
                              "resolveTotal": r.resolveTotal, "resolveMiss": r.resolveMiss,
                              "missKinds": r.missKinds]
    if let od = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys, .prettyPrinted]) {
        try? od.write(to: URL(fileURLWithPath: OUT).appendingPathComponent(base + ".swift.json"))
    }
    aggTotal += r.resolveTotal; aggMiss += r.resolveMiss
    for (k, v) in r.missKinds { aggMissKinds[k, default: 0] += v }
}

print("== M2 harness ==")
print("expand_ok map MATCH=\(mapMatch) MISMATCH=\(mapMismatch)")
print("expected-block correctly blocked=\(blockCorrect) wrongType=\(blockWrongType.count) shouldBlockButImported=\(shouldBlockButOk)")
print("threw V8 but should expand=\(threwButShouldExpand.count) | other-gate blocks=\(gateOther.count)")
for (f, t) in threwButShouldExpand.sorted(by: { $0.0 < $1.0 }) { print("   THREW \(f): \(t)") }
for (f, t) in gateOther.sorted(by: { $0.0 < $1.0 }) { print("   GATEOTHER \(f): \(t)") }
for (f, s, t) in blockWrongType { print("   WRONGBLOCKTYPE \(f) [\(s)]: \(t)") }
for (f, g, s) in mapMismatchList {
    print("   MAPDIFF \(f): golden=\(g) swift=\(s)")
}
let rate = aggTotal > 0 ? String(format: "%.2f%%", Double(aggTotal - aggMiss) / Double(aggTotal) * 100) : "n/a"
print("resolve total=\(aggTotal) miss=\(aggMiss) hitRate=\(rate)")
for (k, v) in aggMissKinds.sorted(by: { $0.value > $1.value }) { print("  miss \(v)x  \(k)") }
