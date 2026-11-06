# Real imPro 顶部 UI 大改 — 只读勘察报告 + 逐 hunk 方案

> 日期：2026-10-08　状态：**勘察/方案阶段，生产零改动**
> 范围：纯 UI / 信息架构重构与接线。**不碰**算法、引擎、整流、生成逻辑与任何默认值。
> 落地纪律：整文件备份（含 SHA1）→ 旧码中文注释原位封存 → 逐 hunk 应用 → Xcode GUI Build → 回归门 + 真机/模拟器 → 回报数值与截图。**未获书面批准不动手。**

---

## 0. 结论速览（乐手话版）

1. **引擎早就支持自由组合，只是 UI 把它锁成了四个套餐。** Guide 引擎 `ImproVisorOriginalGuideToneStrategy` 的走向、起始音级、最大时长、音域上下限全是可注入参数（`GuideLineGenerator.swift:66-67, 83-86`），只是 worker 现在用 Smooth/Rising/Falling/Busy 四个预设去填，并把起始音级写死 "1"、音域写死 60–79（`ContentView.swift:1243-1247`）。废弃四档、改三参数自由组合**不需要改一行算法**。
2. **新默认 == 旧 Smooth，18,470 音符数不会动。** 旧 Smooth = 走向 0（No Preference）+ 最大时长 240（Half）+ 起始 "1" + 音域 60–79；新卡片出厂值照此设置。
3. **色彩开关一共 4 个键，分工已核清**（见第 2 节映射表）：Guide 骨架色彩 `guideLineColorEnabled`、Guide 加花星光 `guideColorEnabled`（留在调音台）、Grammar 色彩 `grammarColorEnabled`、Learning 色彩 `lstmColorEnabled`。迁移不丢不串，默认全 false。
4. **Avoid repeat pitches 已固定内置**（`GrammarNoteConverter.swift:39,162` 默认 true + 结尾合并 `GrammarLickGlue.swift:654`），对齐 Java `LickGen.java:107` 默认 `"true"`，不暴露。
5. **Basic/Master 合并的分支点全部集中在 `ContentView.swift` 一个文件**（共 9 处，见 3.4）；调音台用 if/else 不用 switch，合并后天然走 Grammar 路径，**阶段二调音台零改动**。
6. **已知修复核实通过**：`generateEmptyRoadmap()` 末尾 `self.generatedSolo = tempMeasures` 当前在位（`ContentView.swift:1127`，在 `refreshKeySections` 之后、`soloVersion` 之前）。
7. **弹出方式建议用 popover**（锚定 Settings 按钮、320pt 固定宽、不遮乐谱与 # 按钮；Range 键盘子页在卡内 NavigationStack push，键盘横向滚动）。理由见 3.6。

### ⚠ 一个需您拍板的歧义点（影响"Extended 扩展色彩"入口）

调音台现有的 **CONSERV/EXT 色彩宽度下拉**（`BandMixerView.swift:290-319`，持久化键 `colorModeRaw`，默认 conservative），您的规格里：
- 卡片规格（Guide/Grammar/Learning）都**没有**吸收宽度项；
- 调音台取舍（任务书 D 节）只写"去掉 Color，保留 Transform 乐手下拉 + 星光 ✧"，**未点名宽度下拉的去留**。

宽度下拉是通往 **Extended（扩展色彩音池）的唯一入口**，删掉等于悄悄收回一个现有能力（超出"不翻默认、不加不减"的范围）。

- **我的建议（默认方案）：阶段一保留宽度下拉在调音台**——它是服务三条链路的全局"色彩宽度"偏好，与各卡片的"是否允许色彩"开关正交。本报告阶段一 hunks 按此编写。
- 若您要求一并去掉：方案中已附 **Hunk M1-C（备选，不默认执行）**，封存宽度下拉即可；但 Extended 将无 UI 入口（默认值不变，仍可经 UserDefaults 调试写入）。

**请在书面批准时注明：宽度下拉「保留 / 去掉」。**

---

## 1. 现状勘察（文件 : 行，均为今日实读行号）

### 1.1 涉及文件与指纹

| 文件 | 行数 | SHA1（今日） | 阶段一是否改 | 阶段二是否改 |
|---|---|---|---|---|
| `Real imPro/Views/ContentView.swift` | 5064 | `c9e984b2ae6c45ecaf0b7f83db7804c22a56476f` | 是 | 是 |
| `Real imPro/Views/BandMixerView.swift` | 426 | `16957013bf2de919df1119f45aa04b80640e14f3` | 是 | 否（已核） |
| `Real imPro/Views/ModeSettingsCard.swift` | 新增 | — | 新建 | 改 |

> `project.pbxproj` 用 PBXFileSystemSynchronizedRootGroup（path="Real imPro"），新增 `.swift` 自动收录，不改工程文件。

### 1.2 枚举与模式（ContentView.swift）

- `ImproAlgorithmGroup`（`:6-13`）：`guide="Guide" / basic="Basic" / master="Master" / learning="Learning"`。
- `GuideLinePreset`（`:17-34`）：`smooth/rising/falling/busy`；计算属性 `direction`（`:19`，rising=+1/falling=-1/其余 0）、`maxDuration`（`:20`，busy=120/其余 240）、`shortName`（`:22-24`）、`fullDisplayName`（`:26-33`，中文 key→en.lproj）。
- `ImproAlgorithmType`（`:36-100`）：
  - 基础：`chordExercise="Chord+App"`、`colorTone="Chord+Col"`、`Lick="Great Lick"`；
  - 大师 9 项：`LeeMorgan / charlieParker="CharliePark" / billEvans / joePass / cannonballAdderley="Cannonball" / chetBaker="Chet Baker" / johnColtrane="Coltrane" / milesDavis="Miles" / redGarland="Red Garland"`；
  - Learning：`combination="Combination" / greatMoments="Great Moments"`；
  - `getStrategyInstance()`（`:62-79`）：LSTM 两项返回 nil；`grammarFileName`（`:82-99`）：LSTM 两项返回 ""。
- `currentAlgorithmList`（`:765-788`）：guide→[]；basic→[chordExercise, colorTone, Lick]；master→9 项按显示名长度再字母序排序；learning→[combination, greatMoments]。

### 1.3 状态与持久化键（ContentView.swift）

- 顶部选择状态（**@State，非持久化**）：`selectedAlgorithmGroup=.basic`（`:735`）、`selectedAlgorithm=.chordExercise`（`:736`）、`selectedGuidePreset=.smooth`（`:737`）。
- 色彩/加花 @AppStorage：
  - `transformEnabled=false`（`:738`）、`transformMusician=My`（`:739`）；
  - `guideColorEnabled=false`（`:740`，Guide **加花星光 ✧**，TRANSFORM 开才生效）；
  - `guideLineColorEnabled=false`（`:741`，Guide **骨架线条色彩**，独立于 TRANSFORM）；
  - `grammarColorEnabled=false`（`:745`，旧默认 true 已在 `:742-744` 封存注释）；
  - `lstmColorEnabled=false`（`:747`）；
  - `colorModeRaw=conservative`（`:751`，色彩宽度）。
- `analysisDisplayMode=chordDegrees`（`:111`）——**本次不碰**。
- 休眠（dormant）旧设置码，**本次不动、仅记录**：
  - `lowNoteMidi=60 / highNoteMidi=81`（`:710-711`，注意休眠默认是 81 不是 79）；
  - `showSettings`（`:732`）+ 其 sheet（`:2002-2007`，引用 `SettingsView`）；
  - `struct SettingsView`（`:3373-3408`）、`struct PianoRangeView`（`:3419-3486`，静态不可点）、`struct PianoKeyboardView`（`:3714` 起，可拖动但无引用）。

