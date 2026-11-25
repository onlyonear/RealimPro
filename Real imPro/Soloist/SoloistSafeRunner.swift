//
//  SoloistSafeRunner.swift
//  Real imPro · Soloist 运行时（K2-7 生产接入）
//
//  R9 防御层：对应 Java 里"重试 15 次、到头递归重启（无上限）"的控制流风险。
//  本方案用真实片段、音高天然不越界，但仍加结构性安全网：
//  - 每次生成后做绝对音域校验（门 4-D：越界音零漏出）
//  - K2-7b 音域围栏校验（门 4-E：发声音必须落在 [center-11, center+11] 内，越界即判失败）
//  - 时值守恒校验（门 4-A：总时值必须等于 目标小节数 × 每小节 480 slot）
//  - 意外越界时有限重试，超过安全上限明确回退 grammar（不做无界递归）
//  - DEBUG 下逐笔记账（回退原因/触发频率），Release 完全剥离
//

import Foundation

// MARK: - 绝对音域校验

enum SoloistBoundsGovernor {
    /// 门 4-D：每个发声单元必须在 0...127；休止（-1）合法
    static func withinAbsoluteBounds(_ notes: [PhysicalNote]) -> Bool {
        notes.allSatisfy { note in
            note.midiPitch == -1 || (0...127).contains(note.midiPitch)
        }
    }

    /// 门 4-E（K2-7b）：每个发声单元必须落在音域围栏 [center-half, center+half] 内。
    /// 越界即判失败——不再"洗成合法音"，避免错误被静默抹平。
    static func withinRegisterWindow(_ notes: [PhysicalNote], center: Int, half: Int) -> Bool {
        notes.allSatisfy { note in
            note.midiPitch == -1
                || (note.midiPitch >= center - half && note.midiPitch <= center + half)
        }
    }

    /// 时值守恒：单元时值之和应等于目标小节总 slot
    static func durationConserved(_ notes: [PhysicalNote],
                                  targetMeasures: Int,
                                  measureLength: Int) -> Bool {
        let sum = notes.reduce(0) { $0 + $1.durationSlots }
        return sum == targetMeasures * measureLength
    }
}

// MARK: - DEBUG 记账（Release 剥离）

#if DEBUG
struct SoloistLedgerEntry: Equatable {
    let file: String
    let targetMeasures: Int
    let attempt: Int
    let reason: String
}

final class SoloistDebugLedger {
    static let shared = SoloistDebugLedger()
    private(set) var entries: [SoloistLedgerEntry] = []
    private init() {}

    func record(_ entry: SoloistLedgerEntry) { entries.append(entry) }
    func reset() { entries.removeAll() }

    /// 按原因汇总触发频率
    func frequencyByReason() -> [String: Int] {
        var m: [String: Int] = [:]
        for e in entries { m[e.reason, default: 0] += 1 }
        return m
    }
}
#endif

// MARK: - 安全运行器

struct SoloistSafeRunner {
    let generator: SoloistMelodyGenerator
    /// R9 安全上限：真实片段几乎不触发，仅作结构性兜底
    let maxAttempts: Int
    /// 每小节 slot 数（4/4 拍 = 4 × 120）
    let measureLength: Int

    init(generator: SoloistMelodyGenerator,
         maxAttempts: Int = 3,
         measureLength: Int = 4 * JazzGuideToneEngine.slotsPerBeat) {
        self.generator = generator
        self.maxAttempts = max(3, maxAttempts)
        self.measureLength = measureLength
    }

    func run(targetMeasures: Int, rng: SoloistRNG,
             harmonicContext: SoloistHarmonicContext? = nil) -> SoloistGenerateOutcome {
        let rng = rng

        for attempt in 0..<maxAttempts {
            let outcome = generator.generate(targetMeasures: targetMeasures, rng: rng,
                                             harmonicContext: harmonicContext)

            switch outcome {
            case .fallbackToGrammar(let reason):
                // 无等长轮廓/空候选是确定性的，重试无意义，直接回退
                #if DEBUG
                SoloistDebugLedger.shared.record(
                    SoloistLedgerEntry(file: generator.runtime.file,
                                       targetMeasures: targetMeasures,
                                       attempt: attempt,
                                       reason: reason))
                #endif
                return .fallbackToGrammar(reason: reason)

            case .solo(let notes):
                let boundsOK = SoloistBoundsGovernor.withinAbsoluteBounds(notes)
                let conserveOK = SoloistBoundsGovernor.durationConserved(
                    notes, targetMeasures: targetMeasures, measureLength: measureLength)
                let registerOK = SoloistBoundsGovernor.withinRegisterWindow(
                    notes, center: generator.registerCenter,
                    half: SoloistMelodyGenerator.halfWindow)
                if boundsOK && conserveOK && registerOK {
                    return .solo(notes)
                }
                // 意外越界/时值不守恒/跑出音域围栏：记账后有限重试
                #if DEBUG
                let why = !boundsOK ? "绝对音域越界"
                    : (!conserveOK ? "时值不守恒" : "跑出音域围栏")
                SoloistDebugLedger.shared.record(
                    SoloistLedgerEntry(file: generator.runtime.file,
                                       targetMeasures: targetMeasures,
                                       attempt: attempt,
                                       reason: why))
                #endif
            }
        }

        // 超过安全上限：明确回退 grammar，杜绝无界递归
        #if DEBUG
        SoloistDebugLedger.shared.record(
            SoloistLedgerEntry(file: generator.runtime.file,
                               targetMeasures: targetMeasures,
                               attempt: maxAttempts,
                               reason: "R9 安全上限，回退 grammar"))
        #endif
        return .fallbackToGrammar(reason: "R9 安全上限")
    }
}
