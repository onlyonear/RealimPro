# P3-b.1 落地回归报告 · 下架 3 个真机听感不佳的伴奏（46 → 43）

- 日期：2026-10-11
- 工程：Real imPro（SwiftUI iPadOS，部署 iOS 16.6，scheme/target = RealimPro）
- 性质：纯 UI/注册表/资源删减，**未改任何算法、伴奏取音、solo 四链路、默认值、付费归属**
- 依据：用户书面批准「落地 P3-b.1」；diff 见《P3-c调研-贝斯音域与响度-附P3b1下架三风格diff-20261011.md》第三部分
- 结论：✅ 自动化回归门全绿，可交真机人工点验嵌套菜单

---

## 一、乐手版说明（一句话）

把你真机听感不喜欢的 3 个伴奏从菜单和资源里下架：**Light Shuffle、Triplet Rock、Triplet Rock 2**。
其余 43 个伴奏一个不动、默认仍是 Simple Swing、生成与播放效果零变化；下架的 3 个文件没有删除，移到了备份目录，随时能一键恢复成 46 个。

---

## 二、改动清单（5 处 hunk，2 个生产文件 + 1 个探针脚本 + 3 个资源移动）

| Hunk | 文件:行（现状） | 内容 |
|---|---|---|
| H1 | `Real imPro/MidiPlayer/StyleEngine/StyleEngine.swift:80-86` | 注册表 `styResourceNames`：Shuffle 5→4（删 shuffle-light）、Rock 13→11（删 rock-triplet / rock-triplet-2，folk-rock 保留）；旧数组整块中文注释封存 |
| H2 | `Real imPro/Views/BandMixerView.swift:38,52-54` | 枚举删 `styShuffleLight / styRockTriplet / styRockTriplet2`（穷尽 switch 同步），旧 case 中文封存；分组头注释 Shuffle 4 / Rock 11 |
| H3 | `BandMixerView.swift:104,118-120` | `displayName` 删 3 项返回，旧码中文封存 |
| H4 | `BandMixerView.swift:161,167` | 二级菜单 Shuffle / Rock 分组项删 3 项，旧项中文封存 |
| H5 | `scripts/p3b_regress.sh` | 探针 ITEMS 与期望改为 CLEAN=43 |
| 资源 | `Real imPro/Resources/Styles/` | 3 个 .sty 用 `mv` 移入备份（**未 rm**），源目录 46→43 |

下架后分组计数：**Swing 11 + Shuffle 4 + Rock 11 + Latin 10 + Funk 2 + Blues 3 + Two-Beat 1 + Tango 1 = 43**。

### SHA1 核对

| 文件 | 改前（=P3-b 基线，备份 .bak） | 改后（当前生产） |
|---|---|---|
| StyleEngine.swift | `26111d768fe7c89ce15a34842e2a87107d0d8004` | `63abdedfd19198c940805546a5d762dfa2c035af` |
| BandMixerView.swift | `c849ee0eb08358e2d28e95a4154c1f798dd214c2` | `890397d6424dd3135c6b08e14db579c4e810e1e1` |

备份目录：`.backup/P3b1-20261011/`（含 `StyleEngine.swift.bak`、`BandMixerView.swift.bak`、`p3b_regress.sh.bak`、`removed_styles/{shuffle-light,rock-triplet,rock-triplet-2}.sty`）。备份 SHA1 已与 P3-b 基线逐一核对一致。

---

## 三、一键回退

- 脚本：`scripts/rollback_p3b1.sh`（`bash -n` 语法校验通过，幂等可重复运行）
- 动作：恢复 2 个 .swift 与探针脚本 → 移回 3 个 .sty → SHA1 自检（须回到 `26111d76…` / `c849ee0e…`）→ 校验 Styles 目录恢复 46
- 回退后在 Xcode 按 **⇧⌘K Clean Build Folder 再 ⌘B**（删除资源后必须 Clean，增量构建不会清掉包里的旧 .sty，见下「五、踩坑记录」）

---

## 四、回归门实测数值

