# P3-a 逐 hunk 落地 diff（下篇）—— Java swing.sty 通用伴奏引擎接入

> 状态：**待书面批准**（如「批准 P3-a 按此 diff 落地」）。批准前生产零改动。
> 范围：把已在 `/tmp` 双探针（均 ALL PASS）与暂存目录 `.p3a_staging/StyleEngine/`（11 文件，已 `swiftc -parse` 通过）验证的**通用 .sty 加载/展开引擎**接入生产，仅打包标准 `swing.sty`，DEBUG 临时菜单入口打通鼓/贝斯/钢琴三轨真机直听。**菜单二级化与其余 45 个 .sty 属 P3-b，本轮不做。**
> 性质：纯**新增能力 + 4 处接线**，不改任何 solo 四链路算法/引擎/整流/默认值/付费/持久化键。

---

## 一、落地清单总览

| 类型 | 路径 | 说明 |
|---|---|---|
| 新增目录 | `Real imPro/MidiPlayer/StyleEngine/` | 11 个新 Swift 文件（同步根自动入 target 编译） |
| 新增资源 | `Real imPro/Resources/Styles/swing.sty` | 2711 B，从 Java `styles/swing.sty` 原样拷贝（字节一致） |
| 改 ① | `Real imPro/MidiPlayer/AccompanimentModels.swift` | BackingTrackData 加 2 个可选 Double（Hunk A） |
| 改 ② | `Real imPro/MidiPlayer/AccompanimentGenerator.swift` | switch 前前置 .sty 分支（Hunk B） |
| 改 ③ | `Real imPro/MidiPlayer/JazzMidiPlayer.swift` | 主入口用 .sty 文件头 swing 覆盖（Hunk C） |
| 改 ④ | `Real imPro/Views/BandMixerView.swift` | `#if DEBUG` 临时菜单项 sty:swing（Hunk D） |
| 新增脚本 | `scripts/rollback_p3a.sh` | 一键回退 |

**11 个新文件**（职责与指纹见第四部分，完整代码见附录 A，均以暂存磁盘版为准、零手工转写）：
StyleSExpression / StyleDuration / StyleNoteName / StyleDrumMap / StyleModel / StyleParser / StyleScaleTable / StyleEngine / StyleBassRenderer / StyleDrumRenderer / StyleChordRenderer。

**dead code 声明**：`JazzMidiPlayer.playWithAccompanimentAndGraces`（定义 :689、generate :706）经全工程 grep 确认**零调用**（三处真实播放 ContentView:2836/3144/3259 全走主入口 `playWithAccompaniment`）。本轮**不接线、不改动**该遗留路径。

---

## 二、备份计划与基线哈希

落地第一步先整文件备份 4 个被改生产文件到 `.backup/P3a-20261010/`，并与下表 SHA1 逐一核对（均为 P2.3b 后、P3-a 前的当前值）：

| 文件 | 落地前 SHA1 |
|---|---|
| `Real imPro/MidiPlayer/AccompanimentModels.swift` | `6e2f6de8044595ca9a6c99c23ebda3ee86a28ebb` |
| `Real imPro/MidiPlayer/AccompanimentGenerator.swift` | `53cf8b95760526482df7f01e19245b20165bb943` |
| `Real imPro/MidiPlayer/JazzMidiPlayer.swift` | `0ef3235edac36ce352f5d9066b6d8e6e5649d84d` |
| `Real imPro/Views/BandMixerView.swift` | `88e9d3f559cf68f11fd5b4398db07701b2ce63f8` |

备份命令（落地时执行）：
```bash
cd "/Users/onlyonear/Desktop/Improlyze"
mkdir -p .backup/P3a-20261010 scripts \
         "Real imPro/MidiPlayer/StyleEngine" "Real imPro/Resources/Styles"
cp "Real imPro/MidiPlayer/AccompanimentModels.swift"  .backup/P3a-20261010/
cp "Real imPro/MidiPlayer/AccompanimentGenerator.swift" .backup/P3a-20261010/
cp "Real imPro/MidiPlayer/JazzMidiPlayer.swift"       .backup/P3a-20261010/
cp "Real imPro/Views/BandMixerView.swift"             .backup/P3a-20261010/
shasum -a 1 .backup/P3a-20261010/*.swift   # 必须与上表 4 个 SHA1 完全一致
```

一键回退脚本 `scripts/rollback_p3a.sh`（回退 = 恢复 4 文件 + 删除新增引擎目录与 swing.sty）：
```bash
#!/bin/bash
set -e
ROOT="/Users/onlyonear/Desktop/Improlyze"
BAK="$ROOT/.backup/P3a-20261010"
cd "$ROOT"
cp "$BAK/AccompanimentModels.swift"   "$ROOT/Real imPro/MidiPlayer/AccompanimentModels.swift"
cp "$BAK/AccompanimentGenerator.swift" "$ROOT/Real imPro/MidiPlayer/AccompanimentGenerator.swift"
cp "$BAK/JazzMidiPlayer.swift"        "$ROOT/Real imPro/MidiPlayer/JazzMidiPlayer.swift"
cp "$BAK/BandMixerView.swift"         "$ROOT/Real imPro/Views/BandMixerView.swift"
rm -rf "$ROOT/Real imPro/MidiPlayer/StyleEngine"
rm -f  "$ROOT/Real imPro/Resources/Styles/swing.sty"
rmdir  "$ROOT/Real imPro/Resources/Styles" 2>/dev/null || true
rmdir  "$ROOT/Real imPro/Resources"        2>/dev/null || true
echo "P3-a 已回退；请在 Xcode ⌘⇧K Clean 后重新 ⌘B 验证。"
```

---

## 三、4 处接线 hunk（旧码 → 新码）

### Hunk A — `AccompanimentModels.swift`（BackingTrackData，现 :6–10）

**旧码（原样）**
```swift
struct BackingTrackData {
    var bassNotes: [CompanionNote] = []
    var pianoNotes: [CompanionNote] = []
    var drumNotes: [CompanionNote] = []
}
```

**新码（新增 2 个可选字段，全默认 nil，旧的无参构造与所有现有调用零影响）**
```swift
struct BackingTrackData {
    var bassNotes: [CompanionNote] = []
    var pianoNotes: [CompanionNote] = []
    var drumNotes: [CompanionNote] = []
    // [P3-a 新增] .sty 伴奏型文件头自带的 swing / comp-swing；nil=旧手写风格，由播放层按风格名猜测
    var compSwing: Double? = nil
    var melodySwing: Double? = nil
}
```

---

### Hunk B — `AccompanimentGenerator.swift`（segments 统一之后、原 switch 之前，现 :29–32）

**旧码（原样）**
```swift
                             durationSlots: slotsPerMeasure)
            }
        }
        
        switch style.lowercased() {
        case "ballad":
```

**新码（在原 switch 前插入 .sty 前置分支；原手写 switch 原样保留、继续服务 Simple/手写风格，不属于封存死码）**
```swift
                             durationSlots: slotsPerMeasure)
            }
        }

        // [P3-a 新增] Java .sty 伴奏型（styleId 形如 "sty:swing"）：交通用 StyleEngine 解析 bundle 内 .sty 并展开三轨，命中即返回。
        if StyleEngine.shared.isStyStyle(style) {
            return StyleEngine.shared.render(styleId: style,
                                             measureCount: measureCount,
                                             chordSegments: segments,
                                             slotsPerMeasure: slotsPerMeasure)
        }

        // [P3-a 说明] 下方手写风格 switch 原样保留：.sty 已在上方提前 return；选 "Swing"/"Ballad"/... 仍走原手写路径，行为不变。
        switch style.lowercased() {
        case "ballad":
```

> 说明：`render` 的 `seed` 参数有默认值 `nil`（真随机，正式播放每次不同，与 Java 一致）；固定种子仅用于回归/DEBUG，接线处不传。`render` 只依赖 `chordSegments`（不需要 chordSymbols）。

---

### Hunk C — `JazzMidiPlayer.swift`（主入口 playWithAccompaniment，现 :424–428）

`SwingProfile` 是 `private struct SwingProfile { let melody; let comp }`（:349，**字段为 let 不可变**），故不能就地改字段，改为 generate 后合成一个常量。

**旧码（原样）**
```swift
        let swing = Self.swingProfile(for: style)
        let backingTrack = AccompanimentGenerator.shared.generate(
            style: style, measureCount: remainingMeasures,
            chordSymbols: realChords, chordSegments: chordSegments, slotsPerMeasure: spm
        )
```

**新码（.sty 用文件头 swing/comp-swing 覆盖；非 .sty 两字段 nil，回退默认，结果与旧版逐值一致）**
```swift
        // [P3-a] 先取按风格名猜测的默认 swing；generate 后若为 .sty（BackingTrackData 带文件头值）则覆盖，nil 回退默认。
        let baseProfile = Self.swingProfile(for: style)
        let backingTrack = AccompanimentGenerator.shared.generate(
            style: style, measureCount: remainingMeasures,
            chordSymbols: realChords, chordSegments: chordSegments, slotsPerMeasure: spm
        )
        let swing = SwingProfile(melody: backingTrack.melodySwing ?? baseProfile.melody,
                                 comp: backingTrack.compSwing ?? baseProfile.comp)
```
其后 :431–434 三轨 `compSwing: swing.comp` 与旋律 `melodySwing: swing.melody` **不变**。第二入口 `playWithAccompanimentAndGraces`（dead code）**不碰**。

---

### Hunk D — `BandMixerView.swift`（MixerDisplayMode 枚举，现 :3–12；DEBUG-only）

**旧码（原样）**
```swift
enum MixerDisplayMode: String, CaseIterable {
    case swing  = "Swing"
    case ballad = "Ballad"
    case blues  = "Shuffle"
    case afro   = "Afro"
    //case bebop  = "Bebop"
    case bossa  = "Bossa"
    case waltz  = "Waltz"
    case latin  = "Latin"
}
```

