# IDEA_trading_port.md — Trading 移植任务事实库（接手前必读）

> 本文件是「Impro-Visor Trading → Real imPro」任务的**事实基线与任务书**。它建立在项目总事实库 `IDEA.md` 之上：读我之前，先读 `IDEA.md`（项目使命、slot 口径、编译命令、方法论、已拍板设计都在那里）。
> 行号会随提交漂移，**正式引用前以你现读源码为准**。本文件给的是路径、架构、常量、已完成项与本期边界。
> **本阶段只做离线可行性分析与设计，不写实现代码、不改 `Real imPro/` 任何现有文件（见 `SOUL_trading_port.md` 红线）。**

---

## 一、你要回答的核心问题（逐字来自用户）

> "这个视频里详细介绍了 Impro-Visor 这个软件的实时输入音符以及对应的 Trading 功能，你帮我看看这个视频的介绍，然后结合这个软件的源代码（`/Users/onlyonear/Desktop/Impro-Visor-master`），分析一下这个 Trading 功能是否可以**完美地移植**到我的 iOS 应用内，让 MIDI 键盘连接 iPad，实现和视频中一样的**实时输入**以及**'互相用音乐对话'**的那种效果？"

你必须：① 自己看视频；② 自己读 Java 源码；③ 自己读 RealimPro Swift 现状；④ 独立给出可行性结论与离线设计。前一任 AI 的结论（见第七节）只是**待复核线索**。

---

## 二、关键路径

| 项 | 路径 |
|---|---|
| Java 原版源码根 | `/Users/onlyonear/Desktop/Impro-Visor-master/` |
| Java 源码包 | `/Users/onlyonear/Desktop/Impro-Visor-master/src/imp/` |
| 教学视频（已下载，本地） | `/Users/onlyonear/Desktop/Improlyze/Trading教学视频_Impro-Visor_Xfk8vR2vsb4.mp4`（约 70MB，时长约 17 分 26 秒，360p） |
| 视频原始链接 | `https://youtu.be/Xfk8vR2vsb4`（YouTube：Impro-Visor 作者 Bob Keller 演示） |
| Swift 工程根 | `/Users/onlyonear/Desktop/Improlyze`（scheme/target：`RealimPro`） |
| Swift 生产目录 | `/Users/onlyonear/Desktop/Improlyze/Real imPro/`（路径含空格，命令行加引号） |
| 项目总事实库 | `/Users/onlyonear/Desktop/Improlyze/IDEA.md`（必读） |
| 角色/红线 | `/Users/onlyonear/Desktop/Improlyze/SOUL_trading_port.md` |

### 如何"看"这个视频（无 GUI 也能分析）
- 直接用本地视频文件，不要依赖联网下载。
- 抽帧看界面（示例，帧时间点按你需要调整）：
  ```bash
  mkdir -p /tmp/tradeframes
  ffmpeg -y -ss 30  -i "/Users/onlyonear/Desktop/Improlyze/Trading教学视频_Impro-Visor_Xfk8vR2vsb4.mp4" -frames:v 1 /tmp/tradeframes/f30.jpg
  # 多抽几个时间点：120/240/360/480/600/720/840/960 秒
  ```
  然后用 Read 工具打开 jpg 看界面。
- 提取音频转写（可用工程内可用的音频解析能力，或 ffmpeg 提音后转写）：
  ```bash
  ffmpeg -y -i "/Users/onlyonear/Desktop/Improlyze/Trading教学视频_Impro-Visor_Xfk8vR2vsb4.mp4" -vn -ac 1 -ar 16000 -b:a 64k /tmp/trade_audio.m4a
  ```
- 已知画面要点（仍需你亲眼看）：Mac 跑 Impro-Visor + Casio PX-5S 键盘 + 监听音箱；示例曲 Autumn Leaves（G 小调）；后半段 Trading 对话框；结尾用口风琴 + Pitch Tracker（音频→MIDI，本期不做）。

---

## 三、Java Trading 代码地图（权威来源是源码，下面是入口）

