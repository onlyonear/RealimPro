//
//  JavaRoadmapAnalyzer.swift
//  RealimPro
//
//  独立「Java 对齐 Roadmap 链」总入口。
//  与现有 PostProcessorFull.analyze 并行、从同一 roadmap 派生、互不影响；现有 Swift 链一行不动。
//
//  J2 管线（忠实 Java RoadMap.process 铁序）：
//    flattenRoadmap → buildAnalysisChords → JLeaf
//    → 设备侧解析 My.dictionary 得规则（JavaBrickParser）
//    → 逐段静态 CYK（JavaCYKParser.parse）→ 拼接
//    → findLaunchers（圈链/单属 launcher，一次）
//    → JavaDiatonic.findKeys（反向 KeySpan；段尾强制开新段、approach 解决改写砖 mode）
//    → 产出逐和弦完整标签 + 聚合 JavaKeySpan（含终止式类型/砖名）
//  注意：不调用 findKeysV2，也不做现有链兜底压扁（PostProcessorFull:676-689）。
//

import Foundation

enum JavaRoadmapAnalyzer {

    /// 对同一 roadmap 跑 Java 对齐分析，产出独立 KeySpan 与逐和弦完整标签。
    /// - Parameters:
    ///   - roadmap: 与现有分析相同的输入 roadmap
    ///   - tonicPC: 歌曲显式主调（KeyParser.parseKey(...).tonicPC）
    ///   - mode: 歌曲调式（KeyParser.parseKey(...).mode）
    ///   - beatsPerMeasure: 每小节拍数（默认 4）
    static func analyze(roadmap: JazzRoadmap,
                        tonicPC: Int,
                        mode: JazzMode = .major,
                        beatsPerMeasure: Double = 4.0) -> JavaRoadmapResult {
        let songMode = mode == .minor ? "Minor" : "Major"
        let flat = roadmap.flattenRoadmap()
        guard !flat.isEmpty else {
            return JavaRoadmapResult(spans: [], chordLabels: [],
                                     tonicPC: tonicPC, songMode: songMode)
        }

        // 1. 分析和弦序列（rootPC/qualityClass/isSectionEnd）
        let chords = PostProcessorFull.buildAnalysisChords(from: flat)

        // 2. 建 JLeaf（与 headless j2verify 同口径）
        let leaves: [JavaCYKParser.JLeaf] = chords.map { c in
            let pc = JavaBrickParser.parseChord(c.name)
            let slots = Int64((c.duration * 120.0).rounded())
            return JavaCYKParser.JLeaf(idx: c.chordIdx, name: c.name, root: c.rootPC,
                                       family: pc.family, rawQuality: pc.rawQuality, dur: slots,
                                       isSectionEnd: c.isSectionEnd)
        }

        // 3. 内置 My.dictionary → 规则（设备侧静态字典，不在设备解析 CSV/权重）
        guard let rules = JavaBrickParser.loadBundledRules() else {
            return JavaRoadmapResult(spans: [], chordLabels: [],
                                     tonicPC: tonicPC, songMode: songMode)
        }

        // 4. 逐段静态 CYK → 拼接 → findLaunchers
        var blocks = JavaCYKParser.parse(leaves: leaves,
                                         binary: rules.binary, unary: rules.unary)
        blocks = JavaCYKParser.findLaunchers(blocks)

        // 5. findKeys（inout：段尾开新段、approach 解决改写砖自身 mode）
        let keySpans = JavaDiatonic.findKeys(&blocks)

        // 6. 逐和弦 beat 起点（来自 flat ChordBlock 时长）
        var beatStarts: [Double] = []
        beatStarts.reserveCapacity(chords.count)
        var beat = 0.0
        for cb in flat {
            beatStarts.append(beat)
            beat += cb.duration
        }
        let totalBeats = beat

        // 7. 逐和弦完整标签
        func topBlock(containing i: Int) -> JavaCYKParser.JTopBlock? {
            blocks.first { $0.startIdx <= i && i < $0.endIdx }
        }
        func span(containing i: Int) -> JavaDiatonic.Span? {
            keySpans.first { $0.startIdx <= i && i < $0.endIdx }
        }
        var chordLabels: [JavaChordLabel] = []
        chordLabels.reserveCapacity(chords.count)
        for i in 0..<chords.count {
            guard let sp = span(containing: i), let tb = topBlock(containing: i) else {
                continue
            }
            // [J3 呈现层] 砖/段首判定（只读结果，不影响算法）
            let isBrick: Bool
            let curBrickDashed: String?
            switch tb {
            case .brick(let n, _, _, _, _, _, _):
                isBrick = true; curBrickDashed = JavaBrickParser.dashed(n)
            case .chord:
                isBrick = false; curBrickDashed = nil
            }
            var prevBrickDashed: String?
            if i > 0, let ptb = topBlock(containing: i - 1) {
                switch ptb {
                case .brick(let pn, _, _, _, _, _, _):
                    prevBrickDashed = JavaBrickParser.dashed(pn)
                case .chord:
                    prevBrickDashed = nil
                }
            }
            let isBrickStart = isBrick && (curBrickDashed != prevBrickDashed)
            let isSpanStart = (i == sp.startIdx)
            let sBeat = beatStarts[i]
            let dBeat = chords[i].duration
            let lbl: JavaChordLabel
            switch tb {
            case .brick(let n, let t, let m, let k, _, _, _):
                lbl = JavaChordLabel(chordIdx: i, chordName: chords[i].name,
                                     finalKey: sp.key, finalMode: sp.mode,
                                     brickKey: k, brickMode: m, brickType: t,
                                     brickName: JavaBrickParser.dashed(n),
                                     startBeat: sBeat, durationBeats: dBeat,
                                     isSpanStart: isSpanStart, isBrick: isBrick,
                                     isBrickStart: isBrickStart)
            case .chord(let leaf):
                lbl = JavaChordLabel(chordIdx: i, chordName: chords[i].name,
                                     finalKey: sp.key, finalMode: sp.mode,
                                     brickKey: leaf.root, brickMode: leaf.mode,
                                     brickType: leaf.mode, brickName: leaf.name,
                                     startBeat: sBeat, durationBeats: dBeat,
                                     isSpanStart: isSpanStart, isBrick: false,
                                     isBrickStart: false)
            }
            chordLabels.append(lbl)
        }

        // 8. 以 findKeys 跨度为边界聚合 JavaKeySpan；代表砖取段首顶砖（J3 呈现可细化）
        var out: [JavaKeySpan] = []
        for sp in keySpans {
            let sBeat = beatStarts[sp.startIdx]
            let eBeat = sp.endIdx < chords.count ? beatStarts[sp.endIdx] : totalBeats
            var cadenceType: String?
            var brickName: String?
            if let tb = topBlock(containing: sp.startIdx) {
                switch tb {
                case .brick(let n, let t, _, _, _, _, _):
                    cadenceType = t
                    brickName = JavaBrickParser.dashed(n)
                case .chord:
                    cadenceType = nil
                    brickName = nil
                }
            }
            out.append(JavaKeySpan(rootPC: sp.key, mode: sp.mode,
                                   startBeat: sBeat, endBeat: eBeat,
                                   cadenceType: cadenceType, brickName: brickName))
        }

        return JavaRoadmapResult(spans: out, chordLabels: chordLabels,
                                 tonicPC: tonicPC, songMode: songMode)
    }
}
