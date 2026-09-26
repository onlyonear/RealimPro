# PROVENANCE — 逐文件来源清单（合规工作底稿）

更新日期：2026-09-26
对象：`Real imPro`（App Store 产品，最新版 1.06；iPad only，部署目标 iPadOS 16.6）

## 类别图例

| 标记 | 含义 |
| --- | --- |
| **V** | 逐字复制 Impro-Visor 文件（已用 diff 验证一致） |
| **D** | 由 Impro-Visor 数据机械转换/生成（衍生数据） |
| **P** | Swift 移植/重写 Impro-Visor Java 代码（衍生作品），文件头注释有明确移植标记 |
| **P?** | 高度疑似移植，但文件头无明确标记，**需逐行确认** |
| **O** | 本人原创代码 |
| **T** | 第三方组件，按其自有许可证分发 |
| **?** | 来源待确认 |

说明：无论 O/P 如何分类，本仓库整体按 **GPL v2** 发布；分类只用于署名与第三方许可证核对。GPL v2 第 0 条明确规定"翻译成另一种语言"属于修改，因此 Java→Swift 的移植整体受 GPL 约束。

## 已核验的关键事实

1. **combination.rnn = D（已核验）**：文件头 `RNN1`，首个权重矩阵为 300×350，与上游 `connectomes/combination.ctome`（ZIP，含 40 个 CSV 权重）中的 `param_0_lstm1_input_w.csv`（300 行 × 350 列）完全对应；网络结构（2 experts、2 LSTM 层、full 层、initial state 600 = 300 cell + 300 hidden）与 ctome 内容一一对应。即由 ctome 的 CSV 经离线工具打包转换而成。
2. **ChoriumRevA.sf2 = T（已核验来源，许可待确认）**：内嵌元数据 INAM = "Chorium Custom Revision"，ICRD = 2023-05-21，IENG = openwrld@kebi.com，ICOP = "all rights reserved to the author(s)"。即 openwrld（ChoriumRevA 作者）2023 年的自定义修订版，**不是** un4seen 上的原始 ChoriumRevA。已起草致 openwrld 的再分发许可邮件。
3. **builtin_classic_jazz.json 的 34 曲全部 PD（已核验）**：全部为 1930 年及以前出版的作品；1930 年作品于 2026-01-01 进入美国公有领域（Duke 大学 PD Day 2026 名单含 I Got Rhythm、But Not for Me、Embraceable You、I've Got a Crush on You 等）。逐曲年份见文末附录。
4. **版本快照**：v1.0 / v1.01 / v1.03 / v1.06 有快照可重建；v1.02 / v1.04 / v1.05 无快照，不做假 tag，以邮件源码承诺覆盖。

## 一、根目录

| 文件 | 类别 | 备注 |
| --- | --- | --- |
| DebugLog.swift | O | |
| Launch Screen.storyboard | O | |
| vexflow-min.js | T | VexFlow，MIT 许可 |

## 二、BuiltinLibrary

| 文件 | 类别 | 备注 |
| --- | --- | --- |
| builtin_classic_jazz.json | O（数据 PD） | 34 首 PD 曲目，含原旋律；年份核验见附录 |
| BuiltinMelodyLibrary.swift | O | 加载逻辑 |
| RegionGate.swift | O | |

## 三、CoreEngine

| 文件 | 类别 | 备注 |
| --- | --- | --- |
| JazzEngine.swift | P? | 引擎抽象层，待确认 |
| JazzStrategy.swift | P? | |
| MelodyPart.swift | P? | 与上游 MelodyPart.java 同名，优先核对 |

## 四、Expectancy

| 文件 | 类别 | 备注 |
| --- | --- | --- |
| ExcpectancyCore.swift | P? | 上游有 expectancy 模型，待确认 |

## 五、FullVoicing（全部为衍生）

| 文件 | 类别 | 备注 |
| --- | --- | --- |
| ChordFormMaps.swift | D | 文件头自述：My.voc 经 Java ExportMaps 金标准导出 |
| ChordFormVoicing.swift | P | 对齐 ChordForm.getVoicings L976 |
| ChordSymbolMapper.swift | P | 对齐 Chord.makeChord / PitchClass.findRise |
| FullVoicingEngine.swift | P | 对齐 ChordPattern.getVoicingAndExtensionList L1050-1089 |
| JazzVoicingTemplates.swift | D | My.voc 经 Java DumpVoicingTemplates 导出 |
| VoicingPlacer.swift | P | 逐方法对齐 ChordPattern.placeVoicing/Above/Below 等 |
| VoicingRNG.swift | P | 对齐 getRandomItem |

