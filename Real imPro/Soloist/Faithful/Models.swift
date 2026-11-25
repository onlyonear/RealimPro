import Foundation

// MARK: 类型常量（与 LickGen/NoteChooser 一致）
let NOTE = 1000
let CHORD = 1001
let SCALE = 1002
let COLOR = 1003
let APPROACH = 1004
let RANDOM = 1005
let BASS = 1006
let GOAL = 1007
let OUTSIDE = 1008
let EXPECTANCY = 1009
let REST = -1   // 抽象休止用 pitch=-1 表示

// MARK: 时值解析（复刻 Duration.getDuration）
enum Duration2 {
    static let WHOLE = 480
    static func getDuration(_ item: String) -> Int {
        guard let first = item.first, first.isNumber else { return 120 }
        var duration = 0
        var index = item.startIndex
        var isFirstSegment = true
        while index < item.endIndex && (isFirstSegment || item[index] == "+") {
            if !isFirstSegment { index = item.index(after: index) } // 跳过 '+'
            isFirstSegment = false
            // 收集数字
            var numStr = ""
            while index < item.endIndex && item[index].isNumber {
                numStr.append(item[index]); index = item.index(after: index)
            }
            let numerator = Int(numStr) ?? 1
            var denominator = 1
            if index < item.endIndex && item[index] == "/" {
                index = item.index(after: index)
                var denStr = ""
                while index < item.endIndex && item[index].isNumber {
                    denStr.append(item[index]); index = item.index(after: index)
                }
                denominator = Int(denStr) ?? 1
            }
            var slots = WHOLE
            if denominator > 1 { slots *= (denominator - 1) }
            var thisDuration = slots / (numerator * denominator)
            // 附点
            var increment = thisDuration
            while index < item.endIndex && item[index] == "." {
                increment /= 2
                thisDuration += increment
                index = item.index(after: index)
            }
            duration += thisDuration
        }
        return duration <= 0 ? 120 : duration
    }
}

// MARK: 抽象音符（发声前 pitch 存类型，发声后存真实 MIDI）
struct Note2 {
    var pitch: Int
    var rhythmValue: Int
    var isRest: Bool
    static func makeRest(_ rv: Int) -> Note2 { Note2(pitch: -1, rhythmValue: rv, isRest: true) }
}

// MARK: 和弦（spell/color 音高 class，数据来自 ChordTonesProbe 实测）
struct Chord2 {
    let name: String
    let root: Int          // 根音半音 class
    let family: String     // major/minor/minor7/dominant/...
    let spell: Set<Int>
    let color: Set<Int>
    var isNoChord: Bool = false   // NC 占位：占整小节、选音不限制（对齐 Java checkNote 短路）
    /// 判断某 MIDI 音高 class 是否为和弦音
    func isChordTone(_ pc: Int) -> Bool { isNoChord ? true : spell.contains(pc) }
    func isColorTone(_ pc: Int) -> Bool { isNoChord ? true : color.contains(pc) }
}

enum ChordCatalog {
    /// 金标准表未覆盖的补充：C 三和弦（口径与 Java ChordTonesProbe 一致）
    private static let supplement: [String: Chord2] = [
        "C": Chord2(name: "C", root: 0, family: "major", spell: [0, 4, 7], color: [6, 2, 11, 9]),
    ]
    /// NC 占位和弦：占整小节、无 spell/color，选音不限制（对齐 Java ChordSymbol NC + checkNote 短路）
    static let noChord = Chord2(name: "NC", root: 0, family: "NC", spell: [], color: [], isNoChord: true)
    private static var cache: [String: Chord2] = [:]

