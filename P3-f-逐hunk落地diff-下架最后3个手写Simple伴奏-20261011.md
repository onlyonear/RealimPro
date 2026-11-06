# P3-f 逐 hunk 落地 diff —— 下架最后 3 个手写 Simple 伴奏（Simple Shuffle / Simple Afro / Simple Bossa）

日期：2026-10-11　｜　状态：**只读勘察 + 精确 diff，生产零改动，等用户书面批准后才落地**
性质：纯 UI 枚举/菜单 + 导入映射；**2 改文件、6 个 hunk**。不碰任何 .sty/.tsv/.rnn 资源、伴奏生成与播放算法、solo 四链路、付费、Roadmap、默认风格、pbxproj。

---

## 一、乐手版：要做什么

把菜单里最后三个「手写简化版」伴奏——**Simple Shuffle、Simple Afro、Simple Bossa**——像上次下架 Simple Swing 一样摘掉。摘完之后，**菜单里 50 个伴奏全部是 Java 移植的 .sty 原版**，全都走同一套响度校准，「Simple 那一档明显偏轻」的问题从根上不存在，也不再需要 P3-c.2 的手写专属补偿。

- 旧曲/新歌导入若带 shuffle / bossa / afro(african) 风格标签，**自动落到对应的 Java 版**（Shuffle / Bossa / African），绝不会落到被删的手写型，也不会空白。
- 手写生成/播放代码**不删**，原样保留为「不可达存档」（和上次下架 Simple Swing/Ballad/Waltz/Latin 完全一致的做法），可一键回退。

## 二、勘察结论（只读，已逐处核实）

### 1. 三个手写项在全工程的活跃引用（删枚举必须同步处理的，共 6 处，全部在本轮 2 个文件内）

| # | 文件:行 | 内容 | 处理 |
|---|---|---|---|
| H1 | BandMixerView.swift:19-22 | 枚举 `case blues="Shuffle"` / `case afro="Afro"` / `case bossa="Bossa"` | 注释封存 |
| H2 | BandMixerView.swift:96/100/101 | displayName 返回 "Simple Shuffle"/"Simple Afro"/"Simple Bossa" | 注释封存 |
| H3 | BandMixerView.swift:188 | Shuffle 子菜单首位 `.blues` | 移除（旧行封存） |
| H4 | BandMixerView.swift:224 | Bossa 子菜单首位 `.bossa` | 移除（旧行封存） |
| H5 | BandMixerView.swift:233 | Afro 子菜单首位 `.afro` | 移除（旧行封存） |
| H6 | ContentView.swift:2430/2432/2434 | 导入嗅探返回 `.bossa` / `.afro` / `.blues` | 改返回同族 Java `.styBossa` / `.styAfrican` / `.styShuffle`（旧行封存） |

- `MixerDisplayMode` 全工程**仅 1 个穷尽 switch**（displayName，BandMixerView.swift:93）；另两个 switch（:244/:250）属于 `PianoVoicingMode`，与本枚举无关。删 case 只需同步 H2，无其他编译断点。
- `MixerDisplayMode.allCases` **无活跃遍历**（仅 BandMixerView.swift:392/394 封存注释里出现）。
- `selectedStyle` 是 **@State 非持久化**（ContentView.swift:977，默认 `.stySwing`），删枚举不产生 UserDefaults 悬空、不影响启动。

### 2. 同名误报（**不动**，已逐一甄别）