### 1. 轮流调度与应答核心（`src/imp/trading/`）
| 文件 | 作用 |
|---|---|
| `ActiveTrading.java` | **主状态机/调度器**：以 Sequencer 的 slot 位置为时钟，管理"谁先开始、每轮小节数、处理提前量、音量"，在 USER_TURN / PROCESS_INPUT / COMPUTER_TURN 之间切换（触发器栈）。关键常量在 `:89-92`：`DEFAULT_TRADE_LENGTH=4`（小节）、`DEFAULT_TRADE_MODE="Transform"`、`DEFAULT_VOLUME=80`；构造里 `slotsForProcessing = BEAT`（=120 slot，约 1 拍处理窗口）。 |
| `TradingResponseController.java` | 异步生成控制器（Future）；`desiredFinishDuration = 20000000`（20ms，`:58`），期望在边界前极快生成回应。 |
| `TradingResponseInfo.java` | 各类回应模式的**共享生成算法**（rectify、transform、grammar、abstract、memorize 等），是体量最大的逻辑类（约 56KB）。 |
| `TradeListener.java` | 回合事件监听接口。 |
| `PhraseTable.java` | "Chop & Memorize" 的片段记忆/重组表（约 130 行）。 |
| `ContourGenerator.java` | 旋律轮廓生成（AA/AB/BA/BB 等轮廓形态）。 |
| `TradingDialog.java`（+`.form`） | Swing 对话框（UI）："Who goes first?"、"Trade length (bars)"、"Processing beats"、"Lead"、"Tempo"、"Response Volume"、Grammar/Transform 选择器等。**移植参考其选项，不照搬 Swing。** |
| `tradingResponseModes/*.java` | 11 种回应模式（见下）。 |

### 2. 回应模式（`src/imp/trading/tradingResponseModes/`）
- `TradingResponseMode.java`：模式接口；`BlockResponseMode.java`：阻塞式基类（等信号后在边界一次性生成）。
- 视频核心的 7 种"对话"模式：
  1. `RepeatTRM` — Repeat（原样回敬）
  2. `RepeatAndRectifyTRM` — Repeat and Rectify（节奏照抄、音高修正到和弦）
  3. `ModifyAndRectifyTRM` — Modify and Rectify（倒影/逆行 + 修正）
  4. `AbstractMelodyTRM` — Abstract Melody（提取轮廓→换音高重新具象）
  5. `TransformTRM` — Transform（默认，用某大师 `.transform` 规则改写）
  6. `GrammarTRM` — Grammar（生成语法独立造句）
  7. `ChopAndMemorizeTRM` — Chop and Memorize（切碎记忆重组）
- 节奏练习类（本期列二期）：`MemorizeMotifsTRM`、`CorrectRhythmTRM`、`SuggestRhythmTRM`、`RhythmHelperTRM`。

### 3. 实时 MIDI 输入与时钟（`src/imp/midi/`）
| 文件 | 作用 |
|---|---|
| `MidiManager.java` | 枚举/打开 `javax.sound.midi` 输入输出设备、Transmitter/Receiver 接线。 |
| `MidiRecorder.java` | **实时录音器**：实现 `Receiver`，监听 note on/off，**从 Sequencer 读 tick 位置**换算成 slot，按 slot 量化写入 MelodyPart；含 latency 偏移补偿。 |
| `MidiNoteListener.java` | 音符事件回调接口。 |
| `MidiSynth.java` | 播放合成器：内部是一个 `javax.sound` **Sequencer**；Trading 里回应通过 `PlayScoreCommand` 在（新建的）Sequencer 上按 slot 对齐播放。 |
| `com/PlayScoreCommand.java` | 把 Score 序列化成 MIDI 并播放（约 454 行）。 |

