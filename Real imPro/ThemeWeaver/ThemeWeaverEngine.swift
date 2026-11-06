//
//  ThemeWeaverEngine.swift
//  RealimPro
//
//  ThemeWeaver M1：纯编织引擎（不接 grammar；空当窗先填整段休止占位，M2 再换 grammar）。
//  逐字对齐活路径 myGenerateSolo(ThemeWeaver.java:4890) → adjustTheme(:5257)
//  → transpose(:5436)/sideslip(:5529)/barLineShift(:5622)/adjustToFit(:5225)。
//
//  关键表示：内部全程使用稀疏 _SlotGrid（权威长度=grid.size，末音 rv 允许溢出网格，
//  等价 Java Part.size() 与 Unit.rhythmValue 相互独立），仅最终转密集 MelodyPart。
//
//  两条随机流：inst=实例 Random（用/不用主题、选主题、移调距离、侧滑档、错拍数），
//  bern=Notate.bernoulli（六变形命中、方向、全/半音），均可 setSeed 以做 L1 逐音复现。
//

import Foundation

/// M2 空当回落：给定全局起点/窗长/±6音域窗(已夹到硬音域,首窗nil)/首音参考，返回该窗 grammar 生成的密集旋律；
/// 由上层（M4 Strategy）注入，内部走 Grammar.run + GrammarNoteConverter.convert 增量重载。
/// 返回 nil 表示不可用→引擎退回整段休止（M1 行为）。
typealias ThemeGrammarFallback = (
    _ globalStart: Int,
    _ windowSlots: Int,
    _ pitchWindow: ClosedRange<Int>?,
    _ seedLastPitch: Int?
) -> MelodyPart?

struct ThemeWeaverEngine {

    private var inst: JavaLCG
    private var bern: JavaLCG
    let config: ThemeWeaverConfig
    /// M2 空当 grammar 回落；nil（默认）＝M1 整段休止占位，保证 M1 对拍不退化
    private let grammarFallback: ThemeGrammarFallback?
    /// M3：接缝削峰 connectSections 开关，默认关（关＝M2 行为，保 G4 回归）
    private let m3ConnectSections: Bool
    /// M3：整曲整流闭包（解耦：引擎不持有和弦）；拼完整曲、夹尾之后只调一次。默认 nil＝不整流
    private let wholeSongRectify: ((MelodyPart) -> MelodyPart)?
    private(set) var trace: [String] = []

    init(config: ThemeWeaverConfig = ThemeWeaverConfig(),
         instSeed: Int64, bernSeed: Int64,
         grammarFallback: ThemeGrammarFallback? = nil,
         m3ConnectSections: Bool = false,
         wholeSongRectify: ((MelodyPart) -> MelodyPart)? = nil) {
        self.config = config
        self.inst = JavaLCG(seed: instSeed)
        self.bern = JavaLCG(seed: bernSeed)
        self.grammarFallback = grammarFallback
        self.m3ConnectSections = m3ConnectSections
        self.wholeSongRectify = wholeSongRectify
    }

    // MARK: - 音域工具（网格层，对齐 lowestNote/highestNote/inRange）
    static func lowest(_ g: _SlotGrid) -> Int {
        var lo = 128
        for i in 0..<g.size where g.pitch[i] != nil && g.pitch[i] != PhysicalNote.restPitch {
            lo = min(lo, g.pitch[i]!)
        }
        return lo
    }
    static func highest(_ g: _SlotGrid) -> Int {
        var hi = 0
        for i in 0..<g.size where g.pitch[i] != nil && g.pitch[i] != PhysicalNote.restPitch {
            hi = max(hi, g.pitch[i]!)
        }
        return hi
    }
    func inRange(_ g: _SlotGrid) -> Bool {
        Self.highest(g) <= config.maxPitch && Self.lowest(g) >= config.minPitch
    }

    /// adjustToFit（L5225，确定性）：最低低于下限逐次 +1，最高高于上限逐次 -1，直到入域
    func adjustToFit(_ g: _SlotGrid) -> _SlotGrid {
        var cur = g
        while true {
            if Self.lowest(cur) < config.minPitch {
                MotifTransform.gShift(&cur, semitones: +1)
            } else if Self.highest(cur) > config.maxPitch {
                MotifTransform.gShift(&cur, semitones: -1)
            }
            if inRange(cur) { return cur }
        }
    }