**新码（末尾加 DEBUG-only 临时项；Release 不编译，P3-b 二级菜单正式接入后移除）**
```swift
enum MixerDisplayMode: String, CaseIterable {
    case swing  = "Swing"
    case ballad = "Ballad"
    case blues  = "Shuffle"
    case afro   = "Afro"
    //case bebop  = "Bebop"
    case bossa  = "Bossa"
    case waltz  = "Waltz"
    case latin  = "Latin"
    #if DEBUG
    // [P3-a 临时] 真机直听 Java swing.sty；rawValue 即 styleId，经 selectedStyle.rawValue 透传到 Hunk B 前置分支。
    case stySwing = "sty:swing"
    #endif
}
```
> 已核实无穷尽 switch 风险：风格菜单为 `ForEach(allCases){ Text(style.rawValue.capitalized) }`（:154-163，无图标 switch）；`matchStyleMode`（ContentView:2418-2426）是 contains 链 + `return .swing` 兜底；`onChange` 仅透传 `newStyle.rawValue`。加 DEBUG case 不破坏任何分支。
> 折叠态 STYLE 胶囊显示 `rawValue.uppercased()`＝`STY:SWING`（9 字符，110 宽胶囊 + 10pt + `minimumScaleFactor(0.8)` + lineLimit1），仅 DEBUG 可见；mini 竖屏需截图确认不截断（见回归门）。

---

## 四、11 个新文件（拷贝落地 + 指纹校验）

落地用整目录拷贝（不用手工新建，避免转写漂移），拷贝后逐文件校验 SHA256：
```bash
cd "/Users/onlyonear/Desktop/Improlyze"
cp .p3a_staging/StyleEngine/*.swift "Real imPro/MidiPlayer/StyleEngine/"
shasum -a 256 "Real imPro/MidiPlayer/StyleEngine/"*.swift   # 必须与下表一致
```

| 文件 | 字节 | SHA256 |
|---|---|---|
| StyleSExpression.swift | 3108 | `bf3e567a1849fa3badd141eabbd8994742808e597aae8c9414fbe3a1b56a0a6c` |
| StyleDuration.swift | 2782 | `9230286b637174fa974bc40597280ce789fc17a097cd9ea3d4bcbf9cdd5a1367` |
| StyleNoteName.swift | 1273 | `b6ef2cdfb8365f52039ac3b8b1fb2dbeca1ffd426707cfb329bda583ecd7f4ec` |
| StyleDrumMap.swift | 3053 | `a9fafc7e83290b34f60b77da6023c1a47c0e577633d5bb972f2af5381de4d699` |
| StyleModel.swift | 1907 | `8f545b8b3de3b0431a6b902f592f3d3359babe5940bcfab0b42e6227a9b97e6c` |
| StyleParser.swift | 7604 | `a1b48f4f8bad422d9d6f635f0b674d03048a7b9bb02325f8634fd5bface03811` |
| StyleScaleTable.swift | 5796 | `dfce2c7ea2ed59721699c9b19bcd5a5c931f4d234fcfcc58d4d6daad61fd40aa` |
| StyleEngine.swift | 4984 | `3a698491a5ef6f536aa0ff3c31409df8d6f43a46f0b969368a191e36c2ed7f0c` |
| StyleBassRenderer.swift | 12854 | `a34d727fb0b91e99c9ae6392dce8d994355b4237a548782797df9ee3a295fcaf` |
| StyleDrumRenderer.swift | 2296 | `9fca9c0c05561181a564398db07701b280234e0fae468dc725601feb1b537a7834` |
| StyleChordRenderer.swift | 7263 | `42c97dd1a37a06e4313dc47d6e59da76efd85ecadd33e5380849caaea1eb7e54` |

资源：
```bash
cp .p3a_staging/Resources/swing.sty "Real imPro/Resources/Styles/swing.sty"
shasum -a 256 "Real imPro/Resources/Styles/swing.sty"
# 期望 6f793ab056720150551e510b293c50571af834ec2f8a9285d9cf00327f9e9e62 ，2711 B（与 Java 原文件字节一致）
```

### 引擎分层（一句话乐手版 + 工程定位）
- **乐手版**：这 11 个文件等于把 Impro-Visor 的「编曲配方读取器 + 鼓/贝斯/钢琴三件套演奏员」整套搬进 iOS。App 读到 `swing.sty` 这份配方，按里面的权重每次随机抽取鼓点句型、贝斯走句、钢琴铺底句，拼成完整伴奏；同一份配方每次演奏略有不同，和桌面版一个道理。
- S 表达式解析（StyleSExpression/Parser/Model）、时值换算（StyleDuration，whole=480，8/3=40、4.=180、64/3=5）、音名（StyleNoteName，中央 c=60，g--=43）、GM 鼓表 47 件 index+35（StyleDrumMap，Acoustic_Bass_Drum=35）。
- 贝斯（StyleBassRenderer）：完整 B/C/S/A/N/R/=/V/degree 取音、transpose(-24)、Java 精确 `pressure`（center=high quirk、四次方概率，BassPattern.java:1096-1137）、确定性 `placePitchNear`（MARGIN=11）、[low,high] 钳、getPattern 加权拼满、末段趋近指下一和弦、初始音=音域中点、channel 2。
- 鼓（StyleDrumRenderer）：逐小节加权抽 drum-pattern → 转现有 DrumPattern/DrumRule → 复用已验证 `DrumPatternExtractor.generate`（同 slot 去重、channel 9）。
- 钢琴（StyleChordRenderer）：自建、不改 ChordPatternExtractor；单个贯穿全曲的 `FullVoicingEngine`（音域 d-(50)~a(69)、open）经 `ChordSymbolMapper.resolve → engine.voicing(forForm:rootRise:)` 保声部连接；时间线复刻 `generateTimeline` 的 residual/origin/segLen/push（仅 firstOfSeg&&origin==0）/负起点钳 0/跨小节切割；channel 1。

---

## 五、swing.sty 资源收录验证（唯一可能动 pbxproj 处）

工程用 `PBXFileSystemSynchronizedRootGroup`（同步根 path="Real imPro"），`.swift` 自动入 target；但**非源码扩展名 `.sty` 是否自动归为 resource 未经验证**。落地 Build 后用两条硬证据确认：
```bash
# ① .app 包内是否实际收录 swing.sty（不依赖运行时）
find ~/Library/Developer/Xcode/DerivedData/RealimPro-* -name "swing.sty" -path "*.app*"
```
② DEBUG 菜单选 `sty:swing` 播放，鼓/贝斯/钢琴三轨有声（即 `Bundle.main.url(forResource:"swing")` 命中、`StyleEngine.load` 成功）。
引擎 `load` 已对多路径做兜底：Bundle 根、`Styles`、`Resources/Styles`、`Real imPro/Resources/Styles` 子目录依次尝试。

**若 ① 找不到 swing.sty（未被同步根归为 resource）**：这是本轮**唯一**可能需要改 `project.pbxproj` 的地方，**立即暂停并单独报批**（在同步根的 membershipExceptions/resource 归类中显式加入 `.sty`），**不得夹带擅改**。

---

## 六、两处「有意与桌面版同源」的口径（已知晓，非缺陷）

1. **贝斯音区高约八度**：swing.sty 文件头 `bass-low=g--`(G2=43)、`bass-high=c`(C4=60)、`bass-base=e--`(E2=40)，初始音=音域中点 51；比 Swift 手写 Simple Swing（E1=28–G3=55）整体高约八度。这是 swing.sty 明文规定、忠实原版；Simple Swing（手写）与 Swing（Java 移植）两套并存、互不影响。
2. **力度取规则原值、引擎内不做响度压缩**：Java 规则层三轨在无 V 标记时默认均为满力度 **127**（Style.java:1414 钢琴、:2364 贝斯、DrumPattern.java:318 鼓），V 标记（V90/V50/V10…）是相对力度。引擎输出规则原始 velocity（钢琴另加与现有 comping 相同的人性化：力度 ±8、起点 ±3），**不在引擎内乘响度增益**。
   - 原因：线性压缩会把军鼓 fill 的 V10/V20 等弱音压到近无声（×0.6 → 6/12）；Java 规则本就是「127 基准 + 播放端伴奏音量」的设计。
   - **预期现象**：P3-a DEBUG 首听 sty:swing 可能比 Simple Swing 响（尤其钢琴/贝斯长音）。这是忠实规则的中间态。
   - **P3-c 行动项**：真机并听后若需响度平衡，在**播放端伴奏轨**（复用现有 BandMixer 音量轨或加一个三轨同源的单一增益）统一校准全部 46 个风格，**不在引擎内逐轨压**。本轮不实施。

---

## 七、落地步骤（批准后严格按序）

1. 整文件备份 4 个生产文件 → `.backup/P3a-20261010/`，SHA1 与第二部分表核对一致；写 `scripts/rollback_p3a.sh`。
2. 拷贝 11 个新文件到 `Real imPro/MidiPlayer/StyleEngine/`，逐文件 SHA256 与第四部分表核对。
3. 拷贝 swing.sty 到 `Real imPro/Resources/Styles/`，SHA256 核对。
4. 依次应用 Hunk A → B → C → D（旧码不删除：B 的原 switch 保留；A/C/D 为原位增改）。
5. Xcode GUI ⌘B（权威以 GUI 为准；命令行 AssetCatalogAgent/宏插件 spawn 怪象如出现需说明），要求 **Build Succeeded、0 error**。
6. 第五部分 ① 验证 .app 内含 swing.sty；若缺失立即停工报批 pbxproj。
7. 跑第八部分回归门 + 6 组 iPad 尺寸 + 真机三轨并听，回报数值与截图。
8. `find -newermt` 列改动清单，核对无夹带。

---

## 八、回归门（落地后实测回报）

