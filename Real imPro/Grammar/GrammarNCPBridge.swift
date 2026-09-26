import Foundation

// MARK: GrammarTerminal ↔ NoteChordPair 双向转换桥接
extension GrammarTerminal {
    /// 抽象文法终结符包装为变换单元NCP
    /// 说明：GrammarTerminal仅为类型定义，实际MIDI音高由上层生成逻辑赋值，此处预留音高入口
    func toNCP(chord: ChordBlock, currentSlot: Int, midiPitch: Int = 60) -> TransformEngine.NoteChordPair {
        // 🌟 修复 1：如果是休止符，严格将 midiPitch 设为 -1，绝对不许发声！
        let actualPitch = (self.type == .rest) ? -1 : midiPitch
        let note = PhysicalNote(
            midiPitch: actualPitch,
            durationSlots: self.actualDuration,
            terminalType: self.type.rawValue
        )
        return TransformEngine.NoteChordPair(
            note: note,
            chord: chord,
            slot: currentSlot,
            transformVar: 0
        )
    }
    
    /// 批量转换文法序列，【绝对全局时间轴算法】修复和弦错位Bug，兼容跨和弦长音/切分音
    static func batchToNCP(
        terminals: [GrammarTerminal],
        chordBlocks: [ChordBlock],
        metre: [Int] = [4,4],
        slotsPerBeat: Int = 120,
        defaultMidi: Int = 60
    ) -> [TransformEngine.NoteChordPair] {
        var ncpList: [TransformEngine.NoteChordPair] = []
        guard !chordBlocks.isEmpty else { return ncpList }
        
        // 预计算所有和弦全局起始slot（绝对时间标尺）
        var chordStartSlots: [Int] = []
        var totalAccSlot = 0
        for chord in chordBlocks {
            chordStartSlots.append(totalAccSlot)
            let chordSlotCount = Int(Double(chord.duration) * Double(slotsPerBeat))
            totalAccSlot += chordSlotCount
        }
        
        var globalSlot = 0
        for term in terminals {
            // 查找当前全局时间落在哪个和弦区间
            var chordIndex = 0
            for i in 0..<chordStartSlots.count {
                if globalSlot >= chordStartSlots[i] {
                    chordIndex = i
                } else {
                    break
                }
            }
            
            let targetChord = chordBlocks[chordIndex]
            let ncp = term.toNCP(chord: targetChord, currentSlot: globalSlot, midiPitch: defaultMidi)
            ncpList.append(ncp)
            
            // 推进全局时间轴
            globalSlot += term.actualDuration
        }
        return ncpList
    }
}

// MARK: PhysicalNote（导音输出）↔ NoteChordPair 完整对接
extension PhysicalNote {
    func toNCP(chord: ChordBlock, currentSlot: Int) -> TransformEngine.NoteChordPair {
        return TransformEngine.NoteChordPair(
            note: self,
            chord: chord,
            slot: currentSlot,
            transformVar: 0
        )
    }
    
    /// 批量转换导音线条，【绝对全局时间轴算法】修复和弦错位Bug
    static func batchToNCP(
        guideToneLine: [PhysicalNote],
        chordBlocks: [ChordBlock],
        slotsPerBeat: Int = 120
    ) -> [TransformEngine.NoteChordPair] {
        var ncpList: [TransformEngine.NoteChordPair] = []
        guard !chordBlocks.isEmpty else { return ncpList }
        
        // 预计算所有和弦全局起始slot（绝对时间标尺）
        var chordStartSlots: [Int] = []
        var totalAccSlot = 0
        for chord in chordBlocks {
            chordStartSlots.append(totalAccSlot)
            let chordSlotCount = Int(Double(chord.duration) * Double(slotsPerBeat))
            totalAccSlot += chordSlotCount
        }
        
        var globalSlot = 0
        for note in guideToneLine {
            // 查找当前全局时间落在哪个和弦区间
            var chordIndex = 0
            for i in 0..<chordStartSlots.count {
                if globalSlot >= chordStartSlots[i] {
                    chordIndex = i
                } else {
                    break
                }
            }
            
            let targetChord = chordBlocks[chordIndex]
            let ncp = note.toNCP(chord: targetChord, currentSlot: globalSlot)
            ncpList.append(ncp)
            
            // 推进全局时间轴
            globalSlot += note.durationSlots
        }
        return ncpList
    }
}

// MARK: NoteChordPair 反向转回 GrammarTerminal（变换后旋律回传给文法/渲染层）
extension TransformEngine.NoteChordPair {
    func toGrammarTerminal(type: GrammarTerminalType = .chord) -> GrammarTerminal {
        let actualType: GrammarTerminalType
        if self.note.midiPitch == -1 || self.note.isRest {
            actualType = .rest
        } else if let raw = self.note.terminalType, let parsed = GrammarTerminalType(rawValue: raw) {
            actualType = parsed
        } else {
            actualType = type
        }
        return GrammarTerminal(
            type: actualType,
            durationSlots: self.note.durationSlots,
            isDotted: false,
            tuplet: 0
        )
    }
    
    static func batchToTerminals(ncpSequence: [TransformEngine.NoteChordPair], baseType: GrammarTerminalType = .chord) -> [GrammarTerminal] {
        ncpSequence.map { $0.toGrammarTerminal(type: baseType) }
    }
}
