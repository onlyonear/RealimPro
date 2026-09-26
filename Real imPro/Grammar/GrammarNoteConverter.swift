//
//  GrammarNoteConverter.swift
//  Improlyze
//
//  Grammar 音符转换器 - 把抽象音符转换成具体的 MIDI 音高
//  第一阶段：最简单的转换，和弦音选最近的
//

import Foundation

// P0-1: Trend池桥接 — GrammarStrategy赋值, selectPitch()消费
var _pendingTrendSegment: TrendSegment? = nil
// F3: 八度上下文桥接 — convert()每帧更新, getClosestPitch()消费
var _prevPrevPitchBridge: Int? = nil
// M5: expectancy multiplier bridge — convert() reads from grammar params, getClosestPitch() consumes
var _expectancyBridge: Double = 0.0
// 🔍 排查: 和弦切换日志去重
fileprivate var _lastLoggedChord: String = ""

/// 音符分类器+文法音符到MIDI音高转换器
class GrammarNoteConverter {

    // 记录方向偏好，避免来回跳
    private static var lastDirection: Int = 0  // 1=上行, -1=下行, 0=无
    private static var recentPitches: [Int] = []  // 最近用过的音，避免立刻回去
    
    // P0-4a: avoidRepeats 重复音概率数组 (Java pitchUsed[], 长度128, 初始全1.0)
    // 未使用音=1.0必接受, 刚使用音=1/512低概率接受, 每次选音前recalc逐步*=2恢复
    private static var _pitchUsed: [Double] = Array(repeating: 1.0, count: 128)
    
    // P0-4b: 文法参数缓存 (convert入口设置, selectPitchWithProbTable读取)
    private static var _grammarChordToneWeight: Double = 0.7
    private static var _grammarColorToneWeight: Double = 0.2
    private static var _grammarScaleToneWeight: Double = 0.1
    private static var _grammarChordToneDecay: Double = 0.0
    private static var _grammarLeapProb: Double = 0.01
    private static var _grammarMinInterval: Int = 0   // Java MIN_INTERVAL_DEFAULT
    private static var _grammarMaxInterval: Int = 9   // Java MAX_INTERVAL_DEFAULT
    private static var _grammarAvoidRepeats: Bool = true

    // MARK: - 性能优化: 和弦解析缓存 (P0)
    /// 缓存单个和弦的所有解析结果。缓存 key = chordName + 权重三元组。
    /// 所有字段均为纯函数结果，无随机数，缓存命中时输出与重算完全一致。
    /// 注: chordToneDecayRate 为 fillProbs 的死参数(传入但未使用)，不影响输出，故不纳入缓存 key。
    /// 注: 单槽缓存，当前 solo 生成串行执行，安全；若未来并发生成需改字典+锁。
    private struct ChordResolveCache {
        let chordName: String           // 已 trim 的干净和弦名
        let chordToneWeight: Double     // 权重三元组(缓存失效判断用)
        let colorToneWeight: Double
        let scaleToneWeight: Double
        let quality: ChordQuality       // ChordQuality.init 结果
        let rootPC: Int                 // getRootPC 结果
        let probs: [Double]             // fillProbs 结果 (12音级概率表)
        let chordPCSet: Set<Int>        // 和弦音音级集合 (checkNote 用)
        let colorPCSet: Set<Int>        // 色彩音音级集合
        let scalePCSet: Set<Int>        // 音阶音音级集合
    }
    private static var _chordResolveCache: ChordResolveCache?

    // MARK: - 性能优化: 音高数组缓存 (P1)
    /// 缓存单个和弦在指定音域内的 chord/color/scale 音高数组。
    /// 缓存 key = chordName + minPitch + maxPitch。
    /// 注: 单槽缓存，当前 solo 生成串行执行，安全；若未来并发生成需改字典+锁。
    private struct ChordToneCache {
        let chordName: String
        let minPitch: Int
        let maxPitch: Int
        let chordTones: [Int]
        let colorTones: [Int]
        let scaleTones: [Int]
    }
    private static var _chordToneCache: ChordToneCache?

    // MARK: - Garzone Triadic 状态缓存 (Outside Playing 引擎)
    private static let ROOT_STORAGE_NUMBER = 6
    private static var triadicRecentRoots = Array(repeating: -1, count: ROOT_STORAGE_NUMBER)
    private static var triadicRecentTypes = Array(repeating: 0, count: ROOT_STORAGE_NUMBER + 1) // 5=maj, 6=min, 7=dim, 8=aug
    private static var triadicRootCounter = 0
    private static var triadicLastInversion = 0
    // P0-修复4: adjustTriadicPitch 动态音域 (对齐 Java L1310-1324, ±12 半音 = 1 八度)
    private static var triadicMinPitch = 0
    private static var triadicMaxPitch = 127
    
    // MARK: - 转换
    