| 门 | 期望 | 实测 | 结果 |
|---|---|---|---|
| Xcode GUI 构建 | 0 error | Clean Build Folder 后全量 **Build Succeeded 15:18，0 error**（当前 scheme 为 Release 配置，产物 `Release-iphonesimulator`） | ✅ |
| `.app` 内 .sty 数 | 43 | **43**；被删 3 个在包内 = **0** | ✅ |
| 包内分组 | Swing11/Shuffle4/Rock11/Latin10/Funk2/Blues3/Two1/Tango1 | 逐组计数合计 43，无 shuffle-light / rock-triplet | ✅ |
| 43 风格 CLEAN 探针 | CLEAN=43 / WARN=0 / CRASH=0 / MISSING=0 | **CLEAN=43 WARN=0 CRASH/PARSEFAIL=0 MISSING=0 总计=43** | ✅ |
| 8 位大师 Swing 鼓 | d 非空、end7680（H1 修复不回归） | d143–162 end7680，全部非空 | ✅ |
| swing 本体（扁平） | 不回归 | `swing` d162、`swing-backbeat` d223、`swing-square-comp` d98 | ✅ |
| 资源指纹 .tsv | 26 个 / 11,235,463 B | **26 个 / 11,235,463 B** | ✅ |
| 资源指纹 .rnn | 2 个 / 各 9,136,016 B | **2 个 / 合计 18,272,032 B** | ✅ |
| solo 四链路 | Guide 18,470 / grammar 30:30 / Transform diff 0 / Learning 双 1536 / 守恒 0 | **本次零改动**：Guide/Grammar/LSTM/Transform 全部源文件 mtime 最晚 10-10，早于本窗口；伴奏取音引擎（StyleParser/三 Renderer）亦未改，仅删注册表字符串与菜单项，无数值变化路径，结果沿用 P3-b 实测 | ✅（零改动路径） |
| 模拟器启动 | 不崩 / 默认 Simple Swing / Demo 无旋律不空白 | iPad mini(A17 Pro) 安装 Release 包启动，进程状态 0；首屏 Roadmap 正常、STYLE=SIMPLE SWING、调音台正常（截图 `/tmp/p3b1_mini_p3b1.png`） | ✅ |

### 无夹带硬证据

今天 15:00 后工程内改动/新增（排除 `.backup` / `.git` / `xcuserdata` / 报告 .md）仅 4 个文件：

```
./Real imPro/MidiPlayer/StyleEngine/StyleEngine.swift   （H1）
./Real imPro/Views/BandMixerView.swift                  （H2/H3/H4）
./scripts/p3b_regress.sh                                （H5）
./scripts/rollback_p3b1.sh                              （新增回退脚本）
```

未翻任何默认、未新增付费点或顶栏、用户可见处无「Java」、`project.pbxproj` 未改动（同步根自动收录/移除资源）。

---

## 五、踩坑记录（供后续）

增量 ⌘B（15:13）虽然 Build Succeeded，但**没有把删除的 3 个 .sty 从 .app 清掉，包内仍是 46**——Xcode 的 PBXFileSystemSynchronizedRootGroup 对「删除资源」的增量拷贝不会清理旧产物。
处理：**Product > Clean Build Folder（⇧⌘K）→ 全量 ⌘B（15:18）**，之后包内为 43、被删 3 个为 0。以后凡是删除/改名资源，都需 Clean 后全量重建再核对包内计数。
另：当前 Run 配置为 **Release**（Clean 已清掉旧 Debug 产物，权威包在 `Release-iphonesimulator`）；本次改动为纯数组/菜单/资源，与构建配置无关，Debug 配置在 P3-b 已双验。

---

## 六、待真机人工点验（simctl 无法操作嵌套菜单）

请在真机/模拟器打开 Style 二级菜单确认：

1. **Shuffle 子菜单** = Simple Shuffle + 4 个 .sty（shuffle / shuffle-cloppety / boogie-shuffle-1 / boogie-shuffle-2），**无 Light Shuffle**；
2. **Rock 子菜单** = 11 个，**无 Triplet Rock / Triplet Rock 2**，**Folk Rock 仍在**；
3. 其余 Swing(11) / Latin(10) / Funk(2) / Blues(3) / Two-Beat / Tango 数量不变、可正常选中播放；
4. 切到这 43 个伴奏生成/播放正常，默认 Simple Swing 不变。

---

## 七、下一阶段（暂停，另行书面报批）

**P3-c（贝斯音域 + 响度校准 + 两个真 bug）** 只读调研已完成、方向经两方 AI 认可（方案 C：播放端按来源归一 + Java 主次比例），但**隔离探针与逐 hunk diff 尚未开始**。拟修：

- `JazzMidiPlayer.swift:106` masterGain 单位误用（线性值塞进 dB）→ 固定 0 dB，音量只走线性 volume；
- `StyleChordRenderer.swift:142` 钢琴力度 127+8=135 越界 → clamp 到 1…127（±8/±3 人性化保留）；
- .sty 贝斯渲染端由 G2–C4 覆盖回 Java 引擎内置默认 **G1(31)–G3(55)**（G1 vs E1 留真机 A/B）；
- 播放端按来源归一 + Java 主次比例（melody 1.0 / bass·drum ≈0.47 / piano ≈0.31），归一系数探针给初值、最终真机并听 Java 校准，鼓不压残；
- 不翻默认风格（仍 Simple Swing）、不碰 solo 四链路与 .sty 资源。

**P3-b.1 落地完成，现暂停，等待真机点验结果与 P3-c 的书面批准。**
