# P3-c.2 逐 hunk 落地 diff —— 手写伴奏专属响度补偿（常数真机定标）

日期：2026-10-11　｜　性质：**纯播放/渲染层混音常数与接线，2 改文件、2 个 hunk**
不碰：solo 四链路（Guide/Grammar/Transform/Learning）、.sty 解析与资源、伴奏生成 pattern、付费、Roadmap、默认风格、UI、pbxproj。
状态：**待书面批准，批准前生产零改动**。

---

## 一、乐手版背景（为什么 P3-e 数学等响了，真机还是 Simple 偏弱）

P3-e 用「每小节 Σvel² 能量归一」把保留的三个手写伴奏（Simple Shuffle / Simple Afro / Simple Bossa）与 Java .sty 锁到同一能量目标，隔离探针误差 rel=0.00%。但真机并听三对风格（Simple Shuffle↔Shuffle、Simple Afro↔African、Simple Bossa↔Bossa），Simple 仍明显偏弱。

根因（隔离探针 `/tmp/p3e/diag.swift`，6 种和弦进行 × 3 对风格实测）：**能量平方（Σvel²）只是响度代理，在编制悬殊 3~11 倍时失效**。

- 同一小节 Java 织体远比手写丰满（raw 能量 Java/手写 比值）：

  | 轨 | raw 能量 Java/手写（6 曲区间） | 典型音符数（12 小节 Blues） |
  |---|---|---|
  | 钢琴 | **1.2 ~ 11.2 倍** | 手写 68 音 vs Java 181 音 |
  | 贝司 | 1.7 ~ 4.2 倍 | 手写 36 vs Java 51 |
  | 鼓 | 3.4 ~ 6.7 倍 | Simple 单件/少量 Ride；African 手写 444 件 vs Java 605 件（全套鼓） |

- P3-e 的做法是「Java 丰满→把节点音量关小；手写稀疏→把节点音量开大」，使 Σvel²×音量² 相等。但人耳的响度还取决于**发声密度（时间占空比）、频谱覆盖、低频持续**：Java 是持续铺满被整体关小，手写是少量音点被单独拧大、留白多且缺中低频，所以数字相等、耳朵仍觉得 Simple 又弱又空。
- 这正是 P3-c 时既定方法论「探针给初值、最终增益以真机并听 Java 为准」要覆盖的情形；P3-e 误把探针 0% 误差当终验、跳过了真机定标，本轮补回。

### 为什么不是别的原因（均已排除）
- **不是接错分支**：`isStyStyle` 是注册表精确匹配（StyleEngine.swift:119 `idToResource[style] != nil`），手写 rawValue "Shuffle/Afro/Bossa" 必返回 false、走 else 放大支（JazzMidiPlayer.swift:180-189）；`style.lowercased()` 后命中 AccompanimentGenerator.swift:47/53/71，与探针同路径。
- **不是 handGainCap=1.6 截断**：6 曲实测手写真实需求倍数全部 ≤1.51（最大 3/4 曲 Bossa 贝司 1.51、鼓 1.49），未触 1.6。**所以抬 handGainCap 没有用**，本轮不改它。
- **不是小节数分母错**：generate（:520-522）与 configureAccompanimentMix（:529）都用同一 `remainingMeasures`。
- **不是推子/fader**：手写与 .sty 共用同一组推子，A/B 切风格时推子不变。

---

## 二、修复思路（最小侵入）

在 P3-e 能量归一**之后**、采样器节点音量上，给**手写三轨**各乘一个专属响度补偿常数（线性振幅倍数），并在末端钳 0...1 保证不削波；`.sty` 分支一行不动。

- 能量归一 gHand / handGainCap / 鼓编制补偿 1.4 全部保留不变；
- 新增 `handPianoBoost / handBassBoost / handDrumBoost`，只作用于手写 else 支的最终 `gain[...]`；
- 末端 `max(0, min(1, …))` 是节点音量硬顶（与 applyTrackGain :127 同款钳制），**结构上保证永不削波**；
- 常数即「节点音量振幅倍数」，真机直接调、所见即所得，无需改任何逻辑；
- 钢琴织体最稀（raw 比最高 11 倍）给最大补偿 1.6，贝司/鼓给 1.3。

