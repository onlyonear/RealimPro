# MusicXML 导入功能设计稿 —— 评审意见（供第三方复核）

> **文档目的**：本文是对《MusicXML导入设计稿.md》的独立代码级评审，交给另一位不了解项目历史的 AI / 工程师复核。请在**通读本文 + 对照真实工程代码**后，判断结论是否准确、方案是否可行。
>
> **评审方式**：所有结论均对照当前工程源码逐行核实，关键位置给出了文件路径与行号（行号基于评审时的代码状态，若代码已改动请按符号名重新定位）。
>
> **评审日期**：2026-09-22
>
> **红线（最高优先级约束）**：本功能**不得修改** App 现有的 solo 生成算法、播放引擎、VexFlow 渲染引擎、界面布局与工具栏尺寸。新功能应以"产出与内置库同构的数据 + 复用现有映射/解码链路"的方式接入。评审阶段不改动任何 Swift 代码。

---

## 一、背景与工程基线

### 1.1 App 与功能目标

- 产品：**Real Impro**（爵士即兴 solo 生成 App，已上架），Xcode 工程 `RealimPro.xcodeproj`，bundle id `wonderbread.realimpro`。
- 工程根目录：`/Users/onlyonear/Desktop/Improlyze/`
- 核心源码目录：`/Users/onlyonear/Desktop/Improlyze/Real imPro/`
- 目标功能：让用户把自己下载的 **lead sheet 版 MusicXML（单旋律 + 和弦标记）** 导入歌单，在现有五线谱上显示旋律与和声，并能播放旋律/伴奏、生成即兴 solo。
- App 为**完全离线**应用，不联网、不收集用户信息。

### 1.2 现有三套曲库数据（理解导入链路的前提）

| 曲库 | 来源 | 旋律 | 和声 | 接入方式 |
|---|---|---|---|---|
| 内置 Classic Jazz（公共领域，分地区 16/34 首） | 编译进 Bundle 的 JSON | 有 | 有 | `BuiltinMelodyLibrary.load(bundle:)` |
| effendi 79 首（实际 78 首，"Classic Jazz Standards"） | 离线 Python(music21) 从 MusicXML 转 JSON | 有 | 有 | 用户导入 JSON，走 `BuiltinMelodyLibrary.load(from:)` |
| iRealPro 1460 首 | 用户导入 `.txt` / `irealb://` | **无** | 有 | `IRealProParser.parseHTML` |

关键：**已经存在一条"外部旋律 JSON → 与内置库同构 DTO → 落库 → 渲染/播放/生成"的成熟链路**，MusicXML 导入本质上是在它前面加一个"MusicXML → 同构 JSON"的转换器。

### 1.3 离线转换管线（设计稿大量引用，已验证存在）

目录：`/Users/onlyonear/Desktop/video_shoot/jazz_songs/effendi/`

- `build_79.py`：权威转换脚本，含以下被设计稿引用的函数，**均真实存在**：
  - `chord_melody_midi(ch)`（:68）
  - `extract_events(measure)`（:80，读取 `measure.paddingLeft`，:83）
  - `split_into_chunks(raw, bar_end, g)`（:130）
  - `PIECE_STD = [480,360,240,180,120,90,60,45,30,15]`（:156）
  - `PIECE_STD_T3 = [160,80,40,20]`（:157，三连音专用网格）
  - `split_slots(want, tuplet)`（:158）
  - `repair_orphan_ties(out)`（:232）
  - `repair_dangling_ties(measures, title)`（:285）
  - `finalize(out)`（:337）
  - **反复展开 `sc.expandRepeats()`（:261）**
- `convert_core.py`：另一版转换核心，:79-86 也有反复展开逻辑。
- 黄金集：`mxl_all/` 目录，**正好 400 个未压缩谱**（347 个 `.xml` + 63 个 `.musicxml`，无 `.mxl`）。

---

## 二、总体结论

**设计稿整体可行、专业度高，可作为开工基础。** 其核心架构判断正确：

- 产出与内置库同构的 `LibraryDTO`，复用现有 `BuiltinMelodyLibrary.load(from:)`；
- 和弦直接复用 `ChordSymbolMapper`，不重造映射表；
- 渲染/播放/生成引擎零改动；
- "宁可明确拦截，不可静默导入错谱"的闸门哲学正确；
- 落库前的守恒 / 0 卡音仿真终检（V20）是命门，必须保留。