### 1.4 生成管线与 worker（ContentView.swift）

- `generateEmptyRoadmap()`（`:950-1129`）：无旋律谱休止骨架；分析 `:1120-1125` → `refreshKeySections`（`:1126`）→ **`self.generatedSolo = tempMeasures`（`:1127`，在位 ✓）** → `soloVersion`（`:1128`）。
- `runJazzGenerationPipeline(jumpToSolo:)`（`:1134-1177`）：
  - 付费门（`:1137`）：`(.master || .learning) && !purchased` → 记 pending + 弹墙、return；
  - 捕获快照（`:1144-1154`），`Task.detached`（`:1163`）调 worker；
  - 回主线程（`:1165-1175`）：写 `generatedSolo`、`soloVersion`、analysis、keySections、`hasGeneratedImprovisation=true`，jumpToSolo 时切 Solo。
- `generateMeasuresWorker(...)`（`:1180` 起，nonisolated）：
  - `isGuide`（`:1182`）；Guide 保留 NC 的 roadmap 构建（`:1197-1208`），非 Guide 过滤 NC（`:1209-1231`）；
  - Guide 策略装配（`:1239-1252`）：direction/maxDuration 取自预设、startDegree 写死 "1"、limits 写死 60/79、`allowColor=guideLineColorEnabled`；
  - Learning 分支（`:1253-1258`）：`(algorithm==.greatMoments) ? "GreatMoments" : "combination"`，色彩/宽度注入 LSTMStrategy；
  - Grammar 分支（`:1259-1279`）：`transformMode`、`rectifyMode = grammarColorEnabled ? .allBeats : .javaSpellOnly`（`:1273`）、`colorMode`（`:1274`）、octave 固定 smooth（`:1276`）；
  - Guide 加花桥（`:1306-1318`）：仅 `isGuide && enableTransform`；加花色彩 `gColor`：✧ 关→.off，✧ 开→按 `colorRaw` 出 conservative/full（`:1308-1311`）；
  - Guide 不做相邻同音合并（`:1329-1331`）；Guide 特殊量化分支另见 `:1482`、`:1706`。

### 1.5 顶部工具栏 UI（ContentView.swift `topToolbar` `:2242` 起）

- 第一组 Menu（`:2279-2317`）：遍历 `[.guide,.basic,.master,.learning]`（`:2280`）；选中回调重置三标记（`:2283-2286`），非 guide 时若已选不在目标列表则回退首项（`:2289-2294`）。
- 第二控件（`:2319-2386`）：
  - Guide：四档预设 Menu（`:2321-2347`）；
  - 其余：语法 Menu（`:2349-2385`），**付费点 ②** 选择拦截（`:2352-2355`）、**付费点 ③** 锁图标（`:2361-2363`）。
- 生成键（`:2574-2601`）：**付费点 ④**（`:2576-2580`）；清场后 `runJazzGenerationPipeline()`（`:2590`）。

### 1.6 付费墙（4 处行为点 + 购买回调）

| # | 位置 | 现状判定 | 作用 |
|---|---|---|---|
| ① | `:1137` | `.master\|\|.learning` | pipeline 最底层门 |
| ② | `:2352` | `.master\|\|.learning` | 第二下拉选择拦截 → pending + 墙 |
| ③ | `:2361` | `.master\|\|.learning` | 菜单行锁图标（纯显示） |
| ④ | `:2576` | `.master\|\|.learning` | 生成键门 |

- Paywall sheet（`:2024-2033`）：`PaywallView { … }`，解锁回调只做 `selectedAlgorithm = pendingMasterAlgorithm`（`:2027-2030`）——**与组无关**。
- `PaywallView.swift`：标题 "Unlock Master Algorithms"；购买成功或 `isPurchased` 翻 true 均触发 `onUnlock`（`:27, 67-69`）。
- `IAPManager.swift`：单商品 `com.realimpro.master.lifetime`（`:7`）；DEBUG 出厂 `isPurchased=true`（`:17-19`，回归真机 Release 需用 TestFlight/沙盒账号验证未购态）；购买/恢复/交易监听均只翻 `isPurchased`，不区分组。

### 1.7 调音台（BandMixerView.swift）

- 入参绑定（`:35-60`）：四轨音量/静音、STYLE、展开态、Transform 开关/乐手、四个色彩绑定、`group`、`isPlaying`。
- 分流（`:63-90`）：`isGuideGroup`、`isLearning`；
  - ① 主 COLOR 圆点绑定 `lineColorBinding`（`:67-71`：guide→guideLine、learning→lstm、其余→grammar）、`lineColorIsOn`（`:73`）；
  - ② 宽度下拉绑定 `widthColorBinding`（`:76-80`）、`widthColorIsOn`（`:81`）；
  - ③ Guide 加花 ✧：`embellishInteractive = isGuideGroup && enableTransform`（`:84`）、`embellishIsOn=guideColorEnabled`（`:85`）；
  - ④ 宽度菜单可点条件 `widthMenuInteractive`（`:88-90`）；TRANSFORM 对 Learning 置灰 `transformInteractive`（`:92`）。
- 右栏 UI（展开时）：STYLE（`:142-174`）、**COLOR 圆点行（`:180-204`）**、TRANSFORM 行 + Guide ✧（`:208-252`）、乐手 Menu（`:256-285`）、宽度 Menu（`:290-319`）。右栏恒宽 **110**（`:364`）。
- ContentView 调用点：`:2751-2767`。

---

## 2. 色彩 / 设置开关 → @AppStorage 键 → 迁移位置（完整映射表）

| # | 开关（乐手语义） | 现有键（类型, 默认） | 现有 UI 入口 | 阶段一新位置 | 阶段二新位置 |
|---|---|---|---|---|---|
| 1 | Guide **骨架线条**是否含色彩音（Allow Color Tones） | `guideLineColorEnabled`（Bool, **false**） | 调音台 COLOR 圆点（Guide 时） | **Guide 卡片 · Color 行** | 同左 |
| 2 | Guide **加花**星光色彩 ✧（仅 TRANSFORM 点亮可点） | `guideColorEnabled`（Bool, **false**） | 调音台 TRANSFORM 行内 ✧ | **调音台保留 ✧**（规格 D 拍板） | 同左 |
| 3 | Grammar（Basic/Master）是否含色彩音 | `grammarColorEnabled`（Bool, **false**） | 调音台 COLOR 圆点（Basic/Master 时） | **Basic 卡 / Master 卡 · Color 行** | **Grammar 卡 · Color 行** |
| 4 | Learning 是否含色彩音 | `lstmColorEnabled`（Bool, **false**） | 调音台 COLOR 圆点（Learning 时） | **Learning 卡 · Color 行** | 同左 |
| 5 | Transform 加花总开关 | `transformEnabled`（Bool, **false**） | 调音台 TRANSFORM 圆点 | 调音台保留 | 同左 |
| 6 | Transform 乐手（My + 25 位） | `transformMusician`（String, **My**） | 调音台乐手 Menu | 调音台保留 | 同左 |
| 7 | 色彩音池宽度 Conservative/Extended | `colorModeRaw`（String, **conservative**） | 调音台宽度 Menu | **建议调音台保留（待拍板 §0）** | 同左 |
| 8 | Guide 走向 Direction | `selectedGuidePreset`（@State, **smooth→0**） | 顶部第二下拉（Guide） | **Guide 卡 · Direction**；新持久化 `guideDirectionRaw=0` | 同左 |
| 9 | Guide 起始音级 Start Degree | 无（worker 写死 **"1"**） | 无 | **Guide 卡 · Start Degree**；`guideStartDegreeRaw="1"` | 同左 |
| 10 | Guide 最大音符时长 Max Duration | `selectedGuidePreset`（smooth→**240**；busy→120） | 顶部第二下拉（Guide） | **Guide 卡 · Max Duration**；`guideMaxDurationRaw=240` | 同左 |
| 11 | Guide 音域 Range | 无（worker 写死 **60/79**） | 无 | **Guide 卡 · Range → 键盘子页**；`guideRangeLowRaw=60 / HighRaw=79` | 同左 |
| 12 | Grammar 具体语法选择 | `selectedAlgorithm`（@State, **chordExercise**） | 顶部第二下拉 | Basic 卡 / Master 卡 · **Grammar Select** | Grammar 卡 · 统一 **Grammar Select**（3 免费 + 9 付费） |
| 13 | Learning 模型选择 Model Select | `selectedAlgorithm`（@State, **combination**） | 顶部第二下拉 | **Learning 卡 · Model Select**（Combination/Great Moments） | 同左 |

