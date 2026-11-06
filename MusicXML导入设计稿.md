# MusicXML 导入功能设计稿（特性清单 · 字段映射 · 校验/报错规则）

状态：**v2.1 评审修订稿（不含实现）** ｜ v1 2026-09-21，v2 2026-09-22（并入首轮代码级评审并独立复核），v2.1 2026-09-22（并入第二轮评审的 4 个实现注意点 + 开工顺序）
目标：让用户把自己下载的 lead sheet 版 MusicXML 导入歌单，在现有五线谱上显示**和弦 + 旋律**并可播放/伴奏。
定位：**lead sheet 专用导入器，不是通用 MusicXML 阅读器/打谱器。**

> **v2 修订摘要（每条均已对照源码/数据独立复核）**
> 1. **【纠错】渲染端其实画调号**：`SheetMusicView.swift:887` 首小节执行 `stave.addKeySignature(...)`，v1"不画调号"说法错误。导入器**必须**新增 `fifths/mode → App 调名字符串` 映射（§5.1）。逐音临时记号仍由渲染端按调号上下文自动去重（`:345-369`），无需新写记号逻辑。
> 2. **【补漏】2/2 已可用**：内置 34 首实测 7 首是 2/2。显示走原始拍号串（`:656/:888`），2/2 现在就正确显示、不会变 4/4；`getProfile` 兜底 480 slots 对 2/2 时值恰好正确。仅符杠分组按四分（美观细节，非错误），**不改引擎、不告警**，只把 2/2 补进支持表。（评审称"会显示成 4/4"，经核验不成立。）
> 3. **【范围上调】简单反复 + 一/二房子进 MVP**：黄金集 319/400（79%）含反复（forward 801/backward 854/ending 1015），"线性导入+告警"会让约 8 成曲静默变短，不可接受。D.S./D.C./Coda/Fine 等非线性跳转仍拦截（少数，约 7–12%）。
> 4. **【口径收紧】v1 检测到多个含音符 Part（钢琴大谱表/鼓谱/TAB）直接拦截**；同一 Part 内多声部（voice/backup）取 voice 1。自动选旋律属静默错误，危害大于拒绝。
> 5. **技术补强**：divisions 按小节取值；`.xml` 路由必须内容嗅探 `<score-partwise>`；和弦 noteIndex 锚定升为强制验收项。
> 6. **红线复核结论：按 v2 范围，MVP 不需要改动 solo 生成 / 播放 / VexFlow 渲染 / UI 布局任何一行**——引擎表达不了的输入一律"拦截"而非"扩展引擎"。
>
> **v2.1 增补（第二轮评审，4 个实现注意点，均已核验）**
> - **和弦 `<kind>` 映射是除反复外第二块工作量，必须先建表**：黄金集实测 **21 种 kind**（分布见 §3.4.1），离线管线靠 music21 先生成 figure 再归一，Swift 侧没有 music21，须直接把 kind+degree 映射到 App canonical 后缀；M1 就要出 `ChordSymbolMapper` 命中率报告，不能边写边补。
> - **style 固定 "Medium Swing" 是已知降级**：bossa/waltz/ballad 导入后会按 swing 伴奏，必须在导入报告明示（V19），避免被当成 bug；tempo 取 `<sound tempo>`、缺省 120 不变。
> - **不是"零 Swift 改动"**：新增整个 `Importers/MusicXML/` 目录，并对**两个现有文件**做最小接线（`ContentView.importFromFile` 加路由、`DocumentPickerView` 加 UTType），需重新编译发版；引擎与 UI 布局不动。
> - **两个边界**：① 开头（含第一小节）无和弦时"沿用上一小节"没有前值，导入器须**向后取本曲第一个和弦回填**（DTO 自带兜底用的是可能为空的 `dto.chord`，不可依赖）；② 反复展开必须**先把全曲解析成中间 measure 模型再做**（backward 要回溯 forward），禁止流式边解析边产出。
> - 附：`SheetMusicView.swift:612`（及 :262）的 `let profile = getProfile(...)` 目前结果未被读取（显示拍号走原始串），属历史死代码，红线内不动，二期可清理。

---

## 0. 一句话方案

App 内用 Swift 原生 `XMLParser` 解析 MusicXML，**复用离线管线 `build_79.py` 已验证的反复展开、量化/守恒/连音修复规则**，产出与内置库完全相同的旋律 DTO（`BuiltinMelodyLibrary` 的 `LibraryDTO/SongDTO/MeasureDTO/NoteDTO`），随后走现有导入落库链路。渲染（VexFlow）、播放（`JazzMidiPlayer`）、符头分色、三轨伴奏、即兴引擎**全部零改动**。

---

## 1. 现状架构锚点（实现时按这些文件定位）

