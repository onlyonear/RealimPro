# P2 逐 hunk diff：Basic + Master 合并为 Grammar（只读勘察 + 精确 diff，批准前生产零改动）

- 文档日期：2026-10-09
- 工程：RealimPro（`/Users/onlyonear/Desktop/Improlyze`），部署目标 iOS 16.6
- 状态：**待书面批准**。本文档不含任何已落地改动；批准口令示例：「批准 P2 按此 diff 落地」。
- 目标：第一下拉由 Guide / Basic / Master / Learning 收敛为 **Guide / Grammar / Learning**；付费判定从「组 = Master」迁移为「选中的具体语法 ∈ 9 位大师付费集合」；Grammar 设置卡合并为单一语法下拉。
- 红线：纯 UI / 信息架构与接线；不动算法、引擎、整流、语法/.tsv/.rnn 资源；不翻默认、不新增付费点/顶栏按钮；用户可见处无「Java」。

---

## 第一部分　只读勘察结论（re-grounding 于 P1.5a 后生产代码）

### 1.1 全工程影响面（grep `ImproAlgorithmGroup / .basic / .master / currentAlgorithmList`，9 个文件命中）

| 文件 | 命中性质 | P2 处置 |
|---|---|---|
| `Real imPro/Views/ContentView.swift` | 枚举定义、默认组、列表、2 处活跃付费门、组菜单、worker 分流 | **改（9 个编辑位）** |
| `Real imPro/Views/ModeSettingsCard.swift` | 两个穷尽 switch、Basic/Master 卡、卡内付费锁 | **改（3 hunk）** |
| `Real imPro/Views/BandMixerView.swift` | 只用 `group == .guide / .learning`，其余（含 Basic/Master）走隐式 else 绑 grammar 键 | **零改动**（见 §1.4） |
| `Grammar/GrammarStrategy.swift`、`ThemeWeaver/ThemeWeaverStrategy.swift` | 仅 `grammar.masterParameters`（语法参数字典属性名，与组枚举无关） | 不动 |
| `MidiPlayer/ChordPatternExtractor.swift`、`AccompanimentGenerator.swift`、`JazzMidiPlayer.swift` | `basicSwing()` / `masterGain`，无关 | 不动 |
| `Views/IAPManager.swift` | `productID = "com.realimpro.master.lifetime"` | **不动**（App Store Connect 产品 ID，改名即断购） |
| `Views/PaywallView.swift` | 标题文案 "Unlock Master Algorithms" | **不动**（售卖内容仍是大师文法，文案仍准确；属方案外，不夹带） |

### 1.2 组判定点全量清单（ContentView，行号为 P1.5a 后现读）

| # | 位置 | 现状 | P2 处置 |
|---|---|---|---|
| 1 | `ContentView.swift:6-13` | 枚举 4 case：guide/basic/master/learning | basic/master → 单 case `grammar="Grammar"`（H1） |
| 2 | `:735` | `@State selectedAlgorithmGroup = .basic` | 默认改 `.grammar`（H3） |
| 3 | `:779-802` | `currentAlgorithmList` 穷尽 switch，basic=3 基础、master=9 大师排序 | 合并为 grammar = 3 基础 + 排序后 9 大师（H4） |
| 4 | `:1151-1155` | **活跃付费门①**（管线最底层保险）：`.master || .learning` | 改判统一谓词（H5+ H6） |
| 5 | `:1204` | worker 形参默认 `group: … = .basic` | 默认值改 `.grammar`（H7）；分流逻辑 `if isGuide / else if .learning / else 语法`**不动**（.grammar 自然落 else，与旧 basic/master 同路径） |
| 6 | `:1206,1263,1286,1348,1373,1526,1750` | 只用 isGuide / `group == .learning`，语法组走 else | 不动 |
| 7 | `:2068-2077` | 购买成功回调：组无关，pending 什么就选中什么 | 不动（大师文法在新组下同样生效） |
| 8 | `:2080-2092` | ModeSettingsCard 传 group/options | 不动（新枚举/新列表自动生效） |
| 9 | `:2340` | 组菜单 `ForEach([.guide,.basic,.master,.learning])` | 改 `[.guide,.grammar,.learning]`（H8） |
| 10 | `:2353-2360` | 切组时算法选中回退逻辑（不属于目标组才回第一项） | 改为：切入 Grammar 无条件回第一个免费基础；切入 Learning 不含则回 Combination（H9） |
| 11 | `:2420,:2429` | 付费判定，但整段位于 P1 封存块 `/* … */`（`:2379-2455`）内，**不参与编译的死码** | 不动（封存码内的 .master 引用不影响编译） |
| 12 | `:2666-2670` | **活跃付费门②**（生成按钮） | 改判统一谓词（H10） |
| 13 | `:4301-4317` | `effectiveDisplayPalette` 用 `switch … default:`，default 即语法组 | 不动（.grammar 自动落 default；非穷尽 switch，编译无误） |