### 2.1 特别核实：各链路"开 Transform 后的加花色彩"归谁（防串键）

- **Guide（双色彩，最易串）**：
  - 骨架线条本身的色彩 → `guideLineColorEnabled`（`worker :1251` 注入 `allowColor`），**与 TRANSFORM 无关**；
  - TRANSFORM 加花部分的色彩 → `guideColorEnabled`（星光 ✧，`worker :1308-1311` 决定 `GuideRectifyColorMode`），仅 TRANSFORM 点亮生效；
  - 加花色彩的宽度 → `colorModeRaw`（conservative/full）。
- **Grammar（Basic/Master）**：加花在 `GrammarStrategy` 内部完成；加花后哪些音留下由整流档位决定——`grammarColorEnabled` 关→`.javaSpellOnly`、开→`.allBeats`（`worker :1273`）；色彩宽度读 `colorModeRaw`（`:1274`）。**即 Grammar 加花色彩 = `grammarColorEnabled`（总开关）+ `colorModeRaw`（宽度），没有第三个键。**
- **Learning**：Transform 引擎对 Learning **不作用**（调音台 TRANSFORM 恒置灰，`BandMixerView.swift:92`）；其"色彩"是 LSTM 整流允许音集合，由 `lstmColorEnabled` 控制（`LSTMStrategy.swift:55, 97-110`），宽度同样读 `colorModeRaw`。
- 结论：迁移后**每个色彩键仍只有一条消费链**，切组互不污染；调音台去 Color 不影响 ✧（独立键）。

---

## 3. 需要核实确认点的结论

### 3.1 Guide 引擎是否支持 Direction / StartDegree / MaxDuration 自由组合？旧四档如何映射？

**支持，且无需改算法。** 证据：
- `direction: Int`（`GuideLineGenerator.swift:83`）：作为实时方向贯穿评分 `directionScores`（`:76-80, 496-501`）与首音/就近八度选择（`:308-311`），接受任意 Int（-1/0/1）。
- `startDegree: String`（`:84`）：经 `oneGuideLine → firstNote`（`:109, 248`），由 `GTVocResolver.degreeOffset` 解析（`:254`），"1/3/5/7" 均可。
- `maxDuration: Int`（`:85`）：`notesToAdd` 切块（`:527-531`）：`maxDuration > 0 且剩余 > maxDuration` 才切，**0 = 不限制（No Preference）**。

**旧四档 → 新三参数映射（Java `GuideToneLineDialog.java:739-752, 1022-1033` 口径）：**

| 旧预设 | Direction | Max Duration | Start Degree（旧写死） |
|---|---|---|---|
| Smooth | 0 = No Preference | 240 = Half | "1" |
| Rising | +1 = Ascending | 240 = Half | "1" |
| Falling | −1 = Descending | 240 = Half | "1" |
| Busy | 0 = No Preference | 120 = Quarter | "1" |

- Java 常量已核：`WHOLE=480 / HALF=240 / QUARTER=120`（`Constants.java:66-68`）；Direction：ascending=1/descending=−1/noPreference=0（`GuideToneLineDialog.java:1022-1033`）。
- Java 出厂选中：Direction = **No Preference**（`:238`）、Max Duration = **Half**（`:346`）；Start Degree 按钮按首和弦动态生成、默认第一项。Swift 卡片按规格固定 1/3/5/7，**出厂默认取 "1"（沿用现行为、不翻默认）**。
- 新出厂组合（No Preference + "1" + Half + 60–79）**逐参数等于旧 Smooth** → Guide 回归 18,470 音符不变。

### 3.2 Range 音域可否参数化？键盘子页怎么接？

- 引擎侧 `lowLimit/highLimit` 本就是变量（`GuideLineGenerator.swift:66-67`），`middleOfRange`（`:63-65`）、`closestToMiddle`（`:279-332`）、`getClosest`（`:367-430`）全部读这两个值；仅 worker `:1246-1247` 写死 60/79。**可参数化。**
- Java 接法（`GuideToneLineDialog.java:968-971`）：`RangeChooser(notate, low, high, OCTAVE)`。`RangeChooser.java` 语义：
  - 两个被点键 clicked[LOW/HIGH]；**点任意键 → 替换距离更近的那个端点**（`closer()` `:391-393`）；
  - 结果必须合法：两端在可点范围、low < high、跨度 ≥ minimum（Guide 传 **OCTAVE=12**，`:345-349`）；不合法则忽略（`:411-413`）；
  - 高音谱可点范围 **A2–C7（MIDI 45–96）**（`GuideToneLineDialog.java:78`），默认 **{C4, G5} = {60, 79}**（`:73`）。
- Swift 子页（本报告新文件内 `GuideRangeSubpage`）：横向滚动钢琴（白键 22pt），范围 45–96，低/高端点分别着色，点键按上述 Java 规则替换、强制跨度 ≥12；出厂居中到 60。

### 3.3 Avoid repeat pitches 是否已固定内置？

**是，不暴露。**
- Swift：`_grammarAvoidRepeats` 默认 **true**（`GrammarNoteConverter.swift:39`），从文法参数读 `"avoid-repeats"`、缺省回退 true（`:162`）；选音接受概率 `:1102-1103`；生成后结尾合并相邻非休止同音（`GrammarLickGlue.swift:570, 654`，对齐 Java `removeRepeatedNotesInPlace`）。
- Java：`AVOID_REPEATS = "avoid-repeats"`、**`AVOID_REPEATS_DEFAULT = "true"`**（`LickGen.java:106-107`，默认值返回 `:3007-3009`）。两边一致。

### 3.4 Basic/Master 合并涉及的全部分支点 & 付费改"语法在付费集合"的做法

**全工程 `.basic/.master` 组级分支仅存在于 ContentView.swift（9 处）**，其余命中（`grammar.masterParameters`、`basicSwing()`、`masterGain`）均为无关同名物。清单：

