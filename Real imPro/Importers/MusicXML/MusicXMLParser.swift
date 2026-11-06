import Foundation

// MARK: - 中间模型（MusicXML → 量化前）

/// 一个发声音/休止（dyad 和弦的多个组成音放在 components，旋律音在量化阶段挑选）
final class MXSoundEvent {
    var offQl: Double
    var ql: Double
    var isRest: Bool
    var tuplet: Bool
    var rawTie: String?            // start / continue / stop（music21 口径）
    var components: [(midi: Int, tie: String?)]
    init(offQl: Double, ql: Double, isRest: Bool, tuplet: Bool, rawTie: String?,
         components: [(midi: Int, tie: String?)]) {
        self.offQl = offQl; self.ql = ql; self.isRest = isRest
        self.tuplet = tuplet; self.rawTie = rawTie; self.components = components
    }
}

struct MXHarm { var offQl: Double; var chord: String }

final class MXRawMeasure {
    var sounds: [MXSoundEvent] = []
    var harmonies: [MXHarm] = []
    var contentEndQl: Double = 0   // 内容时间线长度（用于弱起 pad）

    // MARK: 反复记号（M2）
    var leftRepeat: String?        // 小节左 barline 上的 repeat 方向：forward / backward
    var leftRepeatTimes: Int?
    var rightRepeat: String?       // 小节右 barline 上的 repeat 方向
    var rightRepeatTimes: Int?
    var endStarts: [[Int]] = []    // 左 barline 上 type="start" 的 volta 房子编号集合
    var endStops: [[Int]] = []     // 右 barline 上 type="stop"/"discontinue" 的编号集合
    var nonStandardBarline = false // start 落在右 / stop 落在左等非标准摆位（黄金集无，直接拒）
}

struct MXScore {
    var title = ""
    var composer = ""
    var keyName = "C"
    var timeSignature = "4/4"
    var tempo = 120
    var gQl: Double = 4.0
    var spm = 480
    var measures: [MXRawMeasure] = []

    // 闸门标志（M3 校验用，M1 先记录）
    var partCount = 1
    var hasAnyHarmony = false
    var mixedMeter = false
    var unsupportedMeter = false
    var hasDrum = false
    var hasTranspose = false
    var hasRepeatOrEnding = false
    var hasNav = false
    var parseError: String?
}

// MARK: - SAX 解析

final class MusicXMLParser: NSObject, XMLParserDelegate {
    private var score = MXScore()

    // 运行上下文
    private var partCount = 0
    private var activePart = false
    private var curMeasure: MXRawMeasure?
    private var curDivisions: Double?
    private var cursor: Double = 0
    private var contentEnd: Double = 0

    // 全局调号/拍号
    private var gotKey = false
    private var tsSet = Set<String>()
    private var firstBeats = 4
    private var firstBeatType = 4

    // attributes 子上下文
    private var inKey = false
    private var curFifths = 0
    private var curMode: String?
    private var inTime = false
    private var beatsParts: [String] = []
    private var beatTypeParts: [String] = []
    private var inClef = false
    private var clefPercussion = false
    private var clefSign = ""

    // note 上下文
    private var curNote: N?
    private struct N {
        var isChord = false, isRest = false, isGrace = false
        var inPitch = false, inTM = false, inNotations = false
        var step = "", alter = 0, hasAlter = false, octave = 0
        var duration: Int?
        var actualNotes: Int?, normalNotes: Int?
        var hasType = false
        var hasTupletTag = false
        var tieStart = false, tieStop = false
    }

    // backup / forward
    private var inBackup = false, inForward = false
    private var bfDuration: Int?

    // barline / repeat / ending（M2）
    private var barlineLoc = "right"
    private var blRepeatDir: String?
    private var blRepeatTimes: Int?
    private var blEndingSet: [Int]?
    private var blEndingType: String?

    // harmony 上下文
    private var curHarmony: MXHarmony?
    private var inRoot = false, inBass = false, inDegree = false
    private var rootStep: String?, rootAlter = 0
    private var bassStep: String?, bassAlter = 0
    private var dValue = 0, dAlter = 0, dType: MXDegree.Kind?
    private var harmonyOffset: Int = 0
    private var inMetronome = false

    // metadata
    private var inWorkTitle = false, inMovementTitle = false
    private var creatorIsComposer = false
    private var inComposerCreator = false