### 1.3 付费墙现状（「4 处」按 P1.5a 后实际活跃口径核对）

- **活跃门①**：`ContentView.swift:1151`（runJazzGenerationPipeline 入口，最底层保险）。
- **活跃门②**：`ContentView.swift:2666`（wand.and.stars 生成按钮）。
- **活跃锁③**：`ModeSettingsCard.swift:378/387`（Master 卡语法 Menu：未购点选弹墙 + 行旁 lock.fill）。
- **活跃锁④**：`ModeSettingsCard.swift:441/451`（Learning 卡 Model Menu，P1 补的同构锁，本阶段保持原样）。
- 旧第二下拉内两处判定（`:2420/:2429`）在 P1 封存块内，是死码，不计。
- 购买回调（`:2069-2075`）组无关：买完 `selectedAlgorithm = pending`，对 Grammar 组大师行天然成立，**不改**。
- DEBUG 出厂 `isPurchased=true`（`IAPManager.swift:17-19`），无调试开关；未购态验收方式见 §4.3。

### 1.4 BandMixerView 零改动论证（满足工单第 4 条）

- 该文件对组只有两个派生量：`isGuideGroup = group == .guide`（:63）、`isLearning = group == .learning`（:64）。
- 其余全部按「非 Guide 且非 Learning = 语法链路」走隐式分支：✝ 可用 `!isLearning`（:89）、TRANSFORM 可用 `!isLearning`（:98）、胶囊 `isLearning || …`（:331-332）。
- 旧 .basic/.master 合并为 .grammar 后，Grammar 仍是「非 Guide、非 Learning」，所有分支行为不变。
- 结论：**P2 对 BandMixerView 零 hunk**。文件内注释文字里的 "Basic/Master" 字样为非用户可见的历史注释，按无夹带原则不动。

### 1.5 ModeSettingsCard 穷尽 switch 清单（不改会编译失败）

- `title`（:32-39）：basic/master 两 case → 合并为 `.grammar → "Grammar Settings"`（M1）。
- `body`（:44-62）：`case .basic, .master` → `case .grammar`，GrammarSettingsCard 去掉 group 形参（M2）。
- `GrammarSettingsCard`（:355-411）：锁判据由 `group == .master` 改为逐行 `algo.isPaidGrammar`（M3）。
- LearningSettingsCard 不动。

### 1.6 默认输出不变论证（数值门等价的根据）

- 出厂状态：旧 = 组 `.basic` + 选中 `.chordExercise`；新 = 组 `.grammar` + 选中 `.chordExercise`（`:736` 本就默认 `.chordExercise`）。
- worker 内语法链路是 `if isGuide {} else if group == .learning {} else { 语法 }`；旧 .basic 与新 .grammar 都走同一 else、同一 `getStrategyInstance()`、同一 grammarWidthRaw/grammarColorEnabled 接线 → **默认生成逐音路径完全不变**。
- Guide、Learning、Transform、资源文件均不在本次改动路径上。

