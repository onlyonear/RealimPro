# 五线谱「音符渲染」对比报告 —— Real imPro（Swift / iPad） vs Impro-Visor（Java / 桌面）

> 日期：2026-10-12　｜　性质：**纯只读静态源码对比**（未改动/格式化/移动/删除任何生产文件；未运行 xcodebuild；未启动 Java 桌面版；未做同种子并排截图）。
> 对接人：非程序员爵士萨克斯手。所有结论先给"乐手话"，再给双端 `文件:行` 证据。
> 判定口径：**对语义，不对像素**。同一个音在两边被记成不同的时值 / 符号类别 / 结构，才算问题；字体、曲率、留白归为审美。
> 说明：本报告是**内部技术文档**，可出现 "Java" 字样；但 **App 内用户可见 UI 文案一律为英文，且不得出现 "Java" 字样**（落地时请前端遵守）。

---

## 1. 乐手版总览（先看这段就够）

1. **总体上两份谱"长得像、读得通"**：音符时值体系、四类颜色（黑=和弦音、蓝=趋近、绿=色彩、红=外音）、符干朝向规则、三连/五连括号、跨小节延音线，两边的音乐含义基本一致——这些你可以放心。
2. **有一个真正重要、会影响视奏的差别（头号问题）**：iPad 版会把**三十二分级别的极短音**自动改成"小号、带斜杠、不占拍子的倚音"，贴在后一个主音前面；桌面版**从来没有这种小倚音**，再快也是正常大小、占拍子的 32 分音符。一个该在拍子里数清楚的快音，在 iPad 上会被读成"滑一下带过"。
3. **这个小倚音主要在"导入曲谱"时冒出来**：你自己用 App 的 Guide/Grammar/Transform/Learning 自动生成，几乎不会产生小倚音（最短也是正常的 16 分/八分三连）；但**导入一首带 32 分快句的 MusicXML（比如 bebop 曲子的 head）**，那串 32 分就很可能整片变成小倚音。
4. **导入还有一处反方向的丢失**：MusicXML 文件里**本来正规写好的倚音记号，iPad 版导入时直接删掉了**（不画也不响）。一删一造，正好相反——该留的装饰音丢了，该占拍的快音被降级了。
5. 其余是几处"记谱习惯"差别（都不影响听感）：iPad 的符杠连得更现代、和弦字用爵士简写（C-7／C△7／Dø7）且分大小字、切分音会拆成拍对齐再加延音线、还多一层可开关的级数标注；桌面版则有小节号、乐句记号。
6. 你可能担心的很多记号——**反复记号、1./2. 房子、颤音/滑音符号、重音断音记号、圆滑线、多小节休止、双音和声**——**两个版本本来就都没有**，不是 iPad 做漏了，不用纠结。字体一个现代（Bravura）一个老式（手绘小图），纯属审美。

---

## 2. 为什么两份谱不可能"一模一样"：技术栈差异

- **iPad 版（Real imPro）= 专业网页绘谱引擎 VexFlow 跑在 WKWebView 里**。Swift 并不直接画音符，而是拼一大段 HTML/JavaScript 喂给 WebView，由 VexFlow 在 SVG 画布上绘制。
  - 唯一谱面视图：`Real imPro/Views/SheetMusicView.swift`。建 WebView 在 `:67`；首次 `webView.loadHTMLString(html, baseURL: Bundle.main.bundleURL)` 在 `:141`；切歌/重生成/转调时用 `window.updateSheetMusic(...)` 增量注入在 `:152`；SVG 后端在 `:891`。
  - VexFlow 本体是 **App 包内置的本地资源** `vexflow-min.js`（HTML 内联 `<script src="vexflow-min.js">`，`SheetMusicView.swift:675`；实体文件 `Real imPro/vexflow-min.js`，754,004 字节，webpack 打包，断网可用、不依赖外部 CDN）。
  - **版本与字体（已钉死）**：库体内同时内嵌 **Bravura、Gonville、Petaluma** 三套音乐字体；默认字体栈为 `[Bravura, Gonville, Custom]`（Petaluma 已定义但不在默认栈），并含 VexFlow **4.0** 才引入的 `DefaultFontStack`/Petaluma，内部 `RESOLUTION=16384` → 属 **VexFlow 4.x，实际生效字形为库默认 Bravura**（Swift 模板从未调用 setMusicFont 切换）。⚠️ `SheetMusicView.swift:772` 代码注释自称"VexFlow 3.0.9"，与库体证据矛盾，**是过时注释，应以库体为准**（精确小版本在压缩包里无法确证，不臆断）。
- **桌面版（Impro-Visor, Java）= Java2D 纯手绘**，没有任何第三方记谱库：符头、符干、符杠、连线、休止符、谱号全部由 `imp/gui/Stave.java`（6225 行）用 Graphics2D 一笔笔画（音乐符号是 `Images.java` 里预渲染的小图），和弦名在 `Stave.java` 内直接 drawString。
- **推论**：像素级一致既不可能也无必要（像两位抄谱员的笔迹）。VexFlow 自动排版与 Java 手算间距造成的疏密差别多为审美；**只有"同一音被记成不同时值/符号类别/结构"才是要抓的语义问题**——头号即第 3 章 #1。
- **两套引擎共用同一套"时间语言"**（这是能逐音对比的基础）：全音符 480、二分 240、**四分（1 拍）=120**、八分 60、十六分 30、三十二分 15。Java 见 `imp/Constants.java:48,66-82`；Swift 见 `SheetMusicView.swift:224`、`ContentView.swift:1545`。连音/附点公式双端等价（Java `imp/data/Duration.java:227-251`；Swift `SheetMusicView.swift:218-230`）。

---

## 3. 差异明细（20 个维度，按严重度分级）

**判定图例**：【语义差异】= 同一音被记成不同类别/时值/结构；【一边有一边没有】；【语义一致】；【仅审美】。

### 3.0 二十维度判定总表

| # | 维度 | 判定 | 分级 |
|---|---|---|---|
| 1 | 倚音 / 装饰音表示 | **语义差异** | **P0** |
| 2 | 符杠 Beam 分组 | 语义差异（Swift 更规范） | P1 |
| 3 | 符干方向 | 语义一致（分组算法审美差） | P2 |
| 4 | 延音线 Tie / 圆滑线 Slur | tie 三类都画=一致；**弧方向语义差异**；slur 双端都无 | P1 |
| 5 | 连音 Tuplet（三/五连） | 语义一致（括号方向审美差） | P2 |
| 6 | 变音记号 / 等音拼写 / 还原号 | 语义一致（等音调边界待真机） | P2 |
| 7 | 休止符样式 | 语义一致（多小节休止双端同缺） | P2 |
| 8 | 时值体系 / 附点 / swing 切片 | **语义差异** | P1 |
| 9 | 符头形状 / articulation | 语义一致（双端都无演奏记号） | P2 |
| 10 | 色彩 / 趋近 / 避免音着色 | 语义一致，渲染层无回归 | P2 |
| 11 | 和弦符号排版 | **语义差异**（简写集/字号/颜色） | P1 |
| 12 | 谱号/调号/拍号/小节线/段落记号 | 谱号段一致；**小节号·乐句记号一边有一边没有** | P1 |
| 13 | 小节布局 / 换行 / 行宽 | 语义差异（定宽机制不同，结果相近） | P2 |
| 14 | 字体 / 字号 / 线粗 | 仅审美 | P2 |
| 15 | 引导音 / 级数标注 | **一边有一边没有**（Swift 增强） | P1 |
| 16 | 跨小节 / 切分 / 弱起 | 跨小节延音一致；**切分跨拍重记语义差异**；弱起 Swift 增强 | P1 |
| 17 | 缩放 / 滚动 / 分页 | 仅审美 / 交互差异 | P2 |
| 18 | 爵士特殊装饰（trill/fall/mordent 等） | 语义一致（双端都不画符号） | P2 |
| 19 | 多声部 / 和声块 | 语义一致（双端均单声部单音） | P2 |
| 20 | MusicXML 导入记谱保真 | **一边有一边没有**（原生倚音被丢弃） | P1 |