## 六、Grammar

| 文件 | 类别 | 备注 |
| --- | --- | --- |
| ApproachType.swift | P? | |
| Grammar.swift | P? | |
| GrammarLickGlue.swift | P? | |
| GrammarNCPBridge.swift | P? | |
| GrammarNoteConverter.swift | P? | |
| GrammarStrategy.swift | P | 对齐 Java Grammar.run |
| GrammarTerminals.swift | P | 对齐 Constants.java L881-884 |
| NoteChooser.swift | P? | |
| PitchProbTable.swift | P | 移植 LickGen.fillProbs（L960-1076） |
| TupletSanitizer.swift | P? | |

## 七、grammars（数据文件）

| 文件 | 类别 | 备注 |
| --- | --- | --- |
| My.dictionary | **V** | 与上游 `vocab/My.dictionary` 逐字节一致 |
| BillEvans.grammar | **V** | 与上游 `grammars/BillEvans.grammar` 逐字节一致 |
| JoePass.grammar | **V** | 与上游 `grammars/JoePass.grammar` 逐字节一致 |
| chord.rules | D | 规则行与上游 chord.grammar 完全一致（diff 验证） |
| color.rules | D | 规则行与上游 color.grammar 完全一致（diff 验证） |
| Ballads.rules | D | 以 Impro-Visor 文法语法编写，按衍生数据处理 |
| Bebop.rules | D | 同上（含 BRICK/slope 规则） |
| BillEvans.rules | D | |
| Blues.rules | D | |
| Bossa Nova.rules | D | |
| CannonballAdderley.rules | D | |
| ChetBaker.rules | D | |
| greatMoments.rules | D | |
| JoePass.rules | D | |
| JohnColtrane.rules | D | |
| MilesDavis.rules | D | 1401 行，体量大于上游 MilesDavis.soloist（277 行），为自行扩写 |
| RedGarland.rules | D | |
| Waltzes.rules | D | |

## 八、GuideTone

| 文件 | 类别 | 备注 |
| --- | --- | --- |
| GTVocResolver.swift | P | 对齐 Java colorBox 档位 |
| GuideLineGenerator.swift | P | 严格对齐 Java GuideLineGenerator |
| GuideToneVocabularyTable.swift | P? | |
| JazzGuideToneEngine.swift | P | 浓缩自 Java Note.java 与 PitchClass.java |

## 九、Harmony

| 文件 | 类别 | 备注 |
| --- | --- | --- |
| ChordForm.swift | P? | 与 Java 和声模型对应，待逐行确认 |
| Coloration.swift | P? | |
| Constants.swift | P? | |
| JazzHarmonicModels.swift | P? | |
| Key.swift | P? | |
| NoteSpelling.swift | P? | |
| PitchClass.swift | P? | |
| ScaleForm.swift | P? | |
| Transposition.swift | P? | |

## 十、Importers/MusicXML（v1.06 快照中不含该目录；属后续版本）

| 文件 | 类别 | 备注 |
| --- | --- | --- |
| MusicXMLChordMapper.swift | O | 自有导入功能 |
| MusicXMLImporter.swift | O | |
| MusicXMLKeyMap.swift | O | |
| MusicXMLParser.swift | O | |
| MusicXMLQuantizer.swift | O | |
| MusicXMLRepeater.swift | O | 反复展开思路参考 music21（BSD-3-Clause），独立实现，已在 NOTICE 署名 |

## 十一、LSTM（v1.06 快照中不含该目录；属后续版本）

| 文件 | 类别 | 备注 |
| --- | --- | --- |
| combination.rnn | D | 由 combination.ctome 打包转换（核验过程见上文） |
| LSTMStrategy.swift | P? | |
| RNNLSTM.swift | P | 对齐 LSTM.java（门顺序、state 结构） |
| RNNMath.swift | P | 算子对齐 Java(mikera/vectorz)；**为独立重写，未复制 mikera 代码**（mikera 为 LGPL-3.0） |
| RNNMelody.swift | P | 对齐上游 token 解码 |
| RNNModel.swift | P? | RNN1 格式加载器 |
| RNNPostprocessors.swift | P | 对齐 Rectify 等 Postprocessor |
| RNNProductModel.swift | P | 对齐 IntervalRelativeNoteEncoding |

