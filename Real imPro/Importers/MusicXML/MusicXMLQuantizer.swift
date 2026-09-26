import Foundation

// MARK: - 输出 note（可变，供连音修复改写）

final class QuantNote {
    var pitch: String
    var isRest: Bool
    var duration: String
    var isTriplet: Bool
    var isTieStart: Bool
    var isTieEnd: Bool
    init(pitch: String, isRest: Bool, duration: String, isTriplet: Bool,
         isTieStart: Bool, isTieEnd: Bool) {
        self.pitch = pitch; self.isRest = isRest; self.duration = duration
        self.isTriplet = isTriplet; self.isTieStart = isTieStart; self.isTieEnd = isTieEnd
    }
    func json() -> [String: Any] {
        return ["pitch": pitch, "isRest": isRest, "duration": duration,
                "isTriplet": isTriplet, "isTieStart": isTieStart, "isTieEnd": isTieEnd]
    }
}

final class OutMeasure {
    var notes: [QuantNote] = []
    var chordSlots: [(chord: String, startSlot: Int)] = []
    var g: Double
    init(g: Double) { self.g = g }
}

// MARK: - 内部工作事件

private final class E {
    var off: Double
    var ql: Double
    let isRest: Bool
    let tuplet: Bool
    var tie: String?
    let midi: Int
    var actual: Double = 0
    var drop: Bool = false
    var absorbEnd: Double?
    init(off: Double, ql: Double, isRest: Bool, tuplet: Bool, tie: String?, midi: Int) {
        self.off = off; self.ql = ql; self.isRest = isRest
        self.tuplet = tuplet; self.tie = tie; self.midi = midi
    }
}

private struct ChunkEv {
    var off: Double, ql: Double, actual: Double
    var midi: Int?, isRest: Bool, tuplet: Bool
    var ts: Bool, te: Bool, rbwd: Bool
}

enum MusicXMLQuantizer {

    static let SHARP_NAMES = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
    static let NOTE_SLOT: [Int: String] = [480:"w",360:"hd",240:"h",180:"qd",120:"q",90:"8d",
                                           60:"8",45:"16d",30:"16",15:"32",
                                           160:"h_t3",80:"q_t3",40:"8_t3",20:"16_t3"]
    static let SLOT: [String: Int] = ["w":480,"h":240,"q":120,"8":60,"16":30,"32":15]
    static let PIECE_STD = [480,360,240,180,120,90,60,45,30,15]
    static let PIECE_STD_T3 = [160,80,40,20]
    static let REST_STD = [480,360,240,180,120,90,60,45,30,15]
    static let REST_NAME: [Int: String] = [480:"wr",360:"hdr",240:"hr",180:"qdr",120:"qr",
                                           90:"8dr",60:"8r",45:"16dr",30:"16r",15:"32r"]
    static let REST_STD_T3 = [160,80,40,20]
    static let REST_NAME_T3: [Int: String] = [160:"hr_t3",80:"qr_t3",40:"8r_t3",20:"16r_t3"]

    static func pyRound(_ x: Double) -> Int { Int(x.rounded()) }

    static func pitchFromMidi(_ m: Int) -> String {
        "\(SHARP_NAMES[m % 12])/\(m / 12 - 1)"
    }

    static func durToSlots(_ durIn: String, isTriplet forceT: Bool = false) -> Int {
        var dur = durIn
        var triplet = forceT
        if dur.hasSuffix("_t3") { triplet = true; dur = String(dur.dropLast(3)) }
        if dur.hasSuffix("r") { dur = String(dur.dropLast()) }
        var dotted = false
        if dur.hasSuffix("d") { dotted = true; dur = String(dur.dropLast()) }
        var v = SLOT[dur] ?? 120
        if dotted { v = Int(Double(v) * 1.5) }
        if triplet { v = Int((Double(v) * 2.0 / 3.0).rounded()) }
        return v
    }

    static func splitSlots(_ want: Int, tuplet: Bool) -> [Int] {
        let std = tuplet ? PIECE_STD_T3 : PIECE_STD
        var pieces: [Int] = []
        var rem = want
        while rem > 0 {
            if let hit = std.first(where: { $0 <= rem }) { pieces.append(hit); rem -= hit }
            else { pieces.append(rem); break }
        }
        return pieces
    }