### 起始值与不削波验证（隔离探针 `/tmp/p3e/verify2.swift`，复刻生产公式 + 本补偿，6 曲 × 3 风格）
- 起始值：**钢琴 ×1.6（≈+4.1dB）、贝司 ×1.3（≈+2.3dB）、鼓 ×1.3（≈+2.3dB）**。
- 补偿后手写最终能量 / .sty 目标：恒定 **钢琴 2.56（=1.6²）、贝司/鼓 1.69（=1.3²）**，说明 gHand 全程未触顶、补偿充分生效。
- 三轨节点音量 contentGain **峰值 = 0.928**（3/4 曲 Bossa 贝司），**0 个轨次触顶（=1）**，4/4 主流曲峰值约 0.87。→ 起始值全程 <1，不削波，可作真机定标起点。
- 该 2.56/1.69 倍是「为补偿稀疏织体听感折损」有意上修，**最终以真机并听锁定**：若 Simple 反而偏响就下调常数，仍弱就上调；每 +0.1 常数约 +0.6~0.8dB。

### 边界（如实说明）
- 本补偿解决「弱」。若真机定标后仍觉得 Simple「空/薄」（发声点少、铺底不满），那是编制密度的审美差异，只能靠补音/改编曲解决，属生成层（本轮红线内不做），可另行立项评估。
- 本轮不新增/删除任何伴奏、不改菜单与导入映射（P3-e 结论保持）。

---

## 三、备份与基线 SHA1（落地第一步执行，含双端核对）

落地时先整文件备份到 `.backup/P3c2-20261011/`（目录已建、为空，位于同步根 `Real imPro` 之外、不打包）：

```
cp "Real imPro/MidiPlayer/StyleEngine/AccompanimentMix.swift" ".backup/P3c2-20261011/AccompanimentMix.swift.bak"
cp "Real imPro/MidiPlayer/JazzMidiPlayer.swift"               ".backup/P3c2-20261011/JazzMidiPlayer.swift.bak"
shasum -a 1 ".backup/P3c2-20261011/AccompanimentMix.swift.bak" ".backup/P3c2-20261011/JazzMidiPlayer.swift.bak"
```

**落地前当前生产 SHA1（P3-e 后，已实测，备份必须与此一致）：**

| 文件 | SHA1 |
|---|---|
| Real imPro/MidiPlayer/StyleEngine/AccompanimentMix.swift | `d2315cd47057e34b5d6f52d74a93e053a943ed6d` |
| Real imPro/MidiPlayer/JazzMidiPlayer.swift | `969b444c2c12786d691236520c416159777af8ed` |

---

## 四、逐 hunk 精确 diff（旧码中文原位封存，不删除）

### H1 ｜ AccompanimentMix.swift：新增三个手写响度补偿常数

位置：现 `handGainCap`（:44）之后、枚举结束 `}`（:45）之前新增一段。

**新增（新码）：**
```swift

    // ⑦ [P3-c.2] 手写专属响度补偿（线性振幅倍数，直接乘节点音量；能量变化≈平方）。
    //    真机实测：仅靠 ⑥ 的每小节 Σvel² 能量归一，手写与 .sty 数学等响但听感仍偏弱/空——
    //    手写老 pattern 织体比 .sty 稀 3~11 倍（钢琴音点少、鼓单件 Ride），把少数音拧大≠持续铺满。
    //    故在能量归一之后、节点音量上再给手写三轨一个额外乘区，补偿稀疏织体的听感折损；.sty 不套此乘区。
    //    起始值经隔离探针验证 contentGain 峰值 0.928<1（不削波）；最终以真机并听同族 .sty 定标，
    //    来回切 Simple Shuffle/Afro/Bossa ↔ Java，听感等响即锁定，过响↓、仍弱↑。
    //    钢琴织体最稀（raw 能量比最高达 11 倍）给最大补偿，贝司/鼓次之。
    static let handPianoBoost: Float = 1.6   // 振幅 ×1.6 ≈ +4.1dB
    static let handBassBoost:  Float = 1.3   // 振幅 ×1.3 ≈ +2.3dB
    static let handDrumBoost:  Float = 1.3   // 振幅 ×1.3 ≈ +2.3dB
```