## 十二、MidiPlayer

| 文件 | 类别 | 备注 |
| --- | --- | --- |
| ChoriumRevA.sf2 | T | openwrld 2023 自定义修订；再分发许可待作者确认 |
| AccompanimentGenerator.swift | P? | |
| AccompanimentModels.swift | P? | |
| BassPattern.swift | P? | |
| BassPatternExtractor.swift | P? | 伴奏型提取疑似移植 |
| ChordPattern.swift | P | 对齐 Java `(push 8/3)` 时间线 |
| ChordPatternExtractor.swift | P? | |
| DrumPattern.swift | P? | |
| DrumPatternExtractor.swift | P | |
| JazzMidiPlayer.swift | O? | iOS 播放实现，待确认 |
| Pattern.swift | P? | |
| PatternElement.swift | P? | |
| TimeSignatureManager.swift | P? | |

## 十三、Rhythm

| 文件 | 类别 | 备注 |
| --- | --- | --- |
| ChordExtensionTonePool.swift | P? | |
| RhythmBlueprint.swift | P? | |
| RhythmGenerator.swift | P | 对应 Generator.java 第 33-65 行 |
| Syncopation.swift | P? | |
| TensionAnalyzer.swift | P | 对应 Tension.java 第 31-63 行 |
| Unit+SlottedNote.swift | P? | |

## 十四、Roadmap

| 文件 | 类别 | 备注 |
| --- | --- | --- |
| BrickDictionaryParser.swift | P | 解析上游 My.dictionary |
| BrickLibrary.swift | P? | |
| CYKParser.swift | P? | 对应上游 CYK 解析器 |
| IRealProParser.swift | O | iReal Pro 格式互操作解析 |
| JazzRoadmap.swift | P | 对应 RoadMap.java |
| JazzSong.swift | P? | |
| KeyAnalysisModels.swift | P? | |
| KeySpan.swift | P? | |
| PostProcessor.swift | P? | |
| PostProcessorFull.swift | P | 完整移植 findKeys()，注释标注 Java 行号 149-367 等 |
| SubstitutionDictionary.swift | P? | |

## 十五、ThemeWeaver

| 文件 | 类别 | 备注 |
| --- | --- | --- |
| JavaLCG.swift | P | 对齐 ThemeWeaver.java:179/187 的 java.util.Random |
| MotifSeedGenerator.swift | P | |
| MotifTextParser.swift | P? | |
| MotifTransform.swift | P | 对齐 Note.shiftPitch、MelodyPart.java:1590 |
| SectionConnector.swift | P | 1:1 移植 ThemeWeaver.java:5053-5209 |
| ThemeGrammarFallback.swift | P | 对齐 generateFromGrammar:5694 |
| ThemeModel.swift | P? | |
| ThemeWeaverEngine.swift | P | 对齐 myGenerateSolo:4890、adjustTheme:5257 |
| ThemeWeaverStrategy.swift | P | |

## 十六、TransformEngine

| 文件 | 类别 | 备注 |
| --- | --- | --- |
| Evaluate.swift | P | 对应 Evaluate.java（约 1540 行） |
| GuideTransformBridge.swift | P | |
| JavaAlignedTransformEngine.swift | P | |
| MelodyTransformAdapter.swift | P | 对齐 applySubstitutionsToPart |
| MusicTools.swift | P | 对齐 Duration.getDuration |
| NCPIterator.swift | P? | |
| NoteChordPair.swift | P? | |
| Scorer.swift | P? | |
| Substitution.swift | P? | |
| Transform.swift | P? | |
| Transform+Defaults.swift | O | 旧链手写 19 组默认模板，明确保留 |
| Transformation.swift | P? | |
| TransformationTesting.swift | P? | |
| TransformLearning.swift | P? | |
| TransformMusicianRegistry.swift | P? | |
| TransformRNG.swift | P | 重实现 java.util.Random 算法 |
| TransformRuleTable.swift | P? | |
| TransformVocabulary.swift | P? | |
| TrendBase.swift | P | 移植 trends/ 系列 |
| TrendDetector.swift | P? | |
| TrendSegment.swift | P? | |