### 1.7 一个需你知晓的行为点（已按你工单原话实现，可否决）

工单要求「切到 Grammar 默认选中第一个免费基础语法」。H9 实现为**每次切入 Grammar 都无条件回到 Chord+App**——包括已购用户选了某大师后 Guide⇄Grammar 往返也会回到 Chord+App。若你希望「仅当当前算法不在 Grammar 列表、或未购时落在付费行才回退，已购则保留大师选择」，请在批准时注明，我改 H9 判定；否则按无条件回退落地。

---

## 第二部分　备份计划（含当前 SHA1，即 P1.5a 后值）

落地第一步执行（只备份、不改）：

```bash
cd "/Users/onlyonear/Desktop/Improlyze"
cp "Real imPro/Views/ContentView.swift"     ".backup/ContentView.swift.P2-grammar-merge-backup"
cp "Real imPro/Views/ModeSettingsCard.swift" ".backup/ModeSettingsCard.swift.P2-grammar-merge-backup"
shasum -a 1 .backup/ContentView.swift.P2-grammar-merge-backup .backup/ModeSettingsCard.swift.P2-grammar-merge-backup
```

备份完成后**预期 SHA1 必须与下列当前值逐一核对一致**，不一致立即停止报我：

| 文件 | 当前（P1.5a 后）SHA1 |
|---|---|
| `Real imPro/Views/ContentView.swift` | `4514c020efdc7a6fd81544505a427e8a90d4dd2d` |
| `Real imPro/Views/ModeSettingsCard.swift` | `60677c9e62d016086b5263824ee350637d0bbede` |

回退脚本（落地时新建，已含在本方案内，不触碰其他文件）：`scripts/rollback_phase2.sh`

```bash
#!/bin/bash
# P2 一键回退：撤销 Basic/Master→Grammar 合并，恢复 P1.5a 后状态
set -e
ROOT="/Users/onlyonear/Desktop/Improlyze"
cd "$ROOT"
cp ".backup/ContentView.swift.P2-grammar-merge-backup"     "Real imPro/Views/ContentView.swift"
cp ".backup/ModeSettingsCard.swift.P2-grammar-merge-backup" "Real imPro/Views/ModeSettingsCard.swift"
echo "P2 已回退（恢复到 P1.5a），请在 Xcode GUI 重新 Build"
```

---

## 第三部分　逐 hunk 精确 diff（2 文件，12 个编辑位）

> 体例：每 hunk 给文件:行、旧码（整段原位封存为中文注释，不删除）、新码。除下列 hunk 外不改任何字符。

### 文件 A：`Real imPro/Views/ContentView.swift`（9 个编辑位）

#### H1　枚举收敛（:6-13）

旧码（原位封存）：

```swift
    enum ImproAlgorithmGroup: String, Equatable {
        case guide = "Guide"
        case basic = "Basic"
        case master = "Master"
        case learning = "Learning"   // [LSTM P2] 第4组：神经网络，付费（与 Master 同档）
```

新码：

```swift
    enum ImproAlgorithmGroup: String, Equatable {
        case guide = "Guide"
        case grammar = "Grammar"   // [P2 20261009] 原 basic/master 两组合并为 Grammar
        case learning = "Learning"   // [LSTM] 第3组：神经网络，付费
        // [旧码封存 P2 20261009] 合并前的两个独立组：
        // case basic = "Basic"
        // case master = "Master"
```

（其后原 `.melody` 下线注释保留不动。）

#### H2　新增付费语法集合与判定（插在 `grammarFileName` 计算属性闭合 `}` 之后、枚举闭合 `}` 之前，现 :99-100 之间）

新增：