| 关注点 | 文件 / 类型 | 说明 |
|---|---|---|
| 乐谱数据模型 | `CoreEngine/JazzEngine.swift` `GeneratedNote`（:21）/ `GeneratedMeasure`（:38） | slot 网格模型；含 isTieStart/End、isTriplet、graceNotes、chordSlots、chordAnnotations |
| 导入 DTO（可 Codable） | `BuiltinLibrary/BuiltinMelodyLibrary.swift`（DTO :125-170，转换 :176-278） | 字段全 Optional、容错解码；DTO→模型默认值都在这里 |
| 文件导入路由 | `Views/ContentView.swift` `importFromFile(url:)`（:505） | 现 `.json` 走旋律库（:510），其余按 UTF-8 文本走 iReal（:528-532）；新分支加在这里 |
| 外部旋律落盘 | `ContentView.persistExternalMelodyFile`（:497），目录 `Documents/ImportedMelodies` | 原始文件原子落盘、启动重建索引 |
| 导入结果 UI | `handleImportResult`（:544）：`importedTotalCount / importSkippedCount / mixedAlertCount / fileImportError` | 复用为导入报告字段 |
| 渲染 | `Views/SheetMusicView.swift`（WKWebView + `vexflow-min.js`） | 首小节 `addClef`+**`addKeySignature`**+`addTimeSignature`（:886-888）；逐音 `VF.Accidental` 且按调号/小节上下文去重（:345-369）；`StaveTie`、`Triplet(realTuplet)`、`Beam`、`GraceNote`、`Barline` 均已用 |
| 调号字符串解析 | `getVexflowKey(for:)`（:171-205） | 接受 15 个大调（C/G/D/A/E/B/F#/C#/F/Bb/Eb/Ab/Db/Gb/Cb）；小调（后缀 m）按关系大调映射；兜底 C |
| 拍号 profile | `MidiPlayer/TimeSignatureManager.swift`（:15-75） | 单一拍号全曲一套；支持集合见 §3.2；**无 2/2 case，落 default=480（时值正确）** |
| 和弦归一化（Swift） | `FullVoicing/ChordSymbolMapper.swift`、`FullVoicing/ChordFormMaps.swift` | MusicXML `<kind>` 最终交它 resolve，无法识别返回 nil；**不要新造和弦表** |
| 音高拼写 | `Harmony/NoteSpelling.swift`（:55 `spellNote`） | MIDI→拼写（sharp/flat 表、useSharps）优先复用 |
| 离线参考实现（权威口径） | `video_shoot/jazz_songs/effendi/build_79.py`、`convert_core.py`、`chord_norm.py` | 反复展开（:261）、量化网格、休止/长音拆分、连音孤儿/断头修复、守恒补拍、和弦沿用的"标准答案" |
| 黄金集 | `…/effendi/mxl_all/`（400 个未压缩谱：347 `.xml` + 63 `.musicxml`，无 `.mxl`） | 导入器回归对照集 |

**关键事实（决定设计边界）**
- 模型是**固定 slot 网格**：四分音符 = 120 slots，最小量化 15 slots（64 分音符）；每小节时值必须守恒。
- 模型**每首歌只支持一个拍号**；混合拍/逐小节换拍在渲染和伴奏都不成立（现有 `hasMixedTimeSignature` 即拦截路径）。
- **渲染端既画调号又画逐音临时记号**：导入器既要给对调号字符串，也要给每个音确定拼写；临时记号是否显示由渲染端按调号/小节上下文决定，导入器不决定。
- 播放器对 `isTieStart` 不发 note-off：**任何悬空 tieStart 都会造成卡音长鸣**（Days bug 根因）。导入数据落库前必须保证 0 悬空连音（运行时 `heldTieNotes` 兜底是第二道保险，不替代数据自检）。

---

## 2. 输入文件形态

| 形态 | 后缀 | MVP | 处理 |
|---|---|---|---|
| 未压缩 MusicXML | `.musicxml` / `.xml` | ✅ 支持 | **必须内容嗅探**：扩展名命中**且**根元素为 `<score-partwise>` 才进 MusicXML 分支（防止把含 XML 标签的 iReal `.html/.txt` 误判，也防止把 XML 误送 iReal） |
| 压缩 MusicXML（ZIP：`META-INF/container.xml`→rootfile） | `.mxl` | ⏳ 二期 | MVP 明确报错并指引"MuseScore 另存为未压缩 .musicxml"；二期用 ZIPFoundation（SPM） |
| `score-timewise` | — | ❌ 不支持 | 报错（二期可做 partwise↔timewise 转换） |
| iReal Pro / 其它文本 | `.txt/.html` | — | 内容嗅探不到 score-partwise 时维持现有 iReal 分支 |

路由顺序：`.json` → **内容嗅探 score-partwise（MusicXML）** → iReal 文本。现 `importFromFile` 仅以 `.json` 分流、其余一律送 iReal，必须改。

---

## 3. MusicXML 特性支持清单

图例：✅ MVP ｜ ⏳ 二期 ｜ ⚠️ 受限（带告警）｜ ❌ 不支持（忽略或拦截）

### 3.1 谱面结构

