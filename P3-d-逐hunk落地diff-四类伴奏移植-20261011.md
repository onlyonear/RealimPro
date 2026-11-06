# P3-d 逐 hunk 落地 diff —— Ballad / Bossa / Waltz / Afro 四类 Java .sty 伴奏移植（二级子菜单）

> 日期：2026-10-11　工程根：`/Users/onlyonear/Desktop/Improlyze`　生产目录：`Real imPro/`（含空格）
> scheme/target：RealimPro　最低部署 iOS 16.6
> 性质：**伴奏资源移植 + 菜单 UI/接线**。不碰 solo 四链路算法、引擎整流、默认值、付费、Roadmap 分析。
> 状态：**只读勘察 + /tmp 隔离探针已完成，生产零改动；待书面批准后才落地。**

---

## 0. 乐手版概述（先看这段）

- 把 Java 原版的 **10 个伴奏配方**装进 App，挂到现在调音台 Style 菜单里 **Ballad / Bossa / Waltz / Afro 四个标签的二级子菜单**中（和现在 Swing 子菜单一个用法）。每个子菜单第一项是你原来的手写版（改名 `Simple Xxx` 置顶），后面是 Java 原版的若干个。
- 装完后 .sty 总数 **43 → 53**。
- **Waltz 三个都是 3/4 拍**：只有在 3/4 的曲子里选才完全正确；在 4/4 曲里选，引擎会把 3 拍律动循环塞进 4 拍（不会静音、不会崩，但律动会错位）。本方案**不做"选 Waltz 自动改曲谱拍号"**这种越界逻辑，与现在手写 Waltz 的行为一致。
- 探针发现**两个原版文件本身就缺轨**（不是引擎问题，是 Java 原文件如此），先照你拍板的"全装"，真机试听后再决定是否像上次那样下架：
  - **Chopin Waltz（waltz-chopin.sty，仅 272 B）**：原版**没有鼓**，贝斯极稀疏，是钢琴主导的肖邦风圆舞曲；
  - **African Slow（african-slow.sty，仅 311 B）**：原版**只有一轨 Ride 镲（三连音），没有贝斯、没有钢琴**。
- 探针还发现 bossaA/bossaB 里一个裸写的 `X` 贝斯符号，核实 Java 源码后确认**它和根音 B 完全等价**、现有引擎取音本来就是对的（虚惊一场，详见 §3.4）；附带 1 行**零行为变化**的严谨性补丁（H6，建议带）。

---

## 1. 移植清单（10 个，分四类）

| 子菜单 | Java 资源名（去 .sty） | 拍号 | UI 显示名 | 与手写关系 |
|---|---|---|---|---|
| Ballad | `ballad` | 4/4 | Ballad | 手写 Ballad 本就参照 ballad.sty；原版为完整随机配方（**先全装，试听后定**） |
| Bossa | `bossa` | 4/4 | Bossa | 手写 Bossa 为独立简化版，原版更丰富 |
| Bossa | `bossaA` | 4/4（三连音网格） | Bossa A | 新增 |
| Bossa | `bossaB` | 4/4（三连音网格） | Bossa B | 新增 |
| Waltz | `waltz` | **3/4** | Waltz | 手写 Waltz 独立；原版标准爵士圆舞曲 |
| Waltz | `waltz-chopin` | **3/4** | Chopin Waltz | **原版无鼓、钢琴主导（先全装，试听后定）** |
| Waltz | `waltz-parisienne` | **3/4** | Parisienne Waltz | 新增（巴黎/法国风） |
| Afro | `african` | 4/4（密集三连音） | African | 手写 Afro 的钢琴 4 句即源自此（**先全装，试听后定**） |
| Afro | `african-slow` | 4/4（三连音） | African Slow | **原版仅 Ride 镲、无贝斯/钢琴（先全装，试听后定）** |
| Afro | `african3` | 4/4（三连音） | African Triplet | 新增（三连音版，名为暂定可改） |

> 手写四项显示名改为：`Simple Ballad` / `Simple Bossa` / `Simple Waltz` / `Simple Afro`（与 Simple Swing / Simple Shuffle / Simple Latin 一致）。rawValue（`"Ballad"`/`"Bossa"`/`"Waltz"`/`"Afro"`）**严禁改**，`AccompanimentGenerator` 靠它小写匹配手写分支。

