# P3-c.2 落地与验证报告 —— 手写伴奏专属响度补偿

日期：2026-10-11　｜　状态：**代码已落地、自动数值门全绿；真机并听定标待用户完成（最终三常数以真机为准）**
性质：纯播放/渲染层，2 改文件、2 个 hunk；不碰 solo 四链路、.sty 解析与资源、伴奏生成 pattern、付费、Roadmap、默认风格、UI、pbxproj。

---

## 一、乐手版改了什么

给保留的三个手写伴奏（Simple Shuffle / Simple Afro / Simple Bossa）在「最终送到扬声器的音量」上各加一个固定放大：**钢琴 ×1.6、贝司 ×1.3、鼓 ×1.3**，Java 那 50 个 .sty 伴奏一个数都不碰。放大后末端硬钳不超过满音量，**结构上不可能爆音**。这三个数是安全起始值，最终以真机并听锁定。

## 二、实际落地（与批准 diff 一致）

| 文件 | hunk | 内容 |
|---|---|---|
| Real imPro/MidiPlayer/StyleEngine/AccompanimentMix.swift | H1（:45 起新增 ⑦ 段） | 新增 `handPianoBoost=1.6`、`handBassBoost=1.3`、`handDrumBoost=1.3`（含中文注释） |
| Real imPro/MidiPlayer/JazzMidiPlayer.swift | H2（configureAccompanimentMix 手写 else 支 :188-190） | 手写三轨节点音量在归一后再乘对应 hand*Boost，`max(0,min(1,…))` 末端钳 0...1；旧三行中文注释原位封存（:191-194） |

- `.sty` 分支（if isSty，:177-179）、`norm()` / `normHand()`、`handGainCap=1.6` 逐字未动（`diff 备份` 已直接证明）。
- 备份（含 SHA1，已核对一致）：`.backup/P3c2-20261011/AccompanimentMix.swift.bak`、`JazzMidiPlayer.swift.bak`。
- 回退脚本：`scripts/rollback_p3c2.sh`（已 chmod +x、`bash -n` 通过）；回退后 SHA1 = AccompanimentMix `d2315cd4…`、JazzMidiPlayer `969b444c…`。

## 三、构建（Xcode GUI，权威）

⇧⌘K Clean Build Folder 后：
- **Release：Build Succeeded（20:43）0 error**；
- **Debug：Build Succeeded（20:39）0 error**；
- 验证完已把 Run Build Configuration **切回 Release**（用户原状）。
- 命令行 AssetCatalogAgent/宏插件 spawn 环境怪象本轮未介入，以 GUI 为准。

## 四、数值门（全部实测通过）

| 门 | 预期 | 实测 | 结论 |
|---|---|---|---|
| 两包 .sty 计数 | 50 | Debug 50 / Release 50 | ✅ |
| 两包 .tsv / .rnn 计数 | 26 / 2 | 26 / 2（两包） | ✅ |
| 26 个 .tsv 合计字节 | 11,235,463 B | 11,235,463 B | ✅ |
| combination.rnn / GreatMoments.rnn | 各 9,136,016 B | 9,136,016 / 9,136,016 | ✅ |
| 50 .sty 渲染守恒探针 | CLEAN=50，WARN/CRASH/MISS=0 | CLEAN=50，WARN=0 CRASH=0 MISS=0 | ✅ |
| .sty 混音支零变化 | 15 代表风格 finalE=1935/7036/16493 | 15/15 命中，ALL PASS(0 failure) | ✅ |
| 手写补偿不削波（verify2，6 曲×3 风格） | contentGain<1、0 触顶 | **峰值 0.928（3/4 曲 Bossa 贝司），触顶 0 次** | ✅ |
| 补偿量充分生效 | 钢琴 2.56×、贝司鼓 1.69×（=倍数平方） | 恒定 2.56 / 1.69 / 1.69，gHand 未触 cap | ✅ |
| find 无夹带 | 仅 2 个 .swift | 仅 AccompanimentMix.swift、JazzMidiPlayer.swift；同步根内无其他文件改动 | ✅ |

- solo 四链路（Guide 18,470 / grammar 30:30 / Transform diff 0 / Learning 双 1536）本轮无一生成链路文件被改、独奏轨 track0 恒 1.0，且 .tsv/.rnn 字节指纹不变，按 P3 系列既定口径论证零影响（未重跑 solo 探针）。

## 五、真机并听定标（**需用户完成，本轮最终验收**）

请在 Xcode 选真机 iPad mini（Run 已为 Release 配置）编译运行，同一首曲、同一速度，三对来回切：
1. Simple Shuffle ↔ Shuffle（及 Boogie Shuffle）；
2. Simple Afro ↔ African / African Triplet；
3. Simple Bossa ↔ Bossa / Bossa A / Bossa B。

**目标**：来回切响度一致（不要求织体一样满，但 Simple 不能明显轻）；强奏 solo 与补偿后伴奏齐鸣处主输出不破音；鼓组不压残、钢琴垫底可闻、独奏萨克斯始终最突出。

**调常数（只改 AccompanimentMix 三个数字、重编即可，不动其他）**：
- Simple 偏响 → 对应轨下调（如钢琴 1.6→1.4/1.5）；仍弱 → 上调；
- 每 +0.1 约 +0.6~0.8dB；钢琴 1.6≈+4.1dB、贝司/鼓 1.3≈+2.3dB；
- 末端钳 1.0：若某轨调到头（contentGain=1）仍觉弱，**不要再加**（会被钳住无效），记录下来——那属于织体密度的「空/薄」，需补音/改编曲，另行立项，不在本轮红线内。

另请顺手回归：推子/静音实时生效；短曲多次播放不跳；无旋律谱不空白；选曲/转调/生成/Original⇄Solo 后正确刷新不残留。

## 六、回退

`bash scripts/rollback_p3c2.sh`（恢复 2 文件到 P3-e 状态），随后 ⇧⌘K Clean Build Folder 全量重建。

## 七、无夹带声明

落地窗口仅改动 AccompanimentMix.swift、JazzMidiPlayer.swift 两个播放层文件（find 硬证据），新增文件仅同步根外 `scripts/rollback_p3c2.sh`。未改 .sty 支/能量归一函数/handGainCap，未改任何生成/解析/资源/UI/付费/默认风格，未新增伴奏或顶栏，用户可见文案无「Java」；旧码中文注释原位封存、未删除。