> 分级统计：**P0 ×1（#1）；P1 ×8（#2/#4/#8/#11/#12/#15/#16/#20）；P2 ×11（其余）**。

---

### P0 —— 记谱语义错误

#### #1 倚音 / 装饰音表示　【语义差异】· P0（头号问题）

**① 乐手话**
桌面版里**根本没有"小倚音"这种记法**：哪怕最快的 32 分经过句，每个音都是正常大小符头、带该有的符杠、占真拍子，视奏时就是一串数得清的快音符。iPad 版则定了一条全局规则：**任何 ≤ 一个 32 分（15 个时间单位）的音，一律从小节里抽走，改成一个小一号、单音还带斜杠、不占小节宽度的"倚音"，挂到它后面那个主音前面**。于是同一段 bebop 快句——桌面版是"两个并排的 32 分符头+双符杠"；iPad 是"前一个音被悄悄拉长一点，后面冒出一个 tiny 小音符贴在下一音前面，像滑一下的引子"。前者让你把快音在拍子里数清楚，后者暗示你"轻、短、不占拍、一带而过"——视奏与句法处理完全不同。

**② 工程定位**

*Swift —— 渲染成小号倚音（不占 ticks）*　`Views/SheetMusicView.swift:427-456`
```js
:436  let drawSlash = note.graceNotes.count == 1 ? "true" : "false";   // 单倚音才画斜杠
:439  new VF.GraceNote({ keys:[...], duration:gNote.duration, slash:drawSlash })  // 数学上不占小节 Ticks
:453  var graceGroup = new VF.GraceNoteGroup(graces, true);
:454  if (graces.length >= 2) { graceGroup.beamNotes(); }             // 多倚音才互相连杠
:455  n.addModifier(0, graceGroup);                                   // 挂到主干音
```
视觉时长字符串：单倚音 `"8"`、≥2 个 `"16"`，`Views/ContentView.swift:1721`。数据结构 `GeneratedGraceNote` / `GeneratedNote.graceNotes` 在 `CoreEngine/JazzEngine.swift:13-35`。

*Swift —— 倚音是怎么从旋律里被"剥离"的（关键全局规则）*　`Views/ContentView.swift:1518-1539`
```swift
:1523  if pNote.durationSlots <= 15 && pNote.midiPitch >= 0 {
:1525    if !globalEnriched.isEmpty && !globalEnriched[last].isRest {
:1526      globalEnriched[last].durationSlots += pNote.durationSlots   // ① 时值补回【前一个音】
:1527    }
:1529    pendingGraces.append(pNote.midiPitch)                         // ② 音高暂存，准备挂【下一个】主干音
:1534    ...EnrichedNote(... gracePitches: pendingGraces ...)          //    遇到后一主干音才挂上
```

*Swift —— 播放端（视觉不占时值，发声要借时间）*　`MidiPlayer/JazzMidiPlayer.swift:732-749`
```swift
:732  if !note.isTieEnd, !note.graceNotes.isEmpty {
:736    let graceEach = min(playDuration * 0.18, 0.12)   // 单倚音借主干 18%，封顶 0.12 拍(≈附点32分)
:740    sampler.startNote(gp, withVelocity: 50, ...)      // 倚音力度固定 50
:747    graceWindowBeats = graceEach * Double(graces.count)
:748    mainStartBeat += graceWindowBeats
:749    playDuration -= graceWindowBeats                 // 严格守恒，不拖拍
```

*Java —— 渲染层没有 grace，最短音也是正常音符*　`imp/gui/Stave.java`
- `drawNote(...)` 在 `:3384`；符头由 `:3405 unitImage = chooseImage(pitch, rhythmValue, noteColor, beamed, stemUp)` 选**固定图元、无缩放参数**，`:3471 g.drawImage(unitImage, ...)` 按原生尺寸贴——**没有任何 small / slash / grace 分支**；连最短的 32 分三连（10 slots）都在 `:3506` 画正常符头+正常符杠。
- 符杠数 `getNumBeams:3711-3757`：`≤12→3 杠、≤15→3（32 分）、≤20/24/30→2（16 分）、≤40/45/60→1（8 分）、≤80/90→1、else 0`。
- 全 `src/` 量 `grep -rniE "grace|acciaccatura|appoggiatura"`：仅 8 处命中——`HelpDialog.java:252`/`.form:478`（说明文案）、`TransformationTesting.java:39,41,583`（变换规则语法）、`Part.java:192`/`Phrase.java:194`/`Audio.java:37`（英文俚语 "ungracefully/disgrace" 误命中）。**0 个绘制分支**。
- 连名字都叫 gracenote 的加花，落地也是**真音符**：
  - Java：`transforms/My.transform:134-178` 用 `(subtract-duration 16 n1)` + `(set-duration 16 (transpose-chromatic ...))`，即从前一音**减一个 16 分（30 slots）**、把趋近音设为**真正的 16 分**（三连语境为 `16/3`=20 slots，见 `TransformationTesting.java:77-80`），总时值严格守恒；`HelpDialog.java:252` 明确要求 source-notes 与 target-notes 总时值相等。
  - Swift 同名加花 `TransformEngine/Transform+Defaults.swift:361-393`：匹配四分音，注释明示"时值分配 **40+80**"，即装饰音 **40 slots（八分三连）**+主音 80——40 同样 **>15，不会被剥离**，渲染为正常音（不是小倚音）。

**③ 差异机制 + 触发条件 + 建议**
- **机制**：Swift 在数据进入渲染前硬编码 `<=15 slots` 阈值，把短音"降级"为不占时值的装饰音；Java 对所有音一视同仁正常大小绘制。落入区间的具体时值：**32 分=15、32 分三连=10、32 分五连=12、64 分三连=5**（Java `Constants.java:77,82,95`），这些在 iPad 全变倚音。
- **触发频率（哪步最容易看到倚音）**：
  | 来源 | 是否产生 ≤15 | 结论 |
  |---|---|---|
  | **导入 MusicXML（含 32 分/32 分三连/五连）** | 是（15/10/12） | **最高频**，bebop head 类谱子导入即整片小倚音 |
  | `RhythmGenerator.generateTriplet(base:60, ratio 2:1:1)` | 30/15/15（`RhythmGenerator.swift:456-473`） | 低频、取决于调用方；四分(120)三连=60/30/30 不触发 |
  | GridQuantizer 最小锁 `ContentView.swift:4899`、splitCrossBeatDots `:4757+` | 10/12/15，但发生在剥离**之后** | 存活为正常 "32" 主干，**不**变倚音 |
  | Guide/Grammar/Transform/Learning 四链 | 否（≥30/40） | Grammar 趋近音=30（`GrammarNoteConverter.swift:920-934`）、切分 graceShift=30（`Syncopation.swift:49-52`）、Transform gracenote=40，均不剥离 |
  | 内置曲库 BuiltinMelodyLibrary | 否 | 数据只用 "8" 等长 token |
  > **一句话**：**导入一首带 32 分快句的 MusicXML 最容易看到一片小倚音；纯自动生成几乎不会。**
- **三层口径错位（复核任务书第 3 节，确实存在，建议拍板）**：
  1. "时间向后给、装饰向前挂"：被剥音 B 的时值补给**前音 A**（`:1526`），音高却挂**后音 C**（`:1529/1534`），播放又从**后音 C** 借 18%（`:736/749`）——三处归因分裂；A 被悄悄拉长最多一个 32 分，C 被倚音挤 18%。
  2. **前音是休止符时，这 ≤15 slots 直接丢失**：`:1525` 要求前一音 `!isRest` 才补偿，否则该时间既不补休止、也不进主干，网格时间凭空少一小块。
  3. **视觉时长 ≠ 发声时长**：画成"8 分倚音（单）/16 分双符杠（组）"，实际发声恒为 `min(主干×18%, 0.12 拍)`≈一个 32 分；快速长主干上"看着两个 16 分、听着挤成 18%"会偏赶。