```swift

        // [P2] 付费大师文法集合（9 位）：合并后付费判定从「组 = Master」改为「具体语法属于本集合」。
        //   3 个免费基础语法（chordExercise / colorTone / Lick）与两个 LSTM 模型不在本集合（Learning 整组另判）。
        static let paidGrammarTypes: Set<ImproAlgorithmType> = [
            .LeeMorgan, .charlieParker, .billEvans, .joePass,
            .cannonballAdderley, .chetBaker, .johnColtrane, .milesDavis, .redGarland
        ]
        /// 是否为付费大师文法（Grammar 合并组逐行加锁 / 付费墙统一判据）
        var isPaidGrammar: Bool { Self.paidGrammarTypes.contains(self) }
```

#### H3　默认组（:735）

旧码封存、新码：

```swift
    // [旧码封存 P2] @State private var selectedAlgorithmGroup: ImproAlgorithmGroup = .basic
    @State private var selectedAlgorithmGroup: ImproAlgorithmGroup = .grammar   // [P2] 默认 Grammar；:736 selectedAlgorithm 默认 .chordExercise 即第一个免费基础语法
```

#### H4　currentAlgorithmList 合并（:779-802）

旧码整段封存（注释），新码：

```swift
    /// 根据当前分组，动态返回下拉算法列表
    private var currentAlgorithmList: [ImproAlgorithmType] {
        switch selectedAlgorithmGroup {
        case .guide:
            // Guide 组无语法列表（Guide 卡用线条参数）
            return []
        case .grammar:
            // [P2] Grammar 合并组：3 个免费基础语法在前，9 位大师在后；
            //   大师排序沿用原 Master 组规则（显示名长度由短到长，同长按字母序）。
            let basics: [ImproAlgorithmType] = [.chordExercise, .colorTone, .Lick]
            let masters: [ImproAlgorithmType] = [.LeeMorgan, .charlieParker, .billEvans, .joePass,
                                                 .johnColtrane, .milesDavis, .cannonballAdderley,
                                                 .chetBaker, .redGarland]
            let sortedMasters = masters.sorted {
                let len0 = $0.rawValue.count, len1 = $1.rawValue.count
                if len0 != len1 { return len0 < len1 }
                return $0.rawValue < $1.rawValue
            }
            return basics + sortedMasters
        case .learning:
            // Learning 组仅两个 LSTM 模型
            return [.combination, .greatMoments]
        }
        // [旧码封存 P2] 合并前的两个独立分支：
        // case .basic:  return [.chordExercise, .colorTone, .Lick]
        // case .master: return 9 大师按显示名长度+字母序排序（现并入 .grammar）
    }

    /// [P2] 当前选择是否需要付费（统一判据，供生成按钮 / 管线两道门使用）：
    ///   Grammar 组且选中 9 位付费大师文法之一 → true；Learning 组 → true；Guide / 3 基础语法 → false。
    private var currentSelectionRequiresPurchase: Bool {
        switch selectedAlgorithmGroup {
        case .learning: return true
        case .grammar:  return selectedAlgorithm.isPaidGrammar
        case .guide:    return false
        }
    }
```

#### H5　活跃付费门①——管线入口（:1150-1151）

旧码：

```swift
        // 最底层保险：任何路径调用 Master 算法都必须先购买
        if (selectedAlgorithmGroup == .master || selectedAlgorithmGroup == .learning) && !iapManager.isPurchased {
```

新码：

```swift
        // [P2] 最底层保险：Grammar 下选中付费大师文法、或 Learning 组，未购一律拦截
        // [旧码封存 P2] if (selectedAlgorithmGroup == .master || selectedAlgorithmGroup == .learning) && !iapManager.isPurchased {
        if currentSelectionRequiresPurchase && !iapManager.isPurchased {
```

（门内 `pendingMasterAlgorithm = selectedAlgorithm; showPaywall = true; return` 三行不动。）

#### H6　worker 形参默认组（:1204）

签名中 `group: ImproAlgorithmGroup = .basic` 改为：