**A. solo 四链路数值金标准（本轮只动伴奏，必须零变化）**
- Guide 音符数 **18,470**；raw grammar **30/30 OK / BAD=0**、FNV 稳定；Transform 对 Java **diff=0**、时值守恒 **0** 违例；Learning 两模型 teacher-forcing 与固定种子自由生成 **1536/1536**。
- 资源指纹：包内 **26 个 .tsv = 11,235,463 B**；combination.rnn / GreatMoments.rnn 各 **9,136,016 B**。
- 选 "Swing"（Simple，手写）等全部旧风格：固定种子逐音不变（.sty 前置分支只认 styleId `sty:swing`，绝不误拦截 "swing"）。

**B. .sty 新增门**
- .app 内含 swing.sty（find 硬证据）；`StyleEngine.load("sty:swing")` 非 nil，三轨 notes 非空。
- 结构/时值（与探针 ALL PASS 同代码路径）：bass 16 条、drum 10 条、chord 3 条句型可加权抽取；chord push=40、长句 1920；鼓 kick=**35**；贝斯音区落在 **43–60**；时值 8/3=40、4.=180、64/3=5、三连/附点正确。
- DEBUG 选 `sty:swing` 播放：三轨有声、swing/comp-swing=0.67 律动正确、贝斯在 G2–C4、钢琴为 open voicing 且随和弦声部连接。
- 钢琴无「整段哑火」（DEBUG 控制台无 `chord: N hit point(s) had no voicing`，或 N=0）。

**C. 构建与 UI**
- Xcode GUI Build Succeeded、0 error。
- 6 组 iPad（mini / 11 / 13 × 横竖；mini 竖先截图）：DEBUG 风格菜单含 `Sty:swing` 项、折叠态 `STY:SWING` 胶囊不截断不溢出、右栏恒宽 110、不压五线谱/#钮。Release 配置该项不可见。
- 真机路径：无旋律谱不空白；选曲/转调/生成/Original⇄Solo 后风格与谱面正确刷新；播放中切风格热重载正常（:3116 onChange 走 sty:swing 也成立）。

**D. 听感对拍（P3-a 主目标，不逐音）**
- 同一首曲，DEBUG `sty:swing` vs Java Impro-Visor 桌面版 swing：鼓句型/贝斯 walking 句读/钢琴铺底与抢拍同源、swing 律动一致；记录主观响度（为 P3-c 播放端增益校准取证）。

---

## 九、无夹带声明

- 改动严格限定：**4 个生产文件接线 + 11 个新增引擎文件 + 1 个 swing.sty + 1 个回退脚本**，无其他。
- 不碰：solo 四链路算法/引擎/整流、Roadmap 两套分析、默认值、付费墙与 IAP、任何 @AppStorage 持久化键、顶栏控件、pbxproj（除非第五部分条件触发并另行报批）。
- 不新增付费点、不新增正式顶栏/菜单入口（DEBUG 项 Release 不编译）、用户可见正式界面无「Java」字样。
- 落地后以 `find "Real imPro" -newermt <落地时刻> -type f` 输出作为改动文件硬证据，与本清单逐一核对。
- 旧码处置：Hunk B 原手写 switch 保留并继续生效（非死码）；Hunk A/C/D 为原位增改，无删除；新增逻辑均带 `[P3-a]` 中文注释。

---


## 附录 A：11 个新文件完整代码

> 由暂存目录 `.p3a_staging/StyleEngine/` 原样拼接（已通过 `swiftc -parse` 与基于真实接口桩的 `swiftc -typecheck` 双闸门），SHA256 见第四部分；落地以整目录 `cp` 为准，请勿手工转写。

### A. StyleSExpression.swift
```swift
import Foundation

// MARK: - StyleSExpression
// 原版 .sty 伴奏型文件的 S-表达式（Lisp 风格）最小解析器。
// 对齐 Java Style.java 的 tokenize / parse：.sty 顶层为若干 (section ...) 嵌套表。
// 纯文本解析，无 UI、无引擎依赖，可被 StyleParser 与测试探针共用。

indirect enum StyleSex: Equatable {
    case atom(String)
    case list([StyleSex])

    var asAtom: String? { if case .atom(let v) = self { return v }; return nil }
    var asList: [StyleSex]? { if case .list(let v) = self { return v }; return nil }
}

enum StyleSExpression {

    /// 解析整段文本，返回顶层表达式序列（.sty 通常只有一个 (style ...)）。
    static func parse(_ text: String) -> [StyleSex] {
        let tokens = tokenize(text)
        var pos = 0
        var forms: [StyleSex] = []
        while pos < tokens.count {
            if let (form, next) = parseTokens(tokens, from: pos) {
                forms.append(form)
                pos = next
            } else {
                pos += 1
            }
        }
        return forms
    }

    /// 词法切分：`(` `)` 为独立 token；`;` 起到行尾为注释；双引号字符串整体为一个 token；其余按空白切 atom。
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inComment = false
        var inString = false

        func flush() {
            if !current.isEmpty { tokens.append(current); current = "" }
        }

        for ch in text {
            if inString {
                current.append(ch)
                if ch == "\"" { inString = false; flush() }
                continue
            }
            if ch == "\"" {
                flush(); inString = true; current.append(ch); continue
            }
            if ch == "\n" || ch == "\r" {
                inComment = false; flush(); continue
            }
            if inComment { continue }
            if ch == ";" {
                flush(); inComment = true; continue
            }
            if ch == "(" || ch == ")" {
                flush(); tokens.append(String(ch))
            } else if ch.isWhitespace {
                flush()
            } else {
                current.append(ch)
            }
        }
        flush()
        return tokens
    }

    private static func parseTokens(_ tokens: [String], from start: Int) -> (StyleSex, Int)? {
        guard start < tokens.count else { return nil }
        var i = start
        if tokens[i] == "(" {
            i += 1
            var items: [StyleSex] = []
            while i < tokens.count && tokens[i] != ")" {
                if let (sub, next) = parseTokens(tokens, from: i) {
                    items.append(sub); i = next
                } else {
                    i += 1
                }
            }
            if i < tokens.count { i += 1 }   // 吃掉右括号
            return (.list(items), i)
        } else if tokens[i] == ")" {
            return nil
        } else {
            return (.atom(tokens[i]), i + 1)
        }
    }
}
```

### A. StyleDuration.swift
```swift
import Foundation

// MARK: - StyleDuration
// .sty 时值表达式 → Style 时间轴 slots（全音符 = 480 = 4/4 一小节，1 拍 = 120）。
// 对齐 Java Duration.java:201-240（Java 内部 WHOLE=1920，是这里的 4 倍，公式同构：先乘后除保证整数）。
//
// 规则：
// - 裸数字 = 音符分母：4→四分(120)、8→八分(60)、16→十六分(30)、2→二分(240)、1→全(480)；
// - "/k" 连音：slots = whole*(k-1)/(n*k)，故 8/3=40、4/3=80、16/3=20、64/3=5（全部整除）；
// - "." 附点：每点在前一次增量上折半累加，4.=180、2.=360；
// - "+" 相加：2+4=360、4+8=180、1+1+1+1=1920（钢琴 4 小节长句）、4/3+16+64/3=115。
//
// .sty 规则里的时值几乎总是紧凑字符串 token（如 X2+4+8、R8、push 8/3、(X 3 4.) 内的 "4."），
// 故以字符串解析为主；另提供 StyleSex 重载以兼容 ( + ... ) / ( n / k ) 的表写法。

enum StyleDuration {
    static let whole = 480

    static func slots(_ token: String) -> Int {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        return trimmed
            .split(separator: "+", omittingEmptySubsequences: false)
            .map { single(String($0)) }
            .reduce(0, +)
    }

    private static func single(_ raw: String) -> Int {
        var str = raw.trimmingCharacters(in: .whitespaces)
        var dots = 0
        while str.hasSuffix(".") { str.removeLast(); dots += 1 }

        var numStr = str
        var denominator = 1
        if let range = str.firstIndex(of: "/") {
            numStr = String(str[str.startIndex..<range])
            denominator = Int(str[str.index(after: range)...]) ?? 1
        }
        let numerator = max(1, Int(numStr) ?? 1)

        var s = whole
        if denominator > 1 { s *= (denominator - 1) }
        var duration = s / (numerator * denominator)

        // 附点：第一点加原值一半，第二点再加四分之一……
        var increment = duration
        for _ in 0..<dots {
            increment /= 2
            duration += increment
        }
        return duration
    }

    static func slots(_ sex: StyleSex) -> Int {
        switch sex {
        case .atom(let a):
            return slots(a)
        case .list(let items):
            guard let head = items.first?.asAtom else { return 0 }
            if head == "+" {
                return items.dropFirst().reduce(0) { $0 + slots($1) }
            }
            if head == "/", items.count >= 3,
               let n = items[1].asAtom, let k = items[2].asAtom {
                return slots("\(n)/\(k)")
            }
            // 兜底：表内若直接包了一个时值 atom
            return items.compactMap { $0.asAtom }.map { slots($0) }.first ?? 0
        }
    }
}
```

### A. StyleNoteName.swift
```swift
import Foundation

// MARK: - StyleNoteName
// .sty 音名 ↔ MIDI。对齐 Java NoteSymbol.java:50-89：
// 中央 c = MIDI 60（octave 0）；每个 '-' 降一个八度、每个 '+' 升一个八度。
// 例：g-- = G2(43)、e-- = E2(40)、c = C4(60)、a = A4(69)、d- = D3(50)。
// 用于读取 .sty 文件头的 bass-low / bass-base / bass-high / chord-low / chord-high。

enum StyleNoteName {
    private static let pitchClass: [String: Int] = [
        "c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11
    ]

    /// 解析如 "c"、"g--"、"d-"、"c+"、"c#-" 的音名为 MIDI 号。
    /// .sty 音域参数只用自然音名 + 八度符号；这里仍兼容单个 #/b 变音记号。
    static func midi(_ note: String) -> Int? {
        var t = note.lowercased().trimmingCharacters(in: .whitespaces)
        guard let first = t.first, let pc = pitchClass[String(first)] else { return nil }
        t.removeFirst()

        var semi = pc
        if t.hasPrefix("#") { semi += 1; t.removeFirst() }
        else if t.hasPrefix("b") { semi -= 1; t.removeFirst() }

        var octave = 0
        for ch in t {
            if ch == "-" { octave -= 1 }
            else if ch == "+" { octave += 1 }
        }
        return 60 + octave * 12 + semi
    }
}
```

