//
//  RNNPostprocessors.swift
//  RealimPro
//
//  LSTM P0 —— 三个概率后处理器，口径对齐原版：
//    RectifyPostprocessor（按和弦 spell/color 清零非可用音；色彩由 provider 决定，默认 spell-only）
//    MergeRepeatedPostprocessor（把"重复同音"概率并入"延音"）
//    ForcePlayPostprocessor（长休止后强制下一拍吹音：清零休止/延音）
//

import Foundation

protocol RNNPostprocessor {
    func postprocess(_ probabilities: [Float]) -> [Float]
    func resetState()
}

/// 逐时间步提供 12 个 PC 是否可用（1=可用，0=不可用）。
/// harness 直接读 Java 导出的 spellpcs；App 端由现有和弦 spell/color 查询构造。
typealias RNNSpellProvider = (_ stepIndex: Int) -> [Float]

/// Rectify（RectifyPostprocessor.java）。
final class RNNRectify: RNNPostprocessor {
    private let lowBound: Int
    private let provider: RNNSpellProvider
    private var position = 0

    init(lowBound: Int, provider: @escaping RNNSpellProvider) {
        self.lowBound = lowBound
        self.provider = provider
    }

    func resetState() { position = 0 }

    /// 在生成开始时调用（对齐 rectifier.start）。
    func start() { position = 0 }

    func postprocess(_ probabilities: [Float]) -> [Float] {
        var probs = probabilities
        let allowed = provider(position)   // 12 PC
        let offset = lowBound              // Java: offset=lowBound
        for i in 0..<12 {
            let pc = (i + offset) % 12
            let isAllowed = allowed[pc] > 0.5
            if !isAllowed {
                var pidx = 2 + i
                while pidx < probs.count {
                    probs[pidx] = 0.0
                    pidx += 12
                }
            }
        }
        position += 10   // RectifyPostprocessor.java:76
        return probs
    }
}

/// MergeRepeated（MergeRepeatedPostprocessor.java）。
final class RNNMergeRepeated: RNNPostprocessor {
    private let lowBound: Int
    private var lastPlayedNote = -1

    init(lowBound: Int) {
        self.lowBound = lowBound
    }

    func resetState() { lastPlayedNote = -1 }

    func noteWasPlayed(_ note: Int) {
        if note != -2 {   // 非延音 = 新音（含休止 -1）
            lastPlayedNote = note
        }
    }

    func postprocess(_ probabilities: [Float]) -> [Float] {
        var probs = probabilities
        // 上一步是休止(-1)时不处理
        if lastPlayedNote != -1 {
            let repeatIndex = lastPlayedNote - lowBound + 2
            if repeatIndex >= 0 && repeatIndex < probs.count {
                let repeatProb = probs[repeatIndex]
                let sustainProb = probs[1]
                probs[repeatIndex] = 0.0
                probs[1] = repeatProb + sustainProb
            }
        }
        return probs
    }
}

/// ForcePlay（ForcePlayPostprocessor.java）。
final class RNNForcePlay: RNNPostprocessor {
    private var shouldForce = false

    func forcePlayNext() { shouldForce = true }
    func resetState() { shouldForce = false }

    func postprocess(_ probabilities: [Float]) -> [Float] {
        var probs = probabilities
        if shouldForce {
            probs[0] = 0.0
            probs[1] = 0.0
            shouldForce = false
        }
        return probs
    }
}