## 十七、TransformTables（26 个，全部 D）

由上游 `transforms/*.transform`（S-表达式）机械转换为 TSV，26 个文件名一一对应：
BillEvans, BobBerg, CedarWalton, CharlieParker, CliffordBrown, ColemanHawkins, DizzyGillespie, FreddieHubbard, JackieMcLean, JimmyHeath, JoeHenderson, JoeLovano, JohnColtrane, KennyGarrett, LeeMorgan, LesterYoung, MilesDavis, My, NickBrignola, PaulDesmond, RedGarland, RichPerry, StanGetz, TomHarrell, VincentHerring, WesMontgomery（均为 .tsv）。

## 十八、Views（UI 层，原则上 O）

| 文件 | 类别 | 备注 |
| --- | --- | --- |
| ImprolyzeApp.swift | O | App 入口 |
| ContentView.swift | O | 含移植胶水代码（如 ImproVisorOriginalGuideToneStrategy 注入） |
| BandMixerView.swift | O | |
| ChordDictionaryView.swift | O | |
| DocumentPickerView.swift | O | |
| IAPManager.swift | O | StoreKit 内购管理 |
| MotifEntryView.swift | O | |
| NoteColorLegendView.swift | O | |
| PaywallView.swift | O | |
| SheetMusicView.swift | O | |
| TransformMusicianCatalog.swift | O | |

## 附录：34 曲 PD 核验（出版年份）

| 曲目 | 作者 | 出版年 |
| --- | --- | --- |
| They Didn't Believe Me | Jerome Kern | 1914 |
| You Made Me Love You | James V. Monaco | 1913 |
| The Love Nest | Louis A. Hirsch | 1920 |
| Look for the Silver Lining | Jerome Kern | 1919 |
| Indian Summer | Victor Herbert | 1919 |
| Avalon | Vincent Rose | 1920 |
| Do It Again | George Gershwin | 1922 |
| My Buddy | Walter Donaldson | 1922 |
| Limehouse Blues | Philip Braham | 1921 |
| Can't Help Lovin' Dat Man | Jerome Kern | 1927 |
| Ol' Man River | Jerome Kern | 1927 |
| Why Do I Love You | Jerome Kern | 1927 |
| How Long Has This Been Going On? | George Gershwin | 1927 |
| 'S Wonderful | George Gershwin | 1927 |
| Soon | George Gershwin | 1927 |
| If I Could Be with You | James P. Johnson | 1926 |
| Somebody Loves Me | George Gershwin | 1924 |
| Fascinating Rhythm | George Gershwin | 1924 |
| Oh, Lady Be Good | George Gershwin | 1924 |
| Embraceable You | George Gershwin | 1930 |
| I've Got a Crush on You | George Gershwin | 1930 |
| Bidin' My Time | George Gershwin | 1930 |
| But Not for Me | George Gershwin | 1930 |
| I Got Rhythm | George Gershwin | 1930 |
| Strike Up the Band | George Gershwin | 1930 |
| Liza | George Gershwin | 1929 |
| Mean to Me | Roy Turk / Fred Ahlert | 1929 |
| I'll Get By | Fred Ahlert | 1928 |
| Makin' Whoopee | Walter Donaldson | 1928 |
| Love Me or Leave Me | Walter Donaldson | 1928 |
| Beyond the Blue Horizon | Whiting / Harling | 1930 |
| My Baby Just Cares for Me | Walter Donaldson | 1930 |
| Danny Boy | Weatherly / traditional | 1913 |
| Down by the Riverside | traditional | 19 世纪 |

注：以上为美国版权状态（95 年保护期，1930 年作品 2025 年起 PD，2026 年在售全部合规）。若在欧盟销售，"Beyond the Blue Horizon" 共同作者 Harling（卒于 1958）的保护期至 2028 年，建议欧盟区先下架该曲或该区域不提供。

## 仍待确认

- P? 类文件（约 50 个）本人确认是否为移植；建议抽查 CoreEngine/MelodyPart、Harmony 全目录、MidiPlayer 各 Pattern。
- 是否给移植 Swift 文件逐个加 GPL 头注释（严格做法），还是以 NOTICE + App 内许可页集中声明（常见实践，建议先用后者）。
