// =====================================================================
// JavaAlignedTransformEngine.swift
// ② Guide Tone & Transform（T2）Java 对齐通用变换内核（生产版）。
//
// 严格镜像 Java：
//   Transform.applySubstitutionsToMelodyPart（两阶段 motif→embellishment，空阶段跳过 F16）
//   Transform.applySubstitutionType（外层 weight 重复装袋→洗牌→保序去重→首个成功）
//   Substitution.apply（内层同法；学习规则 rel-pitch 适用判定 F14）
//   Transformation.apply（绑定源变量→changesFirstNote 回退一音→guard 须 true→
//                         target map/flatten→enforceDuration 时长守恒）
//   Part.pasteOver / setUnit / delUnit 的 slot 数组铺砌语义（F22 SlotGrid）
//
// 随机口径（两层一致、内外共用同一条随机流）：
//   weight 重复装袋 →（生产）真洗牌 /（对拍）保序 → 按【行身份 id】保序去重保留首次出现，
//   等价 Java get(0)+removeAll(singleton)（F15）。两档随机源见 TransformRNG.swift。
//
// 通用性：内核只吃/吐 [NoteChordPair]，grammar lick 与 guide PhysicalNote 两种输入都先
//   由各自薄桥转成 NCP，再走同一内核。仅在 useJavaAlignedTransform 打开时可达。
//
// [T2] 总开关默认【开】（R6续2 49/49 随机双端 diff=0 + 真人 GUI 跳进分布重合后翻 true）；
//   回退：把 useJavaAlignedTransform 改回 false 即恢复旧 19 模板链（见文件末封存段）。
// =====================================================================

import Foundation

extension TransformEngine {

    // MARK: T2 总开关
    /// true = 走 Java 对齐通用内核 + 26 乐手离线静态表（两层真洗牌/可对拍保序）。
    /// false = 旧 19 组手写模板链（Transform.swift 旧三阶段 + 单层 randomElement，已封存保留可回退）。
    static var useJavaAlignedTransform = true
    /// 新内核当前乐手（对应 Bundle 内 TransformTables/<id>.tsv），默认 My；由调音台 UI 选择。
    static var javaAlignedMusician = TransformMusicianRegistry.defaultMusician
    /// [T2] 生产档最近一次使用的随机种子（SystemTransformRNG 自动记录，便于复现/排障）
    static private(set) var lastProductionSeed: Int64 = 0

    /// 内核工作音符（仅保留变换所需：音高/时值/是否休止）
    fileprivate struct KWNote { var pitch: Int; var dur: Int; var rest: Bool }

    final class JavaAlignedTransformEngine {

        private let allSubs: [GSub]
        /// 和弦时间线（按起始 slot 升序，供替换后新音按 slot 找和弦）
        private let chordStarts: [(start: Int, chord: ChordBlock)]
        /// 审计 trace 开关（生产默认关；对拍时可开，打印两层候选/选择轨迹）
        var trace: Bool
        /// 非 nil 时两层走真洗牌（内外共用同一条流）；nil 时保序首取（对拍/单测）
        private var rng: TransformRNG?

        /// 以规则表 + 输入 NCP 序列构造（和弦时间线默认从输入序列本身导出）。
        /// - M2/F26：`explicitChordStarts` 非 nil（且非空）时，用调用方按和弦时值累加得到的【精确边界】，
        ///   对齐 Java 独立 ChordPart.getCurrentChord(slot)——旋律在换和弦处恰好无音头时，
        ///   旧的"只在输入 NCP 音头记边界"会把新和弦错挂到下一个音头。guide/grammar 不传此参（nil），
        ///   逐字走旧推断；仅内置旋律加花适配层（MelodyTransformAdapter）传入。
        init(table: [GSub], input: [NoteChordPair], mode: TransformRandomMode = .randomized(SystemTransformRNG()), trace: Bool = false,
             explicitChordStarts: [(start: Int, chord: ChordBlock)]? = nil) {
            self.allSubs = table
            self.trace = trace
            switch mode {
            case .deterministic:
                self.rng = nil
            case .randomized(let r):
                self.rng = r
                if let sys = r as? SystemTransformRNG { TransformEngine.lastProductionSeed = sys.seed }
            }
            if let ex = explicitChordStarts, !ex.isEmpty {
                self.chordStarts = ex   // M2/F26：用独立和弦时间线的精确边界，不从音头反推
            } else {
                var starts: [(start: Int, chord: ChordBlock)] = []
                for ncp in input {
                    if let last = starts.last, last.chord.name == ncp.chord.name { continue }
                    starts.append((start: ncp.slot, chord: ncp.chord))
                }
                // 防御：空序列兜底
                if starts.isEmpty, let first = input.first { starts = [(0, first.chord)] }
                self.chordStarts = starts
            }
        }