### A. StyleDrumMap.swift
```swift
import Foundation

// MARK: - StyleDrumMap
// GM 打击乐名（spaceless，下划线连写）→ MIDI note。
// 对齐 Java MIDIBeast.spacelessDrumName（MIDIBeast.java:270-319）：数组 index + 35，覆盖 MIDI 35–81 共 47 件。
// 关键：swing.sty 底鼓用 Acoustic_Bass_Drum = 35（不是手写 DrumKit.kick 的 36）。
// 本字典为 .sty 引擎独立持有，不修改手写 DrumKit 常量（保护 Simple Swing 等旧风格）。

enum StyleDrumMap {

    /// index 0 → MIDI 35
    static let names: [String] = [
        "Acoustic_Bass_Drum",   // 35
        "Bass_Drum_1",          // 36
        "Side_Stick",           // 37
        "Acoustic_Snare",       // 38
        "Hand_Clap",            // 39
        "Electric_Snare",       // 40
        "Low_Floor_Tom",        // 41
        "Closed_Hi-Hat",        // 42
        "High_Floor_Tom",       // 43
        "Pedal_Hi-Hat",         // 44
        "Low_Tom",              // 45
        "Open_Hi-Hat",          // 46
        "Low-Mid_Tom",          // 47
        "Hi-Mid_Tom",           // 48
        "Crash_Cymbal_1",       // 49
        "High_Tom",             // 50
        "Ride_Cymbal_1",        // 51
        "Chinese_Cymbal",       // 52
        "Ride_Bell",            // 53
        "Tambourine",           // 54
        "Splash_Cymbal",        // 55
        "Cowbell",              // 56
        "Crash_Cymbal_2",       // 57
        "Vibraslap",            // 58
        "Ride_Cymbal_2",        // 59
        "Hi_Bongo",             // 60
        "Low_Bongo",            // 61
        "Mute_Hi_Conga",        // 62
        "Open_Hi_Conga",        // 63
        "Low_Conga",            // 64
        "High_Timbale",         // 65
        "Low_Timbale",          // 66
        "High_Agogo",           // 67
        "Low_Agogo",            // 68
        "Cabasa",               // 69
        "Maracas",              // 70
        "Short_Whistle",        // 71
        "Long_Whistle",         // 72
        "Short_Guiro",          // 73
        "Long_Guiro",           // 74
        "Claves",               // 75
        "Hi_Wood_Block",        // 76
        "Low_Wood_Block",       // 77
        "Mute_Cuica",           // 78
        "Open_Cuica",           // 79
        "Mute_Triangle",        // 80
        "Open_Triangle"         // 81
    ]

    /// 精确匹配优先；失败则按「去空格/下划线/连字符、小写」容错（不同 .sty 写法差异）。
    static func midi(_ spacelessName: String) -> UInt8? {
        let key = spacelessName.trimmingCharacters(in: .whitespaces)
        if let i = names.firstIndex(of: key) { return UInt8(i + 35) }
        let norm = normalize(key)
        if let i = names.firstIndex(where: { normalize($0) == norm }) { return UInt8(i + 35) }
        return nil
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }
}
```

### A. StyleModel.swift
```swift
import Foundation

// MARK: - StyleModel
// .sty 解析后的内存模型（与播放无关的纯数据）。三轨 pattern 中：
// - bass / chord 保留原始规则 S-表达式子树（ruleTrees），交给各自 Renderer 按本轨规则码展开；
// - drum 规则最简单（鼓名 + X/R/V 平铺），在解析期直接展开成 StyleDrumHit。

/// bass / chord 共用的一条 pattern。
struct StylePattern {
    let weight: Double            // 同小节多句时的加权抽取权重（Java getPattern）
    let ruleTrees: [StyleSex]     // (rules ...) 去掉包裹后的规则 token（B4、C8、X2+4+8、V90、(X 3 4.) …）
    let lengthSlots: Int          // 规则总时值（X/R/音名占时值；V 音量、U/D 方向不占）
    let pushSlots: Int            // 句首抢拍量（仅 chord 的 (push x)，bass 通常 0）
}

/// 鼓单件的一次敲击（或休止占位）。
struct StyleDrumHit {
    let onsetSlots: Int
    let durationSlots: Int
    let velocity: UInt8
    let isRest: Bool
}

/// 一件鼓的一整条规则（同名鼓在一小节内的全部击点）。
struct StyleDrumRule {
    let drumName: String
    let hits: [StyleDrumHit]
}

/// 一条鼓 pattern（含若干件鼓）。
struct StyleDrumPattern {
    let weight: Double
    let rules: [StyleDrumRule]
    let lengthSlots: Int
}

/// 一个解析完成的 .sty 风格。
struct ParsedStyle {
    let name: String
    let melodySwing: Double       // 文件头 (swing)，旋律摇摆比
    let compSwing: Double         // 文件头 (comp-swing)，伴奏摇摆比
    let voicingType: String       // open / closed（钢琴排簿方式）
    let bassLow: Int              // 以下均为 MIDI
    let bassHigh: Int
    let bassBase: Int
    let chordLow: Int
    let chordHigh: Int
    let bassPatterns: [StylePattern]
    let drumPatterns: [StyleDrumPattern]
    let chordPatterns: [StylePattern]
}
```

### A. StyleParser.swift
```swift
import Foundation

// MARK: - StyleParser
// 把 .sty 的 S-表达式解析为 ParsedStyle。识别的 section / 关键字对齐 Style.java:238-247：
//   标量：name / swing / comp-swing / voicing-type / bass-high / bass-low / bass-base / chord-high / chord-low
//   段落：(bass-pattern (weight) (rules ...))、(drum-pattern (weight) (drum n name X.. R.. V..) …)、
//         (chord-pattern (weight) (rules ...) [(push x)])
// 时值合计规则照搬探针 v1（已 ALL PASS）：X/R/音名占时值，V 音量、U/D 方向不占，(push) 单独提取不计入长度。

enum StyleParser {

    static func parse(text: String) -> ParsedStyle? {
        let forms = StyleSExpression.parse(text)
        guard let styleList = forms.first(where: { $0.asList?.first?.asAtom == "style" })?.asList else {
            // 容错：有的文件顶层直接是若干段，取第一个含多元素的 list
            guard let any = forms.first(where: { $0.asList != nil })?.asList else { return nil }
            return build(from: any)
        }
        return build(from: styleList)
    }

    private static func build(from styleList: [StyleSex]) -> ParsedStyle {
        var globals: [String: String] = [:]
        var bassPatterns: [StylePattern] = []
        var drumPatterns: [StyleDrumPattern] = []
        var chordPatterns: [StylePattern] = []

        for node in styleList {
            guard let seg = node.asList, let head = seg.first?.asAtom else { continue }
            switch head {
            case "bass-pattern":
                if let p = parseMelodicPattern(seg, isBass: true) { bassPatterns.append(p) }
            case "chord-pattern":
                if let p = parseMelodicPattern(seg, isBass: false) { chordPatterns.append(p) }
            case "drum-pattern":
                if let p = parseDrumPattern(seg) { drumPatterns.append(p) }
            default:
                // 标量键值：(swing 0.67)、(bass-high c) …
                if seg.count >= 2, let v = seg[1].asAtom { globals[head] = v }
            }
        }

        func dbl(_ key: String, _ fallback: Double) -> Double {
            guard let s = globals[key], let v = Double(s) else { return fallback }
            return v
        }
        func note(_ key: String, _ fallback: Int) -> Int {
            guard let s = globals[key], let m = StyleNoteName.midi(s) else { return fallback }
            return m
        }
        func str(_ key: String, _ fallback: String) -> String {
            guard let s = globals[key] else { return fallback }
            return s.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }

        // Java/Style 默认摇摆 2/3；swing.sty 显式写 0.67。音域缺省给 swing.sty 同值作安全兜底。
        return ParsedStyle(
            name: str("name", "style"),
            melodySwing: dbl("swing", 0.67),
            compSwing: dbl("comp-swing", dbl("swing", 0.67)),
            voicingType: str("voicing-type", "open"),
            bassLow: note("bass-low", 43),
            bassHigh: note("bass-high", 60),
            bassBase: note("bass-base", 40),
            chordLow: note("chord-low", 50),
            chordHigh: note("chord-high", 69),
            bassPatterns: bassPatterns,
            drumPatterns: drumPatterns,
            chordPatterns: chordPatterns
        )
    }

    // MARK: bass / chord pattern

    private static func parseMelodicPattern(_ seg: [StyleSex], isBass: Bool) -> StylePattern? {
        var weight = 0.0
        var ruleTrees: [StyleSex] = []
        var length = 0
        var push = 0

        for sub in seg.dropFirst() {
            guard let q = sub.asList, let key = q.first?.asAtom else { continue }
            switch key {
            case "rules":
                ruleTrees = Array(q.dropFirst())
                length = isBass ? bassRuleSlots(ruleTrees) : percRuleSlots(ruleTrees)
            case "weight":
                if let v = q.dropFirst().first?.asAtom, let wv = Double(v) { weight = wv }
            case "push":
                if let e = q.dropFirst().first { push = StyleDuration.slots(e) }
            default:
                break
            }
        }
        guard !ruleTrees.isEmpty else { return nil }
        return StylePattern(weight: weight, ruleTrees: ruleTrees,
                            lengthSlots: length, pushSlots: push)
    }

    /// 贝斯规则总时值：B/C/S/A/N/R/= 与嵌套 (X degree dur) 占时值；V 音量、U/D 方向不占。
    static func bassRuleSlots(_ trees: [StyleSex]) -> Int {
        var total = 0
        for tk in trees {
            if let items = tk.asList {
                // (X degree duration [modifier])
                if items.first?.asAtom == "X", items.count >= 3, let dur = items[2].asAtom {
                    total += StyleDuration.slots(dur)
                }
            } else if let s = tk.asAtom {
                let lead = String(s.prefix(1))
                if lead == "V" || lead == "U" || lead == "D" { continue }
                if s.count >= 2 { total += StyleDuration.slots(String(s.dropFirst())) }
            }
        }
        return total
    }

    /// 鼓 / 钢琴规则总时值：X/R 占时值，V 不占；嵌套表（如 push）不计入。
    static func percRuleSlots(_ trees: [StyleSex]) -> Int {
        var total = 0
        for tk in trees {
            guard let s = tk.asAtom else { continue }
            let lead = String(s.prefix(1))
            if lead == "V" { continue }
            if (lead == "X" || lead == "R") && s.count >= 2 {
                total += StyleDuration.slots(String(s.dropFirst()))
            }
        }
        return total
    }

    // MARK: drum pattern

    private static func parseDrumPattern(_ seg: [StyleSex]) -> StyleDrumPattern? {
        var weight = 0.0
        var rules: [StyleDrumRule] = []
        var length = 0

        for sub in seg.dropFirst() {
            guard let q = sub.asList, let key = q.first?.asAtom else { continue }
            if key == "drum", q.count >= 2, let name = q[1].asAtom {
                let tokens = Array(q.dropFirst(2))
                let hits = expandDrumHits(tokens)
                rules.append(StyleDrumRule(drumName: name, hits: hits))
                let l = percRuleSlots(tokens)
                if l > length { length = l }
            } else if key == "weight", let v = q.dropFirst().first?.asAtom, let wv = Double(v) {
                weight = wv
            }
        }
        guard !rules.isEmpty else { return nil }
        return StyleDrumPattern(weight: weight, rules: rules, lengthSlots: length)
    }

    /// 展开一件鼓的 X/R/V 序列为带绝对起点的击点。X 无前置 V 时默认力度 127（Java DrumPattern.java:318）。
    static func expandDrumHits(_ trees: [StyleSex]) -> [StyleDrumHit] {
        var hits: [StyleDrumHit] = []
        var onset = 0
        var velocity: UInt8 = 127   // Java DrumPattern.java:318 localVolume 默认 127
        for tk in trees {
            guard let s = tk.asAtom else { continue }
            let lead = String(s.prefix(1))
            if lead == "V", let v = Int(String(s.dropFirst())) {
                velocity = UInt8(max(1, min(127, v)))
            } else if (lead == "X" || lead == "R") && s.count >= 2 {
                let dur = StyleDuration.slots(String(s.dropFirst()))
                hits.append(StyleDrumHit(onsetSlots: onset, durationSlots: dur,
                                        velocity: velocity, isRest: lead == "R"))
                onset += dur
            }
        }
        return hits
    }
}
```

