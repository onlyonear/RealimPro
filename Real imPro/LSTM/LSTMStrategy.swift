//
//  LSTMStrategy.swift
//  RealimPro
//
//  LSTM P0 —— App 桥：把 Roadmap 转成网络帧，自由生成后解码为 PhysicalNote。
//
//  纪律（P0）：
//    · 默认关闭、不接 UI（不修改 ContentView / 不加顶栏）；仅 DEBUG 静态调试入口可调用；
//    · 色彩口径 spell-only（不沿用原版出厂含色彩）；色彩接入留待后续报批；
//    · 模型打包（bundle/ODR）属 P1；当前 Release 从 bundle 读，缺失即安全返回空；
//      DEBUG 额外支持从构建机绝对路径读取，便于端到端调试。
//

import Foundation

/// LSTM 功能总开关，默认关闭。P1 不接正式 UI，仅 DEBUG 调试入口可调用。
enum LSTMFeature {
    static var enabled = false
}

#if DEBUG
/// DEBUG-only：让生成管线改走 LSTM。默认 false；仅 DEBUG 编译，Release 不可达。
enum LSTMDebugSwitch {
    static var useLSTM = false
}
#endif

final class LSTMStrategy: JazzImproStrategy {
    let name = "LSTM Neural"

    // [LSTM P2] 模型名 + Rectify 色彩（默认 spell-only）
    private let modelName: String
    private let colorEnabled: Bool
    private let colorMode: ColorPaletteMode
    init(modelName: String = "combination", colorEnabled: Bool = false,
         colorMode: ColorPaletteMode = .conservative) {
        self.modelName = modelName
        self.colorEnabled = colorEnabled
        self.colorMode = colorMode
    }

    // beat 9 维的周期（时间步），来自 DataPartIO（Constants/RESOLUTION_SCALAR）
    private static let beatPeriods: [Int] = [48, 24, 12, 6, 3, 16, 8, 4, 2]

    func generateSolo(for roadmap: JazzRoadmap) -> [PhysicalNote] {
        let blocks = roadmap.flattenRoadmap()
        guard !blocks.isEmpty, let file = loadModel() else { return [] }

        var frames: [RNNProductNetwork.Frame] = []
        var allowedByStep: [[Float]] = []   // [LSTM P2] Rectify 允许音 = spell ∪（可选）色彩
        var globalStep = 0

        for block in blocks {
            let chord13 = Self.chordVector(block)
            let allowed = Self.absoluteAllowed(block, colorEnabled: colorEnabled, mode: colorMode)

            let slots = Int(block.duration * Double(JazzGuideToneEngine.slotsPerBeat))
            let nsteps = max(1, slots / 10)

            for k in 0..<nsteps {
                let gs = globalStep + k
                frames.append(RNNProductNetwork.Frame(beat: Self.beatVector(globalStep: gs), chord: chord13))
                allowedByStep.append(allowed)
            }
            globalStep += nsteps
        }

        // Rectify 复用 App 现有和弦 spell/color 查询结果（默认 spell-only；点亮 Color 才并色彩），不另造。
        // [贴 Java] 每次生成用系统随机源，等价 Java 两个无种子 new Random()：
        //   ① 抽样种子 = GenerativeProductModel 构造里的 rand（GenerativeProductModel.java:54）；
        //   ② 起始把位 = IntervalRelativeNoteEncoding.reset 里 low + random.nextInt(high-low)
        //      （IntervalRelativeNoteEncoding.java:51），范围 48..84。
        // 故每次点生成，抽样与起始把位都全新随机、结果不同。
        var seedGen = SystemRandomNumberGenerator()
        let randomSeed = seedGen.next()
        let initialRelpos = file.lowBound
            + Int(seedGen.next(upperBound: UInt64(file.highBound - file.lowBound)))
        let net = RNNProductNetwork(file: file, initialRelpos: initialRelpos, spellProvider: { slot in
            let row = slot / 10
            return (row >= 0 && row < allowedByStep.count) ? allowedByStep[row]
                                                          : [Float](repeating: 1, count: 12)
        }, seed: randomSeed)

        let tokens = net.generateTokens(frames: frames)
        let rnnNotes = RNNMelody.decode(tokens: tokens)
        return rnnNotes.map { PhysicalNote(midiPitch: $0.midiPitch, durationSlots: $0.durationSlots) }
    }

    // MARK: 13 维和弦（bass PC + bass 帧 12 维 spell，index0=1）
    private static func chordVector(_ block: ChordBlock) -> [Float] {
        let rootPC = block.chordRootPC()
        let bassPC = block.centerPC()
        let quality = ChordQuality(chordName: block.name)

        var type = [Float](repeating: 0, count: 12)
        for interval in quality.chordIntervals {   // spell-only，不含色彩
            var idx = (rootPC + interval - bassPC) % 12
            if idx < 0 { idx += 12 }
            type[idx] = 1
        }
        type[0] = 1
        return [Float(bassPC)] + type
    }

    /// Rectify 用：12 个【绝对 PC】是否允许。off=仅 spell（默认）；colorEnabled 时按 conservative/full 并色彩。
    private static func absoluteAllowed(_ block: ChordBlock, colorEnabled: Bool,
                                        mode: ColorPaletteMode) -> [Float] {
        let rootPC = block.chordRootPC()
        let quality = ChordQuality(chordName: block.name)
        var row = [Float](repeating: 0, count: 12)
        for interval in quality.chordIntervals {
            row[((rootPC + interval) % 12 + 12) % 12] = 1
        }
        if colorEnabled {
            for interval in quality.colorIntervals(for: block.name, palette: mode) {
                row[((rootPC + interval) % 12 + 12) % 12] = 1
            }
        }
        return row
    }

    // MARK: beat 9 维
    private static func beatVector(globalStep: Int) -> [Float] {
        var beat = [Float](repeating: 0, count: 9)
        for i in 0..<9 {
            if globalStep % beatPeriods[i] == 0 { beat[i] = 1 }
        }
        return beat
    }

    // MARK: 模型加载（bundle；DEBUG 构建机路径兜底）
    private func loadModel() -> RNNFile? {
        if let url = Bundle.main.url(forResource: modelName, withExtension: "rnn") {
            return try? RNNModelLoader.load(url: url)
        }
        #if DEBUG
        let devPath = "/Users/onlyonear/Desktop/Improlyze/audit_harness/lstm_feasibility_20260925/p0_impl/\(modelName).rnn"
        if FileManager.default.fileExists(atPath: devPath) {
            return try? RNNModelLoader.load(url: URL(fileURLWithPath: devPath))
        }
        #endif
        return nil
    }

    #if DEBUG
    /// 仅 DEBUG：端到端调试入口（不接 UI）。
    static func debugRun(roadmap: JazzRoadmap) -> [PhysicalNote] {
        return LSTMStrategy().generateSolo(for: roadmap)
    }
    #endif
}
