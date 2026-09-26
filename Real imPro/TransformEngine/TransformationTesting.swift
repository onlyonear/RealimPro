import Foundation

extension TransformEngine {
    /// 对标TransformationTesting：离线调试、单元校验工具，用于验证表达式、匹配、替换结果
    struct TransformationTesting {
        /// 全局单例测试实例
        static let shared = Self()
        private init() {}
        
        // MARK: 1. 表达式求值测试入口
        func testEvaluate(expression: String, ncp: NoteChordPair? = nil) -> Double {
            var frame = Evaluate.TransformFrame()
            return Evaluate.shared.evaluate(expression, frame: &frame, ncp: ncp)
        }
        
        // MARK: 2. 单条变换匹配测试
        func testTransformationMatch(trans: Transformation, segment: [NoteChordPair]) -> Bool {
            trans.matches(segment: segment)
        }
        
        // MARK: 3. 执行单条变换替换，返回结果
        func runSingleTransformation(trans: Transformation, segment: [NoteChordPair]) -> [NoteChordPair] {
            var frame = Evaluate.TransformFrame()
            return trans.applyReplace(segment: segment, frame: &frame)
        }
        
        // MARK: 4. 整组 Substitution 测试
        func testSubstitutionApply(
            sub: Substitution,
            melody: [NoteChordPair],
            chords: [ChordBlock],
            startSlot: Int = 0,
            enforceDuration: Bool = true
        ) -> [NoteChordPair]? {
            sub.apply(melody: melody, chords: chords, startSlot: startSlot, enforceDuration: enforceDuration)
        }
        
        // MARK: 5. 完整变换流水线全流程测试
        func runFullTransformPipeline(
            transform: Transform,
            melody: [NoteChordPair],
            chords: [ChordBlock],
            metre: [Int] = [4, 4],
            enforceDuration: Bool = true
        ) -> [NoteChordPair] {
            var mutableTransform = transform
            return mutableTransform.applyAllTransformations(
                ncpSequence: melody,
                chordBlocks: chords,
                metre: metre,
                enforceDuration: enforceDuration
            )
        }
        
        // MARK: 6. 片段打分测试（修正参数名错误）
        func scoreSegment(trend: [NoteChordPair], metre: [Int] = [4, 4]) -> Double {
            let scorer = Scorer(
                priorityWeight: 1.0,
                beatWeight: 1.0,
                durationWeight: 1.0,
                metre: metre
            )
            return scorer.score(trend: trend)
        }
        
        // MARK: 快速构造测试用 NCP 辅助方法
        func makeTestNCP(pitch: Int, duration: Int, chord: ChordBlock) -> NoteChordPair {
            let note = PhysicalNote(midiPitch: pitch, durationSlots: duration)
            return NoteChordPair(note: note, chord: chord)
        }
    }
}