- AccompanimentGenerator.swift:48/54/72 的 `DrumPattern.blues()/.bossa()/.afro()` 是**方法调用**；:47/:53/:71 的 `case "shuffle"/"bossa"/"afro"` 是**字符串 switch**（不是枚举）。
- JazzMidiPlayer.swift:477-479 `swingProfile(for:)` 的 `case "shuffle"/"afro"/"bossa"` 也是字符串 switch；.sty 时被文件头 compSwing/melodySwing 覆盖（:529-530 `??`），这些 case 本就只服务手写。
- DrumPattern / BassPattern / ChordPattern(+Extractor) 内的 `.blues()/.bossa()/.afro()` 方法与 `"shuffle"/"bossa"/"afro"` 字符串 case，均为手写 pattern 实现。
- RhythmBlueprint.swift:27/77 的 `.bossa` 属内部枚举 `RhythmBlueprint.JazzStyle`；BrickLibrary/BrickDictionaryParser 的 `.blues` 是 Roadmap 曲式分类；IRealProParser.swift:857-879 是 **BPM 探测**（返回速度数值）；StyleEngine.swift:90/103/107 的 `"shuffle"/"bossa"/"african"` 是 **.sty 资源名**。

以上在三个手写枚举 case 删除、H6 改映射后，**全部成为不可达存档但仍可编译**（字符串 switch 有 default、方法仍被存档代码引用），按 P3-e 惯例本轮**零改动**。

### 3. 下架后菜单盘点（50 项，全部 .sty，与资源数严格相等）

| 区块 | 下架前 | 下架后 |
|---|---|---|
| groupedSections：Swing / Shuffle / Rock / Latin / Funk / Blues | 11 / **5** / 11 / 10 / 2 / 2 = 41（Shuffle 含手写 Simple Shuffle） | 11 / **4** / 11 / 10 / 2 / 2 = **40** |
| standalone：two-beat / tango | 2 | **2** |
| preservedSections：Ballad / Bossa / Waltz / Afro | 1 / **4** / 2 / **3** = 10（Bossa、Afro 各含 1 手写） | 1 / **3** / 2 / **2** = **8** |
| **菜单可选合计** | 53（50 .sty + 3 手写） | **50（全部 .sty）** |

- Shuffle 子菜单剩 4 个 Java：Swing(shuffle)、Cloppety、Boogie 1、Boogie 2。
- Bossa 子菜单剩 3 个 Java：Bossa、Bossa A、Bossa B。
- Afro 子菜单剩 2 个 Java：African、African 3（均 >1，菜单体 BandMixerView.swift:435 的「单项才拍平」逻辑不会触发，三组仍为二级子菜单，**菜单体零改动**）。
- 映射目标资源均已在 StyleEngine 注册表核实存在：`sty:shuffle`（StyleEngine.swift:90）、`sty:bossa`（:103）、`sty:african`（:107）。
- 下架后所有可选 rawValue 都满足 `StyleEngine.isStyStyle==true`（StyleEngine.swift:119），AccompanimentGenerator 的手写 switch（:40 起）与 JazzMidiPlayer 的手写播放支（含 P3-c.2 hand*Boost）**彻底不可达**，但保留不删。

## 三、备份与回退

- 备份目录：`.backup/P3f-20261011/`
  - `BandMixerView.swift.bak`，SHA1 = **721e930ac5cc021a604c8c88c24e4c81c1acf5d7**
  - `ContentView.swift.bak`，SHA1 = **d69d1afae158c618fcd022bf7fd31f53787c1a40**
- 回退脚本（落地时落盘 `scripts/rollback_p3f.sh`，chmod +x）：

```bash
#!/bin/bash
set -euo pipefail
PROJ="/Users/onlyonear/Desktop/Improlyze"
BK="$PROJ/.backup/P3f-20261011"
cp "$BK/BandMixerView.swift.bak" "$PROJ/Real imPro/Views/BandMixerView.swift"
cp "$BK/ContentView.swift.bak"   "$PROJ/Real imPro/Views/ContentView.swift"
echo "已回退 P3-f。回退后 SHA1 应为："
echo "  BandMixerView 721e930ac5cc021a604c8c88c24e4c81c1acf5d7"
echo "  ContentView    d69d1afae158c618fcd022bf7fd31f53787c1a40"
echo "请在 Xcode ⇧⌘K Clean Build Folder 后重新构建。"
```

## 四、逐 hunk 精确 diff（旧码中文原位封存，不删除）

