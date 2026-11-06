# P3-c 逐 hunk 落地 diff —— 贝斯音域沉回 + 伴奏/独奏响度校准 + 两个真 bug

> 日期：2026-10-11　状态：**待书面批准（批准前生产零改动）**
> 工程：Real imPro（SwiftUI iPadOS，iOS 16.6）　scheme/target：RealimPro
> 性质：**纯播放/渲染层校准**。不碰 solo 四条生成链路、不碰 .sty 资源、不翻任何默认、不新增付费点/顶栏、用户可见无「Java」。

---

## 0. 乐手版一句话结论

- **贝斯太高**：移植来的伴奏把贝司框在 G2–C4（平均音在 D#3，大部分音落在 C3 那一个八度，飘、像吉他）。Java 引擎作者自己的出厂默认是 **G1–G3**（平均 G2，重心落在 C2–B2 的经典 walking 区），只是每个 .sty 文件头又把它抬高了。本次在渲染端把它**拉回 Java 出厂 G1–G3**；若真机还想更低沉，改一个常量即可切到 E1–G3（四弦电贝最低空弦）做 A/B。
- **伴奏一响一轻**：Java 原版没有"伴奏躲独奏"的自动压低，它是**固定分轨音量**——独奏 127、贝司 60、鼓 60、钢琴 40（`Preferences.java:123-143`）。只放伴奏觉得响、一加独奏觉得伴奏弱，是被满音量的独奏掩蔽，电平本身没变。移植来的 .sty 保留了满力度 127，而 App 原手写伴奏力度烘焙得较低，两套基准不同才造成"一个响一个轻"。本次：① 修掉把线性音量误当 dB 的 bug；② 播放端把 .sty 三轨**按能量自动归一到手写基准**，再统一套上 Java 的 40/60/60 主次比例；鼓组额外保留一点响度（完整鼓组不能被压成单件 Ride 那么轻）。
- **两个真 bug 一起修**：钢琴力度会算出非法的 135（MIDI 合法上限 127，8 个代表风格里共 **327 个**越界音）；`masterGain`（dB 单位）被塞进了线性 0.8（实际变成 +0.8dB≈110%）。
- **最终响度以真机并听 Java 为准**：探针给的是数学初值，文档里把所有校准量集中成一个常量文件、附"偏轻/偏重怎么调"，真机一次性 A/B 定稿。

---

## 1. 备份计划与当前 SHA1（落地第 1 步核对）

落地前整文件备份到 `.backup/P3c-20261011/`（同步根之外的备份目录，不会被打进包），并与下列**当前只读实测 SHA1** 逐一核对：

| 文件 | 类型 | 当前 SHA1（改前基线，20261011 实测） |
|---|---|---|
| `Real imPro/MidiPlayer/JazzMidiPlayer.swift` | 改 | `85f300d2d84e58af32fce7801b950e18a8d19e07` |
| `Real imPro/MidiPlayer/StyleEngine/StyleChordRenderer.swift` | 改 | `4603690cbe379fae4552db7896f938109c8a0476` |
| `Real imPro/MidiPlayer/StyleEngine/StyleBassRenderer.swift` | 改 | `8ad71953817c2390075f373ade15251ec3c8a3bb` |
| `Real imPro/MidiPlayer/StyleEngine/AccompanimentMix.swift` | **新增** | 无（新文件，回退即删） |

合计 **3 改 + 1 新增 = 4 个文件**；`ContentView.swift`、`BandMixerView.swift`、所有 solo 引擎、`.sty/.tsv/.rnn` 资源**一律不动**。
pbxproj 用 PBXFileSystemSynchronizedRootGroup，新增 `AccompanimentMix.swift` 自动入 target，**不手改 pbxproj**（P3-a 新增 11 文件已验证此机制）。

---

## 2. 隔离探针实测结论（/tmp，生产零改动）

探针：`/tmp/p3c/main.swift`（编译集＝生产 StyleEngine 11 文件 + Pattern/Drum/Bass/Chord 及其 Extractor + FullVoicing 7 文件；固定 16 小节 Cmaj7/Am7/Dm7/G7、spm480、种子 12345）。**已编译运行通过（exit=0）**。

### 2.1 响度：手写基准与各 .sty 归一系数（velocity 已 clamp≤127 后统计）

手写 Simple Swing（App 原有，响度基准）16 小节总能量 Σvel²：