### A. StyleScaleTable.swift
```swift
import Foundation

// MARK: - StyleScaleTable
// 给贝斯渲染器提供「根音 + 和弦音 + 首选音阶」。
// 根音 / canonical form 复用 App 内权威的 ChordSymbolMapper（斜杠和弦只取本体）；
// 每个 form 的首选音阶取自出厂词汇 Original.voc 中该 chord form 的 scales 块第一项（实测）：
//   大/大七/大六 → major(Ionian)；小七/九/十一/十三 → dorian；小六/小大七 → melodic minor；
//   属七/九 → mixolydian；自然 13 / #11 / b5 → lydian dominant；属 #5 → whole tone；
//   b9/#9/b13(altered) → altered；半减 m7b5 → locrian #2；减七 → half-whole diminished；
//   大增(#5) → lydian augmented；小增 → aeolian。
// 罕见 / 未识别 form 退化为只用和弦音（Java 无音阶时同样退回随机和弦音）。

struct StyleHarmony: Equatable {
    let rootPC: Int            // 根音 pitch class（相对 C，0–11）
    let chordTones: [Int]      // 相对根的和弦音半音（一个八度内，含根 0）
    let scale: [Int]?          // 首选音阶相对根半音（一个八度内、升序、含根 0）；nil = 退化为和弦音
}

enum StyleScaleTable {

    static func resolve(_ chordName: String) -> StyleHarmony? {
        guard let r = ChordSymbolMapper.resolve(chordName) else { return nil }
        let pc = ((r.rise % 12) + 12) % 12
        let suffix = String(r.canonical.dropFirst())   // 去掉根名字母 "C"
        let h = classify(suffix)
        return StyleHarmony(rootPC: pc, chordTones: h.tones, scale: h.scale)
    }

    // 各音阶（相对根半音，一个八度）
    private static let ionian   = [0, 2, 4, 5, 7, 9, 11]
    private static let dorian   = [0, 2, 3, 5, 7, 9, 10]
    private static let melMinor = [0, 2, 3, 5, 7, 9, 11]
    private static let aeolian  = [0, 2, 3, 5, 7, 8, 10]
    private static let mixo     = [0, 2, 4, 5, 7, 9, 10]
    private static let lydDom   = [0, 2, 4, 6, 7, 9, 10]
    private static let lydian   = [0, 2, 4, 6, 7, 9, 11]
    private static let lydAug   = [0, 2, 4, 6, 8, 9, 11]
    private static let wholeTone = [0, 2, 4, 6, 8, 10]
    private static let altered  = [0, 1, 3, 4, 6, 8, 10]
    private static let locrianSharp2 = [0, 2, 3, 5, 6, 8, 10]
    private static let locrian  = [0, 1, 3, 5, 6, 8, 10]
    private static let dimHW    = [0, 1, 3, 4, 6, 7, 9, 10]

    private struct H { let tones: [Int]; let scale: [Int]? }

    // swiftlint:disable:next function_body_length
    private static func classify(_ s: String) -> H {
        // —— 特殊单音 / 无调 ——
        if s == "Bass" || s == "Note" { return H(tones: [0], scale: nil) }
        if s == "Blues" { return H(tones: [0, 4, 7], scale: nil) }

        // —— 减 / 半减 ——
        if s.contains("o") { return H(tones: [0, 3, 6, 9], scale: dimHW) }
        if s.contains("m7b5") || s.contains("m9b5") {
            return H(tones: [0, 3, 6, 10], scale: locrianSharp2)
        }

        // —— 小大七 / 小六（melodic minor 系）——
        if s.hasPrefix("mM") { return H(tones: [0, 3, 7, 11], scale: melMinor) }
        if s.hasPrefix("m6") { return H(tones: [0, 3, 7, 9], scale: melMinor) }

        // —— 小三和弦家族 ——
        if s.hasPrefix("m") {
            if s.contains("#5") {
                let tones = s.contains("7") ? [0, 3, 8, 10] : [0, 3, 8]
                return H(tones: tones, scale: aeolian)
            }
            if s.contains("b5") { return H(tones: [0, 3, 6, 10], scale: locrian) }
            let hasSeventh = s.contains("7") || s.contains("9") || s.contains("11") || s.contains("13")
            return H(tones: hasSeventh ? [0, 3, 7, 10] : [0, 3, 7], scale: dorian)
        }

        // —— sus 挂留（在大 / 属常规判定前）——
        if s.contains("sus") {
            let dominant = s.first?.isNumber == true || s.contains("7") || s.contains("13")
            if dominant {
                return H(tones: [0, 5, 7, 10], scale: mixo)
            }
            if s.contains("24") { return H(tones: [0, 2, 5, 7], scale: ionian) }
            if s.contains("2") { return H(tones: [0, 2, 7], scale: ionian) }
            return H(tones: [0, 5, 7], scale: ionian)
        }

        // —— 属七家族（canonical 以 7/9/11/13 开头）——
        if s.first?.isNumber == true {
            // quartal C4 / power C5
            if s == "4" { return H(tones: [0, 5, 10], scale: nil) }
            if s == "5" { return H(tones: [0, 7], scale: nil) }

            if s.contains("b9") || s.contains("#9") || s.contains("b13") || s.lowercased().contains("alt") {
                return H(tones: [0, 4, 7, 10], scale: altered)
            }
            if s.contains("#5") { return H(tones: [0, 4, 8, 10], scale: wholeTone) }
            if s.contains("#11") || s.contains("b5") || s.contains("13") {
                return H(tones: [0, 4, 7, 10], scale: lydDom)
            }
            return H(tones: [0, 4, 7, 10], scale: mixo)
        }

        // —— 大三和弦家族（M 前缀，含裸 C → CM）——
        if s.hasPrefix("M") || s.isEmpty {
            if s.contains("#5") {
                let tones = s.contains("7") ? [0, 4, 8, 11] : [0, 4, 8]
                return H(tones: tones, scale: lydAug)
            }
            if s.contains("#11") { return H(tones: [0, 4, 7, 11], scale: lydian) }
            if s.contains("6") { return H(tones: [0, 4, 7, 9], scale: ionian) }
            if s.contains("7") || s.contains("9") || s.contains("13") {
                return H(tones: [0, 4, 7, 11], scale: ionian)
            }
            return H(tones: [0, 4, 7], scale: ionian)
        }

        // —— 兜底：大三和弦、无音阶 ——
        return H(tones: [0, 4, 7], scale: nil)
    }
}
```

