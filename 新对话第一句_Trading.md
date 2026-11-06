你好，我们启动一个新任务：把桌面开源软件 Impro-Visor（Java）里的 **Trading（实时"trading fours / 互相用音乐对话"）功能**，新增移植到我的 iOS App **RealimPro（Swift）** 中，让 MIDI 键盘连接 iPad 后，能像视频里那样实时弹、由电脑轮流回应。

## 请先按顺序读完这三份文件（它们是本次任务的"宪法"）
1. `/Users/onlyonear/Desktop/Improlyze/SOUL_trading_port.md` —— 你的角色、最高红线与工作闸门；
2. `/Users/onlyonear/Desktop/Improlyze/IDEA_trading_port.md` —— 本任务的事实库、代码地图与要交付的文档；
3. `/Users/onlyonear/Desktop/Improlyze/IDEA.md` —— 整个 RealimPro 项目的总事实基线（编译命令、slot 口径、方法论、已拍板的设计都在里面）。

## 本轮只做"离线可行性分析 + 设计"，绝对不许动代码
- **红线：不碰、不改、不重构 `Real imPro/` 下任何现有文件与逻辑**；Trading 未来只能以**纯新增**模块（建议 `Real imPro/Trading/`）落地。任何绕不开的现有文件接触点，本轮只写进《集成点清单》并标注"待批准"，不要实际修改。
- 这一轮**只产出设计文档，不写、不改、不生成任何进工程的实现代码**（只读探针可放 `/tmp`）。等我对设计**书面评审通过后**，才进入实施。

## 你这一轮要独立完成的事（不要只信前一任 AI 的结论，要自己复核）
1. **看视频**：教学视频已下载到本地 `/Users/onlyonear/Desktop/Improlyze/Trading教学视频_Impro-Visor_Xfk8vR2vsb4.mp4`（约 17 分半；原始链接 https://youtu.be/Xfk8vR2vsb4 ）。用 ffmpeg 抽帧 + 提取音频转写，搞清楚它演示的硬件设置、实时输入流程、Trading 对话框选项（谁先开始、每轮小节数、处理提前量等），以及 7 种回应模式（Repeat、Repeat & Rectify、Modify & Rectify、Abstract Melody、Transform、Grammar、Chop & Memorize）。结尾的 Pitch Tracker（口风琴音频转 MIDI）本期不做，看懂即可。
2. **读 Java 源码**：`/Users/onlyonear/Desktop/Impro-Visor-master/`，重点是 `src/imp/trading/**`（ActiveTrading、TradingResponseController、TradingResponseInfo、tradingResponseModes、PhraseTable）、`src/imp/midi/**`（MidiManager、MidiRecorder、MidiSynth）、`com/PlayScoreCommand`、`data/AbstractMelodyExtractor`、`com/RectifyPitchesCommand`，以及被复用的 Transform/Grammar 引擎。弄清楚它的数据流和"以 Sequencer 为主时钟"的轮流调度机制。
3. **读我的 Swift 工程现状**：`/Users/onlyonear/Desktop/Improlyze/Real imPro/`，重点 `MidiPlayer/JazzMidiPlayer.swift`、`MidiPlayer/StyleEngine/`、`TransformEngine/`、`Grammar/`、`CoreEngine/`、`ThemeWeaver/MotifTransform.swift`、`Views/`。自己用 grep 核实哪些已具备、哪些缺失（重点确认：现在是否真的没有 CoreMIDI 实时输入、没有实时录音器、没有轮流状态机、没有动态调度）。
4. **联网核查**：GitHub 上 Impro-Visor 有没有人做过移动端/iOS 移植，有无可参考的同类实时爵士"对话"项目（如 GimmeDaBlues、Djazz、j2objc 等）。

## 最终请正面回答我这个问题，并落两份文档
问题：**"Trading 功能是否可以完美移植到 RealimPro，让 MIDI 键盘接 iPad 实现和视频一样的实时输入与'互相用音乐对话'？"** 请明确区分"1:1 原样搬代码"与"等价复刻这套交互"，给出逐模式可行性、Java→iOS 技术栈映射、已具备/需新建清单、关键难点与风险、粗略工期（授权风险：用户已拍板不考虑，详见 SOUL 红线 4，不单独讨论）。

交付（放到项目根目录 `/Users/onlyonear/Desktop/Improlyze/`，Markdown）：
- `Trading可行性复核报告-<日期>.md`
- `Trading离线设计方案-<日期>.md`（含纯新增模块设计、主时钟/录音/延迟/状态机/动态调度方案、以及《集成点清单》《分阶段计划与验收标准》）

交付时用 `git status` 等自证：**这一轮没有改动任何现有文件**。

## 开始方式
请先回复我：你已读完三份文件、复述一遍你的红线与本轮边界，然后给出你的**勘察与分析计划（先读什么、怎么看视频、怎么核实、最终交付什么）**；在我确认计划后再开始正式勘察。现在先不要分析、也不要动任何代码。