| 轨 | 音符数 | Σvel² | 平均力度 |
|---|---|---|---|
| DRUM | 128 | **603,200** | 67（basicSwing 仅单件 Ride=GM51） |
| BASS | 64 | **504,400** | 88 |
| PIANO | 69 | **312,148** | 66 |

Java 通道席位（`Preferences.java`，值/127 线性振幅）：melody=127→**1.000**、bass=60→**0.472**、drums=60→**0.472**、chords(钢琴)=40→**0.315**、entry=50（导入旋律，不涉及）。默认风格 `DS_VAL="swing"`（:147）也与 App 默认 Simple Swing 一致。

各 .sty 相对手写的**节点振幅归一系数 g = √(手写每小节能量 ÷ .sty 每小节能量)**，以及"Java 席位 × g"后的内容增益（cd）：

| style | g_drum | g_bass | g_piano | cdDrum | cdBass | cdPiano | 钢琴非法>127 音数 |
|---|---|---|---|---|---|---|---|
| swing | 0.550 | 0.716 | 0.538 | 0.260 | 0.338 | 0.169 | 41 |
| shuffle | 0.441 | 0.688 | 0.274 | 0.209 | 0.325 | 0.086 | 108 |
| rock-medium | 0.321 | 0.989 | 0.418 | 0.151 | 0.467 | 0.132 | 45 |
| latin | 0.424 | 0.761 | 0.364 | 0.200 | 0.360 | 0.115 | 68 |
| funk | 0.424 | 0.694 | 0.591 | 0.200 | 0.328 | 0.186 | 0 |
| pop-blues | 0.443 | 0.528 | 0.671 | 0.209 | 0.250 | 0.211 | 0 |
| two-beat | 0.483 | 0.989 | 0.428 | 0.228 | 0.467 | 0.135 | 65 |
| tango | 0.386 | 0.625 | 0.457 | 0.182 | 0.295 | 0.144 | 0 |
| **g 区间(min/中位/max)** | .321/.441/.550 | .528/.716/.989 | .274/.457/.671 | | | | **合计 327** |

要点（乐手版）：
- cd 数字是"该轨音量旋钮拧到的位置"，不是最终响度。.sty 源力度接近满格 127，所以旋钮要拧得比手写更小，**两者最终听到的响度才相等**（能量 ×g² 严格相等，已在探针数学验证）。
- g 随风格明显离散（鼓 0.32–0.55、钢琴 0.27–0.67），**用一个全局常数无法同时拉平 43 个风格**，故落地采用"播放端按当前 backingTrack 每小节能量**实时自动归一**"（见 §3），新增风格也无需手调。
- 钢琴非法 velocity>127 共 **327 个**（swing41/shuffle108/rock45/latin68/two-beat65；funk/pop-blues/tango 为 0），坐实 135 bug 面，clamp 后归 0。

### 2.2 贝斯音域三方案（swing.sty，同种子重置；唯一变量是文件头 bass-low/high，仍走生产 parser+renderer）

| 方案 | 文件头 | 音符数 | 总时值(slots) | 实际音域 | 平均音 | 八度分布 | 首拍根音 |
|---|---|---|---|---|---|---|---|
| **现状 G2–C4** | g-- / c (43/60) | 68 | 7680 | G#2(44)~A3(57) | D#3(51.3) | C2:15　C3:53 | 16/16 |
| **覆盖 G1–G3（Java 出厂，推荐）** | g--- / g- (31/55) | 66 | 7680 | C2(36)~G3(55) | **G2(42.7)** | C2:58　C3:8 | 16/16 |
| 备选 E1–G3（四弦空弦） | e--- / g- (28/55) | 66 | 7680 | C2(36)~F#3(54) | F#2(41.6) | C2:64　C3:2 | 16/16 |

- 三版**总时值都 7680、首拍根音 16/16 全中**：音域只改变八度放置，不改节奏骨架与和声。
- 现状平均 D#3、53/68 的音挤在 C3–B3，确属偏高；G1–G3 后平均 G2、58/66 沉到 C2–B2，是立式/电贝 walking 的经典音区。
- 音符数 68→66（−2）：总时值守恒、根音全中，差异为沉到低八度后个别经过音的放置/同音处理，**不改节奏总时值与和声骨架**；列入真机"walking 连贯性"核对项，不阻塞。
- Java 逐行依据：`Style.java:188 bassLow=makeNoteSymbol("g---")`=G1(31)、`:193 bassHigh=...("g-")`=G3(55)；`.sty` 在 `load()` 的 `:790 BASS_HIGH / :797 BASS_LOW` 覆盖之；初始音取音域中点 `:2196 (high+low)/2`。本次渲染端覆盖＝**撤销文件头抬高、回到引擎出厂默认**。

