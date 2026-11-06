import Foundation

let MXL = "/Users/onlyonear/Desktop/video_shoot/jazz_songs/effendi/mxl_all"
let SW2 = "/Users/onlyonear/Desktop/Improlyze/importer_m1/swift2"
let SW1 = "/Users/onlyonear/Desktop/Improlyze/importer_m1/swift"

let v17 = Set(["MyFavoriteThings(Coltrane)"])
let v20 = Set(["MyMama", "MrMagic", "Arriving Soon", "InnerCityBlues", "SoulfulStrut",
                "Brother Ray", "WhenTheSunComesDown"])
let gated = v17.union(v20)

var priorSucc = Set<String>()
for dir in [SW1, SW2] {
    for p in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where p.hasSuffix(".swift.json") {
        priorSucc.insert(String(p.dropLast(".swift.json".count)))
    }
}

let files = ((try? FileManager.default.contentsOfDirectory(atPath: MXL)) ?? [])
    .filter { $0.hasSuffix(".xml") || $0.hasSuffix(".musicxml") }

var okCount = 0, throwCount = 0
var failures = [String]()
var codeCount = [String: Int]()

for fn in files {
    let base = fn.hasSuffix(".musicxml") ? String(fn.dropLast(9)) : String(fn.dropLast(4))
    let url = URL(fileURLWithPath: MXL).appendingPathComponent(fn)
    guard let data = try? Data(contentsOf: url) else { failures.append("read \(fn)"); continue }
    let expectSuccess = priorSucc.contains(base) && !gated.contains(base)
    do {
        let json = try MusicXMLImporter.libraryForApp(data: data, fallbackTitle: base)
        guard expectSuccess else { failures.append("should throw but imported: \(fn)"); continue }
        let lib = try BuiltinMelodyLibrary.load(from: json)
        guard let b = lib.songs.first else { failures.append("decode empty \(fn)"); continue }
        if b.melody.count != lib.playlist.songs[0].measures.count {
            failures.append("measure count mismatch \(fn) mel=\(b.melody.count) song=\(lib.playlist.songs[0].measures.count)")
            continue
        }
        okCount += 1
    } catch let e as MusicXMLImportError {
        guard !expectSuccess else { failures.append("should import but threw \(fn): \(e.description)"); continue }
        let code = String(e.description.prefix(3))
        codeCount[code, default: 0] += 1
        throwCount += 1
    } catch {
        failures.append("unexpected error \(fn): \(error)")
    }
}

print("M3: importedOK=\(okCount) threwOK=\(throwCount) failures=\(failures.count)")
print("block codes:", codeCount.sorted { ($0.value, $0.key) > ($1.value, $1.key) })
for f in failures { print("  FAIL", f) }