    static func decomposeRest(_ slotsIn: Int, tuplet: Bool = false) -> [QuantNote] {
        var slots = slotsIn
        let std = tuplet ? REST_STD_T3 : REST_STD
        let name = tuplet ? REST_NAME_T3 : REST_NAME
        var out: [Int] = []
        while slots > 0 {
            if let hit = std.first(where: { $0 <= slots }) { out.append(hit); slots -= hit }
            else { out.append(std.last!); slots -= std.last! }
        }
        return out.map { QuantNote(pitch: "b/4", isRest: true, duration: name[$0]!,
                                   isTriplet: tuplet, isTieStart: false, isTieEnd: false) }
    }

    static func soundNotes(midi: Int, want: Int, tuplet: Bool, inTie: Bool, outTie: Bool) -> [QuantNote] {
        let pitch = pitchFromMidi(midi)
        if let single = NOTE_SLOT[want], (!tuplet || single.hasSuffix("_t3")) {
            let ts = outTie, te = inTie && !outTie
            return [QuantNote(pitch: pitch, isRest: false, duration: single, isTriplet: tuplet,
                              isTieStart: ts, isTieEnd: te)]
        }
        let pieces = splitSlots(want, tuplet: tuplet)
        var out: [QuantNote] = []
        let P = pieces.count
        for (k, sl) in pieces.enumerated() {
            let dur = NOTE_SLOT[sl] ?? "q"
            let last = (k == P - 1)
            let ts = last ? outTie : true
            let te = last ? (inTie && !outTie) : false
            out.append(QuantNote(pitch: pitch, isRest: false, duration: dur, isTriplet: tuplet,
                                 isTieStart: ts, isTieEnd: te))
        }
        return out
    }

    // dyad 选旋律音（对齐 chord_melody_midi）
    static func chordMelodyMidi(_ comps: [(midi: Int, tie: String?)], ct: String?) -> Int {
        if let ct = ct {
            let fwd = (ct == "start" || ct == "continue")
            var cand: [Int] = []
            for c in comps {
                guard let t = c.tie else { continue }
                if t == ct || ((t == "start" || t == "continue") == fwd) { cand.append(c.midi) }
            }
            if !cand.isEmpty { return cand.max()! }
        }
        return comps.map { $0.midi }.max()!
    }

    // MARK: 单小节 extract（actual 钳制 + collapse）

    private static func extract(_ m: MXRawMeasure, barEnd: Double) -> [E] {
        var evs: [E] = []
        for s in m.sounds {
            if s.ql <= 0.01 { continue }
            if s.isRest {
                evs.append(E(off: s.offQl, ql: s.ql, isRest: true, tuplet: s.tuplet, tie: nil, midi: -1))
            } else {
                // music21 Chord.tie = 第一个带 tie 的组成音的 tie（忽略 None）。
                let ct = s.components.first(where: { $0.tie != nil })?.tie ?? nil
                let midi = s.components.count > 1
                    ? chordMelodyMidi(s.components, ct: ct)
                    : (s.components.first?.midi ?? -1)
                evs.append(E(off: s.offQl, ql: s.ql, isRest: false, tuplet: s.tuplet,
                             tie: ct, midi: midi))
            }
        }
        evs.sort { $0.off < $1.off }
        for (i, e) in evs.enumerated() {
            let nxt = (i + 1 < evs.count) ? evs[i + 1].off : barEnd
            e.actual = max(0.0, min(e.ql, nxt - e.off))
        }
        for (i, e) in evs.enumerated() {
            if e.actual < 0.094 && !e.tuplet {
                if e.isRest {
                    e.drop = true
                } else {
                    var prev: E?
                    for x in evs[..<i] where !x.drop { prev = x }
                    if let pv = prev, !pv.isRest, pv.midi == e.midi {
                        pv.ql = e.off + e.actual
                        pv.absorbEnd = e.off + e.actual
                        e.drop = true
                    }
                }
            }
        }
        let kept = evs.filter { !$0.drop }
        for (j, e) in kept.enumerated() {
            if let ae = e.absorbEnd {
                let nxtOn = (j + 1 < kept.count) ? kept[j + 1].off : barEnd
                let rawWant = pyRound(ae * 120) - pyRound(e.off * 120)
                let cap = pyRound(nxtOn * 120) - pyRound(e.off * 120)
                let snapped = min(Int((Double(rawWant) / 15.0).rounded(.up)) * 15, cap)
                e.actual = max(e.actual, Double(snapped) / 120.0)
            }
        }
        return evs.filter { !$0.drop }
    }