| # | 行 | 内容 | 阶段二处理 |
|---|---|---|---|
| 1 | `:735` | 默认组 `.basic` | → `.grammar` |
| 2 | `:770-772` | currentAlgorithmList `.basic` | 合并为 `.grammar` 单 case |
| 3 | `:773-783` | currentAlgorithmList `.master` | 同上（列表 = 3 + 9） |
| 4 | `:1137` | 付费门 ① | 改新判定（下） |
| 5 | `:1180` | worker 形参默认 `.basic` | → `.grammar` |
| 6 | `:2280` | 第一 Menu 遍历 4 组 | → `[.guide,.grammar,.learning]` |
| 7 | `:2352` | 付费点 ② | 阶段二此 UI 已在卡片，按行判定 |
| 8 | `:2361` | 付费点 ③ 锁图标 | 同上 |
| 9 | `:2576` | 付费门 ④ | 改新判定（下） |

- worker 内分流只有 `isGuide`（`:1182`）与 `group == .learning`（`:1253`）；basic/master **本来就共用同一条 else 路径**，合并后零算法改动。
- **付费判定新做法**（在 `ImproAlgorithmType` 上新增，落在 `:99` 之后）：

```swift
        // [阶段二] 大师付费语法集合（9 项）；免费＝基础 3 项（chord/color/greatMoments）
        static let paidGrammarTypes: Set<ImproAlgorithmType> = [
            .LeeMorgan, .charlieParker, .billEvans, .joePass,
            .cannonballAdderley, .chetBaker, .johnColtrane,
            .milesDavis, .redGarland]
        /// 是否属于付费大师语法
        var isPaidGrammar: Bool { Self.paidGrammarTypes.contains(self) }
```

  统一门判定（① `:1137` 与 ④ `:2576`）：

```swift
let needsPaywall = (selectedAlgorithmGroup == .grammar && selectedAlgorithm.isPaidGrammar)
                || (selectedAlgorithmGroup == .learning)
if needsPaywall && !iapManager.isPurchased { … }
```

  卡片 Grammar Select 逐行：`algo.isPaidGrammar && !isPurchased` → 行尾锁、点选走 pending+墙；其余直接选。**Learning 仍整组付费；购买回调与组无关，无需改。**
- **无 UserDefaults 迁移负担**：组与算法选择都是 @State（`:735-736`），不持久化，不存在残留 "basic"/"master" 原始值。
- **BandMixerView 无需改动**：其分流仅 `group == .guide / == .learning`（`:63-64`），if/else 非 switch，新增 `.grammar` 天然落入 Grammar 路径（lineColor 已在阶段一移除；宽度/✧ 逻辑不受影响）。阶段二构建时会以编译+截图复核此结论。

### 3.5 Learning Model Select 现有接线如何搬到卡片？

- 现状：第二下拉 learning 列表 `[.combination,.greatMoments]`（`:786`）；worker 把选中算法翻译成模型文件名（`:1255`）；LSTMStrategy 按名从 bundle 读 `<name>.rnn`（`LSTMStrategy.swift:123-126`）。
- 搬迁：Learning 卡内 **Model Select Menu 直接绑定同一个 `$selectedAlgorithm`**，两项二选一；未购用户点选仍走 pending+墙（同现 `:2352` 行为）。**worker、模型加载、文件均不动。**
- 不暴露 Generation Mode（内部固定整段生成）；Risk Level / Expert Weighting 二期。

### 3.6 弹出方式与最窄 mini 竖屏布局

- **方式：popover**（iPadOS 原生，锚定 Settings 按钮）：
  - 不全屏压乐谱、不遮 # 分析按钮；带箭头指向来源，符合"对话框"心智；iPad 上尺寸行为最可预测（无需 detents 那套固定比例，卡片可按内容定高）。
  - 固定 **宽 320pt**；卡内 `NavigationStack`（Range 子页 push）；高度按卡种给初定值（Guide 330 / Basic·Master·Learning 200 / Range 子页 360），落地以截图校准，只调高度常量。
  - 内容超高度时 ScrollView 兜底；卡片不随设置改动触发任何生成（所有参数只在下次点生成时被 worker 读取，符合回归点⑥）。
- **最窄基准 iPad mini 竖屏（744pt 宽）**：320pt 卡片浮层两侧仍余乐谱；右栏（调音台）恒宽 110 不受影响。
- **Range 键盘放不下的预案**：键盘横向 ScrollView（白键恒 22pt 可点），出厂滚动居中到默认区间，端点着色 + 顶栏文字实时显示 Low/High；不压缩键宽、不改为双步弹窗。
- 6 组尺寸（mini/11/13 × 横竖）按 mini 竖屏先出图，再逐一核对：不压五线谱、不截断、不遮 # 按钮。

---

## 4. 阶段一逐 hunk diff（组仍为 Guide/Basic/Master/Learning）

> 改动文件：**新建 `Views/ModeSettingsCard.swift`**、改 **ContentView.swift**、改 **BandMixerView.swift**。
> 所有"旧码封存"均为中文注释原位保留、不删除。下列行号为今日实读；应用前以工具重新校位。

### 4.0 新文件 Hunk N1：`Real imPro/Views/ModeSettingsCard.swift`（整文件即 hunk）

