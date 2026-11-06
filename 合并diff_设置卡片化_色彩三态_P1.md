# 合并版逐 Hunk Diff：设置卡片化 + 四链路色彩统一 + Guide 骨架三态（阶段 P1）

> 状态：**待书面批准**。本文档产出前生产代码零改动；批准后才按「整文件备份 → 旧码封存 → 逐 hunk 应用 → Xcode GUI Build → 回归门 + 真机 → 回报数值截图」推进。
> 本轮**不做** Basic/Master → Grammar 合并（下阶段另报批）。

---

## 0. 范围、默认值与无夹带声明

**本轮做三件事（一份 diff）：**
1. 顶部第二下拉（Guide 预设 Menu / 语法 Menu）整体替换为一个 **Settings 按钮**，点击弹 sheet，sheet 内按当前组显示：
   - **Guide 卡**：Allow Color Tones（骨架）+ Conserv/Ext 宽度、Direction、Start on Scale Degree、Max Note Duration、Range（键盘子页；Range 跨启动持久化，其余参数不跨启动）；
   - **Basic / Master 卡**：Allow Color Tones + Conserv/Ext 宽度、Grammar 选择（Master 的付费锁原样迁移）；
   - **Learning 卡**：Allow Color Tones + Conserv/Ext 宽度、Model 选择（Combination / Great Moments，**未购带付费锁、点选弹付费墙，与 Master 卡同构**）。
2. Guide 骨架引擎 `Bool allowColor` 三态化为 `GuideRectifyColorMode { off, conservative, full }`；`off/full` 与旧 Bool 逐音等价（探针 0 失配），`conservative` 为新增档（用户已拍板）。
3. 调音台封存主 COLOR 行与 Conserv/Ext 宽度 Menu；保留 TRANSFORM 圆点、乐手下拉、Guide 加花 ✝（sparkles）。

**默认值核对（全部不翻）：** Guide 新五参数出厂 = No Preference(0) / degree "1" / Half(240) / 60 / 79 —— 逐参数等于旧 Smooth 预设，故 Guide 默认生成 18,470 音符不变。各色彩键出厂全 `false`；`colorModeRaw` 出厂 `conservative`。

**有意变更（用户已知晓并拍板）：** Guide 骨架开色彩时的宽度随全局 `colorModeRaw`（出厂 conservative），不再是写死 full；full 档保留、能力不丢。

**红线遵守：** 不改任何算法/引擎整流/生成逻辑/语法文件；不加付费点；不新增顶栏按钮（第二下拉是**替换**为按钮，顶栏控件总数不增）；用户可见处不出现「Java」；旧码一律中文注释原位封存、不删除。

**无夹带声明：** 本 diff 仅含下列 4 个文件的下列 hunk（3 改 + 1 新建），不含任何重命名、格式化、import 调整等方案外改动。

---

## 1. 文件清单、当前指纹与备份计划

| 文件 | 当前 SHA1（2026-10-09 实测） | 动作 | 落地时备份路径 |
|---|---|---|---|
| `Real imPro/GuideTone/GuideLineGenerator.swift` | `3ffee61ac71959f800b8fdc2bb82dbef4ad1a30f` | 5 hunk | `.backup/GuideLineGenerator.swift.P1-settingscard-backup` |
| `Real imPro/Views/ContentView.swift` | `c9e984b2ae6c45ecaf0b7f83db7804c22a56476f` | 7 hunk | `.backup/ContentView.swift.P1-settingscard-backup` |
| `Real imPro/Views/BandMixerView.swift` | `16957013bf2de919df1119f45aa04b80640e14f3` | 4 hunk | `.backup/BandMixerView.swift.P1-settingscard-backup` |
| `Real imPro/Views/ModeSettingsCard.swift` | （新建） | 新文件，同步根自动收录，无需改 pbxproj | 无需备份（git 可追） |

落地时先 `mkdir -p .backup` 并 `cp` 整文件备份，备份后 `shasum -a 1` 记录并与本表核对一致，再动 hunk。

---

## 2. 色彩 / 设置开关 → 持久化键 → 新位置 映射表

| 开关（乐手含义） | 现有键 / 默认 | 现状位置 | 迁移后位置 | 宽度可点条件 |
|---|---|---|---|---|
| Guide 骨架线条色彩（线条本身走出 9/11/13） | `guideLineColorEnabled` = false | 调音台主 COLOR 行（Guide 时） | **Guide 卡 Allow Color Tones** | 骨架开 或 (TRANSFORM 开且 ✝ 开) |
| Guide 加花色彩 ✝（TRANSFORM 加花部分带色彩） | `guideColorEnabled` = false | 调音台 TRANSFORM 行 ✝ | **调音台原位保留**（不动） | 同上（共用宽度键） |
| Grammar 色彩（Basic/Master 整流色彩） | `grammarColorEnabled` = false | 调音台主 COLOR 行（Basic/Master 时） | **Basic/Master 卡 Allow Color Tones** | grammarColor 开 |
| Learning 色彩（LSTM 整流色彩） | `lstmColorEnabled` = false | 调音台主 COLOR 行（Learning 时） | **Learning 卡 Allow Color Tones** | lstmColor 开 |
| 色彩宽度 Conserv/Ext | `colorModeRaw` = conservative（**全局单键，四链路共用**） | 调音台乐手下方宽度 Menu | **三张卡片各自带宽度控件，实时同步**；调音台封存 | 见上各行 |
| Guide 线条方向 | 现由四预设填（@State，非持久化） | 第二下拉（Guide） | **Guide 卡 Direction**（0/±1） | — |
| Guide 起始音级 | 写死 "1" | worker :1245 | **Guide 卡 Start Degree**（出厂仍 "1"） | — |
| Guide 最大音长 | 现由四预设填 | 第二下拉（Guide） | **Guide 卡 Max Duration**（出厂 240=Half） | — |
| Guide 音域 | 写死 60/79 | worker :1246-1247 | **Guide 卡 Range → 键盘子页**（出厂 60–79；**@AppStorage guideLowMidi/guideHighMidi 跨启动记忆**） | — |
| 语法文件选择 | `selectedAlgorithm`（@State） | 第二下拉（Basic/Master） | **Basic/Master 卡 Grammar 选择**（锁逻辑同迁） | — |
| Learning 模型选择 | `selectedAlgorithm`（@State） | 第二下拉（Learning） | **Learning 卡 Model 选择（Menu，未购带 lock.fill、点选弹付费墙；已购正常切换）** | — |

