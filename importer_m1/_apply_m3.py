#!/usr/bin/env python3
import io,sys
P="/Users/onlyonear/Desktop/Improlyze/Real imPro/Views/ContentView.swift"
s=io.open(P,encoding="utf-8").read()

OLD1='''            }
        }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return FileImportResult(songs: [], error: NSLocalizedString("无法读取文件，请确认文件编码为 UTF-8。", comment: ""))
        }
'''
NEW1='''            }
        }

        // —— MusicXML 导入分支 —— .mxl(压缩)二期；.musicxml 直接走；.xml 先嗅探 <score-partwise>
        let ext = url.pathExtension.lowercased()
        if ext == "mxl" {
            return FileImportResult(songs: [], error: NSLocalizedString(
                "暂不支持压缩的 .mxl 文件，请在“文件”App 中解压或另存为 .musicxml/.xml 后再导入。", comment: ""))
        }
        if ext == "musicxml" {
            guard let data = try? Data(contentsOf: url) else {
                return FileImportResult(songs: [], error: NSLocalizedString("无法读取文件。", comment: ""))
            }
            return Self.importMusicXML(data: data, url: url)
        }
        if ext == "xml", let data = try? Data(contentsOf: url) {
            let head = String(data: data.prefix(8192), encoding: .utf8) ?? ""
            if head.contains("score-partwise") {
                return Self.importMusicXML(data: data, url: url)
            }
            // 非 score-partwise 的 .xml：当作普通文本，继续走下面的 iReal Pro 解析
        }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return FileImportResult(songs: [], error: NSLocalizedString("无法读取文件，请确认文件编码为 UTF-8。", comment: ""))
        }
'''

OLD2='''        let groupName: String? = songs.count == 1 ? nil : url.deletingPathExtension().lastPathComponent
        return FileImportResult(songs: songs, error: nil, groupName: groupName)
    }
'''
HELPER='''
    /// MusicXML → 解码为曲库 → 落库 ImportedMelodies，返回带旋律索引的导入结果
    private static func importMusicXML(data: Data, url: URL) -> FileImportResult {
        let fallback = url.deletingPathExtension().lastPathComponent
        do {
            let json = try MusicXMLImporter.libraryForApp(data: data, fallbackTitle: fallback)
            let lib = try BuiltinMelodyLibrary.load(from: json)
            guard let first = lib.songs.first else {
                return FileImportResult(songs: [], error: NSLocalizedString("MusicXML 中未解析出有效乐曲。", comment: ""))
            }
            // 唯一文件名（标题|作曲家），重导覆盖、不同曲不互相覆盖
            let key = Self.normalizedSongKey(title: first.title, composer: first.composer)
            let safe = ("mx_" + key)
                .replacingOccurrences(of: "|", with: "_")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ":", with: "_")
            persistExternalMelodyFile(data: json, name: safe)
            var mel: [String: [GeneratedMeasure]] = [:]
            for bs in lib.songs {
                mel[Self.normalizedSongKey(title: bs.title, composer: bs.composer)] = bs.melody
            }
            return FileImportResult(songs: lib.playlist.songs, error: nil, groupName: nil, externalMelodies: mel)
        } catch let e as MusicXMLImportError {
            return FileImportResult(songs: [], error: e.description)
        } catch {
            return FileImportResult(songs: [], error: NSLocalizedString(
                "MusicXML 解析失败，请确认是单 Part 的 lead sheet（和弦+旋律）。", comment: ""))
        }
    }
'''
NEW2=OLD2+HELPER

for tag,old,new in [("ROUTING",OLD1,NEW1),("HELPER",OLD2,NEW2)]:
    c=s.count(old)
    if c!=1:
        print(f"ABORT {tag}: occurrences={c}"); sys.exit(1)
    s=s.replace(old,new)
io.open(P,"w",encoding="utf-8").write(s)
print("OK both edits applied")