---

## 2. 接线勘察结论（为什么改动面很小）

1. **生成路由已通用，无需改**：`AccompanimentGenerator.swift:32-37` 在手写 switch 之前用 `StyleEngine.shared.isStyStyle(style)` 前置分流，命中即交 `StyleEngine.render` 并透传 `slotsPerMeasure`。新 10 个只要在注册表登记（H1）+ 枚举 rawValue 为 `"sty:"+资源名`（H2），自动走 .sty 引擎，**不会被手写 switch 接走**。
2. **拍号已参数化**：`StyleEngine.render(... slotsPerMeasure:)`（`StyleEngine.swift:128-145`）把 spm 透传给鼓/贝斯/钢琴三渲染器；播放侧 `JazzMidiPlayer.swift:500` `let spm = solo.first?.slotsPerMeasure ?? 480`，即**伴奏拍号跟随曲谱**。工程已有完整拍号表 `TimeSignatureManager`（3/4=360、4/4=480、12/8=720…）。
3. **swing 浓度自动取文件头，无需改**：`StyleEngine.render` 输出 `compSwing/melodySwing`（`StyleEngine.swift:143-144`），`JazzMidiPlayer.swift:508-509` 用它覆盖按风格名猜测的默认值。10 个文件头浓度探针已读出并自动生效（见 §3.1）。
4. **贝斯音域 G1–G3、响度归一自动继承**：P3-c 在 `StyleBassRenderer` 渲染端统一覆盖音域、在播放端对所有 .sty 做能量归一与 velocity clamp。新 10 个**自动受益**，无需再调（探针实测音域/力度全部合规，见 §3.2）。
5. **UI 风格嗅探 `matchStyleMode` 无需改、也不会误路由**：它只在导入/选曲时被调用（`ContentView.swift:2273 / :2334`，入参是 `song.style` 曲谱曲风串），把歌曲映射到一个**手写组**作为默认选中；用户在菜单里手选某个 .sty 子项是直接 `selectedStyle = .styXxx`，**不经过** `matchStyleMode`。新 rawValue 虽含 ballad/bossa/waltz/african 关键词，但该函数输入不是 enum rawValue，故无误路由（与已上线的 43 个 .sty 同机制）。导入 Bossa/Waltz 曲仍默认到手写 Simple 版，属合理默认。
6. **第二播放入口 `playWithAccompanimentAndGraces` 零调用（dead code），本轮不碰、不透传**（P3-a 起即如此）。

---

## 3. /tmp 隔离探针结果（生产零改动）

- 探针：`/tmp/p3d/main.swift` + `/tmp/p3d/run.sh`；**编译直接引用生产源码**（`StyleEngine/*.swift` + Pattern + FullVoicing），自动带 P3-c/P3-c.1 最新逻辑。
- 方法：16 小节 Cmaj7/Am7/Dm7/G7、固定种子 12345；**Waltz 三個用 spm=360（3/4），其余 7 个 spm=480（4/4）**；另对 Waltz 三个跑 spm=480 作 4/4 对照。
- **总结果：10 CLEAN / 0 WARN / 0 CRASH / 0 MISSING。**

### 3.1 逐风格实测（b=贝斯 p=钢琴 d=鼓；[音域] v力度范围 t总时值；end=末音结束/应到）