- **建议（只建议，不改，待书面批准另开任务）**：
  - (a) **对齐 Java**：把 `<=15` 剥离取消，或缩小到"仅对引擎刻意标记的装饰音"生效；对真实 32 分快句（尤其 MusicXML 导入）应保留为正常 32 分（双符杠、占拍）。
  - (b) 修前音为休止符时的 slots 丢失（补回或显式对账）。
  - (c) 视觉 8/16 倚音与发声 18% 的偏差属装饰音惯例，可保留为增强，但**需乐手听感拍板**。

---

### P1 —— 明显视觉 / 记谱差异

#### #8 时值体系 / 附点 / swing 切片　【语义差异】· P1

**① 乐手话**：标准音符（全/二/四/八/十六/三十二）、附点、三连、五连、swing 的长短八分，两边数值都对得上。问题有两个：其一，桌面版能堂堂正正写出来的**最快音（32 分及其三连=10、五连=12）**，在 iPad 被降级成小倚音（同 #1）；其二，iPad 为了把碎音对齐网格，会把任意时长**往最近的标准值上"吸附"**（函数名叫 `getExactVexFlowDuration`，其实是区间吸附），极端情况下还会冒出桌面版**根本写不出来的"64 分""128 分"**——那是它自己切拍子切出的残渣。

**② 工程定位**
- Swift 区间吸附 `Views/ContentView.swift:982-1015`：如 `30-39→"16"`、`20-23→"16"_t3`、`12-14→"32"_t5`、`10-11→"32"_t3`；**越界残渣 `:1008 7-9→"64"`、`:1009 5-6→"64"_t3`、`:1010 default→"128"`**。白名单 `:4640-4641`（standardSlots=[480,360,240,180,120,90,60,30]；tupletSlots=[320,160,96,80,72,48,40,24,20,10]）。
- Swift 网格量化 `ContentView.swift:4829-5083`：非连音按 `grid=15` 吸附（`:4853`），兜底最小时值锁 `max(currentStart+15, sn.end)`（`:4899`）；跨拍拆附点 `splitCrossBeatDots(beatSize:120)`（`:4757`，调用在 `:1655`）。
- Java：`imp/Constants.java:62` 注释明示"no SIXTYFOURTH"（无普通 64 分），但 `:95 SIXTYFOURTH_TRIPLET=5` 存在；时值/连音/附点精确分数解析在 `imp/data/Duration.java:227-251`（`slots=WHOLE；分母>1 则 slots*=(分母-1)；duration=slots/(numerator*分母)`；五连先 ×4；附点循环 ×1.5）。

**③ 机制 + 触发 + 建议**：标准/附点/三连/五连/swing 双端等价（一致）。差异 1=同 #1 的 P0（32 分级被剥倚音）；差异 2（P2，自产 64/128 残渣）只可能来自跨拍残片或小节尾钳位，桌面版无此时值；差异 3（P2）区间吸附在边界吃掉几个 slots。**建议**：差异 1 对齐 Java（同 #1-a）；差异 2/3 列真机确认是否真出现 64 分符头，暂不动。

#### #2 符杠 Beam 分组　【语义差异】· P1（Swift 更贴近现代规范）

**① 乐手话**：一串快音里，桌面版**只在"两个音一样长"时才连横杠**——八分接十六分就各画各的小尾巴，老谱常满屏独立符尾；iPad 把同一拍里的八/十六/三十二分**混着也连成一杠**（副杠层数不同），是现代教科书的拍组写法，更容易一眼读出"这一拍有多少东西"。6/8、12/8 复拍子里，桌面版仍按四分拍两音一组连（老式/欠规范），iPad 按附点四分拍三音一组连。

**② 工程定位**
- Swift `SheetMusicView.swift:557-636`（makeBeams）：`:566 beamTicks=(6/8||12/8)?1536:1024`；`:621 可连杠=['8','16','32','64']`（混合时值可连，不要求等长）；`:610-613` 跨拍断杠；`:615-616` 同连音组不断；`:622-624` 休止符/不可连音断杠。
- Java `Stave.java:3042-3048`：
```java
boolean beamed = beamingNotes && sameBeat(i,inext)          // :3043
   && note.getRhythmValue() < 80                            // :3044 短于四分
   && nextNote!=null && isaNote(nextNote.getPitch())        // :3045-46 下一音非休止
   && sameStemDirection(note,nextNote,type)                 // :3047 音高差≤2
   && note.getRhythmValue()==nextNote.getRhythmValue();     // :3048 必须【等长】
```
`sameBeat :3762-3765` 恒为 `(i/BEAT)==(j/BEAT)`、`BEAT=120`——**硬按四分拍分组，不随拍号变**。

**③ 机制 + 触发 + 建议**：差异 A（等长才连）触发于八分接十六分的非等值快音串；差异 B（复拍子拍桶）触发于 6/8、12/8；差异 C（Swift 可连 64 分，Java 无 64 分概念）罕见。休止符断杠、拍边界断杠、连音组内不断，两边一致。**建议**：Swift 更规范，**保留**，不建议为 1:1 老谱观感而回退；64 分孤杠列真机确认。

#### #4 延音线 Tie / 圆滑线 Slur　【tie 三类齐全=一致；弧方向语义差异 P1；slur 双端都无】

**① 乐手话**：同音高的延音线，同小节、跨小节、换行**三种两边都画**。差在弧线朝向：桌面版的弧会**躲到符干的反方向**（符干朝上弧在符头下、朝下弧在符头上）；iPad 的**跨小节/换行**延音弧却**一律压在符头正上方**，不管音多高——高音到上加线时，硬塞在上方容易和加线/谱顶打架。至于连接**不同音高**、表示"一口气连贯吹"的圆滑线 slur，**两个版本都没有**。

**② 工程定位**
- 同小节：Swift `SheetMusicView.swift:643 new VF.StaveTie(...)`（VexFlow 自动定上下）；Java `Stave.java:3668-3671 drawTie(...)`。
- 跨小节（同行）：Swift `:1334-1365`（须 isTieStart/isTieEnd `:1341`、同 key `:1342-1344`，一条二次贝塞尔）；Java `:3311-3321 drawTie(startOfTie, STAVE_WIDTH+10, isStemUp(lastNote,type), g)`。
- 跨行（换行）：Swift `:1366-1394` 两段开口弧；Java 同走 `:3321`，并在 `:3323 startOfTie=leftMargin-10` 续画下行首段。
- 弧方向：Swift `:1346-1347 cmY=getYs()[0]-7` **恒在符头上方 7px**；Java `drawTie:4851-4880`：`stemUp→tieUnder(yPosition+20)`（弧在下）、`else→tieOver(yPosition-16)`（弧在上），**随符干翻转**。
- slur：Java `grep -rniE "slur" imp/gui imp/data` = **0**（"Slash chords" 是斜杠和弦文案）；Swift 连线均要求同 key（同音高），也无 slur。另核实 `imp/gui/CstrLine.java:25-32` 是"construction line 拍位构造网格线"，**不是连线**，未误用。

**③ 机制 + 触发 + 建议**：三类 tie 都画=语义一致；弧方向 P1 差异触发于高音区（上加线）跨小节延音、或符干朝上的低音延音。另注意 Swift **同小节用 VF.StaveTie（自动上下）、跨小节却恒上，自身两套策略不统一**。**建议**：真机抽查高音区跨小节 tie 是否与加线打架；若打架，把跨小节 `cmY` 改为按符干方向/音高翻转（对齐 Java），属渲染微调不改音乐含义。slur 若需要，两端都要新增，属功能增强。

#### #11 和弦符号排版　【语义差异】· P1

