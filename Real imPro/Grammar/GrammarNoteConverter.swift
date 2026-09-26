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
    
    // MARK: - Garzone Triadic 状态缓存 (Outside Playing 引擎)
    private static let ROOT_STORAGE_NUMBER = 6
    private static var triadicRecentRoots = Array(repeating: -1, count: ROOT_STORAGE_NUMBER)
    private static var triadicRecentTypes = Array(repeating: 0, count: ROOT_STORAGE_NUMBER + 1) // 5=maj, 6=min, 7=dim, 8=aug
    private static var triadicRootCounter = 0
    private static var triadicLastInversion = 0
    
    // MARK: - 转换
    
    static func convert(
        abstractMelody: [GrammarTerminal],
        roadmap: JazzRoadmap,
        grammarParameters: [String: Any],
        beatsPerMeasure: Int = 4
    ) -> [PhysicalNote] {
        var result: [PhysicalNote] = []
        
        // 读取文法定义音域，适配 CharlieParker (min-pitch 58, max-pitch 82)
        let globalMinPitch = grammarParameters["min-pitch"] as? Int ?? 58
        let globalMaxPitch = grammarParameters["max-pitch"] as? Int ?? 82
        
        // M5: 读取expectancy参数，控制方向连续性偏好强度 (0=禁用, 默认0)
        _expectancyBridge = grammarParameters["expectancy-multiplier"] as? Double ?? 0.0
        
        // 展平 roadmap，获取和弦序列
        let chordBlocks = roadmap.flattenRoadmap()
        
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
        
        var skipNext = false
        for (idx, terminal) in abstractMelody.enumerated() {
            if skipNext { skipNext = false; continue }
            if terminal.type == .approach {
                #if DEBUG
                print("【APPROACH-ARRIVAL】 slot=\(currentSlot) beat=\(currentSlot/120) idx=\(idx)")
                #endif
            }
            // 找到当前位置的和弦
            let currentChord = findChordAt(slot: currentSlot, chordBlocks: chordBlocks)
            
            // 🔍 排查日志: 和弦切换时打印基准音列表 (每个和弦只打一次)
            if currentSlot == 0 || currentChord != _lastLoggedChord {
                _lastLoggedChord = currentChord
                let tones = getChordTones(chordName: currentChord, minPitch: globalMinPitch, maxPitch: globalMaxPitch)
                logChordTones(currentChord, tones)
            }
            
            // ========== slope 特殊处理：一个终结符生成多个音符 ==========
            if terminal.type == .slope, let notes = terminal.slopeNotes,
               let minSlope = terminal.minSlope, let maxSlope = terminal.maxSlope {
                
                // 🔍 slope全链路追踪
                #if DEBUG
                print("【SLOPE-ENTER】 minSlope=\(minSlope) maxSlope=\(maxSlope) lastPitch=\(lastPitch) chord=\(currentChord) noteCount=\(notes.count)")
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
                            print("【SLOPE-FIXED】 type=\(innerNote.type.rawValue) fixedPitch=\(fixedPitch) slope=[0,0]")
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
                            
                            // 2. 反推 approach 音（调用公共方法）
                            let approachFromBelow: Bool = {
                                if targetPitch < lastPitch { return false }
                                if maxSlope < 0 && minSlope < 0 { return false }
                                return true
                            }()
                            
                            var approachPitch = deriveApproachPitch(targetPitch: targetPitch, chordName: targetChord,
                                                                     lastPitch: lastPitch, preferBelow: approachFromBelow)
                            
                            let appInterval = abs(approachPitch - targetPitch)
                            let appWarning = appInterval > 2 ? "⚠️ ANOMALY" : "  OK"
                            #if DEBUG
                            print("【APPROACH-DIAG】\(appWarning) chord=\(targetChord) target=\(targetPitch) app=\(approachPitch) intv=\(appInterval)")
                            #endif
                            
                            approachPitch = max(36, min(96, approachPitch))
                            
                            // 4. 添加 approach 音符
                            let approachNote = PhysicalNote(midiPitch: approachPitch, durationSlots: innerNote.actualDuration, terminalType: innerNote.type.rawValue)
                            #if DEBUG
                            print("【SLOPE-APPROACH】 pitch=\(approachPitch) targetPitch=\(targetPitch) slope=[\(minSlope),\(maxSlope)]")
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
                            // 没有下一个音符：随机选一个音阶音作为 approach 音
                            let scalePitches = getScaleTones(chordName: innerChord, minPitch: globalMinPitch, maxPitch: globalMaxPitch)
                            let pitch = scalePitches.randomElement() ?? lastPitch
                            
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
                        print("【SLOPE-NOTE】 type=\(innerNote.type.rawValue) chord=\(innerChord) pitch=\(pitch) slope=[\(minSlope),\(maxSlope)] lastPitch=\(lastPitch)")
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
            // ========== triadic 特殊处理：单个标记裂变根/三/五3个分解音 ==========
            if terminal.type == .triadic {
                // 调用 Garzone 高级三和弦半音阶引擎 (Outside Playing)
                // 注意：它完全抛弃了 currentChord，直接以 lastPitch 为起点进行半音游走
                let triadicPitches = getTriadicTones(
                    referencePitch: lastPitch,
                    minPitch: globalMinPitch,
                    maxPitch: globalMaxPitch
                )
                let totalSlots = terminal.actualDuration
                // 平分总时值，余数全部给最后一个音保证时长精确对齐
                let baseSlot = totalSlots / 3
                let remainSlot = totalSlots % 3
                
                // 循环生成琶音分解音符
                for (idx, pitch) in triadicPitches.enumerated() {
                    let realDur = idx == 2 ? baseSlot + remainSlot : baseSlot
                    let note = PhysicalNote(midiPitch: pitch, durationSlots: realDur, terminalType: terminal.type.rawValue)
                    result.append(note)
                    
                    // 更新走向、最近音缓存
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
                }
                // 时间轴一次性推进全部时长，跳过下方单音生成逻辑
                currentSlot += totalSlots
                continue
            }
            // ========== triadic 处理结束 ==========
            
            // 诊断: 记录所有趋近音终端的到达
            if terminal.type == .approach {
                #if DEBUG
                print("【APPROACH-TERMINAL】 slot=\(currentSlot) beat=\(currentSlot/120) chord=\(currentChord) idx=\(idx)")
                #endif
            }
            
            // ========== Path B 趋近音预读配对 ==========
            if terminal.type == .approach, idx + 1 < abstractMelody.count {
                #if DEBUG
                print("【PATHB-APPROACH】 slot=\(currentSlot) beat=\(currentSlot/120) chord=\(currentChord)")
                #endif
                let next = abstractMelody[idx + 1]
                if next.type != .slope && next.type != .triadic {
                    let targetSlot = currentSlot + terminal.actualDuration
                    let targetChord = findChordAt(slot: targetSlot, chordBlocks: chordBlocks)
                    
                    // 对齐 Java: 强制 A 的目标音为和弦音 (LickGen:2295 "nextType = CHORD")
                    let chordNext = GrammarTerminal(
                        type: .chord,
                        durationSlots: next.durationSlots,
                        isDotted: next.isDotted,
                        tuplet: next.tuplet
                    )
                    let targetPitch = selectPitch(terminal: chordNext, chordName: targetChord,
                        lastPitch: lastPitch, minPitch: globalMinPitch, maxPitch: globalMaxPitch)
                    
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
                    
                    let appPitch = deriveApproachPitch(targetPitch: targetPitch, chordName: targetChord,
                                                        lastPitch: lastPitch, preferBelow: targetPitch >= lastPitch)
                    
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
            if let smin = terminal.slopeMin, let smax = terminal.slopeMax {
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
            //print("【音高选择过程】 和弦=\(currentChord) terminalType=\(terminal.type.rawValue)(\(terminal.type)) 候选范围=[\(globalMinPitch)-\(globalMaxPitch)] → 选中=\(nn[pc])\(oct)(midi\(pitch)) lastPitch=\(lastPitch)")
            
            // 创建物理音符
            if terminal.type != .rest {
                let note = PhysicalNote(
                    midiPitch: pitch,
                    durationSlots: terminal.actualDuration,
                    terminalType: terminal.type.rawValue
                )
                // 🔍 排查日志: PhysicalNote创建
                //print("【PhysicalNote创建】 midi=\(pitch) 音名=\(nn[pc])\(oct) 时值=\(terminal.actualDuration)slots terminalType=\(terminal.type.rawValue)")
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
            //print("=== 最终音符音高范围 ===")
            //print("最小MIDI: \(allMidi.min() ?? 0), 最大MIDI: \(allMidi.max() ?? 0)")
            //print("低于48的超低音数量: \(allMidi.filter { $0 < 48 }.count)")
            if let minPitch = allMidi.min() {
                //print("最低音MIDI: \(minPitch)")
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
                    print("⚠️ [APPROACH-GAP] app=\(pa) next=\(note.midiPitch) gap=\(gap) nextType=\(note.terminalType)")
                    #endif
                }
                paPitch = nil
            }
        }
        
        // avoidRepeats: rest合并 + 同音合并，对齐 Java LickGen.addNote()
        #if DEBUG
        print("  [MERGE-PASS] result count=\(result.count)")
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
                print("  [MERGE] pitch=\(last.midiPitch) dur=\(last.durationSlots)+\(note.durationSlots) lastType=\(last.terminalType ?? "nil") nowType=\(note.terminalType ?? "nil")")
                #endif
            } else {
                if note.terminalType != "R", last.terminalType != "R", note.midiPitch == last.midiPitch {
                    #if DEBUG
                    print("❌ [MERGE-FAIL] samePitch notMerged! last=\(last.midiPitch)(\(last.terminalType ?? "nil")) dur=\(last.durationSlots) now=\(note.midiPitch)(\(note.terminalType ?? "nil")) dur=\(note.durationSlots)")
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
                print("⚠️ [POST-SCAN-A] slot=\(scanSlot) beat=\(scanSlot/120) pitch=\(note.midiPitch) dur=\(note.durationSlots)")
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
                    print("⚠️ [APPROACH-GAP] app=\(pa) next=\(note.midiPitch) gap=\(gap) nextType=\(note.terminalType)")
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
        // 根据终结符类型选择不同的音高集合
        let candidatePitches: [Int]
        
        switch terminal.type {
        case .chord:
            // 纯和弦音（根、三、五、七）
            candidatePitches = getChordTones(chordName: chordName, minPitch: minPitch, maxPitch: maxPitch)
            
        case .highColor:
            // M1: 高色彩音 — 倾向音域上半区 + NoteChooser概率选池
            let chordTones = getChordTones(chordName: chordName, minPitch: minPitch, maxPitch: maxPitch)
            let colorTones = getColorTones(chordName: chordName, minPitch: minPitch, maxPitch: maxPitch)
            let midPitch = (minPitch + maxPitch) / 2
            let highColors = colorTones.filter { $0 >= midPitch }
            let pool = highColors.isEmpty ? colorTones : highColors
            return selectWithNoteChooser(
                chordPool: chordTones, colorPool: pool,
                chordName: chordName, lastPitch: lastPitch,
                minPitch: minPitch, maxPitch: maxPitch,
                terminal: terminal
            )
            
        case .lowColor:
            // M1: 低色彩音 — 倾向音域下半区 + NoteChooser概率选池
            let chordTones = getChordTones(chordName: chordName, minPitch: minPitch, maxPitch: maxPitch)
            let colorTones = getColorTones(chordName: chordName, minPitch: minPitch, maxPitch: maxPitch)
            return selectWithNoteChooser(
                chordPool: chordTones, colorPool: colorTones,
                chordName: chordName, lastPitch: lastPitch,
                minPitch: minPitch, maxPitch: maxPitch,
                terminal: terminal
            )

        case .midColor:
            // 调式音阶音 / 中色彩音
            candidatePitches = getScaleTones(chordName: chordName, minPitch: minPitch, maxPitch: maxPitch)
            
        case .approach:
            // 经过音/邻音：和弦音上下半音/全音
            candidatePitches = getApproachTones(chordName: chordName, minPitch: minPitch, maxPitch: maxPitch)
            #if DEBUG
            print("【APPROACH-FALLBACK】 chord=\(chordName) lastPitch=\(lastPitch) poolSize=\(candidatePitches.count)")
            #endif
            
        case .arbitrary, .outside:
            // 任意音/外音，暂时用音阶音
            candidatePitches = getScaleTones(chordName: chordName, minPitch: minPitch, maxPitch: maxPitch)
            
        case .scaleDegree:
            // 音阶级数：直接根据级数计算具体音高
            if let degree = terminal.scaleDegree {
                let pitch = getPitchFromScaleDegree(degree: degree, chordName: chordName, lastPitch: lastPitch)
                return pitch
            }
            candidatePitches = getScaleTones(chordName: chordName, minPitch: minPitch, maxPitch: maxPitch)
            
        case .slope:
            // slope 类型暂时返回 0，后面专门处理
            return 0
            
        case .triadic:
            // triadic 已在外层convert函数提前拦截拆分为3个分解音，不会进入本函数，直接return占位补齐枚举
            return 0
            
        case .rest:
            // 休止符，返回 0
            return 0
        }
        
        // 选择离上一个音最近的 (ExpectancyCore动态评分 + NoteChooser静态查表兜底)
        return getClosestPitch(targetPitches: candidatePitches, referencePitch: lastPitch, lastPitch: lastPitch, terminal: terminal)
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

        // 大跳区间放宽标记
        let relaxConstraints = abs(minSlope) >= 6 || abs(maxSlope) >= 6
        if relaxConstraints {
            lowerBound -= 3
            upperBound += 3
        }

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
            
        case .lowColor:
            // L: 低色彩音 - 优先下线音域
            targetPool = validColor.isEmpty ? validChord : Array(validColor.filter { $0 <= (lowerBound + upperBound) / 2 })
            if targetPool.isEmpty { targetPool = validColor.isEmpty ? validChord : validColor }
            
        case .midColor:
            // S: 中音域音阶/色彩音
            targetPool = validScale
            
        case .highColor:
            // H: 高色彩音 - 优先上线音域
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

        // 防连续同音、防近期重复过滤
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

        // P0-1: Trend主动生成注入 — 缓存Trend音池, 后续在Expectancy循环中权重加倍
        let trendSet: Set<Int> = {
            guard let trendSeg = _pendingTrendSegment else { return [] }
            let pool = trendSeg.generateNotePool(for: ChordBlock(name: chordName, duration: 0))
            return Set(pool)
        }()

        // ------------- 嵌入Expectancy + 标准轮盘赌加权抽样 -------------
        var scoredCandidates: [(pitch: Int, score: Double)] = []
        var totalExpectancyScore = 0.0
        // 取上上音作为expectancy第二历史音
        let prevPrevPitch = recentPitches.count >= 2 ? recentPitches[recentPitches.count - 2] : lastPitch
        
        // 1. 遍历全部候选音，计算期望值，规避负数概率
        for pitch in candidatePool {
            let rawScore = ExpectancyCore.computeExpectancyScore(
                candidatePitch: pitch,
                prevPitch: lastPitch,
                prevPrevPitch: prevPrevPitch,
                chordName: chordName,
                lookup: GrammarNoteConverter.self
            )
            // 双重兜底：极低分数强制上浮，保证外音/大跳有极小概率触发
            var safeScore = max(rawScore, 0.001)
            // 低于0.05的低分音小幅抬升权重，避免完全消失
            if safeScore < 0.05 {
                safeScore = 0.05
            }
            // P0-1: Trend音池权重加倍
            if trendSet.contains(pitch) { safeScore *= 2.0 }
            scoredCandidates.append((pitch: pitch, score: safeScore))
            totalExpectancyScore += safeScore
        }

        // 兜底：候选池为空直接返回上一个音
        guard !scoredCandidates.isEmpty else {
            return lastPitch
        }

        // 2. 轮盘赌随机落点
        let randomSpin = Double.random(in: 0..<totalExpectancyScore)
        var cumulativeScore = 0.0
        var pickedPitch = scoredCandidates.first!.pitch

        for entry in scoredCandidates {
            cumulativeScore += entry.score
            if randomSpin <= cumulativeScore {
                pickedPitch = entry.pitch
                break
            }
        }

        // 🔍 排查日志: selectPitch候选音池
        let nn2 = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        let candNames = targetPool.map { m in
            let p = ((m % 12) + 12) % 12; let o = (m / 12) - 1
            return "\(nn2[p])\(o)(midi\(m))"
        }
        #if DEBUG
        print("【selectPitch候选池】 和弦=\(chordName) terminalType=\(terminal.type.rawValue) targetPool=[\(candNames.joined(separator:", "))] → 选中=\(nn2[((pickedPitch%12)+12)%12])\((pickedPitch/12)-1)(midi\(pickedPitch))")
        #endif
        
        return pickedPitch
    }
    // MARK: - 获取和弦音
    
    private static func getChordTones(chordName: String, minPitch: Int, maxPitch: Int) -> [Int] {
        let cleanName = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootPC = getRootPC(cleanName)
        
        // 由枚举引擎统一提供精确的根三五七音程
        let quality = ChordQuality(chordName: cleanName)
        let intervals = quality.chordIntervals
        
        var validPitches: [Int] = []
        
        for interval in intervals {
            let targetPC = (rootPC + interval) % 12
            // 限制在传入的动态音区
            for octave in stride(from: (minPitch/12)*12, through: (maxPitch/12)*12, by: 12) {
                let pitch = targetPC + octave
                if pitch >= minPitch && pitch <= maxPitch {
                    validPitches.append(pitch)
                }
            }
        }
        
        return validPitches.isEmpty ? [60] : validPitches.sorted()
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
        //print("【和弦基准音列表】 和弦=\(chordName) 数量=\(tones.count) → [\(names.joined(separator:", "))]")
    }
    
    // MARK: - 获取色彩音（延伸音：9、11、13）
    
    private static func getColorTones(chordName: String, minPitch: Int, maxPitch: Int) -> [Int] {
        let cleanName = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootPC = getRootPC(cleanName)
        
        // 获取该和弦专用的色彩音池 (包含 Altered 张力音)
        let quality = ChordQuality(chordName: cleanName)
        let colorIntervals = quality.colorIntervals(for: cleanName)
        
        var validPitches: [Int] = []
        
        for interval in colorIntervals {
            let targetPC = (rootPC + interval) % 12
            for octave in stride(from: (minPitch/12)*12, through: (maxPitch/12)*12, by: 12) {
                let pitch = targetPC + octave
                if pitch >= minPitch && pitch <= maxPitch {
                    validPitches.append(pitch)
                }
            }
        }
        
        return validPitches.sorted()
    }
    
    // MARK: - 获取音阶音（大调音阶/小调音阶，第一阶段先简单处理）
    
    private static func getScaleTones(chordName: String, minPitch: Int, maxPitch: Int) -> [Int] {
        let cleanName = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootPC = getRootPC(cleanName)
        
        // 使用强类型的质量枚举获取对应的爵士音阶
        let quality = ChordQuality(chordName: cleanName)
        let scaleIntervals = quality.scaleIntervals
        
        var validPitches: [Int] = []
        
        for interval in scaleIntervals {
            let targetPC = (rootPC + interval) % 12
            for octave in stride(from: (minPitch/12)*12, through: (maxPitch/12)*12, by: 12) {
                let pitch = targetPC + octave
                if pitch >= minPitch && pitch <= maxPitch {
                    validPitches.append(pitch)
                }
            }
        }
        
        return validPitches.sorted()
    }
    
    // MARK: - 趋近音反推公共方法（给定目标音高 → 下方半音 / 上方音阶音）
    
    private static func deriveApproachPitch(
        targetPitch: Int, chordName: String, lastPitch: Int, preferBelow: Bool
    ) -> Int {
        let scaleTones = getScaleTones(chordName: chordName, minPitch: targetPitch, maxPitch: targetPitch + 3)
        let diatonicUpper = scaleTones.first(where: { $0 > targetPitch }) ?? (targetPitch + 2)
        let chromaticLower = targetPitch - 1
        var fromBelow = preferBelow
        if fromBelow && chromaticLower == lastPitch { fromBelow = false }
        else if !fromBelow && diatonicUpper == lastPitch { fromBelow = true }
        var result = fromBelow ? chromaticLower : diatonicUpper
        if abs(result - targetPitch) > 2 {
            result = targetPitch - 1
            if result == lastPitch { result = targetPitch - 2 }
        }
        return result
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
            print("⚠️ [APPROACH-POOL] chord=\(chordName) pool=\(approachPitches.sorted()) anomalies=[\(anomalies.joined(separator: "; "))]")
            #endif
        } else {
            #if DEBUG
            print("  [APPROACH-POOL] chord=\(chordName) pool=\(approachPitches.sorted())")
            #endif
        }
        
        return Array(approachPitches).filter { $0 >= minPitch && $0 <= maxPitch }.sorted()
    }
    
    // MARK: - Triadic 三和弦分解音池 (Garzone 随机半音阶趋近理论)
    /// 核心升级：完全抛弃底层和弦束缚，基于半音游走、随机转位与八度错位，生成现代爵士的 Outside 线条
    private static func getTriadicTones(referencePitch: Int, minPitch: Int, maxPitch: Int) -> [Int] {
        // 1. 获取下一个基准音（以上一个音为基准，随机上下半音游走）
        let basePitch = getGarzoneBase(referencePitch: referencePitch, minPitch: minPitch, maxPitch: maxPitch)
        
        // 2. 基于游走到的基准音，生成高度错位和变形的随机三和弦
        return makeGarzoneTriad(basePitch: basePitch, minPitch: minPitch, maxPitch: maxPitch)
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
    
    private static func getRootPC(_ name: String) -> Int {
        let normalized = name
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "♯", with: "#")
        let chars = Array(normalized)
        guard !chars.isEmpty else { return 0 }
        var rootStr = String(chars[0]).uppercased()
        if chars.count > 1 && (chars[1] == "#" || chars[1] == "b") { rootStr.append(chars[1]) }
        let pcMap: [String: Int] = ["C": 0, "C#": 1, "Db": 1, "D": 2, "Eb": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "Ab": 8, "A": 9, "Bb": 10, "B": 11]
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
        
        // 目标类型: chord→CHORD, color→COLOR
        let targetType: Int
        switch terminal.type {
        case .lowColor, .highColor: targetType = NoteChooser.COLOR
        default:                  targetType = NoteChooser.CHORD
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
            
            // 反向惩罚：色彩音/延伸音减半，提升爵士色彩中性生成概率≈2倍
            if lastDirection != 0 && direction != lastDirection {
                let isColorType = terminal?.type == .lowColor || terminal?.type == .highColor
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
        let typeMap: [GrammarTerminalType: Int] = [.chord: 1, .lowColor: 1, .highColor: 1, .midColor: 3, .arbitrary: 3, .approach: 1, .outside: 3]
        let lookupType = typeMap[terminal.type] ?? 0
        let rule = NoteChooser.probabilityTable.first { $0.type == lookupType && $0.hChord == 1 } ?? NoteChooser.probabilityTable[0]
        let probs = [rule.pChord, rule.pColor, rule.pRandom, rule.pScale]
        return Double(probs.max() ?? 100) / 100.0
    }

    // MARK: - Scale Degree 音高计算
    
    /// 根据音阶级数计算具体音高
    /// - Parameters:
    ///   - degree: 级数字符串，如 "3", "b5", "#9", "b13"
    ///   - chordName: 和弦名称
    ///   - lastPitch: 上一个音的音高（用于选择合适的八度）
    /// - Returns: 具体的 MIDI 音高
    private static func getPitchFromScaleDegree(degree: String, chordName: String, lastPitch: Int) -> Int {
        let rootPC = getRootPC(chordName)
        
        // 1. 先解析级数，得到相对于根音的半音数（大调音阶基准）
        let semitoneOffset = parseScaleDegree(degree)
        
        // 2. 计算目标音高类（0-11）
        let targetPC = (rootPC + semitoneOffset + 120) % 12
        
        // 3. 选择离上一个音最近的八度
        var bestPitch = 60 + targetPC  // 默认中央C八度
        var minDistance = Int.max
        
        for octave in [36, 48, 60, 72, 84] {  // 多个八度候选
            let pitch = octave + targetPC
            if pitch >= 48 && pitch <= 84 {  // 合理音域
                let distance = abs(pitch - lastPitch)
                if distance < minDistance {
                    minDistance = distance
                    bestPitch = pitch
                }
            }
        }
        
        return bestPitch
    }
    
    /// 解析音阶级数字符串，返回相对于根音的半音数（大调音阶基准）
    /// 支持："1", "b2", "2", "b3", "3", "4", "#4", "5", "b6", "6", "b7", "7", "8", "9", "#9", "b9", "11", "#11", "13", "b13"
    private static func parseScaleDegree(_ degree: String) -> Int {
        let deg = degree.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 大调音阶中各音级相对于根音的半音数
        let majorScaleDegrees: [String: Int] = [
            "1": 0, "8": 0, "15": 0,
            "2": 2, "9": 14,
            "3": 4, "10": 16,
            "4": 5, "11": 17,
            "5": 7, "12": 19,
            "6": 9, "13": 20,
            "7": 11, "14": 23
        ]
        
        // 判断升降号
        var accidental = 0
        var numStr = deg
        
        if deg.hasPrefix("b") || deg.hasPrefix("♭") {
            accidental = -1
            numStr = String(deg.dropFirst())
        } else if deg.hasPrefix("#") || deg.hasPrefix("♯") {
            accidental = 1
            numStr = String(deg.dropFirst())
        }
        
        // 查找基础级数
        if let baseSemitones = majorScaleDegrees[numStr] {
            return baseSemitones + accidental
        }
        
        // 如果解析失败，默认返回根音
        return 0
    }
}
// MARK: - 爵士和弦品质与音程映射引擎 (DeepSeek 修正黄金谱系版)
enum ChordQuality {
    case major7, minor7, dominant7, halfDiminished, diminished7, augmented7, minorMajor7, alt, sus

    init(chordName: String) {
        let name = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerName = name.lowercased()
        
        // 1. 优先匹配复合词或长后缀，防止短字符（如 m 或 dim）贪婪劫持
        // 注意: maj7/M7 必须在 m 之前检测，否则 Cmaj7 会被 "m" 误捕获
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
        } else if lowerName.contains("sus") {
            self = .sus
        } else if lowerName.contains("m") && !lowerName.contains("dom") {
            self = .minor7
        } else if lowerName.contains("6") {
            self = .major7
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
        case .sus:           return [0, 5, 7]         // 纯四度挂留，无三音
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
        case .sus:           return [0, 2, 5, 7, 9, 10]       // Mixolydian (sus 属七替代)
        }
    }

    // 色彩延伸音 (与 ChordExtensionTonePool 统一，chordName 区分属七 alt)
    func colorIntervals(for chordName: String) -> [Int] {
        switch self {
        case .alt:           return [1, 3, 6, 8]             // b9, #9, #11, b13 (alt 特化)
        case .halfDiminished:return [2, 5, 8]             // 9, 11, b13
        case .augmented7:    return [2, 6]                // 9, #11 (增三特化)
        case .dominant7:     
            return hasAlteredIndicators(chordName)
                ? ChordExtensionTonePool.tonesFor(.dominant)
                : ChordExtensionTonePool.primaryTonesFor(.dominant)
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
        case .major7:        return .major
        case .minor7:        return .minor
        case .dominant7:     return .dominant
        case .halfDiminished:return .halfDiminished
        case .diminished7:   return .diminished
        case .augmented7:    return .augmented
        case .minorMajor7:   return .minor
        case .alt:           return .dominant
        case .sus:           return .sus
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