        // MARK: 对外主入口

        /// 对一条 NCP 旋律施加两阶段替换，返回替换后的 NCP（时值守恒由内部 enforceDuration 保证）
        /// - M2/F26：`chordTimeline` 透传给 init 的 explicitChordStarts，默认 nil（guide/grammar 旧路径不变）。
        static func apply(to input: [NoteChordPair],
                          table: [GSub],
                          mode: TransformRandomMode = .randomized(SystemTransformRNG()),
                          trace: Bool = false,
                          chordTimeline: [(start: Int, chord: ChordBlock)]? = nil) -> [NoteChordPair] {
            let engine = JavaAlignedTransformEngine(table: table, input: input, mode: mode, trace: trace,
                                                     explicitChordStarts: chordTimeline)
            let work = input.map { KWNote(pitch: $0.note.isRest ? -1 : $0.note.midiPitch,
                                          dur: $0.note.durationSlots, rest: $0.note.isRest) }
            let out = engine.run(work)
            // 回到 NCP：累计 slot，按 slot 找和弦
            var result: [NoteChordPair] = []
            var slot = input.first?.slot ?? 0
            for w in out {
                let chord = engine.chordAt(slot)
                let note = PhysicalNote(midiPitch: w.rest ? -1 : w.pitch, durationSlots: w.dur)
                result.append(NoteChordPair(note: note, chord: chord, slot: slot))
                slot += w.dur
            }
            return result
        }

        // MARK: 和弦时间线

        /// 【D4】按 slot 二分定位当前和弦：chordStarts 按 start 升序，找 start <= slot 的最后一个；
        /// slot 早于首个边界时回退首个和弦（与旧全扫结果逐字一致），复杂度 O(log 和弦数)。
        private func chordAt(_ slot: Int) -> ChordBlock {
            guard !chordStarts.isEmpty else {
                return ChordBlock(name: "NC", duration: 0)
            }
            var lo = 0
            var hi = chordStarts.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if chordStarts[mid].start <= slot { lo = mid } else { hi = mid - 1 }
            }
            return chordStarts[lo].chord
        }

        // MARK: weight 装袋 →（真洗牌 / 保序）→ 按 id 去重保留首次出现（等价 Java get(0)+removeAll）

        private func orderedUniqueSubs(_ subs: [GSub]) -> [GSub] {
            var bag: [GSub] = []
            for s in subs { for _ in 0..<max(1, s.weight) { bag.append(s) } }
            if var r = rng { r.shuffle(&bag); rng = r }   // 外层真洗牌（推进共享随机流）
            var out: [GSub] = []
            var seen = Set<Int>()
            for s in bag where !seen.contains(s.id) { seen.insert(s.id); out.append(s) }
            return out
        }
        private func orderedUniqueTrans(_ ts: [GTrans]) -> [GTrans] {
            var bag: [GTrans] = []
            for t in ts { for _ in 0..<max(1, t.weight) { bag.append(t) } }
            if bag.isEmpty { return [] }   // 对齐 Java full.size()<1 return null（不洗牌、不抽牌）
            if var r = rng { r.shuffle(&bag); rng = r }   // 内层真洗牌（每个尝试的 sub 都推进）
            var out: [GTrans] = []
            var seen = Set<Int>()
            for t in bag where !seen.contains(t.id) { seen.insert(t.id); out.append(t) }
            return out
        }

        // MARK: F14 学习规则适用判定