---

### H2 ｜ JazzMidiPlayer.swift：手写 else 支节点音量乘补偿 + 末端钳 0...1

位置：`configureAccompanimentMix` 内 **else（手写）支**，现 :183-189。
注意：if isSty 支（:173-179）有外形相同的三行 `gain[1/2/3] = …`，**本轮不改**；为保证旧码块唯一匹配，old_string 必须从手写支独有的 `let gP = normHand(` 起整段替换。

**旧码（P3-e 现状，:183-189，逐字）：**
```swift
            let gP = normHand(AccompanimentMix.refPianoEnergy, perMeasureEnergy(backing.pianoNotes))
            let gB = normHand(AccompanimentMix.refBassEnergy,  perMeasureEnergy(backing.bassNotes))
            let gD = normHand(AccompanimentMix.refDrumEnergy,  perMeasureEnergy(backing.drumNotes),
                              boost: AccompanimentMix.drumEnsembleBoost)
            gain[1] = AccompanimentMix.seatPiano * gP * AccompanimentMix.trimPiano
            gain[2] = AccompanimentMix.seatBass  * gB * AccompanimentMix.trimBass
            gain[3] = AccompanimentMix.seatDrum  * gD * AccompanimentMix.trimDrum
```

**新码（替换为）：**
```swift
            let gP = normHand(AccompanimentMix.refPianoEnergy, perMeasureEnergy(backing.pianoNotes))
            let gB = normHand(AccompanimentMix.refBassEnergy,  perMeasureEnergy(backing.bassNotes))
            let gD = normHand(AccompanimentMix.refDrumEnergy,  perMeasureEnergy(backing.drumNotes),
                              boost: AccompanimentMix.drumEnsembleBoost)
            // [P3-c.2] 手写节点音量在归一基础上再乘专属响度补偿（AccompanimentMix.hand*Boost），末端钳 0...1 防削波。
            gain[1] = max(0, min(1, AccompanimentMix.seatPiano * gP * AccompanimentMix.trimPiano * AccompanimentMix.handPianoBoost))
            gain[2] = max(0, min(1, AccompanimentMix.seatBass  * gB * AccompanimentMix.trimBass  * AccompanimentMix.handBassBoost))
            gain[3] = max(0, min(1, AccompanimentMix.seatDrum  * gD * AccompanimentMix.trimDrum  * AccompanimentMix.handDrumBoost))
            // [旧码封存 P3-c.2 20261011] P3-e 手写节点音量无专属响度补偿（数学等响但稀疏织体听感偏弱）：
            // gain[1] = AccompanimentMix.seatPiano * gP * AccompanimentMix.trimPiano
            // gain[2] = AccompanimentMix.seatBass  * gB * AccompanimentMix.trimBass
            // gain[3] = AccompanimentMix.seatDrum  * gD * AccompanimentMix.trimDrum
```

> if isSty 支（:171-179）与 `norm()` / `normHand()` 函数本体（:155-164）、handGainCap（AccompanimentMix :44）本轮**逐字不动**。

---

## 五、落地步骤（书面批准后按序执行）

1. 整文件备份 2 文件并核对 SHA1 = 第三节基线；
2. 应用 H1（新增常数）、H2（手写 else 支三行 + 封存注释）；
3. 落 `scripts/rollback_p3c2.sh`（见第七节）并 `bash -n`；
4. Xcode GUI：⇧⌘K Clean Build Folder → Debug、Release 双 Build，确认各 0 error；
5. 跑第六节回归门；
6. 真机并听定标（第六节 B），锁定三个常数（如需偏离起始值，仅改 AccompanimentMix 三个数字、重编即可，不动其他）；
7. find 无夹带核对，汇总数值与听感回报。