### 4. 被复用的生成 / 数据类
- 变换：`src/imp/lickgen/transformations/{Transform,Substitution,Transformation,Evaluate}.java`（S-表达式守卫条件 DSL，Evaluate 约 1500 行）。
- 文法：`src/imp/lickgen/Grammar.java`（注意不是 LickGen）。
- 音高修正：`src/imp/com/RectifyPitchesCommand.java`（约 383 行）。
- 抽象旋律：`src/imp/data/AbstractMelodyExtractor.java`（约 553 行）。
- 数据模型：`src/imp/data/{Note,Chord,MelodyPart,ChordPart,Score}.java`。
- S-表达式工具：`src/polya/`（Polylist 等，约 2800 行）。
- 规模参考：`trading` 包 26 文件/约 8,468 行（含 Swing UI，纯逻辑约 4,600 行）；全仓 Java 约 35.7 万行。

### 5. 数据流（你要在报告里自己画一遍并核实）
```
MIDI 键盘 → MidiManager(设备) → MidiRecorder(读 Sequencer tick，按 slot 量化) → MelodyPart(用户乐句)
                                    ↑ 时钟来自 Sequencer（同时播放伴奏）
ActiveTrading(slot 边界状态机)：USER_TURN → PROCESS_INPUT(边界前约 1 拍生成) → COMPUTER_TURN
   → TradingResponseController(Future) → 某个 TradingResponseMode → TradingResponseInfo
   → 调用 Transform / Grammar / rectify / AbstractMelodyExtractor / PhraseTable
   → 回应 MelodyPart → PlayScoreCommand / MidiSynth(Sequencer) → 发声
```
**你要特别确认的关键点**：桌面端把"播放伴奏的 Sequencer"当作绝对主时钟，录音、轮流、回应发声全部对齐它；iOS 没有等价的 `javax.sound Sequencer`，这部分必须用 CoreMIDI + AVAudioEngine 重新设计，而不是翻译。

---

## 四、RealimPro（Swift）现状地图（路径以现读为准）

### 已具备（约 140 个 Swift 文件，需你逐个打开核实）
- 播放引擎：`Real imPro/MidiPlayer/JazzMidiPlayer.swift`
  - `AVAudioEngine` + **4 个 `AVAudioUnitSampler`**（旋律/贝斯/鼓/钢琴）+ 共享混响，加载 `ChoriumRevA.sf2`。
  - 已有 **slot 时钟锚点**：`tempoAnchorEffectiveNs / tempoAnchorSlot`，且 slot 口径与 Java 一致（120 slot=1 拍、480 slot=4/4 小节）；已有 swing 弯曲（`swingWarpBeat`）。
  - **现状是"预渲染整段再播"**：`playWithAccompaniment(...)` / `playSoloTrackAsync` 把 solo/伴奏排好后播放；Trading 需要的是"边界处才生成、边播边动态排"。
- 伴奏型引擎：`Real imPro/MidiPlayer/StyleEngine/`（Style/贝斯/鼓/和弦渲染）。
- Transform 引擎：`Real imPro/TransformEngine/`（`JavaAlignedTransformEngine / Evaluate / Substitution / Transform / Transformation / NCP / Scorer / TransformRNG / MusicianRegistry` 等，**已较完整移植**）。
- Grammar 引擎：`Real imPro/Grammar/`（`Grammar / GrammarStrategy / GrammarNoteConverter / GrammarLickGlue(含 rectify*) / NoteChooser / PitchProbTable`）。
- 倒影/逆行：`Real imPro/ThemeWeaver/MotifTransform.swift`（`inverted` / `reversed`）。
- 数据/和声/节奏：`CoreEngine/`（`MelodyPart / JazzEngine / JazzStrategy`）、`Harmony/`、`Rhythm/`。
- LSTM：`Real imPro/LSTM/`（RNN 模型与 `.rnn` 已在端上）。
- 规则数据：`Real imPro/TransformTables`、`Real imPro/grammars/`、`Real imPro/Resources/Styles/`。

