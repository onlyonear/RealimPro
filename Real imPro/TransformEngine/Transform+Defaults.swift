import Foundation

// MARK: - 默认变换规则
extension TransformEngine.Transform {
    
    /// 最小时值：30 slots = 十六分音符，避免生成过短的音符
    /// （已在 Transformation.matches 和 applyReplace 中双重保护）
    
    /// 创建包含默认变换规则的 Transform 实例
    static func makeDefault() -> Self {
        var transform = Self()
        
        // ==========================================
            // 第一阶段：Motif 动机级变换（大结构）
            // ==========================================

            // identity-motif: 不做动机变换，权重1 (对齐原版)
            transform.addMotifSubstitution(makeIdentityMotif())

            // passing-tone: 经过音，权重5 (对齐原版)
            transform.addMotifSubstitution(makePassingToneMotif())

            // split-half: 拆分二分音符，权重1
            transform.addMotifSubstitution(makeSplitHalfMotif())

            // split-whole: 拆分全音符，权重5 (对齐原版)
            transform.addMotifSubstitution(makeSplitWholeMotif())

            // P1: 长音拆分规则 (密度增强)
            transform.addMotifSubstitution(makeSplitHalfToEighths())
            transform.addMotifSubstitution(makeSplitHalfToEQQ())
            transform.addMotifSubstitution(makeSplitDottedQuarterToEighths())
            transform.addMotifSubstitution(makeSplitEighthToSixteenths())
            transform.addMotifSubstitution(makePassingToneSplit())

            // triplet-arpeggio: 三连音琶音，权重4 (对齐原版)
            transform.addMotifSubstitution(makeTripletArpeggioMotif())

            // ==========================================
            // 第二阶段：Embellishment 装饰音级变换（小细节）
            // ==========================================

            // identity-embellishment: 不做装饰，权重10 (对齐原版)
            transform.addEmbellishmentSubstitution(makeIdentityEmbellishment())

            // mordent/neighbors: 邻音/波音，权重1
            transform.addEmbellishmentSubstitution(makeMordentEmbellishment())

            // gracenote: 倚音，权重1
            transform.addEmbellishmentSubstitution(makeGracenoteEmbellishment())

            // split-quarter: 拆分四分音符，权重4 (对齐原版)
            transform.addEmbellishmentSubstitution(makeSplitQuarterEmbellishment())

            // triplet-embellish: 三连音装饰，权重4 (对齐原版)
            transform.addEmbellishmentSubstitution(makeTripletEmbellishment())

            // add-rests: 添加呼吸休止，权重1
            transform.addEmbellishmentSubstitution(makeAddRestsEmbellishment())

            // P0-2 新补全: Approach音/邻音/双经过音装饰规则
            // approach-chromatic: 半音趋近装饰，权重2
            transform.addEmbellishmentSubstitution(makeApproachChromaticEmbellishment())
            // neighbor-lower: 下邻音装饰，权重2
            transform.addEmbellishmentSubstitution(makeNeighborLowerEmbellishment())
            // neighbor-upper: 上邻音装饰，权重2
            transform.addEmbellishmentSubstitution(makeNeighborUpperEmbellishment())
            // double-passing: 双经过音填充，权重2
            transform.addEmbellishmentSubstitution(makeDoublePassingEmbellishment())

            // P1: grace-approach装饰, 权重2
            transform.addEmbellishmentSubstitution(makeGraceApproach())

        // 诊断: 打印所有Motif替换规则
        //print("=== 加载的Motif替换规则 ===")
        for sub in transform.motifSubstitutions {
            for t in sub.transformations {
                //print("规则[\(sub.name)]: expr=\(t.replaceExpressions) wt=\(sub.weight)")
            }
        }
        //print("===========================")

        return transform
    }
    
    // MARK: - ========== Motif 动机级变换 ==========
    