### 2.3 两个真 bug（精确定位）

1. **钢琴 135 越界**：`StyleChordRenderer.swift:142` `UInt8(clamping: 127 + rng.nextInt(17)-8)`，127+8=135。`UInt8(clamping:)` 只在 >255 截断、**不截 127**，产生语义非法的 7-bit MIDI velocity。当前被播放端 `JazzMidiPlayer.swift:464 min(127)` 兜住不会真发出，但污染 `CompanionNote.volume` 与一切能量统计，且是未来路径隐患。源头 clamp 1...127；±8 力度人性化保留（:144 起点 ±3 已 `max(0,...)`，保留）。
2. **masterGain dB 误用**：`JazzMidiPlayer.swift:106` 把线性 finalVolume(0–1) 赋给 dB 单位（−90…+12）的 `masterGain`。0.8 被当 **+0.8dB≈振幅 110%**（不是 80%）。全仓 masterGain **唯一出现点**（已 grep 确认）。修法：masterGain 恒 0dB，音量只走线性 `AVAudioNode.volume`。

### 2.4 渲染侧改动的补丁副本隔离自证（已通过，生产零改动）

已在 `/tmp` 拷一整套 StyleEngine 副本并**逐字应用 H0/H4/H5/H6/H7**（生产文件未动），与生产 Pattern/Drum/Bass/Chord/FullVoicing 一起 `swiftc` 编译（**0 error**）后跑全量验证（exit=0）：

- **swing（文件头仍是 G2–C4）**：贝司 `n=66 slots=7680 域 C2(36)~G3(55) 平均=G2(42.7) 根音 16/16`——与 §2.2"手动替换文件头为 G1–G3"版**完全一致**，证明 H6 渲染端覆盖等价生效；钢琴 `n=68 maxVel=127 非法>127=0`（H4/H5 生效，clamp 不删音、音符数不变）；鼓 n=162 不变。
- **全 43 个 .sty 回归扫描**：`parseOK=43 parseFail=0 空轨=0 贝司超域=0 钢琴越界风格=0`，全量 PASS（音域全部落入 G1–G3、钢琴 velocity 全合法、三轨非空）。
- 播放端 H1/H2/H3（JazzMidiPlayer，AVFAudio，依赖 GeneratedMeasure/SwingProfile 等整 App 类型）未做命令行 typecheck，语法已逐行人工审查，**以落地时 Xcode GUI Build 0 error 为权威门**。

---

## 3. 落地方案（方案 C：播放端按来源归一 + Java 主次比例）

- 归一在**播放节点的线性增益 `.volume`** 做，**不改任何 MIDI velocity / 音色 / .sty 资源 / 生成算法**。
- 轨道编号沿用现有约定：0=sax 独奏、1=piano、2=bass、3=drum。
- 每次播放 `playWithAccompaniment` 生成 backingTrack 后，按 `StyleEngine.shared.isStyStyle(style)` 设定每轨"内容增益 contentGain"，节点最终音量 = **UI 推子 × contentGain**：
  - **独奏轨(0)**：恒 `seatMelody(1.0) × trimMelody`，不做来源归一（独奏永远基准、最响）。
  - **手写风格（非 .sty）**：伴奏三轨 = Java 席位（piano 0.315 / bass 0.472 / drum 0.472）× trim。手写即响度基准，不再缩放。
  - **.sty 移植风格**：伴奏三轨 = Java 席位 × **自动归一系数 g** × trim。
    - g 按**每小节平均能量**实时计算（消除歌曲长度影响）：`g = √(手写每小节参考能量 ÷ 本风格每小节能量)`，钳到 ≤1.0（只压低、不放大，避免稀疏织体被抬出噪声底）。
    - 鼓轨参考能量额外乘 `drumEnsembleBoost²`（初值 1.4≈+2.9dB），保留完整鼓组存在感，不被压成单件 Ride。
- `updateTrackVolume(track:volume:isMuted:)` **签名不变**（全仓仅 `ContentView.swift:3107-3114` 八处 onChange 调用，已 grep），内部改为"缓存推子/静音 → 重算 节点音量 = 推子×contentGain，masterGain=0"。故 **ContentView、BandMixerView 零改动**，调音台推子手动控制与静音全部保留。
- 校准量（Java 席位、trim、鼓补偿、参考能量、贝斯音域）全部集中在新增的 `AccompanimentMix.swift`，真机 A/B 只改这一个文件。
- 自动归一**每次按当前 backingTrack 实时算、不做跨曲缓存**：多小节平均后随机拼装的能量波动被摊薄，且能自适应和声与曲长。备选"按 styleId 缓存首次系数"在 §9 列出，若真机听出同风格每次轻微跳再启用。