**① 乐手话**：谱上方的和弦字，iPad 把**根音写大（14pt）、属性写小（10pt）**，根音带升降时还把升降号"叠"到属性上方，像手写 lead sheet，而且字是**蓝色**；桌面版是**一行同字号黑色粗体**（Helvetica Bold），不分大小层级。更要注意**简写不一样**：iPad 把 "Dm7" 写成 **"D-7"**、"Cmaj7"→"C△7"、"Cm7b5"→"Cø7"、"Gdim"→"G°"、"Caug"→"C+"；桌面版只把大七 M7 转 △、半减七 m7b5 转 φ（还能在设置里关），其余照写（常显示 "Cm7" 而非 "C-7"）。两边都是合法爵士记法，但同首曲对照读会别扭，甚至误以为是不同和弦。

**② 工程定位**
- Swift：手绘 canvas `SheetMusicView.swift:1140-1214`（根音 -apple-system 14pt `:1163/1182`、升降/属性 10pt `:1166-1190`、堆叠分支 `:1184-1190`、固定蓝 `#007AFF` `:1147`、一音多和弦按比例排开 `:1198-1207`）；简写集 `jazzShorthand :1473-1534`（m7b5→ø7、dim→o、maj7→△7、m7→-7、aug→+；斜杠和弦保留 "/"）。
- Java：`Stave.java:3132-3138` 单一 `chordFont`（Helvetica Bold，黑色，选中态才红）一次 `g.drawString(toSymbols(...))`；`toSymbols :2618-2668` 仅 `toDelta`（M7→△ `:2661`）与 `toPhi`（m7b5→φ `:2643`），且受用户开关 `getDeltaStatus/getPhiStatus` 控制。

**③ 机制 + 触发 + 建议**：字号层级/颜色属 P2 审美（Swift 更接近商业 lead sheet，建议保留）；**简写符号集是 P1 语义差异**——同一和弦字符串两边印出不同字面。**建议**：与乐手拍板：要么 Swift 收敛到桌面版字面写法，要么接受爵士简写并在内部文档注明；不擅自改。斜杠和弦（C/E）双端都保留。

#### #12 谱号 / 调号 / 拍号 / 小节线 / 段落记号　【谱号段一致；小节号·乐句记号一边有一边没有】· P1

**① 乐手话**：开头的高音谱号、升降调号、拍号，**两边都只在最开头画一次，换行了也不重画**（和正规印刷谱"每行开头重画谱号"不同，但两边一致，读惯没问题）。每小节一道竖线、曲终一道粗终止线、段落切换一道双纵线，两边都有。差别在：桌面版还印**小节号**和**乐句记号**、段落处印**风格名**（如 "Bossa Nova"）；iPad 没有小节号和乐句记号，只在段落处印**橙色段落名**。而真正的**反复记号 𝄆𝄇、1./2. 房子、Segno/Coda、段落字母 A/B，两个版本都没有**——这份谱本来就不告诉你反复跳房。

**② 工程定位**
- Swift：谱号/调号/拍号仅首小节 `if(mIndex===0)` `SheetMusicView.swift:933-937`，换行不重画；末小节 END `:939-940`、section 前 DOUBLE `:941-942`；橙色段落名 Arial 11 bold `#FF9500` `:1012-1019`；渲染层 grep `repeat|volta|ending|segno|coda` = 0。
- Java：谱号/调号/拍号仅首行绘制块调用一次 `Stave.java:2363(drawClef)/2369(drawKeySig)/2375(drawTimeSig)`；换行后只 `drawStave :3282` + 行首 `drawBarLine(leftMargin) :3286`，**同样不重画**；`drawBarLine :4544-4564`，SECTION_END 置 doubleBar `:2879`；风格名 STYLE_MARK `:2803-2805/:3290-3295`、乐句记号 PHRASE_MARK（TimesRoman 24）`:2866-2871`、小节号 showBarNums `:3234-3238/:3298-3303`；全 Stave 无 segno/coda/volta/房子。

**③ 机制 + 触发 + 建议**："谱号/调号/拍号只画一次、换行不重画"双端一致（虽偏离印刷惯例，不判差异）。**一边有一边没有**：小节号、乐句记号（Java 有 Swift 无）；iPad 用橙色 sectionName 对应桌面风格名（近似）。反复/房子/segno/coda 双端同缺。**建议**：小节号/乐句记号对 lead sheet 影响小，可保持现状；若乐手需要反复/房子，那是新功能（VexFlow 有 Barline/StaveConnector 支持，成本低），本轮只记录不实现。

#### #15 引导音 / 音阶度数标注　【一边有一边没有：Swift 增强】· P1

**① 乐手话**：iPad 可在谱下方用小字标**级数**（这个音相对和弦是几级），或标"现在进入 G 大调段/这是某个 brick"，还带淡底色块，是"看着谱学级数"的辅助层（开了才显示，关掉就是干净谱）。桌面版的主谱面**不印这些数字**——它的分析在另一个 RoadMap 窗口里看。

**② 工程定位**
- Swift：级数文字 `SheetMusicView.swift:1112-1138`（Arial 12、谱线下 18px、白光晕+彩色上层）；数据注入 `generateAnalysisJS :259-277`；调性段色块/文字 `:984-1008/:1277-1325`；仅 `showAnalysis` 开启时绘制（`:267/:282`）。
- Java：主 Stave 绘制中无任何级数/罗马数字/度数文字（grep degree/Roman 命中均在 RoadMap 窗口与算法层）。

**③ 机制 + 建议**：Swift 独有叠加层，Java 分析在独立窗口。**红线遵守**：本条只确认"级数画在谱下、对位和弦起始拍"这一渲染行为，**不切换、不评价 chordDegrees 与 keySections 两套分析模式，不碰 Roadmap 算法**。**建议**：保留为 App 增强；真机确认密集小节级数文字不与符干/连音/倚音重叠（已有光晕+防撞）。

#### #16 跨小节音 / 切分 / 弱起　【跨小节延音一致；切分跨拍重记语义差异 P1；弱起 Swift 增强 P2】

**① 乐手话**：一个长音跨过小节线，两边都把它切成两个符头、中间加延音线，视奏一致。**切分（反拍起音）写法不同**：iPad 会把"反拍起、又跨过下一拍打点的附点音"**拆成两个拍对齐的音再用延音线连起来**（每一拍都对齐、好数）；桌面版直接在反拍位置画一个附点音、不拆。听感完全一样，只是谱面写法不同。**弱起**：iPad 对开头连续空和弦的小节会**补整小节休止**垫在最前面做对齐（注意补的是"整小节休止"，不是正规的"不完全弱起小节"）；桌面版旋律直接从第一个真和弦小节开始。

**② 工程定位**
- 跨小节切音+tie：Swift `ContentView.swift:1597-1606`（被小节线切断即置 isTieStart/End）；Java `MelodyPart.java:1000-1023 tieThis`（copy 成两段、setFirstTie），同源。
- 切分跨拍重记：Swift `ContentView.swift:4757-4820 splitCrossBeatDots`，调用 `:1655 beatSize:120`，`shouldSplit=!startsOnBeat && crossesBeat`（`:4766`），拆出拍对齐片段并打 tie（`:4794-4803`）；Java 仅跨小节才 tieThis（`:916 firstNoteRV>measureLength`），**小节内反拍跨拍附点不拆**，按真实 slot 位置直接画。
- 弱起：Swift `ContentView.swift:1556 leadingPickupCount`、`:1566-1571` 前置整小节休止；判定在 `CoreEngine/JazzEngine.swift:54-63`（开头连续"空和弦"小节数）；Java 无对应概念。

**③ 机制 + 触发 + 建议**：跨小节延音两边一致。切分重记 P1 触发于 Syncopation 生成的切分（`Syncopation.swift:49-57` 正拍音推迟 30）及一切反拍跨拍附点；听感相同、谱面写法不同，Swift 拍对齐更专业，**建议保留**。⚠️ **隐患 P1**：`splitCrossBeatDots` 硬编码 `beatSize:120`（四分拍），而 makeBeams 在 6/8、12/8 用 1536（附点四分=180 slots）——复拍子下两套拍口径不一致，可能把"附点四分组"从中切开；**建议真机用 6/8、12/8 验证切分/连杠是否错组，必要时 beatSize 按拍号 profile 取**。弱起 P2 保留为增强；若要正规"不完全弱起小节"两端都需新增。