| 特性 | MusicXML 元素 | 档位 | 说明 |
|---|---|---|---|
| partwise 结构 | `score-partwise > part > measure` | ✅ | 主路径；timewise ❌ |
| 标题/作曲家 | `work-title`/`movement-title`/`identification` | ✅ | 缺标题用文件名 |
| **调号（显示+元数据）** | `attributes/key (fifths,mode)` | ✅ | **必须**经 §5.1 映射成 App 调名字符串；同时用于音高拼写与伴奏调性 |
| 拍号 | `attributes/time (beats,beat-type)` | ✅（限 §3.2） | 全曲单一 |
| 逐小节换拍/混合拍 | 多个不同 `time`、复合 `beats="4+3"` | ❌ 拦截 | 复用混合拍拦截，整曲跳过并报告检测到的拍号 |
| 弱起小节 | 首小节 `barDuration < grid` | ✅ | 头部补休止凑满（对齐 build_79 paddingLeft） |
| 结尾超长小节（16/4 等） | barDuration 为网格整数倍 | ⏳ 二期拆分 | MVP：拍号不在支持集即拦截，不自动拆小节 |
| **成对简单反复** ‖:…:‖ | `<repeat direction="forward/backward">` | ✅ **MVP 展开** | 见 §6.2，展开后小节被真正复制 |
| **一房子/二房子（volta）** | `<ending number type>` | ✅ **MVP 展开** | 按遍次选择对应 ending 小节 |
| **D.S./D.C./al Coda/al Fine/To Coda/segno/coda 跳转** | `<words>`/`<sound>`/barline 的 `segno,coda`/rehearsal | ❌ 拦截 | 非线性跳转 v1 不展开、**不写盘**，提示在 MuseScore 展开后导出；检测要覆盖以上全部载体，不能只看文字 |
| 同一 Part 内多声部 | `<voice>`/`<backup>`/`<forward>` | ⚠️ | 取 voice 1（主旋律），其余忽略并计数告警 |
| **多个含音符 Part（钢琴大谱表/总谱）** | 多个 `score-part` | ❌ **v1 拦截** | 自动选旋律属静默错误，危害最大；提示用单旋律 lead sheet |
| 鼓谱 / 六线谱 TAB | percussion clef、`<midi-drum>`、tab clef | ❌ 拦截 | — |
| 谱号 clef | `<clef>` | ⚠️ | 仅用于辅助判别；旋律统一按高音谱输出（现有渲染固定） |
| 移调乐器 `<transpose>` | `<transpose>` | ❌ 忽略（MVP） | 检测到则告警"按记谱音高导入，未做移调还原" |

### 3.2 拍号（命中 `TimeSignatureManager` 现有 profile，外加 2/2）

| 拍号 | slotsPerMeasure | 备注 |
|---|---|---|
| 4/4 | 480 | 默认 |
| **2/2** | **480** | **v2 补入**：显示走原始串已正确；时值=4 个四分=480；符杠分组沿用 4/4（仅美观），无需改引擎 |
| 3/4 | 360 | |
| 2/4 | 240 | |
| 1/2 | 240 | |
| 6/8 | 360 | divisions 以四分为基准，6 八分=3 四分=360 |
| 12/8 | 720 | |
| 5/4 | 600 | |
| 6/4 | 720 | |

> 其余（7/8、9/8、3/8、自由拍 senza-misura 等）❌ 整曲拦截。全曲只允许一种拍号。

### 3.3 音符与节奏

| 特性 | MusicXML | 档位 | 映射/处置 |
|---|---|---|---|
| 音高 | `pitch(step,alter,octave)` | ✅ | 先算 MIDI（播放真值），拼写经 `NoteSpelling`/缺省 #（与 effendi 一致） |
| 自然/升降/重升降 | `alter=0/±1/±2` | ✅/⚠️ | ±1→#/b；±2 重升/重降能等音转换则转换+告警 |
| 休止 | `<rest/>` | ✅ | isRest=true，按 §4 拆标准休止 |
| 时值 | `duration` + **当前小节生效的** `attributes/divisions` | ✅ | quarterLength=duration/divisions；slot=round(ql×120)，吸附 15 网格。**divisions 可逐小节变化，按 measure 取，不假设全曲统一** |
| 类型/附点 | `<type>`/`<dot/>` | ✅ | 仅用于校验，时值以 duration 为准 |
| 全…三十二分 | w/h/q/8/16/32 | ✅ | 见 §4 |
| 附点节奏 | ql×1.5 | ✅ | hd/qd/8d/16d |
| 三连音 | `<tuplet>`/`<time-modification>` 实际 3:2 | ✅ | isTriplet=true，token 加 `_t3` |
| 五/六/七连音等 | 其它 actual:normal | ❌ 量化+告警 | 吸附最近网格；整曲量化误差超阈（建议每小节 >15 slots）转拦截 |
| 同时和弦音 | `<chord/>` | ✅ | 取最高音作旋律（对齐 `chord_melody_midi`） |
| 连音线 | `<tie>`+`<notations><tied>` | ✅ | isTieStart/End；**强制过连音修复**（§5.3） |
| 倚音/碎音 | `<grace/>` | ⏳ 二期 | 模型/渲染已支持 graceNotes；MVP 丢弃并计数告警 |
| 短于 32 分（<15 slots）碎音 | — | ⚠️ | 同音并入前音、休止折叠（对齐 extract_events collapse） |
| 64 分及更短/二全音 | — | ⚠️ | 量化到边界并告警 |
| slur、力度、歌词、指法、装饰音、断奏/重音 | 各类 notations | ❌ 忽略 | 与"和弦+旋律"无关，不报错（汇总计数） |

