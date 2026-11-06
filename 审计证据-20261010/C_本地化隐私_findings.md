# C — Real imPro 发布前【本地化 + 隐私/发布工程】只读审计 Findings

- 审计对象：`/Users/onlyonear/Desktop/Improlyze/Real imPro/`（生产代码，只读）
- 审计日期：2026-10-10 ｜ 审计方式：静态只读（截图/语言实测由运行时子代理执行）
- 工程基线：Xcode 26.5 / objectVersion 77 / Swift 5.0 / 部署目标 16.6 / MARKETING 1.07 / BUILD 1
- 纪律：未修改任何生产文件；以下「修复示意」仅作报告建议，不落地。

---

## 0. 结论速览

| 维度 | 结论 |
|---|---|
| 实际支持语言 | **仅英文**。`developmentRegion=en`、`knownRegions=(en, Base)`，全工程只有 `Real imPro/en.lproj/Localizable.strings`，**无 zh-Hans/zh-CN .lproj、无 .xcstrings、无 .stringsdict**。 |
| 本地化组织方式 | 反模式：**以中文当 key、英文当 value**（`"删除" = "Delete";`）。漏 key 时英文环境直接回退显示中文 key。 |
| 用户可见中文泄漏 | **存在，且为 P1**：付费错误串全中文硬编码 + 7 处中文 key 漏配回退中文 + 1 处中文 .help 提示。 |
| 硬编码未走本地化 | **约 45+ 处用户可见英文字符串**未包 `NSLocalizedString`（付费墙、设置卡、调音台、图例等）；当前英文环境显示正确，但属未来加简中时的技术债。 |
| 「Java」用户可见字样 | **未发现**。仅存在于注释与内部类型名（`JavaRoadmapAnalyzer`/`JavaLCG` 等）。 |
| 「Impro-Visor」用户可见字样 | **仅在 LicensesView 致谢/GPL 页**（GPL v2 合规署名，必须保留，不得删）。功能 UI 未出现。 |
| 隐私清单 | **缺失 PrivacyInfo.xcprivacy**（P1，上架元数据/合规要求）。无联网、无分析 SDK、无崩溃上报、无跟踪。 |
| Required Reason API | 未使用文件时间戳/磁盘空间等需声明原因的 API；UserDefaults 不在 Required Reason 名单。 |
| GPL | 整引擎为 Impro-Visor(Swift port) 衍生作品，致谢页已署名 + GitHub 源码链接，符合 GPL v2；受影响文件清单见 C3。 |
| 包体 | 同步文件夹自动进包，无 ODR；首启资源即 `ChoriumRevA.sf2`(57MB)+TransformTables(11MB)+LSTM(17MB)≈90MB 全量内置。 |

---

## P0 / P1 阻塞上架相关

### LOC-001 ｜ P1 ｜ 本地化
**标题**：付费错误提示全部硬编码中文，英文 UI 弹窗里直接弹中文（半中半英）
- 文件:行：`Views/IAPManager.swift:43`、`:55`、`:60`、`:66`、`:77`、`:79`
- 触发前置：用户在英文环境触发购买失败 / 验证失败 / 待处理 / 恢复购买无记录。
- 逐步复现：进入付费墙 → 断网点「购买」或「Restore Purchase」→ 触发 `.alert("Notice")`（PaywallView.swift:73-80）→ `Text(iapManager.errorMessage)`。
- 实际结果：弹出 `"无法连接 App Store，请检查网络后重试"` / `"购买验证失败，请重试"` / `"购买待处理，App Store 确认后将自动激活"` / `"购买失败：…"` / `"未找到购买记录，请确认 Apple ID 是否正确"` / `"恢复失败：…"` —— 纯中文。
- 预期结果：英文 UI 内应为英文。
- 证据：静态（已逐行读 IAPManager.swift 全文）。
- 修复示意（不落地）：改为 `errorMessage = NSLocalizedString("无法连接 App Store，请检查网络后重试", comment: "")` 并在 `en.lproj` 补英文 value；或直接用英文写死再进 strings。
- 是否阻塞上架：否（不致拒审），但属严重体验缺陷，**交叉-付费**（文案判定由付费子代理复核）。

### LOC-002 ｜ P1 ｜ 本地化
**标题**：7 处中文 `NSLocalizedString` key 在 .strings 表中缺失，英文环境回退直接显示中文
- 文件:行（key → 位置）：
  1. `无法读取 JSON 文件。` → `Views/ContentView.swift:577`
  2. `旋律 JSON 解析失败。` → `Views/ContentView.swift:589`
  3. `暂不支持压缩的 .mxl 文件，请在“文件”App 中解压或另存为 .musicxml/.xml 后再导入。` → `Views/ContentView.swift:597`
  4. `无法读取文件。` → `Views/ContentView.swift:601`（表内只有更长的 `无法读取文件，请确认文件编码为 UTF-8。`）
  5. `MusicXML 中未解析出有效乐曲。` → `Views/ContentView.swift:635`
  6. `已导入《%@》。MusicXML 无可靠风格字段，伴奏统一按 Medium Swing（中等摇摆）处理；速度 %d BPM。原曲旋律与和弦可直接显示、播放与即兴。` → `Views/ContentView.swift:650`
  7. `MusicXML 解析失败，请确认是单 Part 的 lead sheet（和弦+旋律）。` → `Views/ContentView.swift:658`