    static func convert(
        abstractMelody: [GrammarTerminal],
        roadmap: JazzRoadmap,
        grammarParameters: [String: Any],
        beatsPerMeasure: Int = 4
    ) -> [PhysicalNote] {
        var result: [PhysicalNote] = []
        
        // 🔍 对比验证: 终端类型分布统计 (递归 slope 内部 + 展平后携带 slopeMin/Max 的终端)
        #if DEBUG
        var ttCount: [String: Int] = ["C":0, "L":0, "S":0, "H":0, "A":0, "R":0, "X":0, "Y":0, "slope":0, "triadic":0, "scaleDegree":0, "slopeChild":0, "other":0]
        func countTT(_ t: GrammarTerminal) {
            ttCount["total"] = (ttCount["total"] ?? 0) + 1
            // 统计展平后携带 slopeMin/Max 的终端（原 slope 内部子音符）
            if t.slopeMin != nil || t.slopeMax != nil {
                ttCount["slopeChild"] = (ttCount["slopeChild"] ?? 0) + 1
            }
            switch t.type {
            case .chord: ttCount["C"] = (ttCount["C"] ?? 0) + 1
            case .color: ttCount["L"] = (ttCount["L"] ?? 0) + 1
            case .scale: ttCount["S"] = (ttCount["S"] ?? 0) + 1
            case .note: ttCount["H"] = (ttCount["H"] ?? 0) + 1
            case .approach: ttCount["A"] = (ttCount["A"] ?? 0) + 1
            case .rest: ttCount["R"] = (ttCount["R"] ?? 0) + 1
            case .arbitrary: ttCount["X"] = (ttCount["X"] ?? 0) + 1
            case .outside: ttCount["Y"] = (ttCount["Y"] ?? 0) + 1
            case .scaleDegree: ttCount["scaleDegree"] = (ttCount["scaleDegree"] ?? 0) + 1
            case .slope:
                ttCount["slope"] = (ttCount["slope"] ?? 0) + 1
                if let notes = t.slopeNotes { for n in notes { countTT(n) } }
            case .triadic: ttCount["triadic"] = (ttCount["triadic"] ?? 0) + 1
            }
        }
        for t in abstractMelody { countTT(t) }
        let ttTotal = ttCount["total"] ?? 0
        dprint("🔍[TERMINAL-DIST] total=\(ttTotal) | C(chord)=\(ttCount["C"] ?? 0)(\(ttTotal>0 ? (ttCount["C"] ?? 0)*100/ttTotal : 0)%) L(color)=\(ttCount["L"] ?? 0)(\(ttTotal>0 ? (ttCount["L"] ?? 0)*100/ttTotal : 0)%) S(scale)=\(ttCount["S"] ?? 0)(\(ttTotal>0 ? (ttCount["S"] ?? 0)*100/ttTotal : 0)%) H(note)=\(ttCount["H"] ?? 0)(\(ttTotal>0 ? (ttCount["H"] ?? 0)*100/ttTotal : 0)%) A(approach)=\(ttCount["A"] ?? 0)(\(ttTotal>0 ? (ttCount["A"] ?? 0)*100/ttTotal : 0)%) R(rest)=\(ttCount["R"] ?? 0)(\(ttTotal>0 ? (ttCount["R"] ?? 0)*100/ttTotal : 0)%) X(arbitrary)=\(ttCount["X"] ?? 0) Y(outside)=\(ttCount["Y"] ?? 0) slope=\(ttCount["slope"] ?? 0) slopeChild=\(ttCount["slopeChild"] ?? 0)(\(ttTotal>0 ? (ttCount["slopeChild"] ?? 0)*100/ttTotal : 0)%) triadic=\(ttCount["triadic"] ?? 0) scaleDegree=\(ttCount["scaleDegree"] ?? 0)(\(ttTotal>0 ? (ttCount["scaleDegree"] ?? 0)*100/ttTotal : 0)%)")
        #endif
        
        // 读取文法定义音域，适配 CharlieParker (min-pitch 58, max-pitch 82)
        let globalMinPitch = grammarParameters["min-pitch"] as? Int ?? 58
        let globalMaxPitch = grammarParameters["max-pitch"] as? Int ?? 82
        
        // P0-4b: 读取文法音高选择参数 (对齐 Java LickGen 构造器 L820-834)
        _grammarChordToneWeight = grammarParameters["chord-tone-weight"] as? Double ?? 0.7
        _grammarColorToneWeight = grammarParameters["color-tone-weight"] as? Double ?? 0.2
        _grammarScaleToneWeight = grammarParameters["scale-tone-weight"] as? Double ?? 0.1
        _grammarChordToneDecay = grammarParameters["chord-tone-decay"] as? Double ?? 0.0
        _grammarLeapProb = grammarParameters["leap-prob"] as? Double ?? 0.01
        // Java 默认 min-interval=0, max-interval=9; BillEvans 文法定义 max-interval=6
        _grammarMinInterval = grammarParameters["min-interval"] as? Int ?? 0
        _grammarMaxInterval = grammarParameters["max-interval"] as? Int ?? 9
        _grammarAvoidRepeats = grammarParameters["avoid-repeats"] as? Bool ?? true
        
        // P0-4a: 初始化 avoidRepeats 概率数组 (Java initPitchArray 全部置 1, L3627-3631)
        _pitchUsed = Array(repeating: 1.0, count: 128)

        // 性能优化: 重置和弦解析缓存，防止跨次生成污染
        _chordResolveCache = nil
        _chordToneCache = nil
        
        // M5: 读取expectancy参数，控制方向连续性偏好强度 (0=禁用, 默认0)
        _expectancyBridge = grammarParameters["expectancy-multiplier"] as? Double ?? 0.0
        
        // 展平 roadmap，获取和弦序列
        let chordBlocks = roadmap.flattenRoadmap()
        
        // 🔍 调试: 输出完整和弦序列，验证多和弦小节的 duration
        #if DEBUG
        dprint("🔍 [CHORD-BLOCKS] 共\(chordBlocks.count)个和弦:")
        var accumBeat = 0.0
        for (i, cb) in chordBlocks.enumerated() {
            dprint("  [\(i)] \(cb.name) duration=\(cb.duration)拍 (从第\(accumBeat)拍到第\(accumBeat + cb.duration)拍)")
            accumBeat += cb.duration
        }
        #endif
        
        let slotsPerBeat = JazzGuideToneEngine.slotsPerBeat
        let strongBeatCount = beatsPerMeasure <= 3 ? 1 : (beatsPerMeasure % 2 == 0 ? 2 : (beatsPerMeasure % 3 == 0 ? 3 : 1))
        let strongBeatInterval = beatsPerMeasure * slotsPerBeat / strongBeatCount
        func isOnOrStrongBeat(_ slot: Int) -> Bool {
            slot % slotsPerBeat == 0 || slot % strongBeatInterval == 0
        }
        
        var currentSlot = 0
        var lastPitch = 64  // 默认从 E4 开始
        var prevPrevPitch: Int? = nil  // 双音回溯: chooseNote 八度选择上下文
        lastDirection = 0   // 重置方向
        recentPitches = []  // 重置最近音
        
        // 重置 Triadic 引擎状态，防止跨次生成污染
        triadicRecentRoots = Array(repeating: -1, count: ROOT_STORAGE_NUMBER)
        triadicRecentTypes = Array(repeating: 0, count: ROOT_STORAGE_NUMBER + 1)
        triadicRootCounter = 0
        triadicLastInversion = 0
        triadicMinPitch = globalMinPitch
        triadicMaxPitch = globalMaxPitch
        
        var skipNext = false
        for (idx, terminal) in abstractMelody.enumerated() {
            if skipNext { skipNext = false; continue }
            if terminal.type == .approach {
                #if DEBUG
                dprint("【APPROACH-ARRIVAL】 slot=\(currentSlot) beat=\(currentSlot/120) idx=\(idx)")
                #endif
            }
            // 找到当前位置的和弦
            let currentChord = findChordAt(slot: currentSlot, chordBlocks: chordBlocks)
            
            // 🔍 排查日志: 和弦切换时打印基准音列表 (每个和弦只打一次)
            if currentSlot == 0 || currentChord != _lastLoggedChord {
                _lastLoggedChord = currentChord
                #if DEBUG
                dprint("🔍 [CHORD-SWITCH] slot=\(currentSlot) beat=\(Double(currentSlot)/120.0) chord=\(currentChord) terminal=\(terminal.type.rawValue)")
                #endif
                let tones = getChordTones(chordName: currentChord, minPitch: globalMinPitch, maxPitch: globalMaxPitch)
                logChordTones(currentChord, tones)
            }
            
            // ========== slope 特殊处理：一个终结符生成多个音符 ==========
            if terminal.type == .slope, let notes = terminal.slopeNotes,
               let minSlope = terminal.minSlope, let maxSlope = terminal.maxSlope {
                
                // 🔍 slope全链路追踪
                #if DEBUG
                dprint("【SLOPE-ENTER】 minSlope=\(minSlope) maxSlope=\(maxSlope) lastPitch=\(lastPitch) chord=\(currentChord) noteCount=\(notes.count)")
                #endif
                
                // slope 0 0 特殊情况：所有音强制同音，增加边界保护
                if minSlope == 0 && maxSlope == 0 {
                    // slope 0 0 特殊情况：所有音强制同音，增加边界保护
                    var fixedPitch = lastPitch
                    
                    // 核心修正：不取全局lastPitch，用本段第一个有效音符匹配和弦合法音高
                    if let firstRealNote = notes.first(where: { $0.type != .rest }) {
                        fixedPitch = selectPitch(
                            terminal: firstRealNote,
                            chordName: currentChord,
                            lastPitch: lastPitch,
                            minPitch: globalMinPitch,
                            maxPitch: globalMaxPitch
                        )
                    }
                    
                    // 自动钳位文法配置音域
                    if fixedPitch < globalMinPitch { fixedPitch = globalMinPitch }
                    if fixedPitch > globalMaxPitch { fixedPitch = globalMaxPitch }
                    
                    for innerNote in notes {
                        if innerNote.type == .rest {
                            let rest = PhysicalNote(midiPitch: -1, durationSlots: innerNote.actualDuration, terminalType: innerNote.type.rawValue)
                            result.append(rest)
                        } else {
                            let note = PhysicalNote(midiPitch: fixedPitch, durationSlots: innerNote.actualDuration, terminalType: innerNote.type.rawValue)
                            #if DEBUG
                            dprint("【SLOPE-FIXED】 type=\(innerNote.type.rawValue) fixedPitch=\(fixedPitch) slope=[0,0]")
                            #endif
                            result.append(note)
                            
                            // 连续同音不重复压入缓存，避免过早触发重复音惩罚
                            if recentPitches.last != fixedPitch {
                                recentPitches.append(fixedPitch)
                                if recentPitches.count > 3 {
                                    recentPitches.removeFirst()
                                }
                            }
                            prevPrevPitch = lastPitch  // 双音回溯
                            _prevPrevPitchBridge = prevPrevPitch  // F3: 同步桥接
                            lastPitch = fixedPitch
                        }
                        currentSlot += innerNote.actualDuration
                    }
                    continue
                }
                
                var i = 0
                while i < notes.count {
                    let innerNote = notes[i]
                    let innerChord = findChordAt(slot: currentSlot, chordBlocks: chordBlocks)
                    
                    if innerNote.type == .rest {
                        // 休止符
                        let rest = PhysicalNote(midiPitch: -1, durationSlots: innerNote.actualDuration, terminalType: innerNote.type.rawValue)
                        result.append(rest)
                        currentSlot += innerNote.actualDuration
                        i += 1
                    } else if innerNote.type == .approach {
                        // ========== APPROACH 特殊处理：预读下一个音符，反向接近 ==========
                        if i + 1 < notes.count {
                            // 有下一个音符：先确定目标音高，再反推 approach 音
                            let targetNote = notes[i + 1]
                            let targetChord = findChordAt(slot: currentSlot + innerNote.actualDuration, chordBlocks: chordBlocks)
                            
                            // 1. 先选目标音高（在 slope 范围内）
                            let targetPitch = selectSlopePitch(
                                terminal: targetNote,
                                chordName: targetChord,
                                lastPitch: lastPitch,
                                minSlope: minSlope,
                                maxSlope: maxSlope,
                                globalMinPitch: globalMinPitch,
                                globalMaxPitch: globalMaxPitch
                            )
                            
                            // 正拍/强拍 → 跳过趋近音，直接出和弦音
                            if isOnOrStrongBeat(currentSlot) {
                                let mergedDur = innerNote.actualDuration + targetNote.actualDuration
                                let mergedNote = PhysicalNote(midiPitch: targetPitch, durationSlots: mergedDur, terminalType: targetNote.type.rawValue)
                                result.append(mergedNote)
                                prevPrevPitch = lastPitch; _prevPrevPitchBridge = prevPrevPitch
                                lastDirection = targetPitch > lastPitch ? 1 : (targetPitch < lastPitch ? -1 : 0)
                                lastPitch = targetPitch; recentPitches.append(targetPitch)
                                if recentPitches.count > 3 { recentPitches.removeFirst() }
                                currentSlot += mergedDur
                                i += 2
                                continue
                            }
                            
                            // P0-4c: 趋近音方向判定 — 对齐 Java L2070-2103
                            // 前置防同音特判 → 零音程分支 → 正常分支
                            var approachPitch: Int
                            if targetPitch + 1 == lastPitch {
                                // 前置防同音特判: 目标音+1==上一音 → 趋近音=目标音-1
                                approachPitch = targetPitch - 1
                            } else if targetPitch - 1 == lastPitch {
                                // 前置防同音特判: 目标音-1==上一音 → 趋近音=目标音+1
                                approachPitch = targetPitch + 1
                            } else if minSlope == 0 || maxSlope == 0 {
                                // 零音程 slope 特殊分支 (Java L2080-2089: 两个独立if)
                                if maxSlope > 0 {
                                    approachPitch = targetPitch - 1  // 上界>0 → 下行半音趋近
                                } else if minSlope < 0 {
                                    approachPitch = targetPitch + 1  // 下界<0 → 上行半音趋近
                                } else {
                                    // slope 0 0: 原版不设置pitch(边缘bug), 此处刻意修正为默认下行
                                    approachPitch = targetPitch - 1
                                }
                            } else if minSlope > 0 {
                                // 正常分支: 上行slope → 下行趋近
                                approachPitch = targetPitch - 1
                            } else if maxSlope < 0 {
                                // 正常分支: 下行slope → 上行趋近
                                approachPitch = targetPitch + 1
                            } else {
                                // 默认下行
                                approachPitch = targetPitch - 1
                            }
                            // 音域钳位 (用文法配置音域, 而非硬编码36-96)
                            approachPitch = max(globalMinPitch, min(globalMaxPitch, approachPitch))
                            
                            let appInterval = abs(approachPitch - targetPitch)
                            let appWarning = appInterval > 2 ? "⚠️ ANOMALY" : "  OK"
                            #if DEBUG
                            dprint("【APPROACH-DIAG】\(appWarning) chord=\(targetChord) target=\(targetPitch) app=\(approachPitch) intv=\(appInterval) slope=[\(minSlope),\(maxSlope)]")
                            #endif
                            
                            // 4. 添加 approach 音符
                            let approachNote = PhysicalNote(midiPitch: approachPitch, durationSlots: innerNote.actualDuration, terminalType: innerNote.type.rawValue)
                            #if DEBUG
                            dprint("【SLOPE-APPROACH】 pitch=\(approachPitch) targetPitch=\(targetPitch) slope=[\(minSlope),\(maxSlope)]")
                            #endif
                            result.append(approachNote)
                            
                            // 更新方向和最近音（approach 音）
                            if approachPitch > lastPitch {
                                lastDirection = 1
                            } else if approachPitch < lastPitch {
                                lastDirection = -1
                            }
                            recentPitches.append(approachPitch)
                            if recentPitches.count > 3 {
                                recentPitches.removeFirst()
                            }
                            
                            currentSlot += innerNote.actualDuration
                            
                            // 5. 添加目标音符
                            let targetPhysicalNote = PhysicalNote(midiPitch: targetPitch, durationSlots: targetNote.actualDuration, terminalType: targetNote.type.rawValue)
                            result.append(targetPhysicalNote)
                            
                            // 更新方向和最近音（目标音）
                            if targetPitch > approachPitch {
                                lastDirection = 1
                            } else if targetPitch < approachPitch {
                                lastDirection = -1
                            }
                            recentPitches.append(targetPitch)
                            if recentPitches.count > 3 {
                                recentPitches.removeFirst()
                            }
                            
                            lastPitch = targetPitch
                            currentSlot += targetNote.actualDuration
                            
                            // 跳两步（approach + target）
                            i += 2
                        } else {
                            // 没有下一个音符：无法构成趋近音→目标音关系，降级为音阶音处理
                            // 修复：不标记为 "A"(趋近音)，改为 "S"(音阶/色彩音)，避免显示层误标蓝
                            let scalePitches = getScaleTones(chordName: innerChord, minPitch: globalMinPitch, maxPitch: globalMaxPitch)
                            let pitch = scalePitches.randomElement() ?? lastPitch
                            
                            let note = PhysicalNote(midiPitch: pitch, durationSlots: innerNote.actualDuration, terminalType: "S")
                            result.append(note)
                            
                            // 更新方向和最近音
                            if pitch > lastPitch {
                                lastDirection = 1
                            } else if pitch < lastPitch {
                                lastDirection = -1
                            }
                            recentPitches.append(pitch)
                            if recentPitches.count > 3 {
                                recentPitches.removeFirst()
                            }
                            lastPitch = pitch
                            
                            currentSlot += innerNote.actualDuration
                            i += 1
                        }
                        // ========== APPROACH 处理结束 ==========
                    } else {
                        // 普通音符：在 [lastPitch + minSlope, lastPitch + maxSlope] 范围内选音高
                        let pitch = selectSlopePitch(
                            terminal: innerNote,
                            chordName: innerChord,
                            lastPitch: lastPitch,
                            minSlope: minSlope,
                            maxSlope: maxSlope,
                            globalMinPitch: globalMinPitch,
                            globalMaxPitch: globalMaxPitch
                        )
                        #if DEBUG
                        dprint("【SLOPE-NOTE】 type=\(innerNote.type.rawValue) chord=\(innerChord) pitch=\(pitch) slope=[\(minSlope),\(maxSlope)] lastPitch=\(lastPitch)")
                        #endif
                        
                        let note = PhysicalNote(midiPitch: pitch, durationSlots: innerNote.actualDuration, terminalType: innerNote.type.rawValue)
                        result.append(note)
                        
                        // 更新方向和最近音
                        if pitch > lastPitch {
                            lastDirection = 1
                        } else if pitch < lastPitch {
                            lastDirection = -1
                        }
                        recentPitches.append(pitch)
                        if recentPitches.count > 3 {
                            recentPitches.removeFirst()
                        }
                        lastPitch = pitch
                        
                        // 大跳后自动反向（爵士即兴规则）
                        if abs(pitch - (result.isEmpty ? 64 : result.last?.midiPitch ?? 64)) >= 6 {
                            lastDirection = -lastDirection
                        }
                        
                        currentSlot += innerNote.actualDuration
                        i += 1
                    }
                }
                
                continue  // slope 处理完，跳过后面的普通处理
            }
            // ========== slope 处理结束 ==========
            // ========== triadic 特殊处理：按时长循环生成多个三和弦 (对齐 Java L2175-2252) ==========
            if terminal.type == .triadic {
                // P0-修复5: 按总时长循环生成多个三和弦, 每个3音, 每音固定 8 分音符 = 60 slots
                // (原版 whatLength 硬编码 "8", GrammarTerminal 不携带 whatLength 参数)
                let slotsPerEighth = 60
                let totalEighths = terminal.actualDuration / slotsPerEighth
                let numTriads = totalEighths / 3
                let remainder = totalEighths % 3

                var currentBase = lastPitch
                for _ in 0..<numTriads {
                    let triadPitches = getTriadicTones(
                        referencePitch: currentBase,
                        minPitch: globalMinPitch,
                        maxPitch: globalMaxPitch
                    )
                    for pitch in triadPitches {
                        result.append(PhysicalNote(midiPitch: pitch, durationSlots: slotsPerEighth, terminalType: "T"))
                        // 更新走向、最近音缓存
                        if pitch > lastPitch { lastDirection = 1 }
                        else if pitch < lastPitch { lastDirection = -1 }
                        recentPitches.append(pitch)
                        if recentPitches.count > 3 { recentPitches.removeFirst() }
                        prevPrevPitch = lastPitch
                        _prevPrevPitchBridge = prevPrevPitch
                        lastPitch = pitch
                        currentBase = pitch
                    }
                }
                // remainder: 0-2 音 (对齐 Java L2238-2247)
                if remainder > 0 {
                    let triadPitches = getTriadicTones(
                        referencePitch: currentBase,
                        minPitch: globalMinPitch,
                        maxPitch: globalMaxPitch
                    )
                    for i in 0..<remainder {
                        let pitch = triadPitches[i]
                        result.append(PhysicalNote(midiPitch: pitch, durationSlots: slotsPerEighth, terminalType: "T"))
                        if pitch > lastPitch { lastDirection = 1 }
                        else if pitch < lastPitch { lastDirection = -1 }
                        recentPitches.append(pitch)
                        if recentPitches.count > 3 { recentPitches.removeFirst() }
                        prevPrevPitch = lastPitch
                        _prevPrevPitchBridge = prevPrevPitch
                        lastPitch = pitch
                    }
                }
                // 时间轴一次性推进全部时长，跳过下方单音生成逻辑
                currentSlot += terminal.actualDuration
                continue
            }
            // ========== triadic 处理结束 ==========
            
            // 诊断: 记录所有趋近音终端的到达
            if terminal.type == .approach {
                #if DEBUG
                dprint("【APPROACH-TERMINAL】 slot=\(currentSlot) beat=\(currentSlot/120) chord=\(currentChord) idx=\(idx)")
                #endif
            }
            
            // ========== Path B 趋近音预读配对 ==========
            if terminal.type == .approach, idx + 1 < abstractMelody.count {
                #if DEBUG
                dprint("【PATHB-APPROACH】 slot=\(currentSlot) beat=\(currentSlot/120) chord=\(currentChord)")
                #endif
                let next = abstractMelody[idx + 1]
                if next.type != .slope && next.type != .triadic {
                    let targetSlot = currentSlot + terminal.actualDuration
                    let targetChord = findChordAt(slot: targetSlot, chordBlocks: chordBlocks)
                    
                    // P0-slope-approach: 目标音选择分支化
                    // slope 内展平的 approach: 目标音在 slope 范围内选音, 类型用 next.type (对齐 Java L2048/2052-2060)
                    // 普通 approach: 全局范围选和弦音 (对齐 Java L2295: nextType = CHORD)
                    let targetPitch: Int
                    if let smin = terminal.slopeMin, let smax = terminal.slopeMax {
                        // slope 内 approach: 目标音在 slope 音程范围内, 类型 = next.type
                        let slopeTarget = GrammarTerminal(
                            type: next.type,
                            durationSlots: next.durationSlots,
                            isDotted: next.isDotted,
                            tuplet: next.tuplet,
                            slopeMin: smin, slopeMax: smax
                        )
                        targetPitch = selectSlopePitch(
                            terminal: slopeTarget, chordName: targetChord,
                            lastPitch: lastPitch, minSlope: smin, maxSlope: smax,
                            globalMinPitch: globalMinPitch, globalMaxPitch: globalMaxPitch
                        )
                    } else {
                        // 普通 approach: 强制目标音为和弦音 (对齐 Java L2295 "nextType = CHORD")
                        let chordNext = GrammarTerminal(
                            type: .chord,
                            durationSlots: next.durationSlots,
                            isDotted: next.isDotted,
                            tuplet: next.tuplet
                        )
                        targetPitch = selectPitch(terminal: chordNext, chordName: targetChord,
                            lastPitch: lastPitch, minPitch: globalMinPitch, maxPitch: globalMaxPitch)
                    }
                    
                    // 正拍/强拍 → 跳过趋近音，直接出和弦音
                    if isOnOrStrongBeat(currentSlot) {
                        let mergedDur = terminal.actualDuration + next.actualDuration
                        result.append(PhysicalNote(midiPitch: targetPitch, durationSlots: mergedDur,
                                                   terminalType: "C"))
                        prevPrevPitch = lastPitch; _prevPrevPitchBridge = prevPrevPitch
                        lastDirection = targetPitch > lastPitch ? 1 : (targetPitch < lastPitch ? -1 : 0)
                        lastPitch = targetPitch; recentPitches.append(targetPitch)
                        if recentPitches.count > 3 { recentPitches.removeFirst() }
                        currentSlot += mergedDur
                        skipNext = true
                        continue
                    }
                    
                    // P0-slope-approach: 趋近音方向分支化
                    // slope 内展平的 approach: 方向由 slope 走向决定 (对齐 Java L2070-2103)
                    // 普通 approach: 50% 随机上下半音 (对齐 Java L2322-2345)
                    let appPitch: Int
                    if let smin = terminal.slopeMin, let smax = terminal.slopeMax {
                        appPitch = deriveSlopeApproachPitch(
                            targetPitch: targetPitch, minSlope: smin, maxSlope: smax,
                            lastPitch: lastPitch, minPitch: globalMinPitch, maxPitch: globalMaxPitch
                        )
                    } else {
                        appPitch = deriveApproachPitch(targetPitch: targetPitch, chordName: targetChord,
                                                        lastPitch: lastPitch, preferBelow: targetPitch >= lastPitch)
                    }
                    
                    result.append(PhysicalNote(midiPitch: appPitch, durationSlots: terminal.actualDuration,
                                               terminalType: terminal.type.rawValue))
                    prevPrevPitch = lastPitch; _prevPrevPitchBridge = prevPrevPitch
                    lastDirection = appPitch > lastPitch ? 1 : (appPitch < lastPitch ? -1 : 0)
                    lastPitch = appPitch; recentPitches.append(appPitch)
                    if recentPitches.count > 3 { recentPitches.removeFirst() }
                    currentSlot += terminal.actualDuration
                    
                    result.append(PhysicalNote(midiPitch: targetPitch, durationSlots: next.actualDuration,
                                               terminalType: "C"))
                    prevPrevPitch = appPitch; _prevPrevPitchBridge = prevPrevPitch
                    lastDirection = targetPitch > appPitch ? 1 : (targetPitch < appPitch ? -1 : 0)
                    lastPitch = targetPitch; recentPitches.append(targetPitch)
                    if recentPitches.count > 3 { recentPitches.removeFirst() }
                    currentSlot += next.actualDuration
                    
                    skipNext = true
                    continue
                }
            }
            // ========== Path B 趋近音预读结束 ==========
            // 根据终结符类型选择音高
            // 🌟 展平后 slope 子音符：携带 slopeMin/slopeMax，走 slope 选音路径
            let pitch: Int
            // approach fallback 正拍检查: Path B 未触发时(无下一音或下一音是 slope/triadic),
            // 正拍上用和弦音替代, 不生成趋近音 (用户偏好: 趋近音不在正拍出现)
            if terminal.type == .approach && isOnOrStrongBeat(currentSlot) {
                let chordTerminal = GrammarTerminal(
                    type: .chord,
                    durationSlots: terminal.durationSlots,
                    isDotted: terminal.isDotted,
                    tuplet: terminal.tuplet
                )
                pitch = selectPitchWithProbTable(
                    terminal: chordTerminal,
                    chordName: currentChord,
                    lastPitch: lastPitch,
                    minPitch: globalMinPitch,
                    maxPitch: globalMaxPitch
                )
            } else if let smin = terminal.slopeMin, let smax = terminal.slopeMax {
                pitch = selectSlopePitch(
                    terminal: terminal,
                    chordName: currentChord,
                    lastPitch: lastPitch,
                    minSlope: smin,
                    maxSlope: smax,
                    globalMinPitch: globalMinPitch,
                    globalMaxPitch: globalMaxPitch
                )
            } else {
                pitch = selectPitch(
                    terminal: terminal,
                    chordName: currentChord,
                    lastPitch: lastPitch,
                    minPitch: globalMinPitch,
                    maxPitch: globalMaxPitch
                )
            }
            // 🔍 排查日志: 音高选择结果
            let pc = ((pitch % 12) + 12) % 12
            let oct = (pitch / 12) - 1
            let nn = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
            //dprint("【音高选择过程】 和弦=\(currentChord) terminalType=\(terminal.type.rawValue)(\(terminal.type)) 候选范围=[\(globalMinPitch)-\(globalMaxPitch)] → 选中=\(nn[pc])\(oct)(midi\(pitch)) lastPitch=\(lastPitch)")
            
            // 创建物理音符
            if terminal.type != .rest {
                let note = PhysicalNote(
                    midiPitch: pitch,
                    durationSlots: terminal.actualDuration,
                    terminalType: terminal.type.rawValue
                )
                // 🔍 排查日志: PhysicalNote创建
                //dprint("【PhysicalNote创建】 midi=\(pitch) 音名=\(nn[pc])\(oct) 时值=\(terminal.actualDuration)slots terminalType=\(terminal.type.rawValue)")
                result.append(note)
                
                // 更新方向和最近音
                if pitch > lastPitch {
                    lastDirection = 1
                } else if pitch < lastPitch {
                    lastDirection = -1
                }
                recentPitches.append(pitch)
                // 只保留最近 3 个音
                if recentPitches.count > 3 {
                    recentPitches.removeFirst()
                }
                prevPrevPitch = lastPitch  // 双音回溯: 记录前前音高
                _prevPrevPitchBridge = prevPrevPitch  // F3: 同步桥接
                lastPitch = pitch
            } else {
                // 休止符，midiPitch = -1 表示休止
                let rest = PhysicalNote(
                    midiPitch: -1,
                    durationSlots: terminal.actualDuration,
                    terminalType: terminal.type.rawValue
                )
                result.append(rest)
            }
            
            currentSlot += terminal.actualDuration
        }

        // P1-3~P1-6: 后置装饰处理 — 已禁用
        // 逻辑: Approach音/切分/Bebop经过音由文法文件自身规则控制
        // 全局强制执行会导致Chord Tone等简单文法也被加上装饰, 丧失层次感
        // 如需按需启用新风格, 可回退至 enableApproachNotes/enableSyncopation 开关
        //
        // result = insertApproaches(result, ...)    // P1-3
        // result = Syncopation.apply(notes:...)     // P1-5

        // 诊断: 超低音排查 — 打印最终音符音高范围
        let allMidi = result.compactMap { $0.midiPitch >= 0 ? $0.midiPitch : nil }
        if !allMidi.isEmpty {
            //dprint("=== 最终音符音高范围 ===")
            //dprint("最小MIDI: \(allMidi.min() ?? 0), 最大MIDI: \(allMidi.max() ?? 0)")
            //dprint("低于48的超低音数量: \(allMidi.filter { $0 < 48 }.count)")
            if let minPitch = allMidi.min() {
                //dprint("最低音MIDI: \(minPitch)")
            }
        }

        // post-scan: 检测趋近音与下一音间距异常
        var paPitch: Int? = nil
        for note in result {
            if note.terminalType == "A" {
                paPitch = note.midiPitch
            } else if note.midiPitch >= 0, let pa = paPitch {
                let gap = abs(note.midiPitch - pa)
                if gap > 2 {
                    #if DEBUG
                    dprint("⚠️ [APPROACH-GAP] app=\(pa) next=\(note.midiPitch) gap=\(gap) nextType=\(note.terminalType)")
                    #endif
                }
                paPitch = nil
            }
        }
        
        // avoidRepeats: rest合并 + 同音合并，对齐 Java LickGen.addNote()
        #if DEBUG
        dprint("  [MERGE-PASS] result count=\(result.count)")
        #endif
        var merged: [PhysicalNote] = []
        for note in result {
            guard let last = merged.last else { merged.append(note); continue }
            if note.terminalType == "R", last.terminalType == "R" {
                merged[merged.count - 1] = PhysicalNote(midiPitch: -1,
                    durationSlots: last.durationSlots + note.durationSlots, tuplet: last.tuplet, terminalType: "R")
            } else if note.terminalType != "R", last.terminalType != "R", note.midiPitch == last.midiPitch {
                merged[merged.count - 1] = PhysicalNote(midiPitch: last.midiPitch,
                    durationSlots: last.durationSlots + note.durationSlots, tuplet: last.tuplet, terminalType: last.terminalType)
                #if DEBUG
                dprint("  [MERGE] pitch=\(last.midiPitch) dur=\(last.durationSlots)+\(note.durationSlots) lastType=\(last.terminalType ?? "nil") nowType=\(note.terminalType ?? "nil")")
                #endif
            } else {
                if note.terminalType != "R", last.terminalType != "R", note.midiPitch == last.midiPitch {
                    #if DEBUG
                    dprint("❌ [MERGE-FAIL] samePitch notMerged! last=\(last.midiPitch)(\(last.terminalType ?? "nil")) dur=\(last.durationSlots) now=\(note.midiPitch)(\(note.terminalType ?? "nil")) dur=\(note.durationSlots)")
                    #endif
                }
                merged.append(note)
            }
        }
        result = merged

        // slotMap 一次性构建，两种检测共用
        var slotMap: [Int] = []
        var s = 0
        for note in result { slotMap.append(s); s += note.durationSlots }

        // === 检测 1: 4-note window ===
        if result.count >= 8 {
            var i = 0
            while i + 7 < result.count {
                let seg1 = Array(result[i..<i+4]).map { $0.midiPitch }
                let seg2 = Array(result[i+4..<i+8]).map { $0.midiPitch }
                if seg1.allSatisfy({ $0 >= 0 }), seg2.allSatisfy({ $0 >= 0 }), seg1 == seg2 {
                    let prev = result[i+4].midiPitch, next = result[i+6].midiPitch
                    let orig = result[i+5].midiPitch
                    let chord = findChordAt(slot: slotMap[i+5], chordBlocks: chordBlocks)
                    let tones = getChordTones(chordName: chord, minPitch: globalMinPitch, maxPitch: globalMaxPitch)
                    var cand = tones.filter { $0 != orig && abs($0 - prev) <= 6 && abs($0 - next) <= 6 }
                    let dir = (next + prev) / 2
                    cand.sort { a, b in
                        if dir >= orig {
                            let u = a > orig, v = b > orig
                            if u != v { return u }; return u ? a < b : a > b
                        } else {
                            let u = a < orig, v = b < orig
                            if u != v { return u }; return u ? a > b : a < b
                        }
                    }
                    if let rep = cand.first {
                        result[i+5] = PhysicalNote(midiPitch: rep, durationSlots: result[i+5].durationSlots,
                                                    terminalType: result[i+5].terminalType)
                    }
                }
                i += 4
            }
        }

        // === 检测 2: 3+ consecutive 2-note groups ===
        var j = 0
        while j + 6 < result.count {
            let a = result[j].midiPitch, b = result[j+1].midiPitch
            guard a >= 0, b >= 0, a != b else { j += 1; continue }
            var run = 2
            while j + run*2 + 1 < result.count,
                  result[j + run*2].midiPitch == a,
                  result[j + run*2 + 1].midiPitch == b { run += 1 }
            if run >= 3 {
                let t = j + 5
                let prev = result[t-1].midiPitch, next = result[t+1].midiPitch
                let orig = result[t].midiPitch
                let chord = findChordAt(slot: slotMap[t], chordBlocks: chordBlocks)
                let tones = getChordTones(chordName: chord, minPitch: globalMinPitch, maxPitch: globalMaxPitch)
                var cand = tones.filter { $0 != orig && abs($0 - prev) <= 6 && abs($0 - next) <= 6 }
                let dir = (next + prev) / 2
                cand.sort { a, b in
                    if dir >= orig {
                        let u = a > orig, v = b > orig
                        if u != v { return u }; return u ? a < b : a > b
                    } else {
                        let u = a < orig, v = b < orig
                        if u != v { return u }; return u ? a > b : a < b
                    }
                }
                if let rep = cand.first {
                    result[t] = PhysicalNote(midiPitch: rep, durationSlots: result[t].durationSlots,
                                              terminalType: result[t].terminalType)
                }
                j += run * 2
            } else { j += 1 }
        }

        // 诊断: 扫描所有标记为 "A" 的音符（全量累计slot）
        var scanSlot = 0
        for note in result {
            if note.terminalType == "A" {
                #if DEBUG
                dprint("⚠️ [POST-SCAN-A] slot=\(scanSlot) beat=\(scanSlot/120) pitch=\(note.midiPitch) dur=\(note.durationSlots)")
                #endif
            }
            scanSlot += note.durationSlots
        }

        return result
    }

