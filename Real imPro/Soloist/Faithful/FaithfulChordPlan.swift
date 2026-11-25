import Foundation

// MARK: 小节内真实和弦（slot 时值）
struct MeasureChord: Equatable {
    let name: String
    let slots: Int          // 该和弦在本小节占的 slot 数；同小节各 slots 之和 = 480
}

/// 把当前歌曲真实 roadmap 按小节切分，得到每小节的真实和弦序列。
/// 对齐 Java buildSolo：每小节 extract 当前真实和弦、定音基于当前和弦。
enum FaithfulChordPlan {

    /// 从 JazzSong 直接构建【保留 NC】的展平 blocks（Faithful 专用，不碰 grammar 共用 roadmap）。
    /// 口径与 worker isGuide 路径一致：N.C. 归一为 NC，全 NC 小节也保留、占整小节时长，
    /// 保证总拍数 = 小节数 × 4，供 FaithfulChordPlan.make 切小节守恒。
    static func blocksKeepingNoChord(from song: JazzSong) -> [ChordBlock] {
        var blocks: [ChordBlock] = []
        for (measureIndex, measureChords) in song.measures.enumerated() {
            let measureDurations = song.measureDurations[measureIndex]
            for (index, rawChord) in measureChords.enumerated() {
                let clean = rawChord.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { continue }
                let name = (clean == "N.C.") ? "NC" : clean
                let duration = index < measureDurations.count ? measureDurations[index] : 4.0
                let isSectionStart = (index == 0) && (song.sectionMarkers[measureIndex] != nil)
                blocks.append(ChordBlock(name: name, duration: duration,
                                         isSectionStart: isSectionStart))
            }
        }
        return blocks
    }

    /// 从已展平、已过滤 NC 的 ChordBlock 序列，提炼 numMeasures 小节的和弦计划。
    /// 用全局 slot 边界切分，天然保证每小节 slot 守恒（=480）；任一空小节返回 nil。
    static func make(blocks: [ChordBlock], numMeasures: Int) -> [[MeasureChord]]? {
        // 每个 block 的全局结束 slot（拍 ×120，四舍五入）
        var endSlots: [Int] = []
        var accBeats = 0.0
        for b in blocks {
            accBeats += b.duration
            endSlots.append(Int((accBeats * 120.0).rounded()))
        }
        // 总长度必须等于 numMeasures×480（FaithfulGate 已在外部保证，这里再校验一次）
        guard endSlots.last == numMeasures * 480 else { return nil }

        var plan: [[MeasureChord]] = []
        for m in 0..<numMeasures {
            let mStart = m * 480
            let mEnd = mStart + 480
            var items: [MeasureChord] = []
            for (bi, b) in blocks.enumerated() {
                let bStart = bi == 0 ? 0 : endSlots[bi - 1]
                let bEnd = endSlots[bi]
                let ovStart = max(bStart, mStart)
                let ovEnd = min(bEnd, mEnd)
                guard ovEnd > ovStart else { continue }
                items.append(MeasureChord(name: b.name, slots: ovEnd - ovStart))
            }
            if items.isEmpty { return nil }
            plan.append(items)
        }
        return plan
    }

    /// 把一小节的真实和弦计划转成定音用 ChordContext（单和弦/多和弦）。
    static func context(for items: [MeasureChord]) throws -> ChordContext {
        if items.count == 1 {
            guard let chord = ChordCatalog.chordIfExists(items[0].name) else {
                throw FaithfulError.chordUnavailable(name: items[0].name)
            }
            return ChordContext(chord: chord)
        }
        let parts = items.map { (name: $0.name, duration: $0.slots) }
        guard let ctx = ChordContext(parts: parts) else {
            throw FaithfulError.chordUnavailable(name: items.map { $0.name }.joined(separator: ","))
        }
        return ctx
    }
}