        /// 内层 Substitution.applicable：desc 含 rel-pitch- 且含 -to- 时，
        /// 要求【下一音】相对级 == "-to-" 之后的串（末音无下一音=false）；否则恒 true。
        private func transApplicable(_ t: GTrans, grid: SlotGrid, curSlot: Int) -> Bool {
            let d = t.desc
            if d.contains("rel-pitch-"), let r = d.range(of: "-to-") {
                let second = String(d[r.upperBound...])
                let ch = grid.headAtOrBefore(curSlot)
                let nh = grid.nextHead(ch)
                guard nh < grid.total else { return false }
                return relPitchOf(grid.cells[nh]!, nh) == second
            }
            return true
        }
        /// 外层 Transform.applicable：sub 名含 first-rel-pitch- 为学习规则：
        /// 当前音相对级须 == 前缀后串，且时值精确匹配 whole/half/quarter/eighth。
        private func subApplicable(_ s: GSub, grid: SlotGrid, curSlot: Int) -> Bool {
            let n = s.name
            guard let r = n.range(of: "first-rel-pitch-") else { return true }
            let want = String(n[r.upperBound...])
            let ch = grid.headAtOrBefore(curSlot)
            let wn = grid.cells[ch]!
            guard relPitchOf(wn, ch) == want else { return false }
            return exactMatch(n, wn.dur)
        }
        private func exactMatch(_ n: String, _ dur: Int) -> Bool {
            if n.contains("whole-")   && dur == 480 { return true }
            if n.contains("half-")    && dur == 240 { return true }
            if n.contains("quarter-") && dur == 120 { return true }
            if n.contains("eighth-") && dur == 60  { return true }
            return false
        }
        /// 复用已 F3/F7/F9 修正的 relative-pitch 算子求某音相对级（休止 "rest"、NC "none"）
        private func relPitchOf(_ wn: KWNote, _ slot: Int) -> String {
            var fr = Evaluate.TransformFrame()
            let ncp = NoteChordPair(note: PhysicalNote(midiPitch: wn.rest ? -1 : wn.pitch, durationSlots: wn.dur),
                                    chord: chordAt(slot), slot: slot)
            fr.setVar(name: "x", value: ncp)
            return (Evaluate.shared.evaluateAny("(relative-pitch x)", frame: &fr) as? String) ?? ""
        }

        // MARK: [T2 F22] slot 网格：精确复刻 Java Part 的 slot 数组语义
        //  - 音只占一个音头 slot，其余 slot 为 nil；音持续到下一音头（head-gap）。
        //  - pasteOver 逐 slot 覆盖：区间内音头被抹掉（区间内原音整音消失），与 Part.pasteOver 一致。
        //  - 绑定 guard 用音头【存储时值】(cells[h].dur)；最终输出按音头间隙重算时值（同金标准 OUT 遍历）。
        fileprivate final class SlotGrid {
            var cells: [KWNote?]
            let total: Int
            init(notes: [KWNote]) {
                total = notes.reduce(0) { $0 + $1.dur }
                cells = Array(repeating: nil, count: max(total, 1))
                var s = 0
                for n in notes { cells[s] = n; s += n.dur }
            }
            /// 最近的 <= slot 的非空音头（getCurrentNoteIndex）
            func headAtOrBefore(_ slot: Int) -> Int {
                var s = min(max(slot, 0), total - 1)
                while s >= 0 && cells[s] == nil { s -= 1 }
                return s
            }
            /// > slot 的第一个非空音头（getNextIndex）
            func nextHead(_ slot: Int) -> Int {
                var s = slot + 1
                while s < total && cells[s] == nil { s += 1 }
                return s
            }
            /// < slot 的最近非空音头（getPrevIndex：从 slot-1 向前扫）
            func prevHead(_ slot: Int) -> Int {
                var s = slot - 1
                while s >= 0 && cells[s] == nil { s -= 1 }
                return s
            }
            /// Part.pasteOver：先清空 [at,at+W)，再把 result 音头放到各自本地偏移；
            /// 最后按 Part 铺砌不变量重算每个音头存储时值=到下一音头间隙（setUnit 截前音/吞被抹音）
            func pasteOver(_ result: [KWNote], at pasteSlot: Int) {
                let w = result.reduce(0) { $0 + $1.dur }
                for off in 0..<w where pasteSlot + off < total { cells[pasteSlot + off] = nil }
                var lo = 0
                for n in result { cells[pasteSlot + lo] = n; lo += n.dur }
                retile()
            }
            /// 重算所有音头存储时值 = 下一音头 − 本音头（末音到 total）
            func retile() {
                var h = 0
                while h < total {
                    if cells[h] != nil { let d = nextHead(h) - h; var nn = cells[h]!; nn.dur = d; cells[h] = nn }
                    h += 1
                }
            }
            /// 输出：遍历音头，时值=到下一音头的间隙
            func compress() -> [KWNote] {
                var out: [KWNote] = []
                var h = 0
                while h < total {
                    if let n = cells[h] {
                        var nn = n; nn.dur = nextHead(h) - h; out.append(nn)
                    }
                    h += 1
                }
                return out
            }
        }