---

## 4. 逐 hunk 精确 diff

### H0｜新增 `Real imPro/MidiPlayer/StyleEngine/AccompanimentMix.swift`（新文件全文）

```swift
import Foundation

// MARK: - P3-c 伴奏混音 / 贝斯音域 校准常量（纯播放·渲染层；不改生成算法与 .sty 资源）
// 乐手版：把移植来的 Java 伴奏与 App 原手写伴奏的音量拉到同一档，再按 Java 原版主次
// （独奏最响、钢琴垫底、贝司/鼓居中）摆位；并把贝司音区沉回传统 walking 区间。
// 真机并听 Java 校准时只需调本文件常量，不必动引擎。
enum AccompanimentMix {

    // ① Java 原版固定通道席位（imp/util/Preferences.java :123-143，值/127 = 线性振幅）
    //    MELODY=127(1.0)  BASS=60(0.472)  DRUMS=60(0.472)  CHORDS=40(0.315)
    static let seatMelody: Float = 127.0 / 127.0   // 1.000 独奏（萨克斯）满席，不做来源归一
    static let seatBass: Float   = 60.0  / 127.0   // 0.472
    static let seatDrum: Float   = 60.0  / 127.0   // 0.472
    static let seatPiano: Float  = 40.0  / 127.0   // 0.315

    // ② 真机校准总旋钮（默认 1.0；某轨整体偏轻/偏响就调这里：>1 提亮，<1 压暗）
    static let trimMelody: Float = 1.0
    static let trimBass: Float   = 1.0
    static let trimDrum: Float   = 1.0
    static let trimPiano: Float  = 1.0

    // ③ 鼓"编制补偿"（振幅倍数，能量乘平方）：.sty 是完整鼓组、手写基准仅单件 Ride，
    //    严格按能量归一会把鼓组压残；故把鼓的目标响度相对手写基准上调。1.4≈+2.9dB，真机定
    //    （鼓残就↑到 1.6，轰/抢戏就↓到 1.2）。
    static let drumEnsembleBoost: Float = 1.4

    // ④ 手写 Simple Swing 参考能量 Σvel²（16 小节 Cmaj7/Am7/Dm7/G7，spm480，种子12345 实测）。
    //    运行时按"每小节平均能量"比较，与曲长无关。
    static let refMeasures: Double = 16
    static let refDrumEnergy: Double = 603200
    static let refBassEnergy: Double = 504400
    static let refPianoEnergy: Double = 312148

    // ⑤ 贝斯音域：覆盖 .sty 文件头普遍的 G2-C4（偏高），回到 Java 引擎内置默认 G1-G3。
    //    Style.java:188 bassLow=g---(G1=31)、:193 bassHigh=g-(G3=55)；.sty 在 load():790-797 覆盖之。
    //    备选更沉的传统四弦 walking 音区 E1-G3：把 bassRangeLow 改为 28（电贝最低空弦 E1）做真机 A/B。
    static let bassRangeLow: Int = 31    // G1
    static let bassRangeHigh: Int = 55   // G3
}
```

### H1｜`JazzMidiPlayer.swift` 属性区（现 :14 `private var playTask` 一行之后）新增混音状态

在
```swift
    private var playTask: Task<Void, Never>?
    private var vibratoTimer: DispatchSourceTimer?
```
之间/之后插入：
```swift
    // [P3-c] 伴奏混音：UI 推子缓存 + 每轨"内容增益"（来源归一 × Java 席位）。
    // 节点最终音量 = 推子 × 内容增益；masterGain 固定 0dB，音量只走线性 .volume。
    // 轨道编号：0=sax 独奏 / 1=piano / 2=bass / 3=drum；推子默认 0.8 与 ContentView @State 一致。
    private var faderVolume: [Float] = [0.8, 0.8, 0.8, 0.8]
    private var faderMuted: [Bool] = [false, false, false, false]
    private var contentGain: [Float] = [1.0, 1.0, 1.0, 1.0]
```

### H2｜`JazzMidiPlayer.swift:95-107` 整段替换 `updateTrackVolume`，并新增三个混音方法

