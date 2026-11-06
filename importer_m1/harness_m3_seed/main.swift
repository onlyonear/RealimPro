import Foundation
let a = CommandLine.arguments
let outDir = a[1], src = a[2]
let data = try Data(contentsOf: URL(fileURLWithPath: src))
let json = try MusicXMLImporter.libraryForApp(data: data, fallbackTitle: "Blue Moon")
let lib = try BuiltinMelodyLibrary.load(from: json)
let songs = lib.songs.map { $0.song }
let playData = try JSONEncoder().encode(songs)
try FileManager.default.createDirectory(at: URL(fileURLWithPath: outDir), withIntermediateDirectories: true)
try playData.write(to: URL(fileURLWithPath: outDir).appendingPathComponent("playlists.json"))
let mdir = URL(fileURLWithPath: outDir).appendingPathComponent("ImportedMelodies")
try FileManager.default.createDirectory(at: mdir, withIntermediateDirectories: true)
try json.write(to: mdir.appendingPathComponent("mx_test_blueMoon.json"))
print("seeded", songs[0].title, "melodyBars", lib.songs[0].melody.count)
