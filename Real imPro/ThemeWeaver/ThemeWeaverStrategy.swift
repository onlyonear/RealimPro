//
//  ThemeWeaverStrategy.swift
//  RealimPro
//
//  ThemeWeaver M4：主题发展 Solo 生成器（独立 JazzImproStrategy）。
//  ── 启用方式（重要）──────────────────────────────────────────────
//  本类是与 GrammarStrategy 并排的【独立新生成器】。M4 阶段【不接 UI】，
//  全工程没有任何生产代码构造它（落地后用 grep 可证：仅本文件与 audit 探针引用），
//  因此“默认关”靠【不可达】保证——不使用 fatalError / 全局开关等会误伤正常路径的手段。
//  M5 才在点音符/粘贴入口显式构造；哼唱另立。
//  ── 数据来源 ────────────────────────────────────────────────────
//  · 空当回落：仅复用 M2 已验证的 ThemeGrammarFallbackGenerator（参数不改、选音不动）。
//  · 整曲整流：wholeSongRectify 闭包喂【roadmap.flattenRoadmap() 的全局和弦块】，
//    accumSlot 从选区起点（M4 只跑整曲＝曲首）；严禁使用空当窗内的局部和弦块。
//  · 拍号 beatsPerMeasure 由调用方按真实拍号注入（3/4 传 3），不在此写死 4。
//

import Foundation

final class ThemeWeaverStrategy: JazzImproStrategy {

    let name: String
    private let grammarFileName: String
    /// 真实拍号（每小节拍数），由调用方从曲目 timeSignature 注入；兼容 3/4 等
    private let beatsPerMeasure: Int
    private let slotsPerBeat = 120
    // 固定调试种子：M5 接入真实动机输入前的占位，保证端到端可复现
    private let instSeed: Int64
    private let bernSeed: Int64
    private var cachedGrammar: Grammar?
    // M5：UI 注入的真实动机；nil 时逐字回到 M4 的固定占位动机（保证 M4/V-1tap 行为不变）
    private let userMotifs: [MotifTheme]?

    init(grammarFileName: String,
         displayName: String,
         beatsPerMeasure: Int = 4,
         instSeed: Int64 = 42,
         bernSeed: Int64 = 7,
         userMotifs: [MotifTheme]? = nil) {
        self.grammarFileName = grammarFileName
        self.name = displayName
        self.beatsPerMeasure = beatsPerMeasure
        self.instSeed = instSeed
        self.bernSeed = bernSeed
        self.userMotifs = userMotifs
        // 与 GrammarStrategy 一致：走 App Bundle 加载 .rules（设备路径）
        self.cachedGrammar = Grammar(grammarFile: grammarFileName)
    }

    private func getGrammar() -> Grammar {
        if let g = cachedGrammar { return g }
        let g = Grammar(grammarFile: grammarFileName)
        cachedGrammar = g
        return g
    }

    // MARK: JazzImproStrategy
    func generateSolo(for roadmap: JazzRoadmap) -> [PhysicalNote] {
        if roadmap.keyMap.isEmpty { roadmap.buildKeyMap(beatsPerMeasure: beatsPerMeasure) }
        let grammar = getGrammar()
        grammar.slotsPerBeat = slotsPerBeat
        grammar.beatsPerMeasure = beatsPerMeasure

        // 全局线性和弦块 + 全局 slot 排程（整曲化：flatten，不按窗切局部和弦）
        let globalBlocks = roadmap.flattenRoadmap()
        var schedule: [(startSlot: Int, block: ChordBlock)] = []
        schedule.reserveCapacity(globalBlocks.count)
        var cursor = 0
        for b in globalBlocks {
            schedule.append((cursor, b))
            cursor += Int(Double(b.duration) * Double(slotsPerBeat))
        }
        let totalSlots = cursor

        // 空当回落：只接 M2 已验证参数（硬要求④，不改选音）
        let fallbackGen = ThemeGrammarFallbackGenerator(
            grammar: grammar,
            roadmap: roadmap,
            schedule: schedule,
            baseParameters: grammar.masterParameters,
            beatsPerMeasure: beatsPerMeasure
        )
        let fallback: ThemeGrammarFallback = { globalStart, windowSlots, pitchWindow, seedLastPitch in
            fallbackGen.make(globalStart: globalStart,
                             windowSlots: windowSlots,
                             pitchWindow: pitchWindow,
                             seedLastPitch: seedLastPitch)
        }

        // 整曲整流：全局和弦块、accumSlot 从整曲起点；beatsPerMeasure 用真实拍号（硬要求②③）
        let bpm = beatsPerMeasure
        let rectify: (MelodyPart) -> MelodyPart = { part in
            let out = LightPostProcessor.rectifyStrongBeats(
                part.notes,
                chordBlocks: globalBlocks,
                slotsPerBeat: 120,
                beatsPerMeasure: bpm
            )
            return MelodyPart(out)
        }

        // 出厂变形概率 1:1 抄 Java（全 0）
        let p = ThemeUseProb.javaDefault
        let themes: [(theme: MotifTheme, prob: ThemeUseProb)]
        if let user = userMotifs, !user.isEmpty {
            // M5：UI 注入动机（自动动机 / 点音符 / 粘贴）
            themes = user.map { ($0, p) }
        } else {
            // M4 固定占位动机（在 ThemeWeaver 硬音域 60–82 内）；nil 路径逐字保留
            func mp(_ seq: [(Int, Int)]) -> MelodyPart {
                MelodyPart(seq.map { PhysicalNote(midiPitch: $0.0, durationSlots: $0.1) })
            }
            themes = [
                (MotifTheme(name: "motifA", melody: mp([(60, 60), (64, 60), (67, 120), (65, 60), (62, 60)])), p),
                (MotifTheme(name: "motifB", melody: mp([(62, 60), (65, 60), (69, 60), (67, 180)])), p),
                (MotifTheme(name: "motifC", melody: mp([(67, 120), (71, 60), (72, 60), (69, 240)])), p)
            ]
        }

        var engine = ThemeWeaverEngine(
            config: ThemeWeaverConfig(),
            instSeed: instSeed,
            bernSeed: bernSeed,
            grammarFallback: fallback,
            m3ConnectSections: true,
            wholeSongRectify: rectify
        )
        let solo = engine.weave(themes: themes, totalSlots: totalSlots)
        return solo.notes
    }

    // MARK: 未来选区支持（M4 不启用；保留切片 helper，accumSlot 从选区起点对齐）
    /// 把全局 flatten 和弦块裁到选区起点：返回的 blocks[0] 即选区第一拍，
    /// 使 rectifyStrongBeats 内部 accumSlot=0 正好对应选区起点（而非曲首）。
    private static func blocks(forSelection selectionStartBeat: Double,
                               in global: [ChordBlock]) -> [ChordBlock] {
        var acc = 0.0
        var idx = 0
        while idx < global.count, acc + global[idx].duration <= selectionStartBeat {
            acc += global[idx].duration
            idx += 1
        }
        return Array(global[idx...])
    }
}
