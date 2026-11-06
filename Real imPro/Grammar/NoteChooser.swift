import Foundation

// MARK: - NoteChooser
// 
// 功能: 基于28条概率查表规则的音符类型选择器
//       目标类型(chord/color/scale/random) + 可用音符组合 →
//       查表→4维概率分布→随机掷骰选类型→从候选音随机取音高差→八度修正

struct NoteChooser {

    // ═════════════════════════════════════════════════════════════
    // 音符类型常量 — Java L32-39
    // P0: 暴露为internal供GrammarStrategy.NoteChooser后处理器调用
    // ═════════════════════════════════════════════════════════════
    static let NOTE     = 1000   // L32: public static final int NOTE = 1000
    static let CHORD    = 1001   // L33: CHORD = 1001
    static let SCALE    = 1002   // L34: SCALE = 1002
    static let COLOR    = 1003   // L35: COLOR = 1003
    static let APPROACH = 1004   // L36: APPROACH = 1004
    static let RANDOM   = 1005   // L37: RANDOM = 1005
    static let BASS     = 1006   // L38: BASS = 1006
    static let GOAL     = 1007   // L39: GOAL = 1007

    // Java L41-43: typeMap — 概率选出的 newType(0-3) 映射回实际类型常量
    //   typeMap[0]=CHORD, typeMap[1]=COLOR, typeMap[2]=RANDOM, typeMap[3]=SCALE
    static let typeMap: [Int] = [CHORD, COLOR, RANDOM, SCALE]

    /// L47: doNotSwitchOctave — true=禁止八度越界修正
    private let noOctaveSwitch: Bool


    // ═════════════════════════════════════════════════════════════
    // 28条概率查表规则 — Java L61-93 probString
    //
    // 每条规则: (type, haveChord, haveColor, haveRandom,
    //           probChord%, probColor%, probRandom%, probScale%)
    //
    // type: 0=目标chord  1=目标color  2=目标random  3=目标scale
    //
    // 设计原理 (Jon Gillick):
    //   rules 0-6:   目标chord  → 优先chord(100%), 无chord用color/random替补
    //   rules 7-13:  目标color  → 主选color(90-100%), chord引流(10-85%瑕疵=爵士灵魂)
    //   rules 14-20: 目标scale  → all scale(100%), 无scale用random
    //   rules 21-27: 目标random → 三路混合(25-80% chord, 20-50% color, 25-50% random)
    // ═════════════════════════════════════════════════════════════

    static let probabilityTable: [(
        type: Int, hChord: Int, hColor: Int, hRandom: Int,
        pChord: Int, pColor: Int, pRandom: Int, pScale: Int
    )] = [

        // ── type=0: looking for CHORD (L62-68) ──
        (0, 1, 1, 1,  100, 0, 0, 0),    // L62: 有chord+color+random → all chord
        (0, 1, 1, 0,  100, 0, 0, 0),    // L63: 有chord+color → all chord
        (0, 1, 0, 1,  100, 0, 0, 0),    // L64: 有chord+random → all chord
        (0, 1, 0, 0,  100, 0, 0, 0),    // L65: 仅有chord → all chord
        (0, 0, 1, 1,  0, 100, 0, 0),    // L66: 有color+random, 无chord → all color
        (0, 0, 1, 0,  0, 100, 0, 0),    // L67: 仅有color → all color
        (0, 0, 0, 1,  0, 0, 100, 0),    // L68: 仅有random → all random

        // ── type=1: looking for COLOR (L70-76) ──
        (1, 1, 1, 1,  0, 100, 0, 0),    // L70: 全有 → all color
        (1, 1, 1, 0,  10, 90, 0, 0),    // L71: 有chord+color → 10%chord 90%color
        (1, 1, 0, 1,  85, 0, 15, 0),    // L72: 有chord+random → 85%chord 15%random
        (1, 1, 0, 0,  100, 0, 0, 0),    // L73: 仅有chord → all chord
        (1, 0, 1, 1,  0, 100, 0, 0),    // L74: 有color+random → all color
        (1, 0, 1, 0,  0, 100, 0, 0),    // L75: 仅有color → all color
        (1, 0, 0, 1,  0, 0, 100, 0),    // L76: 仅有random → all random

        // ── type=3: looking for SCALE (L78-84) ──
        (3, 1, 1, 1,  0, 0, 0, 100),    // L78: 全有 → all scale
        (3, 1, 1, 0,  0, 0, 0, 100),    // L79: 有chord+color → all scale
        (3, 1, 0, 1,  0, 0, 0, 100),    // L80: 有chord+random → all scale
        (3, 1, 0, 0,  0, 0, 0, 100),    // L81: 仅有chord → all scale
        (3, 0, 1, 1,  0, 0, 0, 100),    // L82: 有color+random → all scale
        (3, 0, 1, 0,  0, 0, 0, 100),    // L83: 仅有color → all scale
        (3, 0, 0, 1,  0, 0, 100, 0),    // L84: 仅有random → all random

        // ── type=2: looking for RANDOM (L87-93) ──
        (2, 1, 1, 1,  50, 25, 25, 0),   // L87: 全有 → 50%chord 25%color 25%random
        (2, 1, 1, 0,  80, 20, 0, 0),    // L88: 有chord+color → 80%chord 20%color
        (2, 1, 0, 1,  50, 0, 50, 0),    // L89: 有chord+random → 50%chord 50%random
        (2, 1, 0, 0,  100, 0, 0, 0),    // L90: 仅有chord → all chord
        (2, 0, 1, 1,  0, 50, 50, 0),    // L91: 有color+random → 50%color 50%random
        (2, 0, 1, 0,  0, 100, 0, 0),    // L92: 仅有color → all color
        (2, 0, 0, 1,  0, 0, 100, 0),    // L93: 仅有random → all random
    ]