        // MARK: 单条 transformation

        private func tryTrans(_ t: GTrans, grid: SlotGrid, curSlot: Int) -> Int? {
            let changeFirst = t.changesFirstNote()
            // F22：windowStart 用 getPrevIndex 语义（游标在音内回本音头，恰在音头才回上一音）
            var windowStart = curSlot
            if !changeFirst {
                let p = grid.prevHead(curSlot)
                if p > -1 { windowStart = p }
            }
            let k = t.src.count
            // 从 windowStart 起取 k 个音头（首头=getCurrentNote=windowStart 处/之前最近音头，绑定用存储时值）
            var heads: [Int] = []
            var hh = grid.headAtOrBefore(windowStart)
            guard hh >= 0 else { return nil }
            for _ in 0..<k {
                guard hh < grid.total else { return nil }
                heads.append(hh); hh = grid.nextHead(hh)
            }
            var frame = Evaluate.TransformFrame()
            for (j, v) in t.src.enumerated() {
                let slot = heads[j]
                let wn = grid.cells[slot]!
                let ncp = NoteChordPair(note: PhysicalNote(midiPitch: wn.rest ? -1 : wn.pitch, durationSlots: wn.dur),
                                        chord: chordAt(slot), slot: slot)
                frame.setVar(name: v, value: ncp)
            }
            // guard 必须为布尔 true
            let gv = Evaluate.shared.evaluateAny(t.guardExpr, frame: &frame)
            guard let g = gv as? Bool, g else { return nil }
            // targets 逐个求值并摊平
            var result: [KWNote] = []
            for tg in t.targets {
                guard let rv = Evaluate.shared.evaluateAny(tg, frame: &frame) else { continue }
                for ncp in flattenNCP(rv) {
                    result.append(KWNote(pitch: ncp.note.isRest ? -1 : ncp.note.midiPitch,
                                        dur: ncp.note.durationSlots, rest: ncp.note.isRest))
                }
            }
            if result.isEmpty { return nil }
            // enforceDuration=true：替换前=绑定音头【存储时值】之和（Java totalDurBefore 用 varNote.getRhythmValue）
            let before = heads.reduce(0) { $0 + grid.cells[$1]!.dur }
            let after = result.reduce(0) { $0 + $1.dur }
            if before != after { return nil }
            // F22：slot 级 pasteOver（区间内音头抹除、边界外保留）
            grid.pasteOver(result, at: windowStart)
            // Java next = 原游标 slot + 窗时长 W(=before=after)，可能落在音内
            return curSlot + before
        }

        private func flattenNCP(_ v: Any) -> [NoteChordPair] {
            // F17 对齐 Java Transformation.apply：减时值产生的零长音（duration<=0）不发声、不进入结果。
            func alive(_ n: NoteChordPair) -> Bool { n.note.durationSlots > 0 }
            if let n = v as? NoteChordPair { return alive(n) ? [n] : [] }
            if let arr = v as? [NoteChordPair] { return arr.filter(alive) }
            if let arr = v as? [Any?] { return arr.flatMap { $0.flatMap { flattenNCP($0) } ?? [] } }
            if let arr = v as? [Any] { return arr.flatMap { flattenNCP($0) }.filter(alive) }
            return []
        }

        // MARK: 单个 sub（内层首个成功）