```swift
//
//  ModeSettingsCard.swift
//  RealimPro
//
//  [阶段一 20261008] 顶部「Settings」按钮弹出的上下文设置卡片（随当前模式换内容）。
//  纯 UI / 接线：不含任何算法、引擎、整流、生成逻辑；全部状态由 ContentView 持有并以 Binding 注入。
//  改动设置不触发重新随机——参数只在下次点「生成」时由 worker 读取。
//

import SwiftUI

// MARK: - 卡片入口
struct ModeSettingsCard: View {
    let group: ContentView.ImproAlgorithmGroup
    @Binding var selectedAlgorithm: ContentView.ImproAlgorithmType
    // 色彩开关
    @Binding var guideLineColorEnabled: Bool
    @Binding var grammarColorEnabled: Bool
    @Binding var lstmColorEnabled: Bool
    // Guide 卡片参数
    @Binding var guideDirection: Int
    @Binding var guideStartDegree: String
    @Binding var guideMaxDuration: Int
    @Binding var guideRangeLow: Int
    @Binding var guideRangeHigh: Int
    // 付费
    let isPurchased: Bool
    let onRequestPaywall: (ContentView.ImproAlgorithmType) -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch group {
                case .guide:
                    GuideSettingsCard(guideDirection: $guideDirection,
                                      guideStartDegree: $guideStartDegree,
                                      guideMaxDuration: $guideMaxDuration,
                                      guideLineColorEnabled: $guideLineColorEnabled,
                                      rangeLow: $guideRangeLow,
                                      rangeHigh: $guideRangeHigh)
                case .basic:
                    GrammarSettingsCard(title: "Basic",
                                        items: ContentView.ImproAlgorithmType.basicGrammarTypes,
                                        selected: $selectedAlgorithm,
                                        colorEnabled: $grammarColorEnabled,
                                        wholeCardPaid: false,
                                        isPurchased: isPurchased,
                                        onRequestPaywall: onRequestPaywall)
                case .master:
                    GrammarSettingsCard(title: "Master",
                                        items: ContentView.ImproAlgorithmType.masterGrammarList,
                                        selected: $selectedAlgorithm,
                                        colorEnabled: $grammarColorEnabled,
                                        wholeCardPaid: true,
                                        isPurchased: isPurchased,
                                        onRequestPaywall: onRequestPaywall)
                case .learning:
                    LearningSettingsCard(selected: $selectedAlgorithm,
                                         colorEnabled: $lstmColorEnabled,
                                         isPurchased: isPurchased,
                                         onRequestPaywall: onRequestPaywall)
                }
            }
            .padding(16)
            .frame(width: 320)
        }
    }
}

// MARK: - 语法列表（阶段一：沿用现分组；阶段二合并）
extension ContentView.ImproAlgorithmType {
    /// 基础 3 项（免费）
    static let basicGrammarTypes: [ContentView.ImproAlgorithmType] = [.chordExercise, .colorTone, .Lick]
    /// 大师 9 项（付费），排序规则与现 currentAlgorithmList 完全一致（显示名长度→字母序）
    static var masterGrammarList: [ContentView.ImproAlgorithmType] {
        [.LeeMorgan, .charlieParker, .billEvans, .joePass,
         .johnColtrane, .milesDavis, .cannonballAdderley,
         .chetBaker, .redGarland].sorted {
            let len0 = $0.rawValue.count, len1 = $1.rawValue.count
            if len0 != len1 { return len0 < len1 }
            return $0.rawValue < $1.rawValue
        }
    }
}

// MARK: - Guide 卡片
private struct GuideSettingsCard: View {
    @Binding var guideDirection: Int
    @Binding var guideStartDegree: String
    @Binding var guideMaxDuration: Int
    @Binding var guideLineColorEnabled: Bool
    @Binding var rangeLow: Int
    @Binding var rangeHigh: Int

    private let directions: [(label: String, value: Int)] = [
        ("No Preference", 0), ("Ascending", 1), ("Descending", -1)]
    private let degrees = ["1", "3", "5", "7"]
    private let durations: [(label: String, value: Int)] = [
        ("No Preference", 0), ("Whole", 480), ("Half", 240), ("Quarter", 120)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Guide").font(.system(size: 15, weight: .bold))

                // Direction
                cardRow(label: "Direction") {
                    Menu {
                        ForEach(directions, id: \.value) { d in
                            Button { guideDirection = d.value } label: {
                                HStack { Text(d.label); if d.value == guideDirection { Image(systemName: "checkmark") } }
                            }
                        }
                    } label: { menuLabel(current: directions.first { $0.value == guideDirection }!.label) }
                }

                // Start on Scale Degree
                cardRow(label: "Start on\nScale Degree") {
                    Menu {
                        ForEach(degrees, id: \.self) { d in
                            Button { guideStartDegree = d } label: {
                                HStack { Text(d); if d == guideStartDegree { Image(systemName: "checkmark") } }
                            }
                        }
                    } label: { menuLabel(current: guideStartDegree) }
                }

                // Max Note Duration
                cardRow(label: "Max Note\nDuration") {
                    Menu {
                        ForEach(durations, id: \.value) { d in
                            Button { guideMaxDuration = d.value } label: {
                                HStack { Text(d.label); if d.value == guideMaxDuration { Image(systemName: "checkmark") } }
                            }
                        }
                    } label: { menuLabel(current: durations.first { $0.value == guideMaxDuration }!.label) }
                }

                // Color（骨架线条色彩）
                HStack(spacing: 8) {
                    CircleToggle(isOn: $guideLineColorEnabled)
                    Text("Allow Color Tones").font(.system(size: 13))
                    Spacer()
                }

                // Range → 键盘子页
                NavigationLink {
                    GuideRangeSubpage(rangeLow: $rangeLow, rangeHigh: $rangeHigh)
                } label: {
                    HStack {
                        Text("Range").font(.system(size: 13)).foregroundColor(.primary)
                        Spacer()
                        Text(midiName(rangeLow) + "  –  " + midiName(rangeHigh))
                            .font(.system(size: 12)).foregroundColor(.secondary)
                        Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(width: 320, height: 330)   // 初定高，落地按 mini 竖屏截图校准
    }
}

// MARK: - Grammar 卡片（阶段一：Basic / Master 各一）
private struct GrammarSettingsCard: View {
    let title: String
    let items: [ContentView.ImproAlgorithmType]
    @Binding var selected: ContentView.ImproAlgorithmType
    @Binding var colorEnabled: Bool
    let wholeCardPaid: Bool        // Master=true：未购时整组行加锁
    let isPurchased: Bool
    let onRequestPaywall: (ContentView.ImproAlgorithmType) -> Void

    private var rowLocked: Bool { wholeCardPaid && !isPurchased }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 15, weight: .bold))

            HStack(spacing: 8) {
                CircleToggle(isOn: $colorEnabled)
                Text("Allow Color Tones").font(.system(size: 13))
                Spacer()
            }

            cardRow(label: "Grammar\nSelect") {
                Menu {
                    ForEach(items, id: \.self) { algo in
                        Button {
                            if rowLocked { onRequestPaywall(algo) } else { selected = algo }
                        } label: {
                            HStack {
                                Text(algo.rawValue)
                                if rowLocked { Image(systemName: "lock.fill").font(.caption2) }
                                if algo == selected { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: { menuLabel(current: selected.rawValue) }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 320, height: 200)
    }
}

// MARK: - Learning 卡片
private struct LearningSettingsCard: View {
    @Binding var selected: ContentView.ImproAlgorithmType
    @Binding var colorEnabled: Bool
    let isPurchased: Bool
    let onRequestPaywall: (ContentView.ImproAlgorithmType) -> Void

    private let models: [ContentView.ImproAlgorithmType] = [.combination, .greatMoments]
    private var rowLocked: Bool { !isPurchased }   // Learning 整组付费

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Learning").font(.system(size: 15, weight: .bold))

            HStack(spacing: 8) {
                CircleToggle(isOn: $colorEnabled)
                Text("Allow Color Tones").font(.system(size: 13))
                Spacer()
            }

            cardRow(label: "Model\nSelect") {
                Menu {
                    ForEach(models, id: \.self) { algo in
                        Button {
                            if rowLocked { onRequestPaywall(algo) } else { selected = algo }
                        } label: {
                            HStack {
                                Text(algo.rawValue)
                                if rowLocked { Image(systemName: "lock.fill").font(.caption2) }
                                if algo == selected { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: { menuLabel(current: selected.rawValue) }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 320, height: 200)
    }
}

// MARK: - Range 键盘子页（对齐 Java RangeChooser：点键替换更近端点、跨度≥12）
private struct GuideRangeSubpage: View {
    @Binding var rangeLow: Int
    @Binding var rangeHigh: Int

    private let clickableLow = 45    // A2
    private let clickableHigh = 96   // C7
    private let minSpan = 12
    private let whiteW: CGFloat = 22
    private let whiteH: CGFloat = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose Range").font(.system(size: 15, weight: .bold))
            Text("Low: \(midiName(rangeLow))    High: \(midiName(rangeHigh))")
                .font(.system(size: 12)).foregroundColor(.secondary)
            ScrollViewReader { sp in
                ScrollView(.horizontal, showsIndicators: true) {
                    keyboard()
                }
                .onAppear { sp.scrollTo(60, anchor: .center) }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 320, height: 360)
        .navigationTitle("Range")
        .navigationBarTitleDisplayMode(.inline)
    }

    // 逐八度绘制（C3=48 … C7=96），末尾补 C7
    private func keyboard() -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<4) { oct in
                octaveKeys(rootMidi: 48 + oct * 12)
            }
            singleWhite(midi: 96)   // C7
        }
    }

    private func octaveKeys(rootMidi: Int) -> some View {
        let blackOffsets: [(pc: Int, w: CGFloat)] =
            [(1, whiteW*1 - 7), (3, whiteW*2 - 7), (6, whiteW*4 - 7),
             (8, whiteW*5 - 7), (10, whiteW*6 - 7)]
        return ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ForEach(0..<7) { pc in singleWhite(midi: rootMidi + pc) }
            }
            ForEach(blackOffsets.indices, id: \.self) { i in
                singleBlack(midi: rootMidi + blackOffsets[i].pc)
                    .offset(x: blackOffsets[i].w)
            }
        }
    }

    private func singleWhite(midi: Int) -> some View {
        let isLow = midi == rangeLow, isHigh = midi == rangeHigh
        return Button { tapped(midi) } label: {
            ZStack(alignment: .bottom) {
                Rectangle().fill(isLow ? Color.accentColor.opacity(0.85)
                                       : (isHigh ? Color.orange : Color.white))
                Rectangle().stroke(Color.gray.opacity(0.4), lineWidth: 0.5)
                if midi % 12 == 0 {
                    Text(midiName(midi)).font(.system(size: 8))
                        .foregroundColor(.secondary).padding(.bottom, 4)
                }
            }
            .frame(width: whiteW, height: whiteH)
        }
        .buttonStyle(.plain)
    }

    private func singleBlack(midi: Int) -> some View {
        let isEdge = midi == rangeLow || midi == rangeHigh
        return Button { tapped(midi) } label: {
            Rectangle().fill(isEdge ? Color.red : Color.black)
                .frame(width: 14, height: whiteH * 0.6)
        }
        .buttonStyle(.plain)
    }

    // Java RangeChooser 规则：替换更近端点；low<high 且跨度≥12，否则忽略
    private func tapped(_ midi: Int) {
        guard (clickableLow...clickableHigh).contains(midi) else { return }
        let replaceLow = abs(midi - rangeLow) < abs(midi - rangeHigh)
        if replaceLow {
            if midi < rangeHigh && (rangeHigh - midi) >= minSpan {
                rangeLow = midi; lightHaptic()
            }
        } else {
            if rangeLow < midi && (midi - rangeLow) >= minSpan {
                rangeHigh = midi; lightHaptic()
            }
        }
    }

    private func lightHaptic() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

// MARK: - 通用小组件
/// 圆点勾选（circle / largecircle.fill.circle），与调音台圆点同风格
struct CircleToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isOn.toggle()
        } label: {
            Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isOn ? .accentColor : .secondary)
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 卡片行：左标签（固定 104pt）+ 右控件
private func cardRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
    HStack {
        Text(label).font(.system(size: 12)).foregroundColor(.secondary)
            .frame(width: 104, alignment: .leading)
        Spacer(minLength: 0)
        content()
    }
}

/// 胶囊式 Menu 标签（与调音台胶囊风格一致）
private func menuLabel(current: String) -> some View {
    HStack(spacing: 4) {
        Text(current).font(.system(size: 12, weight: .medium)).lineLimit(1)
        Spacer(minLength: 0)
        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
    }
    .foregroundColor(.primary)
    .padding(.horizontal, 8)
    .frame(width: 160, height: 28)
    .background(Color.gray.opacity(0.12))
    .clipShape(Capsule())
    .contentShape(Capsule())
}

/// MIDI → 音名（MIDI 60 = C4）
fileprivate func midiName(_ midi: Int) -> String {
    let names = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "G#", "A", "Bb", "B"]
    return names[midi % 12] + "\(midi / 12 - 1)"
}
```