    /// 与 Java 一致的名称归一：斜杠取本体、减号/o7/dim 等后缀归一，还原为带 root 的规范名。
    /// 对齐 Java ChordSymbol：getQuality 对斜杠 split 取 [0]，checkValidity 用 CROOT+type 查 ChordForm。
    private static func normalizedCanonicalName(_ raw: String) -> String? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 1) 斜杠 X/Y：定音只看本体 X（斜杠后是 bass，只给贝斯用）
        let body = key.components(separatedBy: "/").first ?? key
        let chars = Array(body)
        guard !chars.isEmpty else { return nil }
        var rootLen = 1
        if chars.count > 1 && (chars[1] == "#" || chars[1] == "b") { rootLen = 2 }
        var rootSpell = String(chars[0..<rootLen])
        if let first = rootSpell.first, first.isLowercase {
            rootSpell = first.uppercased() + rootSpell.dropFirst()
        }
        // 2) 通用后缀归一（减号 minor、o7/dim、maj 等全部写法），失败即 nil
        guard let resolved = ChordSymbolMapper.resolve(body) else { return nil }
        // 3) canonical 首字母为 C，去掉得到规范后缀，拼回原 root
        let suffix = String(resolved.canonical.dropFirst())
        return rootSpell + suffix
    }

    /// 可失败查找（绝不强制崩溃）：先直接查金标准表，再对表外写法做名称归一。
    /// 对应 Java 查不到返回 null 的口径；返回 nil 由上层抛错并回退 grammar。
    static func chordIfExists(_ name: String) -> Chord2? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // NC/N.C. 占位：返回不限制选音的特殊和弦（对齐 Java makeChordSymbol NC）
        if key == "NC" || key == "N.C." { return noChord }
        if let hit = cache[key] { return hit }
        // 1) 金标准表/补充表直接命中（歌曲里的规范写法，保证零回归）
        if let direct = ChordGoldTable.gold[key] ?? supplement[key] {
            cache[key] = direct
            return direct
        }
        // 2) 表外写法：先旧别名（maj69/maj6/E7alt），再通用归一（斜杠/减号/o7）
        let canon = ChordGoldTable.alias[key] ?? normalizedCanonicalName(key)
        guard let hit = canon.flatMap({ ChordGoldTable.gold[$0] ?? supplement[$0] }) else {
            return nil
        }
        cache[key] = hit
        return hit
    }
}

// MARK: 小节和弦上下文（支持单和弦占满 480，或多和弦按起始 slot 切换）
struct ChordContext {
    let entries: [(start: Int, chord: Chord2)]

    /// 整段：直接指定绝对位置 entries
    init(entries: [(start: Int, chord: Chord2)]) {
        self.entries = entries
    }

    init(chord: Chord2) {
        entries = [(0, chord)]
    }
    /// 多和弦（可失败）：parts 为 (和弦名, 时值)，按顺序拼接，时值总和应为 480；
    /// 任一和弦无法解析则返回 nil（上层抛错回退 grammar，绝不崩溃）
    init?(parts: [(name: String, duration: Int)]) {
        var es: [(Int, Chord2)] = []
        var cursor = 0
        for p in parts {
            guard let chord = ChordCatalog.chordIfExists(p.name) else { return nil }
            es.append((cursor, chord))
            cursor += p.duration
        }
        entries = es
    }
    /// 复刻 getCurrentChord：返回该位置发声的和弦（回退到前一个起始和弦）
    func chordAt(position: Int) -> Chord2 {
        var result = entries[0].chord
        for e in entries where e.start <= position { result = e.chord }
        return result
    }
}

// MARK: 发声结果容器（稀疏绝对 slot 存储，复刻 Part/MelodyPart：每个数组元素=一个最小 slot，允许重叠）
struct MelodyPart2 {
    private(set) var slots: [Note2?] = []
    var partSize: Int { slots.count }

    /// Part.addUnit：在末尾展开 rv 个 slot（后 rv-1 个为 null），起始 slot 放 note；返回写入位置
    @discardableResult
    mutating func addUnit(_ n: Note2) -> Int {
        let index = slots.count
        let newSize = index + n.rhythmValue
        while slots.count < newSize { slots.append(nil) }
        slots[index] = n
        return index
    }
    /// 对外发声追加入口（MelodyPart.addNote 即 addUnit），返回写入位置
    @discardableResult
    mutating func addNote(_ n: Note2) -> Int { addUnit(n) }

