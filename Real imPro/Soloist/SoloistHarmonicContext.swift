//
//  SoloistHarmonicContext.swift
//  Real imPro · Soloist 运行时（K2-7c 和弦适配）
//
//  作用：把"绝对 slot → 当前和弦"映射成可查询的上下文，并提供"和弦上站得住的音"集合。
//  对齐口径（二十审）：
//  - 只从 JazzRoadmap 按拍长累加建表（roadmap 已在 ContentView:1331-1343 剔除空/NC 和弦），
//    因此天然从 solo 起点对齐；绝不引用原始歌曲的小节索引（弱起会整段错位）。
//  - 合法音判定与验收测量共用同一把尺：Coloration.classify ∈ {chordTone, colorTone}。
//

import Foundation

struct SoloistHarmonicContext {

    struct Entry {
        let startSlot: Int
        let name: String
    }

    private let entries: [Entry]
    private let endSlot: Int

    static let slotsPerBeat = JazzGuideToneEngine.slotsPerBeat

    /// 生产路径：由 roadmap 建表（solo 从 roadmap 第 0 拍开始）
    init(roadmap: JazzRoadmap) {
        var cur = 0
        var out: [Entry] = []
        for block in roadmap.flattenRoadmap() {
            out.append(Entry(startSlot: cur, name: block.name))
            cur += Int((block.duration * Double(Self.slotsPerBeat)).rounded())
        }
        entries = out
        endSlot = cur
    }

    /// 测试路径：直接给和弦时间表（合成弱起、单元测试用）
    init(schedule: [(name: String, durationSlots: Int)]) {
        var cur = 0
        var out: [Entry] = []
        for item in schedule {
            out.append(Entry(startSlot: cur, name: item.name))
            cur += item.durationSlots
        }
        entries = out
        endSlot = cur
    }

    var totalSlots: Int { endSlot }

    /// 绝对 slot 处的和弦名；越界返回 nil
    func chordName(atAbsoluteSlot slot: Int) -> String? {
        guard !entries.isEmpty, slot >= 0 else { return nil }
        var lo = 0, hi = entries.count - 1, ans: Int? = nil
        while lo <= hi {
            let mid = (lo + hi) / 2
            if entries[mid].startSlot <= slot { ans = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        guard let idx = ans else { return nil }
        return entries[idx].name
    }

    /// 该和弦上"站得住"的音级集合（和弦音 ∪ 色彩音）
    func legalPitchClasses(for chordName: String) -> Set<Int> {
        var set = Set<Int>()
        for pc in 0..<12 {
            let cat = Coloration.classify(midiPitch: pc, chordName: chordName)
            if cat == .chordTone || cat == .colorTone { set.insert(pc) }
        }
        return set
    }

    /// 在 [lo, hi] 内找离 p 最近的合法音；等距取靠下（音高更小）。找不到返回 nil
    func nearestLegalPitch(to p: Int, chordName: String, lo: Int, hi: Int) -> Int? {
        let legal = legalPitchClasses(for: chordName)
        guard !legal.isEmpty else { return nil }
        let clampedLo = max(lo, 0, p - 11)
        let clampedHi = min(hi, 127, p + 11)
        for d in 0...11 {
            let down = p - d
            if down >= clampedLo && legal.contains(((down % 12) + 12) % 12) { return down }
            if d == 0 { continue }
            let up = p + d
            if up <= clampedHi && legal.contains(((up % 12) + 12) % 12) { return up }
        }
        return nil
    }
}