#### #20 MusicXML 导入记谱保真（原生倚音 vs 生成剥离）　【一边有一边没有】· P1

**① 乐手话**：你从别的打谱软件导出一个标准 MusicXML，里面**本来就正规写了一个小倚音（grace note）**——iPad 导入时**把它直接删掉**，不画也不响，像没存在过；可反过来，若谱里有一个**真正占拍的 32 分快音**，iPad 又会**自作主张把它画成不占拍的小倚音**。一删一造，正好相反：该保留的装饰音丢了，该占拍的快音被降级。

**② 工程定位**
- 原生 `<grace>` 被丢弃：`Importers/MusicXML/MusicXMLParser.swift:185 case "grace": curNote?.isGrace=true`，`:425 if n.isGrace { return }  // M1 丢弃 grace，不占时`（在 endNote() 内，直接 return，不进 sounds、不渲染、不发声）。
- 占拍 32 分导入后又被剥：`Importers/MusicXML/MusicXMLQuantizer.swift:58 NOTE_SLOT[15]="32"`（导入 32 分先认成真 32 分）→ 汇入 `ContentView.swift:1523` 的 `<=15` 剥离 → 变 VexFlow GraceNote。
- 连音识别 `MusicXMLParser.swift:437` 只认三连（actualNotes==3 && normalNotes==2），**不认五连**；64 分三连=5 更无对应。
- Java：导入侧同样无 grace 绘制分支（见 #1），32 分正常大小绘制。

**③ 机制 + 触发 + 建议**（两类来源严格分开，勿混）：
- (a) **MusicXML 原生 `<grace>`**：Swift 在 `:425` 主动丢弃；而 VexFlow **明明有能力**用现成 GraceNote 管线（`SheetMusicView.swift:427-456`）正确渲染它，能力没用上。→ 判"一边有一边没有"。**建议（保留为增强）**：把 `:425` 改为"将 isGrace 音挂到下一主干音的 gracePitches"，复用现成 GraceNote 渲染——这才是"原生倚音正确渲染"。
- (b) **生成/量化把占拍短音剥成 grace**：即 #1 主体，按 #1 建议 (a) 不要把占拍 32 分剥成倚音。
- 另：导入连音识别应补五连（actualNotes==5）以对齐 Java 32 分五连=12。

---

### P2 —— 语义一致 / 可接受审美差异（逐条留档）

#### #3 符干方向　【语义一致】· P2
- **乐手话**："第三线（B 音）以上符干朝下、以下朝上，一组连杠统一方向"，两边都守这条中线；细微差别是 iPad 按**一组音的平均高度**定方向，桌面版按**组里第一个音**定再整组继承，跨中线的一组偶尔方向相反，但都在规范内。
- **证据**：Swift `SheetMusicView.swift:589-595` 组平均 `line>=3→dir=-1`，单音 `autoStem() :598/624`；经实跑 VexFlow `getKeyProps()` 钉死 **b/4（中线）= line 3**。Java `Stave.java:4888-4910 isStemUp`：TREBLE 谱 `pitch<71(B4)→朝上`；连杠继承上一音 `:3027`；`sameStemDirection:4917-4921` 要求相邻音高差 ≤2。
- **机制/建议**：分向线都是中线 B4（Swift line3 / Java pitch71），语义一致；仅跨中线连杠组的组方向算法不同（平均 vs 首音），且 Java 连杠多一道"音高差≤2"门槛（与 #2 等长规则同源）。P2，不需对齐，真机抽查跨中线组即可。

#### #5 连音 Tuplet（三/五连）　【语义一致】· P2
- **乐手话**：三连、五连两边都在音组上方画括号+"3"/"5"；**都不画六连、七连**。差别：桌面括号永远在上方，iPad 会智能放到符干反方向（低音组在上、高音组在下）省空间。
- **证据**：Swift `SheetMusicView.swift:470-556`（三连 ticks 和 768/1536/3072/6144、五连 1280/2560/5120 `:501-502`，允许异构时值、max/min≤4 `:517`，括号方向按组平均 `:537-538`，非法组"击杀"`:544-550`、孤音降级`:539-543`、无括号复活`:760-777`）；只产 tup=3/5（`ContentView.swift:989-1007`）。Java `Stave.java:2907-2973` 识别 32分→2分 的 TRIPLET/QUINTUPLET（只 3/5），`drawTupletBracket:4658-4731` 恒上方直角括号+数字、跨行拆两段；`Constants.java:73-82` 无六/七连常量。
- **机制/建议**：都只认 3/5、都画括号数字=一致；括号侧（P2）与异构组队宽容度（Swift 更宽容）属审美/能力差，保留 Swift。**未决**：Swift"击杀非法组"会不会在真实生成流误杀合法三连、出现无括号"裸三连音"，需真机/日志确认。

#### #6 变音记号 / 等音拼写 / 还原号　【语义一致】· P2（一处等音调边界待真机）
- **乐手话**：按调号自动选升/降写法；同一小节同音第一次显号、后面省、回到本位补 ♮——这些规则两边都有。
- **证据**：Swift 小节内记忆+还原号 `SheetMusicView.swift:389-413`（每小节重置 `:310`，还原号兜底 `:404-405`），候选拼写排序 `spellNote :1536-1581`、调号 alter `keyAlterations :1435-1464`、记号 `accSymbol :1466`，渲染前按和弦粗选升降 `ContentView.swift:1705-1715`。Java 数据层预算 `displayPart.makeAccidentals()`（`Stave.java:1025/2325`），绘制 `:3422-3433` drawImage sharp/flat/natural，调号序列 `drawKeySig:4376-4448`。
- **机制/建议**：规则同构（小节内省复+还原号+调号隐含，跨小节都清空）。**未决（勿臆断）**：等音调（如 Abm→关系大调 Cb，7 降）下"从升降回到本位"是否漏显 ♮，静态推断正确，需真机用 7 降调+还原 C 验一次。

#### #7 休止符样式　【语义一致】· P2
- **乐手话**：各时值休止符两边都标准、附点都带点；"一个横杠+数字表示休 N 小节"的多小节休止 **两边都没有**。
- **证据**：Swift `type:'r' SheetMusicView.swift:344`、手动附点 `:350`、排版期临时压窄休止符 glyph 宽 `:1044-1067`（w18/h14/q12/8=10/余8，format 后还原）；无多小节休止。Java `chooseImage :4951-5037` 按 rhythmValue 选 6 种休止图（>360 whole…10-15 三十二分），`<10→smallbox`，附点旗标统一补点；`Images.java:116-141/:167` 无多小节休止字形。
- **机制/建议**：时值→休止类别映射对齐（32 分边界都在 10-15 slot）；Swift 的"压扁休止符腾空间"是独有增强、无回归。多小节休止双端同缺，**建议都不加**（避免引入桌面版没有的记谱法）。32 分及更短休止的实际 glyph 与压扁效果列真机确认（与 #1 阈值联动）。

#### #9 符头形状 / 特殊 articulation　【语义一致：双端同缺演奏记号】· P2
- **乐手话**：实心/空心符头规则两边一样；但**重音 >、断音 ·、保持音 –、强音 ^、方头/叉号符头，两边谱面都不画**——这份谱只记音高时值，吐音强弱靠风格与听感。
- **证据**：Swift 主干 `new VF.StaveNote({keys:[单key]}) :381`、setKeyStyle 上色 `:383`；全文件 grep articulation/staccato/accent/tenuto/marcato/notehead/Fermata = 0。Java `chooseImage :5046-5137` 选 filledNoteHead/minim/semibreve（实/空心），`Images.java` 无叉号/方头；全 imp grep 仅命中 Tension.java 的算法词与帮助文案，无打印符号。
- **机制/建议**：双端同缺=非回归；上色对象都是符头本身。**建议**不补（保持一致）；未来若加，Swift 端 VF.Articulation 成本最低，属新功能。