但有 **2 处事实性错误必须修正**、**1 个被低估的关键问题（反复展开，涉及 80% 的谱）**、**4 个产品口径需拍板**、**4 个技术点需补强**。详见下文。

---

## 三、已逐项核实"准确"的内容（可直接采信）

| 设计稿假设 | 代码核实结果 |
|---|---|
| `GeneratedNote` 含 pitch/duration/isRest/isTriplet/isTieStart/isTieEnd/graceNotes | ✅ `CoreEngine/JazzEngine.swift:15-35` 全部存在 |
| `GeneratedMeasure` 含 chordAnnotations / slotsPerMeasure(默认480) / chordSlots | ✅ `CoreEngine/JazzEngine.swift:38-47` |
| 拍号 slots：4/4=480、3/4=360、2/4=240、6/8=360、12/8=720、5/4=600、6/4=720、1/2=240 | ✅ `MidiPlayer/TimeSignatureManager.swift:18-70` 逐一吻合（四分音符=120 slots，最小量化 15） |
| DTO 全 Optional 容错、`load(from data: Data)` 与 `load(bundle:)` 存在 | ✅ `BuiltinLibrary/BuiltinMelodyLibrary.swift:96-167` |
| LibraryDTO/SongDTO/MeasureDTO/NoteDTO/ChordSlotDTO/ChordAnnotationDTO 字段 | ✅ 同上，:125-167 |
| `importFromFile(url:)` 现仅按 `.json` 分流旋律库，其余按 UTF-8 文本走 iReal 解析 | ✅ `Views/ContentView.swift:505-540`，:510 判断 `pathExtension == "json"`，:532 走 `IRealProParser.parseHTML` |
| `persistExternalMelodyFile`（落盘 ImportedMelodies/*.json）、`handleImportResult` | ✅ `ContentView.swift:497`、`:544` |
| 单曲(count==1, groupName=nil)进 My Songs，多首用文件名做歌单名 | ✅ `ContentView.swift:538-539` |
| `ChordSymbolMapper.resolve(_:)` 无法识别返回 nil；斜杠和弦只看本体 | ✅ `FullVoicing/ChordSymbolMapper.swift:9-23`（rootRise 查不到或 canonical 查不到均 `return nil`） |
| `NoteSpelling.spellNote(midiPitch:chordName:)` 可复用 | ✅ `Harmony/NoteSpelling.swift:55`（含 sharpNames/flatNames 表、useSharps） |
| 悬空 isTieStart 会卡音长鸣；播放端有 heldTieNotes 兜底 | ✅ `MidiPlayer/JazzMidiPlayer.swift:471-559`：tieStart 入集合(:533)，遇异音强制 stopNote(:528-530)，休止/曲末清空(:548,:558) |
| 渲染支持 StaveTie / Triplet(realTuplet) / GraceNote / Accidental / Barline | ✅ `Views/SheetMusicView.swift:598(StaveTie)`、`:303/:343(realTuplet)`、`:394-409(GraceNote)`、`:369(Accidental)`、`:891-895(Barline)` |
| 黄金集 400 个未压缩 MusicXML | ✅ `mxl_all/` 实测 400 个（.xml/.musicxml） |

---

## 四、必须修正的事实性错误

### ❌ 错误 1："渲染不画调号（无 setKeySignature），临时记号逐音绘制" —— 不成立

设计稿 §1 特性表与"关键事实"声称渲染端不画调号、完全依赖逐音临时记号。**这与代码不符**：

- `Views/SheetMusicView.swift:885-889`，第一小节（`mIndex === 0`）同时执行：
  - `stave.addClef("treble")`（:886）
  - **`stave.addKeySignature(keySignature)`（:887）**
  - `stave.addTimeSignature(timeSignature)`（:888）
- 与此同时，:345-369 仍对每个需要的音绘制 `VF.Accidental`（逐音临时记号机制也存在）。

**调号数据链路（已查清）**：

- JS 变量 `keySignature` 由 Swift 的 `vexflowKey` 注入（`SheetMusicView.swift:655`），转调时经 `updateSheetMusic(newData,newKey,...)` 更新（:661-664）。
- `vexflowKey` 来自 `getVexflowKey(for: key)`（:140、:614 调用；定义在 :171-205）：
  - 标准大调（C/G/D/A/E/B/F#/C#/F/Bb/Eb/Ab/Db/Gb/Cb）直接返回；
  - 小调（后缀 `m`）按"关系大调 = 小调根音 +3 半音"的穷举表映射；
  - 兜底返回 `"C"`。

**对 MusicXML 导入的影响（设计稿漏掉的工作）**：

MusicXML 的调号不是调名字符串，而是 `<key><fifths>N</fifths><mode>major|minor</mode></key>`，其中 `fifths` 是升降号个数（-7~+7）。导入器**必须新增一张 `(fifths, mode) → App 调名字符串` 的映射表**，例如：

- major：fifths=0→C、+1→G、-1→F、-2→Bb、+2→D …（共 15 个大调）
- minor：fifths=0→Am、-1→Dm、-2→Gm、+1→Em …，再交给 `getVexflowKey` 转关系大调。

若不做这张表（或映射错），导入曲的**调号会显示错误**；虽然逐音 Accidental 可能仍让单个音的升降显示正确，但会出现"调号与临时记号不一致 / 重复记号"的视觉问题。**开工前必须把 fifths/mode → key 的映射列为明确任务并用黄金集验证。**

> 设计稿"必须给每个音确定拼写"的结论仍成立（逐音 Accidental 还在），但理由需要更正：渲染端**既画调号又画逐音临时记号**，二者都要喂对。

### ⚠️ 错误 2：拍号支持表漏了 2/2

- 设计稿 §3.2 列了 `1/2 = 240`，但**漏了 `2/2`**。
- `TimeSignatureManager.swift` 的 switch **没有 `2/2` 这个 case**，会落到 `default` 当作 4/4（slotsPerMeasure=480）。
- 时值上 2/2（每小节 2 个二分音符 = 4 个四分音符）确实等于 480 slots，**节奏时值不会错**；但**拍号会被显示成 4/4**，与原谱不符。
- 这不是理论边角：**内置 Classic Jazz JSON 中实测有 7 首是 `"2/2"`**（26 首 4/4、7 首 2/2、1 首 3/4），是真实高频拍号。

**修正建议**：§3.2 增补 `2/2 = 480`，并二选一：
- (a) 在 TimeSignatureManager 增加 2/2 case 使其正确显示（注意：这会动到渲染/拍号层，需评估是否触碰"引擎零改动"红线）；或
- (b) 导入器遇到 2/2 时显式告警"2/2 将按 4/4 显示，时值不变"，由用户知情接受。

建议在评审中明确选 (a) 还是 (b)；若严守红线，v1 先用 (b)。

---

## 五、被低估的关键问题：反复记号（Repeats）

### 5.1 概念澄清："展开"与"线性导入"是相反操作

设计稿提出 MVP "**线性导入 + 告警（歌曲可能比原谱短）**"，并把"复杂反复展开"推到二期。这与产品方既有的"反复段直接再渲染一遍"哲学**不是一回事，方向相反**：

MusicXML 中，被反复的段落**音符只物理存储一次**，反复靠跳转标记 `<repeat direction="backward"/>`（即 :||）表达。

| 处理方式 | A 段在数据里 | 听到/看到的结果 | 相对"实际演奏" |
|---|---|---|---|
| 纸面原谱（带 :|| 记号） | 1 次音符 + 1 个回头记号 | 纸面短，演奏时人回头再弹一遍 | — |
| **Swift 线性导入（不解释跳转）** | 只读物理存在的 1 次，忽略 :|| | A 段只过一遍就继续向下 | **变短（漏掉重复段）** |
| **离线 Python `expandRepeats()`（产品方哲学）** | 真正复制成 2 次音符 | A 段过 2 遍 | 等长（=实际演奏），比纸面长 |

- 产品方印象中的"反复段再渲染一遍、变长"，对应的是**第三行（展开）**，由离线脚本 `build_79.py:261 sc.expandRepeats()` 实现。
- 设计稿 MVP 的"线性导入"是**第二行（不展开）**，Swift 端没有 music21、也不打算写展开器，因此会**变短**。告警"可能比原谱短"是给这个降级方案兜底的。

### 5.2 数据证明：这个降级代价过大，不能整体推到二期

对黄金集 `mxl_all/` 400 个谱的实测统计：

- **319 / 400（约 80%）含 `<repeat>` 反复记号**；
- 前向反复 `direction="forward"`（||: 起点）：**801 处**；
- 回头反复 `direction="backward"`（:||）：**854 处**；
- 一房子/二房子 `<ending>`（volta）：**1015 处**；
- D.S. / D.C. / al Coda / al Fine / To Coda 等文字跳转：**29 首（约 7%）**。

若 MVP 真的"线性导入 + 一句告警"，约 **80% 的用户导入曲都会缺段少小节**，功能事实上不可用；普通用户也无法理解"歌曲可能比原谱短"，只会认为 App 把谱弄错了。

旁证：`build_79.py:7` 注释写明"3 首反复展开失败回退原始谱"，连成熟的 music21 都有展不开的情况，说明复杂跳转确实难，**宁可拦截也不要硬展或静默变短**。

### 5.3 修正建议：把反复处理拆成两档，而非整体二期

1. **MVP 必须实现**：
   - 成对的简单反复（forward/backward，即 ||: … :||）展开；
   - 一房子/二房子（volta ending）展开——出现频率高达 1015 处，是 lead sheet 标准写法，不能跳过。
2. **MVP 可拦截并明确提示**：
   - D.S. / D.C. / al Coda / Fine 等非线性跳转（仅约 7%）。自检到这类结构时**不写盘**，提示"该谱含暂不支持的跳转记号（D.S./Coda 等），请在 MuseScore 中展开反复后重新导出 MusicXML"。
3. 展开结果同样要过 V20 守恒终检（展开前后总时值、小节数符合反复语义）。

> 请复核方重点判断：在 Swift 端实现"简单成对反复 + volta 房子"展开器的工作量与风险，是否可纳入 MVP；以及"复杂跳转拦截"的边界检测是否可靠（避免漏检导致静默变短）。

---

## 六、4 个产品口径的建议（需产品方拍板）

设计稿结尾提出 4 个问题，评审建议如下：

1. **全曲无和弦标记 → 建议 v1 直接拦截（同意设计稿）。**
   App 的伴奏引擎与 solo 生成都依赖和弦；支持"纯旋律无伴奏"需要给播放/渲染/生成三条链路都加"无和弦"分支，违反引擎零改动红线。拦截并提示即可。

2. **压缩格式 `.mxl` → 建议 v1 不支持（同意设计稿），二期再引入 ZIPFoundation。**
   .mxl 本质是 ZIP，v1 支持需新增压缩依赖、包体积与审核面；MuseScore 免费"另存为未压缩 .musicxml"用户成本极低。但 effendi 等站点不少直接提供 .mxl，拦截率不低，**提示文案需写清转换步骤**。

3. **反复记号 → 不接受简单"线性导入 + 告警"，改为按第五节两档处理**（简单反复+房子 MVP 展开，复杂跳转拦截）。

4. **多声部 / 钢琴谱 → 建议比设计稿更严格：检测到多个 Part（钢琴大谱表）v1 直接拦截**，只收单旋律 lead sheet。
   "在钢琴谱里自动选哪条是旋律"本质无解，启发式选错属于**静默错误**（导入了错误旋律，用户却以为正确），危害最大。同一谱表内的 voice1/backup（多声部叠在一行）可以取 voice 1；但多 Part（如左右手双谱表、鼓谱、六线谱/TAB）应拦截并提示"请下载单旋律 lead sheet 版本"。

---

## 七、设计稿遗漏、建议补强的技术点

1. **`<divisions>` 可能逐小节变化。**
   MusicXML 的 divisions 写在 attributes 里，理论上每个 measure 可不同。量化时必须取**当前小节生效的 divisions**，不能假设全曲统一（lead sheet 通常统一，但解析器要按 measure 取值）。

2. **和弦时间锚定（chordAnnotations 的 noteIndex）是高频翻车点，应列为强制验收项。**
   此项目曾出现"两个和弦标签在视觉上贴在一起"的 bug：根因是和弦的 startSlot 被挂到了错误的旋律音符 noteIndex 上（第二个和弦本应挂在第 3 拍的音，却挂到了第 1 拍反拍的音）。导入器必须用"startSlot 二分/就近定位到时间最接近的旋律音符"来确定 noteIndex，并把"chordAnnotations 与 chordSlots 等长、每个标签锚点时间正确"列入强制验收，而不是普通规则。

3. **`.xml` 路由不能只看扩展名。**
   现 `importFromFile` 仅以 `.json` 分流（`ContentView.swift:510`），其余一律按 UTF-8 文本送 iReal 解析（:528-532）。而 iReal 导出的 `.html/.txt` 也可能含 XML 标签。新增 MusicXML 分支时应**双重判断**：扩展名（.xml/.musicxml）**且**文件头/内容包含 `<score-partwise`（或 partwise 根元素），避免把 MusicXML 误送进 iReal 解析器，或把含 XML 的文本误判为 MusicXML。`.mxl` 按口径 2 明确拦截。

4. **V20 终检是命门，务必保留且"不通过不写盘"。**
   落库前至少校验：小节时值守恒（每小节音符 slots 之和 = slotsPerMeasure，含 tie 拆分）、0 卡音仿真（无悬空 isTieStart、无未闭合连音）、chordAnnotations/chordSlots 等长、每小节至少 1 个和弦、三连音网格对齐。这套终检在离线管线中已被证明能拦住绝大多数问题，App 端导入器应移植同等强度的校验。

---

## 八、建议修订后的 MVP 范围（汇总）

**纳入 MVP：**

- 未压缩 `.musicxml` / `.xml`（文件头含 score-partwise）；
- 单旋律 lead sheet（单 Part；同谱表 voice1/backup 取 voice1）；
- 单一拍号：4/4、3/4、2/4、2/2(按错误2处理)、6/8、12/8、5/4、6/4、1/2；
- 时值：全/二/四/八/十六/三十二分 + 附点 + 三连音 + tie；同时和弦取最高音；
- 含 `<harmony>` 和弦，经 `ChordSymbolMapper` 归一；
- **调号：实现 fifths/mode → App key 字符串映射（修正错误1）**；
- **简单成对反复 + volta 一/二房子展开（第五节）**；
- 非标准时值吸附 15 网格、空隙补休止、连音修复（移植离线管线函数，用户文件只做"不改音高"的修复）；
- 完整 V20 终检，不通过不写盘。

**MVP 拦截 / 告警（不静默降级）：**

- 全曲无和弦；压缩 `.mxl`；多 Part 钢琴谱/鼓谱/TAB；混合拍号；timewise 谱；
- D.S./D.C./Coda/Fine 等非线性跳转；
- 无法闭合的连音、守恒不过；
- 五连音等复杂连音可量化+告警（设计稿原方案），grace note、歌词、力度、装饰音按原方案忽略或二期。

**二期：**

- .mxl 压缩支持（ZIPFoundation）；复杂反复跳转展开；grace note；多声部旋律智能选择；移调乐器处理。

---

## 九、请复核方重点回答的问题

1. 第四节两处事实性错误（调号 `addKeySignature` 确实存在、漏 2/2），对照源码是否成立？
2. 第五节"约 80% 谱含反复、线性导入会导致缺段"的统计与结论是否成立？把"简单反复 + volta 房子展开"纳入 MVP 是否合理、工作量是否可控？
3. 第六节 4 个产品口径（无和弦拦截 / .mxl 二期 / 反复两档 / 多 Part 拦截）是否有更优选择？
4. 第七节 4 个技术补强点（divisions 逐小节、和弦 noteIndex 锚定强制验收、.xml 双重路由判断、V20 终检）是否遗漏或过度？
5. 在"不改动 solo 生成 / 播放 / 渲染引擎 / UI 布局"的红线下，本方案是否存在设计稿未识别到的、必须改动引擎才能实现的点？

---

### 附：复核所需的关键文件清单

- 数据模型：`Real imPro/CoreEngine/JazzEngine.swift`
- 拍号：`Real imPro/MidiPlayer/TimeSignatureManager.swift`
- 内置库 DTO/解码：`Real imPro/BuiltinLibrary/BuiltinMelodyLibrary.swift`
- 导入路由：`Real imPro/Views/ContentView.swift`（importFromFile :505）
- 渲染：`Real imPro/Views/SheetMusicView.swift`（调号 :655/:887、getVexflowKey :171、Accidental :345-369、StaveTie :598）
- 和弦映射：`Real imPro/FullVoicing/ChordSymbolMapper.swift`、`ChordFormMaps.swift`
- 音高拼写：`Real imPro/Harmony/NoteSpelling.swift`
- 播放/连音兜底：`Real imPro/MidiPlayer/JazzMidiPlayer.swift:471-559`
- 离线权威管线：`/Users/onlyonear/Desktop/video_shoot/jazz_songs/effendi/build_79.py`、`convert_core.py`
- 黄金集：`/Users/onlyonear/Desktop/video_shoot/jazz_songs/effendi/mxl_all/`（400 个未压缩谱）