旧码（**原位中文封存，不删除**）：
```swift
    // MARK: - 🎛️ 调音台音量/静音控制
    func updateTrackVolume(track: Int, volume: Float, isMuted: Bool) {
        let finalVolume = isMuted ? 0.0 : max(0, min(1, volume))
        let target: AVAudioUnitSampler
        switch track {
        case 0: target = sampler        // 萨克斯旋律
        case 1: target = pianoSampler   // 钢琴
        case 2: target = bassSampler    // 贝斯
        case 3: target = drumSampler    // 鼓
        default: return
        }
        target.volume = finalVolume
        target.masterGain = finalVolume
    }
```

新码：
```swift
    // MARK: - 🎛️ 调音台音量/静音控制
    // [旧码封存 P3-c 20261011] 旧实现把线性音量误赋给 dB 单位的 masterGain（0.8 被当 +0.8dB≈110%）：
    //   func updateTrackVolume(track: Int, volume: Float, isMuted: Bool) {
    //       let finalVolume = isMuted ? 0.0 : max(0, min(1, volume))
    //       let target: AVAudioUnitSampler
    //       switch track { case 0: target = sampler; case 1: target = pianoSampler
    //                     case 2: target = bassSampler; case 3: target = drumSampler; default: return }
    //       target.volume = finalVolume
    //       target.masterGain = finalVolume   // ← dB 单位误用
    //   }
    func updateTrackVolume(track: Int, volume: Float, isMuted: Bool) {
        guard (0...3).contains(track) else { return }
        faderVolume[track] = max(0, min(1, volume))
        faderMuted[track] = isMuted
        applyTrackGain(track)
    }

    /// 重算单轨节点音量：静音=0；否则 = 推子 × 内容增益（线性振幅，钳 0...1）。masterGain 恒 0dB。
    private func applyTrackGain(_ track: Int) {
        let target: AVAudioUnitSampler
        switch track {
        case 0: target = sampler        // 萨克斯旋律
        case 1: target = pianoSampler   // 钢琴
        case 2: target = bassSampler    // 贝斯
        default: target = drumSampler   // 鼓
        }
        let v = faderMuted[track] ? 0.0 : max(0, min(1, faderVolume[track] * contentGain[track]))
        target.volume = v
        target.masterGain = 0.0   // dB 单位，0 = 单位增益；音量只走线性 .volume（修复旧码 dB 误用）
    }

    /// 四轨全部重算（开始播放/切换风格后调用）。
    private func applyAllTrackGains() {
        for t in 0...3 { applyTrackGain(t) }
    }

    /// [P3-c] 按风格来源设定伴奏内容增益并立即落到四个节点。
    /// 独奏(0)恒满席；手写风格伴奏 = Java 席位；.sty 伴奏 = Java 席位 × 每小节能量自动归一系数
    /// （拉到手写基准；鼓另给编制补偿）。UI 推子与静音在外层 applyTrackGain 内相乘，View 无需改动。
    private func configureAccompanimentMix(style: String, track backing: BackingTrackData, measureCount: Int) {
        let measures = max(1, measureCount)
        let isSty = StyleEngine.shared.isStyStyle(style)

        // 每小节平均能量 Σvel²（velocity 双保险钳 1...127，非法值不进能量）
        func perMeasureEnergy(_ notes: [CompanionNote]) -> Double {
            let e = notes.reduce(0.0) { acc, n in
                let v = Double(max(1, min(127, Int(n.volume))))
                return acc + v * v
            }
            return e / Double(measures)
        }
        // 节点振幅归一系数 g = √(手写参考每小节能量 ÷ .sty 每小节能量)；鼓参考能量乘编制补偿²。
        // 钳 ≤1.0：只压低、不放大，避免稀疏织体被抬出噪声底。
        func norm(_ refTotal: Double, _ styPerMeasure: Double, boost: Float = 1.0) -> Float {
            let refPerM = refTotal / AccompanimentMix.refMeasures * Double(boost * boost)
            return Float(max(0, min(1.0, sqrt(refPerM / max(1, styPerMeasure)))))
        }

        var gain: [Float] = [
            AccompanimentMix.seatMelody * AccompanimentMix.trimMelody,   // 0 独奏恒满席
            AccompanimentMix.seatPiano  * AccompanimentMix.trimPiano,    // 1 钢琴（手写基准值；.sty 下方覆盖）
            AccompanimentMix.seatBass   * AccompanimentMix.trimBass,     // 2 贝斯
            AccompanimentMix.seatDrum   * AccompanimentMix.trimDrum      // 3 鼓
        ]
        if isSty {
            let gP = norm(AccompanimentMix.refPianoEnergy, perMeasureEnergy(backing.pianoNotes))
            let gB = norm(AccompanimentMix.refBassEnergy,  perMeasureEnergy(backing.bassNotes))
            let gD = norm(AccompanimentMix.refDrumEnergy,  perMeasureEnergy(backing.drumNotes),
                          boost: AccompanimentMix.drumEnsembleBoost)
            gain[1] = AccompanimentMix.seatPiano * gP * AccompanimentMix.trimPiano
            gain[2] = AccompanimentMix.seatBass  * gB * AccompanimentMix.trimBass
            gain[3] = AccompanimentMix.seatDrum  * gD * AccompanimentMix.trimDrum
        }
        contentGain = gain
        applyAllTrackGains()
    }
```