**核实结论（特别项）：**
- Grammar/Learning 开 TRANSFORM 后的加花色彩：Transform 内核本身**不产生色彩**；加花片段的色彩由所在链路键控制——Guide 走 `guideColorEnabled`（✝），Grammar 的加花随语法色彩同走 `colorModeRaw`（ContentView:1274），Learning 不作用于 Transform（TRANSFORM 在 Learning 下置灰）。
- Guide 骨架色彩 vs 加花 ✝ 是两个独立键（:740/:741），但**宽度共用** `colorModeRaw`——这是本轮有意设计，宽度控件在 Guide 卡只有一个。
- Avoid repeat pitches：Swift 语法引擎已固定内置（GrammarNoteConverter `_grammarAvoidRepeats=true`、读 "avoid-repeats" ?? true；结尾合并 GrammarLickGlue），不暴露。

---

## 3. 探针结论（/tmp/guide3state，生产零改动）

- **逐音等价**：288 和弦矩阵（12 根 × 24 质量）+ 12 调 ii-V-I cycle，新引擎 `off` vs 旧 false、`full` vs 旧 true：**0 失配**。
- **conservative 乐理正确性**（16 拍长线条、quarter 密度，324 测试和弦）：
  - 普通 7/11：全 12 根无 b9/#9/b13；
  - C9：旧 full 实际会吹 b13（Ab），conservative 滤除；C13 旧 full 吹 #11，滤除；
  - C7b13：显式 b13 保留、未写明的变化音滤除；7alt：变化音全保留（== full）；
  - 6/dim7/m6：滤掉 maj7（如 Cm 上的 B）；
  - conservative 与 full 实际音集合不同的 31/324，其余自然一致。
- **族级 fallback**（未知和弦强制表未命中）：三态均工作，conservative 同样过滤。
- 机制说明（乐手话）：Guide 走线在持续和弦上主要在和弦音间振荡；评分平局时 priority 恒让和弦音胜出，故色彩音本就极少被走到——三态化对默认听感几乎无影响，只在真正走到色彩音时决定"放哪些"。

---

## 4. 逐 Hunk Diff

### A. `Real imPro/GuideTone/GuideLineGenerator.swift`（5 hunk）

#### A1. 配置字段（现 :86）

```swift
// ── 现状（替换前）──
    var allowColor: Bool = false        // 是否允许色彩音
```
```swift
// ── 替换后 ──
    // [旧码封存 P1 20261009] var allowColor: Bool = false        // 是否允许色彩音（true=full/false=off）
    // [P1 用户已拍板] 骨架色彩三态：off/conservative/full；off/full 与旧 Bool 逐音等价，conservative 为新增档
    var colorMode: GuideRectifyColorMode = .off
```

#### A2. firstNote 查表（现 :252）

```swift
// ── 现状 ──
        if Self.useGuideToneVocabulary,
           let r = GTVocResolver.resolve(name: chord.name, allowColor: allowColor) {
```
```swift
// ── 替换后 ──
        if Self.useGuideToneVocabulary,
           // [旧码封存 P1] let r = GTVocResolver.resolve(name: chord.name, allowColor: allowColor) {
           let r = GTVocResolver.resolve(name: chord.name, colorMode: colorMode) {
```

#### A3. getChordTones 查表（现 :578）

```swift
// ── 现状 ──
        if Self.useGuideToneVocabulary,
           let r = GTVocResolver.resolve(name: chord.name, allowColor: allowColor) {
            return r.candidatePCs
        }
```
```swift
// ── 替换后 ──
        if Self.useGuideToneVocabulary,
           // [旧码封存 P1] let r = GTVocResolver.resolve(name: chord.name, allowColor: allowColor) {
           let r = GTVocResolver.resolve(name: chord.name, colorMode: colorMode) {
            return r.candidatePCs
        }
```

#### A4. 族级 fallback 色彩块（现 :651-685）

```swift
// ── 现状（整块替换）──
        // 色彩音（按优先级：9 > 13 > 11）
        if allowColor {
            // 九音
            if name.contains("9") || isAlt || name.contains("add9") {
                var ninthInterval = 2
                if name.contains("b9") || isAlt { ninthInterval = 1 }
                if name.contains("#9") { ninthInterval = 3 }
                tones.append((rootPC + ninthInterval) % 12)
            }

            // 十三音
            if name.contains("13") || isAlt {
                var thirteenthInterval = 9
                if name.contains("b13") { thirteenthInterval = 8 }
                if name.contains("#13") { thirteenthInterval = 10 }
                tones.append((rootPC + thirteenthInterval) % 12)
            }

            // 十一音
            if name.contains("11") || name.contains("add11") {
                var eleventhInterval = 5
                if name.contains("#11") { eleventhInterval = 6 }
                tones.append((rootPC + eleventhInterval) % 12)
            }
        }
```
```swift
// ── 替换后 ──
        // 色彩音（按优先级：9 > 13 > 11）
        // [旧码封存 P1 20261009] 旧 Bool 整块：
        // if allowColor {
        //     if name.contains("9") || isAlt || name.contains("add9") {
        //         var ninthInterval = 2
        //         if name.contains("b9") || isAlt { ninthInterval = 1 }
        //         if name.contains("#9") { ninthInterval = 3 }
        //         tones.append((rootPC + ninthInterval) % 12)
        //     }
        //     if name.contains("13") || isAlt {
        //         var thirteenthInterval = 9
        //         if name.contains("b13") { thirteenthInterval = 8 }
        //         if name.contains("#13") { thirteenthInterval = 10 }
        //         tones.append((rootPC + thirteenthInterval) % 12)
        //     }
        //     if name.contains("11") || name.contains("add11") {
        //         var eleventhInterval = 5
        //         if name.contains("#11") { eleventhInterval = 6 }
        //         tones.append((rootPC + eleventhInterval) % 12)
        //     }
        // }
        if colorMode != .off {
            // [P1] conservative 与 GTVocResolver 同源（conservativeColorIntervals）：
            // full 全放；conservative 只放 keep 集合内的色彩音程（自然 9/11/13；符号显式变化音按同集合保留）
            let keepConservative = Set(
                ChordQuality(chordName: name).colorIntervals(for: name, palette: .conservative))
            func appendColor(_ interval: Int) {
                if colorMode == .full || keepConservative.contains(interval) {
                    tones.append((rootPC + interval) % 12)
                }
            }
            // 九音
            if name.contains("9") || isAlt || name.contains("add9") {
                var ninthInterval = 2
                if name.contains("b9") || isAlt { ninthInterval = 1 }
                if name.contains("#9") { ninthInterval = 3 }
                appendColor(ninthInterval)
            }
            // 十三音
            if name.contains("13") || isAlt {
                var thirteenthInterval = 9
                if name.contains("b13") { thirteenthInterval = 8 }
                if name.contains("#13") { thirteenthInterval = 10 }
                appendColor(thirteenthInterval)
            }
            // 十一音
            if name.contains("11") || name.contains("add11") {
                var eleventhInterval = 5
                if name.contains("#11") { eleventhInterval = 6 }
                appendColor(eleventhInterval)
            }
        }
```