### 3.4 和弦（和声层）

| 特性 | MusicXML | 档位 | 处置 |
|---|---|---|---|
| 和弦标记 | `<harmony>` 的 root/root-step/root-alter、`kind`、`bass`、`degree` | ✅ | 转 App 和弦串后交 `ChordSymbolMapper.resolve` |
| 变化/延伸音 | `<degree>`（add9/#11/b9/b13/alter…） | ✅ | 参照 `chord_norm.py` degree→canonical（7#9/7b9/7#11/7b13/9#11/M69/M7#11…） |
| 减/半减/增 | diminished/half-diminished/augmented | ✅ | 严格区分 `o`/`o7`/`m7b5`，不可互相压缩 |
| 斜杠和弦 | `<bass>` | ✅ | 保留 `/bass` 显示；伴奏 voicing 只看本体（现有行为） |
| N.C. / 空和弦小节 | N.C. 或无 harmony | ✅ | 沿用上一小节最后一个和弦（finalize 规则） |
| **全曲无任何 `<harmony>`** | — | ❌ **v1 拦截** | 纯旋律需给播放/渲染/生成三条链路加无和弦分支，触碰红线；v1 明确报错，纯旋律列二期 |
| 个别和弦无法 resolve | — | ⚠️ | 原样保留用于显示+计数；不可解析率 >20% → 整曲拦截 |

> 经验数据：400 个精修 lead sheet 中 380 带 harmony、20 不带；用户自下载文件不含和弦比例预计更高，必须导入前检测并明确提示。

### 3.4.1 `<kind>` 基础映射表（v2.1 新增，黄金集实测 21 种 + 常见补全）

离线管线由 music21 把 `kind+degree` 先合成 figure 再 `norm_chord`；Swift 无 music21，导入器须**直接**按下表把 `<kind>` 映射到 App canonical 后缀（拼到根音后），`<degree>` 再按 `chord_norm.py` 的后缀规则叠加。下表"实测次数"为黄金集 400 谱统计。

| MusicXML `<kind>` | App 后缀 | 实测次数 | 备注 |
|---|---|---|---|
| dominant（属七） | `7` | 5156 | |
| minor-seventh | `m7` | 3537 | |
| major（大三） | （空，纯根音） | 1252 | |
| major-seventh | `M7` | 1218 | |
| dominant-ninth | `9` | 627 | |
| dominant-13th | `13` | 481 | |
| minor（小三） | `m` | 233 | |
| minor-11th | `m11` | 121 | |
| minor-ninth | `m9` | 103 | |
| suspended-fourth | `sus4`（+7度→`7sus4`，+9度→`9sus4`） | 94 | degree 决定是否带 7/9 |
| diminished-seventh | `o7` | 87 | 减七，勿压成 m7b5 |
| diminished（减三） | `o` | 74 | |
| major-sixth | `6`（+9度→`M69`） | 69 | |
| major-ninth | `M9` | 32 | |
| major-minor（小大七） | `mM7`（+9度→`mM9`） | 29 | |
| minor-sixth | `m6` | 26 | |
| major-13th | `M13`（#11→`M13#11`） | 22 | |
| minor-13th | `m13` | 15 | |
| power（五度/无三音） | ⚠️ 无对应 canonical | 10 | 无三音，按 V17：记 WARN，降级为根音三和弦或不可解析计数，**不臆造三音性质** |
| augmented-seventh | `7#5` | 4 | 即 norm 表 `7+`/`7 alter #5` |
| augmented（增三） | `+`（待命中率核验） | 4 | 若 ChordFormMaps 无 `+`，落 V17，不静默 |
| half-diminished（半减七，实测 0 但补全） | `m7b5` | 0 | 也可能由 minor-seventh + degree alter b5 表达，统一收 `m7b5` |

**`<degree>` 组合规则（移植 chord_norm `_norm_body` 表）**：在基础后缀上按 degree-type(add/alter/subtract) + degree-value(5/9/11/13) + degree-alter(−1/0/+1) 叠加，canonical 目标含 `7#9 7b9 7#11 7b13 7#5 7b5 9#11 M69 M7#11 mM9 7sus4 9sus4 M13#11`；斜杠 bass 保留显示。黄金集 degree 实测：add 438、alter+1 约 487、alter−1 149、alter 0 92。