    // MARK: - 构造器
    // ═════════════════════════════════════════════════════════════
    // Java L48-98: public NoteChooser(boolean noOctaveSwitch)
    //
    // 将28条规则以Polylist S表达式字符串解析后存储。
    // Swift以静态编译期元组数组代替, 免去运行时解析开销, 语义完全一致。

    init(noOctaveSwitch: Bool = false) {
        self.noOctaveSwitch = noOctaveSwitch          // L51
    }


    // MARK: - chooseNote (核心查表选音算法)
    // ═════════════════════════════════════════════════════════════
    // Java L107-188: public int getNote(int minPitch, int maxPitch,
    //     int low, int high, int type, int[] numTypes, int[] noteTypes, int attempts)
    //
    // 7步算法:
    //   [1] L112-115: 类型映射 CHORD→0 COLOR→1 RANDOM→2 SCALE→3
    //   [2] L120-123: 构建标识符 (type, haveChord, haveColor, haveRandom)
    //   [3] L136-145: 遍历28条规则查匹配行, 提取概率分布
    //   [4] L149-162: randNum∈[1,100]掷骰, 逐概率递减选定 newType∈[0,3]
    //   [5] L165-175: 从 noteTypes[] 取第randNum个匹配类型的音高差
    //   [6] L176:      finalPitch = low + pitchdiff
    //   [7] L178-186: 最后attempts且允许octave切换时, 八度±12修正到[minPitch,maxPitch]
    //
    // melodyGenLimit: 对应 Java LickGen.MELODY_GEN_LIMIT, 默认50

    func chooseNote(
        minPitch: Int,
        maxPitch: Int,
        low: Int,
        high: Int,
        type: Int,
        numTypes: [Int],
        noteTypes: [Int],
        attempts: Int,
        melodyGenLimit: Int = 50
    ) -> Int {

        // ── [1] 类型映射: 实际类型常量 → 0-3 索引 (L112-115) ──
        var t = type
        if t == Self.CHORD  { t = 0 }                    // L112
        if t == Self.COLOR  { t = 1 }                    // L113
        if t == Self.RANDOM { t = 2 }                    // L114
        if t == Self.SCALE  { t = 3 }                    // L115

        // ── [2] 构建标识符 (L120-123) ──
        let haveChord  = (numTypes[0] != 0) ? 1 : 0       // L121: numTypes[0]→chord count
        let haveColor  = (numTypes[1] != 0) ? 1 : 0       // L122: numTypes[1]→color count
        let haveRandom = (numTypes[2] != 0) ? 1 : 0       // L123: numTypes[2]→random count

        // ── [3] 查表匹配 (L133-145) ──
        // L133: Polylist identifier = Polylist.list(type, haveChord, haveColor, haveRandom)
        // L136-145: for(Polylist L=probabilities; L.nonEmpty(); L=L.rest())
        //              if identifier matches tempIdentifier → prob = tempProb.coprefix(4)
        var probs = (0, 0, 0, 0)
        for rule in Self.probabilityTable {
            if rule.type == t,
               rule.hChord == haveChord,
               rule.hColor == haveColor,
               rule.hRandom == haveRandom {
                probs = (rule.pChord, rule.pColor, rule.pRandom, rule.pScale)
                break
            }
        }
        let probArray = [probs.0, probs.1, probs.2, probs.3]  // L149: int[] probs = setProb(prob)

        // ── [4] 按概率掷骰选定输出类型 (L151-162) ──
        // L154: int randNum = rand.nextInt(100) + 1
        var randNum = Int.random(in: 1...100)
        var newType = 0                                      // L155

        // L156-162: for(i=0;i<probs.length;i++) { randNum-=probs[i]; if(randNum≤0){...} }
        for i in 0..<probArray.count {
            randNum -= probArray[i]                          // L157
            if randNum <= 0 {                                // L158
                newType = i                                  // L159
                break                                        // L160
            }
        }

        // ── [5] 从候选音中随机取音高差 (L164-175) ──
        let targetType = Self.typeMap[newType]               // L168: typeMap[newType]
        // L165: randNum = rand.nextInt(numTypes[newType]) + 1
        randNum = Int.random(in: 1...numTypes[newType])
        var pitchDiff = 0                                    // L166

        // L167-173: for(i=0;i<noteTypes.length;i++)
        for i in 0..<noteTypes.count {
            let nt = noteTypes[i]
            // L168-169: 类型匹配(或scale=3时放宽至chord/color)
            if nt == targetType ||
               (newType == 3 && (nt == Self.CHORD || nt == Self.COLOR)) {
                randNum -= 1                                 // L170
            }
            // L171-173: if(randNum≤0) { pitchdiff=i; break }
            if randNum <= 0 {
                pitchDiff = i                                // L172
                break                                        // L173
            }
        }

        // ── [6] 计算最终音高 (L176) ──
        var finalPitch = low + pitchDiff                     // L176

        // ── [7] 八度越界修正 (L178-186) ──
        // L178: if(attempts >= LickGen.MELODY_GEN_LIMIT-1 && doNotSwitchOctave==false)
        if attempts >= melodyGenLimit - 1, !noOctaveSwitch {
            while finalPitch > maxPitch { finalPitch -= 12 } // L180-181
            while finalPitch < minPitch { finalPitch += 12 } // L183-184
        }

        return finalPitch                                    // L187
    }
}