#### A5. priorityIndex 查表（现 :710）

```swift
// ── 现状 ──
        if Self.useGuideToneVocabulary,
           let r = GTVocResolver.resolve(name: chord.name, allowColor: allowColor) {
```
```swift
// ── 替换后 ──
        if Self.useGuideToneVocabulary,
           // [旧码封存 P1] let r = GTVocResolver.resolve(name: chord.name, allowColor: allowColor) {
           let r = GTVocResolver.resolve(name: chord.name, colorMode: colorMode) {
```

> `GTVocResolver.swift` 不改：生产代码已含 `enum GuideRectifyColorMode`（:20）与 `resolve(name:colorMode:)`（:89），探针即直接使用生产版编译。

---

### B. `Real imPro/Views/ContentView.swift`（7 hunk）

#### B1. 状态声明（现 :737）

```swift
// ── 现状 ──
    @State private var selectedGuidePreset: GuideLinePreset = .smooth  // Guide 组四档线条，默认平滑两拍
```
```swift
// ── 替换后 ──
    // [旧码封存 P1 20261009] @State private var selectedGuidePreset: GuideLinePreset = .smooth  // Guide 组四档线条
    // [P1] 四预设废弃 → 三参数自由组合 + 可参数化音域；出厂值逐参数=旧 Smooth（0/"1"/240/60/79）
    @State private var showModeSettings: Bool = false
    @State private var guideDirection: Int = 0          // Direction：0=No Preference（@State，不跨启动，同旧预设）
    @State private var guideStartDegree: String = "1"   // Start on Scale Degree（@State，不跨启动）
    @State private var guideMaxDuration: Int = 240      // Max Note Duration：240=Half（@State，不跨启动）
    // [P1 补充 20261009] Range 跨启动持久化（用户拍板）：标准 Int 键，默认仍 60/79；Binding 语义与 @State 一致
    @AppStorage("guideLowMidi") private var guideLow: Int = 60   // Range 最低音（持久化）
    @AppStorage("guideHighMidi") private var guideHigh: Int = 79 // Range 最高音（持久化）
```
> `enum GuideLinePreset`（:17-34）保留不删（无引用，顶层类型不触发警告），以备回退对照。

#### B2. 后台快照（现 :1147）

```swift
// ── 现状 ──
        let guidePreset = selectedGuidePreset
```
```swift
// ── 替换后 ──
        // [旧码封存 P1] let guidePreset = selectedGuidePreset
        let guideDir = guideDirection          // [P1] Guide 三参数+音域 捕获到后台
        let guideStart = guideStartDegree
        let guideMax = guideMaxDuration
        let guideLowCap = guideLow
        let guideHighCap = guideHigh
```

#### B3. Task.detached 调用参数（现 :1164）

```swift
// ── 现状（仅参数片段）──
    let result = self.generateMeasuresWorker(song: songToUse, key: key, group: group, algorithm: algorithm, guidePreset: guidePreset, enableTransform: transform, transformMusician: transformMusician, colorRaw: colorRaw, guideColorEnabled: guideColor, guideLineColorEnabled: guideLineColor, grammarColorEnabled: grammarColor, lstmColorEnabled: lstmColor)
```
```swift
// ── 替换后 ──
    let result = self.generateMeasuresWorker(song: songToUse, key: key, group: group, algorithm: algorithm, guideDirection: guideDir, guideStartDegree: guideStart, guideMaxDuration: guideMax, guideLow: guideLowCap, guideHigh: guideHighCap, enableTransform: transform, transformMusician: transformMusician, colorRaw: colorRaw, guideColorEnabled: guideColor, guideLineColorEnabled: guideLineColor, grammarColorEnabled: grammarColor, lstmColorEnabled: lstmColor)
```

#### B4. worker 签名（现 :1180）

```swift
// ── 现状（仅形参片段）──
nonisolated private func generateMeasuresWorker(song: JazzSong, key: String, group: ImproAlgorithmGroup = .basic, algorithm: ImproAlgorithmType, guidePreset: GuideLinePreset = .smooth, enableTransform: Bool, transformMusician: String, colorRaw: String, guideColorEnabled: Bool = false, guideLineColorEnabled: Bool = false, grammarColorEnabled: Bool = false, lstmColorEnabled: Bool = false) -> (measures: [GeneratedMeasure], analysis: AnalysisResult?) {
```
```swift
// ── 替换后 ──
// [旧码封存 P1] 旧形参 guidePreset: GuideLinePreset = .smooth（四预设）
nonisolated private func generateMeasuresWorker(song: JazzSong, key: String, group: ImproAlgorithmGroup = .basic, algorithm: ImproAlgorithmType, guideDirection: Int = 0, guideStartDegree: String = "1", guideMaxDuration: Int = 240, guideLow: Int = 60, guideHigh: Int = 79, enableTransform: Bool, transformMusician: String, colorRaw: String, guideColorEnabled: Bool = false, guideLineColorEnabled: Bool = false, grammarColorEnabled: Bool = false, lstmColorEnabled: Bool = false) -> (measures: [GeneratedMeasure], analysis: AnalysisResult?) {
```