### 文件 1：Real imPro/Views/BandMixerView.swift（SHA1 721e930a…）

#### H1 — 枚举：三个手写 case 注释封存（替换现 :13-22 区块）

旧码（逐字）：
```swift
    // [P3-e] 真机听感下架，旧码封存（AccompanimentGenerator 内对应字符串分支保留为“不可达存档”，
    //        导入旧曲经 matchStyleMode 自动映射同族 Java 版，不会再走到这些手写分支）：
    // case swing  = "Swing"     // 原 Simple Swing（默认风格已迁移到 .stySwing，见 ContentView）
    // case ballad = "Ballad"    // 原 Simple Ballad
    // case waltz  = "Waltz"     // 原 Simple Waltz
    // case latin  = "Latin"     // 原 Simple Latin
    case blues  = "Shuffle"   // 显示 Simple Shuffle，Shuffle 子菜单置顶
    case afro   = "Afro"      // Simple Afro，Afro 子菜单置顶
    //case bebop  = "Bebop"
    case bossa  = "Bossa"     // Simple Bossa，Bossa 子菜单置顶
```
新码：
```swift
    // [P3-e + P3-f] 7 个手写风格已全部真机听感下架，旧码封存（AccompanimentGenerator/JazzMidiPlayer 内对应
    //        字符串分支与手写 pattern 保留为“不可达存档”；导入旧曲经 matchStyleMode 一律映射同族 Java .sty）：
    // case swing  = "Swing"     // 原 Simple Swing（默认风格已迁移到 .stySwing，见 ContentView）
    // case ballad = "Ballad"    // 原 Simple Ballad
    // case waltz  = "Waltz"     // 原 Simple Waltz
    // case latin  = "Latin"     // 原 Simple Latin
    // [P3-f] 下架最后三个手写（Simple Shuffle/Afro/Bossa），彻底统一为 .sty 响度：
    // case blues  = "Shuffle"   // 原 Simple Shuffle
    // case afro   = "Afro"      // 原 Simple Afro
    //case bebop  = "Bebop"
    // case bossa  = "Bossa"     // 原 Simple Bossa
```

#### H2 — displayName：三行返回值注释封存（替换现 :94-102 区块内三行）

旧码（逐字，保留其余已注释行）：
```swift
        // 手写（[P3-e] Simple Swing / Simple Latin / Simple Ballad / Simple Waltz 已下架，旧码封存；保留 Simple Shuffle / Simple Afro / Simple Bossa）
        // case .swing:  return "Simple Swing"
        case .blues:  return "Simple Shuffle"
        // case .latin:  return "Simple Latin"
        // [P3-d] 手写保留项加 Simple 前缀（[P3-e] ballad 已下架、旧码封存）：
        // case .ballad: return "Simple Ballad"
        case .afro:   return "Simple Afro"
        case .bossa:  return "Simple Bossa"
        // case .waltz: return "Simple Waltz"
```
新码：
```swift
        // 手写（[P3-e + P3-f] 7 个手写风格已全部下架，旧码封存；菜单仅保留 Java .sty）：
        // case .swing:  return "Simple Swing"
        // [P3-f] case .blues:  return "Simple Shuffle"
        // case .latin:  return "Simple Latin"
        // [P3-d] 手写保留项加 Simple 前缀（[P3-e] ballad 已下架、旧码封存）：
        // case .ballad: return "Simple Ballad"
        // [P3-f] case .afro:   return "Simple Afro"
        // [P3-f] case .bossa:  return "Simple Bossa"
        // case .waltz: return "Simple Waltz"
```

#### H3 — Shuffle 子菜单移除手写首位（替换现 :186-189）