    // MARK: - P1-3 Approach音插入

    /// 30%概率为强拍和弦音插入趋近装饰, 保持总时值不变
    private static func insertApproaches(_ notes: [PhysicalNote],
                                          globalMinPitch: Int, globalMaxPitch: Int) -> [PhysicalNote] {
        var result: [PhysicalNote] = []
        let beatSlots = 120  // 四分音符slots
        for note in notes {
            // 跳过休止符和短音 (必须≥八分音符30slots, 实际上≥60)
            guard note.midiPitch >= 0, note.durationSlots >= 60 else {
                result.append(note); continue
            }
            // 30%概率, 只加强拍上的音 (slot能被beatSlots整除)
            guard Double.random(in: 0...1) < 0.3,
                  result.count % beatSlots < 4 else {  // 每个四分音符位置为强拍近似
                result.append(note); continue
            }

            let type = ApproachType.random()
            let approachPitches = type.generateApproachNotes(targetPitch: note.midiPitch)
            guard !approachPitches.isEmpty else { result.append(note); continue }

            // 时值分配
            let approachCount = approachPitches.count
            let graceSlot: Int
            let remainingSlots: Int
            switch approachCount {
            case 1:   graceSlot = 30; remainingSlots = note.durationSlots - graceSlot
            case 2:   graceSlot = 30; remainingSlots = note.durationSlots - graceSlot * 2
            default:  graceSlot = 30; remainingSlots = note.durationSlots - graceSlot
            }
            guard remainingSlots >= 30 else { result.append(note); continue }

            // 插入趋近音 (每个30slots)
            for ap in approachPitches {
                var pitch = ap
                while pitch < globalMinPitch { pitch += 12 }
                while pitch > globalMaxPitch { pitch -= 12 }
                result.append(PhysicalNote(midiPitch: pitch, durationSlots: graceSlot, terminalType: nil))
            }
            // 目标音保留剩余时值
            var targetPitch = note.midiPitch
            while targetPitch < globalMinPitch { targetPitch += 12 }
            while targetPitch > globalMaxPitch { targetPitch -= 12 }
            result.append(PhysicalNote(midiPitch: targetPitch, durationSlots: remainingSlots, terminalType: nil))
        }
        // post-scan: 检测趋近音与下一音间距异常
        var paPitch: Int? = nil
        for note in result {
            if note.terminalType == "A" {
                paPitch = note.midiPitch
            } else if note.midiPitch >= 0, let pa = paPitch {
                let gap = abs(note.midiPitch - pa)
                if gap > 2 {
                    #if DEBUG
                    dprint("⚠️ [APPROACH-GAP] app=\(pa) next=\(note.midiPitch) gap=\(gap) nextType=\(note.terminalType)")
                    #endif
                }
                paPitch = nil
            }
        }
        
        return result
    }

