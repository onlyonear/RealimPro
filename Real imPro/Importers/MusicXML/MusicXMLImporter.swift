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
        // [反复展开 v2] 不再硬拦截 hasNav，改为展开后标注"导航未展开"

        // M2：先全量解析为中间模型，再展开反复（backward 需回溯 forward，禁止流式）。
        // [反复展开 v2] 用 expandSafely，失败时降级为恒等序列 + hadError 标记
        let repeatResult = MusicXMLRepeater.expandSafely(sc.measures)

        // G4：在普通反复展开后的 map 上做导航后处理（D.S./D.C./Coda/Fine）。
        // 普通反复展开失败（hadError）时不做导航，避免「反复没展开、只展开 D.S.」的半成品。
        let navResult: MXNavResult = repeatResult.hadError
            ? MXNavResult(map: repeatResult.map, applied: false)
            : MusicXMLRepeater.applyNavigation(map: repeatResult.map, raw: sc.measures)

        // 导航成功：按 finalMap（元素是源小节号）从普通反复展开结果里取对应 measure 重排；
        // 任何降级：沿用普通反复展开 measures，保持现状。
        var expandedMeasures = repeatResult.measures
        var finalMap = repeatResult.map
        // navApplied 只在「合规且覆盖检查通过、真正采用导航 map」时为 true；
        // 覆盖检查失败导致数据层降级时，标记必须同步为 false，不能让 diag/横幅说谎。
        var navApplied = false
        if navResult.applied {
            var measureBySource: [Int: MXRawMeasure] = [:]
            for (pos, srcIdx) in repeatResult.map.enumerated()
            where measureBySource[srcIdx] == nil {
                measureBySource[srcIdx] = repeatResult.measures[pos]
            }
            // 坐标系安全：导航 map 每个源号都必须落在普通反复 map 的覆盖集合内；
            // 缺一个就整体降级，绝不把源号当播放位置静默塞错小节。
            let covered = Set(repeatResult.map)
            if navResult.map.allSatisfy({ covered.contains($0) }) {
                finalMap = navResult.map
                expandedMeasures = navResult.map.map { measureBySource[$0]! }
                navApplied = true
            }
        }

        var work = sc
        work.measures = expandedMeasures

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

        // [反复展开 v2] 量化原始小节（Original 视图用）
        var rawWork = sc
        rawWork.measures = sc.measures  // 原始未展开
        let (rawOut, _) = MusicXMLQuantizer.buildMeasures(rawWork)
        let (rawMeasures, _) = MusicXMLQuantizer.finalize(rawOut)

        // [反复展开 v2] 提示标记
        let repeatsNotExpanded = repeatResult.hadError && sc.hasRepeatOrEnding
        // G4 横幅：与 diag 同一个 navApplied（真正采用才关），不在 SwiftUI 层另算。
        // 判据是「存在跳转类指令 D.S./D.C.」而非「有字形/有 Fine/有 To Coda」：
        // 纯 segno/coda 字形、孤立 Fine（无 D.S. al Fine 配合）、孤立 To Coda 都没有可执行跳转，
        // 与 Repeater 入口（dirSections 只统计 dalSegno/daCapo）对齐，保持现状即正确，不应凭空警告。
        let hasNavDirective = sc.measures.contains { m in
            m.navDirectives.contains { d in
                switch d.kind {
                case .dalSegno, .daCapo: return true
                case .toCoda, .fineMark: return false
                }
            }
        }
        let navigationNotExpanded = hasNavDirective && !navApplied

        // [反复展开 v3] 反复记号注解（原始谱视图绘制用）
        var repeatAnnotations: [[String: Any]] = []
        for (i, m) in sc.measures.enumerated() {
            var ann: [String: Any] = ["measureIndex": i]
            var hasAny = false

            if m.leftRepeat == "forward" {
                ann["leftRepeat"] = "forward"
                hasAny = true
            }
            if m.rightRepeat == "backward" {
                ann["rightRepeat"] = "backward"
                hasAny = true
            }

            // endStarts/endStops 是 [[Int]]（外层 barline，内层房子编号），flatMap 拍平
            if !m.endStarts.isEmpty {
                let starts = m.endStarts.flatMap { $0 }
                if !starts.isEmpty {
                    ann["voltaStart"] = starts
                    hasAny = true
                }
            }
            if !m.endStops.isEmpty {
                let stops = m.endStops.flatMap { $0 }
                if !stops.isEmpty {
                    ann["voltaStop"] = stops
                    hasAny = true
                }
            }

            // G4 导航：字形（segno/coda）+ 导航 words 原文。文字保留原文，
            // 不做枚举映射（真实谱文本形态多样，如 D.S.alfine / D.S.andfade）。
            if !m.navMarks.isEmpty {
                let glyphs = m.navMarks.map { $0.kind == .segno ? "segno" : "coda" }
                ann["navGlyphs"] = glyphs
                hasAny = true
            }
            if !m.navWords.isEmpty {
                ann["navTexts"] = m.navWords
                hasAny = true
            }

            if hasAny { repeatAnnotations.append(ann) }
        }

        let song: [String: Any] = [
            "title": title,
            "composer": sc.composer,
            "key": sc.keyName,
            "timeSignature": sc.timeSignature,
            "style": "Medium Swing",
            "tempo": sc.tempo,
            "measures": measures,
            "rawMeasures": rawMeasures,
            "repeatAnnotations": repeatAnnotations,
            "measureMap": finalMap,
            "repeatsNotExpanded": repeatsNotExpanded,
            "navigationNotExpanded": navigationNotExpanded,
        ]
        var diag = buildDiag
        diag["nonConserved"] = bad
        diag["barCount"] = measures.count
        diag["rawBars"] = sc.measures.count
        diag["expandedBars"] = expandedMeasures.count
        diag["repeatMap"] = repeatResult.map
        // 只在真正采用时报导航 map；降级（含覆盖检查失败）时回退到实际生效的反复 map，
        // 避免 diag 里出现"拟用未采用"的另一套坐标误导排查。
        diag["navMap"] = navApplied ? navResult.map : repeatResult.map
        diag["navApplied"] = navApplied
        diag["hasRepeat"] = sc.hasRepeatOrEnding
        diag["repeatsNotExpanded"] = repeatsNotExpanded
        diag["navigationNotExpanded"] = navigationNotExpanded
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
