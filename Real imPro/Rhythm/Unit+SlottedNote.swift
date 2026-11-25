import Foundation

// MARK: - Unit + SlottedNote — 统一时隙系统 (P1 · 约60行)
// 消除 GrammarTerminal.durationSlots vs PhysicalNote.durationSlots 语义冲突
// 统一 RhythmValue 读写接口, 适配 Swing 偏移 / 三连音换算

// ═══════════════════════════════════════════════════════
// 1. Unit 协议: 所有含节奏值的类型实现
// ═══════════════════════════════════════════════════════

/// 节奏单元协议 — 统一时值读写接口
protocol RhythmUnit {
    /// 节奏值 (以120slots/拍为基准)
    var rhythmValue: Int { get set }
}

/// 默认节奏值 = 四分音符 (120 slots)
let DEFAULT_RHYTHM_VALUE: Int = 120

// ═══════════════════════════════════════════════════════
// 2. SlottedNote: 带槽位占用的音符
// ═══════════════════════════════════════════════════════

/// 槽位音符: 用于节奏填充算法, 记录占用的槽位数量
struct SlottedNote: RhythmUnit {
    /// 音高 (MIDI, -1=休止符)
    let midiPitch: Int
    /// 节奏值 = 占用槽位数
    var rhythmValue: Int
    /// 起始槽位
    let startSlot: Int

    /// 结束槽位
    var endSlot: Int { startSlot + rhythmValue }

    init(midiPitch: Int, rhythmValue: Int = DEFAULT_RHYTHM_VALUE, startSlot: Int = 0) {
        self.midiPitch = midiPitch
        self.rhythmValue = rhythmValue
        self.startSlot = startSlot
    }

    /// 从 PhysicalNote 构造
    init(note: PhysicalNote, startSlot: Int = 0) {
        self.midiPitch = note.midiPitch
        self.rhythmValue = note.durationSlots
        self.startSlot = startSlot
    }
}

// ═══════════════════════════════════════════════════════
// 3. PhysicalNote RhythmUnit 扩展
// ═══════════════════════════════════════════════════════

extension PhysicalNote: RhythmUnit {
    var rhythmValue: Int {
        get { durationSlots }
        set { self = PhysicalNote(midiPitch: midiPitch, durationSlots: newValue, terminalType: terminalType) }
    }
}

// ═══════════════════════════════════════════════════════
// 4. 时隙换算工具
// ═══════════════════════════════════════════════════════

/// 全局时隙换算 (统一消除 32slot/小节 ↔ 120slot/拍 冲突)
enum SlotConverter {
    /// 标准: 120 slots/拍, 4/4 = 480 slots/小节
    static let SLOTS_PER_BEAT = 120
    static let SLOTS_PER_MEASURE_4_4 = 480

    /// RhythmGenerator 内部使用 32 slots/小节格式 → 转为120标准
    static func rhythmSlotsToStandard(_ rhythmSlots: Int) -> Int {
        rhythmSlots * SLOTS_PER_MEASURE_4_4 / 32
    }

    /// 120标准 → 32 RhythmGenerator 格式
    static func standardToRhythmSlots(_ standardSlots: Int) -> Int {
        standardSlots * 32 / SLOTS_PER_MEASURE_4_4
    }

    /// Beat 拍数 → 120标准 slots
    static func beatsToSlots(_ beats: Double) -> Int {
        Int(beats * Double(SLOTS_PER_BEAT))
    }

    /// 120标准 slots → Beat 拍数
    static func slotsToBeats(_ slots: Int) -> Double {
        Double(slots) / Double(SLOTS_PER_BEAT)
    }

    /// 三连音时隙换算: 1拍三连音 = 3个均分 slot
    /// 每拍120slots, 三连音每音 = 40 slots
    static let TRIPLET_PER_BEAT = 3
    static let TRIPLET_SLOT = SLOTS_PER_BEAT / TRIPLET_PER_BEAT  // 40

    /// n连音时隙计算 (如五连音=120/5=24)
    static func tupletSlots(count: Int) -> Int {
        SLOTS_PER_BEAT / count
    }
}

// ═══════════════════════════════════════════════════════
// 5. Swing 偏移兼容 (追加参数)
// ═══════════════════════════════════════════════════════

extension SlotConverter {
    /// Swing偏移后的时隙分配 (第1个八分音×swingRatio, 第2个×complement)
    static func swingSlots(swingValue: Double = 0.666) -> (first: Int, second: Int) {
        let beatSlots = Double(SLOTS_PER_BEAT)
        let first = Int(beatSlots * swingValue)
        let second = Int(beatSlots * (1.0 - swingValue))
        return (first, second)
    }
}