### H3｜`JazzMidiPlayer.swift` playWithAccompaniment（现 :431 `let swing = SwingProfile(...)` 之后、:433 `playTask = Task {` 之前）插入一次调用

```swift
        let swing = SwingProfile(melody: backingTrack.melodySwing ?? baseProfile.melody,
                                 comp: backingTrack.compSwing ?? baseProfile.comp)

        // [P3-c] 按风格来源（手写 / .sty）设定伴奏三轨内容增益并立即落到节点
        // （修 masterGain dB 误用 + .sty 与手写响度拉平 + Java 主次摆位）。
        configureAccompanimentMix(style: style, track: backingTrack, measureCount: remainingMeasures)

        playTask = Task {
```

> 第二入口 `playWithAccompanimentAndGraces`（约 :689）经全仓 grep 为**零调用 dead code**，本轮不接线、不改动（P3-a 已记录）。

### H4｜`StyleChordRenderer.swift:142` 钢琴随机力度 clamp（±8 人性化保留）

旧码封存 + 新码：
```swift
        // 同一击弦点所有音共用一个力度（±8 人性化）；起点每音独立 ±3（模拟手指滚奏）。
        // [旧码封存 P3-c] UInt8(clamping:) 上限 255，baseVelocity=127 再 +8 会产出非法 velocity 135：
        // let velocity = UInt8(clamping: Int(baseVelocity) + rng.nextInt(17) - 8)
        // [P3-c] ±8 人性化保留，力度钳到合法 7-bit 区间 1...127。
        let velocity = UInt8(max(1, min(127, Int(baseVelocity) + rng.nextInt(17) - 8)))
```

### H5｜`StyleChordRenderer.swift:106-109` .sty V 力度标记 clamp

旧码：
```swift
            if lead == "V", let v = Int(rest) {
                velocity = UInt8(clamping: v)
                continue
            }
```
新码：
```swift
            if lead == "V", let v = Int(rest) {
                // [旧码封存 P3-c] velocity = UInt8(clamping: v)   // clamping 上限 255，拦不住 >127
                velocity = UInt8(max(0, min(127, v)))   // [P3-c] .sty V 力度标记钳到合法区间
                continue
            }
```

### H6｜`StyleBassRenderer.swift:38` 贝斯音域覆盖回 G1–G3

旧码：
```swift
        let low = parsed.bassLow, high = parsed.bassHigh
```
新码：
```swift
        // [旧码封存 P3-c 20261011] .sty 文件头音域（普遍 G2-C4，贝司听感偏高）：
        // let low = parsed.bassLow, high = parsed.bassHigh
        // [P3-c] 渲染端统一覆盖回 Java 引擎内置默认 G1-G3（Style.java:188 g--- / :193 g-）；
        // parsed.bassLow/High 仍照常解析保留，仅不再作为渲染边界。备选 E1-G3 见 AccompanimentMix 注释。
        let low = AccompanimentMix.bassRangeLow
        let high = AccompanimentMix.bassRangeHigh
```
> 已 grep 确认 `parsed.bassLow/bassHigh` 在贝斯渲染侧仅此一处消费；`bassBase` 解析后未使用；`chordLow/chordHigh` 只属钢琴（`StyleChordRenderer.swift:26-27`），故本改动不影响钢琴/鼓/解析。

### H7｜`StyleBassRenderer.swift:143-146` 贝司 V 力度标记 clamp（纵深防御）

旧码：
```swift
            if lead == "V" {
                events.append(Event(op: .volume(UInt8(clamping: Int(rest) ?? 100)), slots: 0))
                continue
            }
```
新码：
```swift
            if lead == "V" {
                // [旧码封存 P3-c] events.append(Event(op: .volume(UInt8(clamping: Int(rest) ?? 100)), slots: 0))
                let vv = Int(rest) ?? 100
                events.append(Event(op: .volume(UInt8(max(0, min(127, vv)))), slots: 0))  // [P3-c] 钳 0...127
                continue
            }
```