#### B5. Guide 策略装配（现 :1243-1251）

```swift
// ── 现状 ──
            guideStrategy.direction   = guidePreset.direction    // 四档：0 / +1 / -1 / 0
            guideStrategy.maxDuration = guidePreset.maxDuration  // 四档：240 / 240 / 240 / 120
            guideStrategy.startDegree = "1"                      // 显式起始级=1，不吃类自带 "3"
            guideStrategy.lowLimit    = 60                       // 显式音域 [60,79]（对齐原版高音谱默认）
            guideStrategy.highLimit   = 79                       // 不吃类自带 40–84
            // …（:1248-1250 注释保留）
            guideStrategy.allowColor  = guideLineColorEnabled
```
```swift
// ── 替换后 ──
            // [旧码封存 P1] 四预设填值与写死音域：
            // guideStrategy.direction   = guidePreset.direction
            // guideStrategy.maxDuration = guidePreset.maxDuration
            // guideStrategy.startDegree = "1"
            // guideStrategy.lowLimit    = 60
            // guideStrategy.highLimit   = 79
            guideStrategy.direction   = guideDirection    // [P1] 卡片三参数自由组合
            guideStrategy.maxDuration = guideMaxDuration
            guideStrategy.startDegree = guideStartDegree
            guideStrategy.lowLimit    = guideLow          // [P1] 音域可参数化
            guideStrategy.highLimit   = guideHigh
            // [P1] 骨架色彩三态：关=off；开则按全局宽度出 conservative/full（默认 conservative）
            let guideSkeletonPalette = ColorPaletteMode(rawValue: colorRaw) ?? .conservative
            guideStrategy.colorMode = guideLineColor
                ? (guideSkeletonPalette == .full ? .full : .conservative)
                : .off
```

#### B6. 第二控件 → Settings 按钮（现 :2319-2386，整块替换）

```swift
// ── 现状：if selectedAlgorithmGroup == .guide { 预设 Menu } else { 语法 Menu }（共 68 行）──
                    if selectedAlgorithmGroup == .guide {
                        // …Guide 预设 Menu（:2320-2347）…
                    } else {
                        // …语法 Menu（:2349-2385，含付费锁 :2352/:2361）…
                    } // 第二控件按组切换（Guide 预设 / Basic-Master 语法）
```
```swift
// ── 替换后 ──
                    /* [旧码封存 P1 20261009] 第二下拉整块（Guide 四档预设 Menu / Basic-Master-Learning 语法 Menu，
                       含付费锁判定）；其职能已迁入 Settings 卡片：
                    if selectedAlgorithmGroup == .guide {
                        Menu {
                            ForEach(GuideLinePreset.allCases, id: \.self) { preset in
                                Button { selectedGuidePreset = preset } label: {
                                    HStack {
                                        Text(preset.fullDisplayName)
                                        if preset == selectedGuidePreset { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing:4) {
                                Text(selectedGuidePreset.shortName)
                                    .font(.system(size: isVerySmallScreen ? 12 : 13, weight: .medium))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName:"chevron.down").font(.caption)
                            }
                            .padding(.horizontal,8).padding(.vertical,6)
                            .frame(width: algorithmLabelWidth)
                            .background(Color.gray.opacity(0.12)).cornerRadius(6)
                        }
                        .layoutPriority(0)
                    } else {
                    Menu {
                        ForEach(currentAlgorithmList, id: \.self) { algo in
                            Button {
                                if (selectedAlgorithmGroup == .master || selectedAlgorithmGroup == .learning) && !iapManager.isPurchased {
                                    pendingMasterAlgorithm = algo
                                    showPaywall = true
                                } else {
                                    selectedAlgorithm = algo
                                }
                            } label: {
                                HStack {
                                    Text(algo.rawValue)
                                    if (selectedAlgorithmGroup == .master || selectedAlgorithmGroup == .learning) && !iapManager.isPurchased {
                                        Image(systemName: "lock.fill").font(.caption2)
                                    }
                                    if algo == selectedAlgorithm { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing:4) {
                            Text(selectedAlgorithm.rawValue)
                                .font(.system(size: isVerySmallScreen ? 12 : 13, weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName:"chevron.down").font(.caption)
                        }
                        .padding(.horizontal,8).padding(.vertical,6)
                        .frame(width: algorithmLabelWidth)
                        .background(Color.gray.opacity(0.12)).cornerRadius(6)
                    }
                    .layoutPriority(0)
                    } // 第二控件按组切换
                    */
                    // [P1] 第二控件统一为 Settings 按钮（顶栏控件总数不增；不付费、不 gating）
                    Button {
                        showModeSettings = true
                    } label: {
                        HStack(spacing:5) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: isVerySmallScreen ? 11 : 12, weight: .semibold))
                            Text("Settings")
                                .font(.system(size: isVerySmallScreen ? 12 : 13, weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName:"chevron.down").font(.caption)
                        }
                        .padding(.horizontal,8).padding(.vertical,6)
                        .frame(width: algorithmLabelWidth)
                        .background(Color.gray.opacity(0.12)).cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .layoutPriority(0)
```

#### B7. 新增 sheet（挂在现 paywall sheet 之后，即 :2033 之后插入）

```swift
            // [P1] 随当前模式变化的设置卡片
            .sheet(isPresented: $showModeSettings) {
                ModeSettingsCard(
                    group: selectedAlgorithmGroup,
                    options: currentAlgorithmList,
                    selectedAlgorithm: $selectedAlgorithm,
                    guideDirection: $guideDirection,
                    guideStartDegree: $guideStartDegree,
                    guideMaxDuration: $guideMaxDuration,
                    guideLow: $guideLow,
                    guideHigh: $guideHigh,
                    pendingMasterAlgorithm: $pendingMasterAlgorithm,
                    showPaywall: $showPaywall,
                    iapManager: iapManager
                )
            }
```