    private var buffer = ""
    private static let navRegex = try! NSRegularExpression(
        pattern: "D\\.\\s*[SC]\\.|Dal\\s*Segno|Da\\s*Capo|al\\s*Coda|al\\s*Fine|To\\s*Coda|(^|[^a-z])fine([^a-z]|$)|(^|[^a-z])coda([^a-z]|$)|(^|[^a-z])segno([^a-z]|$)",
        options: [.caseInsensitive])

    static func parse(data: Data) -> MXScore {
        let p = MusicXMLParser()
        let xml = XMLParser(data: data)
        xml.delegate = p
        xml.shouldProcessNamespaces = false
        xml.shouldReportNamespacePrefixes = false
        let ok = xml.parse()
        if !ok, let e = xml.parserError {
            p.score.parseError = e.localizedDescription
        }
        p.finish()
        return p.score
    }

    private func finish() {
        score.partCount = partCount
        // 拍号
        let beats = firstBeats, bt = firstBeatType
        let g = Double(beats) * 4.0 / Double(bt)
        score.gQl = g
        score.spm = Int((g * 120.0).rounded())
        score.timeSignature = "\(beats)/\(bt)"
        let supported: Set<String> = ["4/4","2/2","3/4","2/4","1/2","6/8","12/8","5/4","6/4"]
        if tsSet.count > 1 { score.mixedMeter = true }
        if !supported.contains(score.timeSignature) { score.unsupportedMeter = true }
        if !gotKey { score.keyName = "C" }
    }