    // MARK: - 查找当前位置的和弦
    
    private static func findChordAt(slot: Int, chordBlocks: [ChordBlock]) -> String {
        var currentSlot = 0
        
        for block in chordBlocks {
            let blockDuration = Int(Double(block.duration) * Double(JazzGuideToneEngine.slotsPerBeat))
            
            if slot < currentSlot + blockDuration {
                return block.name
            }
            
            currentSlot += blockDuration
        }
        
        // 超出范围，返回最后一个和弦
        return chordBlocks.last?.name ?? "C"
    }
    
    // MARK: - 选择音高
    
    private static func selectPitch(
        terminal: GrammarTerminal,
        chordName: String,
        lastPitch: Int,
        minPitch: Int,
        maxPitch: Int
    ) -> Int {
        // ═════════════════════════════════════════════════════════════
        // P0-3a: C/L/S/H 终端改用 fillProbs + getRandomNote + checkNote
        // 对齐 Java LickGen.fillMelodyHelper default 分支 (L2520-2570)
        // ═════════════════════════════════════════════════════════════
        switch terminal.type {
        case .chord, .color, .scale, .note:
            return selectPitchWithProbTable(
                terminal: terminal,
                chordName: chordName,
                lastPitch: lastPitch,
                minPitch: minPitch,
                maxPitch: maxPitch
            )
            
        case .approach:
            // 对齐 Java L2356: fallback 用 getRandomNote 纯随机 (原版标注 "approach->random")
            // 正拍检查由调用方(convert主循环)处理, 此处只负责选音
            let noteTerminal = GrammarTerminal(
                type: .note,
                durationSlots: terminal.durationSlots,
                isDotted: terminal.isDotted,
                tuplet: terminal.tuplet
            )
            return selectPitchWithProbTable(
                terminal: noteTerminal,
                chordName: chordName,
                lastPitch: lastPitch,
                minPitch: minPitch,
                maxPitch: maxPitch
            )
            
        case .arbitrary:
            // P0-4d: X(RANDOM) 终端 — 纯随机 + 排除 minInterval 内音 (Java L2367-2387)
            // 不看 probs[], 纯随机; 范围=[max(minPitch, lastPitch-maxInterval), min(maxPitch, lastPitch+maxInterval)]
            let low = max(minPitch, lastPitch - _grammarMaxInterval)
            let high = min(maxPitch, lastPitch + _grammarMaxInterval)
            guard low <= high else {
                // 兜底: 范围非法时回退音阶音
                let fallback = getScaleTones(chordName: chordName, minPitch: minPitch, maxPitch: maxPitch)
                return getClosestPitch(targetPitches: fallback, referencePitch: lastPitch, lastPitch: lastPitch, terminal: terminal)
            }
            var randomPitch = lastPitch
            // while 循环排除距离 lastPitch < minInterval 的音; 最多重试100次防止死循环
            for _ in 0..<100 {
                randomPitch = Int.random(in: low...high)
                if !(randomPitch > lastPitch - _grammarMinInterval &&
                     randomPitch < lastPitch + _grammarMinInterval) {
                    break  // 距离 >= minInterval, 接受
                }
            }
            return randomPitch
            
        case .outside:
            // P0-4d: Y(OUTSIDE) 终端 — default 逻辑 + pitch+1 (Java L2401-2436)
            // 原版 checkNote(OUTSIDE) 恒 false 空转取末值, 净效果="概率表加权任意音+1"
            // 用 .note 类型 (checkNote 恒 true, 等价"不验证类型"), 准确对齐原版净效果
            let noteTerminal = GrammarTerminal(type: .note, durationSlots: terminal.durationSlots)
            let basePitch = selectPitchWithProbTable(
                terminal: noteTerminal,
                chordName: chordName,
                lastPitch: lastPitch,
                minPitch: minPitch,
                maxPitch: maxPitch
            )
            var outsidePitch = basePitch + 1  // 移高半音制造外音
            outsidePitch = max(minPitch, min(maxPitch, outsidePitch))  // 音域钳位
            return outsidePitch
            
        case .scaleDegree:
            // 音阶级数：直接根据级数计算具体音高
            if let degree = terminal.scaleDegree {
                return getPitchFromScaleDegree(degree: degree, chordName: chordName, lastPitch: lastPitch,
                                               minPitch: minPitch, maxPitch: maxPitch)
            }
            let candidatePitches = getScaleTones(chordName: chordName, minPitch: minPitch, maxPitch: maxPitch)
            return getClosestPitch(targetPitches: candidatePitches, referencePitch: lastPitch, lastPitch: lastPitch, terminal: terminal)
            
        case .slope:
            // slope 类型暂时返回 0，后面专门处理
            return 0
            
        case .triadic:
            // triadic 已在外层 convert 函数提前拦截拆分
            return 0
            
        case .rest:
            // 休止符，返回 0
            return 0
        }
    }
    