---

### C. `Real imPro/Views/BandMixerView.swift`（4 hunk）

#### C1. 封存色彩绑定辅助（现 :66-81）

```swift
// ── 现状 ──
    // ① 主 COLOR 圆点＝线条/骨架色彩：Guide→guideLineColorEnabled；Learning→lstmColorEnabled；Basic/Master→grammarColorEnabled。
    private var lineColorBinding: Binding<Bool> {
        if isGuideGroup { return $guideLineColorEnabled }
        if isLearning { return $lstmColorEnabled }
        return $grammarColorEnabled
    }
    // 主 COLOR 圆点恒可点（Guide 不再依赖 TRANSFORM；grammar/learning 本就恒可点）。
    private var lineColorIsOn: Bool { lineColorBinding.wrappedValue }

    // ② Conserv/Ext 宽度下拉服务的色彩：Guide→加花✧(guideColorEnabled)；Learning→lstmColorEnabled；Basic/Master→grammarColorEnabled。
    private var widthColorBinding: Binding<Bool> {
        if isGuideGroup { return $guideColorEnabled }
        if isLearning { return $lstmColorEnabled }
        return $grammarColorEnabled
    }
    private var widthColorIsOn: Bool { widthColorBinding.wrappedValue }
```
```swift
// ── 替换后（整块注释封存）──
    /* [旧码封存 P1 20261009] 主 COLOR 圆点与宽度下拉的色彩绑定辅助；
       色彩开关已迁入各模式设置卡片，宽度全绑全局 colorModeRaw：
    private var lineColorBinding: Binding<Bool> {
        if isGuideGroup { return $guideLineColorEnabled }
        if isLearning { return $lstmColorEnabled }
        return $grammarColorEnabled
    }
    private var lineColorIsOn: Bool { lineColorBinding.wrappedValue }
    private var widthColorBinding: Binding<Bool> {
        if isGuideGroup { return $guideColorEnabled }
        if isLearning { return $lstmColorEnabled }
        return $grammarColorEnabled
    }
    private var widthColorIsOn: Bool { widthColorBinding.wrappedValue }
    */
```
> 入参 stored properties（guideLineColorEnabled / grammarColorEnabled / lstmColorEnabled）保留：Content View 调用点不动，且无"未使用存储属性"警告。

#### C2. 封存宽度 Menu 可点条件（现 :87-90）

```swift
// ── 现状 ──
    // ④ 宽度下拉是否可点：Guide 需 TRANSFORM 开且 ✧ 开（关 TRANSFORM 即 resident 置灰）；其余只看各自色彩键。
    private var widthMenuInteractive: Bool {
        isGuideGroup ? (embellishInteractive && embellishIsOn) : widthColorIsOn
    }
```
```swift
// ── 替换后 ──
    // [旧码封存 P1] private var widthMenuInteractive: Bool {
    //     isGuideGroup ? (embellishInteractive && embellishIsOn) : widthColorIsOn
    // }
    // [P1] 宽度迁入卡片；Guide 卡宽度可点 = guideLineColorEnabled || (TRANSFORM && ✝)，其余=各自色彩键（见 ModeSettingsCard）
```

#### C3. 封存 colorModeRaw（现 :93-95）

```swift
// ── 现状 ──
    // D4：色彩音池档位（与 ContentView 生成处共用同一持久化键）
    // 注：整流(Rectify)已固定为全拍对齐，不再在调音台显示；逻辑仍保留在 GrammarLickGlue/LightPostProcessor
    @AppStorage("colorModeRaw") private var colorModeRaw: String = ColorPaletteMode.conservative.rawValue
```
```swift
// ── 替换后 ──
    // [旧码封存 P1] @AppStorage("colorModeRaw") private var colorModeRaw: String = ColorPaletteMode.conservative.rawValue
    // [P1] 宽度 Menu 迁入设置卡片；调音台不再持有 colorModeRaw
```

#### C4. 封存主 COLOR 行与宽度 Menu UI（现 :180-204 与 :287-319，两块分别封存）

```swift
// ── 现状①：主 COLOR 圆点行（:180-204）──
                        // [Guide 双色彩 20261002] 主 COLOR 圆点＝骨架/线条色彩（全界面唯一「COLOR」单词）：…
                        HStack(spacing: 4) {
                            Button { … lineColorBinding.wrappedValue.toggle() … } label: {
                                Image(systemName: lineColorIsOn ? "largecircle.fill.circle" : "circle") …
                            }
                            Text("COLOR") …
                            Spacer(minLength: 0)
                        }
                        .frame(height: 14)
```
```swift
// ── 替换后（整块封存）──
                        /* [旧码封存 P1 20261009] 主 COLOR 圆点行；骨架/线条色彩开关已迁入各模式设置卡片：
                        HStack(spacing: 4) {
                            Button {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    lineColorBinding.wrappedValue.toggle()
                                }
                            } label: {
                                Image(systemName: lineColorIsOn ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(lineColorIsOn ? .accentColor : .secondary)
                                    .frame(width: 18, height: 18).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Text("COLOR")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                            Spacer(minLength: 0)
                        }
                        .frame(height: 14)
                        */
```

```swift
// ── 现状②：宽度 Menu（:287-319）──
                        // [Guide 双色彩 20261002] Conserv/Ext 宽度下拉（迁到乐手下方）：…
                        Menu {
                            ForEach(ColorPaletteMode.allCases, id: \.self) { mode in
                                Button { colorModeRaw = mode.rawValue } label: {
                                    Text(mode.label)
                                    if colorModeRaw == mode.rawValue { Image(systemName: "checkmark") }
                                }
                            }
                        } label: { … CONSERV/EXT 胶囊 … }
                        .disabled(!widthMenuInteractive)
                        .opacity(widthMenuInteractive ? 1 : 0.4)
```
```swift
// ── 替换后（整块封存）──
                        /* [旧码封存 P1 20261009] Conserv/Ext 宽度下拉；已迁入各模式设置卡片（全绑 colorModeRaw）：
                        Menu {
                            ForEach(ColorPaletteMode.allCases, id: \.self) { mode in
                                Button { colorModeRaw = mode.rawValue } label: {
                                    Text(mode.label)
                                    if colorModeRaw == mode.rawValue { Image(systemName: "checkmark") }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text((ColorPaletteMode(rawValue: colorModeRaw) ?? .conservative).shortLabel.uppercased())
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundColor(.primary).padding(.horizontal, 8)
                            .frame(maxWidth: .infinity).frame(height: 30)
                            .background(Color.gray.opacity(0.12)).clipShape(Capsule()).contentShape(Capsule())
                        }
                        .disabled(!widthMenuInteractive)
                        .opacity(widthMenuInteractive ? 1 : 0.4)
                        */
```
> TRANSFORM 圆点行（:206-252，含 Guide ✝ :233-250）与乐手 Menu（:256-285）原样保留，一个字符不动。