#### #10 色彩 / 趋近 / 避免音着色　【语义一致，渲染层无回归】· P2
- **乐手话**：颜色约定两边完全同一套——和弦音黑、趋近蓝、色彩绿、外音红，倚音小音符也跟主干同色；tie 右段继承左段颜色。
- **证据**：Swift 色值 `SheetMusicView.swift:5-11`（#111111/#007AFF/#0E7C6B/#FF3B30）、符头 fill+stroke `:383`、倚音同色 `:446`、判色 `ContentView.swift:1727-1781`（和弦音最高优先黑；±1/±2 级进解决判蓝；自身色彩音判绿）。Java `Stave.determineColor:3831-3889`（外音且 approach→蓝 `:3853`；可解决音前一音 ±1 半音递归标蓝 `:3862-3881`）、`collectNoteColors:3772-3820`（tie 继承 `:3793-3801`）取预渲染彩色符头图。
- **机制/建议**：四类一一对应、上色对象都是符头、判定口径高度同构，**渲染层确认无回归**（未染符杠/符干/连线）。一处算法层微差（Swift 跨和弦趋近只查当前和弦、Java 查下一音落点和弦，`ContentView.swift:1754` 自承）属生成/整流层，本轮不动。

#### #13 小节布局 / 换行 / 行宽　【语义差异（机制不同，结果相近）】· P2
- **乐手话**：桌面版"一行固定排几小节、排不下就压缩、允许超一点点"；iPad"先按每小节内容算重量，再把一行等比拉开/压缩，一行排 2-4 个（屏越宽排越多）"。结果相近：密的小节给宽、松的给窄、太挤换行；iPad 对横竖屏更自适应。
- **证据**：Swift minWidth `Formatter.preCalculateMinTotalWidth :846-857`（兜底120，首小节 padding90/余40）、换行 `:876-890`（>900→4、>600→3、否则2；溢出/1.176 压缩判定）、行高190/步进170、整行等比 widthMultiplier 下限0.8、末行封顶 `:914-924`、密集右边距35→18 `:1041`。Java 真正定宽 `findSpacing :4043+`（按构造线数算宽、widthOver=240 允许挤压 `:4062`）、`setSpacingVars :2219-2242`、每行上限 `:4202-4205`、换行 `toNextLine :3243-3269`。（注：`BarDimensions.java` 仅服务"复杂度图表面板"，与谱面定宽无关。）
- **机制/建议**：纯工程/审美差异，无需对齐；真机确认不会"一行只剩 1 小节太稀"（末行封顶已处理）。

#### #14 字体 / 字号 / 线粗 / 谱线密度　【仅审美】· P2
- Swift：音乐字形=VexFlow **Bravura**（默认栈首，模板未切换；`:772` 的"3.0.9"注释过时，见第 2 章）；文字 -apple-system/Arial（和弦根14/属性10、级数12、段落名11）；行高190/步进170；走带高亮橙 #FFB300。
- Java：音乐符号=Images.java 预渲染 GIF（像素风）；文字 Helvetica Bold（和弦，字号=用户设置 `:629/6185`）、Helvetica 12（小节号）、TimesRoman 24（乐句记号）；5 线、lineSpacing=(5+15)*staveSpaceHeight `:2224`。
- **建议**：P2 记录即可；Bravura 比 Java GIF 现代圆润，属观感升级，保留。

#### #17 缩放 / 滚动 / 分页　【仅审美 / 交互差异】· P2
- **乐手话**：iPad 上下滚动（左右不滚）、转屏 150ms 后自动重排，但**禁双指缩放**；桌面版 StaveScrollPane 滚动仅作布局语义参考、不移植。
- **证据**：Swift WKWebView 纵向滚动 `:110-112`、`user-scalable=no :666`、onresize 防抖重排 `:1419-1426`、走带黄金分割视口自动追踪 `:751-755`；Java StaveScrollPane。
- **建议**：P2，固定字号看谱是刻意设计；iPad mini/11/13 × 横竖 6 组下一行小节数(2/3/4)与是否截断列真机确认。

#### #18 爵士特殊装饰（trill / fall / doit / scoop / turn / mordent）　【语义一致：双端都不画符号】· P2
- **乐手话**："tr 颤音、波浪、fall/doit 滑音"这类**符号**两边谱面都不画；所谓"装饰"两边都用**实际音符**表达——桌面版把 mordent/trill 展开成**一排正常大小的小音符**，iPad 则把其中 ≤15 slot 的极短音画成**小倚音**（边界归 #1）。
- **证据**：Swift SheetMusicView.swift grep trill/fall/doit/scoop/turn/mordent/Ornament = 0，唯一装饰化绘制是 GraceNote（`:439-455`）。Java 全 imp grep 仅命中 `TransformationTesting.java:200(mordent)/:544(below-trill-from-small-note)/:583`，其 target-notes 全是 `transpose-diatonic/set-duration` 的**普通音符序列**（mordent=主-邻-主 `:217-221`、below-trill=一串 8/3 三连 `:552-555`），无装饰符号绘制分支；Images.java 无对应字形。
- **机制/建议**：符号层双端同无=语义一致；同一"装饰"的两种呈现（Java 全尺寸音串 / iPad 小倚音）其边界由 #1 主责，本条只确认"无装饰符号"成立。

#### #19 多声部 / 和声块（双音）　【语义一致】· P2
- **乐手话**：这是单音旋律主线，没有双音/和声块，两边一致。
- **证据**：Swift 主干 StaveNote `keys` 恒为单元素数组（`SheetMusicView.swift:381`），GraceNote 同样单 key（`:439`），跨小节 tie 仅同 key 才画（`:1342-1344`），无多键/TabNote/第二声部；Java MelodyPart 每 slot 一个单音 Note，chooseImage 按单 pitch 选图，Images.java 无双符头字形。
- **建议**：单声部是产品定位（萨克斯主旋律），无需处理。

---

## 4. 「一边有一边没有」清单

### 4.1 Java（桌面版）有、iPad 没画
1. **小节号**：每小节上方数字，`Stave.java:3234-3238/:3298-3303`（showBarNums）。
2. **乐句记号 PHRASE_MARK**：TimesRoman 24 文字，`Stave.java:2866-2871`。
3. **段落风格名文字**：STYLE_MARK+styleName（如 "Bossa Nova"），`Stave.java:2803-2805/:3290-3295`（iPad 仅有橙色 sectionName，语义近似、来源不同）。
4. 预渲染**彩色符头 GIF**（黑/绿/蓝/红四套图）——iPad 用 setKeyStyle 实时改色，视觉等价、机制不同，不算缺口。

### 4.2 iPad（Swift）有、Java 主谱面没有
1. **小号倚音 GraceNote**（斜杠、不占 ticks）：`SheetMusicView.swift:439-455` + 剥离规则 `ContentView.swift:1518-1539`。⚠️ 这是 #1 的 P0——桌面版对应物是正常大小的 32 分音符。
2. **音阶级数 / 调性段文字叠加 + 底色块**：`SheetMusicView.swift:1112-1138/:1277-1325`（Java 分析在独立 RoadMap 窗口）。
3. **和弦根/属性双字号 + 升降号堆叠排版**：`:1163-1190`（Java 单字号横排）。
4. **爵士简写符号集**：m→-、dim→°、aug→+、maj→△ 等，`jazzShorthand :1473-1534`（Java 仅 M7→△、m7b5→φ 且可关）。
5. **走带高亮 + 自动滚动追踪当前音**：`:726-757`、CSS `.highlighted-note :682-690`（Java 只有播放指示线 drawPlayLine，机制不同）。

### 4.3 两边都没有（不是 iPad 做漏，双端同缺）
反复记号 𝄆𝄇 / 1.2. 房子 / Segno / Coda / 段落字母；多小节休止 𝄽；articulation 全套（重音 >、断音 ·、保持音 –、强音 ^）；trill/fall/doit/scoop/turn/mordent **符号**；fermata 延长号；**slur 圆滑线（不同音高）**；特殊符头（叉号/方头/打击乐）；第二声部 / 双音和声块；六连 / 七连记法。

