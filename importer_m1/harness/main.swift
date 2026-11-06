import Foundation

let REF = "/Users/onlyonear/Desktop/Improlyze/importer_m1/ref"
let MXL = "/Users/onlyonear/Desktop/video_shoot/jazz_songs/effendi/mxl_all"
let OUT = "/Users/onlyonear/Desktop/Improlyze/importer_m1/swift"
try? FileManager.default.createDirectory(atPath: OUT, withIntermediateDirectories: true)

let fm = FileManager.default
let refFiles = (try? fm.contentsOfDirectory(atPath: REF))?
    .filter { $0.hasSuffix(".ref.json") }.sorted() ?? []

var ok = 0
var blocked: [(String, String)] = []
var aggTotal = 0, aggMiss = 0
var aggMissKinds: [String: Int] = [:]

for rf in refFiles {
    let refURL = URL(fileURLWithPath: REF).appendingPathComponent(rf)
    guard let data = try? Data(contentsOf: refURL),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let file = json["file"] as? String else {
        blocked.append((rf, "bad ref json")); continue
    }
    let base = file
    let srcURL = URL(fileURLWithPath: MXL).appendingPathComponent(file)
    guard let src = try? Data(contentsOf: srcURL) else {
        blocked.append((base, "src missing")); continue
    }
    do {
        let res = try MusicXMLImporter.importSong(data: src, fallbackTitle: (file as NSString).deletingPathExtension)
        let out: [String: Any] = [
            "file": file,
            "song": res.song,
            "resolveTotal": res.resolveTotal,
            "resolveMiss": res.resolveMiss,
            "missKinds": res.missKinds,
            "diag": res.diag,
        ]
        let odata = try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys, .prettyPrinted])
        let outName = ((file as NSString).deletingPathExtension) + ".swift.json"
        try odata.write(to: URL(fileURLWithPath: OUT).appendingPathComponent(outName))
        ok += 1
        aggTotal += res.resolveTotal; aggMiss += res.resolveMiss
        for (k, v) in res.missKinds { aggMissKinds[k, default: 0] += v }
    } catch let e as MusicXMLImportError {
        blocked.append((base, e.description))
    } catch {
        blocked.append((base, "\(error)"))
    }
}

print("== Swift importer harness ==")
print("ref=\(refFiles.count) ok=\(ok) blocked=\(blocked.count)")
for (b, r) in blocked.sorted(by: { $0.0 < $1.0 }) { print("  BLOCK \(b): \(r)") }
let rate = aggTotal > 0 ? String(format: "%.2f%%", Double(aggTotal - aggMiss) / Double(aggTotal) * 100) : "n/a"
print("resolve total=\(aggTotal) miss=\(aggMiss) hitRate=\(rate)")
for (k, v) in aggMissKinds.sorted(by: { $0.value > $1.value }) { print("  miss \(v)x  \(k)") }