### A. StyleEngine.swift
```swift
import Foundation

// MARK: - StyleRNG
// .sty 展开的随机源。Java 用 java.util.Random（加权抽取/取音）与 Math.random()（placePitchNear/pressure），
// 不要求与 Java 逐音一致，只需：① 固定种子可复现（回归 / DEBUG 对拍）；② 正式播放真随机。

protocol StyleRNG {
    func nextDouble() -> Double                 // [0, 1)
    func nextInt(_ count: Int) -> Int           // [0, count)
    func nextWeightedIndex(_ weights: [Double]) -> Int
}

extension StyleRNG {
    /// 加权随机下标（Java getPattern 的等长加权选择）。
    func nextWeightedIndex(_ weights: [Double]) -> Int {
        guard !weights.isEmpty else { return 0 }
        let total = weights.reduce(0, +)
        guard total > 0 else { return 0 }
        var r = nextDouble() * total
        for (i, w) in weights.enumerated() {
            r -= w
            if r < 0 { return i }
        }
        return weights.count - 1
    }
}

/// SplitMix64：固定种子、跨设备一致，用于回归与 DEBUG 对拍。
final class SeededStyleRNG: StyleRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    func nextDouble() -> Double {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(1 << 53)
    }
    func nextInt(_ count: Int) -> Int {
        guard count > 0 else { return 0 }
        return Int(nextDouble() * Double(count)) % count
    }
}

/// 系统真随机，用于正式播放（每次伴奏不同，与 Java 行为一致）。
final class RandomStyleRNG: StyleRNG {
    private var generator = SystemRandomNumberGenerator()
    func nextDouble() -> Double { Double.random(in: 0..<1, using: &generator) }
    func nextInt(_ count: Int) -> Int {
        guard count > 0 else { return 0 }
        return Int.random(in: 0..<count, using: &generator)
    }
}

/// 把 StyleRNG 适配给 FullVoicingEngine 的 VoicingRNG（钢琴排簿候选随机）。
struct StyleVoicingRNG: VoicingRNG {
    let rng: StyleRNG
    func nextIndex(_ count: Int) -> Int { rng.nextInt(count) }
}

// MARK: - StyleEngine
// .sty 引擎总入口：从 bundle 加载并缓存解析结果，调度鼓 / 贝斯 / 钢琴三轨渲染，产出 BackingTrackData。
// P3-a 只注册标准 swing（id "sty:swing" → 资源 swing.sty）；P3-b 再注册其余 45 个并接二级菜单。

final class StyleEngine {
    static let shared = StyleEngine()

    /// 接线层使用的 styleId → bundle 内资源名（不含扩展名）。
    private let idToResource: [String: String] = [
        "sty:swing": "swing"
    ]
    private var cache: [String: ParsedStyle] = [:]
    private init() {}

    func isStyStyle(_ style: String) -> Bool { idToResource[style] != nil }

    func load(_ styleId: String) -> ParsedStyle? {
        if let cached = cache[styleId] { return cached }
        guard let resource = idToResource[styleId] else { return nil }
        let candidates = [
            Bundle.main.url(forResource: resource, withExtension: "sty"),
            Bundle.main.url(forResource: resource, withExtension: "sty", subdirectory: "Styles"),
            Bundle.main.url(forResource: resource, withExtension: "sty", subdirectory: "Resources/Styles"),
            Bundle.main.url(forResource: resource, withExtension: "sty", subdirectory: "Real imPro/Resources/Styles")
        ].compactMap { $0 }
        guard let url = candidates.first,
              let text = try? String(contentsOf: url, encoding: .utf8),
              let parsed = StyleParser.parse(text: text) else { return nil }
        cache[styleId] = parsed
        return parsed
    }

    /// 生成三轨伴奏。seed 非空 → 可复现（回归 / DEBUG）；nil → 真随机。
    func render(styleId: String,
                measureCount: Int,
                chordSegments: [ChordSegment],
                slotsPerMeasure: Int,
                seed: UInt64? = nil) -> BackingTrackData {
        var data = BackingTrackData()
        guard let parsed = load(styleId) else { return data }
        let rng: StyleRNG = seed.map { SeededStyleRNG(seed: $0) } ?? RandomStyleRNG()

        data.bassNotes = StyleBassRenderer.render(parsed: parsed, segments: chordSegments,
                                                  slotsPerMeasure: slotsPerMeasure, rng: rng)
        data.pianoNotes = StyleChordRenderer.render(parsed: parsed, segments: chordSegments,
                                                    slotsPerMeasure: slotsPerMeasure, rng: rng)
        data.drumNotes = StyleDrumRenderer.render(parsed: parsed, measureCount: measureCount,
                                                  slotsPerMeasure: slotsPerMeasure, rng: rng)
        data.compSwing = parsed.compSwing
        data.melodySwing = parsed.melodySwing
        return data
    }
}
```