### 4.1 ContentView.swift hunks

**Hunk P1-A｜新增 Guide 卡片状态（插在 `:747` lstmColorEnabled 之后）**

```swift
    // [阶段一 20261008] Guide 卡片参数（持久化；出厂默认＝旧 Smooth：direction 0 / degree "1" / maxDuration 240 / range 60–79）
    @AppStorage("guideDirectionRaw") private var guideDirectionRaw: Int = 0
    @AppStorage("guideStartDegreeRaw") private var guideStartDegreeRaw: String = "1"
    @AppStorage("guideMaxDurationRaw") private var guideMaxDurationRaw: Int = 240
    @AppStorage("guideRangeLowRaw") private var guideRangeLowRaw: Int = 60
    @AppStorage("guideRangeHighRaw") private var guideRangeHighRaw: Int = 79
    @State private var showModeSettings: Bool = false
```

**Hunk P1-B｜封存四档枚举（`:15-34` 整体块注释）**

```swift
    // MARK: - [旧码封存 P1 20261008] Guide Tone Line 四档线条预设枚举（Guide 卡片 Direction+StartDegree+MaxDuration 取代）：
    /*
    enum GuideLinePreset: CaseIterable {
        …（原 :17-34 全部内容原位保留于本块注释内）…
    }
    */
```

**Hunk P1-C｜封存 selectedGuidePreset 状态（`:737`）**

```swift
    // [旧码封存 P1 20261008] @State private var selectedGuidePreset: GuideLinePreset = .smooth  // Guide 组四档线条，默认平滑两拍
```

> 附注：`:768`（currentAlgorithmList 内"Guide 组第二控件显示四档线条预设"）为**纯注释行**，阶段一应用时在该行尾补注"（已迁入 Guide 卡片，P1）"，不改任何代码；其余 `GuideLinePreset` 引用（`:1180`、`:2322`）均已在 P1-F / P1-H 中处理。

**Hunk P1-D｜pipeline 快照捕获（替换 `:1147`）**

旧码：`let guidePreset = selectedGuidePreset`
新码（旧码以注释封存于上一行）：

```swift
        // [旧码封存 P1] let guidePreset = selectedGuidePreset
        // [阶段一] Guide 卡片三参数 + 音域，捕获快照进后台
        let guideDirection = guideDirectionRaw
        let guideStartDegree = guideStartDegreeRaw
        let guideMaxDuration = guideMaxDurationRaw
        let guideRangeLow = guideRangeLowRaw
        let guideRangeHigh = guideRangeHighRaw
```

**Hunk P1-E｜worker 调用（替换 `:1164`）**

```swift
            let result = self.generateMeasuresWorker(song: songToUse, key: key, group: group,
                                                     algorithm: algorithm,
                                                     guideDirection: guideDirection,
                                                     guideStartDegree: guideStartDegree,
                                                     guideMaxDuration: guideMaxDuration,
                                                     guideRangeLow: guideRangeLow,
                                                     guideRangeHigh: guideRangeHigh,
                                                     enableTransform: transform,
                                                     transformMusician: transformMusician,
                                                     colorRaw: colorRaw,
                                                     guideColorEnabled: guideColor,
                                                     guideLineColorEnabled: guideLineColor,
                                                     grammarColorEnabled: grammarColor,
                                                     lstmColorEnabled: lstmColor)
```

**Hunk P1-F｜worker 签名（替换 `:1180`；阶段一默认组仍 `.basic`）**

```swift
    nonisolated private func generateMeasuresWorker(song: JazzSong, key: String,
                                                    group: ImproAlgorithmGroup = .basic,
                                                    algorithm: ImproAlgorithmType,
                                                    guideDirection: Int = 0,
                                                    guideStartDegree: String = "1",
                                                    guideMaxDuration: Int = 240,
                                                    guideRangeLow: Int = 60,
                                                    guideRangeHigh: Int = 79,
                                                    enableTransform: Bool,
                                                    transformMusician: String,
                                                    colorRaw: String,
                                                    guideColorEnabled: Bool = false,
                                                    guideLineColorEnabled: Bool = false,
                                                    grammarColorEnabled: Bool = false,
                                                    lstmColorEnabled: Bool = false
    ) -> (measures: [GeneratedMeasure], analysis: AnalysisResult?) {
```