```swift
    // [旧码封存 P2] 形参默认 group: ImproAlgorithmGroup = .basic
    nonisolated private func generateMeasuresWorker(..., group: ImproAlgorithmGroup = .grammar, ... )
```

（仅改这一处默认值；函数体 if guide / else if .learning / else 语法 的分流不动。）

#### H7　组菜单数据源（:2340）

旧码封存、新码：

```swift
                        // [旧码封存 P2] ForEach([ImproAlgorithmGroup.guide, .basic, .master, .learning], id: \.self) { grp in
                        ForEach([ImproAlgorithmGroup.guide, .grammar, .learning], id: \.self) { grp in
```

#### H8　切组算法选中回退（:2353-2360）

旧码整段封存：

```swift
                                // 仅当当前选中算法不属于目标组时才回退到该组第一项（保留用户在 Master/Basic 的已选）；
                                // guide 无语法列表，不回退
                                if grp != .guide {
                                    let targetList = currentAlgorithmList
                                    if !targetList.contains(selectedAlgorithm) {
                                        selectedAlgorithm = targetList.first ?? .chordExercise
                                    }
                                }
```

新码：

```swift
                                // [P2] 语法选择随组复位：
                                //   切入 Grammar 一律回到第一个免费基础语法（Chord+App），保证不落在付费大师行；
                                //   切入 Learning 时若当前不在两个模型之中则回 Combination；Guide 无列表不处理。
                                // [旧码封存 P2] 旧「仅当不属于目标组才回退第一项（保留 Master/Basic 已选）」逻辑见文档封存段。
                                if grp == .grammar {
                                    selectedAlgorithm = currentAlgorithmList.first ?? .chordExercise
                                } else if grp == .learning {
                                    if !currentAlgorithmList.contains(selectedAlgorithm) {
                                        selectedAlgorithm = .combination
                                    }
                                }
```

（P1.5a 的 Transform 复位 4 行、方案21 的三个标记复位均在其上方，不动。）

#### H9　活跃付费门②——生成按钮（:2666）

旧码封存、新码：

```swift
                // [旧码封存 P2] if (selectedAlgorithmGroup == .master || selectedAlgorithmGroup == .learning) && !iapManager.isPurchased {
                if currentSelectionRequiresPurchase && !iapManager.isPurchased {
```

（门体 `pendingMasterAlgorithm = selectedAlgorithm; showPaywall = true; return` 不动。）

> 以上 ContentView 共 **9 个编辑位**（H1-H9，其中 H4 含「列表重写」与「新增统一付费谓词」两段）；ModeSettingsCard 共 **3 个编辑位**（M1-M3）。合计 **12 个编辑位**，落地时逐位应用、逐位封存。

### 文件 B：`Real imPro/Views/ModeSettingsCard.swift`（3 hunk）

#### M1　标题 switch（:32-39）

旧码封存、新码：

```swift
    private var title: String {
        switch group {
        case .guide:    return "Guide Settings"
        case .grammar:  return "Grammar Settings"   // [P2] 原 Basic Grammar / Master Grammar 两卡合并
        case .learning: return "Learning Settings"
        // [旧码封存 P2] case .basic:  return "Basic Grammar"
        // [旧码封存 P2] case .master: return "Master Grammar"
        }
    }
```

#### M2　body switch（:44-62）

旧码中 `case .basic, .master: GrammarSettingsCard(group: group, options: options, …)` 整段封存，新码：

