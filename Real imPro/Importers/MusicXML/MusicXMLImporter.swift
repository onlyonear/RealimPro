import Foundation

enum MusicXMLImportError: Error, CustomStringConvertible {
    case parse(String)
    case noMeasures
    case noHarmony
    case multiPart(Int)
    case drum
    case transpose
    case unsupportedMeter(String)
    case mixedMeter
    case navigation
    case malformedRepeat(String)
    case unresolvedChords(miss: Int, total: Int)
    case nonConserved(String)
    // [旧码封存 P1修复 20261010] description 原为中文硬编码（"XML 解析失败: …"/"V3 小节为空"/"V6 全曲无和弦"/
    // "V4 多 Part(n)，M3 前拦截"/"V? 鼓/谱号不支持"/"V19 含移调乐器 transpose"/"V5 不支持的拍号 t"/
    // "V5 曲中换拍/混合拍"/"V8 含 D.S./D.C./Coda/Fine …"/"V8 s"/"V17 …比例过高…"/"V20 …时值不守恒…"），
    // 现统一改走 NSLocalizedString（英文表补 value），插值与分支逻辑零改动。
    var description: String {
        switch self {
        case .parse(let s):
            return String(format: NSLocalizedString("XML 解析失败: %@", comment: ""), s)
        case .noMeasures:
            return NSLocalizedString("V3 小节为空", comment: "")
        case .noHarmony:
            return NSLocalizedString("V6 全曲无和弦", comment: "")
        case .multiPart(let n):
            return String(format: NSLocalizedString("V4 多 Part(%d)，M3 前拦截", comment: ""), n)
        case .drum:
            return NSLocalizedString("V? 鼓/谱号不支持", comment: "")
        case .transpose:
            return NSLocalizedString("V19 含移调乐器 transpose", comment: "")
        case .unsupportedMeter(let t):
            return String(format: NSLocalizedString("V5 不支持的拍号 %@", comment: ""), t)
        case .mixedMeter:
            return NSLocalizedString("V5 曲中换拍/混合拍", comment: "")
        case .navigation:
            return NSLocalizedString("V8 含 D.S./D.C./Coda/Fine 等导航跳转，暂不支持，已拦截", comment: "")
        case .malformedRepeat(let s):
            return String(format: NSLocalizedString("V8 %@", comment: ""), s)
        case .unresolvedChords(let miss, let total):
            return String(format: NSLocalizedString(
                "V17 和弦无法识别比例过高（%d 个中有 %d 个无法识别，超过 20%），已拦截", comment: ""),
                total, miss)
        case .nonConserved(let s):
            return String(format: NSLocalizedString("V20 存在时值不守恒小节（%@），已拦截", comment: ""), s)
        }
    }
}

struct MusicXMLImportResult {
    var song: [String: Any]
    var diag: [String: Any]
    var resolveTotal = 0
    var resolveMiss = 0
    var missKinds: [String: Int] = [:]
}

enum MusicXMLImporter {

    static func importSong(data: Data, fallbackTitle: String) throws -> MusicXMLImportResult {
        let sc = MusicXMLParser.parse(data: data)
        if let e = sc.parseError { throw MusicXMLImportError.parse(e) }
        if sc.partCount > 1 { throw MusicXMLImportError.multiPart(sc.partCount) }
        if sc.hasDrum { throw MusicXMLImportError.drum }
        if sc.hasTranspose { throw MusicXMLImportError.transpose }
        if sc.mixedMeter { throw MusicXMLImportError.mixedMeter }
        if sc.unsupportedMeter { throw MusicXMLImportError.unsupportedMeter(sc.timeSignature) }
        if sc.measures.isEmpty { throw MusicXMLImportError.noMeasures }
        if !sc.hasAnyHarmony { throw MusicXMLImportError.noHarmony }
        if sc.hasNav { throw MusicXMLImportError.navigation }

        // M2：先全量解析为中间模型，再展开反复（backward 需回溯 forward，禁止流式）。
        let repeatResult: (measures: [MXRawMeasure], map: [Int])
        do {
            repeatResult = try MusicXMLRepeater.expand(sc.measures)
        } catch let e as MusicXMLRepeatError {
            throw MusicXMLImportError.malformedRepeat(e.description)
        }
        var work = sc
        work.measures = repeatResult.measures

        let (out, buildDiag) = MusicXMLQuantizer.buildMeasures(work)
        let (measures, bad) = MusicXMLQuantizer.finalize(out)

        // resolve 命中率（V17）——按展开后的实际和弦统计
        var total = 0, miss = 0
        var missKinds: [String: Int] = [:]
        for m in work.measures {
            for h in m.harmonies {
                total += 1
                if !MusicXMLChordMapper.resolvable(h.chord) {
                    miss += 1
                    missKinds[h.chord, default: 0] += 1
                }
            }
        }

        let title = sc.title.isEmpty ? fallbackTitle : sc.title
        let song: [String: Any] = [
            "title": title,
            "composer": sc.composer,
            "key": sc.keyName,
            "timeSignature": sc.timeSignature,
            "style": "Medium Swing",
            "tempo": sc.tempo,
            "measures": measures,
        ]
        var diag = buildDiag
        diag["nonConserved"] = bad
        diag["barCount"] = measures.count
        diag["rawBars"] = sc.measures.count
        diag["expandedBars"] = repeatResult.measures.count
        diag["repeatMap"] = repeatResult.map
        diag["hasRepeat"] = sc.hasRepeatOrEnding
        return MusicXMLImportResult(song: song, diag: diag,
                                    resolveTotal: total, resolveMiss: miss, missKinds: missKinds)
    }

    // MARK: - App 接线入口（M3）：在 M1/M2 纯算法之上叠加 V17 / V20 硬闸门，
    // 产出与 BuiltinMelodyLibrary DTO 同构的曲库 JSON（含 1 首），交由 App 解码落库。
    static func libraryForApp(data: Data, fallbackTitle: String) throws -> Data {
        let r = try importSong(data: data, fallbackTitle: fallbackTitle)

        // V17：单首未解析和弦比例 > 20% → 拦截
        if r.resolveTotal > 0,
           Double(r.resolveMiss) / Double(r.resolveTotal) > 0.20 {
            throw MusicXMLImportError.unresolvedChords(miss: r.resolveMiss, total: r.resolveTotal)
        }
        // V20：存在时值不守恒小节 → 拦截
        if let bad = r.diag["nonConserved"] as? [String], !bad.isEmpty {
            throw MusicXMLImportError.nonConserved(bad.joined(separator: ", "))
        }

        let library: [String: Any] = [
            "playlistName": "MusicXML Imports",
            "playlistNameZh": "导入的乐谱",
            "songCount": 1,
            "songs": [r.song],
        ]
        guard JSONSerialization.isValidJSONObject(library) else {
            throw MusicXMLImportError.parse(NSLocalizedString("内部数据无法序列化为 JSON", comment: ""))
        }
        return try JSONSerialization.data(withJSONObject: library, options: [])
    }
}