    // MARK: 分块（线性谱 nch 恒为 1；保留通用实现以处理超长小节）

    private static func splitChunks(_ evs: [E], _ harmonies: [MXHarm], barEnd: Double, g: Double)
        -> (chunks: [[ChunkEv]], chChords: [[(Double, String)]]) {
        let nch = max(1, Int((barEnd / g - 1e-6).rounded(.up)))
        var chunks = [[ChunkEv]](repeating: [], count: nch)
        var chChords = [[(Double, String)]](repeating: [], count: nch)
        for h in harmonies {
            let k = min(max(0, Int(h.offQl / g)), nch - 1)
            chChords[k].append((h.offQl - Double(k) * g, h.chord))
        }
        for e in evs {
            let s = e.off
            let en = s + e.actual
            let k0 = min(max(0, Int(s / g)), nch - 1)
            let k1 = min(max(0, Int((en - 1e-9) / g)), nch - 1)
            let fwd = (e.tie == "start" || e.tie == "continue")
            let bwd = (e.tie == "continue" || e.tie == "stop")
            for k in k0...k1 {
                let a = max(s, Double(k) * g)
                let b = min(en, Double(k + 1) * g)
                let length = b - a
                if length <= 0 { continue }
                let atL = abs(a - Double(k) * g) < 1e-6
                let atR = abs(b - Double(k + 1) * g) < 1e-6
                let bwdSeg = (k == k0) ? bwd : true
                let fwdSeg = (k == k1) ? fwd : true
                let ts = atR && fwdSeg
                let te = atL && bwdSeg
                chunks[k].append(ChunkEv(off: a - Double(k) * g, ql: length, actual: length,
                                         midi: e.isRest ? nil : e.midi, isRest: e.isRest,
                                         tuplet: e.tuplet, ts: ts, te: te, rbwd: bwd))
            }
        }
        return (chunks, chChords)
    }

    private static func coalesceTies(_ events: [ChunkEv]) -> [ChunkEv] {
        var out: [ChunkEv] = []
        for var e in events.sorted(by: { $0.off < $1.off }) {
            if !e.isRest, let last = out.last, !last.isRest, last.midi == e.midi {
                var prev = out[out.count - 1]
                let adj = abs((prev.off + prev.actual) - e.off) < 1e-6
                if adj && e.rbwd {
                    prev.actual = e.off + e.actual - prev.off
                    prev.ts = e.ts
                    prev.tuplet = prev.tuplet || e.tuplet
                    out[out.count - 1] = prev
                    continue
                }
            }
            // te 作为 in_tie、ts 作为 out_tie，直接随事件进入 emit
            out.append(e)
        }
        return out
    }

    private static func emit(_ eventsIn: [ChunkEv], _ chords: [(Double, String)],
                             g: Double, frontPad: Int) -> (notes: [QuantNote], slots: [(String, Int)], mism: [String]) {
        let spm = Int(g * 120)
        var notes: [QuantNote] = []
        var cursor = frontPad
        var mism: [String] = []
        if frontPad > 0 { notes += decomposeRest(frontPad) }
        for e in coalesceTies(eventsIn) {
            let s = frontPad + pyRound(e.off * 120)
            if s > cursor { notes += decomposeRest(s - cursor) }
            cursor = s
            let end = frontPad + pyRound((e.off + e.actual) * 120)
            let want = end - s
            if !e.isRest, let midi = e.midi {
                let nn = soundNotes(midi: midi, want: want, tuplet: e.tuplet,
                                    inTie: e.te, outTie: e.ts)
                let got = nn.reduce(0) { $0 + durToSlots($1.duration, isTriplet: $1.isTriplet) }
                if got != want { mism.append("midi=\(midi) want=\(want) got=\(got)") }
                notes += nn; cursor += got
            } else {
                if want > 0 { notes += decomposeRest(want, tuplet: e.tuplet) }
                cursor += want
            }
        }
        let tail = spm - cursor
        if tail > 0 { notes += decomposeRest(tail) }
        else if tail < 0 { mism.append("OVERFILL \(-tail) spm=\(spm)") }
        var slots: [(String, Int)] = []
        for (off, c) in chords.sorted(by: { $0.0 < $1.0 }) {
            slots.append((c, frontPad + pyRound(off * 120)))
        }
        return (notes, slots, mism)
    }