### 初步判断缺失（**你必须亲自 grep / 读代码确认**）
- **全工程无 CoreMIDI 实时输入**：用 `grep -rn "CoreMIDI\|MIDIClientCreate\|MIDIInputPortCreate\|MIDIPacketList" "Real imPro"` 自查，预期为空。
- **无实时录音器**（把 MIDI 包按 slot 写入 MelodyPart + 延迟补偿）。
- **无 ActiveTrading 状态机**（USER/PROCESS/COMPUTER 轮流）。
- **无动态实时调度**（边界处生成并精确排入 sampler）。
- **未移植**：`AbstractMelodyExtractor`（Java 553 行）、`PhraseTable`（Java 130 行）。
- 用 `grep -rn "func rectify\|rectifyPitches\|func invert\|func reverse" "Real imPro"` 确认 rectify / 倒影 / 逆行已有（避免重复实现）。

---

## 五、技术栈映射（供你核实与修正，不是结论）

| Java / Impro-Visor | iOS 候选 | 初步判断 |
|---|---|---|
| `javax.sound` 设备枚举 | **CoreMIDI**：`MIDIClientCreate` / `MIDIInputPortCreate` / `MIDIPacketList`（含 USB 与蓝牙 MIDI） | 需新建 |
| Sequencer 主时钟 | 自建音频时钟：AVAudioEngine 渲染时钟 / `AVAudioTime` / 高精度定时，推出小节/拍/slot | 需新建，**最难、最需重设计** |
| `MidiRecorder` | MIDI 接收回调 + 按 slot 量化 + 延迟补偿写入 MelodyPart | 需新建 |
| `ActiveTrading` | Swift 状态机 + 触发器（slot 边界） | 需新建（纯逻辑，参考 Java 等价） |
| `MidiSynth`/`PlayScoreCommand` | 已有 `AVAudioUnitSampler`；新增**动态 look-ahead 调度队列** | 部分已有，需补动态调度 |
| Transform/Grammar/rectify | 已移植的 Swift 引擎 | 复用 |
| 乐器音色 | 已加载 `ChoriumRevA.sf2`；可扩 AUv3 | 已具备 |
| LSTM | 端上 RNN / CoreML（核心对话非必需，规则引擎毫秒级） | 可选 |

调研线索（你要自己联网复核）：官方仓库 `github.com/Impro-Visor/Impro-Visor`（约 160 stars / 33 forks / 31 issues，**未见 iOS 移植**）；iOS 先例 **GimmeDaBlues**（爵士自动伴奏/回应，Max/MSP→跨平台 C++ 引擎+原生 UI，闭源）；记忆/重组可参考开源因子预言机 **Djazz**；Java→Obj-C 工具 **j2objc** 仍维护但**不支持 javax.sound**，且生成引擎你已手工移植，预计不划算。

---

## 六、需要你在设计里讲清楚的工程难点

1. **主时钟与轮流精确性**：必须音频线程级（非普通 Timer），保证回应在小节边界准时进/准时止；这是"对话感"的命门。
2. **动态而非预渲染的调度**：回应在轮到电脑前一刹那才生成，需要 look-ahead 调度（边播边排）。
3. **延迟与补偿**：MIDI 输入→音频出声的缓冲延迟；调小音频缓冲（如 128–256 采样）并做 offset 校准，否则录音整体偏后。
4. **音频会话/路由/中断**：USB 键盘供电、蓝牙 MIDI 抖动、耳机拔出、来电中断、后台行为。
5. **与现有 AVAudioEngine 的协同**：Trading 要用现有伴奏与采样器，但不能改现有播放逻辑——如何以"旁路/会话"方式接入，是设计重点。
6. **纯新增的落点**：所有新文件建议集中在 `Real imPro/Trading/`（含输入、时钟、录音、状态机、调度、UI）；与现有引擎的交互只能通过调用其**现有公开接口**（读代码确认哪些接口可复用），不新增侵入式改动。
7. ~~授权~~：**用户已拍板不考虑 GPL-2.0 授权风险**（见 `SOUL_trading_port.md` 红线 4），本任务不讨论授权合规、不在设计中占用篇幅。

---

## 七、前一任 AI 的结论（**仅线索，必须独立复核，不得照抄**）