### A. StyleBassRenderer.swift
```swift
import Foundation

// MARK: - StyleBassRenderer
// .sty 贝斯（walking bass）渲染器。逐和弦把 bass-pattern 规则拼满该和弦时长。
// 忠实移植 Java：
//   BassPattern.applyRules（stylePatterns/BassPattern.java:640-905）规则码
//     B 根音 / C 随机和弦音 / S 首选音阶的二·三度经过（getIntervals :961-984）/
//     A 下一和弦根音 ±1 趋近 / N 下一和弦根音并结束本段 / R 休止 / = 重复上一音 /
//     V 力度 / (X degree dur) 音阶度数（getInterval :942-950）；
//   每个非休非=音先 transpose(-24)（:857），再 placePitchNear（MARGIN=11，：1029-1085）、
//   pressure（:1096-1137，center 实算到 high 的历史 quirk、四次方软拉回），最后按风格音域硬钳；
//   Style.getPattern（:1020-1087）：取 ≤剩余 的最长句，等长按权重随机；放不下才取 ≥剩余 的最短句截断；
//   Style.addToBassline（:1513-1600）逐和弦 while 拼满；趋近音仅在该句填到段边界时指下一和弦（:1552-1554）；
//   初始音 = 音域中点（:2195-2196），段首八度钳回（:2292-2302）。

enum StyleBassRenderer {
    private static let margin = 11
    private static let softMargin = 6
    private static let defaultVelocity: UInt8 = 127   // Java 规则层无 V 标记时默认 MAX_VOLUME(Style.java:2364)
    private static let bassChannel: UInt8 = 2

    private enum Op {
        case root, chordTone, scaleTone, approach, next, rest, same
        case volume(UInt8)
        case degree(index: Int, alteration: Int)
    }
    private struct Event {
        let op: Op
        let slots: Int
    }

    static func render(parsed: ParsedStyle,
                       segments: [ChordSegment],
                       slotsPerMeasure: Int,
                       rng: StyleRNG) -> [CompanionNote] {
        let patterns = parsed.bassPatterns
        guard !patterns.isEmpty else { return [] }
        let low = parsed.bassLow, high = parsed.bassHigh

        var notes: [CompanionNote] = []
        var globalLast: Int?

        for (i, seg) in segments.enumerated() {
            guard let harmony = StyleScaleTable.resolve(seg.chord) else { continue }
            let nextHarmony = (i + 1 < segments.count) ? StyleScaleTable.resolve(segments[i + 1].chord) : nil

            var last = globalLast ?? ((low + high) / 2)
            // 段首八度钳回
            if last > high { last -= 12 }
            else if last < low { last += 12 }

            var remaining = seg.durationSlots
            var cursor = 0

            while remaining > 0 {
                guard let pattern = getPattern(patterns, remaining: remaining, rng: rng) else { break }
                let events = parseEvents(pattern.ruleTrees)
                let fillTo = min(pattern.lengthSlots, remaining)
                var localCursor = 0
                var endSegment = false
                var runningVel = defaultVelocity

                for event in events {
                    if case .volume(let v) = event.op { runningVel = v; continue }
                    if localCursor >= fillTo { break }
                    let dur = min(max(0, event.slots), fillTo - localCursor)

                    switch event.op {
                    case .volume:
                        break
                    case .rest:
                        localCursor += event.slots
                        continue
                    case .next:
                        if let nh = nextHarmony {
                            let midi = place(nh.rootPC, last: last, low: low, high: high, rng: rng)
                            if dur > 0 {
                                notes.append(CompanionNote(startSlot: seg.startSlot + cursor + localCursor,
                                                           midiPitch: UInt8(clamping: midi),
                                                           durationSlots: dur,
                                                           volume: runningVel,
                                                           channel: bassChannel))
                            }
                            last = midi
                        }
                        localCursor += event.slots
                        endSegment = true
                    default:
                        guard let pc = pitchClass(for: event.op, harmony: harmony,
                                                  nextHarmony: nextHarmony, last: last, rng: rng) else {
                            localCursor += event.slots
                            continue
                        }
                        let midi: Int
                        if case .same = event.op {
                            midi = last
                        } else {
                            midi = place(pc, last: last, low: low, high: high, rng: rng)
                        }
                        if dur > 0 {
                            notes.append(CompanionNote(startSlot: seg.startSlot + cursor + localCursor,
                                                       midiPitch: UInt8(clamping: midi),
                                                       durationSlots: dur,
                                                       volume: runningVel,
                                                       channel: bassChannel))
                        }
                        last = midi
                        localCursor += event.slots
                    }
                    if endSegment { break }
                }

                let filled = endSegment ? remaining : min(pattern.lengthSlots, remaining)
                cursor += filled
                remaining -= filled
                if endSegment { remaining = 0 }
            }
            globalLast = last
        }
        return notes
    }

    // MARK: 规则解析

    private static func parseEvents(_ trees: [StyleSex]) -> [Event] {
        var events: [Event] = []
        for tk in trees {
            if let items = tk.asList {
                // (X degree duration [mod])
                if items.first?.asAtom == "X", items.count >= 3,
                   let degreeAtom = items[1].asAtom, let durAtom = items[2].asAtom {
                    let (idx, alt) = parseDegree(degreeAtom)
                    events.append(Event(op: .degree(index: idx, alteration: alt),
                                        slots: StyleDuration.slots(durAtom)))
                }
                continue
            }
            guard let s = tk.asAtom else { continue }
            let lead = String(s.prefix(1))
            let rest = String(s.dropFirst())

            if lead == "U" || lead == "D" { continue }   // 方向修饰：默认走 placePitchNear+pressure，忽略
            if lead == "V" {
                events.append(Event(op: .volume(UInt8(clamping: Int(rest) ?? 100)), slots: 0))
                continue
            }
            let op: Op
            switch lead {
            case "B": op = .root
            case "C": op = .chordTone
            case "S": op = .scaleTone
            case "A": op = .approach
            case "N": op = .next
            case "R": op = .rest
            case "=": op = .same
            default:  op = .root
            }
            let slots = s.count >= 2 ? StyleDuration.slots(rest) : 0
            events.append(Event(op: op, slots: slots))
        }
        return events
    }

    private static func parseDegree(_ s: String) -> (Int, Int) {
        var t = s
        var alteration = 0
        if t.hasPrefix("b") { alteration = -1; t.removeFirst() }
        else if t.hasPrefix("#") { alteration = 1; t.removeFirst() }
        let n = Int(t) ?? 1
        return (n, alteration)
    }

    // MARK: 取音

    private static func pitchClass(for op: Op,
                                   harmony: StyleHarmony,
                                   nextHarmony: StyleHarmony?,
                                   last: Int,
                                   rng: StyleRNG) -> Int? {
        switch op {
        case .root:
            return harmony.rootPC
        case .chordTone:
            let rel = harmony.chordTones[rng.nextInt(harmony.chordTones.count)]
            return (harmony.rootPC + rel) % 12
        case .scaleTone:
            let candidates = scaleApproachClasses(harmony: harmony, last: last)
            let pool = candidates.isEmpty ? harmony.chordTones.map { ($0 + harmony.rootPC) % 12 } : candidates
            return pool[rng.nextInt(pool.count)]
        case .approach:
            guard let nr = nextHarmony?.rootPC else { return harmony.rootPC }
            return (nr + (rng.nextInt(2) == 0 ? 1 : -1)) % 12
        case .next:
            return nextHarmony?.rootPC ?? harmony.rootPC
        case .same:
            return last % 12
        case .degree(let index, let alteration):
            if let scale = harmony.scale, !scale.isEmpty {
                let i = ((index - 1) % scale.count + scale.count) % scale.count
                return (harmony.rootPC + scale[i] + alteration + 12) % 12
            } else {
                let tones = harmony.chordTones
                let i = ((index - 1) % tones.count + tones.count) % tones.count
                return (harmony.rootPC + tones[i] + alteration + 12) % 12
            }
        case .rest, .volume:
            return nil
        }
    }

    /// S 码：首选音阶中相对上一音的音阶二度（±1 级）与三度（±2 级）候选，对齐 getIntervals(2)+getIntervals(3)。
    private static func scaleApproachClasses(harmony: StyleHarmony, last: Int) -> [Int] {
        guard let scale = harmony.scale, !scale.isEmpty else { return [] }
        var series: [Int] = []
        for oct in -1...3 {
            for pc in scale { series.append(harmony.rootPC + pc + 12 * oct + 36) }
        }
        guard let rootPos = series.indices.min(by: { abs(series[$0] - last) < abs(series[$1] - last) }) else {
            return []
        }
        var out: Set<Int> = []
        for delta in [1, -1, 2, -2] {
            let idx = rootPos + delta
            if series.indices.contains(idx) { out.insert(series[idx] % 12) }
        }
        return Array(out)
    }

    // MARK: 八度放置 / 软边界

    private static func place(_ pitchClass: Int, last: Int, low: Int, high: Int, rng: StyleRNG) -> Int {
        var p = 60 + ((pitchClass % 12) + 12) % 12   // spell transpose(rise) 的中央八度近似
        p -= 24                                        // BassPattern 统一 transpose(-24)
        // placePitchNear：朝 base(last) 收敛到 ±MARGIN（Java 两个随机分支方向相同，净效果确定性）
        while p > last + margin { p -= 12 }
        while p < last - margin { p += 12 }
        // pressure 软拉回
        p = pressure(p, low: low, high: high, rng: rng)
        // 风格音域硬边界
        while p > high { p -= 12 }
        while p < low { p += 12 }
        return p
    }

    /// 对齐 BassPattern.pressure（:1096-1137）。注意 Java 的 center = low + (high-low) = high（注释自承只有期望一半），
    /// 故上软界 high+6 几乎不触发，实际效果集中在「音低于 high-6 时按距离四次方概率抬一个八度」。
    private static func pressure(_ x0: Int, low: Int, high: Int, rng: StyleRNG) -> Int {
        var x = x0
        let center = low + (high - low)
        let softHigh = center + softMargin
        let softLow = center - softMargin

        if x > softHigh {
            let numerator = x - softHigh
            let denominator = high - softHigh
            if denominator != 0 {
                var prob = Double(numerator) / Double(denominator)
                prob = prob * prob * prob * prob
                if rng.nextDouble() < prob { x -= 12 }
            }
        } else if x < softLow {
            let numerator = softLow - x
            let denominator = softLow - low
            if denominator != 0 {
                var prob = Double(numerator) / Double(denominator)
                prob = prob * prob * prob * prob
                if rng.nextDouble() < prob { x += 12 }
            }
        }
        return x
    }

    // MARK: getPattern

    private static func getPattern(_ patterns: [StylePattern], remaining: Int, rng: StyleRNG) -> StylePattern? {
        let fitting = patterns.filter { $0.lengthSlots > 0 && $0.lengthSlots <= remaining }
        if !fitting.isEmpty {
            let longest = fitting.map { $0.lengthSlots }.max()!
            let equalLength = patterns.filter { $0.lengthSlots == longest }
            let idx = rng.nextWeightedIndex(equalLength.map { $0.weight })
            return equalLength[min(idx, equalLength.count - 1)]
        }
        return patterns.filter { $0.lengthSlots >= remaining }.min { $0.lengthSlots < $1.lengthSlots }
    }
}
```

### A. StyleDrumRenderer.swift
```swift
import Foundation

// MARK: - StyleDrumRenderer
// .sty 鼓渲染器：逐小节按权重抽一条 drum-pattern，转换为现有 DrumPattern / DrumRule，
// 复用已验证的 DrumPatternExtractor.generate（同 slot 多鼓去重、channel 9、休止不发声），
// 再按小节偏移到全曲时间线。鼓名→MIDI 走 StyleDrumMap（Acoustic_Bass_Drum=35，区别于手写 kick=36）。

enum StyleDrumRenderer {

    static func render(parsed: ParsedStyle,
                       measureCount: Int,
                       slotsPerMeasure: Int,
                       rng: StyleRNG) -> [CompanionNote] {
        let patterns = parsed.drumPatterns
        guard !patterns.isEmpty else { return [] }

        var out: [CompanionNote] = []
        for measure in 0..<measureCount {
            let index = rng.nextWeightedIndex(patterns.map { $0.weight })
            let styPattern = patterns[min(index, patterns.count - 1)]

            let drumPattern = DrumPattern()
            for rule in styPattern.rules {
                guard let midi = StyleDrumMap.midi(rule.drumName) else { continue }
                let elements: [DrumPatternElement] = rule.hits.map {
                    DrumPatternElement(onsetSlots: $0.onsetSlots,
                                       durationSlots: $0.durationSlots,
                                       velocity: $0.isRest ? 0 : $0.velocity,
                                       isRest: $0.isRest)
                }
                if !elements.isEmpty {
                    drumPattern.rules.append(DrumRule(midiNote: midi, elements: elements))
                }
            }

            let oneBar = DrumPatternExtractor.generate(pattern: drumPattern,
                                                       measureCount: 1,
                                                       slotsPerMeasure: slotsPerMeasure)
            let base = measure * slotsPerMeasure
            out.append(contentsOf: oneBar.map {
                CompanionNote(startSlot: $0.startSlot + base,
                              midiPitch: $0.midiPitch,
                              durationSlots: $0.durationSlots,
                              volume: $0.volume,
                              channel: $0.channel)
            })
        }
        return out
    }
}
```