```swift
                switch group {
                case .guide:
                    GuideSettingsCard(direction: $guideDirection,
                                      startDegree: $guideStartDegree,
                                      maxDuration: $guideMaxDuration,
                                      low: $guideLow, high: $guideHigh)
                case .grammar:
                    // [P2] 单一 Grammar 卡：3 基础 + 9 大师同一下拉，逐行按 isPaidGrammar 加锁
                    GrammarSettingsCard(options: options,
                                        selectedAlgorithm: $selectedAlgorithm,
                                        pendingMasterAlgorithm: $pendingMasterAlgorithm,
                                        showPaywall: $showPaywall,
                                        iapManager: iapManager)
                case .learning:
                    // Model 选择带付费锁（同 Grammar 付费行/旧第二下拉）
                    LearningSettingsCard(selectedAlgorithm: $selectedAlgorithm,
                                         pendingMasterAlgorithm: $pendingMasterAlgorithm,
                                         showPaywall: $showPaywall,
                                         iapManager: iapManager)
                }
                // [旧码封存 P2] case .basic, .master: GrammarSettingsCard(group: group, options: options, …)
```

#### M3　GrammarSettingsCard 去 group 化、逐行付费锁（:354-411）

- MARK 注释（:354）封存更新：

```swift
// MARK: - Grammar 设置卡（P2 合并 Basic/Master；3 基础免费 + 9 大师付费）
// [旧码封存 P2] // MARK: - Basic / Master Grammar 设置卡
```

- 结构体字段（:356）删除 group 形参（封存）：

```swift
struct GrammarSettingsCard: View {
    // [旧码封存 P2] let group: ContentView.ImproAlgorithmGroup
    let options: [ContentView.ImproAlgorithmType]
    @Binding var selectedAlgorithm: ContentView.ImproAlgorithmType
    @Binding var pendingMasterAlgorithm: ContentView.ImproAlgorithmType?
    @Binding var showPaywall: Bool
    @ObservedObject var iapManager: IAPManager
```

- Menu 按钮动作（:377-383）旧码封存、新码：

```swift
                        Button {
                            // [旧码封存 P2] if group == .master && !iapManager.isPurchased {
                            if algo.isPaidGrammar && !iapManager.isPurchased {
                                pendingMasterAlgorithm = algo
                                showPaywall = true
                            } else {
                                selectedAlgorithm = algo
                            }
                        } label: {
```

- 行旁锁图标（:387）旧码封存、新码：

```swift
                                // [旧码封存 P2] if group == .master && !iapManager.isPurchased {
                                if algo.isPaidGrammar && !iapManager.isPurchased {
                                    Image(systemName: "lock.fill").font(.caption2)
                                }
```

- 卡内 Allow Color Tones 行（grammarColorEnabled + grammarWidthRaw）、行标题 "Grammar"、checkmark 逻辑均不动。

### 不改动清单（无夹带声明）

- BandMixerView.swift：**0 hunk**（§1.4 论证）。
- ContentView 中 worker 函数体分流、effectiveDisplayPalette、购买回调、ModeSettingsCard 调用点、P1/P1.5/P1.5a 全部既有逻辑：0 改动。
- ModeSettingsCard 中 GuideSettingsCard / RangeKeyboardPage / LearningSettingsCard / AllowColorRow / ColorWidthMenu：0 改动。
- PaywallView 文案、IAPManager productID、全部算法/引擎/整流/资源文件：0 改动。
- 封存块（:2379-2455）内的死码引用保持原样，不整理。
- 不新增任何文件（同步根无新增 .swift）；不新增付费点、顶栏控件；不翻任何默认（出厂组 Grammar+Chord+App 与旧 Basic+Chord+App 等价；各色彩/宽度键默认值不变）。

---

## 第四部分　落地后回归门清单

### 4.1 数值门（默认输出必须与 P1.5a 逐音一致；/tmp 探针用落地源码重编）

1. Guide：b29 5,102 + matrix 13,368 = **18,470 音符，0 MISMATCH**。
2. Transform 固定输入引擎门：**OK=30 / BAD=0**。
3. raw grammar 端到端口径同 P1.5（固定输入引擎 30/30；xfgate 若仍 28/2 为无种子随机，非回归）。
4. Learning 四项：Combination teacher **1536/1536**（maxDiff 量级 ≤1e-6）、Combination free **1536/1536**、GM teacher **1536/1536**、GM free **1536/1536**。
5. 时值守恒：60 项 **violations=0，totalSlots=15,360**。
6. 资源指纹：**26 个 .tsv = 11,235,463 B**；两 .rnn 各 **9,136,016 B**。
7. Xcode 27.0 GUI 真机 Build **Succeeded、0 error**（模拟器 AssetCatalogAgent 故障为已知环境问题，以 GUI+真机为准并说明）。