---

## 六、回归门（落地后实测回报）

### A. 数值/构建（自动）
- Xcode GUI Debug + Release 双 Build Succeeded、0 error；两包 sty=50、tsv=26、rnn=2。
- 50 个 .sty 守恒探针 CLEAN=50 / WARN=0 / CRASH=0。
- **.sty 响度零变化**：if isSty 支与 norm() 未改；重跑等响探针，15 个代表 .sty 三轨最终能量仍 = 1935/7036/16493、g≤1。
- 手写补偿验证：重跑 verify2 型探针，contentGain 全程 ≤1（起始值峰值 0.928）、0 触顶。
- 资源指纹：26 .tsv = 11,235,463 B；combination.rnn = GreatMoments.rnn = 9,136,016 B。
- solo 四链路金标准不变（本轮仅 2 个播放层文件、无一生成链路文件；独奏轨 track0 恒 1.0）：Guide 18,470、raw grammar 30/30、Transform diff 0、Learning 双 1536（以依赖边界 + 资源指纹论证，同 P3 系列口径）。
- find 无夹带：落地窗口仅 AccompanimentMix.swift、JazzMidiPlayer.swift 两个 .swift 被改。

### B. 真机并听定标（人工，本轮最终验收标准）
1. 同一首曲、同一速度，三对来回切：Simple Shuffle↔Shuffle（及 Boogie Shuffle）、Simple Afro↔African/African Triplet、Simple Bossa↔Bossa/Bossa A/Bossa B。
2. 目标：来回切**响度一致**（不要求织体一样满，但不允许 Simple 明显轻）；鼓组不压残、钢琴垫底可闻、独奏萨克斯始终最突出。
3. 若 Simple 偏响 → 对应轨常数下调（如钢琴 1.6→1.4/1.5）；仍弱 → 上调（注意 contentGain 末端钳 1，到 1 后再调无效，需回报）。
4. 推子/静音实时生效；短曲多次播放不跳、不中断；无旋律谱不空白；选曲/转调/生成/Original⇄Solo 后正确刷新不残留。
5. 至少在 iPad mini 真机 + 一个中速 4/4 曲、一个慢板曲上各验一遍。

---

## 七、一键回退脚本（落地时写入 `scripts/rollback_p3c2.sh`，chmod +x）

```bash
#!/bin/bash
# P3-c.2 回退：恢复 2 个备份文件（移除手写专属响度补偿，回到 P3-e 状态）
set -u
PROJ="/Users/onlyonear/Desktop/Improlyze"
BK="$PROJ/.backup/P3c2-20261011"
cd "$PROJ" || exit 9
cp "$BK/AccompanimentMix.swift.bak" "Real imPro/MidiPlayer/StyleEngine/AccompanimentMix.swift"
cp "$BK/JazzMidiPlayer.swift.bak"        "Real imPro/MidiPlayer/JazzMidiPlayer.swift"
echo "已回退 P3-c.2，回退后 SHA1："
shasum -a 1 "Real imPro/MidiPlayer/StyleEngine/AccompanimentMix.swift" \
            "Real imPro/MidiPlayer/JazzMidiPlayer.swift"
echo "请在 Xcode ⇧⌘K Clean Build Folder 后全量重建。"
```
回退后 SHA1 应为：AccompanimentMix `d2315cd4…`、JazzMidiPlayer `969b444c…`（即第三节基线）。

---

## 八、无夹带声明

本 diff 仅改动 2 个播放层文件：AccompanimentMix.swift（新增 3 个常数）、JazzMidiPlayer.swift（仅手写 else 支 3 行节点音量加乘补偿与钳制 + 旧码中文封存注释）。不改 if isSty（.sty）分支、不改 norm/normHand 函数与 handGainCap、不改任何生成/解析/资源/UI/付费/默认风格，不新增伴奏或菜单项，不新增顶栏，用户可见文案无「Java」。旧码一律中文注释原位封存、不删除。新增文件仅同步根外的 `scripts/rollback_p3c2.sh`。