**Hunk P1-G｜Guide 策略装配（替换 `:1243-1247`；旧 5 行注释封存）**

```swift
            // [旧码封存 P1 20261008] 四档预设/写死值注入：
            // guideStrategy.direction   = guidePreset.direction    // 四档：0 / +1 / -1 / 0
            // guideStrategy.maxDuration = guidePreset.maxDuration  // 四档：240 / 240 / 240 / 120
            // guideStrategy.startDegree = "1"
            // guideStrategy.lowLimit    = 60
            // guideStrategy.highLimit   = 79
            // [阶段一] 改为卡片自由参数（默认值逐参数等于旧 Smooth）
            guideStrategy.direction   = guideDirection
            guideStrategy.maxDuration = guideMaxDuration
            guideStrategy.startDegree = guideStartDegree
            guideStrategy.lowLimit    = guideRangeLow
            guideStrategy.highLimit   = guideRangeHigh
```

**Hunk P1-H｜顶部第二控件 → Settings 按钮（`:2319-2386` 旧整块封存，其后插入新按钮）**

```swift
                    // [旧码封存 P1 20261008] Guide 预设 Menu + Basic/Master/Learning 语法 Menu（Settings 按钮取代）：
                    /*
                    if selectedAlgorithmGroup == .guide {
                        …（原 :2319-2347 全部内容原位保留）…
                    } else {
                        …（原 :2349-2385 全部内容原位保留；含付费点②③）…
                    } // 第二控件按组切换（Guide 预设 / Basic-Master 语法）
                    */
                    // [阶段一] Settings 按钮：占原第二控件位置、宽度沿用 algorithmLabelWidth（零布局位移）
                    Button {
                        triggerImpactHaptic(.light)
                        showModeSettings = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "gearshape")
                                .font(.system(size: isVerySmallScreen ? 12 : 13))
                            Text("Settings")
                                .font(.system(size: isVerySmallScreen ? 12 : 13, weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(width: algorithmLabelWidth)
                        .background(Color.gray.opacity(0.12))
                        .cornerRadius(6)
                    }
                    .popover(isPresented: $showModeSettings) {
                        ModeSettingsCard(group: selectedAlgorithmGroup,
                                         selectedAlgorithm: $selectedAlgorithm,
                                         guideLineColorEnabled: $guideLineColorEnabled,
                                         grammarColorEnabled: $grammarColorEnabled,
                                         lstmColorEnabled: $lstmColorEnabled,
                                         guideDirection: $guideDirectionRaw,
                                         guideStartDegree: $guideStartDegreeRaw,
                                         guideMaxDuration: $guideMaxDurationRaw,
                                         guideRangeLow: $guideRangeLowRaw,
                                         guideRangeHigh: $guideRangeHighRaw,
                                         isPurchased: iapManager.isPurchased,
                                         onRequestPaywall: { algo in
                                             pendingMasterAlgorithm = algo
                                             showPaywall = true
                                         })
                    }
                    .layoutPriority(0)
```

> 说明：付费点②③随旧第二菜单封存；其职能在卡片内重建——Master 卡 / Learning 卡未购时行尾锁、点选走 `onRequestPaywall`（行为等价：记 pending + 弹墙，购买回调不变）。付费点①④保留在原位（`:1137 / :2576`），阶段一判定不变。

### 4.2 BandMixerView.swift hunks

**Hunk M1-A｜封存主 COLOR 绑定（`:66-73` 块注释）**

```swift
    // [旧码封存 P1 20261008] 主 COLOR 圆点绑定（色彩开关已迁入各模式设置卡片）：
    /*
    // ① 主 COLOR 圆点＝线条/骨架色彩：…
    private var lineColorBinding: Binding<Bool> { … }
    // 主 COLOR 圆点恒可点…
    private var lineColorIsOn: Bool { lineColorBinding.wrappedValue }
    */
```

**Hunk M1-B｜封存 COLOR 圆点行 UI（`:180-204` 块注释）**

```swift
                        // [旧码封存 P1 20261008] 主 COLOR 圆点行（色彩开关迁入卡片）：
                        /*
                        HStack(spacing: 4) {
                            …（原 :183-203 全部内容原位保留）…
                        }
                        .frame(height: 14)
                        */
```

保留不动：TRANSFORM 行 + Guide ✧（`:208-252`）、乐手 Menu（`:256-285`）、宽度 Menu（`:290-319`，**按 §0 拍板：默认保留**）。入参清单不变 → ContentView `:2751-2767` 调用点阶段一不动。

**Hunk M1-C（备选，仅当您拍板"宽度下拉去掉"时执行）｜封存宽度 Menu（`:287-319` 块注释）**

```swift
                        // [备选封存 M1-C] Conserv/Ext 宽度下拉（Extended 改无 UI 入口；colorModeRaw 键与默认值保留）：
                        /*
                        Menu { … } … .opacity(widthMenuInteractive ? 1 : 0.4)
                        */
```
> 注：`:95` 的 `@AppStorage("colorModeRaw")` 与 ContentView 侧同键，**不封存**（引擎仍读）；`widthColorBinding/widthMenuInteractive` 随之失去 UI 引用，若执行 M1-C 再一并块注释封存（届时补充，不混入默认 hunks）。

---

## 5. 阶段二逐 hunk diff（Basic + Master → Grammar；阶段一回归通过后另报批）

> 仅改 **ContentView.swift** 与 **ModeSettingsCard.swift**；BandMixerView 已核无需改；算法/语法文件不动。

**Hunk P2-A｜枚举（替换 `:6-13`）**

```swift
    enum ImproAlgorithmGroup: String, Equatable {
        case guide = "Guide"
        // [旧码封存 P2] case basic = "Basic"
        // [旧码封存 P2] case master = "Master"
        case grammar = "Grammar"   // [P2 20261008] Basic+Master 合并
        case learning = "Learning"
        // …（原下线注释保留）…
    }
```

**Hunk P2-B｜默认组（替换 `:735`）**

```swift
    // [旧码封存 P2] @State private var selectedAlgorithmGroup: ImproAlgorithmGroup = .basic
    @State private var selectedAlgorithmGroup: ImproAlgorithmGroup = .grammar
```

**Hunk P2-C｜currentAlgorithmList（替换 `:770-783` 两个 case 为一个）**

```swift
        case .grammar:
            // [P2] 基础 3（免费）在前，大师 9（付费）按原排序规则在后
            return ImproAlgorithmType.basicGrammarTypes + ImproAlgorithmType.masterGrammarList
        // [旧码封存 P2] case .basic: return [.chordExercise, .colorTone, .Lick]
        // [旧码封存 P2] case .master: …（原排序块原位注释保留）…
```

**Hunk P2-D｜付费集合与判定**

1) 在 `ImproAlgorithmType` `:99`（grammarFileName 闭括号）之后新增 `paidGrammarTypes / isPaidGrammar`（代码见 §3.4）。
2) 付费门 ①（`:1137`）与 ④（`:2576`）统一替换为：