    // MARK: 连音修复

    @discardableResult
    static func repairOrphanTies(_ out: [OutMeasure]) -> (repaired: Int, unresolved: [String]) {
        func firstLast(_ mm: OutMeasure) -> (QuantNote?, QuantNote?) {
            let ss = mm.notes.filter { !$0.isRest }
            return (ss.first, ss.last)
        }
        var repaired = 0
        var unresolved: [String] = []
        var held = false
        var hp: String?
        for (mi, mm) in out.enumerated() {
            for n in mm.notes {
                if n.isRest { continue }
                if n.isTieEnd {
                    if !held {
                        let (fs, _) = firstLast(mm)
                        if fs === n && mi > 0 {
                            let (_, pls) = firstLast(out[mi - 1])
                            if let pls = pls, pls.pitch == n.pitch {
                                pls.isTieStart = true; repaired += 1; held = true; hp = n.pitch
                            } else { unresolved.append("m\(mi+1) \(n.pitch)") }
                        } else { unresolved.append("m\(mi+1) \(n.pitch)") }
                    }
                    if held && hp == n.pitch { held = false; hp = nil }
                } else if n.isTieStart { held = true; hp = n.pitch }
                else { held = false; hp = nil }
            }
        }
        return (repaired, unresolved)
    }

    private static func pitchMidi(_ p: String) -> Int {
        let parts = p.split(separator: "/")
        let n = String(parts[0]); let o = Int(parts[1]) ?? 0
        let base: [Character: Int] = ["C":0,"D":2,"E":4,"F":5,"G":7,"A":9,"B":11]
        let b = base[n.first!]!
        let acc = n.dropFirst()
        return 12 * (o + 1) + b + acc.filter { $0 == "#" }.count - acc.filter { $0 == "b" }.count
    }

    /// 仅 policy (a)：同音补 tieEnd；异音/休止/曲末悬空一律撤 tieStart，不改音高。
    @discardableResult
    static func repairDanglingTies(_ out: [OutMeasure]) -> [String] {
        var fixed: [String] = []
        var held: QuantNote?
        var heldMi = -1, heldNi = -1
        for (mi, mm) in out.enumerated() {
            for (ni, n) in mm.notes.enumerated() {
                if n.isRest {
                    if let h = held {
                        h.isTieStart = false
                        fixed.append("m\(heldMi+1)n\(heldNi) \(h.pitch): tieStart 被休止切断，撤销(a)")
                        held = nil
                    }
                    continue
                }
                if n.isTieEnd, let h = held, pitchMidi(h.pitch) != pitchMidi(n.pitch) {
                    h.isTieStart = false
                    fixed.append("m\(heldMi+1)n\(heldNi) \(h.pitch): 终点为异音，撤销 tieStart(a)")
                    held = nil
                }
                if n.isTieEnd {
                    if let h = held, pitchMidi(h.pitch) == pitchMidi(n.pitch) { held = nil }
                    if n.isTieStart { held = n; heldMi = mi; heldNi = ni }
                    continue
                }
                if let h = held {
                    if pitchMidi(h.pitch) == pitchMidi(n.pitch) {
                        n.isTieEnd = true
                        fixed.append("m\(mi+1)n\(ni) \(n.pitch): 补 isTieEnd（同音高延音尾）")
                        if n.isTieStart { held = n; heldMi = mi; heldNi = ni } else { held = nil }
                    } else {
                        h.isTieStart = false
                        fixed.append("m\(heldMi+1)n\(heldNi) \(h.pitch): 后续异音 m\(mi+1)n\(ni) \(n.pitch)，撤销 tieStart(a)，不改音高")
                        held = nil
                        if n.isTieStart { held = n; heldMi = mi; heldNi = ni }
                    }
                } else if n.isTieStart {
                    held = n; heldMi = mi; heldNi = ni
                }
            }
        }
        if let h = held {
            h.isTieStart = false
            fixed.append("m\(heldMi+1)n\(heldNi) \(h.pitch): 曲末悬空，撤销 tieStart(a)")
        }
        return fixed
    }