    // MARK: - P0-3a: 概率表选音 (fillProbs + getRandomNote + checkNote)
    /// 对齐 Java LickGen.fillMelodyHelper default 分支 (L2520-2570)
    /// P0-4a: + leapProb 八度跳转 + avoidRepeats 重复音避免 + recalcPitchArray
    /// P0-4b: + 文法参数化 (权重/音程/leap-prob/avoid-repeats 从文法读取)
    private static func selectPitchWithProbTable(
        terminal: GrammarTerminal,
        chordName: String,
        lastPitch: Int,
        minPitch: Int,
        maxPitch: Int
    ) -> Int {
        // P0-4a: recalcPitchArray — 每个音符迭代前, 对 <1 的值逐步 *=2 恢复 (Java L3641-3649)
        for i in 0..<_pitchUsed.count {
            if _pitchUsed[i] < 1.0 {
                _pitchUsed[i] = min(_pitchUsed[i] * 2, 1.0)
            }
        }
        
        // P0-4a: leapProb 八度跳转 (Java L2527-2541)
        var effectiveLastPitch = lastPitch
        if Double.random(in: 0..<1) < _grammarLeapProb {
            if abs(lastPitch - maxPitch) > abs(lastPitch - minPitch) {
                effectiveLastPitch = min(lastPitch + 12, maxPitch)
            } else {
                effectiveLastPitch = max(lastPitch - 12, minPitch)
            }
            #if DEBUG
            dprint("【LEAP-OCTAVE】 leapProb=\(_grammarLeapProb) oldPitch=\(lastPitch) → effectivePitch=\(effectiveLastPitch)")
            #endif
        }
        
        // P0-4b: 从缓存获取当前和弦的 12 音级概率表 + 音级集合 (性能优化)
        let resolve = resolveChord(chordName)
        let probs = resolve.probs
        
        // P0-4a: maxRetries = 100 (对齐 Java NOTE_GEN_LIMIT=100, L158)
        let maxRetries = 100
        
        for _ in 0..<maxRetries {
            guard let pitch = PitchProbTable.getRandomNote(
                prevPitch: effectiveLastPitch,
                minStep: _grammarMinInterval,
                maxStep: _grammarMaxInterval,
                minPitch: minPitch,
                maxPitch: maxPitch,
                probs: probs
            ) else { break }
            
            guard PitchProbTable.checkNote(
                pitch: pitch,
                terminalType: terminal.type,
                chordPCSet: resolve.chordPCSet,
                colorPCSet: resolve.colorPCSet,
                scalePCSet: resolve.scalePCSet
            ) else {
                continue
            }
            
            // P0-4a: avoidRepeats — 未使用音=1.0必接受; 刚使用音=1/512低概率接受
            if !_grammarAvoidRepeats || Double.random(in: 0..<1) < _pitchUsed[pitch] {
                _pitchUsed[pitch] = 1.0 / 512.0  // setPitchUsed(pitch, REPEAT_PROB)
                return pitch
            }
        }
        
        // 重试失败回退
        #if DEBUG
        dprint("【PROBTABLE-FALLBACK】 chord=\(chordName) type=\(terminal.type) 概率表选音失败, 回退就近音")
        #endif
        
        let fallbackPool: [Int]
        switch terminal.type {
        case .chord:
            fallbackPool = getChordTones(chordName: chordName, minPitch: minPitch, maxPitch: maxPitch)
        case .color:
            fallbackPool = getColorTones(chordName: chordName, minPitch: minPitch, maxPitch: maxPitch)
        case .scale:
            fallbackPool = getScaleTones(chordName: chordName, minPitch: minPitch, maxPitch: maxPitch)
        case .note:
            let chord = getChordTones(chordName: chordName, minPitch: minPitch, maxPitch: maxPitch)
            let color = getColorTones(chordName: chordName, minPitch: minPitch, maxPitch: maxPitch)
            let scale = getScaleTones(chordName: chordName, minPitch: minPitch, maxPitch: maxPitch)
            fallbackPool = Array(Set(chord + color + scale)).sorted()
        default:
            fallbackPool = getScaleTones(chordName: chordName, minPitch: minPitch, maxPitch: maxPitch)
        }
        
        let fallbackPitch = getClosestPitch(targetPitches: fallbackPool, referencePitch: effectiveLastPitch, lastPitch: lastPitch, terminal: terminal)
        if fallbackPitch >= 0 && fallbackPitch < _pitchUsed.count {
            _pitchUsed[fallbackPitch] = 1.0 / 512.0
        }
        return fallbackPitch
    }
    
    
    // MARK: - Slope 音高选择（NoteChooser + Expectancy）
    /// Slope 内部音符音高：先区间过滤，再用Expectancy期望值打分择优
    private static func selectSlopePitch(
        terminal: GrammarTerminal,
        chordName: String,
        lastPitch: Int,
        minSlope: Int,
        maxSlope: Int,
        globalMinPitch: Int,
        globalMaxPitch: Int
    ) -> Int {
        // slope 0 0 强制同音，音域边界兜底
        if minSlope == 0, maxSlope == 0 {
            var safePitch = lastPitch
            if safePitch < globalMinPitch { safePitch = globalMinPitch }
            if safePitch > globalMaxPitch { safePitch = globalMaxPitch }
            return safePitch
        }
        
        // 计算初始音高区间
        var lowerBound = lastPitch + minSlope
        var upperBound = lastPitch + maxSlope

        // 固定音程相等自动放宽 ±1
        if lowerBound == upperBound {
            lowerBound -= 1
            upperBound += 1
        }

        // P0-slope-approach: 大跳放宽 (对齐 Java L3124-3130, MIN_JUMP_UPPER_BOUND=6, 放宽=3)
        // 两个独立条件: 上行大跳只放宽下界, 下行大跳只放宽上界 (原版非合并条件)
        if lowerBound - lastPitch >= 6 { lowerBound -= 3 }
        if upperBound - lastPitch <= -6 { upperBound += 3 }

        // 分三类音池（分层）
        let chordPool = getChordTones(chordName: chordName, minPitch: globalMinPitch, maxPitch: globalMaxPitch)
        let colorPool = getColorTones(chordName: chordName, minPitch: globalMinPitch, maxPitch: globalMaxPitch)
        let scalePool = getScaleTones(chordName: chordName, minPitch: globalMinPitch, maxPitch: globalMaxPitch)

        func filterPool(_ pool: [Int]) -> [Int] {
            pool.filter { $0 >= lowerBound && $0 <= upperBound }
        }
        var validChord = filterPool(chordPool)
        var validColor = filterPool(colorPool)
        var validScale = filterPool(scalePool)

        // CHORD类型找不到音向外最多扩张3次
        if terminal.type == .chord, validChord.isEmpty {
            var currLow = lowerBound
            var currHigh = upperBound
            for _ in 0..<3 {
                currLow -= 1
                currHigh += 1
                validChord = chordPool.filter { $0 >= currLow && $0 <= currHigh }
                if !validChord.isEmpty { break }
            }
        }

        // 池子为空兜底填充全局音
        if validChord.isEmpty { validChord = chordPool }
        if validColor.isEmpty { validColor = colorPool }
        if validScale.isEmpty { validScale = scalePool }

        // ========== 修复：根据终结符类型选择对应音池 ==========
        var targetPool: [Int]
        
        switch terminal.type {
        case .chord:
            // C: 和弦音 - 100%从和弦音选择
            targetPool = validChord
            
        case .color:
            // L (Java T_COLOR): 色彩音 - slope区间内优先下半区
            targetPool = validColor.isEmpty ? validChord : Array(validColor.filter { $0 <= (lowerBound + upperBound) / 2 })
            if targetPool.isEmpty { targetPool = validColor.isEmpty ? validChord : validColor }
            
        case .scale:
            // S (Java T_SCALE): 音阶音
            targetPool = validScale
            
        case .note:
            // H (Java T_NOTE): 普通音符 - 和弦音+色彩音混合 (slope区间内已限音域)
            targetPool = validChord + validColor
            
        case .approach:
            // A: 趋近音 - 理论上在slope循环中已特殊处理，这里做兜底
            // 趋近音使用和弦音上下半音/全音
            let approachPool = getApproachTones(chordName: chordName, minPitch: globalMinPitch, maxPitch: globalMaxPitch)
            let validApproach = approachPool.filter { $0 >= lowerBound && $0 <= upperBound }
            targetPool = validApproach.isEmpty ? validChord : validApproach
            
        case .arbitrary, .outside:
            // X/Y: 任意音/外音 - 使用权重随机混合
            let chordWeight = 0.5
            let colorWeight = 0.3
            let scaleWeight = 0.2
            let total = chordWeight + colorWeight + scaleWeight
            let rand = Double.random(in: 0..<total)
            
            if rand < chordWeight {
                targetPool = validChord
            } else if rand < chordWeight + colorWeight {
                targetPool = validColor
            } else {
                targetPool = validScale
            }
            
        case .scaleDegree, .slope, .triadic, .rest:
            // 这些类型不会走到这里，做兜底
            targetPool = validChord
        }

        // 池子空降级备选
        if targetPool.isEmpty {
            if !validChord.isEmpty { targetPool = validChord }
            else if !validScale.isEmpty { targetPool = validScale }
            else { targetPool = validColor }
        }

        // 防连续同音、防近期重复过滤 (保留, NoteChooser随机天然减重复, 保留无害)
        var candidatePool = targetPool
        if candidatePool.count > 1 {
            candidatePool = candidatePool.filter { $0 != lastPitch }
        }
        if candidatePool.count > 1 {
            candidatePool = candidatePool.filter { !recentPitches.contains($0) }
        }
        if candidatePool.isEmpty {
            candidatePool = targetPool
        }

        // ═════════════════════════════════════════════════════════════
        // P0-3b: 替换 Expectancy 评分为 NoteChooser.chooseNote
        // 对齐 Java LickGen slope 内联处理 (L1991-2200) + chooseNote (L3081-3268)
        // ═════════════════════════════════════════════════════════════
        
        // 1. NOTE→SCALE 转换 (Java L3148-3150: slope内H终端转SCALE)
        var ncType: Int
        switch terminal.type {
        case .chord: ncType = NoteChooser.CHORD
        case .color: ncType = NoteChooser.COLOR
        case .scale: ncType = NoteChooser.SCALE
        case .note: ncType = NoteChooser.SCALE  // NOTE→SCALE
        default: ncType = NoteChooser.RANDOM
        }
        
        // 2. NOCHORD→RANDOM (Java L3153-3167)
        let cleanName = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanName == "NC" || cleanName.isEmpty {
            ncType = NoteChooser.RANDOM
        }
        
        // 3. 构建 noteTypes[upperBound-lowerBound+1] + numTypes[4]
        // 对齐 Java getNoteTypes (L3273-3290) + 统计 (L3183-3196)
        // 复用现有 chordPool/colorPool, 不重复构建
        let chordSet = Set(chordPool)
        let colorSet = Set(colorPool)
        
        var noteTypes: [Int] = []
        var numTypes = [0, 0, 0, 0]  // [chord, color, random, scale]
        
        for pitch in lowerBound...upperBound {
            let noteType: Int
            if chordSet.contains(pitch) {
                noteType = NoteChooser.CHORD
                numTypes[0] += 1
                numTypes[3] += 1  // scale计数包含chord (Java L3185-3200)
            } else if colorSet.contains(pitch) {
                noteType = NoteChooser.COLOR
                numTypes[1] += 1
                numTypes[3] += 1  // scale计数包含color
            } else {
                noteType = NoteChooser.RANDOM
                numTypes[2] += 1
            }
            noteTypes.append(noteType)
        }
        
        // 4. 调用 NoteChooser.chooseNote
        // attempts=14 (MELODY_GEN_LIMIT-1=15-1), 触发八度越界修正 (Java NoteChooser.java:178)
        let noteChooser = NoteChooser(noOctaveSwitch: false)
        var pickedPitch = noteChooser.chooseNote(
            minPitch: globalMinPitch,
            maxPitch: globalMaxPitch,
            low: lowerBound,
            high: upperBound,
            type: ncType,
            numTypes: numTypes,
            noteTypes: noteTypes,
            attempts: 14,
            melodyGenLimit: 15  // 对齐 Java MELODY_GEN_LIMIT=15 (LickGen.java:157)
        )
        
        // 5. 兜底: NoteChooser返回超音域或无效时回退就近音
        if pickedPitch < globalMinPitch || pickedPitch > globalMaxPitch || candidatePool.isEmpty {
            pickedPitch = getClosestPitch(targetPitches: candidatePool, referencePitch: lastPitch, lastPitch: lastPitch, terminal: terminal)
        }
        
        #if DEBUG
        let nn2 = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        dprint("【SLOPE-NOTECHOOSER】 chord=\(chordName) type=\(terminal.type) range=[\(lowerBound),\(upperBound)] ncType=\(ncType) numTypes=\(numTypes) → 选中=\(nn2[((pickedPitch%12)+12)%12])\((pickedPitch/12)-1)(midi\(pickedPitch))")
        #endif
        
        return pickedPitch
    }

    // MARK: - 性能优化: 和弦解析统一入口 (P0)
    /// 解析和弦名，返回缓存的所有解析结果。
    /// 同一和弦 + 同一权重下只计算一次，后续命中缓存。
    /// trim 只在此处执行一次，下游所有函数接收已干净的 chordName。
    private static func resolveChord(_ chordName: String) -> ChordResolveCache {
        let cleanName = chordName.trimmingCharacters(in: .whitespacesAndNewlines)

        // 缓存命中: 同一和弦 + 同一权重三元组
        if let cached = _chordResolveCache,
           cached.chordName == cleanName,
           cached.chordToneWeight == _grammarChordToneWeight,
           cached.colorToneWeight == _grammarColorToneWeight,
           cached.scaleToneWeight == _grammarScaleToneWeight {
            return cached
        }

        // 缓存未命中: 一次性计算所有解析结果
        let rootPC = getRootPC(cleanName)
        let quality = ChordQuality(chordName: cleanName)

        let probs = PitchProbTable.fillProbs(
            chordName: cleanName,
            chordToneWeight: _grammarChordToneWeight,
            colorToneWeight: _grammarColorToneWeight,
            scaleToneWeight: _grammarScaleToneWeight,
            chordToneDecayRate: _grammarChordToneDecay
        )

        // 预计算音级集合，供 checkNote 做 O(1) 查找
        let chordPCSet = Set(quality.chordIntervals.map { (rootPC + $0) % 12 })
        let colorPCSet = Set(quality.colorIntervals(for: cleanName).map { (rootPC + $0) % 12 })
        let scalePCSet = Set(quality.scaleIntervals.map { (rootPC + $0) % 12 })

        let cache = ChordResolveCache(
            chordName: cleanName,
            chordToneWeight: _grammarChordToneWeight,
            colorToneWeight: _grammarColorToneWeight,
            scaleToneWeight: _grammarScaleToneWeight,
            quality: quality,
            rootPC: rootPC,
            probs: probs,
            chordPCSet: chordPCSet,
            colorPCSet: colorPCSet,
            scalePCSet: scalePCSet
        )
        _chordResolveCache = cache
        return cache
    }

    // MARK: - 性能优化: 音高数组统一入口 (P1)
    /// 一次性构建 chord/color/scale 三个音高数组并缓存。
    /// 复用 resolveChord 的 quality/rootPC，避免重复解析和弦。
    private static func resolveTones(chordName: String, minPitch: Int, maxPitch: Int) -> ChordToneCache {
        let cleanName = chordName.trimmingCharacters(in: .whitespacesAndNewlines)

        // 缓存命中
        if let cached = _chordToneCache,
           cached.chordName == cleanName,
           cached.minPitch == minPitch,
           cached.maxPitch == maxPitch {
            return cached
        }

        let resolve = resolveChord(cleanName)  // 复用 P0 缓存
        let rootPC = resolve.rootPC

        // 通用: 给定音程数组 → 音高数组
        func pitches(for intervals: [Int]) -> [Int] {
            var result: [Int] = []
            for interval in intervals {
                let targetPC = (rootPC + interval) % 12
                for octave in stride(from: (minPitch/12)*12, through: (maxPitch/12)*12, by: 12) {
                    let pitch = targetPC + octave
                    if pitch >= minPitch && pitch <= maxPitch {
                        result.append(pitch)
                    }
                }
            }
            return result.sorted()
        }

        var chordTones = pitches(for: resolve.quality.chordIntervals)
        if chordTones.isEmpty { chordTones = [60] }  // 对齐原 getChordTones 兜底
        let colorTones = pitches(for: resolve.quality.colorIntervals(for: cleanName))
        let scaleTones = pitches(for: resolve.quality.scaleIntervals)

        let cache = ChordToneCache(
            chordName: cleanName,
            minPitch: minPitch,
            maxPitch: maxPitch,
            chordTones: chordTones,
            colorTones: colorTones,
            scaleTones: scaleTones
        )
        _chordToneCache = cache
        return cache
    }