- 触发前置：用户导入 .json / .mxl / .musicxml / .xml 且走到失败或成功提示分支。
- 实际结果：英文用户在「Import Complete」alert（ContentView.swift:2218）的 message 区看到上述整段中文。
- 预期结果：显示对应英文。
- 证据：静态。脚本 `_scan_localization.py` 差集 + `grep -qF` 二次确认 MISSING。
- 修复示意（不落地）：在 `en.lproj/Localizable.strings` 补齐 7 条 `"中文key" = "English..."`；其中第 6 条含 `%@/%d`，注意保留两个占位符顺序。
- 是否阻塞上架：否，但英文导入流程会露中文，建议首发前修。

### LOC-003 ｜ P1 ｜ 本地化
**标题**：`.help("显示/隐藏级数分析")` 中文硬编码（级数分析按钮的悬停/长按提示）
- 文件:行：`Views/ContentView.swift:3004`
- 触发前置：iPad 上长按/悬停右上角「级数分析」开关按钮。
- 实际结果：tooltip 显示中文「显示/隐藏级数分析」。
- 修复示意：`.help(NSLocalizedString("显示/隐藏级数分析", comment: ""))` 并在 strings 补 `"显示/隐藏级数分析" = "Show / hide degree analysis";`
- 证据：静态。
- 是否阻塞上架：否。

### PRIV-001 ｜ P1 ｜ 隐私发布
**标题**：缺少 `PrivacyInfo.xcprivacy` 隐私清单文件
- 文件:行：全工程 `find -name "*.xcprivacy"` 为空；pbxproj 未引用隐私清单。
- 触发前置：首次提交 App Store。
- 实际结果：无隐私清单。当前 App 全离线、无数据采集、无 Required Reason API 使用，理论上应声明 `NSPrivacyTracking=false`、无采集类型；但苹果自 2024-05 起要求随包提供隐私清单，缺失会在审核/元数据阶段被要求补正。
- 修复示意（不落地）：新建 `PrivacyInfo.xcprivacy`，`NSPrivacyTracking=false`、`NSPrivacyCollectedDataTypes=[]`、`NSPrivacyAccessedAPITypes=[]`（已核未用时间戳/磁盘 API），并加入 Target -> Copy Bundle Resources。
- 证据：静态（find 为空 + pbxproj 无 xcprivacy 引用）。
- 是否阻塞上架：**是（元数据/合规），需随首版补齐**。

---

## P2 技术债 / 提示（不阻塞）

### LOC-101 ｜ P2 ｜ 本地化
**标题**：付费墙 PaywallView 全部字符串硬编码英文、未走 NSLocalizedString
- 文件:行：`Views/PaywallView.swift:13`(`Unlock Master Algorithms`)、`:17`(`Advanced jazz grammar engine`)、`:18`(`Lifetime access, one-time purchase`)、`:34`(`… — Lifetime`)、`:43`(`Connecting to App Store…`)、`:46`(`Cannot connect to App Store`)、`:48`(`Retry`)、`:59`(`Restore Purchase`)、`:73`(.alert `"Notice"`)、`:77`(`OK`)
- 现状：英文环境显示正确（与英文 UI 一致）；但未入本地化表，未来加简中时这 10 处需补 key。
- 证据：静态（已读全文 1-95）。
- 是否阻塞上架：否（当前英文 UI 无错语言）。**交叉-付费**。

### LOC-102 ｜ P2 ｜ 本地化
**标题**：ModeSettingsCard 设置卡大量字符串硬编码英文
- 文件:行：`Views/ModeSettingsCard.swift:40`(`GuideTone Settings`)、`:41`(`Grammar Settings`)、`:42`(`Learning Settings`)、`:50`(`Choose Range`)、`:81`(`Done`)、`:154`(`Allow Color Tones`)、`:269-272`(`Direction`/`No Preference`/`Ascending`/`Descending`)、`:275`(`Start on Scale Degree`)、`:282-286`(`Max Note Duration`/`No Preference`/`Whole`/`Half`/`Quarter`)、`:289`(`Range`)、`:339`(`Use the + and − buttons…`)、`:365`/`:368`(`Reset`/`Done`)、`:558`(`Choose Range`)、`:627`(`Grammar File`)、`:706`(`Model`)、`:760-773`(ModeBlurb 14 条)
- 现状：英文正确；未入表。
- 证据：静态。
- 是否阻塞上架：否。