旧码（逐字）：
```swift
        StyleMenuSection(id: "shuffle", title: "Shuffle", items: [
            // P3-b.1 下架 Light Shuffle，旧码封存：.blues, .styShuffle, .styShuffleLight, .styCloppety, .styBoogie1, .styBoogie2
            .blues, .styShuffle, .styCloppety, .styBoogie1, .styBoogie2
        ]),
```
新码：
```swift
        StyleMenuSection(id: "shuffle", title: "Shuffle", items: [
            // P3-b.1 下架 Light Shuffle，旧码封存：.blues, .styShuffle, .styShuffleLight, .styCloppety, .styBoogie1, .styBoogie2
            // [P3-f] 下架手写 Simple Shuffle（.blues），旧行封存：.blues, .styShuffle, .styCloppety, .styBoogie1, .styBoogie2
            .styShuffle, .styCloppety, .styBoogie1, .styBoogie2
        ]),
```

#### H4 — Bossa 子菜单移除手写首位（替换现 :223-225）

旧码（逐字）：
```swift
        StyleMenuSection(id: "bossa", title: "Bossa", items: [
            .bossa, .styBossa, .styBossaA, .styBossaB
        ]),
```
新码：
```swift
        StyleMenuSection(id: "bossa", title: "Bossa", items: [
            // [P3-f] 下架手写 Simple Bossa（.bossa），旧行封存：.bossa, .styBossa, .styBossaA, .styBossaB
            .styBossa, .styBossaA, .styBossaB
        ]),
```

#### H5 — Afro 子菜单移除手写首位（替换现 :231-234）

旧码（逐字）：
```swift
        StyleMenuSection(id: "afro", title: "Afro", items: [
            // [P3-e 下架 .styAfricanSlow（仅 Ride 镲、真机听感不佳），旧行封存：.afro, .styAfrican, .styAfricanSlow, .styAfrican3
            .afro, .styAfrican, .styAfrican3
        ])
```
新码：
```swift
        StyleMenuSection(id: "afro", title: "Afro", items: [
            // [P3-e 下架 .styAfricanSlow（仅 Ride 镲、真机听感不佳），旧行封存：.afro, .styAfrican, .styAfricanSlow, .styAfrican3
            // [P3-f] 下架手写 Simple Afro（.afro），旧行封存：.afro, .styAfrican, .styAfrican3
            .styAfrican, .styAfrican3
        ])
```

### 文件 2：Real imPro/Views/ContentView.swift（SHA1 d69d1afa…）

#### H6 — 导入嗅探：三种标签改映射同族 Java（替换现 :2422-2435 区块内注释与三行）

旧码（逐字，:2422-2435；未列出的 waltz/latin/ballad/兜底行保持不变）：
```swift
        // [P3-e] 手写 waltz/latin/ballad 与默认 swing 已随真机听感下架，嗅探一律改映射同族 Java .sty；
        //        保留的手写只有 bossa/afro/blues(shuffle)。所有返回值（含兜底）均为保留项，绝不落到被删的 7 个型。
        // 旧码封存：
        // if lower.contains("waltz") || lower.contains("3/4") { return .waltz }
        // if lower.contains("latin") ... { return .latin }
        // if lower.contains("ballad") { return .ballad }
        // return .swing
        if lower.contains("waltz") || lower.contains("3/4") { return .styWaltz }
        if lower.contains("bossa") { return .bossa }
        if lower.contains("latin") || lower.contains("samba") || lower.contains("rhumba") || lower.contains("mambo") { return .styLatin }
        if lower.contains("afro") || lower.contains("african") { return .afro }
        if lower.contains("ballad") { return .styBallad }
        if lower.contains("blues") || lower.contains("shuffle") { return .blues }
        return .stySwing
```
新码：
```swift
        // [P3-e + P3-f] 7 个手写风格已全部下架，嗅探一律映射同族 Java .sty；所有返回值（含兜底）均为 .sty，
        //        无论导入新歌还是旧曲，都不会落到任何已删除的手写型（Simple 系列）。
        // 旧码封存：
        // if lower.contains("waltz") || lower.contains("3/4") { return .waltz }
        // if lower.contains("latin") ... { return .latin }
        // if lower.contains("ballad") { return .ballad }
        // return .swing
        if lower.contains("waltz") || lower.contains("3/4") { return .styWaltz }
        // [P3-f] 旧手写映射封存：if lower.contains("bossa") { return .bossa }
        if lower.contains("bossa") { return .styBossa }
        if lower.contains("latin") || lower.contains("samba") || lower.contains("rhumba") || lower.contains("mambo") { return .styLatin }
        // [P3-f] 旧手写映射封存：if lower.contains("afro") || lower.contains("african") { return .afro }
        if lower.contains("afro") || lower.contains("african") { return .styAfrican }
        if lower.contains("ballad") { return .styBallad }
        // [P3-f] 旧手写映射封存：if lower.contains("blues") || lower.contains("shuffle") { return .blues }
        if lower.contains("blues") || lower.contains("shuffle") { return .styShuffle }
        return .stySwing
```