    // MARK: - 获取和弦音
    
    private static func getChordTones(chordName: String, minPitch: Int, maxPitch: Int) -> [Int] {
        // 性能优化(P1): 复用 resolveTones 缓存，同一和弦+音域只计算一次
        return resolveTones(chordName: chordName, minPitch: minPitch, maxPitch: maxPitch).chordTones
    }
    
    // MARK: - 和弦音 + 音级标记
    
    /// 获取和弦音并标记音级 (增量方法，不动原有 getChordTones)
    static func getChordTonesWithDegree(chordName: String,
                                        minPitch: Int, maxPitch: Int)
    -> [(pitch: Int, degree: ChordDegree)] {
        let cleanName = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootPC = getRootPC(cleanName)
        let quality = ChordQuality(chordName: cleanName)
        let intervals = quality.chordIntervals
        
        var result: [(Int, ChordDegree)] = []
        for interval in intervals {
            let targetPC = (rootPC + interval) % 12
            for octave in stride(from: (minPitch/12)*12, through: (maxPitch/12)*12, by: 12) {
                let pitch = targetPC + octave
                guard pitch >= minPitch && pitch <= maxPitch else { continue }
                let degree: ChordDegree
                switch interval {
                case 0:             degree = .root
                case 3, 4:          degree = .third
                case 5:             degree = .fourth
                case 6, 7, 8:       degree = .fifth
                case 9, 10, 11:     degree = .seventh
                default:            degree = .altered
                }
                result.append((pitch, degree))
            }
        }
        return result
    }
    
    /// 🔍 排查日志: 和弦音列表
    private static func logChordTones(_ chordName: String, _ tones: [Int]) {
        let names = tones.map { m in
            let pc = m % 12
            let oct = m / 12 - 1
            let nn = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
            return "\(nn[pc])\(oct)(midi\(m))"
        }
        //dprint("【和弦基准音列表】 和弦=\(chordName) 数量=\(tones.count) → [\(names.joined(separator:", "))]")
    }
    
    // MARK: - 获取色彩音（延伸音：9、11、13）
    
    private static func getColorTones(chordName: String, minPitch: Int, maxPitch: Int) -> [Int] {
        // 性能优化(P1): 复用 resolveTones 缓存
        return resolveTones(chordName: chordName, minPitch: minPitch, maxPitch: maxPitch).colorTones
    }
    
    // MARK: - 获取音阶音（大调音阶/小调音阶，第一阶段先简单处理）
    
    private static func getScaleTones(chordName: String, minPitch: Int, maxPitch: Int) -> [Int] {
        // 性能优化(P1): 复用 resolveTones 缓存
        return resolveTones(chordName: chordName, minPitch: minPitch, maxPitch: maxPitch).scaleTones
    }
    
    // MARK: - 趋近音反推公共方法（给定目标音高 → 下方半音 / 上方音阶音）
    
    private static func deriveApproachPitch(
        targetPitch: Int, chordName: String, lastPitch: Int, preferBelow: Bool
    ) -> Int {
        // 对齐 Java L2322-2345: 50% 上行半音趋近, 50% 下行半音趋近
        // 防同音特判: 若趋近音 == lastPitch, 强制取反方向
        // 注: chordName/preferBelow 参数保留签名兼容, 纯半音趋近不使用
        let approachBelow = targetPitch - 1
        let approachAbove = targetPitch + 1

        var goBelow = Bool.random()  // 50% 随机 (Java bernoulli(.5))

        // 防同音: 若选中方向 == lastPitch, 强制取反方向
        if goBelow && approachBelow == lastPitch { goBelow = false }
        else if !goBelow && approachAbove == lastPitch { goBelow = true }

        return goBelow ? approachBelow : approachAbove
    }

    // MARK: - slope 内 approach 趋近音方向（由 slope 走向决定）

    /// P0-slope-approach: slope 内 approach 趋近音方向由 slope 走向决定
    /// 对齐 Java LickGen.java L2070-2103 (slope 内 A 终端方向判定)
    private static func deriveSlopeApproachPitch(
        targetPitch: Int, minSlope: Int, maxSlope: Int, lastPitch: Int,
        minPitch: Int, maxPitch: Int
    ) -> Int {
        var approachPitch = targetPitch  // 初始值, 零音程分支若都不触发则默认下行

        // 前置防同音特判 (对齐 Java L2070-2078)
        if targetPitch + 1 == lastPitch {
            approachPitch = targetPitch - 1  // 目标+1==上一音 → 下行趋近
        } else if targetPitch - 1 == lastPitch {
            approachPitch = targetPitch + 1  // 目标-1==上一音 → 上行趋近
        } else if minSlope == 0 || maxSlope == 0 {
            // 零音程 slope: 两个独立 if (覆盖式, 对齐 Java L2082-2089)
            if maxSlope > 0 {
                approachPitch = targetPitch - 1  // 下行
            }
            if minSlope < 0 {
                approachPitch = targetPitch + 1  // 上行 (可能覆盖上一个)
            }
            // 若都不触发 (minSlope==0 && maxSlope==0), approachPitch 保持 targetPitch, 后续默认下行
        } else if minSlope > 0 {
            // 上行 slope → 下行趋近 (对齐 Java L2091-2094)
            approachPitch = targetPitch - 1
        } else if maxSlope < 0 {
            // 下行 slope → 上行趋近 (对齐 Java L2095-2098)
            approachPitch = targetPitch + 1
        } else {
            // 默认下行 (对齐 Java L2100-2102)
            approachPitch = targetPitch - 1
        }

        // 零音程分支若 approachPitch == targetPitch (都不触发), 默认下行 (防御性修正)
        if approachPitch == targetPitch {
            approachPitch = targetPitch - 1
        }

        // 音域钳位
        return Swift.max(minPitch, Swift.min(maxPitch, approachPitch))
    }
    
    // MARK: - 获取经过音/邻音（爵士非对称趋近：下方半音，上方音阶音）
    
    private static func getApproachTones(chordName: String, minPitch: Int, maxPitch: Int) -> [Int] {
        let chordTones = getChordTones(chordName: chordName, minPitch: minPitch - 2, maxPitch: maxPitch + 2)
        let scaleTones = getScaleTones(chordName: chordName, minPitch: minPitch - 2, maxPitch: maxPitch + 2)
        
        var approachPitches = Set<Int>()
        var anomalies: [String] = []
        
        for target in chordTones {
            approachPitches.insert(target - 1)
            if let diatonicUpper = scaleTones.first(where: { $0 > target }) {
                if diatonicUpper - target > 2 {
                    anomalies.append("target=\(target) diatUpper=\(diatonicUpper) intv=\(diatonicUpper-target)")
                    continue
                }
                approachPitches.insert(diatonicUpper)
            } else {
                approachPitches.insert(target + 2)
            }
        }
        
        if !anomalies.isEmpty {
            #if DEBUG
            dprint("⚠️ [APPROACH-POOL] chord=\(chordName) pool=\(approachPitches.sorted()) anomalies=[\(anomalies.joined(separator: "; "))]")
            #endif
        } else {
            #if DEBUG
            dprint("  [APPROACH-POOL] chord=\(chordName) pool=\(approachPitches.sorted())")
            #endif
        }
        
        return Array(approachPitches).filter { $0 >= minPitch && $0 <= maxPitch }.sorted()
    }
    
    // MARK: - Triadic 三和弦分解音池 (Garzone 随机半音阶趋近理论)
    /// P0-修复4: 动态调整 triadic 音域范围 (对齐 Java L1310-1324)
    /// 以上一音为中心, ±12 半音 = 1 八度 (原版注释写 1.5 octaves 是笔误, 代码是 ±12)
    private static func adjustTriadicPitch(referencePitch: Int, globalMin: Int, globalMax: Int) {
        triadicMaxPitch = (referencePitch + 12 <= globalMax) ? referencePitch + 12 : globalMax
        triadicMinPitch = (referencePitch - 12 >= globalMin) ? referencePitch - 12 : globalMin
    }

    /// 核心升级：完全抛弃底层和弦束缚，基于半音游走、随机转位与八度错位，生成现代爵士的 Outside 线条
    private static func getTriadicTones(referencePitch: Int, minPitch: Int, maxPitch: Int) -> [Int] {
        // P0-修复4: 先动态调整 triadic 音域 (±12 半音), 再用调整后的音域生成
        adjustTriadicPitch(referencePitch: referencePitch, globalMin: minPitch, globalMax: maxPitch)
        // 1. 获取下一个基准音（以上一个音为基准，随机上下半音游走）
        let basePitch = getGarzoneBase(referencePitch: referencePitch, minPitch: triadicMinPitch, maxPitch: triadicMaxPitch)

        // 2. 基于游走到的基准音，生成高度错位和变形的随机三和弦
        return makeGarzoneTriad(basePitch: basePitch, minPitch: triadicMinPitch, maxPitch: triadicMaxPitch)
    }

    // MARK: - Garzone Triadic 辅助方法 (Outside Playing)
    
    /// 获取三和弦的半音游走起点 (只允许小二度游走)
    private static func getGarzoneBase(referencePitch: Int, minPitch: Int, maxPitch: Int) -> Int {
        var outPitch = referencePitch
        var attempts = 0
        repeat {
            let r = Int.random(in: 0...19)
            if r <= 8 {
                outPitch = (referencePitch - 1 >= minPitch) ? referencePitch - 1 : referencePitch + 1
            } else if r <= 17 {
                outPitch = (referencePitch + 1 <= maxPitch) ? referencePitch + 1 : referencePitch - 1
            }
            attempts += 1
        } while (outPitch == referencePitch && attempts < 10)
        return outPitch
    }

    /// 获取反演/变异后真正的根音
    private static func getTrueRoot(basePitch: Int, inversion: Int, currentType: Int) -> Int {
        switch inversion {
        case 4, 3, 0: return basePitch
        case 2: return basePitch + 5
        case 1: return basePitch + (currentType == 5 ? 8 : 9)
        default: return basePitch
        }
    }

    /// 检查生成的根音和性质是否与最近使用的重复（避免原地转圈，推动和声流动）
    private static func inRootList(basePitch: Int, inversion: Int, currentType: Int) -> Bool {
        let trueRoot = getTrueRoot(basePitch: basePitch, inversion: inversion, currentType: currentType)
        let trueRootPC = trueRoot % 12
        for i in 0..<ROOT_STORAGE_NUMBER {
            if triadicRecentRoots[i] != -1 {
                let recentPC = triadicRecentRoots[i] % 12
                if trueRootPC == recentPC && currentType == triadicRecentTypes[i] {
                    return true
                }
            }
        }
        return false
    }

    /// 将生成的根音和性质存入历史记录
    private static func addToRootList(basePitch: Int, inversion: Int, currentType: Int) {
        triadicRecentRoots[triadicRootCounter] = getTrueRoot(basePitch: basePitch, inversion: inversion, currentType: currentType)
        triadicRecentTypes[triadicRootCounter] = currentType
        triadicRootCounter = (triadicRootCounter + 1) % ROOT_STORAGE_NUMBER
    }

    /// 核心引擎：生成高度错位的转位三和弦 (Jagged Contour) - 修正黄金谱系版
    private static func makeGarzoneTriad(basePitch: Int, minPitch: Int, maxPitch: Int) -> [Int] {
        var newInversion = 0
        var currentType = 0
        var attempts = 0
        
        // 1. 随机选取和弦转位与性质，并防重
        repeat {
            let r = Int.random(in: 0...10)
            switch r {
            case 0, 1, 2:
                newInversion = 0; currentType = Bool.random() ? 5 : 6 // 5=maj, 6=min
            case 3, 4, 5:
                newInversion = 1; currentType = Bool.random() ? 5 : 6
            case 6, 7, 8:
                newInversion = 2; currentType = Bool.random() ? 5 : 6
            case 9:
                newInversion = 3; currentType = 7 // dim (减三)
            case 10:
                newInversion = 4; currentType = 8 // aug (增三)
            default: break
            }
            attempts += 1
        } while (newInversion == triadicLastInversion || inRootList(basePitch: basePitch, inversion: newInversion, currentType: currentType)) && attempts < 20
        
        triadicLastInversion = newInversion
        addToRootList(basePitch: basePitch, inversion: newInversion, currentType: currentType)
        
        // 2. 构建三和弦 (严格对齐 LickGen.makeTriad)
        var triad = [basePitch, basePitch, basePitch]
        switch newInversion {
        case 4: // Augmented
            triad[1] += 4; triad[2] += 8
        case 3: // Diminished
            triad[1] += 3; triad[2] += 6
        case 2: // 2nd Inversion
            triad[1] += 5
            triad[2] += (currentType == 5 ? 9 : 8)
        case 1: // 1st Inversion (修正：精准展开)
            if currentType == 5 { // Major
                triad[1] += 3; triad[2] += 8
            } else { // Minor
                triad[1] += 4; triad[2] += 9
            }
        case 0: // Root Position
            triad[2] += 7
            triad[1] += (currentType == 5 ? 4 : 3)
        default: break
        }
        
        // 3. 八度错位 (Octave Displacement) - 修正黄金谱系版
        // 随机互换中间和最高音
        if Bool.random() { triad.swapAt(1, 2) }
        // 随机降低中间音八度
        if Bool.random() { triad[1] -= 12 }
        
        let diff01 = abs(triad[0] - triad[1])
        if !(diff01 == 4) { // 不是纯四度关系时，执行更激进的错位
            if diff01 <= 3 {
                // 紧凑音程的错位逻辑
                if triad[0] > triad[1] && triad[2] > triad[1] { triad[2] -= 12 }
                else if triad[0] < triad[1] && triad[2] < triad[1] { triad[2] += 12 }
            } else {
                // 常规音程的错位逻辑
                if triad[0] < triad[1] && triad[1] < triad[2] { triad[2] -= 12 }
                else if triad[0] > triad[1] && triad[2] < triad[1] { triad[2] += 12 }
            }
        } else {
            // 纯四度关系时，随机降低最高音八度
            if Bool.random() { triad[2] -= 12 }
        }
        
        // 4. 音域钳位保护
        for i in 0..<3 {
            while triad[i] > maxPitch { triad[i] -= 12 }
            while triad[i] < minPitch { triad[i] += 12 }
        }
        
        return triad
    }
    