```swift
        // [旧码封存 P2] if (selectedAlgorithmGroup == .master || selectedAlgorithmGroup == .learning) && !iapManager.isPurchased {
        let grammarNeedsPaywall = selectedAlgorithmGroup == .grammar && selectedAlgorithm.isPaidGrammar
        if (grammarNeedsPaywall || selectedAlgorithmGroup == .learning) && !iapManager.isPurchased {
            pendingMasterAlgorithm = selectedAlgorithm
            showPaywall = true
            return
        }
```

**Hunk P2-E｜worker 形参默认组（`:1180`）**

```swift
                                                    group: ImproAlgorithmGroup = .grammar,
```
（`isGuide :1182`、`group == .learning :1253` 不变；else 分支自然承接 `.grammar`，无其他 worker 改动。）

**Hunk P2-F｜第一组 Menu 遍历（替换 `:2280`）**

```swift
                        ForEach([ImproAlgorithmGroup.guide, .grammar, .learning], id: \.self) { grp in
```
（切组回调 `:2283-2294` 逻辑不变：`.grammar` 列表含全部 12 项，已选必在其中。）

**Hunk P2-G｜ModeSettingsCard.swift：两张卡合一**

1) 入口 switch 中 `.basic/.master` 两支替换为单支：

```swift
                case .grammar:
                    GrammarSettingsCard(title: "Grammar",
                                        items: ContentView.ImproAlgorithmType.basicGrammarTypes
                                             + ContentView.ImproAlgorithmType.masterGrammarList,
                                        selected: $selectedAlgorithm,
                                        colorEnabled: $grammarColorEnabled,
                                        isPurchased: isPurchased,
                                        onRequestPaywall: onRequestPaywall)
```

2) `GrammarSettingsCard` 由"整卡付费"改为"逐行付费"（替换其 `wholeCardPaid/rowLocked`）：

```swift
    // 行级判定：仅当该语法属于大师付费集合且未购时加锁
    private func rowLocked(_ algo: ContentView.ImproAlgorithmType) -> Bool {
        algo.isPaidGrammar && !isPurchased
    }
```
   Menu 行内：`if rowLocked(algo) { onRequestPaywall(algo) } else { selected = algo }`；标签处锁图标同条件。
   卡高初定 220（列表更长但只显示当前选中项，Menu 浮层不占卡高），落地按截图校准。

> Learning 卡、Guide 卡、Range 子页阶段二不变。

---

## 6. 备份计划（落地时执行，路径与命名沿用现有 `.backup` 约定）

阶段一（应用前完成，整文件拷贝 + 记录 SHA1）：

```
.backup/ContentView.swift.P1-settingscard-backup
.backup/BandMixerView.swift.P1-colorremove-backup
```

阶段二：

```
.backup/ContentView.swift.P2-grammarmerge-backup
.backup/ModeSettingsCard.swift.P2-grammarmerge-backup
```

应用时先 `shasum -a 1` 记录被改文件指纹（与本报告 §1.1 对照，确认落地前无他人改动）；备份文件与源文件同 hash。另：工程根有 `.git`，落地前后各做一次 `git status`，作为第二道保险（以 `.backup` 为准）。

---

## 7. 一键回退（脚本在落地批准后创建于 `scripts/`，此处先给全文）

**`scripts/rollback_phase1.sh`**

```bash
#!/bin/bash
# 阶段一一键回退：恢复两个被改文件、删除新增卡片文件
set -e
ROOT="/Users/onlyonear/Desktop/Improlyze"
cp "$ROOT/.backup/ContentView.swift.P1-settingscard-backup" \
   "$ROOT/Real imPro/Views/ContentView.swift"
cp "$ROOT/.backup/BandMixerView.swift.P1-colorremove-backup" \
   "$ROOT/Real imPro/Views/BandMixerView.swift"
rm -f "$ROOT/Real imPro/Views/ModeSettingsCard.swift"
echo "Phase 1 rolled back. In Xcode: Product > Clean Build Folder, then rebuild."
```

**`scripts/rollback_phase2.sh`**

```bash
#!/bin/bash
# 阶段二一键回退：恢复 ContentView 与卡片文件（回到阶段一通过态）
set -e
ROOT="/Users/onlyonear/Desktop/Improlyze"
cp "$ROOT/.backup/ContentView.swift.P2-grammarmerge-backup" \
   "$ROOT/Real imPro/Views/ContentView.swift"
cp "$ROOT/.backup/ModeSettingsCard.swift.P2-grammarmerge-backup" \
   "$ROOT/Real imPro/Views/ModeSettingsCard.swift"
echo "Phase 2 rolled back to Phase-1 state. Clean Build Folder then rebuild."
```

使用：`chmod +x scripts/rollback_phase*.sh`，需要时 `bash scripts/rollback_phase1.sh`。回退后 Xcode 内 Clean Build Folder 再编译。

---

## 8. 回归门执行清单（每阶段落地后实测、数值回报）

**数值对齐门（预期不变，若变即停）**
- Guide 音符数 **18,470**；raw grammar **30/30 OK、BAD=0**、FNV 哈希稳定；Transform 双端差异 **0**；Learning 两模型 teacher-forcing + 固定种子自由生成 **1536/1536**。
- 包内 **26 个 .tsv、合计 11,235,463 B**；两 `.rnn` 各 **9,136,016 B**。
- 时值守恒 **0 违例**；音域/空音检查；付费墙 4 处（含购买后解锁）行为正确。
- Xcode **GUI Build Succeeded、0 error**；命令行若现 AssetCatalogAgent/宏插件 spawn 怪象，如实说明、以 GUI + 真机为准。

**UI 回归（6 组尺寸，mini 竖屏先出图）**
- iPad mini / 11 / 13 × 横竖：卡片不压五线谱、不截断、不遮 # 分析按钮；调音台右栏恒宽 **110**；Guide 卡（5 行 + 键盘子页）为最高卡片。

**真机/模拟器用户路径**
1. 无旋律谱（iReal/Stylebook）未点生成即正常显示、不空白；
2. 有旋律谱正常；
3. 选曲、转调、生成 solo、Original⇄Solo 切换后谱面与卡片正确刷新、不残留上一首；
4. Range 选最低/最高实际生效；
5. 各色彩开关点亮/关闭结果正确；
6. 改设置不触发重新随机（下次点生成才生效）。
阶段二额外：免费语法可直接生成；9 位大师未购拦截、购后解锁；Learning 付费不变。

---

## 9. 无夹带声明

- 上述 hunks 仅包含：第二下拉→Settings 按钮+上下文卡片、色彩开关迁移、调音台去 Color（阶段一）；Basic/Master→Grammar 合并与付费判定改造（阶段二）。
- **不含**任何算法/引擎/整流/生成逻辑改动，**不翻**任何默认开关，**不新增**付费点、**不加**顶栏按钮（Settings 为替换原第二控件），用户可见处**不出现**「Java」字样。
- 休眠旧设置码（SettingsView/PianoRangeView/PianoKeyboardView/lowNoteMidi/highNoteMidi/showSettings）**一律不碰**。
- Roadmap 两套分析、Fractal、ThemeWeaver、G8 双线等暂停项不碰。
- 每个 hunk 旧码均中文注释原位封存；应用时逐 hunk 单独成段，不跨 hunk 混改。

**当前状态：勘察与方案已完成，生产目录零改动，等待您的书面批准（并请一并拍板 §0 宽度下拉「保留/去掉」）。**