> 播放端 `JazzMidiPlayer.swift:463-464` 的 ±3/±2 人性化与 `min(127)` 兜底**原样保留**（源头修好后它是第二道保险）；鼓力度在 `StyleParser` 解析期已 clamp，本轮不动。

---

## 5. 一键回退脚本 `scripts/rollback_p3c.sh`（落地时新建）

```bash
#!/bin/bash
# P3-c 一键回退：恢复 3 个被改文件、删除新增 AccompanimentMix.swift，并做 SHA1 自检。
set -u
PROJ="/Users/onlyonear/Desktop/Improlyze"
BAK="$PROJ/.backup/P3c-20261011"
cd "$PROJ" || exit 9

cp "$BAK/JazzMidiPlayer.swift.bak"        "$PROJ/Real imPro/MidiPlayer/JazzMidiPlayer.swift"
cp "$BAK/StyleChordRenderer.swift.bak"    "$PROJ/Real imPro/MidiPlayer/StyleEngine/StyleChordRenderer.swift"
cp "$BAK/StyleBassRenderer.swift.bak"     "$PROJ/Real imPro/MidiPlayer/StyleEngine/StyleBassRenderer.swift"
rm -f "$PROJ/Real imPro/MidiPlayer/StyleEngine/AccompanimentMix.swift"

echo "== SHA1 自检（应回落到改前基线）=="
shasum -a 1 "$PROJ/Real imPro/MidiPlayer/JazzMidiPlayer.swift" \
            "$PROJ/Real imPro/MidiPlayer/StyleEngine/StyleChordRenderer.swift" \
            "$PROJ/Real imPro/MidiPlayer/StyleEngine/StyleBassRenderer.swift"
# 期望：
# 85f300d2d84e58af32fce7801b950e18a8d19e07  JazzMidiPlayer.swift
# 4603690cbe379fae4552db7896f938109c8a0476  StyleChordRenderer.swift
# 8ad71953817c2390075f373ade15251ec3c8a3bb  StyleBassRenderer.swift
echo "回退完成：请在 Xcode ⇧⌘K Clean Build Folder 后 ⌘B 全量重建。"
```

---

## 6. 落地步骤（书面批准后按序执行）

1. 整文件备份 3 个待改文件到 `.backup/P3c-20261011/`，`shasum -a 1` 与 §1 基线逐一核对。
2. 落盘新增 `AccompanimentMix.swift`（H0）。
3. 逐 hunk 应用 H1–H7（旧码一律中文注释原位封存）。
4. 新建 `scripts/rollback_p3c.sh`，`bash -n` 语法自检。
5. Xcode GUI：先 ⇧⌘K Clean Build Folder（当前 Run 为 Release；本改不增删资源，Debug/Release 均验），再 ⌘B，要求 **Build Succeeded、0 error**（命令行 AssetCatalogAgent spawn 环境怪象忽略，以 GUI 为准）。
6. 跑 §7 数值门与 43 CLEAN 探针。
7. 装真机/模拟器走 §7 真机 A/B 校准门，回报数值与听感；`find -newermt` 核无夹带。

---

## 7. 回归门清单（落地后实测回报）