---

## 5. 未决问题 / 需 Xcode GUI 人工真机确认项（静态读码无法定论）

> 本轮按要求**不运行 xcodebuild、不启动 Java GUI、不做截图**；以下须在 Xcode GUI 真机/模拟器由人工确认，**不得据静态推断臆断**。

**P0/P1 相关（建议优先）**
1. 导入一首含 32 分经过句的 MusicXML（bebop head），目视确认 32 分/32 分三连/五连是否真被画成一片小倚音（静态链路已推导"会"）。
2. 导入含**原生 `<grace>`** 的 MusicXML，确认该倚音被删后的实际观感（是否有用户曲谱依赖 grace）。
3. 前音为休止符时 ≤15 slots 丢失（`ContentView.swift:1525`），在走带/小节总长上是否可闻地"抢拍"。
4. 视觉"8 分（单）/16 分（组）倚音"与发声恒为 `主干×18%（封顶0.12拍）` 的偏差，在慢板长主干上是否过赶——**需乐手听感拍板**。
5. 跨小节/跨行 tie 恒在符头上方（`SheetMusicView.swift:1346`）在高音上加线区是否与加线/谱顶拥挤；跨行两段弧衔接是否自然。
6. **6/8、12/8 复拍子**下 `splitCrossBeatDots(beatSize:120)` 与 `makeBeams(beamTicks:1536)` 拍口径不一致，是否导致切分/连杠错组。
7. Swift"击杀非法连音组"（`:544-550`）+ 无括号复活（`:760-777`）是否在真实生成流误杀合法三连，出现无括号"裸三连音"。
8. `getExactVexFlowDuration` 越界兜底（`:1008-1010`）是否真在屏上冒出桌面版没有的 "64"/"128" 符头。
9. 和弦爵士简写（C-7/C△7/Dø7/G°）蓝色双字号 vs 桌面黑色字面，是否造成视奏混淆——需乐手拍板。

**P2 / 布局观感**
10. iPad mini/11/13 × 横竖 6 组尺寸下，一行小节数(2/3/4)与末行是否过稀/截断；Bravura 实际观感、行高 190/步进 170 的疏密是否合适视奏距离。
11. 等音调（Abm/Cb 等 7 降调）下"该显 ♮ 是否漏显"（`SheetMusicView.swift:404-405` 边界）。
12. 级数/调性文字在密集小节是否与符干/连音/倚音重叠；32 分及更短休止 glyph 与"压扁宽"效果。
13. VF.Tuplet 括号 location=-1/1 的实际上下表现；VexFlow 单音 autoStem 在极端加线音的默认方向。
14. VexFlow 精确小版本（现只能确证 4.x + 默认 Bravura），如需锁定可查包内构建信息或在 Safari 开发者工具打印 `Vex.Flow.VERSION`（iOS 16.4+ 已开 isInspectable，`SheetMusicView.swift:117-119`）。

---

## 6. 附录

### 6.1 本轮实际 grep / 核验台账（合并三 shard + Organizer）
- Java（`src/imp`）：
  - `grep -rniE "acciaccatura|appoggiatura" imp/gui imp/data` → **0**。
  - `grep -rniE "grace"` → 仅 `HelpDialog.java:252`、`HelpDialog.form:478`（文案）；扩到全 src 另含 `TransformationTesting.java:39,41,583`（变换语法）及 3 处英文俚语误命中；**0 绘制分支**。
  - `grep -rniE "slur" imp/gui imp/data` → **0**（"Slash chords" 为斜杠和弦文案）。
  - `Stave.java` 内 `grace/slur/trill/mordent/doit/scoop/fall/ornament` → **0**。
  - 六连/七连 `sextuplet/septuplet` → 0（`SIXTH_BEAT` 是 swing 六分，非六连）；`tuplet/triplet/quintuplet` 在 Stave.java 命中 93 处。
  - articulation/装饰：`\b(staccato|tenuto|marcato|sforzando|trill|mordent|doit|scoop|fermata|volta|multiMeasure)\b` → 仅 TransformationTesting 变换语法与帮助文案，无渲染符号；`Images.java` 40 个字形方法中无 articulation/装饰/多小节休止。
- Swift（`Real imPro/`）：
  - 渲染文件 SheetMusicView.swift grep articulation/staccato/accent/tenuto/marcato/notehead/volta/segno/coda/multiMeasure/slur/Fermata/Ornament/TabNote/trill/fall/doit/scoop/mordent → 无任何对应 API（仅 StaveNote/GraceNote/StaveTie/Accidental/NoteHeadColors 常量名）。
  - 全工程 .swift 同名搜索命中 TransformEngine（mordent 等=变换规则名）、LSTM（repeating）等，均非渲染，已排除。
  - grace 产出点全量定位：`ContentView.swift:1523/1534/1721-1724`（剥离与渲染）、`Transform+Defaults.swift:361-393`（gracenote=40+80）、`:603` grace-approach、`GrammarNoteConverter.swift:920-934`（趋近=30）、`Syncopation.swift:49-52`（=30）、`RhythmGenerator.swift:456-473`（base60/2:1:1 出 15）、`MusicXMLParser.swift:185/425`（原生 grace 丢弃）、`MusicXMLQuantizer.swift:58-60`（32 分→15）。
  - vexflow-min.js：Bravura=5、Gonville=9、Petaluma=4、DefaultFontStack=1、`RESOLUTION:16384`；默认栈 `W=[X.Bravura,X.Gonville,X.Custom]`；无 version/RELEASE/banner。
- 关键行号均经 Organizer 二次开卷复核：MusicXMLParser `:185/:425`、ContentView `:1004-1010/:1523-1534`、JazzMidiPlayer `:732-749`、Stave.java `:3042-3048/:3762-3765/:4851-4880/:2363-2375/:3282-3286/:3132-3138`。

### 6.2 读过的文件清单
- **Swift**：`Views/SheetMusicView.swift`（全文 1-1583）、`Views/ContentView.swift`（:982-1015、:1495-1815、:4632-5083 等）、`CoreEngine/JazzEngine.swift`、`MidiPlayer/JazzMidiPlayer.swift`、`Grammar/GrammarNoteConverter.swift`、`Grammar/TupletSanitizer.swift`、`TransformEngine/Transform+Defaults.swift`、`TransformEngine/MelodyTransformAdapter.swift`、`TransformEngine/MusicTools.swift`、`Rhythm/RhythmGenerator.swift`、`Rhythm/Syncopation.swift`、`Importers/MusicXML/MusicXMLParser.swift`、`Importers/MusicXML/MusicXMLQuantizer.swift`、`BuiltinLibrary`（token 抽查）、`Roadmap/JazzSong.swift`、`vexflow-min.js`（字体/版本特征）。
- **Java**：`imp/gui/Stave.java`（主流程 paintComponent/drawPart :2299-3384、drawNote :3384-3563、getNumBeams/drawStem :3699-3765、determineColor/collectNoteColors :3772-3890、谱号调号拍号 :2335-2405、小节线/段落 :2795-2895/:3225-3334、tie :4851-4881、tuplet 括号 :4658-4731、休止符 :4930-5170、布局 findSpacing/setSpacingVars :2219-2242/:4043+）、`imp/data/Duration.java`（全文）、`imp/data/Coloration.java`（全文）、`imp/data/Note.java`、`imp/data/NoteSymbol.java`、`imp/data/MelodyPart.java:995-1024`、`imp/data/SlottedNote.java`、`imp/data/RhythmCluster.java`、`imp/Constants.java:39-120`、`imp/gui/ChordPane.java`（全文）、`imp/gui/BarDimensions.java`（全文，确认仅服务复杂度图）、`imp/gui/CstrLine.java`（确认是构造网格线）、`imp/gui/Images.java`（字形清单）、`imp/lickgen/transformations/TransformationTesting.java:39-98/198-238/540-587`、`imp/gui/HelpDialog.java:252`、`transforms/My.transform:134-180`。