**M1 强制门槛**：对黄金集跑 Swift kind+degree 映射，输出"原始 kind/degree 组合 → App 串 → `ChordSymbolMapper.resolve` 是否非 nil"的全量对照表与命中率；任何 resolve 为 nil 的组合走 V17（保留显示+计数，>20% 拦截）。此表与 chord_norm.py 的 music21 figure 结果对齐，不靠人耳。

---

## 4. 时值 / slot 口径（与离线管线严格一致）

- 基准：四分音符 = 120 slots；`slot = round(quarterLength × 120)`，吸附 **15** 整数倍。
- 标准 token（slots→duration）：

| slots | 普通 | 附点 | 三连音(×2/3) |
|---|---|---|---|
| 480 | `w` | — | `h_t3`=160 |
| 240 | `h` | `hd`=360 | `q_t3`=80 |
| 120 | `q` | `qd`=180 | `8_t3`=40 |
| 60 | `8` | `8d`=90 | `16_t3`=20 |
| 30 | `16` | `16d`=45 | — |
| 15 | `32` | — | — |

- **非标准时值**：贪心拆成标准片段之和（`split_slots`，PIECE_STD=[480,360,240,180,120,90,60,45,30,15]），片段间用 tieStart/tieEnd 连接。
- **休止**：同样贪心拆标准休止 token（`wr/hr/hdr/qr/qdr/8r/8dr/16r/16dr/32r…`），弱起与事件间空隙补休止。
- 每个发声音的实际占长 = min(名义时值, 到下一发声事件/小节末距离)，避免重叠/溢出。
- 三连音以 `<time-modification>`/`<tuplet>` 为准，不仅靠时值近似。

---

## 5. 到 GeneratedMeasure 的字段映射

### 5.1 曲级（SongDTO）

| SongDTO | MusicXML 来源 | 缺省/规则 |
|---|---|---|
| title | work-title/movement-title/metadata | 文件名去扩展名 |
| composer | identification/creator(composer) | "" |
| **key** | **`<key>` fifths+mode，按下表映射** | "C" |
| timeSignature | 全曲唯一的 `<time>` | "4/4"；不在 §3.2 → 拦截 |
| tempo | 首个 `<sound tempo>`/`<metronome>` | 120 |
| style | MusicXML 无可靠风格字段 | 固定 "Medium Swing"（**已知降级**：bossa/waltz/ballad 会按 swing 伴奏，导入报告须明示，见 V19） |
| measures | 逐小节（**反复展开后**）转换 | — |

**fifths/mode → App 调名字符串（v2 新增的必备映射）**：输出大调主音或"主音+m"，再由现有 `getVexflowKey` 转 VexFlow 调号。

- 大调（mode major/缺省），fifths −7…+7：
  `Cb, Gb, Db, Ab, Eb, Bb, F, C, G, D, A, E, B, F#, C#`
- 小调（mode minor），fifths −7…+7：
  `Abm, Ebm, Bbm, Fm, Cm, Gm, Dm, Am, Em, Bm, F#m, C#m, G#m, D#m, A#m`
  （负 fifths 用降号拼写、正 fifths 用升号拼写；这些 key 串均被 `getVexflowKey` 的小调关系大调表覆盖）
- 验收：首小节画出的调号升降号数量必须等于 fifths；黄金集逐首比对（V22）。

### 5.2 小节级（MeasureDTO）

| MeasureDTO | 来源 / 算法 |
|---|---|
| slotsPerMeasure | 拍号 profile（§3.2），全曲一致 |
| notes | 本小节发声/休止经 §4 量化、补休止、守恒后的序列 |
| chordSlots | 本小节所有 `<harmony>`：`{chord: 归一化和弦, startSlot: round(off×120)}`，按 startSlot 排序 |
| chord | chordSlots 第一个 |
| chordAnnotations | 与 chordSlots **一一对应、等长**；`noteIndex` 用 startSlot 在音符累计 slot 上**就近/二分定位**（规则同 finalize）。**锚点时间正确是强制验收项（V21）**——此项目曾出现两个和弦标签贴在一起的 bug |
| sectionName | `<rehearsal>` 排练号，无则 null |

空小节：notes 补满休止。无和弦小节沿用上一小节最后和弦；**开头（含第一小节）就没有和弦时没有"上一小节"可沿用，导入器须向后取本曲第一个出现的和弦回填所有前导空小节**（DTO 自带兜底用的是可能为空的 `dto.chord`，不可依赖）；全曲无和弦由 V6 拦截。落库前保证每小节 chordSlots 非空（V20）。

### 5.3 音符级（NoteDTO）

| NoteDTO | 来源 / 算法 |
|---|---|
| pitch | step+alter+octave→MIDI，拼写经 `NoteSpelling`（按调），缺省 #；格式 `"C#/4"`；休止占位 `"b/4"` |
| isRest | `<rest/>` |
| duration | §4 token；三连音加 `_t3`；休止加 `r` |
| isTriplet | 属于 3:2 连音 |
| isTieStart | tie=start/continue 且声音真正抵达小节右边界（跨块门控，同 `split_into_chunks`） |
| isTieEnd | tie=continue/stop 且声音起于小节左边界 |
| （二期）graceNotes | `<grace>`，MVP 不产出 |

