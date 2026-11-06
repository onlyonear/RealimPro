# C3 — ASC 多语言元数据待补清单 ＋ 隐私/发布工程核查结果

## 1. App Store Connect 多语言元数据待补清单

> 工程 `knownRegions=(en, Base)`，**仅英文**。故 ASC 至少需补「英文(美国)」一套；若要上架简中区，需先在工程补 zh-Hans.lproj（当前完全缺失）。
> 下表为首发需在 ASC 逐语言填写项。

| ASC 字段 | 英文(English, U.S.) | 简体中文(zh-Hans) | 备注 |
|---|---|---|---|
| 名称(Name, ≤30) | 待拟，例：`Real imPro — Jazz Solo Generator` | 暂不需要（当前不发简中） | 主屏幕名由 `CFBundleDisplayName=RealimPro`(pbxproj:281) 控制；ASC 名称可与之不同。注意「RealimPro」无空格，建议确认主屏幕显示名。 |
| 副标题(Subtitle, ≤30) | 待拟，例：`AI jazz improvisation over chord charts` | — | 随首版补。 |
| 描述(Description) | 待拟：功能点（导入 iReal Pro / MusicXML 谱、Guide/Grammar/Learning 三档算法、调音台、离线） | — | 不出现「Java/Impro-Visor」等实现来源字样于营销文案（GPL 署名仅在 App 内许可页）。 |
| 关键词(Keywords, ≤100) | 待拟：jazz, improvisation, chord chart, lead sheet, practice, saxophone, piano, bebop | — | 逗号分隔。 |
| 版本新功能(What's New, 1.07) | 待拟：首版说明 | — | 首发。 |
| 宣传文本(Promotional Text) | 可选 | — | |
| 发布说明(Release Notes) | 待拟 | — | |
| 技术支持 URL | 需填（LicensesView 已留 mailto:onearonly@gmail.com；建议补一个落地页） | — | |
| 营销 URL | 可选 | — | |
| 类别 | 主：Music；副：Productivity（待定） | — | `LSApplicationCategoryType=public.app-category.music` |

### 隐私标签（App Privacy / Nutrition Label）
- 数据采集：**无**。静态确认：无 URLSession、无第三方 SPM、无分析 SDK、无崩溃上报、无 IDFA、无 NSUserTrackingUsageDescription、无跟踪。
- 数据存储位置：全部在本机（UserDefaults + Documents），不离开设备。
- StoreKit 内购（`com.realimpro.master.lifetime`）属 App Store 支付，按 Apple 规则通常不计作「开发者收集的数据」，但仍需在隐私问卷如实选择「不收集数据」。
- 数据删除/导出义务：无账号、无服务端；用户数据（导入的歌单/设置）在 App 内废纸篓/删除即可达成删除；无个人数据导出义务。
- **结论：隐私问卷应选「不收集任何数据」(Data Not Collected)。**

---

## 2. PrivacyInfo.xcprivacy 缺失与 Required Reason API 核查

### 2.1 现状
- 全工程 `find -name "*.xcprivacy"` = **空**；pbxproj 未引用隐私清单。
- 无 `NSPhotoLibraryUsageDescription` / `NSMicrophoneUsageDescription` / `NSCameraUsageDescription` —— **正确，无需**：文件导入走 `UIDocumentPickerViewController`（DocumentPickerView.swift:17，进程外选文件），不直接相册/麦克风/相机；App 内无录音。
- Info.plist(RealimPro-Info.plist) 仅注册 `irealb` / `irealbook` 两个 URL scheme（导入 iReal Pro 链接用），无其他用途描述缺失。

### 2.2 Required Reason API 静态核查（Apple 自 2024 起要求声明使用原因）
| 关注 API | 是否使用 | 结论 |
|---|---|---|
| UserDefaults | 是（`@AppStorage` 十余键 + `UserDefaults.standard`） | **不在 Required Reason 名单**，无需声明原因。 |
| 文件时间戳(creationDate/modificationDate/attributeOfItem/URLResourceKey) | **否**（rg 全空） | 无需。 |
| 磁盘空间/容量(volumeAvailableCapacity/systemFreeSize) | 否 | 无需。 |
| UUID / 设备标识 | 仅 `UUID()` 作本地 token（ContentView.swift:125/3038） | 非设备标识，无需。 |
| FileManager Document/ApplicationSupport 目录 | 是（ContentView.swift:230/558、BrickDictionaryParser.swift:123） | 属正常文件沙盒读写，非 Required Reason。 |

### 2.3 建议（不落地）
新建 `PrivacyInfo.xcprivacy`：
- `NSPrivacyTracking = false`
- `NSPrivacyTrackingDomains = []`
- `NSPrivacyCollectedDataTypes = []`
- `NSPrivacyAccessedAPITypes = []`（未用到需声明的 API）
并加入 Target → Copy Bundle Resources。

---

## 3. 版本升级 / 向前兼容（静态）

- 版本：`MARKETING_VERSION=1.07`、`CURRENT_PROJECT_VERSION=1`（pbxproj:296/319/339）。部署目标 16.6。
- 首版发布，无存量用户；UserDefaults 新增键均带默认值：
  - 颜色/transform 类开关全部默认 **false**（`transformEnabled`/`guideColorEnabled`/`guideLineColorEnabled`/`grammarColorEnabled`/`lstmColorEnabled`，ContentView.swift:844-853）——符合「color/transform 开关默认 false」约定。
  - 宽度键 `guideSkeletonWidthRaw/grammarWidthRaw/learningWidthRaw/transformWidthRaw` 默认 `conservative`。
  - 音域 `guideLowMidi=60/guideHighMidi=79`。
- 注意（非 bug，记录）：`grammarColorEnabled` 默认值曾由 true 改为 false（ContentView.swift:849 注释）。首版无老用户，无需迁移；若未来真有升级，老用户本地 true 会保留、新用户默认 false。
- 已购恢复：`IAPManager.checkCurrentEntitlements`(IAPManager.swift:33) 走 StoreKit `Transaction.currentEntitlements`，卸载重装后由 Apple ID 恢复，不依赖本地标志 —— 符合 StoreKit 规范。
- 隐藏歌单/已导入歌单/废纸篓持久化于 UserDefaults(`hiddenBuiltinPlaylistNames`/`hiddenBuiltinSongKeys`/`importedStoreKey`/`trashStoreKey`)，首版无前向兼容问题。

---

## 4. GPL v2 受影响文件清单（复核标注）

> App 为 Impro-Visor（GPL v2, Robert Keller / Harvey Mudd College）的 Swift 移植衍生作品。`LicensesView.swift:21-31` 已保留原始版权署名 + GPL v2 全文 + GitHub 源码链接 + 源码索取邮箱，**符合 GPL v2 要求，署名不得删除**。
> 下列引擎源码目录为移植/对齐自 Impro-Visor 的受影响范围（用户称已处理，此处只读标注）：

- `Roadmap/`：`JazzRoadmap.swift`、`BrickLibrary.swift`、`BrickDictionaryParser.swift`、`CYKParser.swift`、`IRealProParser.swift`、`JazzSong.swift`、`KeyAnalysisModels.swift`、`KeySpan.swift`、`PostProcessor.swift`、`PostProcessorFull.swift`、`SubstitutionDictionary.swift`，及 `Roadmap/JavaAligned/`（JavaBrickParser / JavaCYKParser / JavaDiatonic / JavaDominantCycle / JavaKeySpanModels / JavaRoadmapAnalyzer）。
- `Grammar/`：`Grammar.swift`、`GrammarStrategy.swift`、`GrammarLickGlue.swift`、`GrammarNCPBridge.swift`、`GrammarNoteConverter.swift`、`GrammarTerminals.swift`、`NoteChooser.swift`、`PitchProbTable.swift`、`ApproachType.swift`、`TupletSanitizer.swift`。
- `TransformEngine/`：`JavaAlignedTransformEngine.swift`、`Transform*.swift`、`Evaluate.swift`、`Scorer.swift`、`Substitution.swift`、`Trend*.swift`、`NCPIterator.swift`、`TransformMusicianRegistry.swift` 等（含 `TransformTables/*.tsv` 26 个乐手学习库数据）。
- `GuideTone/`：`JazzGuideToneEngine.swift`、`GuideLineGenerator.swift`、`GTVocResolver.swift`、`GuideToneVocabularyTable.swift`。
- `LSTM/`：`RNN*.swift`、`LSTMStrategy.swift`（含 `combination.rnn`/`GreatMoments.rnn` 模型权重）。
- `ThemeWeaver/`：`ThemeWeaverEngine/Strategy.swift`、`Motif*.swift`、`SectionConnector.swift`、`JavaLCG.swift`。
- `FullVoicing/`、`Rhythm/`、`Expectancy/`：和声/节奏/期望模型移植。
- 数据：`grammars/*.rules`、`grammars/My.dictionary`、`grammars/*.grammar`。

合规要点：
1. **功能 UI 不得出现「Impro-Visor/Java」字样** —— 静态已核，功能 UI 无；仅许可页保留，合规。
2. 衍生作品须以 GPL v2 发布并提供源码 —— 已通过 GitHub 链接 + 邮件索取方式提供，符合 GPL v2 §3。
3. VexFlow(MIT)、music21(BSD-3)、ChoriumRevA SoundFont 署名均已在许可页保留。

---

## 5. 资源与包体（只读结论）
- 资源经 Xcode16 `fileSystemSynchronizedGroups`（pbxproj:83）整目录自动进包，无需逐文件 Target Membership；首启即用、无 ODR（无 `NSBundleResourceRequest`）。
- 体积：`ChoriumRevA.sf2` 57MB + `TransformTables` 11MB + `LSTM` 17MB + `grammars` 1.6MB + Assets 5MB ≈ **90MB**。
- DEBUG 兜底开发机绝对路径 `LSTMStrategy.swift:137` 已 `#if DEBUG` 包裹，Release 自动剔除，不影响上架。
- `.grammar`（BillEvans/JoePass）当前运行时只加载 `.rules`，`.grammar` 仅随包打包、未被代码读取（轻微冗余，非问题）。