### 7.1 solo 数值金标准（本轮零改动 solo 源文件，必须逐音不变）
- Guide 音符数 **18,470**；raw grammar **30/30 OK / BAD=0**、FNV 稳定；Transform 对 Java **diff=0**、时值守恒 **0** 违例；Learning combination / greatMoments 各 **1536/1536**。
### 7.2 资源指纹（不增删资源，必须不变）
- 包内 **26 个 .tsv = 11,235,463 B**；combination.rnn / GreatMoments.rnn 各 **9,136,016 B**（合计 18,272,032）；**.sty = 43**。
### 7.3 伴奏引擎回归（scripts/p3b_regress.sh，43 项）
- 预期 **43 CLEAN / WARN0 / CRASH0 / MISSING0** 仍全绿——该探针 CLEAN 判定只看 pattern 数、空轨、鼓填充、未映射码/令牌，**不判定贝司音域与 velocity**（span 仅打印、t 时值不判 FAIL，见探针 main:84-100）。
- 人工核对打印变化（非 FAIL）：swing 贝司 span 由 `44-57` 下沉到约 `36-55`、b 计数 68→66、总时值仍 7680；钢琴 velocity 越界数归 0（可复跑 /tmp/p3c 探针验证 327→0）。
### 7.4 构建
- Xcode GUI **Debug + Release 各 Build Succeeded、0 error**。
### 7.5 真机 A/B 校准门（艺术项，本轮核心，逐条回报听感）
1. **贝司音区**：G1–G3 明显沉稳、walking 连贯（首拍根音 16/16 已探针验证）；若想更低沉，把 `AccompanimentMix.bassRangeLow` 改 28（E1）重听 A/B，二选一后定稿。
2. **响度一致性**：在 Simple Swing 与 swing（.sty）及 rock/latin/funk/shuffle 间切换，伴奏三轨不再"一响一轻"。
3. **主次关系**：加独奏后萨克斯突出、钢琴垫底、贝司/鼓居中（对齐 Java 127/40/60/60）；只放伴奏若整体偏轻属预期（见 §9 调法），按听感定 trim。
4. **鼓组**：完整鼓组不被压残（初值 boost=1.4；残→1.6，轰→1.2）。
5. **推子/静音**：调音台四轨推子手动调节、静音仍实时有效；切换风格即时刷新；推子位置与实际响度对应。
6. **稳定性**：同一风格多次播放响度无明显跳动（若听得出，启用 §9 的按 styleId 缓存方案）。
### 7.6 UI / 路径
- 本轮**无任何 UI 布局改动**（纯音频/渲染），界面像素零变化；首屏装包启动不崩、默认仍 Simple Swing、Demo 无旋律谱不空白即可（6 组尺寸非本轮强制，无布局变更）。
### 7.7 无夹带
- `find "Real imPro" -newermt '<落地开始时间>' -name '*.swift'` 仅出现 3 改 + 1 新增；备份与脚本在工程内单独列明。

---

## 8. 无夹带声明 / 明确不改

- 仅改动 §1 的 **3 改 + 1 新增**；不碰：solo 四链路（Guide/Grammar/Transform/Learning）任何引擎与默认值、Roadmap 分析、`.sty/.tsv/.rnn` 资源、`ContentView.swift`、`BandMixerView.swift`、`AccompanimentModels.swift`（数据结构零改动）、`AccompanimentGenerator.swift`（分流不变）、第二播放入口 dead code、pbxproj。
- 不翻任何默认（出厂风格仍 Simple Swing、UI 推子默认 0.8、各色彩键不变）、不新增付费点/顶栏、用户可见无「Java」。
- 旧码全部中文注释原位封存、不删除；备份含 SHA1；提供一键回退。

---

## 9. 风险、预期听感与备选（真机校准指南）

- **整体可能偏轻（预期，非 bug）**：严格对齐 Java 主次并拉平后，钢琴内容增益约 0.09–0.21、贝司 0.25–0.47、鼓 0.15–0.36（再乘 UI 推子 0.8）。这正是 Java "独奏 127 压过伴奏 40/60" 的配比。真机若认为只放伴奏时太轻，按下列顺序调（只改 `AccompanimentMix.swift`）：
  1. 三轨 trim 统一提到 1.2（≈+1.6dB）或 1.4（≈+2.9dB），整体提亮、主次不变；
  2. 仍偏轻再放宽 Java 席位（如 seatPiano 40→52、seatBass/Drum 60→72），等价于整体重摆主次；
  3. 独奏若相对过响，可把 trimMelody 降到 0.9。
- **归一系数随每次生成微波动**：当前实时按每小节能量算（多小节平均后波动很小）。若真机在短曲上听出同风格响度跳，改为按 `styleId` 缓存首次 g（在 JazzMidiPlayer 加 `[String:[Float]]` 缓存），后续复用——这是唯一需要的后续小改，届时另出 hunk。
- **贝司 E1–G3 备选**：`bassRangeLow=28`。探针显示平均 F#2(41.6)、几乎全在 C2–B2，更贴四弦空弦起步的传统 walking，但 Java 出厂默认用 G1（不碰最低 E1 弦）；以真机并听 Java 二选一。
- **钢琴 ±8/±3 人性化保留**（Swift 增强、幅度小、.sty 验收口径为规则/听感同源非逐音对齐），仅把力度 clamp 进 1...127；起点 ±3 已 `max(0,...)`。
- 探针源码 `/tmp/p3c/main.swift`、结果 `/tmp/p3c/out.txt` 留存可复跑（/tmp 可能被清，需要时按 §2 条件重建）。