    // MARK: - 主编织（myGenerateSolo 窗口循环；空当窗填休止）
    mutating func weave(themes: [(theme: MotifTheme, prob: ThemeUseProb)],
                        totalSlots: Int) -> MelodyPart {
        let window = config.windowSlots
        var solo = _SlotGrid()
        var i = 0
        var prevLastPitched: Int? = nil   // M2：上一段(prevSection)最后一个非休止音，用于 ±6 窗
        // M3：上一段网格，供 connectSections 改后按 Java L5036 重贴回 i-prev.size（prev 起点）
        var prevSectionGrid: _SlotGrid? = nil

        while i < totalSlots {
            var newGrid: _SlotGrid
            var inc = 0
            let randProbNT = inst.nextDouble()
            let useTheme = config.probUseTheme > randProbNT
            trace.append(String(format: "NT %.17g %d", randProbNT, useTheme ? 1 : 0))

            if useTheme {
                // ── 归一化 use，随机选主题（L4934-4954，默认最后一个）──
                let sumUse = themes.reduce(0.0) { $0 + $1.prob.use }
                let randUse = inst.nextDouble()
                var chosen = themes.count - 1
                var cum = 0.0
                for k in 0..<themes.count {
                    cum += themes[k].prob.use / sumUse
                    if cum > randUse { chosen = k; break }
                }
                trace.append(String(format: "USE %.17g %d", randUse, chosen))
                let chosenGrid = _SlotGrid(themes[chosen].theme.melody)
                let useProb = themes[chosen].prob
                let originalLength = chosenGrid.size

                newGrid = adjustTheme(chosenGrid, prob: useProb, originalLength: originalLength)

                if newGrid.size + i > totalSlots { break }      // 装不下曲尾→提前结束（L4963）
                inc = newGrid.size > window ? newGrid.size : window
            } else if let fb = grammarFallback {
                // ── M2 空当回落 grammar：全局子区间 [i,i+window] 独立 run（硬要求③）──
                // ±6 音域窗：以上一段尾音为中心，上下界分别夹进 ThemeWeaver 硬音域 60–82（硬要求①）
                var win: ClosedRange<Int>? = nil
                var seed: Int? = nil
                let hardLo = config.minPitch, hardHi = config.maxPitch
                if let pl = prevLastPitched {
                    let lo = max(hardLo, pl - 6)   // ±6 是“音高范围窗”，与 maxInterval 步长无关（硬要求②）
                    let hi = min(hardHi, pl + 6)
                    win = lo...hi
                    seed = (lo + hi) / 2          // D-M2-2(a)：首音取夹取后窗中心
                } else {
                    seed = (hardLo + hardHi) / 2  // 首窗无上一段：硬音域中心
                }
                if let mel = fb(i, window, win, seed) {
                    newGrid = _SlotGrid(mel)
                } else {
                    newGrid = _SlotGrid(); newGrid.appendUnit(PhysicalNote.restPitch, window)
                }
                inc = window
            } else {
                // ── 空当：无回落（M1）用整段休止占位 ──
                newGrid = _SlotGrid()
                newGrid.appendUnit(PhysicalNote.restPitch, window)
                inc = window
            }

            // 音域跨度超界保护（L5019-5026）
            let noteDiff = Self.highest(newGrid) - Self.lowest(newGrid)
            if noteDiff > config.maxPitch - config.minPitch { break }
            // 顺序①（逐段）：不在 60–82 则整体 adjustToFit 移进音域（Java L5028-5032）
            if !inRange(newGrid) { newGrid = adjustToFit(newGrid) }

            // 顺序②（逐接缝）：connectSections 削峰。改后的 prev 尾按 Java L5036
            // 重贴回 i-prevSection.size（prev 起点），而不是当前 i；next 在当前 i 贴。
            if m3ConnectSections, let prev = prevSectionGrid {
                let (movedPrev, movedNext) = SectionConnector.shifted(prev: prev, next: newGrid)
                solo.pasteSlots(movedPrev, at: i - prev.size)
                newGrid = movedNext
                trace.append("M3-CONNECT@\(i)")
            }

            // setSize 预扩 inc、在绝对 i 处 pasteSlots
            solo.setSize(solo.size + inc)
            solo.pasteSlots(newGrid, at: i)
            prevSectionGrid = newGrid
            // M2：记录本窗最后一个非休止音，作为下一空当窗的 ±6 中心
            for k in stride(from: newGrid.size - 1, through: 0, by: -1) {
                if let p = newGrid.pitch[k], p != PhysicalNote.restPitch { prevLastPitched = p; break }
            }
            i += inc
        }

        // 顺序③：拼完整曲先夹尾 setSize（Java L5045）
        solo.setSize(totalSlots)
        var result = solo.toMelodyPart()
        // 顺序④（整曲、只一次）：strongBeat 整流作用在拼好的整曲，不是每窗（Java L5048 整曲 Rectify 的 Swift .strongBeat 档）
        if let rectify = wholeSongRectify { result = rectify(result); trace.append("M3-RECTIFY-once") }
        return result
    }