    private static func makeIdentityMotif() -> TransformEngine.Substitution {
        // identity变换：匹配任何单个音符，原样返回
        let anyNote = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 60, durationSlots: 30),
            chord: ChordBlock(name: "C", duration: 1.0),
            slot: 0,
            transformVar: 0
        )
        
        let identity = TransformEngine.Transformation(
            guardCondition: nil,
            isEnabled: true,
            weight: 1.0,
            matchTemplate: [anyNote],
            replaceExpressions: ["n1"]  // 原样返回
        )
        
        var sub = TransformEngine.Substitution(
            name: "identity-motif",
            subType: "motif",
            weight: 1
        )
        sub.addTransformation(identity)
        return sub
    }
    
    /// 在合适的音程之间插入经过音
    private static func makePassingToneMotif() -> TransformEngine.Substitution {
        var sub = TransformEngine.Substitution(
            name: "passing-tone",
            subType: "motif",
            weight: 5
        )
        
        // 半音经过音模板：两个音相差2半音
        let n1 = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 60, durationSlots: 60),
            chord: ChordBlock(name: "C", duration: 1.0),
            slot: 0, transformVar: 0
        )
        let n2 = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 62, durationSlots: 60),
            chord: ChordBlock(name: "C", duration: 1.0),
            slot: 0, transformVar: 0
        )
        
        // 上行半音经过音
        let chromaticUp = TransformEngine.Transformation(
            guardCondition: "(= (- n2 n1) 2)",
            isEnabled: true, weight: 1.0,
            matchTemplate: [n1, n2],
            replaceExpressions: ["n1", "(+ n1 1)", "n2"]
        )
        
        // 下行半音经过音
        let chromaticDown = TransformEngine.Transformation(
            guardCondition: "(= (- n1 n2) 2)",
            isEnabled: true, weight: 1.0,
            matchTemplate: [n2, n1],
            replaceExpressions: ["n1", "(- n1 1)", "n2"]
        )
        
        // 全音经过音模板：两个音相差4半音（大三度）
        let n3 = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 60, durationSlots: 60),
            chord: ChordBlock(name: "C", duration: 1.0),
            slot: 0, transformVar: 0
        )
        let n4 = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 64, durationSlots: 60),
            chord: ChordBlock(name: "C", duration: 1.0),
            slot: 0, transformVar: 0
        )
        
        // 上行全音经过音
        let diatonicUp = TransformEngine.Transformation(
            guardCondition: "(= (- n2 n1) 4)",
            isEnabled: true, weight: 1.0,
            matchTemplate: [n3, n4],
            replaceExpressions: ["n1", "(+ n1 2)", "n2"]
        )
        
        // 下行全音经过音
        let diatonicDown = TransformEngine.Transformation(
            guardCondition: "(= (- n1 n2) 4)",
            isEnabled: true, weight: 1.0,
            matchTemplate: [n4, n3],
            replaceExpressions: ["n1", "(- n1 2)", "n2"]
        )
        
        sub.addTransformation(chromaticUp)
        sub.addTransformation(chromaticDown)
        sub.addTransformation(diatonicUp)
        sub.addTransformation(diatonicDown)
        
        return sub
    }
    
    /// split-half: 拆分二分音符为两个四分音符（权重1）
    private static func makeSplitHalfMotif() -> TransformEngine.Substitution {
        let halfNote = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 60, durationSlots: 240),
            chord: ChordBlock(name: "C", duration: 1.0),
            slot: 0, transformVar: 0
        )
        
        let split = TransformEngine.Transformation(
            guardCondition: nil,
            isEnabled: true, weight: 1.0,
            matchTemplate: [halfNote],
            replaceExpressions: ["n1", "n1"]
        )
        
        var sub = TransformEngine.Substitution(
            name: "split-half",
            subType: "motif",
            weight: 1
        )
        sub.addTransformation(split)
        return sub
    }
    
    /// split-whole: 拆分全音符为两个二分音符（权重5, 对齐Java原版）
    private static func makeSplitWholeMotif() -> TransformEngine.Substitution {
        let wholeNote = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 60, durationSlots: 480),
            chord: ChordBlock(name: "C", duration: 1.0),
            slot: 0, transformVar: 0
        )
        
        let split = TransformEngine.Transformation(
            guardCondition: nil,
            isEnabled: true, weight: 1.0,
            matchTemplate: [wholeNote],
            replaceExpressions: ["n1", "n1"]
        )
        
        var sub = TransformEngine.Substitution(
            name: "split-whole",
            subType: "motif",
            weight: 5
        )
        sub.addTransformation(split)
        return sub
    }
    
    /// 将一个音符拆成和弦分解三连音
    private static func makeTripletArpeggioMotif() -> TransformEngine.Substitution {
        // 匹配四分音符及以上，拆成三个音（和弦音：根-3-5，根-5-3等）
        let quarterNote = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 60, durationSlots: Constants.slotsPerBeat),
            chord: ChordBlock(name: "C", duration: 1.0),
            slot: 0, transformVar: 0
        )
        
        // 三连音：每个音40 slots（120/3）
        // 上行琶音：根-3-5
        let arpeggioUp = TransformEngine.Transformation(
            guardCondition: nil,
            isEnabled: true, weight: 1.0,
            matchTemplate: [quarterNote],
            replaceExpressions: ["n1", "(+ n1 4)", "(+ n1 7)"]  // 根-大三度-纯五度
        )
        
        // 下行琶音：根-5-3
        let arpeggioDown = TransformEngine.Transformation(
            guardCondition: nil,
            isEnabled: true, weight: 1.0,
            matchTemplate: [quarterNote],
            replaceExpressions: ["n1", "(+ n1 7)", "(+ n1 4)"]
        )
        
        var sub = TransformEngine.Substitution(
            name: "triplet-arpeggio",
            subType: "motif",
            weight: 0   // 禁用: 用户反馈生成太多三连音
        )
        sub.addTransformation(arpeggioUp)
        sub.addTransformation(arpeggioDown)
        return sub
    }
    
    // MARK: - ========== Embellishment 装饰音级变换 ==========
    
    /// identity-embellishment: 不做任何装饰（权重30，最高！）
    /// 这是最重要的变换，保证大部分音符保持原样
    private static func makeIdentityEmbellishment() -> TransformEngine.Substitution {
        // 匹配任何单个音符，原样返回
        let anyNote = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 60, durationSlots: 30),
            chord: ChordBlock(name: "C", duration: 1.0),
            slot: 0, transformVar: 0
        )
        
        let identity = TransformEngine.Transformation(
            guardCondition: nil,
            isEnabled: true,
            weight: 10.0,
            matchTemplate: [anyNote],
            replaceExpressions: ["n1"]
        )
        
        var sub = TransformEngine.Substitution(
            name: "identity-embellishment",
            subType: "embellishment",
            weight: 10
        )
        sub.addTransformation(identity)
        return sub
    }
    
    /// mordent/neighbors: 邻音/波音（权重1）
    /// 长-短-长的装饰，不是平均分配！
    private static func makeMordentEmbellishment() -> TransformEngine.Substitution {
        var sub = TransformEngine.Substitution(
            name: "neighbors",
            subType: "embellishment",
            weight: 1
        )
        
        // 匹配四分音符及以上
        let quarterNote = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 60, durationSlots: Constants.slotsPerBeat),
            chord: ChordBlock(name: "C", duration: 1.0),
            slot: 0, transformVar: 0
        )
        
        // 注意：我们稍后会在applyReplace中特殊处理时值分配
        // 上邻音
        let upper = TransformEngine.Transformation(
            guardCondition: nil,
            isEnabled: true, weight: 1.0,
            matchTemplate: [quarterNote],
            replaceExpressions: ["n1", "(+ n1 2)", "n1"]
        )
        
        // 下邻音
        let lower = TransformEngine.Transformation(
            guardCondition: nil,
            isEnabled: true, weight: 1.0,
            matchTemplate: [quarterNote],
            replaceExpressions: ["n1", "(- n1 2)", "n1"]
        )
        
        // 半音上邻音
        let upperChromatic = TransformEngine.Transformation(
            guardCondition: nil,
            isEnabled: true, weight: 0.5,
            matchTemplate: [quarterNote],
            replaceExpressions: ["n1", "(+ n1 1)", "n1"]
        )
        
        // 半音下邻音
        let lowerChromatic = TransformEngine.Transformation(
            guardCondition: nil,
            isEnabled: true, weight: 0.5,
            matchTemplate: [quarterNote],
            replaceExpressions: ["n1", "(- n1 1)", "n1"]
        )
        
        sub.addTransformation(upper)
        sub.addTransformation(lower)
        sub.addTransformation(upperChromatic)
        sub.addTransformation(lowerChromatic)
        
        return sub
    }
    
    /// gracenote: 倚音（权重1）
    /// 极短的装饰音，几乎不占主音时值
    private static func makeGracenoteEmbellishment() -> TransformEngine.Substitution {
        // 匹配四分音符及以上（120slots），这样倚音至少40slots
        let quarterNote = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 60, durationSlots: Constants.slotsPerBeat),
            chord: ChordBlock(name: "C", duration: 1.0),
            slot: 0, transformVar: 0
        )
        
        // 倚音：短装饰音 + 主音（时值分配：40 + 80）
        // 上方倚音
        let upperGrace = TransformEngine.Transformation(
            guardCondition: nil,
            isEnabled: true, weight: 1.0,
            matchTemplate: [quarterNote],
            replaceExpressions: ["(+ n1 1)", "n1"]
        )
        
        // 下方倚音
        let lowerGrace = TransformEngine.Transformation(
            guardCondition: nil,
            isEnabled: true, weight: 1.0,
            matchTemplate: [quarterNote],
            replaceExpressions: ["(- n1 1)", "n1"]
        )
        
        var sub = TransformEngine.Substitution(
            name: "gracenote",
            subType: "embellishment",
            weight: 1
        )
        sub.addTransformation(upperGrace)
        sub.addTransformation(lowerGrace)
        return sub
    }
    
    /// split-quarter: 拆分四分音符为两个八分音符（权重4）
    private static func makeSplitQuarterEmbellishment() -> TransformEngine.Substitution {
        let quarterNote = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 60, durationSlots: Constants.slotsPerBeat),
            chord: ChordBlock(name: "C", duration: 1.0),
            slot: 0, transformVar: 0
        )
        
        let split = TransformEngine.Transformation(
            guardCondition: nil,
            isEnabled: true, weight: 1.0,
            matchTemplate: [quarterNote],
            replaceExpressions: ["n1", "n1"]
        )
        
        var sub = TransformEngine.Substitution(
            name: "split-quarter",
            subType: "motif",
            weight: 5
        )
        sub.addTransformation(split)
        return sub
    }
    
    /// triplet-embellish: 三连音装饰（权重4）
    /// 将一个音符拆成三个相同音高的三连音
    private static func makeTripletEmbellishment() -> TransformEngine.Substitution {
        let quarterNote = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 60, durationSlots: Constants.slotsPerBeat),
            chord: ChordBlock(name: "C", duration: 1.0),
            slot: 0, transformVar: 0
        )
        
        let triplet = TransformEngine.Transformation(
            guardCondition: nil,
            isEnabled: true, weight: 1.0,
            matchTemplate: [quarterNote],
            replaceExpressions: ["n1", "n1", "n1"]
        )
        
        var sub = TransformEngine.Substitution(
            name: "triplet-embellish",
            subType: "embellishment",
            weight: 4
        )
        sub.addTransformation(triplet)
        return sub
    }
    
    /// add-rests: 添加呼吸休止（权重1）
    /// 将长音符末尾换成短休止，制造呼吸感
    private static func makeAddRestsEmbellishment() -> TransformEngine.Substitution {
        // 匹配二分音符及以上
        let halfNote = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 60, durationSlots: 240),
            chord: ChordBlock(name: "C", duration: 1.0),
            slot: 0, transformVar: 0
        )
        
        // 音符 + 短休止（休止符midi=-1）
        let addRest = TransformEngine.Transformation(
            guardCondition: nil,
            isEnabled: true, weight: 1.0,
            matchTemplate: [halfNote],
            replaceExpressions: ["n1", "-1"]  // -1表示休止符
        )
        
        var sub = TransformEngine.Substitution(
            name: "add-rests",
            subType: "embellishment",
            weight: 1
        )
        sub.addTransformation(addRest)
        return sub
    }

    // MARK: - P0-2 新补全装饰规则

    /// approach-chromatic: 半音趋近装饰 (权重2)
    /// 单音→approach半音+目标音,  ApproachAdvice 引导链
    private static func makeApproachChromaticEmbellishment() -> TransformEngine.Substitution {
        let quarterNote = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 60, durationSlots: Constants.slotsPerBeat),
            chord: ChordBlock(name: "C", duration: 1.0), slot: 0, transformVar: 0)
        let approach = TransformEngine.Transformation(guardCondition: nil, isEnabled: true, weight: 1.0,
            matchTemplate: [quarterNote],
            replaceExpressions: ["(+ n1 1)", "n1"]  // 上邻半音趋近→目标音
        )
        var sub = TransformEngine.Substitution(name: "approach-chromatic", subType: "embellishment", weight: 2)
        sub.addTransformation(approach)
        return sub
    }

    /// neighbor-lower: 下邻音装饰 (权重2)
    /// 单音→音符+下半音邻音+音符,  mordent 修饰
    private static func makeNeighborLowerEmbellishment() -> TransformEngine.Substitution {
        let quarterNote = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 60, durationSlots: Constants.slotsPerBeat),
            chord: ChordBlock(name: "C", duration: 1.0), slot: 0, transformVar: 0)
        let lowerNeighbor = TransformEngine.Transformation(guardCondition: nil, isEnabled: true, weight: 1.0,
            matchTemplate: [quarterNote],
            replaceExpressions: ["n1", "(- n1 1)", "n1"]  // 音符→下邻音→回归
        )
        var sub = TransformEngine.Substitution(name: "neighbor-lower", subType: "embellishment", weight: 2)
        sub.addTransformation(lowerNeighbor)
        return sub
    }

    /// neighbor-upper: 上邻音装饰 (权重2)
    private static func makeNeighborUpperEmbellishment() -> TransformEngine.Substitution {
        let quarterNote = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 60, durationSlots: Constants.slotsPerBeat),
            chord: ChordBlock(name: "C", duration: 1.0), slot: 0, transformVar: 0)
        let upperNeighbor = TransformEngine.Transformation(guardCondition: nil, isEnabled: true, weight: 1.0,
            matchTemplate: [quarterNote],
            replaceExpressions: ["n1", "(+ n1 2)", "n1"]  // 音符→上全音邻音→回归
        )
        var sub = TransformEngine.Substitution(name: "neighbor-upper", subType: "embellishment", weight: 2)
        sub.addTransformation(upperNeighbor)
        return sub
    }

    /// double-passing: 双经过音填充 (权重2)
    /// 两个三度跳进音→中间插入两音半音阶, passing-tone double
    private static func makeDoublePassingEmbellishment() -> TransformEngine.Substitution {
        let chordC = ChordBlock(name: "C", duration: 1.0)
        let n1 = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 60, durationSlots: Constants.slotsPerBeat), chord: chordC, slot: 0, transformVar: 0)
        let n2 = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 63, durationSlots: Constants.slotsPerBeat), chord: chordC, slot: 120, transformVar: 0)
        let doublePass = TransformEngine.Transformation(guardCondition: nil, isEnabled: true, weight: 1.0,
            matchTemplate: [n1, n2],
            replaceExpressions: ["n1", "(+ n1 1)", "(+ n1 2)", "n2"]  // 三度→半音阶填充
        )
        var sub = TransformEngine.Substitution(name: "double-passing", subType: "embellishment", weight: 2)
        sub.addTransformation(doublePass)
        return sub
    }

    // MARK: - P1 长音拆分规则 (密度增强)

    /// split-half-to-eighths: 二分→4八分 (240→60*4), 权重4
    private static func makeSplitHalfToEighths() -> TransformEngine.Substitution {
        let halfNote = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 60, durationSlots: 240),
            chord: ChordBlock(name: "C", duration: 2.0),
            slot: 0, transformVar: 0)
        let split = TransformEngine.Transformation(guardCondition: nil, isEnabled: true, weight: 4.0,
            matchTemplate: [halfNote],
            replaceExpressions: ["n1", "(+ n1 2)", "(+ n1 4)", "(+ n1 3)"])  // 原音→上二度→上四度→上三度
        var sub = TransformEngine.Substitution(name: "split-half-to-eighths", subType: "motif", weight: 4)
        sub.addTransformation(split)
        return sub
    }

    /// split-half-to-eqq: 二分→八分+八分+四分 (240→60+60+120), 权重2
    private static func makeSplitHalfToEQQ() -> TransformEngine.Substitution {
        let halfNote = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 60, durationSlots: 240),
            chord: ChordBlock(name: "C", duration: 2.0),
            slot: 0, transformVar: 0)
        let split = TransformEngine.Transformation(guardCondition: nil, isEnabled: true, weight: 2.0,
            matchTemplate: [halfNote],
            replaceExpressions: ["n1", "(+ n1 1)", "n1"])  // 原音→上半音→原音
        var sub = TransformEngine.Substitution(name: "split-half-to-eqq", subType: "motif", weight: 2)
        sub.addTransformation(split)
        return sub
    }

    /// split-dotted-quarter-to-eighths: 附点四分→3八分 (180→60*3), 权重3
    private static func makeSplitDottedQuarterToEighths() -> TransformEngine.Substitution {
        let dottedQ = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 60, durationSlots: 180),
            chord: ChordBlock(name: "C", duration: 1.5),
            slot: 0, transformVar: 0)
        let split = TransformEngine.Transformation(guardCondition: nil, isEnabled: true, weight: 3.0,
            matchTemplate: [dottedQ],
            replaceExpressions: ["n1", "(- n1 1)", "n1"])  // 原音→下半音→原音
        var sub = TransformEngine.Substitution(name: "split-dotted-quarter", subType: "motif", weight: 3)
        sub.addTransformation(split)
        return sub
    }

    /// split-eighth-to-sixteenths: 八分→2十六分 (60→30*2), 权重1
    private static func makeSplitEighthToSixteenths() -> TransformEngine.Substitution {
        let eighth = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 60, durationSlots: 60),
            chord: ChordBlock(name: "C", duration: 0.5),
            slot: 0, transformVar: 0)
        let split = TransformEngine.Transformation(guardCondition: nil, isEnabled: true, weight: 1.0,
            matchTemplate: [eighth],
            replaceExpressions: ["n1", "(+ n1 1)"])  // 原音→上半音
        var sub = TransformEngine.Substitution(name: "split-eighth-to-sixteenths", subType: "motif", weight: 1)
        sub.addTransformation(split)
        return sub
    }

    /// grace-approach: 长音(≥180)→十六分趋近音(30)+目标长音, 权重2
    private static func makeGraceApproach() -> TransformEngine.Substitution {
        let longNote = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 60, durationSlots: 240),
            chord: ChordBlock(name: "C", duration: 2.0),
            slot: 0, transformVar: 0)
        // 趋近音: n1-1 (下半音)→n1目标音 (时值: 30+剩余)
        let approach = TransformEngine.Transformation(guardCondition: nil, isEnabled: true, weight: 2.0,
            matchTemplate: [longNote],
            replaceExpressions: ["(- n1 1)", "n1"])  // 趋近音→目标音
        var sub = TransformEngine.Substitution(name: "grace-approach", subType: "embellishment", weight: 2)
        sub.addTransformation(approach)
        return sub
    }

    /// passing-tone-split: 长音(≥120)→目标音+十六分经过音+下音, 权重2
    private static func makePassingToneSplit() -> TransformEngine.Substitution {
        let n1 = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 60, durationSlots: 120),
            chord: ChordBlock(name: "C", duration: 1.0),
            slot: 0, transformVar: 0)
        let n2 = TransformEngine.NoteChordPair(
            note: PhysicalNote(midiPitch: 62, durationSlots: 60),
            chord: ChordBlock(name: "C", duration: 1.0),
            slot: 120, transformVar: 0)
        let passing = TransformEngine.Transformation(guardCondition: nil, isEnabled: true, weight: 2.0,
            matchTemplate: [n1, n2],
            replaceExpressions: ["n1", "(+ n1 1)", "n2"])  // n1→半音→n2
        var sub = TransformEngine.Substitution(name: "passing-tone-split", subType: "motif", weight: 2)
        sub.addTransformation(passing)
        return sub
    }
}