**连音强制修复（移植 build_79 两函数，落库前必跑）**
1. `repair_orphan_ties`：小节首音 tieEnd 却无持音、前小节末发声音同音高 → 补前音 tieStart；否则记问题。
2. `repair_dangling_ties`：紧邻同音高缺 tieEnd→补（不改音高）；紧邻**异音→一律撤前音 tieStart（方案 a，不改旋律音高）**；被休止切断/曲末悬空→撤。用户文件不做改音高的"方案 b"（离线人工精修才做）。
3. 硬约束：**输出不允许无配对终点的 tieStart**。

### 5.4 建议的 Swift 模块（仅职责，非最终代码）

- `MusicXMLParser`：XMLParser(SAX) → `MusicXMLScore`（parts/measures/attributes，divisions 按小节维护）。**必须先把全曲完整解析成中间 measure 模型**，再交展开器/量化器；反复 backward 要回溯 forward，禁止边解析边产出最终小节。
- `MusicXMLRepeatExpander`：简单反复 + volta 展开（§6.2），在量化**之前**对 measure 流操作（和弦随小节复制，保证旋律/和声两层对齐）
- `RawEvent` / `MusicXMLQuantizer`：divisions→slots、吸附网格、碎音折叠、休止/长音拆分
- `MusicXMLTieRepair`：孤儿/断头修复
- `MusicXMLChordMapper`：harmony→App 和弦串，内部调 `ChordSymbolMapper`
- `MusicXMLKeyMap`：fifths/mode→调名（§5.1）
- `MusicXMLValidator`：§7 全部规则，产出结构化报告
- 终态 `JSONEncoder().encode(LibraryDTO)` → 用 `BuiltinMelodyLibrary.load(from:)` 自检可解码 → `persistExternalMelodyFile` + `handleImportResult`。

---

## 6. 关键边界

### 6.1 Part / 声部选择（v2 收紧）
- **v1 仅接受单个非打击 Part**：检测到 ≥2 个含音符的 Part（钢琴大谱表、总谱、含独立鼓/TAB 谱表）→ **整曲拦截**，提示"请下载单旋律 lead sheet 版本"。钢琴谱选旋律本质无解，启发式选错是静默错误，危害大于拒绝。
- 同一 Part 内多声部（`<voice>`/`<backup>`/`<forward>`）：取 voice 1，同时发声音取最高音，忽略其余声部并计数告警。
- 打击/六线谱（percussion clef、`<midi-drum>`、tab clef）：拦截。

### 6.2 反复展开（v2 上调到 MVP）
**为什么必须做**：黄金集 79% 含反复。MusicXML 中反复段音符只存一次，不展开就导入会**静默少段**，用户只会认为 App 弄错谱。

**MVP 展开器（量化前对 measure 流做确定性状态机）**：
1. 成对简单反复：遇 `backward`（:||）且本遍未反复 → 跳回匹配的 `forward`（||:，无则回段首/曲首），第二遍走到 backward 后继续。
2. volta 房子：按 `<ending number>` 与遍次选小节——第 1 遍走 1 房、第 2 遍跳过 1 房走 2 房；支持常见 1/2 房（必要时 3 房）。
3. 在**原始小节层**展开，和弦随小节复制；展开后再统一量化，保证旋律层与和弦 JazzSong 层小节一一对应。

**拦截边界（不写盘）**：
- 出现任何 D.S./D.C./segno/coda/Fine/To Coda（检测覆盖 `<words>`、`<sound>`、barline 的 `segno/coda`、rehearsal，不能只看文字）。
- **完备性硬闸门**：任何 `<repeat>/<ending>` 未能被上述规则处理（不配对、未知 ending 类型、跳转目标缺失）→ 一律拦截，**绝不输出可能变短的结果**。
- 展开结果过 V20/V23 终检。
- 验收：黄金集中"仅含简单反复+volta、无非线性跳转"子集，Swift 展开结果与 music21 `expandRepeats()` 的小节序列逐小节对齐；music21 自身展开失败的 3 首，Swift 侧同样要求拦截而非硬展。

### 6.3 压缩 .mxl
MVP 不支持，给可操作提示；二期 ZIPFoundation 解 container.xml。

---

## 7. 校验 / 报错规则（落库前闸门）

三级：**BLOCK**（整曲跳过不入库）/ **AUTO_FIX**（确定性、不改旋律音高，计数）/ **WARN**（可用但报告）。