## 五、明确不改（无夹带）

- 不删任何资源：.sty 仍 **50**、.tsv 26、.rnn 2；不 mv、不动 Resources。
- AccompanimentGenerator.swift、JazzMidiPlayer.swift、AccompanimentMix.swift、DrumPattern/BassPattern/ChordPattern(+Extractor).swift **零改动**（手写字符串分支、swingProfile、P3-c.2 hand*Boost 全部成为不可达存档，保留不删、不发声）。
- 菜单体拍平逻辑、StyleMenuSection、styleMenuButton、调音台、默认风格 `.stySwing`、solo 四链路、Roadmap、付费、pbxproj 一律不动。
- 不新增顶栏/付费点，用户可见文案无「Java」。

## 六、落地步骤（书面批准后）

1. 建 `.backup/P3f-20261011/`，cp 两文件并 `shasum -a 1` 核对 = 721e930a… / d69d1afa…；
2. 落盘 `scripts/rollback_p3f.sh` 并 `bash -n`；
3. 按 H1→H6 逐 hunk 应用（旧码中文原位封存）；
4. Xcode GUI ⇧⌘K Clean Build Folder，Debug + Release 各 Build 一次，均 0 error；
5. 跑第七节回归门；`find "Real imPro" -name '*.swift' -newermt '<落地时刻>'` 硬证据仅 2 文件；
6. 汇总数值与截图回报。

## 七、回归门（落地后实测回报）

**数值门**
- Xcode GUI Debug + Release 双 Build Succeeded、0 error（重点：删枚举后无 `type 'MixerDisplayMode' has no member` 悬空引用）。
- 两包 `.sty=50、.tsv=26、.rnn=2`；26 .tsv 合计 **11,235,463 B**；combination/GreatMoments.rnn 各 **9,136,016 B**。
- 50 .sty 渲染守恒探针 **CLEAN=50、WARN/CRASH/MISS=0**（引擎零改，应保持）。
- solo 金标准零影响（本轮无一生成/播放链路文件被改、track0 恒 1.0）：Guide 18,470、grammar 30:30、Transform diff 0、Learning 双 1536。

**行为门（真机/模拟器，人工）**
1. Style 菜单中**不再出现** Simple Shuffle / Simple Afro / Simple Bossa；Shuffle / Bossa / Afro 三个子菜单点开分别只剩 4 / 3 / 2 个 Java 项，无 "Simple" 前缀项。
2. 三个子菜单逐项可点、正常出声；来回切换响度一致（全走 .sty 同一混音归一，无偏轻档）。
3. 导入含 shuffle / blues / bossa / afro / african 风格标签的**新歌与旧曲**，伴奏分别自动落到 Shuffle(sty:shuffle) / Bossa(sty:bossa) / African(sty:african)，不空白、不落到任何被删型。
4. 默认 stySwing；选曲、转调、生成 solo、Original⇄Solo 切换后菜单与谱面正确刷新、不残留。
5. 6 组 iPad 尺寸（mini/11/13 × 横竖，mini 竖先）三个子菜单不截断、不压五线谱/#钮、右栏恒宽 110。

**无夹带**：find 仅 BandMixerView.swift、ContentView.swift 两个生产文件被改。