    /// 合并：把 atSlot 位置单元的 rv 加 extra，并按 setSize 等价扩展 slots（休止/重复音合并）
    mutating func mergeRhythm(atSlot slot: Int, extra: Int) {
        guard let n = slots[slot] else { return }
        slots[slot] = Note2(pitch: n.pitch, rhythmValue: n.rhythmValue + extra, isRest: n.isRest)
        let newSize = slots.count + extra
        while slots.count < newSize { slots.append(nil) }
    }

    /// 对外逻辑音符视图：非 null 单元，按 slot 顺序（紧凑读取代码用）
    var notes: [Note2] { slots.compactMap { $0 } }

    var size: Int { slots.count }
    var lowest: Int { notes.filter { !$0.isRest }.map { $0.pitch }.min() ?? Int.max }
    var highest: Int { notes.filter { !$0.isRest }.map { $0.pitch }.max() ?? Int.min }

    /// 复刻 Part.getNextIndex：返回 from 之后第一个非 null slot（无则 slots.count）
    func getNextIndex(_ from: Int) -> Int {
        var i = from + 1
        while i < slots.count && slots[i] == nil { i += 1 }
        return i
    }

    /// 复刻 Part.getPrevIndex：返回 slotIndex 之前最近的非 null slot（无则 -1）
    func getPrevIndex(_ slotIndex: Int) -> Int {
        if slotIndex < 0 { return -1 }
        var i = slotIndex - 1
        while i >= 0 && slots[i] == nil { i -= 1 }
        return i
    }

    /// 把另一小节（已含 null 展开的 slots）逐个追加到当前末尾，绝对位置自然对齐（复刻 addMelody 追加）
    mutating func appendPart(_ other: MelodyPart2) {
        for n in other.slots { slots.append(n) }
    }

    /// mergeTies：复刻 HarnessLickGen.mergeTies 523-545 + Part.delUnit 1048-1093。
    /// 关键口径：lastNote 是独立引用，合并后会被重指向"被删的 currentNote"（已脱离 slots）。
    /// 因此连续合并时，只有 delUnit 内部（getPrevIndex 重新定位）那次累加到真正的前音，
    /// 外部 lastNote 的累加可能落到脱离对象上。用 lastNote 副本 + lastSlot（在 slots 中索引；nil=脱离）模拟。
    mutating func mergeTiesAtBoundary() {
        var tracker = getNextIndex(0)
        var lastNote = Note2(pitch: 0, rhythmValue: 0, isRest: false)
        var lastSlot: Int? = nil
        while tracker < slots.count {
            guard let currentNote = slots[tracker] else {
                tracker = getNextIndex(tracker); continue
            }
            if tracker % 480 == 0 && currentNote.pitch == lastNote.pitch {
                // delUnit(tracker)：当前 slot 设 null，prevUnit.rv += current.rv（第一次累加）
                slots[tracker] = nil
                let prevSlot = getPrevIndex(tracker)
                if prevSlot >= 0, let pu = slots[prevSlot] {
                    slots[prevSlot] = Note2(pitch: pu.pitch, rhythmValue: pu.rhythmValue + currentNote.rhythmValue, isRest: pu.isRest)
                }
                // 外部 lastNote.rv += current.rv（第二次）；若 lastNote 仍在 slots 中，同步写回
                lastNote = Note2(pitch: lastNote.pitch, rhythmValue: lastNote.rhythmValue + currentNote.rhythmValue, isRest: lastNote.isRest)
                if let ls = lastSlot, let ln = slots[ls] {
                    slots[ls] = Note2(pitch: ln.pitch, rhythmValue: ln.rhythmValue + currentNote.rhythmValue, isRest: ln.isRest)
                }
                // lastNote = currentNote（已脱离 slots）
                lastNote = currentNote
                lastSlot = nil
            } else {
                // lastNote = currentNote（仍在 slots[tracker]）
                lastNote = currentNote
                lastSlot = tracker
            }
            tracker = getNextIndex(tracker)
        }
    }
}