    // MARK: - adjustTheme（L5257，固定顺序；flags 保留 SideSlip↔BarLineShift 耦合）
    mutating func adjustTheme(_ chosen: _SlotGrid, prob: ThemeUseProb, originalLength: Int) -> _SlotGrid {
        var adj = chosen
        var sideslipFlag = false
        var barlineshiftFlag = false
        var shiftForwardBy = 0

        // ① Transpose
        if bern.bernoulli(prob.transpose) {
            adj = transpose(adj, originalLength: originalLength)
            trace.append("TR 1")
        } else { trace.append("TR 0") }

        // ② Invert
        if bern.bernoulli(prob.invert) { adj = MotifTransform.gInverted(adj); trace.append("IV 1") }
        else { trace.append("IV 0") }

        // ③ Reverse
        if bern.bernoulli(prob.reverse) { adj = MotifTransform.gReversed(adj); trace.append("RV 1") }
        else { trace.append("RV 0") }

        // ④ Expand（仅命中时才再抽一次决定 ×3/×2；未命中只消耗外层这一次 bernoulli）
        if bern.bernoulli(prob.expand) {
            let by3 = bern.bernoulli(config.probExpandBy3)
            adj = MotifTransform.gExpanded(adj, by: by3 ? 3 : 2)
            trace.append("EX 1 \(by3 ? 1 : 0)")
        } else { trace.append("EX 0") }

        // ⑤ Side Slip
        if bern.bernoulli(prob.sideslip) {
            sideslipFlag = true
            var probs = [config.sideSlipHalf, config.sideSlipWhole, config.sideSlipThird]
            let s = probs.reduce(0, +)
            if s != 1.0 { probs = probs.map { $0 / s } }
            let rand = inst.nextDouble()
            var interval = 2
            var temp = 0.0
            for k in 0..<probs.count {
                temp += probs[k]
                if rand > temp { interval = k; break }       // 对齐 Java 原比较方向（L5555）
            }
            let mag = interval == 0 ? 1 : (interval == 1 ? 2 : 3)
            let up = bern.bernoulli(config.probSlideUp)
            adj = MotifTransform.gSideSlipped(adj, originalLength: originalLength,
                                              semitones: up ? +mag : -mag,
                                              priorBarLineShift: barlineshiftFlag,
                                              shiftForwardBy: shiftForwardBy)
            trace.append(String(format: "SS 1 %.17g %d %d", rand, interval, up ? 1 : 0))
        } else { trace.append("SS 0") }

        // ⑥ Bar Line Shift
        if bern.bernoulli(prob.barLineShift) {
            barlineshiftFlag = true
            let numBeats = Int(inst.nextInt(bound: 2)) + 1
            let forward = bern.bernoulli(config.probForwardShift)
            shiftForwardBy = config.shiftForwardByFinal * numBeats
            adj = MotifTransform.gBarLineShifted(adj, numBeats: numBeats,
                                                 baseShiftPerBeat: config.shiftForwardByFinal,
                                                 forward: forward,
                                                 priorSideSlip: sideslipFlag)
            trace.append("BL 1 \(numBeats) \(forward ? 1 : 0)")
        } else { trace.append("BL 0") }

        return adj
    }

    // MARK: - transpose（L5436，循环到落域；保留 Java 半音上行 *2 的 quirk）
    mutating func transpose(_ g: _SlotGrid, originalLength: Int) -> _SlotGrid {
        var cur = g
        while true {
            let maxTransposeDist = (config.maxPitch + config.minPitch) / 2
            if bern.bernoulli(config.probWholeToneTranspose) {
                let n = Int(inst.nextInt(bound: Int32(maxTransposeDist / 2)))
                let dirUp = bern.bernoulli(0.5)
                if !dirUp {
                    if Self.lowest(cur) - n * 2 >= config.minPitch {
                        var t = cur
                        if MotifTransform.gShift(&t, semitones: -n * 2) {
                            trace.append(String(format: "TRtry W n=%d up=0 fit=1", n)); return t
                        }
                    }
                } else {
                    if Self.highest(cur) + n * 2 <= config.maxPitch {
                        var t = cur
                        if MotifTransform.gShift(&t, semitones: +n * 2) {
                            trace.append(String(format: "TRtry W n=%d up=1 fit=1", n)); return t
                        }
                    }
                }
                trace.append(String(format: "TRtry W n=%d up=%d fit=0", n, dirUp ? 1 : 0))
            } else {
                let n = Int(inst.nextInt(bound: Int32(maxTransposeDist)))
                let dirUp = bern.bernoulli(0.5)
                if !dirUp {
                    if Self.lowest(cur) - n >= config.minPitch {
                        var t = cur
                        if MotifTransform.gShift(&t, semitones: -n) {
                            trace.append(String(format: "TRtry H n=%d up=0 fit=1", n)); return t
                        }
                    }
                } else {
                    // Java L5502 quirk：半音“上行”落域判断用 numHalfSteps*2，但实际只移 n 个半音
                    if Self.highest(cur) + n * 2 <= config.maxPitch {
                        var t = cur
                        if MotifTransform.gShift(&t, semitones: +n) {
                            trace.append(String(format: "TRtry H n=%d up=1 fit=1", n)); return t
                        }
                    }
                }
                trace.append(String(format: "TRtry H n=%d up=%d fit=0", n, dirUp ? 1 : 0))
            }
        }
    }
}