        private func applySub(_ s: GSub, grid: SlotGrid, curSlot: Int) -> (nextSlot: Int, picked: String)? {
            let cand = orderedUniqueTrans(s.trans.filter { $0.enabled && transApplicable($0, grid: grid, curSlot: curSlot) })
            if cand.isEmpty { return nil }
            if trace {
                let cj = cand.map { $0.desc }.joined(separator: "\t")
                print("INNERCAND\t\(curSlot)" + (cj.isEmpty ? "" : "\t" + cj))
            }
            for t in cand {
                if let ns = tryTrans(t, grid: grid, curSlot: curSlot) {
                    if trace { print("INNERPICK\t\(ns)\t\(t.desc)") }
                    return (ns, t.desc)
                }
            }
            return nil
        }

        // MARK: 单阶段（motif / embellishment）外层循环

        private func applyPhase(_ phaseSubs: [GSub], _ input: [KWNote]) -> [KWNote] {
            let grid = SlotGrid(notes: input)
            var curSlot = 0
            while curSlot < grid.total {
                let curHead = grid.headAtOrBefore(curSlot)
                let cand = orderedUniqueSubs(phaseSubs.filter { $0.enabled && subApplicable($0, grid: grid, curSlot: curSlot) })
                if trace {
                    let cj = cand.map { $0.name }.joined(separator: "\t")
                    print("OUTERCAND\t\(curSlot)" + (cj.isEmpty ? "" : "\t" + cj))
                }
                var moved = false
                for s in cand {
                    if let ok = applySub(s, grid: grid, curSlot: curSlot) {
                        if trace { print("OUTERPICK\t\(curSlot)\t\(s.name)") }
                        curSlot = ok.nextSlot; moved = true; break
                    }
                }
                if !moved { curSlot = grid.nextHead(curHead) } // 无 sub 成功 → 下一音头
            }
            return grid.compress()
        }

        // MARK: 两阶段

        private func run(_ input: [KWNote]) -> [KWNote] {
            let motif = allSubs.filter { $0.type == "motif" }
            let emb = allSubs.filter { $0.type == "embellishment" }
            var w = input
            // F16：对齐 Java if(subs.size()>0)，空阶段整体跳过（不遍历、无 trace）
            if !motif.isEmpty { w = applyPhase(motif, w) }
            if !emb.isEmpty { w = applyPhase(emb, w) }
            return w
        }
    }
}

// =====================================================================
// 【旧码封存 · T2 F22 之前的"整音 replaceSubrange"实现，保留勿删，仅供回退/对照】
// 旧实现把旋律压缩成 [KWNote] 数组、用 replaceSubrange 整段替换，仅当游标都落在音头时与
// Java 等价；游标落在音内（slot 400 do-nothing 吞中间音等场景）会与 Part slot 数组语义不一致。
// F22 起改为上方 SlotGrid slot 级写入。回退方法：把本类恢复为下方实现、并把总开关改回 false。
//
// fileprivate struct KWNoteLegacy { var pitch: Int; var dur: Int; var rest: Bool }
// private func slotOf(_ work:[KWNote],_ idx:Int)->Int { var a=0; for j in 0..<min(idx,work.count){a+=work[j].dur}; return a }
// private func tryTrans(_ t:GTrans, work:[KWNote], cursor i:Int)->(work:[KWNote],next:Int)? {
//     let changeFirst=t.changesFirstNote(); var start=i
//     if !changeFirst && i>0 { start=i-1 }
//     let k=t.src.count; guard start+k<=work.count else { return nil }
//     /* 绑定 work[start+j] → guard 须 true → targets flatten → before=Σwork[start..].dur，
//        enforceDuration before==after → newWork.replaceSubrange(start..<start+k, with: result)，
//        nextI=i+result.count */
//     return nil
// }
// private func applyPhase(_ phaseSubs:[GSub],_ input:[KWNote])->[KWNote] {
//     var work=input; var i=0
//     while i<work.count {
//         var moved=false
//         for s in orderedUniqueSubs(phaseSubs.filter{...}) {
//             if let ok=applySub(s,work:work,cursor:i){ work=ok.work; i=ok.next; moved=true; break }
//         }
//         if !moved { i+=1 }
//     }
//     return work
// }
//
// 更旧的 19 组手写模板链（Transform.swift 旧三阶段 + 单层 randomElement）仍在 Transform.swift
// 文件内封存（仅 useJavaAlignedTransform=false 时可达），本文件不再重复。
// =====================================================================