| # | 规则 | 级别 | 处置 |
|---|---|---|---|
| V1 | 非 MusicXML：扩展名命中但根元素非 `score-partwise`，或解析失败 / score-timewise | BLOCK | "不是受支持的 MusicXML（partwise）" |
| V2 | `.mxl` 压缩包（MVP） | BLOCK | 提示导出未压缩 .musicxml |
| V3 | 无 Part / 无任何音符 | BLOCK | "谱面为空" |
| V4 | **多个含音符 Part**，或鼓谱/TAB | BLOCK | "仅支持单旋律 lead sheet / 不支持鼓谱六线谱" |
| V5 | 拍号不在 §3.2，或全曲 >1 种拍号/复合混合拍 | BLOCK | 报告检测到的拍号 |
| V6 | 全曲无 `<harmony>`（v1） | BLOCK | "缺少和弦标记"，引导用带和弦的 lead sheet |
| V7 | 含 D.S./D.C./segno/coda/Fine 等非线性跳转 | BLOCK | 提示在 MuseScore 展开反复后重新导出 |
| V8 | 存在展开器无法证明已完整处理的 repeat/ending | BLOCK | 不允许静默变短（§6.2 完备性闸门） |
| V9 | 非休止音缺 `<pitch>` 或音高无法解析 | BLOCK（该曲，定位小节） | — |
| V10 | 小节时值合计 < spm−10 | AUTO_FIX | 尾部补标准休止（finalize pad） |
| V11 | 小节时值溢出 >10 且末音吸收不了 | BLOCK（定位小节） | 不静默截断 |
| V12 | 悬空 tieStart | AUTO_FIX | 跑 §5.3；修复后仍不闭合→BLOCK |
| V13 | 孤儿 tieEnd | AUTO_FIX | 能补则补 tieStart，否则去 tieEnd |
| V14 | 非三连音 N 连音 | WARN | 量化近似；累计误差每小节 >15 slots→BLOCK |
| V15 | 32 分以下碎音 | AUTO_FIX | 同音并入/休止折叠，计数 |
| V16 | 重升/重降、等音拼写 | WARN | 等音转换后入库 |
| V17 | 个别和弦无法 resolve | WARN | 保留显示+计数；不可解析率 >20%→BLOCK |
| V18 | 同 Part 多声部已取 voice 1 | WARN | 提示可能漏声部，建议单旋律谱 |
| V19 | `<transpose>` 移调 / grace / 歌词 / 力度 / 装饰音被忽略；**style 固定 Medium Swing（原曲若为 bossa/waltz/ballad 伴奏风格会变）** | WARN（汇总计数） | 不影响旋律与和弦；风格降级须明示，避免被当成 bug |
| V20 | **落库终检**：每小节 slots 守恒（含 tie 拆分）、连音仿真 0 卡音/0 叠响、每小节 ≥1 和弦、三连音网格对齐 | BLOCK（不过不写盘） | 与内置库同强度 |
| V21 | **和弦锚点强制验收**：chordAnnotations 与 chordSlots 等长，且每个标签 noteIndex 的时间与 startSlot 最近（防标签叠在一起） | BLOCK（该曲） | v2 由普通规则升为强制项 |
| V22 | **调号验收**：首小节调号升降号数 = fifths；调名能被 `getVexflowKey` 解析（不回落错误调） | BLOCK/WARN | 映射缺失即报错，不静默落 C |
| V23 | **反复展开验收**：展开后小节数/总时值与反复语义一致，简单反复子集与黄金集 music21 结果对齐 | BLOCK | 见 §6.2 |

**导入报告**：扩展 `FileImportResult`，每首跳过曲带 `{标题, 原因码(Vx), 详情(小节号/检测值)}`；汇总弹窗复用 `importedTotalCount/importSkippedCount/mixedAlertCount`，新增"告警数"。**任何 BLOCK 都不得写入 `ImportedMelodies`，也不得生成半成品歌单。**

---

## 8. 导入接入（改动点清单，供排期）

> **改动面预期（v2.1 明确）**：这不是"零 Swift 改动"。会新增整个 `Importers/MusicXML/` 目录，并对**两个现有文件**做最小接线——`ContentView.importFromFile` 加一条路由分支、`DocumentPickerView` 加 `.musicxml/.xml` 允许类型；这两处改动需**重新编译发版**。除此之外不碰引擎、播放、渲染与 UI 布局。

1. 新增 `Importers/MusicXML/`：解析器、**反复展开器**、量化器、连音修复、和弦映射、**调号映射**、校验器（纯 Swift，无第三方；`.mxl` 二期才加依赖）。
2. `DocumentPickerView` 允许类型加入 `.musicxml`、`UTType.xml`。
3. `ContentView.importFromFile`：`.json` → **内容嗅探 score-partwise 的 MusicXML 分支** → iReal 文本。MusicXML 输出经 `BuiltinMelodyLibrary.load(from:)` 自检后复用 `persistExternalMelodyFile` 与 `handleImportResult`。
4. 歌单归属沿用现有规则（单曲进 My Songs、多首进命名歌单）；外部旋律作用域用已修好的"来源歌单两级作用域"，避免同名串旋律。
5. 错误文案本地化、可操作（怎么导出/换谱/展开反复）。
6. **不改动** solo 生成、播放引擎、VexFlow 渲染、UI 布局与工具栏尺寸；引擎表达不了的输入走拦截。

---

## 9. 验收与测试（手里有标准答案）