---

### D. 新建 `Real imPro/Views/ModeSettingsCard.swift`（完整代码）

```swift
//
//  ModeSettingsCard.swift
//  RealimPro
//
//  顶部 Settings 按钮弹出的上下文设置卡片：随当前模式（Guide / Basic / Master / Learning）切换内容。
//  色彩宽度全绑全局 colorModeRaw；本文件只做 UI 与接线，不含任何生成逻辑。
//

import SwiftUI

// MARK: - MIDI 音名（本文件内使用）
func modeSettingsNoteName(of midi: Int) -> String {
    let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    return names[midi % 12] + "\(midi / 12 - 1)"
}

// MARK: - 顶层卡片
struct ModeSettingsCard: View {
    let group: ContentView.ImproAlgorithmGroup
    let options: [ContentView.ImproAlgorithmType]
    @Binding var selectedAlgorithm: ContentView.ImproAlgorithmType
    @Binding var guideDirection: Int
    @Binding var guideStartDegree: String
    @Binding var guideMaxDuration: Int
    @Binding var guideLow: Int
    @Binding var guideHigh: Int
    @Binding var pendingMasterAlgorithm: ContentView.ImproAlgorithmType?
    @Binding var showPaywall: Bool
    @ObservedObject var iapManager: IAPManager
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        switch group {
        case .guide:    return "Guide Settings"
        case .basic:    return "Basic Grammar"
        case .master:   return "Master Grammar"
        case .learning: return "Learning Settings"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch group {
                case .guide:
                    GuideSettingsCard(direction: $guideDirection,
                                      startDegree: $guideStartDegree,
                                      maxDuration: $guideMaxDuration,
                                      low: $guideLow, high: $guideHigh)
                case .basic, .master:
                    GrammarSettingsCard(group: group, options: options,
                                        selectedAlgorithm: $selectedAlgorithm,
                                        pendingMasterAlgorithm: $pendingMasterAlgorithm,
                                        showPaywall: $showPaywall,
                                        iapManager: iapManager)
                case .learning:
                    // [P1 补充 20261009] Model 选择带付费锁（同 Master 卡/旧第二下拉）
                    LearningSettingsCard(selectedAlgorithm: $selectedAlgorithm,
                                         pendingMasterAlgorithm: $pendingMasterAlgorithm,
                                         showPaywall: $showPaywall,
                                         iapManager: iapManager)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Allow Color Tones 行（圆点 + 宽度控件）
struct AllowColorRow: View {
    @Binding var isOn: Bool
    @Binding var widthRaw: String
    let widthInteractive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isOn.toggle() }
            } label: {
                Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(isOn ? .accentColor : .secondary)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text("Allow Color Tones")
                .font(.system(size: 14, weight: .medium))
            Spacer(minLength: 0)
            ColorWidthMenu(raw: $widthRaw, interactive: widthInteractive)
        }
        .frame(height: 34)
    }
}

// MARK: - Conserv / Ext 宽度 Menu
struct ColorWidthMenu: View {
    @Binding var raw: String
    let interactive: Bool

    var body: some View {
        Menu {
            ForEach(ColorPaletteMode.allCases, id: \.self) { mode in
                Button { raw = mode.rawValue } label: {
                    HStack {
                        Text(mode.label)
                        if raw == mode.rawValue { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text((ColorPaletteMode(rawValue: raw) ?? .conservative).shortLabel)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 10).frame(height: 28)
            .background(Color.gray.opacity(0.12)).clipShape(Capsule()).contentShape(Capsule())
        }
        .disabled(!interactive)
        .opacity(interactive ? 1 : 0.4)
    }
}

// MARK: - 通用「标题 + 胶囊 Menu」行
struct LabeledMenuRow: View {
    let title: String
    @Binding var selection: Int
    let options: [(label: String, value: Int)]

    private var currentLabel: String { options.first { $0.value == selection }?.label ?? "" }

    var body: some View {
        HStack {
            Text(title).font(.system(size: 14, weight: .medium))
            Spacer(minLength: 0)
            Menu {
                ForEach(options, id: \.value) { opt in
                    Button { selection = opt.value } label: {
                        HStack {
                            Text(opt.label)
                            if selection == opt.value { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Text(currentLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(Color.gray.opacity(0.12)).clipShape(Capsule())
            }
        }
        .frame(height: 36)
    }
}

// MARK: - Guide 设置卡
struct GuideSettingsCard: View {
    @Binding var direction: Int
    @Binding var startDegree: String
    @Binding var maxDuration: Int
    @Binding var low: Int
    @Binding var high: Int

    @AppStorage("guideColorEnabled") private var embellishColor = false
    @AppStorage("guideLineColorEnabled") private var lineColor = false
    @AppStorage("colorModeRaw") private var widthRaw = ColorPaletteMode.conservative.rawValue
    @AppStorage("transformEnabled") private var transform = false

    // 宽度可点：骨架色彩开 或（TRANSFORM 开且 ✝ 开）
    private var widthInteractive: Bool { lineColor || (transform && embellishColor) }

    var body: some View {
        VStack(spacing: 12) {
            AllowColorRow(isOn: $lineColor, widthRaw: $widthRaw,
                          widthInteractive: widthInteractive)
            LabeledMenuRow(title: "Direction", selection: $direction, options: [
                (label: "No Preference", value: 0),
                (label: "Ascending", value: 1),
                (label: "Descending", value: -1)
            ])
            VStack(alignment: .leading, spacing: 6) {
                Text("Start on Scale Degree")
                    .font(.system(size: 14, weight: .medium))
                Picker("", selection: $startDegree) {
                    ForEach(["1", "3", "5", "7"], id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            LabeledMenuRow(title: "Max Note Duration", selection: $maxDuration, options: [
                (label: "No Preference", value: 0),
                (label: "Whole", value: 480),
                (label: "Half", value: 240),
                (label: "Quarter", value: 120)
            ])
            HStack {
                Text("Range").font(.system(size: 14, weight: .medium))
                Spacer(minLength: 0)
                NavigationLink {
                    RangeKeyboardPage(low: $low, high: $high)
                } label: {
                    HStack(spacing: 4) {
                        Text("\(modeSettingsNoteName(of: low)) – \(modeSettingsNoteName(of: high))")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(Color.gray.opacity(0.12)).clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 36)
        }
        .padding(20)
    }
}

// MARK: - Range 键盘子页
struct RangeKeyboardPage: View {
    @Binding var low: Int
    @Binding var high: Int
    @State private var workingLow: Int?
    @State private var workingHigh: Int?
    @State private var nextIsLow = true
    @State private var invalid = false
    @Environment(\.dismiss) private var dismiss

    private let displayStart = 36   // C2
    private let displayEnd = 96     // C7

    private var instruction: String {
        if invalid { return "Minimum span is one octave. Please reselect." }
        if workingLow == nil { return "Tap the lowest note of your range." }
        return "Now tap the highest note of your range."
    }

    private func isWhite(_ midi: Int) -> Bool {
        [0, 2, 4, 5, 7, 9, 11].contains(midi % 12)
    }

    private func handleTap(_ midi: Int) {
        invalid = false
        if nextIsLow {
            workingLow = midi
            workingHigh = nil
            nextIsLow = false
        } else {
            workingHigh = midi
            nextIsLow = true
            guard let l = workingLow, let h = workingHigh else { return }
            let a = min(l, h), b = max(l, h)
            if b - a < 12 {
                invalid = true
            } else {
                low = a
                high = b
            }
        }
    }

    private func inWorkingRange(_ midi: Int) -> Bool {
        let l = workingLow ?? low
        let h = workingHigh ?? high
        return midi >= l && midi <= h
    }

    var body: some View {
        VStack(spacing: 18) {
            Text(instruction)
                .font(.system(size: 13))
                .foregroundColor(invalid ? .red : .secondary)
                .multilineTextAlignment(.center)
            Text("\(modeSettingsNoteName(of: workingLow ?? low)) – \(modeSettingsNoteName(of: workingHigh ?? high))")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            keyboard
                .frame(height: 190)
            HStack {
                Button {
                    workingLow = 60
                    workingHigh = 79
                    invalid = false
                    low = 60
                    high = 79
                } label: {
                    Text("Reset").fontWeight(.medium)
                }
                Spacer()
                Button {
                    guard let l = workingLow, let h = workingHigh, !invalid else { return }
                    low = min(l, h)
                    high = max(l, h)
                    dismiss()
                } label: {
                    Text("Done").fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .disabled(workingLow == nil || workingHigh == nil || invalid)
            }
        }
        .padding(20)
        .navigationTitle("Choose Range")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var keyboard: some View {
        GeometryReader { geo in
            let whites = (displayStart...displayEnd).filter { isWhite($0) }
            let whiteWidth = geo.size.width / CGFloat(whites.count)
            ZStack(alignment: .topLeading) {
                HStack(spacing: 1) {
                    ForEach(whites, id: \.self) { midi in
                        keyButton(midi, isBlack: false)
                            .frame(width: whiteWidth, height: geo.size.height)
                    }
                }
                ForEach((displayStart...displayEnd).filter { !isWhite($0) }, id: \.self) { midi in
                    let preceding = CGFloat(whites.filter { $0 < midi }.count)
                    keyButton(midi, isBlack: true)
                        .frame(width: whiteWidth * 0.62, height: geo.size.height * 0.62)
                        .offset(x: preceding * whiteWidth + whiteWidth - whiteWidth * 0.31)
                }
            }
        }
    }

    private func keyButton(_ midi: Int, isBlack: Bool) -> some View {
        Button {
            handleTap(midi)
        } label: {
            Rectangle()
                .fill(inWorkingRange(midi)
                      ? Color.accentColor.opacity(isBlack ? 0.85 : 0.35)
                      : (isBlack ? Color.black : Color.white))
                .border(Color.gray.opacity(0.3), width: 0.5)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Basic / Master Grammar 设置卡
struct GrammarSettingsCard: View {
    let group: ContentView.ImproAlgorithmGroup
    let options: [ContentView.ImproAlgorithmType]
    @Binding var selectedAlgorithm: ContentView.ImproAlgorithmType
    @Binding var pendingMasterAlgorithm: ContentView.ImproAlgorithmType?
    @Binding var showPaywall: Bool
    @ObservedObject var iapManager: IAPManager

    @AppStorage("grammarColorEnabled") private var grammarColor = false
    @AppStorage("colorModeRaw") private var widthRaw = ColorPaletteMode.conservative.rawValue

    private var isMasterLocked: Bool { group == .master && !iapManager.isPurchased }

    var body: some View {
        VStack(spacing: 16) {
            AllowColorRow(isOn: $grammarColor, widthRaw: $widthRaw,
                          widthInteractive: grammarColor)
            HStack {
                Text("Grammar").font(.system(size: 14, weight: .medium))
                Spacer(minLength: 0)
                Menu {
                    ForEach(options, id: \.self) { algo in
                        Button {
                            if group == .master && !iapManager.isPurchased {
                                pendingMasterAlgorithm = algo
                                showPaywall = true
                            } else {
                                selectedAlgorithm = algo
                            }
                        } label: {
                            HStack {
                                Text(algo.rawValue)
                                if group == .master && !iapManager.isPurchased {
                                    Image(systemName: "lock.fill").font(.caption2)
                                }
                                if algo == selectedAlgorithm {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedAlgorithm.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(Color.gray.opacity(0.12)).clipShape(Capsule())
                }
            }
            .frame(height: 36)
        }
        .padding(20)
    }
}

// MARK: - Learning 设置卡
struct LearningSettingsCard: View {
    @Binding var selectedAlgorithm: ContentView.ImproAlgorithmType
    // [P1 补充 20261009] Model 付费锁：与 GrammarSettingsCard 同构（未购点选→pending+paywall，选项旁 lock.fill）
    @Binding var pendingMasterAlgorithm: ContentView.ImproAlgorithmType?
    @Binding var showPaywall: Bool
    @ObservedObject var iapManager: IAPManager

    @AppStorage("lstmColorEnabled") private var lstmColor = false
    @AppStorage("colorModeRaw") private var widthRaw = ColorPaletteMode.conservative.rawValue

    // Learning 仅两个模型，顺序承接旧第二下拉
    private let modelOptions: [ContentView.ImproAlgorithmType] = [.combination, .greatMoments]

    var body: some View {
        VStack(spacing: 20) {
            AllowColorRow(isOn: $lstmColor, widthRaw: $widthRaw,
                          widthInteractive: lstmColor)
            HStack {
                Text("Model")
                    .font(.system(size: 14, weight: .medium))
                Spacer(minLength: 0)
                Menu {
                    ForEach(modelOptions, id: \.self) { algo in
                        Button {
                            if !iapManager.isPurchased {
                                // 未购：不切换，挂 pending 并弹付费墙（与 Master 卡/旧下拉一致）
                                pendingMasterAlgorithm = algo
                                showPaywall = true
                            } else {
                                selectedAlgorithm = algo
                            }
                        } label: {
                            HStack {
                                Text(algo.rawValue)
                                if !iapManager.isPurchased {
                                    Image(systemName: "lock.fill").font(.caption2)
                                }
                                if algo == selectedAlgorithm && iapManager.isPurchased {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedAlgorithm.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(Color.gray.opacity(0.12)).clipShape(Capsule())
                }
            }
            .frame(height: 36)
        }
        .padding(20)
    }
}
```