| 风格 (spm) | pattern b/d/c | 贝斯 | 钢琴 | 鼓 | swing m/c | 备注 |
|---|---|---|---|---|---|---|
| ballad (480) | 8/4/15 | b36 [36-50] v127 t6000 | p78 [52-69] v82-98 t28800 | d102 end7680/7680 | .55/.60 | 三轨满 |
| bossa (480) | 7/8/6 | b54 [36-48] t6780 | p81 [52-69] v119-127 | d156 end7680 | .55/.50 | 三轨满 |
| bossaA (480) | 3/5/5 | b64 [36-50] t7680 | p203 [48-60] v82-98 | d428 end7680 | .50/.50 | 三连音网格 |
| bossaB (480) | 3/4/9 | b64 [36-50] t7680 | p82 [48-60] v82-98 | d511 end7680 | .50/.50 | 三连音网格 |
| **waltz (360)** | 4/3/2 | b22 [36-50] **t5760** | p111 [50-69] v119-127 t21480 | d56 **end5760/5760** | .67/.67 | **3/4 精确填满** |
| **waltz-chopin (360)** | 1/**0**/1 | b32 [36-50] t1920（稀疏） | p108 [48-60] v83-98 t12960 | **d0（无鼓）** | .50/.50 | **原版无鼓** |
| **waltz-parisienne (360)** | 4/3/6 | b16 [36-48] v90 t5760 | p87 [52-69] v67-97 | d59 **end5760/5760** | .55/.55 | **3/4 精确填满** |
| african (480) | 7/13/4 | b87 [36-55] t6420 | p225 [50-60] v119-127 | d820 end7680 | .50/.50 | 三连音，到 G3 |
| african-slow (480) | **0**/1/**0** | **无** | **无** | d112 end7680（仅 Ride） | .50/.50 | **原版仅鼓** |
| african3 (480) | 3/7/5 | b48 [36-50] t3440 | p202 [48-60] v119-127 t24965 | d842 end7680 | .50/.50 | 三连音 |

- **守恒**：全部 `emptyBar0 / over0`（鼓逐小节无空小节、无音越过小节界）；全局无音符 onset 越界（OOR=0）。
- **3/4 验证**：waltz / parisienne 在 spm=360 下贝斯 t5760、鼓 end5760 = 16×360，**正好填满、零越界**。
- **音域**：所有贝斯音高 ∈ [36,55]，全部落在 G1(31)–G3(55) 内（P3-c 覆盖生效）。
- **力度**：钢琴/贝斯/鼓 velocity 全部 1…127（最大 127，无 P3-c 前的 135 越界）。
- `scalars{voicing-name}`：waltz/african 文件头引用 `default.fv`，引擎用内置 FullVoicing（即 default.fv 的移植）、忽略此声明，等价，不处理。

### 3.2 4/4 对照（Waltz 误配 4/4 曲）
- waltz@480：鼓 d75 end7680、贝斯 t7680——引擎按 4/4 **循环 tile 也填满了**（不是留白静音），但 3 拍 pattern 在 4 拍里循环重复，**律动会错位**（数值不报错，靠听感辨）。
- 结论（修正早先口头说法）：Waltz 在 4/4 曲**不会空白**，而是"3 拍律动被循环塞进 4 拍"，所以**应配 3/4 曲**；本方案不做自动改拍号。

### 3.3 两个缺轨源文件（忠实原版，先全装、试听后定）
- `waltz-chopin.sty`：无 `drum-pattern`、仅 1 条 bass + 1 条 chord（钢琴主导肖邦风）。
- `african-slow.sty`：仅 1 条 `drum-pattern`（Ride 三连音），无 bass/chord。
- 两者探针均判 **CLEAN**（源文件本就如此，不是引擎漏渲染）。真机若不可接受，走 P3-b.1 同款下架流程（资源 `mv` 入备份、注册表/枚举/菜单三处同步移除），**不在本次擅自删**。

### 3.4 裸 `X` 贝斯符号核实（虚惊，现有行为已正确）
- bossaA/bossaB 贝斯句含裸 `X8`（如 `(rules R8 X8)`）。`StyleBassRenderer.parseEvents` 的裸 token switch（`StyleBassRenderer.swift:155-164`）**没有 `case "X"`**，裸 X 落到 `default: op = .root`（根音）。
- Java `BassPattern.java:676-682`：
  ```java
  case PITCH: // Allow X for bass too, as a convenience in cutting and pasting in editor
  case BASS:  { melodySymbol = new NoteSymbol(chord.getBass()); break; }
  ```
  即**裸 X（PITCH）与 B（BASS）完全等价，都取和弦根音**。故 Swift 走 default→root 的取音结果与 Java **一致**，时值（rest="8"）也正常，无数值偏差。
- 括号形式 `(X degree dur)`（如 `(X 5 2/3+16/3)`，音阶度数音）在 `StyleBassRenderer.swift:135-140` 已正确实现为 `.degree`，二者不同、均正确。
- 初次探针的 `BASSCODE?[X]` 告警是**静态白名单漏了裸 X 的误报**，白名单补上后 10 CLEAN。
- **H6（建议带，零行为变化）**：在 switch 显式加 `case "B", "X"`，让语义自文档化、避免日后改 default 误伤；不改变任何输出。

---

## 4. 改动总览

| 项 | 文件 | 性质 |
|---|---|---|
| H0 | 拷 10 个 `.sty` → `Real imPro/Resources/Styles/`（43→53） | 新增资源 |
| H1 | `Real imPro/MidiPlayer/StyleEngine/StyleEngine.swift` | 注册表加 10 名 + 注释计数 |
| H2 | `Real imPro/Views/BandMixerView.swift` | 枚举加 10 case |
| H3 | 同 H2 | displayName：手写 4 项改 Simple + 新增 10 项 |
| H4 | 同 H2 | 分组数据：`preservedStyles` 封存，新增 `preservedSections` 4 组 |
| H5 | 同 H2 | Style 菜单 body：4 个平铺项 → 4 个二级嵌套子菜单 |
| H6（建议） | `Real imPro/MidiPlayer/StyleEngine/StyleBassRenderer.swift` | 显式 `case "B", "X"`（零行为变化） |

**不改**：`AccompanimentGenerator.swift`、`JazzMidiPlayer.swift`、`ContentView.swift`、`AccompanimentMix.swift`、任何 solo/算法/整流文件、`project.pbxproj`（同步根自动收录 .sty；若 .app 内计数不足，立即停工单独报批，不夹带改 pbxproj）。

---

## 5. 备份计划与 SHA1 基线（落地第一步，整文件备份）

新建备份目录 `.backup/P3d-20261011/`，备份 3 个待改代码文件（H6 通过则含 StyleBassRenderer）：

| 文件 | 落地前 SHA1（须与备份一致） |
|---|---|
| `Real imPro/MidiPlayer/StyleEngine/StyleEngine.swift` | `63abdedfd19198c940805546a5d762dfa2c035af` |
| `Real imPro/Views/BandMixerView.swift` | `890397d6424dd3135c6b08e14db579c4e810e1e1` |
| `Real imPro/MidiPlayer/StyleEngine/StyleBassRenderer.swift` | `a3a663f88091428fddc53cb426fe7bbc545d0578`（仅 H6 时备份） |

10 个 .sty 为**新增**，Java 原件在 `/Users/onlyonear/Desktop/Impro-Visor-master/styles/`（不动），回退 = 删除 App 副本，无需备份原件。

---

## 6. 逐 hunk 精确 diff（行号以当前现读为准；旧码中文原位封存）

### H0 ｜ 拷资源（43→53）
```bash
STY="/Users/onlyonear/Desktop/Impro-Visor-master/styles"
DST="/Users/onlyonear/Desktop/Improlyze/Real imPro/Resources/Styles"
for f in ballad bossa bossaA bossaB waltz waltz-chopin waltz-parisienne african african-slow african3; do
  cp "$STY/$f.sty" "$DST/$f.sty"
done
ls -1 "$DST"/*.sty | wc -l   # 必须 = 53
```
> .sty 属资源，增删后必须 **⇧⌘K Clean Build Folder 全量重建**（P3-b.1 教训：增量 build 不清删除的 .sty）。

### H1 ｜ StyleEngine 注册 10 名
**文件**：`StyleEngine.swift`
**旧码（:73 注释 + :96-98 数组尾）**：
```
    // [P3-b] 已移植的 46 个 Java .sty 资源名（不含扩展名），与 Bundle 内 Resources/Styles/*.sty 一一对应。
```
```
        // Funk 2 / Blues 3 / Two-beat / Tango
        "funk", "funk-disco", "pop-blues", "senor-blues", "blues-clair", "two-beat", "tango"
    ]
```
**新码**：
```
    // [P3-d] 已移植的 Java .sty 资源名（不含扩展名）：P3-b 46 → P3-b.1 下架 3（=43）→ P3-d 增 10（=53），
    // 与 Bundle 内 Resources/Styles/*.sty 一一对应。
```
```
        // Funk 2 / Blues 3 / Two-beat / Tango
        "funk", "funk-disco", "pop-blues", "senor-blues", "blues-clair", "two-beat", "tango",
        // [P3-d] Ballad 1 / Bossa 3 / Waltz 3（均 3/4，需配 3/4 曲）/ African 3（4/4 三连音网格）
        "ballad",
        "bossa", "bossaA", "bossaB",
        "waltz", "waltz-chopin", "waltz-parisienne",
        "african", "african-slow", "african3"
    ]
```

### H2 ｜ BandMixerView 枚举加 10 case
**文件**：`BandMixerView.swift`，锚点 `:76  case styTango = "sty:tango"`（其后为空行 + displayName 注释）。
**在 :76 之后插入**（rawValue 必须严格 = `"sty:"+资源名`）：
```
    // [P3-d] Ballad 1 / Bossa 3 / Waltz 3（均 3/4）/ African 3（4/4 三连音）
    case styBallad           = "sty:ballad"
    case styBossa            = "sty:bossa"
    case styBossaA           = "sty:bossaA"
    case styBossaB           = "sty:bossaB"
    case styWaltz            = "sty:waltz"
    case styWaltzChopin      = "sty:waltz-chopin"
    case styWaltzParisienne  = "sty:waltz-parisienne"
    case styAfrican          = "sty:african"
    case styAfricanSlow      = "sty:african-slow"
    case styAfrican3         = "sty:african3"
```

### H3 ｜ displayName（手写 4 项改 Simple + 新增 10 项）
**旧码（:85-88）**：
```
        case .ballad: return "Ballad"
        case .afro:   return "Afro"
        case .bossa:  return "Bossa"
        case .waltz:  return "Waltz"
```
**新码（switch case 不可同 case 双 return，旧值以本文件备份 + 本文档存档；行上注释标注改名）**：
```
        // [P3-d] 手写四项加 Simple 前缀（原 "Ballad"/"Afro"/"Bossa"/"Waltz" 旧名见 .backup/P3d 备份）：
        case .ballad: return "Simple Ballad"
        case .afro:   return "Simple Afro"
        case .bossa:  return "Simple Bossa"
        case .waltz:  return "Simple Waltz"
```
**在 :140 `case .styTango: return "Tango"` 之后、:141 结束花括号之前插入**：
```
        // [P3-d] Ballad / Bossa / Waltz / Afro 子菜单
        case .styBallad:           return "Ballad"
        case .styBossa:            return "Bossa"
        case .styBossaA:           return "Bossa A"
        case .styBossaB:           return "Bossa B"
        case .styWaltz:            return "Waltz"
        case .styWaltzChopin:      return "Chopin Waltz"
        case .styWaltzParisienne:  return "Parisienne Waltz"
        case .styAfrican:          return "African"
        case .styAfricanSlow:      return "African Slow"
        case .styAfrican3:         return "African Triplet"
```
> displayName switch 对枚举强制穷尽：H2 加了 10 case，此处必须同步补 10 个，否则编译报错。

### H4 ｜ 分组数据：平铺数组封存，新增 4 个二级子菜单
**旧码（:183-186）**：
```
    /// 顶层单项。
    static let standaloneStyles: [MixerDisplayMode] = [.styTwoBeat, .styTango]
    /// 保留的手写风格（本期不动），置于菜单末尾。
    static let preservedStyles: [MixerDisplayMode] = [.ballad, .bossa, .waltz, .afro]
```
**新码**：
```
    /// 顶层单项。
    static let standaloneStyles: [MixerDisplayMode] = [.styTwoBeat, .styTango]
    // [旧码封存 P3-d 20261011] Ballad/Bossa/Waltz/Afro 由顶层平铺单项改为二级嵌套子菜单（见 preservedSections）：
    // /// 保留的手写风格（P3-d 前置于菜单末尾平铺）。
    // static let preservedStyles: [MixerDisplayMode] = [.ballad, .bossa, .waltz, .afro]
    // [P3-d] 四个保留手写风格的二级子菜单（手写 Simple 项置顶，其后为 Java .sty 原版）。
    static let preservedSections: [StyleMenuSection] = [
        StyleMenuSection(id: "ballad", title: "Ballad", items: [
            .ballad, .styBallad
        ]),
        StyleMenuSection(id: "bossa", title: "Bossa", items: [
            .bossa, .styBossa, .styBossaA, .styBossaB
        ]),
        StyleMenuSection(id: "waltz", title: "Waltz", items: [
            .waltz, .styWaltz, .styWaltzChopin, .styWaltzParisienne
        ]),
        StyleMenuSection(id: "afro", title: "Afro", items: [
            .afro, .styAfrican, .styAfricanSlow, .styAfrican3
        ])
    ]
```

### H5 ｜ Style 菜单 body：4 个平铺项 → 4 个二级嵌套子菜单
**文件**：`BandMixerView.swift`，菜单体在 `:354 Menu { ... }`。
**旧码（:368-371，第二个 Divider 之后）**：
```
                            Divider()
                            ForEach(MixerDisplayMode.preservedStyles, id: \.self) { style in
                                styleMenuButton(style)
                            }
```
**新码**：
```
                            Divider()
                            // [旧码封存 P3-d 20261011] 原 4 个手写风格在此平铺为顶层单项：
                            // ForEach(MixerDisplayMode.preservedStyles, id: \.self) { style in
                            //     styleMenuButton(style)
                            // }
                            // [P3-d] Ballad/Bossa/Waltz/Afro 改为二级嵌套子菜单（点 Style → Ballad/Bossa/Waltz/Afro → 具体风格）：
                            ForEach(MixerDisplayMode.preservedSections) { section in
                                Menu {
                                    ForEach(section.items, id: \.self) { style in
                                        styleMenuButton(style)
                                    }
                                } label: {
                                    Text(section.title)
                                }
                            }
```
> 嵌套结构与现有 Swing 等六组（`:355-363`）完全同构。若某档真机上三级 Menu 交互异常，按 P3-b 既定兜底改用 `Section` 扁平分组（数据与接线不变），并记录。

### H6 ｜（建议，零行为变化）StyleBassRenderer 显式裸 X
**文件**：`StyleBassRenderer.swift:155-157`
**旧码**：
```
            switch lead {
            case "B": op = .root
            case "C": op = .chordTone
```
**新码**：
```
            switch lead {
            // [P3-d] 裸 X = Java PITCH，与 B(BASS) 等价取和弦根音（BassPattern.java:676-682）；
            //        音阶度数音的括号写法 (X degree dur) 已在 parseEvents 上方 :135-140 处理。
            case "B", "X": op = .root
            case "C": op = .chordTone
```
> 输出逐音不变（原 X 走 `default: .root`），仅让语义显式；`default: op = .root` 保留。

---

## 7. 落地步骤（书面批准后按序执行）

1. 建 `.backup/P3d-20261011/`，备份 3（H6 通过则 3）个代码文件，`shasum -a 1` 与 §5 逐一核对。
2. **H0** 拷 10 个 .sty，`ls *.sty | wc -l` = 53。
3. 依次应用 H1→H6（旧码按上文中文封存）。
4. 落 `scripts/rollback_p3d.sh`（§9），`bash -n` 语法检查。
5. Xcode GUI：**⇧⌘K Clean Build Folder → ⌘B Debug 0 error → 切 Release 再 ⌘B 0 error**。
6. **硬验证 .app 内 .sty 计数 = 53**（Debug 与 Release 产物各数一次；不足立即停工报批，不碰 pbxproj）。
7. 跑 53 CLEAN 回归探针（新增 10 项用 `/tmp/p3d`；原 43 项用 `/tmp/stybatch`，确认无回归）。
8. 数值金标准（§8.1）。
9. 6 组 iPad 尺寸截图 + 真机听感路径（§8.2/§8.3）。
10. `find -newermt` 无夹带核对，汇总数值与截图回报。

---

## 8. 回归门

### 8.1 数值金标准（solo 四链路必须零变化；本任务不改生成源，以 find 硬证据 + 下列数为准）
- Guide 音符数 **18,470**；raw grammar **30/30 OK / BAD=0**、FNV 稳定；Transform 对 Java **diff=0**、时值守恒 **0 违例**；Learning combination / greatMoments 各 **1536 / 1536**。
- 资源指纹：包内 **26 个 .tsv = 11,235,463 B**；`combination.rnn` = `GreatMoments.rnn` = **9,136,016 B**。
- 伴奏：**53 个 .sty 全部 CLEAN**（新增 10 个见 §3，原 43 不回归）。
- Xcode GUI Debug + Release **双 Build Succeeded、0 error**。

### 8.2 UI 门（6 组 iPad：mini / 11 / 13 × 横竖，mini 竖先）
- Style 菜单 → Ballad/Bossa/Waltz/Afro 子菜单 → 具体项，三级层级展开正常、不截断、不闪退；
- 右栏恒宽 110，不压五线谱 / #分析钮；长名（Parisienne Waltz、African Triplet）在 110 胶囊内缩字兜底不溢出；
- 子菜单首项为 Simple 手写版、选中打勾；切风格后胶囊显示名正确。

### 8.3 真机听感 / 用户路径
- 四个子菜单手写 Simple ↔ 各 .sty 可来回切换、响度一致（新风格自动继承 P3-c 归一，不应忽大忽小）、贝斯音域 G1–G3 不偏高。
- **重点试听并决定去留**：`African Slow`（仅鼓）、`Chopin Waltz`（无鼓）；不接受走 P3-b.1 同款下架。
- **Waltz 三风格在 3/4 曲下完全正确**；若手头无 3/4 测试曲，至少在 4/4 下确认不崩、有圆舞曲律动，并知晓 3/4 才是正确配法（本方案不自动改拍号）。
- 选曲 / 转调 / 生成 solo / Original⇄Solo 后切换风格，谱面与伴奏正确刷新、不残留上一首；无旋律谱（iReal/Stylebook）未生成时不空白。
- 改选风格不触发重新随机（下次播放/生成才生效）。

---

## 9. 一键回退脚本（落地时写入 `scripts/rollback_p3d.sh`）

```bash
#!/bin/bash
# P3-d 回退：恢复 3 个代码文件 + 删除 10 个新增 .sty，然后 Clean Build。
set -u
ROOT="/Users/onlyonear/Desktop/Improlyze"
BK="$ROOT/.backup/P3d-20261011"
DST="$ROOT/Real imPro"
NEW_STY=(ballad bossa bossaA bossaB waltz waltz-chopin waltz-parisienne african african-slow african3)

echo "== 恢复代码文件 =="
for pair in \
  "MidiPlayer/StyleEngine/StyleEngine.swift:63abdedfd19198c940805546a5d762dfa2c035af" \
  "Views/BandMixerView.swift:890397d6424dd3135c6b08e14db579c4e810e1e1" \
  "MidiPlayer/StyleEngine/StyleBassRenderer.swift:a3a663f88091428fddc53cb426fe7bbc545d0578"; do
  rel="${pair%%:*}"; want="${pair##*:}"
  cp "$BK/$(basename "$rel").bak" "$DST/$rel"
  got=$(shasum -a 1 "$DST/$rel" | awk '{print $1}')
  [ "$got" = "$want" ] && echo "OK  $rel" || { echo "SHA1 MISMATCH $rel ($got)"; exit 9; }
done
# 若 H6 最终未采纳，StyleBassRenderer 不在改动列表，回退时其 SHA1 本就不变，上面一行可忽略其 mismatch（删该行即可）。

echo "== 删除 P3-d 新增的 10 个 .sty =="
for f in "${NEW_STY[@]}"; do rm -f "$DST/Resources/Styles/$f.sty" && echo "rm $f.sty"; done
echo "剩余 .sty 数：$(ls -1 "$DST/Resources/Styles"/*.sty | wc -l)（应为 43）"
echo "请在 Xcode 手动 ⇧⌘K Clean Build Folder 后 ⌘B 验证。"
```

---

## 10. 无夹带声明与红线

- 落地窗口仅改动：**H1/H2/H3/H4/H5 所在 2 个代码文件**（StyleEngine.swift、BandMixerView.swift）+ **H6 可选 1 个**（StyleBassRenderer.swift）+ **新增 10 个 .sty 资源 + 1 个回退脚本**；其余文件一律不动，`find -newermt` 硬证据核对。
- **不翻任何默认**（默认风格仍 Simple Swing）、**不新增付费点 / 顶栏按钮**、用户可见处**无「Java」字样**、UI 文案全英文。
- 不碰 solo 四链路（Guide/Grammar/Transform/Learning）算法与整流、Roadmap 两套分析、`AccompanimentMix` 校准常量、`.tsv/.rnn` 资源、`project.pbxproj`。
- 旧码一律中文注释原位封存、不删除；每个被改代码文件落地前整文件备份含 SHA1。
- `african-slow` / `waltz-chopin` 本轮**先全装**，是否下架以真机试听为准、另行确认，不在本次擅自删。

---

### 待你确认（不阻塞，默认按括号执行）
1. H6（StyleBassRenderer 显式 `case "B","X"`，零行为变化）**建议带上**（默认带）。
2. `african3` 显示名暂定 **African Triplet**（三连音版），可改。
3. Chopin Waltz / African Slow 先全装、真机试听后再定去留（默认如此）。