- 结论：实时 MIDI 输入 + 音乐对话在 iPad **可行、平台适合**；但**不能 1:1 直接搬代码**，Sequencer 时钟/发声链路必须重设计。
- 认为生成算法（Transform/Grammar/Style/LSTM/rectify/倒影逆行）**已在 RealimPro 基本就绪**，真正缺的是：CoreMIDI 输入、实时录音器、统一主时钟、轮流状态机、动态调度，以及两个小组件（AbstractMelodyExtractor / PhraseTable）。
- 粗略工期（1–2 名熟悉音频的开发）：Repeat 对话 MVP 约 5–7 周；接 Transform/Grammar 约 8–10 周；完整 + 打磨约 11–14 周。
- 已产出一份 HTML 报告：`/Users/onlyonear/Desktop/Improlyze/Trading功能iOS移植可行性分析-20261012.html`（可参考其结构，但你要独立验证其事实与数字）。

> 你不得因为"前任已经分析过"就跳过看视频/读代码；若复核后结论不同，以证据为准并说明。

---

## 八、本阶段必须交付的文档（落到项目根目录，Markdown）

1. **`Trading可行性复核报告-<日期>.md`**：
   - 视频交互流程复述（含时间点/画面证据）；
   - Java 架构与数据流（你自己画的状态机/调用链，标注 `文件:行号`）；
   - 逐模式可行性；Java→iOS 技术栈映射；
   - RealimPro 已具备/需新建清单（每条附 grep/读代码证据）；
   - 明确回答"能否完美移植"，并区分"1:1 搬代码"与"等价复刻交互"；
   - 关键难点、风险、粗略工期（授权：用户已拍板不考虑，不单列）。
2. **`Trading离线设计方案-<日期>.md`**（纯新增、不改现状）：
   - 新模块目录与文件清单（全部在 `Real imPro/Trading/` 下）；
   - 关键类/接口/数据结构、线程模型、主时钟、录音量化、延迟补偿、状态机、动态调度；
   - 与现有引擎的调用边界（只用现有公开接口）；
   - Trading UI 与入口（默认关闭、可一键关）的设计；
   - **《集成点清单》**：将来可能需要触碰的现有文件、位置、可否用纯新增绕过、向后兼容与开关方案；
   - 分阶段实施计划（M1–M4）、每阶段验收标准、测试/对拍思路、回滚方案。
3. 交付时附：你**未改动任何现有文件**的自证（`git status` / `find -newermt` / 与备份对比）。

---

## 九、编译与自证（沿用 `IDEA.md`，仅供将来实施阶段；设计阶段不需要编译）

```bash
cd /Users/onlyonear/Desktop/Improlyze
xcodebuild build -project RealimPro.xcodeproj -scheme RealimPro \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/imp_build
```
设计阶段只允许只读命令与 `/tmp` 探针；禁止写入或修改 `Real imPro/`。

---

## 十、明确边界（本期不做）

- 不做 Pitch Tracker（音频→MIDI，视频结尾口风琴那条路）。
- 不照搬 Swing 对话框 UI；不做被动交易、节奏练习类模式的 UI（列二期）。
- 不做多设备联网合奏、录音导出等周边。
- 不重构、不优化、不"顺手修"任何现有代码。
- 在用户书面批准前，不产出任何进工程的实现代码。

---

## 十一、开工自检清单（开始前默念）

- [ ] 我已读完 `SOUL_trading_port.md`、本文件、`IDEA.md`。
- [ ] 我清楚本轮**只离线分析与设计、零代码落地**。
- [ ] 我会自己看视频、读 Java、读 Swift，并独立复核前任结论。
- [ ] 我的每个"已具备/需新建"判断都有证据。
- [ ] 我会把所有方案设计为**纯新增**，并把任何接触点列成待批准的《集成点清单》。
- [x] 授权风险：用户已拍板不考虑（见 `SOUL_trading_port.md` 红线 4），不单列。
- [ ] 我会在交付时自证未改动现有文件，并等待用户书面批准。