### 4.2 P2 新增行为门（真机/模拟器人工 + 走查）

1. 第一下拉只有 **Guide / Grammar / Learning** 三项，无 Basic/Master 残留；右栏恒宽 110、不压五线谱与 # 分析按钮。
2. Grammar 卡 Grammar 下拉顺序 = **Chord+App、Chord+Col、Great Lick**（无锁）+ 9 大师（沿用原显示名长度/字母序），未购时 9 行逐行带 **lock.fill**。
3. 未购点大师行：弹付费墙、选中项不变化；购买回调完成后自动选中该大师（DEBUG 默认已购，未购态验证方式见 §4.3）。
4. 未购时两道生成门都拦住大师生成（按钮门 :2666、管线门 :1151）；3 个基础语法与 Guide 正常生成；Learning 门行为不变。
5. 任意组切到 Grammar：选中项回到 **Chord+App**（含 Guide⇄Grammar 往返；若你在批准时改为保留已购大师，则按改后口径验）。
6. Grammar 下 TRANSFORM/✝/调音台 Conserv-Ext 胶囊、卡内色彩与宽度终审逻辑与合并前一致（P1.5 分层矩阵重测一遍：✝ 关 spell-only、✝ 开按胶囊宽度、卡宽只管裸语法）。
7. Learning 下 TRANSFORM 行整行置灰、胶囊常驻置灰（P1.5a）；Model 锁仍正常。
8. 杀 App 重开：组 @State 回到出厂 Grammar + Chord+App（与旧 Basic + Chord+App 同样为 @State 不持久化）；Range/宽度等 @AppStorage 记忆不受影响。

### 4.3 未购态验证说明

DEBUG 出厂 `isPurchased=true` 且无开关。锁/付费墙的未购行为建议二选一（请批准时指定，默认走 a）：
- a. 以代码走查 + 统一谓词 `currentSelectionRequiresPurchase` 的单点逻辑核对为准（4 处锁/门全部收敛到同一判据，分支可穷举）；
- b. 落地后临时把 `IAPManager.swift:18` 改为 `isPurchased = false` 出一版真机验证包，验完立即用备份还原该行再出正式包（该行改动不进入 hunk、不留存生产）。

### 4.4 尺寸与真机路径

- 6 组 iPad 尺寸（mini / 11 / 13 × 横竖）：mini 竖屏先截图；环境故障期（Device Hub/AssetCatalogAgent）由你真机验收，覆盖差异如实标注；Grammar 卡下拉 12 行在 mini 竖屏不截断、不遮挡。
- 真机路径照旧：无旋律谱不空白；选曲/转调/生成/Original⇄Solo 刷新不残留；Range 小于八度被拒与杀 App 记忆；改设置不触发重新随机。

---

## 第五部分　执行顺序（批准后）

1. 备份两文件并核对 SHA1（§第二部分）→ 建 `scripts/rollback_phase2.sh` 并 chmod +x。
2. 旧码中文原位封存 → 按 H1-H9、M1-M3 逐位应用。
3. 全工程复扫 `.basic` / `.master` 活跃引用应为 0（封存注释、masterParameters/productID 等无关项除外）。
4. Xcode GUI 真机 Build 0 error → 装 iPad mini。
5. 重跑数值探针（§4.1）→ 真机行为门（§4.2/4.4）→ 数值与截图回报。
6. 产出 P2 落地报告；P2 关闭后本工单全部结束。

**当前生产零改动，等待书面批准。**