- **黄金集**：`mxl_all/` 400 个 MusicXML 跑 Swift 导入链，与 Python 管线 JSON 对比：
  - 守恒 0 违例；连音仿真 0 卡音/0 叠响；
  - **简单反复+volta 子集与 music21 `expandRepeats()` 逐小节对齐**；非线性跳转子集全部正确拦截；
  - 已交付 78 首（effendi）与内置 34 首逐字段对齐（pitch/duration/tie/chordSlots/key/timeSignature），差异仅限已知人工策略项（如 Days）；
  - **调号**：首小节调号与 fifths 一致；**2/2** 7 首显示与时值正确；三连音/附点/弱起命中率统计；
  - **和弦锚点**：多和弦小节标签位置正确、无重叠。
- **负例集**：无 harmony、混合拍、多 Part 钢琴谱、`.mxl`、鼓谱/TAB、timewise、五连音、悬空 tie、D.S./Coda、不配对反复，断言落到正确 BLOCK/WARN。
- **真机回归**：导入后在 VexFlow 视图检查调号/拍号/和弦位置/连音线/三连音/弱起/反复后小节；播放验证无卡音、伴奏跟和弦切换。

---

## 10. 明确不做（避免范围蔓延）

- 不替换渲染引擎（不引入 OSMD/Verovio，不维护第二套乐谱栈）。
- 不改 solo 生成 / 播放 / 渲染 / UI。
- v1 不做：`.mxl` 解压、D.S./D.C./Coda 等非线性跳转展开、多 Part 旋律智能选择、移调乐器、grace note、纯旋律无和弦导入。
- 不做歌词/力度/装饰音/指法/表情/鼓谱/六线谱。
- 不替用户猜和弦（无 harmony 即报错）；不对用户文件做改旋律音高的连音方案 b。

---

## 11. 风险与实话

1. **最大风险是输入良莠不齐，不是解析本身。** 离线管线为 400 个精修谱做过大量特判；用户文件在多声部、记谱规范度上更杂。v2 用"多 Part 直接拦、非线性跳转直接拦、展开不完备直接拦"把启发式风险换成明确拒绝，宁可少导不可错导。
2. **反复展开是 v2 相对 v1 最大的新增工作量**，但它是确定性状态机、可被 music21 黄金结果逐小节验证，风险可控；真正难的非线性跳转已划到拦截侧。
3. **和弦写法杂**，但直接复用 `ChordSymbolMapper` 静态表，覆盖不到的降级+计数，不重造。
4. **调号是 v1 漏掉的真实工作项（评审纠错）**：需要 fifths/mode 映射并验收，但工作量小、词表封闭。
5. MVP 承诺收敛为：**未压缩单 Part lead sheet + 含和弦 + §3.2 单一拍号（含 2/2）+ 简单反复/volta 展开 + 调号正确**，覆盖现有 78/34 的主体形态，并对覆盖不到的输入给明确、可操作的拒绝理由。

---

## 12. 开工顺序（每步都用黄金集机器对比，不靠人耳）

> 评审建议、已采纳。每个里程碑都有可机器判定的出口条件，达不到不进入下一步。

**M1 — 解析 + 映射 + 量化（先不碰反复）**
- 范围：`MusicXMLParser`（全量中间模型、divisions 逐小节）、`MusicXMLKeyMap`（§5.1 调号）、`MusicXMLChordMapper`（§3.4.1 kind+degree）、`MusicXMLQuantizer`（§4 量化/守恒）、`MusicXMLTieRepair`（§5.3）、前导无和弦回填。
- 输入：黄金集中**无反复/已线性**的谱。
- 出口条件：与 Python 管线 JSON **逐事件对齐**（pitch/duration/tie/chordSlots/key/timeSignature）；守恒 0 违例、连音仿真 0 卡音/0 叠响；产出 §3.4.1 要求的 **kind/degree→resolve 全量对照表与 ChordSymbolMapper 命中率**，未命中组合归类清楚。

**M2 — 反复展开器**
- 范围：`MusicXMLRepeatExpander`（§6.2 成对 forward/backward + volta），在量化前对 measure 流操作；V7/V8/V23 拦截与验收。
- 出口条件：简单反复+volta 子集与 music21 `expandRepeats()` **逐小节对齐**；D.S./D.C./segno/coda/Fine 及任何展不完的结构**全部正确拦截**（负例断言），绝不静默变短。

**M3 — 接线 + 落库 + 报告 + 回归**
- 范围：`ContentView.importFromFile` 路由（内容嗅探 score-partwise）、`DocumentPickerView` UTType、`persistExternalMelodyFile`/`handleImportResult` 接入、V1–V23 导入报告（含 style 降级说明）。
- 出口条件：负例集（无 harmony/混合拍/多 Part/.mxl/鼓谱 TAB/timewise/五连音/悬空 tie/非线性跳转/不配对反复）全部落到正确 BLOCK/WARN；全 400 首黄金集跑通；真机回归——调号/拍号(含 2/2)/和弦锚点/连音线/三连音/弱起/反复后小节显示正确，播放无卡音、伴奏跟和弦切换。