    // MARK: finalize（和弦 carry-forward、守恒、noteIndex）

    static func finalize(_ out: [OutMeasure]) -> (measures: [[String: Any]], bad: [String]) {
        var measures: [[String: Any]] = []
        var last = ""
        var bad: [String] = []
        for (i, m) in out.enumerated() {
            let spm = Int(m.g * 120)
            var notes = m.notes
            var slots = m.chordSlots
            if !slots.isEmpty { last = slots.last!.chord }
            else if !last.isEmpty { slots = [(last, 0)] }
            if notes.isEmpty { notes = decomposeRest(spm) }
            var tot = notes.reduce(0) { $0 + durToSlots($1.duration, isTriplet: $1.isTriplet) }
            if tot < spm - 10 { notes += decomposeRest(spm - tot); tot = spm }
            else if tot > spm + 10 { bad.append("m\(i) tot=\(tot) spm=\(spm)") }
            var cum: [Int] = []
            var pos = 0
            for n in notes { cum.append(pos); pos += durToSlots(n.duration, isTriplet: n.isTriplet) }
            var ann: [[String: Any]] = []
            for cs in slots {
                var idx = notes.count - 1
                for (j, st) in cum.enumerated() where st <= cs.startSlot + 1 { idx = j }
                ann.append(["chord": cs.chord, "noteIndex": idx])
            }
            let slotJSON: [[String: Any]] = slots.map { ["chord": $0.chord, "startSlot": $0.1] }
            measures.append([
                "chord": slots.first?.chord ?? "",
                "notes": notes.map { $0.json() },
                "chordAnnotations": ann,
                "chordSlots": slotJSON,
                "sectionName": NSNull(),
                "slotsPerMeasure": spm,
            ])
        }
        return (measures, bad)
    }

    // MARK: 整曲编排（解析后的 MXScore → OutMeasure[]）

    static func buildMeasures(_ score: MXScore) -> (out: [OutMeasure], diag: [String: Any]) {
        let g = score.gQl
        var out: [OutMeasure] = []
        var mism: [String] = []
        for (mi, m) in score.measures.enumerated() {
            // music21 的 barDuration 即使内容溢出（如 4.333/4）仍报声明值 g，
            // extract 会把超出部分钳掉；线性 4/4、3/4 子集 barEnd 恒为 g。
            let barEnd = g
            let evs = extract(m, barEnd: barEnd)
            let (chunks, chChords) = splitChunks(evs, m.harmonies, barEnd: barEnd, g: g)
            for (ci, cevs) in chunks.enumerated() {
                let fp = (mi == 0 && ci == 0 && m.contentEndQl < g - 1e-6)
                    ? pyRound((g - m.contentEndQl) * 120) : 0
                let (notes, slots, mm) = emit(cevs, chChords[ci], g: g, frontPad: fp)
                let om = OutMeasure(g: g)
                om.notes = notes; om.chordSlots = slots
                out.append(om)
                mism += mm.map { "m\(mi+1) \($0)" }
            }
        }
        let (repaired, unresolved) = repairOrphanTies(out)
        if !unresolved.isEmpty { mism += unresolved.map { "ORPHAN \($0)" } }
        let tieFix = repairDanglingTies(out)
        return (out, ["noteDurMismatch": mism, "orphanRepaired": repaired,
                      "tieFixed": tieFix.count])
    }
}