### 6.3 探针 / 运行说明（诚实记录）
- **阶段 4（同种子并排截图、Java 桌面并排、/tmp 数据探针）按用户本轮要求整体取消，未做**；未启动 Java 桌面版，未运行 xcodebuild。
- 唯一一次**只读静态核验**：为钉死 VexFlow 符干方向的音位坐标，用本机 node 直接加载包内 `vexflow-min.js`、以最小 window/document shim 调用 `StaveNote.getKeyProps()`，确认 **b/4（中线）= line 3**（与 Java pitch 71 中线一致）；该临时脚本（/tmp/vftest*.js）**用后即删**，未触碰任何生产文件、未联网、未生成产物。此为库 API 静态校验，非阶段 4 的运行时/截图探针，特此注明。

### 6.4 落地红线（若未来要改，才需遵守；本轮未改任何代码）
- 本报告所有"建议"均**未实施**。任何改动须另立项、整文件备份（含 SHA1）、旧码中文原位封存、逐 hunk diff、用户书面批准、Xcode GUI Build 0 error、iPad mini/11/13 × 横竖 6 组截图与真机回归。
- 不碰生成/算法/引擎/整流与任何默认值；不翻 Roadmap 两套分析（analysisDisplayMode）、Fractal/ThemeWeaver/G8 等暂停项；不新增付费点/顶栏。
- App 内 UI 文案一律英文、**不得出现 "Java" 字样**（本内部报告除外）。

---

## 7. 勘误与重大修正（2026-10-12 第三方审核 + 二次数据流复核）

> 报告发布后，经另一位 AI 审核、并由主 AI **二次回源码做端到端数据流复核**后补记。共 5 条：**7.1 是对 P0 归因的重大修正（推翻原报告"导入最易产生倚音"结论）**；7.2–7.3 为审核者提出的表述与边界补强；7.4 修正真机验证路径；7.5 为版本确认方法。

### 7.1 【重大修正】P0 小号倚音在「MusicXML 导入」链路不会发生 —— 原报告归因错误

**乐手话**
原报告称"导入含 32 分快句的谱子，那串 32 分会整片变成小号倚音"——**经端到端复核，这个场景不会发生**。导入曲里 32 分就是正常大小、占拍子的 32 分音符（与桌面版一致）。小号倚音只可能在你点"生成 solo"时、由生成算法内部极少数节奏路径产生，范围比原报告所述窄得多。

**工程定位与数据流（逐环证据）**
1. 导入接线 `Views/ContentView.swift:634-635`：`let json = MusicXMLImporter.libraryForApp(...)` → `let lib = try BuiltinMelodyLibrary.load(from: json)`；`:648` 把 `bs.melody` 存入旋律表；打开歌曲时 `:923 builtinLibrary?.melody(for:)` 直接返回该旋律。**导入曲走"曲库 DTO 解码"，不进生成管线。**
2. DTO 音符结构 `BuiltinLibrary/BuiltinMelodyLibrary.swift:153-160`：`NoteDTO` 仅含 `pitch / isRest / duration / isTriplet / isTieStart / isTieEnd`，**没有 graceNotes 字段**。
3. DTO→主类型，同文件 `:217-229 makeNote`：逐字段映射为 `GeneratedNote`，**不设置 graceNotes（默认 `[]`）**，全函数无 ≤15→grace 逻辑；`:189-215 makeMeasure` 直接组装 `GeneratedMeasure`。
4. 渲染 `Views/SheetMusicView.swift`：`:428 if !note.graceNotes.isEmpty` 对导入音为 false → 不产生 GraceNote；`:381 new VF.StaveNote({duration:'32'})` 画**正常大小 32 分**。播放端 `MidiPlayer/JazzMidiPlayer.swift:732` 同样因 graceNotes 空而跳过借时、正常发声。

**对比：剥离规则只在生成侧**
`ContentView.swift:1518-1539` 的 `≤15` 剥离，输入是 `finalPhysicalNotes`（Guide/Grammar/Transform/Learning 产物）；导入曲不产生 `PhysicalNote`、不进入该循环。

**修正后的 P0 结论**
- 导入链路（含内置经典曲库）：占拍 32 分（15）/32 分三连（10）/五连（12）**正常显示、正常播放，与 Java 语义一致**。
- 小号倚音仅在**生成链路** `PhysicalNote.durationSlots ≤ 15` 时出现；已查实生成侧来源主要是 `Rhythm/RhythmGenerator.swift:456-473`（base 60、2:1:1 会出 15），低频、取决于调用方；其余生成路径最短 30/40 slot。
- 原报告 3.0 总表把 #1 触发场景描述为"导入 bebop head"应据此更正；#1 的 P0 机制（生成侧剥离）仍成立，但**实际可见概率低、且不影响导入曲**。
- 此为静态数据流结论，建议仍以真机一次导入作为最终判决（见 7.4 与第 5 章）。

### 7.2 【表述严谨】P0"丢音"：丢的是时值，不是音高（审核者提出，已核实）
`ContentView.swift:1525-1529`：短音音高在 `:1529` **无条件**进入 `pendingGraces`，后面有主干音就会画成倚音、播放发声——**音高没丢**。未被补偿的是时值：仅当 `:1525` 前音非休止时才把 slots 补回前音；前音为休止（或短音在序列最开头、`:1525 !isEmpty` 失败）时，这 ≤15 slots 不进任何音的时值账。
- 故原报告"≤15 slots 直接丢失"应改为："**音还在（变倚音），但时值在『前音为休止 / 序列开头』时少补偿一块，可能造成抢拍或切分错位**"。该规则仅在生成侧（见 7.1）。

### 7.3 【边界补强】剥离规则的三个边界（仅生成侧；审核者提出、主 AI 逐条核实）

| 情形 | 数据层 slots | 视觉 | 播放 | 净结果 |
|---|---|---|---|---|
| 短音**前**是休止 / 在最开头（`:1525` 条件失败） | 少补偿 ≤15 | 画成倚音 | 会响 | 时值账少一块，可能抢拍 |
| 短音**后**紧跟休止（休止走 else，`:1534` 把 graces 挂到休止） | 已处理 | **休止不画倚音**（`SheetMusicView.swift:337` rest 分支无 grace 代码；grace 绘制 `:427-456` 在非休止分支内） | **倚音仍发声**（`JazzMidiPlayer.swift:732` 无 `!isRest` 排除，`:740 startNote`） | 视听不一致：看不见、听得见 |
| 短音在**整段最末尾**（for `:1539` 结束后 `pendingGraces` 无消费；grep 确认该变量仅 `:1520/1529/1534/1537` 四处） | 可能已补前音 | 不画 | 不响 | **音高彻底丢失** |

### 7.4 【验证路径修正】"导入一个文件顺带验全部"不可行：导入与生成是两条管线
审核者建议"真机导入 MusicXML 顺带验 #3 休止抢拍、#8 64 分符头"——经核实：
- **#3（`:1525` 少补偿）、#8（`ContentView.swift:1008-1010` getExactVexFlowDuration 越界出 "64"/"128"）均属生成链路**；导入走 Quantizer 的 `NOTE_SLOT`（`MusicXMLQuantizer.swift:57-59`，最小仅到 15/"32"，无 64/128），**导入无法触发这两条**。
- 故真机验证须分两组：①**导入组**——验 7.1（32 分是否正常大小）、原生 `<grace>` 丢弃（#20）、6/8 连杠；②**生成组**——在 App 内生成 solo，才可能验 #1 倚音、#3、#8 及 7.3 三边界。

### 7.5 【版本确认】VexFlow 精确小版本
现仅能静态确证 **4.x + 默认 Bravura**（见第 2 章）。需 100% 钉死时，在 iPad 设置 → Safari 打开 Web 检查器（iOS 16.4+ `isInspectable`，`SheetMusicView.swift:117-119`），于 Mac 的 Safari 开发者工具执行 `Vex.Flow.VERSION`。
