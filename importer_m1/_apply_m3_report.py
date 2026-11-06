#!/usr/bin/env python3
import io,sys
P="/Users/onlyonear/Desktop/Improlyze/Real imPro/Views/ContentView.swift"
s=io.open(P,encoding="utf-8").read()
edits=[]

# 1) struct field
edits.append(('''        /// 外部旋律 JSON 导入时携带的「标题|作曲家 → 原旋律」索引（仅本文件；iRealPro 导入为 nil）
        var externalMelodies: [String: [GeneratedMeasure]]? = nil
    }
''','''        /// 外部旋律 JSON 导入时携带的「标题|作曲家 → 原旋律」索引（仅本文件；iRealPro 导入为 nil）
        var externalMelodies: [String: [GeneratedMeasure]]? = nil
        /// MusicXML 成功导入后的说明（风格固定 / 速度）；其余导入为 nil
        var reportNote: String? = nil
    }
'''))

# 2) state var
edits.append(('''    @State private var fileImportError: String? = nil // 🌟 文件级错误消息
''','''    @State private var fileImportError: String? = nil // 🌟 文件级错误消息
    @State private var importReportNote: String? = nil // MusicXML 成功导入说明（风格/速度）
'''))

# 3) error branch reset + success capture + alert decision
edits.append(('''        if let error = result.error, result.songs.isEmpty {
            fileImportError = error
            importedTotalCount = 0
            importSkippedCount = 0
            mixedAlertCount = 0
            showImportResultAlert = true
            return
        }

        fileImportError = nil
''','''        if let error = result.error, result.songs.isEmpty {
            fileImportError = error
            importReportNote = nil
            importedTotalCount = 0
            importSkippedCount = 0
            mixedAlertCount = 0
            showImportResultAlert = true
            return
        }

        fileImportError = nil
        importReportNote = result.reportNote
'''))

edits.append(('''        showImportResultAlert = hasMixed || hasSkipped || !hasNew
    }
''','''        showImportResultAlert = hasMixed || hasSkipped || !hasNew || (importReportNote != nil)
    }
'''))

# 4) alert message branch
edits.append(('''                if let fileError = fileImportError {
                    Text(fileError)
                } else if importedTotalCount == 0 {
''','''                if let fileError = fileImportError {
                    Text(fileError)
                } else if let note = importReportNote {
                    Text(note)
                } else if importedTotalCount == 0 {
'''))

# 5) success return in importMusicXML
edits.append(('''            return FileImportResult(songs: lib.playlist.songs, error: nil, groupName: nil, externalMelodies: mel)
''','''            let tempo = first.song.tempo
            let note = String(format: NSLocalizedString(
                "已导入《%@》。MusicXML 无可靠风格字段，伴奏统一按 Medium Swing（中等摇摆）处理；速度 %d BPM。原曲旋律与和弦可直接显示、播放与即兴。",
                comment: ""), first.title, tempo)
            return FileImportResult(songs: lib.playlist.songs, error: nil, groupName: nil,
                                    externalMelodies: mel, reportNote: note)
'''))

for i,(old,new) in enumerate(edits):
    c=s.count(old)
    if c!=1:
        print(f"ABORT edit#{i}: occurrences={c}"); sys.exit(1)
    s=s.replace(old,new)
io.open(P,"w",encoding="utf-8").write(s)
print("OK report edits applied:",len(edits))