### A. StyleChordRenderer.swift
```swift
import Foundation

// MARK: - StyleChordRenderer
// .sty 钢琴(comping)渲染器。自建、不改 ChordPatternExtractor（守住“只 3 处生产接线”）。
//  - voicing：每个击弦点用一个贯穿全曲的 FullVoicingEngine（音域/排布取自 .sty：swing 为 d-(50)~a(69)、open），
//    经 ChordSymbolMapper.resolve → engine.voicing(forForm:rootRise:)，保持跨段声部连接；
//  - 时间线：复刻 ChordPatternExtractor.generateTimeline 的 while/residual/push/跨小节窗口切割
//    （对齐 Java Style.getChordPattern + makeChordline），唯一区别是句型从 .sty chord-pattern 加权抽取；
//  - 人性化：力度 ±8、起点 ±3 抖动（同现有 Swift comping，固定种子可复现）；
//  - 力度取 Java 规则原值（无 V 默认 127、V 标记原样，见 Style.java:1414），引擎内【不做响度压缩】：
//    响度平衡属混音层，列入 P3-c 真机听感验收用单一播放端增益统一处理，避免把弱音（如军鼓 fill V10）压到近无声。

enum StyleChordRenderer {

    private static let chordChannel: UInt8 = 1
    private static let defaultVelocity: UInt8 = 127   // Java Style.java:1414 chordline 初始 volume=127

    static func render(parsed: ParsedStyle,
                       segments: [ChordSegment],
                       slotsPerMeasure: Int,
                       rng: StyleRNG) -> [CompanionNote] {
        let styPatterns = parsed.chordPatterns
        guard !styPatterns.isEmpty else { return [] }

        let engine = FullVoicingEngine(rng: StyleVoicingRNG(rng: rng))
        engine.lowMidi = parsed.chordLow
        engine.highMidi = parsed.chordHigh
        engine.requestType = voicingType(parsed.voicingType)

        var notes: [CompanionNote] = []
        var missed = 0
        var residual: ChordPattern? = nil
        var residualOrigin = 0

        for seg in segments {
            var remaining = seg.durationSlots
            var segAbsBase = seg.startSlot
            var firstOfSeg = true

            while remaining > 0 {
                let pat: ChordPattern
                let origin: Int
                if let r = residual {
                    pat = r
                    origin = residualOrigin
                    residual = nil
                } else {
                    let index = rng.nextWeightedIndex(styPatterns.map { $0.weight })
                    pat = convert(styPatterns[min(index, styPatterns.count - 1)])
                    origin = 0
                }

                let patRemain = pat.durationSlots - origin
                let segLen = min(max(patRemain, 0), remaining)
                guard segLen > 0 else { residual = nil; break }   // 防御：异常空片段不死循环

                let push = (firstOfSeg && origin == 0) ? pat.pushSlots : 0
                let winStart = origin
                let winEnd = origin + segLen

                for el in pat.elements where el.noteType == .chord {
                    let s = max(el.onsetSlots, winStart)
                    let e = min(el.onsetSlots + el.durationSlots, winEnd)
                    guard e > s else { continue }
                    var absOn = segAbsBase + (s - winStart) - push
                    if absOn < 0 { absOn = 0 }   // 全曲开头抢拍不得早于 0（对齐 Java time<0 钳 0）
                    emitVoicing(chordName: seg.chord, engine: engine,
                                absStart: absOn, duration: e - s,
                                baseVelocity: el.velocity, rng: rng,
                                into: &notes, missed: &missed)
                }

                remaining -= segLen
                segAbsBase += segLen
                firstOfSeg = false
                let consumedEnd = origin + segLen
                if consumedEnd < pat.durationSlots {
                    residual = pat
                    residualOrigin = consumedEnd
                }
            }
        }

        #if DEBUG
        if missed > 0 {
            print("[StyleEngine] chord: \(missed) hit point(s) had no voicing and were skipped")
        }
        #endif
        notes.sort { $0.startSlot < $1.startSlot }
        return notes
    }

    // MARK: .sty chord-pattern（X/R/V token）→ ChordPattern（供时间线复用）

    private static func convert(_ sp: StylePattern) -> ChordPattern {
        let cp = ChordPattern()
        cp.pushSlots = sp.pushSlots
        cp.patternLengthSlots = sp.lengthSlots > 0 ? sp.lengthSlots : slotsPerMeasureFallback
        var onset = 0
        var velocity = defaultVelocity
        var elements: [ChordElement] = []
        for token in sp.ruleTrees {
            guard let s = token.asAtom else { continue }   // (push …) 已在解析期提取，这里跳过
            let lead = String(s.prefix(1))
            let rest = String(s.dropFirst())
            if lead == "V", let v = Int(rest) {
                velocity = UInt8(clamping: v)
                continue
            }
            if (lead == "X" || lead == "R") && s.count >= 2 {
                let dur = StyleDuration.slots(rest)
                elements.append(ChordElement(onsetSlots: onset,
                                             durationSlots: dur,
                                             velocity: velocity,
                                             noteType: lead == "X" ? .chord : .rest))
                onset += dur
            }
        }
        cp.elements = elements
        return cp
    }

    private static let slotsPerMeasureFallback = 480

    // MARK: 单个击弦点 → 一组 voicing MIDI（无候选则跳过并计数）

    private static func emitVoicing(chordName: String,
                                    engine: FullVoicingEngine,
                                    absStart: Int,
                                    duration: Int,
                                    baseVelocity: UInt8,
                                    rng: StyleRNG,
                                    into notes: inout [CompanionNote],
                                    missed: inout Int) {
        guard let resolved = ChordSymbolMapper.resolve(chordName),
              let voicing = engine.voicing(forForm: resolved.canonical, rootRise: resolved.rise),
              !voicing.isEmpty else {
            missed += 1
            return
        }
        // 同一击弦点所有音共用一个力度（±8 人性化）；起点每音独立 ±3（模拟手指滚奏）。
        let velocity = UInt8(clamping: Int(baseVelocity) + rng.nextInt(17) - 8)
        for midi in voicing.sorted() {
            let start = max(0, absStart + rng.nextInt(7) - 3)
            notes.append(CompanionNote(startSlot: start,
                                       midiPitch: UInt8(clamping: midi),
                                       durationSlots: duration,
                                       volume: velocity,
                                       channel: chordChannel))
        }
    }

    private static func voicingType(_ raw: String) -> JazzVoicingType {
        switch raw.lowercased() {
        case "closed": return .closed
        case "shout":  return .shout
        case "all":    return .all
        default:       return .open
        }
    }
}
```

## 附录 B：swing.sty（从 Java `styles/swing.sty` 原样拷贝，2711 B）
```
(style
	(name swing)
	(bass-high c)
	(bass-low g--)
	(bass-base e--)
	(swing 0.67)
	(comp-swing 0.67)
	(voicing-type open)
	(chord-high a)
	(chord-low d-)
	(comments )
	(bass-pattern (rules B4 S4 C4 V90 A4)(weight 10.0))
	(bass-pattern (rules B4 C4 C4 V90 A4)(weight 5.0))
	(bass-pattern (rules B4 S4 C4 S4)(weight 2.0))
	(bass-pattern (rules B4 S4 C4 A8 V90 A8)(weight 3.0))
	(bass-pattern (rules B4 S4 C4 S8 V90 A8)(weight 2.0))
	(bass-pattern (rules B4 C4)(weight 5.0))
	(bass-pattern (rules B4 C8 V90 A8)(weight 5.0))
	(bass-pattern (rules B4 S4)(weight 3.0))
	(bass-pattern (rules B4)(weight 5.0))
	(bass-pattern (rules B4 V90 A4)(weight 2.0))
	(bass-pattern (rules V90 B8 V127 C4.)(weight 2.0))
	(bass-pattern (rules V90 B8)(weight 10.0))
	(bass-pattern (rules B2 C4)(weight 10.0))
	(bass-pattern (rules B4+8)(weight 100.0))
	(bass-pattern (rules B2+4)(weight 100.0))
	(bass-pattern (rules B4 C4 C8 S8 S8 V90 A8)(weight 5.0))
	(drum-pattern 
		(drum Ride_Cymbal_1 X4 X8 X8 X4 X8 X8)
		(drum Closed_Hi-Hat R4 X4 R4 X4)
		(drum Acoustic_Snare R4 V50 X8 R4+8 X8 R8)
		(weight 50.0)
	)
	(drum-pattern 
		(drum Ride_Cymbal_1 X4 X8 X8 X4 X8 X8)
		(drum Closed_Hi-Hat R4 X4 R4 X4)
		(drum Acoustic_Snare R2 V50 X8 X8 R8 X8)
		(weight 15.0)
	)
	(drum-pattern 
		(drum Ride_Cymbal_1 X4 X4 X8 X8 X4)
		(drum Closed_Hi-Hat R4 X4 R4 X4)
		(drum Acoustic_Snare R2+4 V50 X8 R8)
		(weight 60.0)
	)
	(drum-pattern 
		(drum Ride_Cymbal_1 X8 X8 X4 X4 X4)
		(drum Closed_Hi-Hat R4 X4 R4 X4)
		(drum Acoustic_Snare R4 V50 X8 R2+8)
		(weight 10.0)
	)
	(drum-pattern 
		(drum Ride_Cymbal_1 X8 X8 X4 X4 X4)
		(drum Closed_Hi-Hat R4 X4 R4 X4)
		(drum Acoustic_Snare V50 R2. X4)
		(weight 30.0)
	)
	(drum-pattern 
		(drum Ride_Cymbal_1 X4 X4 X8 X8 X4)
		(drum Closed_Hi-Hat R4 X4 R4 X4)
		(drum Acoustic_Snare V50 R2. X8 X8)
		(weight 10.0)
	)
	(drum-pattern 
		(drum Ride_Cymbal_1 X8 X8 X4 X4 X4)
		(drum Closed_Hi-Hat R4 X4 R4 X4)
		(drum Acoustic_Snare R2 V10 X8/3 V20 X8/3 V30 X8/3 V40 X8/3 V50 X8/3 V60 X8/3)
		(weight 10.0)
	)
	(drum-pattern 
		(drum Ride_Cymbal_1 X4 X8 X8 X4 X8 X8)
		(drum Closed_Hi-Hat R4 X4 R4 X4)
		(drum Acoustic_Snare R2+8 V50 X8 X8 R8)
		(weight 5.0)
	)
	(drum-pattern 
		(drum Acoustic_Snare R2 V10 X8/3 V20 X8/3 V30 X8/3 V40 X8/3 V50 X8/3 V60 X8/3)
		(drum Acoustic_Bass_Drum R2+4+8+16+32 X32)
		(drum Ride_Cymbal_1 X8 X8 X4 X4 X4)
		(drum Closed_Hi-Hat R4 X4 R4 X4)
		(weight 10.0)
	)
	(drum-pattern 
		(drum Ride_Cymbal_1 X4 X8 X8 X4 X8 X8)
		(drum Closed_Hi-Hat R4 X4 R4 X4)
		(drum Acoustic_Snare R2 V50 X8 X8 R8 X8)
		(weight 10.0)
	)
	(chord-pattern (rules X2+4+8 R8)(weight 50.0))
	(chord-pattern (rules X2 R4 V90 X4)(weight 30.0))
	(chord-pattern (rules X1+1+1+1)(weight 10.0)(push 8/3))
)```