    // MARK: - 获取根音音高类
    
    static func getRootPC(_ name: String) -> Int {
        let normalized = name
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "♯", with: "#")
        let chars = Array(normalized)
        guard !chars.isEmpty else { return 0 }
        var rootStr = String(chars[0]).uppercased()
        if chars.count > 1 && (chars[1] == "#" || chars[1] == "b") { rootStr.append(chars[1]) }
        let pcMap: [String: Int] = [
            "C": 0, "B#": 0,
            "C#": 1, "Db": 1,
            "D": 2,
            "D#": 3, "Eb": 3,
            "E": 4, "Fb": 4,
            "F": 5, "E#": 5,
            "F#": 6, "Gb": 6,
            "G": 7,
            "G#": 8, "Ab": 8,
            "A": 9,
            "A#": 10, "Bb": 10,
            "B": 11, "Cb": 11
        ]
        return pcMap[rootStr] ?? 0
    }
    
    // MARK: - NoteChooser概率选池 + 最近音（对齐Java LickGen.chooseNote两层选音）
    
    /// 先掷骰选池(和弦/色彩), 再从选中池取最近音
    private static func selectWithNoteChooser(
        chordPool: [Int], colorPool: [Int],
        chordName: String, lastPitch: Int,
        minPitch: Int, maxPitch: Int,
        terminal: GrammarTerminal
    ) -> Int {
        // 在当前lastPitch ±12区间内构建noteTypes数组
        let low = max(minPitch, lastPitch - 12)
        let high = min(maxPitch, lastPitch + 12)
        guard high > low else { return lastPitch }
        
        let chordPCs = Set(chordPool.map { $0 % 12 })
        let colorPCs = Set(colorPool.map { $0 % 12 })
        
        var noteTypes: [Int] = []
        var numTypes = [0, 0, 0, 0]
        for midi in low...high {
            let pc = midi % 12
            if chordPCs.contains(pc) {
                noteTypes.append(NoteChooser.CHORD)
                numTypes[0] += 1; numTypes[3] += 1
            } else if colorPCs.contains(pc) {
                noteTypes.append(NoteChooser.COLOR)
                numTypes[1] += 1; numTypes[3] += 1
            } else {
                noteTypes.append(NoteChooser.RANDOM)
                numTypes[2] += 1
            }
        }
        
        // 目标类型: chord→CHORD, color/note→COLOR (P0-2阶段.note暂保留原highColor行为, P0-3改三池加权)
        let targetType: Int
        switch terminal.type {
        case .color, .note: targetType = NoteChooser.COLOR
        default:             targetType = NoteChooser.CHORD
        }
        
        let chooser = NoteChooser(noOctaveSwitch: false)
        let selectedPitch = chooser.chooseNote(
            minPitch: minPitch, maxPitch: maxPitch,
            low: low, high: high,
            type: targetType,
            numTypes: numTypes,
            noteTypes: noteTypes,
            attempts: 15
        )
        
        return selectedPitch
    }
    
    // MARK: - 找最近的音高（带方向偏好，避免来回跳）
    
    private static func getClosestPitch(targetPitches: [Int], referencePitch: Int, lastPitch: Int, terminal: GrammarTerminal? = nil) -> Int {
        // 1. 先过滤掉和上一个音完全相同的音
        var candidates = targetPitches.filter { $0 != referencePitch }
        if candidates.isEmpty {
            candidates = targetPitches
        }
        
        // 2. 计算每个候选音的评分
        var scored: [(pitch: Int, score: Double)] = []
        
        for pitch in candidates {
            let distance = abs(pitch - referencePitch)
            var score = Double(distance)
            
            let direction = pitch > referencePitch ? 1 : -1
            
            // 方向偏好：如果和上一次方向相同，给奖励（减分）
            // M5: expectancy-multiplier缩放方向偏好强度
            if lastDirection != 0 && direction == lastDirection {
                score -= 2.0 * _expectancyBridge  // 默认0→禁用, >0时启用
            }
            
            // 反向惩罚：色彩音减半，提升爵士色彩中性生成概率≈2倍
            // 注意: .note(Java T_NOTE)不是色彩音, 不享受减半 (对齐DeepSeek审核结论)
            if lastDirection != 0 && direction != lastDirection {
                let isColorType = terminal?.type == .color
                score += isColorType ? 0.5 : 1.0        // 色彩音基础惩罚减半
                if distance <= 2 {
                    score += isColorType ? 1.5 : 3.0    // 半音/全音反向重罚减半
                }
            }
            
            // 1. 连续同音重惩罚（重复音冷却机制）
            if pitch == lastPitch {
                score += 6.0
            }
            // 近期重复音中等惩罚
            if recentPitches.contains(pitch) {
                score += 3.2
            }
            
            // 2. 超大跳加重扣分（6半音以上大幅提升成本）
            if distance >= 6 {
                score += Double(distance - 5) * 1.2
            } else if distance >= 3 {
                score += Double(distance - 5) * 0.5
            }
            
            // F3: 八度上下文记忆 — 参考前前音prevPrevPitch维持旋律线条连续性
            // prevPrevPitch由convert()的局部变量传入(通过静态桥接)
            if let ppp = _prevPrevPitchBridge, abs(pitch - ppp) <= 4 {
                score -= 1.5  // 保持八度区域内奖励
            }
            
            // F3: 大跳概率 — leap-prob ~0.01随机大跳
            if distance >= 5 && Double.random(in: 0...1) < 0.012 {
                score -= Double(distance) * 0.8  // 偶尔奖励大跳
            }
            
            scored.append((pitch, score))
        }
        
        // 3. 按评分排序
        scored.sort { $0.score < $1.score }
        
        // 取前 3-4 个最好的候选
        let topCount = min(4, scored.count)
        let topCandidates = Array(scored.prefix(topCount))

        // 概率更均匀: 35% best, 35% second, 30% third (更多爵士感变数)
        let random = Double.random(in: 0..<1)
        if topCount == 1 {
            return topCandidates[0].pitch
        } else if topCount == 2 {
            return random < 0.5 ? topCandidates[0].pitch : topCandidates[1].pitch
        } else if topCount == 3 {
            if random < 0.35 { return topCandidates[0].pitch }
            else if random < 0.70 { return topCandidates[1].pitch }
            else { return topCandidates[2].pitch }
        } else {
            if random < 0.30 { return topCandidates[0].pitch }
            else if random < 0.55 { return topCandidates[1].pitch }
            else if random < 0.80 { return topCandidates[2].pitch }
            else { return topCandidates[3].pitch }
        }
    }

    /// NoteChooser 静态概率查表权重映射 (28条规则内置)
    /// 当动态评分差值<0.1时作为轮盘抽样兜底
    private static func noteChooserWeight(for terminal: GrammarTerminal) -> Double {
        let typeMap: [GrammarTerminalType: Int] = [.chord: 1, .color: 1, .note: 1, .scale: 3, .arbitrary: 3, .approach: 1, .outside: 3]
        let lookupType = typeMap[terminal.type] ?? 0
        let rule = NoteChooser.probabilityTable.first { $0.type == lookupType && $0.hChord == 1 } ?? NoteChooser.probabilityTable[0]
        let probs = [rule.pChord, rule.pColor, rule.pRandom, rule.pScale]
        return Double(probs.max() ?? 100) / 100.0
    }

    // MARK: - Scale Degree 音高计算
    
    /// 根据音阶级数计算具体音高
    ///
    /// 对齐 Java LickGen.makeRelativeNote() (imp/lickgen/LickGen.java):
    ///   1. 解析级数字符串 → (基础级数 1-7, 升降号, 八度偏移)
    ///   2. 按 ChordQuality.scaleDegreeSemitones 查该和弦族的 degree→半音映射
    ///   3. 半音偏移 = 基础半音 + 升降号 + 八度偏移×12
    ///   4. 选离 lastPitch 最近的八度 (音域由调用方传入, 对齐文法 min-pitch/max-pitch)
    ///
    /// - Parameters:
    ///   - degree: 级数字符串，如 "3", "b5", "#9", "b13"
    ///   - chordName: 和弦名称 (用于确定 ChordQuality)
    ///   - lastPitch: 上一个音的音高（用于选择合适的八度）
    ///   - minPitch: 文法配置的最低音高 (如 58)
    ///   - maxPitch: 文法配置的最高音高 (如 82)
    /// - Returns: 具体的 MIDI 音高
    private static func getPitchFromScaleDegree(degree: String, chordName: String, lastPitch: Int,
                                                 minPitch: Int, maxPitch: Int) -> Int {
        let rootPC = getRootPC(chordName)

        // 1. 解析级数 (含升降号 + 八度归约)
        let parsed = parseScaleDegree(degree)

        // 2. 按和弦品质查 degree→半音映射 (P0-1 修复: 替代原通用大调音阶)
        let quality = ChordQuality(chordName: chordName)
        let scaleTable = quality.scaleDegreeSemitones
        let baseSemitone = scaleTable[parsed.degree - 1]  // degree 1-7 → index 0-6

        // 3. 总半音偏移 = 基础半音 + 升降号 + 八度偏移
        let semitoneOffset = baseSemitone + parsed.accidental + parsed.octaveShift * 12

        // 4. 计算目标音高类 (0-11)
        let targetPC = (rootPC + semitoneOffset + 120) % 12

        // 5. 选择离上一个音最近的八度 (使用文法配置的音域 minPitch/maxPitch)
        var bestPitch = 60 + targetPC  // 默认中央C八度兜底
        var minDistance = Int.max

        for octave in [36, 48, 60, 72, 84] {
            let pitch = octave + targetPC
            if pitch >= minPitch && pitch <= maxPitch {
                let distance = abs(pitch - lastPitch)
                if distance < minDistance {
                    minDistance = distance
                    bestPitch = pitch
                }
            }
        }

        return bestPitch
    }

    /// 解析后的音阶级数结构
    /// - degree: 归约后的基础级数 (1-7)
    /// - accidental: 升降号调整 (-1=降, 0=自然, +1=升)
    /// - octaveShift: 八度偏移 (degree>7 时为正, degree<1 时为负)
    private struct ParsedScaleDegree {
        let degree: Int
        let accidental: Int
        let octaveShift: Int
    }

    /// 解析音阶级数字符串 → ParsedScaleDegree
    ///
    /// 对齐 Java LickGen.makeRelativeNote() 中的八度归约逻辑:
    ///   while(degreeValue > 7) { octaveAdjustment += 1; degreeValue -= 7; }
    ///   while(degreeValue < 0) { octaveAdjustment -= 1; degreeValue += 8; }
    ///
    /// 支持："1", "b2", "2", "b3", "3", "4", "#4", "5", "b6", "6", "b7", "7",
    ///       "8", "9", "#9", "b9", "11", "#11", "13", "b13"
    private static func parseScaleDegree(_ degree: String) -> ParsedScaleDegree {
        let deg = degree.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. 提取升降号
        var accidental = 0
        var numStr = deg

        if deg.hasPrefix("b") || deg.hasPrefix("♭") {
            accidental = -1
            numStr = String(deg.dropFirst())
        } else if deg.hasPrefix("#") || deg.hasPrefix("♯") {
            accidental = 1
            numStr = String(deg.dropFirst())
        }

        // 2. 解析级数数值
        guard var degreeValue = Int(numStr) else {
            // 解析失败 → 兜底为根音
            return ParsedScaleDegree(degree: 1, accidental: 0, octaveShift: 0)
        }

        // 3. 八度归约 (对齐 Java: degree>7 减7加八度; degree<1 加7减八度)
        var octaveShift = 0
        while degreeValue > 7 {
            octaveShift += 1
            degreeValue -= 7
        }
        while degreeValue < 1 {
            octaveShift -= 1
            degreeValue += 7
        }

        return ParsedScaleDegree(degree: degreeValue, accidental: accidental, octaveShift: octaveShift)
    }
}
// MARK: - 爵士和弦品质与音程映射引擎 (DeepSeek 修正黄金谱系版)
enum ChordQuality {
    case major7, minor7, dominant7, halfDiminished, diminished7, augmented7, minorMajor7, alt
    case sus4, sus2, sevenSus4, add9, six