---

## 5. 一键回退

落地时创建脚本 `scripts/rollback_phase1.sh`（工程根执行；内容如下）：

```bash
#!/bin/bash
# Real imPro P1（设置卡片化）一键回退：恢复 3 个备份文件 + 删除新卡片文件
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

cp ".backup/GuideLineGenerator.swift.P1-settingscard-backup" "Real imPro/GuideTone/GuideLineGenerator.swift"
cp ".backup/ContentView.swift.P1-settingscard-backup"        "Real imPro/Views/ContentView.swift"
cp ".backup/BandMixerView.swift.P1-settingscard-backup"      "Real imPro/Views/BandMixerView.swift"
rm -f "Real imPro/Views/ModeSettingsCard.swift"

echo "P1 已回退。请在 Xcode 重新 Build 确认。"
```

第二保险：工程根有 git，可 `git status` 查看改动、`git checkout -- "Real imPro/..."` 单文件恢复（新文件 `git clean -f` 或手动删）。

注：回退后 `guideLowMidi` / `guideHighMidi` 两个 UserDefaults 键可能仍留有自定义值（旧代码不读它们、无任何影响）；如需彻底清出厂状态，可在 iOS「设置 → 通用 → 传输或还原」或删除 App 重装，回退脚本不主动删 UserDefaults。

