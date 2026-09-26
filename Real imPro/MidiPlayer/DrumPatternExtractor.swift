import Foundation

// MARK: - DrumPatternExtractor 鼓组 → CompanionNote (按时间采样, 修复对齐)
// 解决: 串行生成 → 按 slot 时间点并行采样所有鼓件
//       rest 无等待 → rest 不生成音符, 但后续音的 startSlot 正确偏移
//       假排序   → startSlot 天然有序, 无需排序

struct DrumPatternExtractor {
    
    /// 在一个时间点, 收集所有正在发声的鼓件
    struct ActiveHit {
        let midiPitch: UInt8
        let velocity: UInt8
        let endSlot: Int      // 音结束的绝对 slot
    }
    
    /// 按 slot 时间点采样: 遍历 0..totalSlots, 每 slot 收集所有鼓击 → 每个独立音的 start/end
    static func generate(pattern: DrumPattern, measureCount: Int, slotsPerMeasure: Int = 480) -> [CompanionNote] {
        var notes: [CompanionNote] = []
        let totalSlots = measureCount * slotsPerMeasure
        
        // 展开所有鼓 Rule 到绝对 slot 位置 (pre-compute)
        // 结构: [(startSlot, endSlot, midiPitch, velocity)]
        var allHits: [(start: Int, end: Int, pitch: UInt8, vel: UInt8)] = []
        let patternLen = pattern.durationSlots > 0 ? pattern.durationSlots : 480
        
        for measure in 0..<measureCount {
            let base = measure * slotsPerMeasure
            for rule in pattern.rules {
                var tileOffset = base
                while tileOffset < base + slotsPerMeasure {
                    for elem in rule.elements {
                        if elem.isRest { continue }
                        let start = tileOffset + elem.onsetSlots
                        if start >= base + slotsPerMeasure { continue }
                        let end = min(start + elem.durationSlots, base + slotsPerMeasure)
                        allHits.append((start, end, rule.midiNote, elem.velocity))
                    }
                    tileOffset += patternLen
                }
            }
        }
        
        // 按 startSlot 从小到大排序
        allHits.sort { $0.start < $1.start }
        
        // 聚合同一 startSlot 的所有鼓 (多鼓同时击打 → 取最大力度)
        var slotGroups: [Int: [(end: Int, pitch: UInt8, vel: UInt8)]] = [:]
        for hit in allHits {
            slotGroups[hit.start, default: []].append((hit.end, hit.pitch, hit.vel))
        }
        
        // 去重: 同一 start slot 同一 pitch → 取最大 vel + 最长 duration
        var deduped: [(start: Int, end: Int, pitch: UInt8, vel: UInt8)] = []
        for (start, hits) in slotGroups.sorted(by: { $0.key < $1.key }) {
            var grouped: [UInt8: (end: Int, vel: UInt8)] = [:]
            for h in hits {
                if let existing = grouped[h.pitch] {
                    grouped[h.pitch] = (max(existing.end, h.end), max(existing.vel, h.vel))
                } else {
                    grouped[h.pitch] = (h.end, h.vel)
                }
            }
            for (pitch, info) in grouped {
                deduped.append((start, info.end, pitch, info.vel))
            }
        }
        
        // 最终按 start 排序后输出
        deduped.sort { $0.start < $1.start }
        
        for hit in deduped {
            notes.append(CompanionNote(
                startSlot: hit.start,
                midiPitch: hit.pitch,
                durationSlots: hit.end - hit.start,
                volume: hit.vel,
                channel: 9
            ))
        }
        
        // 插入总时长为 totalSlots 的终点哨兵(rest), 保证最后一个小节也有完整时长
        // (播放器用 startSlot 差值计算等待, 不需要哨兵, 但可帮助 totalDuration 计算)
        
        return notes
    }
}
