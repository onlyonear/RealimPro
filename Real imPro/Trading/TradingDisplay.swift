import Foundation
import Combine

// MARK: - Trading / Display / 谱面显示桥（M2-6b；M2-8 改为「累积谱」）
//
// M2-8 起由「4 小节整体替换」改为「保留完整 roadmap 小节，旋律轨按物理小节累加」：
//   reset(roadmap:)                         开始时铺完整谱（和弦/段落/换和弦常驻，旋律按
//                                           chordSlots 分段填休止符并挂和弦字母）；
//   overlay(turnBars:physicalStartBar:)     每轮只替换对应物理小节的旋律内容（notes +
//                                           chordAnnotations，turnBars 已由 TradingNoteTagger
//                                           打颜色 tag 并重算和弦标签）；替换语义，天然幂等。
//   没有 Trading 内容时（measures == nil）ContentView 完全走原谱逻辑。
//
// 线程纪律：对 full 的读写与 measures 的发布始终在同一主线程闭包内整段完成（不在后台改 full）。
final class TradingDisplay: ObservableObject {
    static let shared = TradingDisplay()

    /// 非 nil 时，五线谱优先显示它（完整 roadmap 小节数，如 demo 36 小节）
    @Published var measures: [GeneratedMeasure]? = nil

    /// 显示版本号（供需要显式触发的视图使用）
    @Published var version: Int = 0

    /// M2-8：播放逐音高亮的当前 note id（形如 "note-mIndex-noteIndex"）；曲末/退出置 ""
    @Published var highlightedNoteId: String = ""

    #if DEBUG
    /// [M2-8f] 逐音高亮变化轨迹（去重），供 tradingdemo36 客观核验随声高亮；reset 时清空。
    var highlightTrace: [String] = []
    /// [M2-8f2] 每次 reset/overlay 的滚动目标小节（= 当前轮起始物理小节）轨迹，供核验视图跟随。
    var activeBarTrace: [Int] = []
    #endif

    /// [M2-8f2] 当前轮起始物理小节（视图滚动锚点）：reset=0、overlay=physicalStartBar。
    /// 普通属性，随 overlay/reset 在主线程更新；非 Trading 时 ContentView 不读取。
    var activeBar: Int = 0

    /// 累积谱真源（measures 是它的发布快照；二者读写始终在同一主线程闭包内）
    private var full: [GeneratedMeasure] = []

    private init() {}

    // MARK: - M2-8 累积谱

    /// 开始：铺完整 roadmap——和弦/段落/chordSlots 常驻；旋律轨按 chordSlots 分段填休止符、
    /// 每段挂和弦字母（TradingChordSkeleton 复刻正常链路 ContentView:1130-1186，bit-exact）。
    func reset(roadmap: [GeneratedMeasure]) {
        let work = {
            self.full = roadmap.map { m in
                TradingChordSkeleton.skeletonRestMeasure(
                    chord: m.chord,
                    chordSlots: m.chordSlots,
                    sectionName: m.sectionName,
                    slotsPerMeasure: m.slotsPerMeasure)
            }
            self.measures = self.full
            self.activeBar = 0
            dprint("[D-P5] reset roadmap=\(roadmap.count) -> full.count=\(self.full.count)")
            #if DEBUG
            self.highlightTrace = []   // [M2-8f] 新会话清空高亮轨迹
            self.activeBarTrace = [0]  // [M2-8f2] reset 锚到第 0 小节
            #endif
            self.version &+= 1
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// 把本轮 turnBars 叠加到物理小节 [physicalStartBar, physicalStartBar+turnBars.count)。
    /// 只替换旋律内容（notes + chordAnnotations）；和弦/段落/chordSlots/slotsPerMeasure
    /// 永远保留 roadmap（full）原值。替换语义 + 固定物理小节 → 天然幂等，不写错小节、不累加。
    func overlay(turnBars: [GeneratedMeasure], physicalStartBar: Int) {
        let work = {
            for (k, turnBar) in turnBars.enumerated() {
                let idx = physicalStartBar + k
                guard self.full.indices.contains(idx) else { continue }
                let old = self.full[idx]
                self.full[idx] = GeneratedMeasure(
                    chord: old.chord,
                    notes: turnBar.notes,
                    chordAnnotations: turnBar.chordAnnotations,
                    sectionName: old.sectionName,
                    slotsPerMeasure: old.slotsPerMeasure,
                    chordSlots: old.chordSlots)
            }
            self.measures = self.full
            self.activeBar = physicalStartBar
            dprint("[D-P5] overlay startBar=\(physicalStartBar) turnBars=\(turnBars.count) full.count=\(self.full.count)")
            #if DEBUG
            self.activeBarTrace.append(physicalStartBar)
            #endif
            self.version &+= 1
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// M2-8：播放中设置当前高亮 note（回放回调在 session queue，内部派主线程）
    func setHighlight(_ noteId: String) {
        let work = {
            self.highlightedNoteId = noteId
            #if DEBUG
            if self.highlightTrace.last != noteId { self.highlightTrace.append(noteId) }
            #endif
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// 清残留高亮（曲末 / 轮切换 / 中途打断 / 退出）
    func clearHighlight() {
        let work = {
            self.highlightedNoteId = ""
            #if DEBUG
            if self.highlightTrace.last != "" { self.highlightTrace.append("") }
            #endif
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    // MARK: - 旧 4 小节整体替换（M2-8d 接线 reset/overlay 后删除；本批保留以免 Session 编译断裂）
    func show(_ m: [GeneratedMeasure]) {
        if Thread.isMainThread {
            measures = m; version &+= 1
        } else {
            DispatchQueue.main.async { self.measures = m; self.version &+= 1 }
        }
    }

    /// 退出 Trading，回到原谱（清空累积谱与高亮）
    func clear() {
        let work = {
            dprint("[D-P5] clear before full.count=\(self.full.count) -> full=[] measures=nil")
            self.full = []
            self.measures = nil
            self.highlightedNoteId = ""
            self.version &+= 1
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }
}