---

## 6. 落地后回归门（逐项实测、数值截图回报）

**数值门：**
- Guide：默认设置（=旧 Smooth）音符数 **18,470 不变**；`off` 态逐音 = 旧 false、`full` = 旧 true（探针已证，落地后在 App 内复核）；
- raw grammar **30/30 OK、BAD=0**、FNV 稳定；Transform 双端差异 **0**；Learning 两模型 teacher-forcing + 固定种子自由生成 **1536/1536**；
- 包内 **26 个 .tsv、合计 11,235,463 B** 不变；两 .rnn 各 **9,136,016 B**；
- 时值守恒 **0 违例**；音域/空音检查通过；付费墙行为正确——门①:1137 / 门④:2576 不动，卡片内：Master Grammar 选择锁（原②③）、**Learning Model 选择锁（新增，未购点选弹墙、lock.fill，购买回调组无关、买完自动选中）**；购买后解锁、解锁回调正常。

**UI 门：**
- 宽度随色彩开关联动置灰；三卡宽度全局同步；Extended 入口仍在（卡片宽度 Menu）；
- iPad mini / 11 / 13 × 横竖共 **6 组尺寸**：卡片不压五线谱、不截断、不遮挡 # 分析按钮；右栏恒宽 **110**；**mini 竖屏先出截图**（Guide 卡 5 行 + Range 键盘子页为最高内容）。

**真机/模拟器用户路径：**
1. 无旋律谱（iReal/Stylebook）未点生成即正常显示，不空白；
2. 有旋律谱正常；
3. 选曲、转调、生成 solo、Original⇄Solo 切换后谱面与卡片正确刷新、不残留上一首；
4. Range 选最低/最高生效（含小于八度被拒）；Reset 写回 60–79 并同步持久化键；
5. 各色彩开关点亮/关闭结果正确；
6. 改动设置不触发重新随机（下次点生成才生效）；
7. **持久化（新增）**：改 Range（如 55–80）后杀 App 重开 → Range 记忆生效；Direction / Start Degree / Max Duration 回出厂默认（No Preference / 1 / Half）。

**编译：** Xcode GUI **Build Succeeded、0 error**；命令行若偶发 AssetCatalogAgent / 宏插件 spawn 报错属环境怪象，以 GUI + 真机为准并在回报中说明。

---

## 7. 待批准事项

请书面回复：
1. 上述 3 改 + 1 新建的全部 hunk 是否照此落地；
2. 若有措辞/布局调整意见，我改文档后再请你确认，不直接动生产。

批准后执行顺序：整文件备份（记录 SHA1）→ 逐 hunk 应用（旧码封存）→ ModeSettingsCard.swift 落盘 → Xcode GUI Build → 数值回归门 → 6 组尺寸 + 真机路径 → 回报全部数值与截图。阶段一通过后，再另行报批 Basic/Master → Grammar 合并。