### LOC-103 ｜ P2 ｜ 本地化
**标题**：调音台/图例/其他零散硬编码英文
- 文件:行：`BandMixerView.swift:136-139`(`SAX/PIANO/BASS/DRUM`)、`:149`(`STYLE`)、`:158`(曲风 rawValue)；`NoteColorLegendView.swift:7/9/13/14`(`Chord/Color/Approach/Avoid`)；`ContentView.swift:2220`(Button `OK`)、`:2759`(Text `Mixed`)、`:3007/3011`(`✓ Chord Degrees`/`Chord Degrees`/`Key Sections`)；`MotifEntryView.swift:150`(`C4 8, D4 16…` 示例占位)。
- 说明：乐手名/曲名/音名/风格名属专有名词，按既有约定不本地化（`TransformMusicianCatalog.swift:6` 注释明确）。
- 是否阻塞上架：否。

### LOC-104 ｜ P2 ｜ 本地化
**标题**：strings 表内存在 12 条从未被代码引用的「死 key」
- 文件:行：`en.lproj/Localizable.strings` 中 `删除歌曲`、`核心三和弦与七和弦`、`属七变化音`、`挂留和弦`、`小调色彩`、`减 · 增 · 变化`、`本页音级由…`、`Conservative：更克制…`、`主题发展`、`换一个`，以及 4 条英文自映射 `Import Complete…/Mixed/Successfully imported…`。
- 说明：多为旧版 UI 下线后的遗留（如 ThemeWeaver Develop/Regenerate 按钮、和弦字典早期表头）。不影响显示，建议清理或核对是否漏接。
- 证据：脚本差集 UNUSED 列表。
- 是否阻塞上架：否。

### LOC-105 ｜ P2 ｜ 本地化（宽度/溢出，运行时抽查明细见 C2）
**标题**：右栏恒宽 110pt，最长乐手短名可能截断
- 文件:行：`BandMixerView.swift:413`(`.frame(width: 110)`)；乐手短名 `WesMontgomery→"W. Montgomery"`(13 字符)、`JoeHenderson→"J. Henderson"` 等，以 10pt bold rounded + `lineLimit(1)` + `minimumScaleFactor(0.85)` 渲染。
- 静态判断：110pt 内 13 字符大写可能需缩字，需运行时在 iPad mini/11/13 横竖屏实测是否截断/溢出。
- 是否阻塞上架：否（体验项，交运行时子代理截图）。

### PRIV-101 ｜ P2 ｜ 隐私发布
**标题**：CFBundleDisplayName 为 `RealimPro`（无空格），与产品名「Real imPro」不一致
- 文件:行：`RealimPro.xcodeproj/project.pbxproj:281/324` `INFOPLIST_KEY_CFBundleDisplayName = RealimPro;`
- 说明：主屏幕图标下名称显示为「RealimPro」。若希望显示「Real imPro」需改 Display Name；ASC 名称可另设。
- 是否阻塞上架：否。

### REL-101 ｜ P2 ｜ 版本升级
**标题**：v1.07 为首版，无老用户迁移负担；但注意 `grammarColorEnabled` 默认值已由 true 改为 false
- 文件:行：`ContentView.swift:849-851`（注释记录旧默认 true → 现 false=spell-only）。
- 说明：因是 1.0 首发、无存量用户，向前兼容风险低；UserDefaults 各新增键均带默认值（false/conservative/60/79 等），卸载重装后回到出厂默认，符合预期。已购状态由 StoreKit `Transaction.currentEntitlements` 恢复，不依赖本地标志。
- 是否阻塞上架：否。

### REL-102 ｜ P2 ｜ 资源/包体
**标题**：付费 Learning 模型 `.rnn`(17MB) 与 26 个乐手 `.tsv`(11MB) 全量打进基础包
- 文件:行：`LSTM/combination.rnn`、`LSTM/GreatMoments.rnn`、`TransformTables/*.tsv`（经 `fileSystemSynchronizedGroups` 自动进包）。
- 说明：无 ODR（无 `NSBundleResourceRequest`），首启即用、无未下载资源依赖。付费模型未做按需下载，包体≈90MB；如需瘦身可后续 ODR，**不在本次修改范围**。
- 是否阻塞上架：否。

### GPL-101 ｜ 合规标注 ｜ GPL
**标题**：GPL v2 受影响文件清单（用户称已处理，此处标注复核）
- 结论：`LicensesView.swift:21-31` 已含「Swift port of Impro-Visor by Robert Keller / Harvey Mudd College」署名、版权年份、GPL v2 全文与 GitHub 源码链接 + 源码索取邮箱，符合 GPL v2「保留版权声明 + 随附许可证 + 源码可得」要求。
- 受影响（衍生自 Impro-Visor）的引擎源码目录/文件清单见 `C3_ASC与隐私发布清单.md` 第 4 节。
- 是否阻塞上架：否（已合规）。
