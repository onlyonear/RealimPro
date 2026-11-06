import Foundation

// MARK: 独立变换模块命名空间，与主引擎完全解耦
enum TransformEngine {}

// MARK: 旋律最小单元封装：音符+对应和弦+位置+变换变量
extension TransformEngine {
    /// 对应原版Java NoteChordPair
    struct NoteChordPair: Equatable {
        static private let NO_VAR: Int = -1
        
        let note: PhysicalNote
        let chord: ChordBlock
        let slot: Int
        let transformVar: Int
        
        // 基础构造器
        init(note: PhysicalNote, chord: ChordBlock, slot: Int, transformVar: Int = Self.NO_VAR) {
            self.note = note
            self.chord = chord
            self.slot = slot
            self.transformVar = transformVar
        }
        
        /// 仅音符+和弦，默认slot=0、无变量
        init(note: PhysicalNote, chord: ChordBlock) {
            self.init(note: note, chord: chord, slot: 0, transformVar: Self.NO_VAR)
        }
        
        /// 音符+和弦+指定slot，无变量
        init(note: PhysicalNote, chord: ChordBlock, slot: Int) {
            self.init(note: note, chord: chord, slot: slot, transformVar: Self.NO_VAR)
        }
        
        /// 深拷贝（音符/和弦均复制副本，防止变换修改原始数据）
        func copy() -> Self {
            let copiedNote = PhysicalNote(
                midiPitch: self.note.midiPitch,
                durationSlots: self.note.durationSlots,
                terminalType: self.note.terminalType
            )
            // ChordBlock 若支持拷贝则调用copy()，无拷贝构造则复用（只读不修改）
            let copiedChord = self.chord
            return Self(note: copiedNote, chord: copiedChord, slot: self.slot, transformVar: self.transformVar)
        }
        
        // MARK: 对外只读访问接口（对齐原版getter）
        func getNote() -> PhysicalNote { note }
        func getChord() -> ChordBlock { chord }
        func getSlot() -> Int { slot }
        func getVar() -> Int { transformVar }
        
        mutating func setSlot(_ newSlot: Int) {
            self = Self(note: self.note, chord: self.chord, slot: newSlot, transformVar: self.transformVar)
        }
        
        mutating func setVar(_ newVar: Int) {
            self = Self(note: self.note, chord: self.chord, slot: self.slot, transformVar: newVar)
        }
        
        /// 获取当前音符时值（slots）
        func getDuration() -> Int {
            note.durationSlots
        }
        
        /// 修改时值，返回全新副本（不修改原实例）
        func setDuration(_ newSlots: Int) -> Self {
            let newNote = PhysicalNote(midiPitch: note.midiPitch, durationSlots: newSlots, terminalType: note.terminalType)
            return Self(note: newNote, chord: chord, slot: slot, transformVar: transformVar)
        }
        
        /// 获取相对音名字符串（对接 RelativePitchTools）
        func getRelativePitch() -> String {
            if note.midiPitch == -1 {
                return "0"
            }
            return RelativePitchTools.relativePitch(
                midiPitch: note.midiPitch,
                chordName: chord.name
            )
        }
        
        /// 获取变量标识字符串 nX
        func varName() -> String {
            "n\(transformVar)"
        }
    }
}