    init(chordName: String) {
        let name = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerName = name.lowercased()
        
        // 1. 优先匹配复合词或长后缀，防止短字符贪婪劫持
        // 长后缀优先: 7sus4 → sus2 → sus4 → add9 → six → 9/7/11/13
        if lowerName.contains("dim7") || lowerName.contains("o7") || lowerName.contains("°7") {
            self = .diminished7
        } else if lowerName.contains("m7b5") || lowerName.contains("ø") || lowerName.contains("min7b5") {
            self = .halfDiminished
        } else if lowerName.contains("dim") || lowerName.hasSuffix("o") || lowerName.contains("°") || lowerName.contains("o/") {
            self = .halfDiminished                  // 普通 dim/减三和弦归为半减七；仅 dim7/o7 为减七
        } else if lowerName.contains("mmaj") || lowerName.contains("mm7") {
            self = .minorMajor7
        } else if lowerName.contains("maj") || name.contains("M7") || name.contains("△") {
            self = .major7
        } else if lowerName.contains("aug") || lowerName.contains("+") {
            self = .augmented7
        } else if lowerName.contains("alt") {
            self = .alt
        // ★ 长后缀优先: 7sus4 先于 sus 检测（避免被 .sus4 劫持）
        } else if lowerName.contains("7sus") {
            self = .sevenSus4
        // ★ sus2 先于 sus 检测
        } else if lowerName.contains("sus2") {
            self = .sus2
        } else if lowerName.contains("sus") {
            self = .sus4                           // 原 .sus，语义更精确为 sus4
        } else if lowerName.contains("m") && !lowerName.contains("dom") {
            self = .minor7
        // ★ 纯六和弦: 含 6 但不含 7/9/11/13（6/9 归 dominant7）
        } else if lowerName.contains("6") && !lowerName.contains("7") && !lowerName.contains("9")
                  && !lowerName.contains("11") && !lowerName.contains("13") {
            self = .six
        // ★ add9 先于 9 检测（避免被 .dominant7 劫持）
        } else if lowerName.contains("add9") || lowerName.contains("add2") {
            self = .add9
        } else if lowerName.contains("7") || lowerName.contains("9")
                  || lowerName.contains("11") || lowerName.contains("13") {
            self = .dominant7                      // 属七/属九/属十一/属十三
        } else {
            self = .major7                         // 无后缀大三和弦
        }
    }

    // 精确的爵士核心内敛音程
    var chordIntervals: [Int] {
        switch self {
        case .major7:        return [0, 4, 7, 11]
        case .minor7:        return [0, 3, 7, 10]
        case .dominant7:     return [0, 4, 7, 10]
        case .halfDiminished:return [0, 3, 6, 10]
        case .diminished7:   return [0, 3, 6, 9]
        case .augmented7:    return [0, 4, 8, 10]
        case .minorMajor7:   return [0, 3, 7, 11]
        case .alt:           return [0, 4, 6, 8, 10] // alt 五音集
        case .sus4:          return [0, 5, 7]         // 纯四度挂留，无三音
        // ★ 新增边缘和弦:
        case .sus2:          return [0, 2, 7]         // 大二度挂留，无三音无四度
        case .sevenSus4:     return [0, 5, 7, 10]     // sus4 + 属七 b7
        case .add9:          return [0, 2, 4, 7]       // 大三和弦 + 9 音（升序，无七音）
        case .six:           return [0, 4, 7, 9]       // 大三和弦 + 六度音（无七音）
        }
    }

    // 乐谱音阶池
    var scaleIntervals: [Int] {
        switch self {
        case .major7:        return [0, 2, 4, 5, 7, 9, 11]    // Ionian (大调)
        case .minor7:        return [0, 2, 3, 5, 7, 9, 10]    // Dorian (爵士经典小调)
        case .dominant7:     return [0, 2, 4, 5, 7, 9, 10]    // Mixolydian (属七音阶)
        case .halfDiminished:return [0, 1, 3, 5, 6, 8, 10]    // Locrian (半减七音阶)
        case .diminished7:   return [0, 2, 3, 5, 6, 8, 9, 11] // 全半减音阶 (W-H)，对齐 Java NoteConverter
        case .augmented7:    return [0, 2, 4, 6, 8, 10]       // Whole Tone (全音音阶)
        case .minorMajor7:   return [0, 2, 3, 5, 7, 9, 11]    // Melodic Minor (旋律小调)
        case .alt:           return [0, 1, 3, 4, 6, 8, 10]    // Super Locrian (变化音阶)
        case .sus4:          return [0, 2, 5, 7, 9, 10]       // Mixolydian (sus 属七替代)
        // ★ 新增边缘和弦:
        case .sus2:          return [0, 2, 4, 5, 7, 9, 11]    // Ionian (sus2 通常用大调)
        case .sevenSus4:     return [0, 2, 4, 5, 7, 9, 10]    // Mixolydian (7sus4 = 属七挂留)
        case .add9:          return [0, 2, 4, 5, 7, 9, 11]    // Ionian (add9 = 大三加音)
        case .six:           return [0, 2, 4, 5, 7, 9, 11]    // Ionian (6 和弦用大调)
        }
    }

    // 色彩延伸音 (与 ChordExtensionTonePool 统一，chordName 区分属七 alt)
    func colorIntervals(for chordName: String) -> [Int] {
        switch self {
        case .alt:           return [1, 3, 6, 8]             // b9, #9, #11, b13 (alt 特化)
        case .halfDiminished:return [2, 5, 8]             // 9, 11, b13
        case .augmented7:    return [2, 6]                // 9, #11 (增三特化)
        case .dominant7:
            let lower = chordName.lowercased()
            if lower.contains("alt") {
                // 真正的alt：全量变化音(b9/#9/#11/b13)，排除自然11(Super Locrian无自然11)
                return ChordExtensionTonePool.tonesFor(.dominant).filter { $0 != 5 }
            }
            // 非alt属七：基础色彩音(9,11,13) + 和弦实际标注的变化音
            // 单个变化音(b9/#9/b13/#11)不构成alt语义，自然11仍为合法色彩音(Mixolydian/减音阶内音)
            var colors = ChordExtensionTonePool.primaryTonesFor(.dominant)  // [2, 5, 9] = 9, 11, 13
            if lower.contains("b9")  { colors.append(1) }
            if lower.contains("#9")  { colors.append(3) }
            if lower.contains("#11") { colors.append(6) }
            if lower.contains("b13") { colors.append(8) }
            return colors
        // ★ 新增: sevenSus4 复用 dominant7 色彩音逻辑（支持 b9/#9 等变化音）
        case .sevenSus4:
            let lower = chordName.lowercased()
            var colors = ChordExtensionTonePool.primaryTonesFor(.dominant)  // [2, 5, 9]
            if lower.contains("b9")  { colors.append(1) }
            if lower.contains("#9")  { colors.append(3) }
            if lower.contains("#11") { colors.append(6) }
            if lower.contains("b13") { colors.append(8) }
            return colors
        // ★ 新增: sus2/sus4 用 sus 族色彩音（避用三音）
        case .sus2, .sus4:
            return ChordExtensionTonePool.tonesFor(.sus)  // [2,5,9]，avoid 3
        // ★ 新增: add9/six 用 major 族色彩音
        case .add9, .six:
            return ChordExtensionTonePool.tonesFor(.major)  // [2,5,6,9]
        default:             return ChordExtensionTonePool.tonesFor(self.chordFamily)
        }
    }
    
    private func hasAlteredIndicators(_ name: String) -> Bool {
        let lowers = name.lowercased()
        let rootLen = lowers.prefix(while: { $0.isLetter || $0 == "#" || $0 == "b" }).count
        let suffix = String(lowers.dropFirst(rootLen))
        return suffix.contains("alt") || suffix.contains("#11") ||
               suffix.contains("b9") || suffix.contains("#9") ||
               suffix.contains("b13") || suffix.contains("#5") ||
               suffix.contains("b5")
    }

    /// 映射到 ChordFamily (供 ChordExtensionTonePool / Coloration 查询)
    var chordFamily: ChordFamily {
        switch self {
        case .major7, .add9, .six:   return .major    // ★ add9/six 归 major 族
        case .minor7:                 return .minor
        case .dominant7, .sevenSus4: return .dominant  // ★ sevenSus4 归 dominant 族
        case .halfDiminished:         return .halfDiminished
        case .diminished7:            return .diminished
        case .augmented7:             return .augmented
        case .minorMajor7:            return .minor
        case .alt:                    return .dominant
        case .sus4, .sus2:           return .sus        // ★ sus2 归 sus 族
        }
    }

    // MARK: - 音阶级数→半音偏移 (对齐 Java LickGen.makeRelativeNote)
    /// 每种和弦品质对应一张 degree→semitone 映射表 (index 0 = degree 1 = root)。
    /// 严格对齐 Java imp/lickgen/LickGen.java makeRelativeNote() 中按 chord.getFamily()
    /// 分发表的 switch(degreeValue) 语义：
    ///   major7        → Java "major"         (Ionian:          1 2 3 4 5 6 7)
    ///   minor7        → Java "minor7"        (Dorian:          1 2 b3 4 5 6 b7)
    ///   dominant7     → Java "dominant"      (Mixolydian:      1 2 3 4 5 6 b7)
    ///   halfDiminished → Java "half-diminished" (Dorian, 同 minor7: 1 2 b3 4 5 6 b7)
    ///   diminished7   → Java "diminished"    (W-H diminished:   1 2 b3 4 b5 b6 6 [7音截取])
    ///   augmented7    → Java "augmented"     (Whole-tone-ish:   1 2 3 4 #5 6 b7)
    ///   minorMajor7   → Java "minor"         (Melodic minor:    1 2 b3 4 5 6 7)
    ///   alt           → Java "dominant"      (alt 归 dominant 族)
    ///   sus4/sus2     → Java 默认 "major"    (sus 无独立族, 回退 major)
    ///   sevenSus4     → Java "dominant"      (7sus4 归 dominant 族)
    ///   add9/six      → Java "major"         (加音/六和弦归 major 族)
    var scaleDegreeSemitones: [Int] {
        switch self {
        case .major7, .add9, .six, .sus2:
            return [0, 2, 4, 5, 7, 9, 11]    // Ionian
        case .minor7, .halfDiminished:
            return [0, 2, 3, 5, 7, 9, 10]    // Dorian
        case .dominant7, .sevenSus4, .sus4, .alt:
            return [0, 2, 4, 5, 7, 9, 10]    // Mixolydian
        case .diminished7:
            return [0, 2, 3, 5, 6, 8, 9]
        case .augmented7:
            return [0, 2, 4, 5, 8, 9, 10]
        case .minorMajor7:
            return [0, 2, 3, 5, 7, 9, 11]    // Melodic minor
        }
    }
}
extension GrammarNoteConverter: ChordPitchLookupProtocol {
    static func isRootPitch(_ midi: Int, chordName: String) -> Bool {
        let pc = midi % 12
        return pc == getRootPC(chordName)
    }
    
    static func isChordTone(_ midi: Int, chordName: String) -> Bool {
        return getChordTones(chordName: chordName, minPitch: 58, maxPitch: 82).contains(midi)
    }
    
    static func isColorTone(_ midi: Int, chordName: String) -> Bool {
        return getColorTones(chordName: chordName, minPitch: 58, maxPitch: 82).contains(midi)
    }
    
    static func isScaleTone(_ midi: Int, chordName: String) -> Bool {
        return getScaleTones(chordName: chordName, minPitch: 58, maxPitch: 82).contains(midi)
    }

    // MARK: - P1-1 Approach音半音/全音趋近目标音

    /// ApproachAdvice.getPart(): 从approach音→目标和弦音的引导
    /// - Parameters:
    ///   - approachPitch: 当前趋近音MIDI
    ///   - targetChordName: 目标音所在和弦
    ///   - minPitch/maxPitch: 音域限定
    /// - Returns: 最佳目标音高 (半音距离内的和弦音)
    static func approachTargetPitch(from approachPitch: Int,
                                     targetChordName: String,
                                     minPitch: Int = 58,
                                     maxPitch: Int = 82) -> Int? {
        let chordTones = getChordTones(chordName: targetChordName, minPitch: minPitch, maxPitch: maxPitch)
        guard !chordTones.isEmpty else { return nil }

        // ApproachAdvice.getPart() L79-83: 半音上下引导, 三度范围内八度修正
        var best: Int? = nil
        var bestDistance = Int.max
        for tone in chordTones {
            for octave in [-12, 0, 12] {
                let target = tone + octave
                guard target >= minPitch && target <= maxPitch else { continue }
                let diff = abs(target - approachPitch)
                if diff < bestDistance && diff <= 3 {  // 半音/全音/小三度均视为有效趋近
                    bestDistance = diff
                    best = target
                }
            }
        }
        // 若找不到三度内的目标音, 取距离最近的和弦音 (兜底)
        if best == nil {
            for tone in chordTones {
                let target = tone  // 取最接近音域的八度
                let diff = abs(target - approachPitch)
                if diff < bestDistance {
                    bestDistance = diff
                    best = target
                }
            }
        }
        return best
    }
}