    // MARK: start

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        buffer = ""
        let e = elementName
        switch e {
        case "part-list": break
        case "score-part": partCount += 1
        case "part":
            partCountSeen += 1
            activePart = (partCountSeen == 1)
        case "measure":
            if activePart {
                curMeasure = MXRawMeasure(); cursor = 0; contentEnd = 0
            }
        case "attributes": break
        case "key": inKey = true; curFifths = 0; curMode = nil
        case "time": inTime = true; beatsParts = []; beatTypeParts = []
        case "clef": inClef = true; clefPercussion = false; clefSign = ""
        case "transpose": score.hasTranspose = true
        case "note": if curMeasure != nil { curNote = N() }
        case "chord": curNote?.isChord = true
        case "rest": curNote?.isRest = true
        case "grace": curNote?.isGrace = true
        case "pitch": curNote?.inPitch = true
        case "time-modification": curNote?.inTM = true
        case "notations": curNote?.inNotations = true
        case "backup": inBackup = true; bfDuration = nil
        case "forward": inForward = true; bfDuration = nil
        case "harmony":
            curHarmony = MXHarmony(rootStep: nil, kind: "")
            inRoot = false; inBass = false; inDegree = false
            rootStep = nil; rootAlter = 0; bassStep = nil; bassAlter = 0
            harmonyOffset = 0
        case "metronome": inMetronome = true
        case "root": inRoot = true
        case "bass": inBass = true
        case "degree":
            inDegree = true; dValue = 0; dAlter = 0; dType = nil
        case "tie":
            if let t = attributeDict["type"] {
                if t == "start" { curNote?.tieStart = true }
                if t == "stop" { curNote?.tieStop = true }
            }
        case "tuplet": curNote?.hasTupletTag = true
        case "percussion":
            if inClef { clefPercussion = true }
        case "work-title": inWorkTitle = true
        case "movement-title": inMovementTitle = true
        case "creator":
            inComposerCreator = (attributeDict["type"]?.lowercased() == "composer")
        case "ending", "repeat":
            score.hasRepeatOrEnding = true
            if e == "repeat" {
                blRepeatDir = attributeDict["direction"]
                blRepeatTimes = attributeDict["times"].flatMap { Int($0) }
            } else {
                blEndingSet = Self.parseEndingNumbers(attributeDict["number"] ?? "")
                blEndingType = attributeDict["type"]
            }
        case "segno", "coda":
            score.hasNav = true
        case "words", "rehearsal":
            break   // 文本在 endElement 用 buffer 判 nav
        case "sound":
            // 注意：tempo 以 <metronome><per-minute> 为准（与 build_79/music21 一致）；
            // 裸 <sound tempo> 只是回放提示，music21 不读，这里忽略。
            // 导航类 sound 属性一律视为 D.S./D.C./Coda/Fine（M2 拦截）。
            let navAttrs = ["coda","segno","dacapo","dalsegno","fine","tocoda"]
            if navAttrs.contains(where: { attributeDict[$0] != nil }) {
                score.hasNav = true
            }
        case "barline":
            barlineLoc = attributeDict["location"] ?? "right"
            blRepeatDir = nil; blRepeatTimes = nil
            blEndingSet = nil; blEndingType = nil
        default: break
        }
        // barline 内的 segno/coda 元素已在上面处理
        if inClef && e == "sign" { /* sign 文本在 end 处理 */ }
    }
    private var partCountSeen = 0

    // MARK: text

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    // MARK: end

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let e = elementName
        switch e {
        // metadata
        case "work-title":
            inWorkTitle = false; if score.title.isEmpty { score.title = text }
        case "movement-title":
            inMovementTitle = false; if score.title.isEmpty { score.title = text }
        case "creator":
            if inComposerCreator && score.composer.isEmpty { score.composer = text }
            inComposerCreator = false
        // attributes
        case "divisions":
            if let v = Double(text) { curDivisions = v }
        case "fifths":
            curFifths = Int(text) ?? 0
        case "mode":
            curMode = text
        case "beats":
            if inTime { beatsParts.append(text) }
        case "beat-type":
            if inTime { beatTypeParts.append(text) }
        case "key":
            inKey = false
            if !gotKey {
                score.keyName = MusicXMLKeyMap.keyName(fifths: curFifths, mode: curMode)
                gotKey = true
            }
        case "time":
            inTime = false
            let beatsExpr = beatsParts.joined(separator: "+")
            let btExpr = beatTypeParts.joined(separator: "+")
            tsSet.insert("\(beatsExpr)/\(btExpr)")
            if score.timeSignature == "4/4" && tsSet.count == 1 {
                if let b = beatsExpr.split(separator: "+").first, let bi = Int(b),
                   let t = btExpr.split(separator: "+").first, let ti = Int(t) {
                    firstBeats = bi; firstBeatType = ti
                }
            }
        case "clef":
            inClef = false
            if clefPercussion || clefSign.lowercased() == "percussion" { score.hasDrum = true }
        case "sign":
            if inClef { clefSign = text }
        // note leaves
        case "pitch": curNote?.inPitch = false
        case "step":
            if curNote?.inPitch == true { curNote?.step = text }
        case "root-step": rootStep = text
        case "bass-step": bassStep = text
        case "alter":
            let v = Int(text) ?? 0
            if curNote?.inPitch == true { curNote?.alter = v; curNote?.hasAlter = true }
        case "root-alter": rootAlter = Int(text) ?? 0
        case "bass-alter": bassAlter = Int(text) ?? 0
        case "octave":
            curNote?.octave = Int(text) ?? 0
        case "duration":
            if curNote != nil { curNote?.duration = Int(text) }
            else if inBackup || inForward { bfDuration = Int(text) }
        case "actual-notes": curNote?.actualNotes = Int(text)
        case "normal-notes": curNote?.normalNotes = Int(text)
        case "type":
            if curNote != nil { curNote?.hasType = true }
        case "time-modification": curNote?.inTM = false
        case "notations": curNote?.inNotations = false
        case "backup":
            inBackup = false
            if let d = bfDuration { cursor -= Double(d) }
        case "forward":
            inForward = false
            if let d = bfDuration {
                cursor += Double(d); contentEnd = max(contentEnd, cursor / (curDivisions ?? 1))
            }
        // harmony leaves
        case "kind": curHarmony?.kind = text
        case "offset":
            if curHarmony != nil { harmonyOffset = Int(text) ?? 0 }
        case "per-minute":
            if inMetronome, let v = Double(text), score.tempo == 120 { score.tempo = Int(v.rounded()) }
        case "metronome": inMetronome = false
        case "root": inRoot = false
        case "bass": inBass = false
        case "degree-value": dValue = Int(text) ?? 0
        case "degree-alter": dAlter = Int(text) ?? 0
        case "degree-type":
            dType = MXDegree.Kind(text)
        case "degree":
            inDegree = false
            if let k = dType { curHarmony?.degrees.append(MXDegree(kind: k, alter: dAlter, value: dValue)) }
        case "harmony":
            if activePart, let m = curMeasure, var h = curHarmony {
                h.rootStep = rootStep; h.rootAlter = rootAlter
                h.bassStep = bassStep; h.bassAlter = bassAlter
                if let chord = MusicXMLChordMapper.display(h) {
                    let off = (cursor + Double(harmonyOffset)) / (curDivisions ?? 1)
                    m.harmonies.append(MXHarm(offQl: off, chord: chord))
                    score.hasAnyHarmony = true
                }
            }
            curHarmony = nil
        // words / rehearsal 导航检测
        case "words", "rehearsal":
            if Self.matchesNav(text) { score.hasNav = true }
        case "note":
            endNote()
            curNote = nil
        case "barline":
            if let m = curMeasure {
                if let dir = blRepeatDir {
                    if barlineLoc == "left" {
                        m.leftRepeat = dir; m.leftRepeatTimes = blRepeatTimes
                    } else if barlineLoc == "right" {
                        m.rightRepeat = dir; m.rightRepeatTimes = blRepeatTimes
                    } else {
                        m.nonStandardBarline = true
                    }
                }
                if let set = blEndingSet {
                    let type = blEndingType ?? ""
                    if type == "start" && barlineLoc == "left" {
                        m.endStarts.append(set)
                    } else if (type == "stop" || type == "discontinue") && barlineLoc == "right" {
                        m.endStops.append(set)
                    } else {
                        m.nonStandardBarline = true
                    }
                }
            }
            blRepeatDir = nil; blRepeatTimes = nil
            blEndingSet = nil; blEndingType = nil
        case "measure":
            if activePart, let m = curMeasure {
                m.contentEndQl = contentEnd
                score.measures.append(m)
            }
            curMeasure = nil
        case "part":
            activePart = false
        default: break
        }
        buffer = ""
    }

    private static func matchesNav(_ s: String) -> Bool {
        let range = NSRange(location: 0, length: s.utf16.count)
        return navRegex.firstMatch(in: s, range: range) != nil
    }

    /// 解析 ending number：与 music21 RepeatBracket 一致——
    /// "a-b" 闭区间；"a,b" 枚举；单数字；空/非法归为 [0]（编号 0 非法，后续拦截）。
    static func parseEndingNumbers(_ raw: String) -> [Int] {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return [0] }
        if s.contains("-") {
            let parts = s.split(separator: "-", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]), a <= b {
                return Array(a...b)
            }
            return [0]
        }
        if s.contains(",") {
            let vals = s.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            return vals.isEmpty ? [0] : vals
        }
        return Int(s).map { [$0] } ?? [0]
    }

    private func endNote() {
        guard let n = curNote, let m = curMeasure else { return }
        if n.isGrace { return }                 // M1 丢弃 grace，不占时
        guard let durDiv = n.duration, let div = curDivisions, div > 0 else { return }
        let ql = Double(durDiv) / div
        let off = cursor / div
        let tie: String? = {
            if n.tieStart && n.tieStop { return "continue" }
            if n.tieStart { return "start" }
            if n.tieStop { return "stop" }
            return nil
        }()
        // music21 仅在 time-modification 与音符 <type> 同时存在时挂 tuplet；
        // 缺 <type> 的 TM 不产生三连音（实测 Theme 末尾 32 分休止）。
        let tuplet = (n.actualNotes == 3 && n.normalNotes == 2 && n.hasType)

        if n.isChord, let last = m.sounds.last {
            if !n.isRest {
                let midi = pitchToMidi(step: n.step, alter: n.hasAlter ? n.alter : 0, octave: n.octave)
                last.components.append((midi, tie))
            }
            return                               // <chord/> 不推进游标
        }

        if n.isRest {
            let ev = MXSoundEvent(offQl: off, ql: ql, isRest: true, tuplet: tuplet,
                                  rawTie: nil, components: [])
            m.sounds.append(ev)
        } else {
            let midi = pitchToMidi(step: n.step, alter: n.hasAlter ? n.alter : 0, octave: n.octave)
            let ev = MXSoundEvent(offQl: off, ql: ql, isRest: false, tuplet: tuplet,
                                  rawTie: tie, components: [(midi, tie)])
            m.sounds.append(ev)
        }
        cursor += Double(durDiv)
        contentEnd = max(contentEnd, off + ql)
    }

    private func pitchToMidi(step: String, alter: Int, octave: Int) -> Int {
        let base: [String: Int] = ["C":0,"D":2,"E":4,"F":5,"G":7,"A":9,"B":11]
        return (octave + 1) * 12 + (base[step] ?? 0) + alter
    }
}
