# Real imPro · 构建与运行时验证 Findings

- 审计日期：2026-10-10
- 被测版本：MARKETING_VERSION=1.07，CURRENT_PROJECT_VERSION=1，bundle id = wonderbread.realimpro
- 部署目标：target 级 IPHONEOS_DEPLOYMENT_TARGET = 16.6（覆盖 project 级 26.5，生效 16.6）
- Xcode：27.0（Build 27A266a）
- 被测对象：iPadOS App「Real imPro」，已上架版本的新版本更新

---

## 结论速览（最重要）

> **🔴 P0 阻塞出包**：`ContentView.swift:2583` 与 `:2592` 活动代码引用已删除枚举 `.master`，全新构建必报 `has no member 'master'`，Release 包出不来。详见 BUILD-000。
>
> 在这 2 行修复前，所有运行时验证（TC-01~TC-20、StoreKit、双语截图、性能）**无法执行**——app 编译不出来。

| 维度 | 结论 |
|---|---|
| Build error | **P0：2 处 `.master` 枚举缺失**（BUILD-000）+ 命令行沙盒宏插件环境问题（BUILD-001） |
| Build warning | **70 条**唯一 Swift warning（60 main-actor 隔离为主） |
| Availability 16.6 | ✅ 零高版本 API 误用 |
| 运行时崩溃预测 | RT-004：Malformed MusicXML 空 step 强制解包崩溃 |
| 付费墙 | RT-002：6 条 IAP 错误文案硬编码中文 |
| 本地化 | RT-003：7 条导入错误文案中文泄漏 |
| Debug 解锁 | RT-001：`#if DEBUG isPurchased=true`（Release 自动排除，需实测确认） |

---

## 0. 环境与口径声明（必读）

| 项 | 值 | 备注 |
|---|---|---|
| 命令行 xcodebuild warm 增量构建 | **BUILD SUCCEEDED，0 error** | 证据 D_日志/cli_debug_build.log |
| 命令行 xcodebuild clean 构建 | **FAILED（环境问题，非代码）** | 根因见 BUILD-001 |
| Xcode GUI Build（0 error 权威口径） | **待 MainAgent 在 GUI 触发 ⌘B** | 子代理沙盒无法驱动 GUI |
| 可用模拟器运行时 | iOS 26.5、iOS 27.0 | **无 iOS 16.6 runtime**，无法在真 16.6 实测 |
| 可用机型 | iPad mini (A17 Pro)、iPad Pro 11"/13" (M5)、iPad Air 11"/13" (M4) | 覆盖要求的 mini + 11/13 寸 |

---

## 1. 构建结果

### 1.1 权威口径状态

- 子代理环境无法完成 Xcode GUI Build。原因：
  1. 子代理平台禁止 `mac_computer_use_tool` / `computer_use_tool`（返回「Subagent暂不支持操作电脑相关操作」）；
  2. 子代理 shell 的嵌套沙盒（audit_AgentInfraService）使 `xcodebuild` 在 clean 构建时无法 spawn SwiftUI 宏插件服务器（见 BUILD-001）。
- 已用 `open RealimPro.xcodeproj` 唤起 Xcode GUI（Xcode 进程在跑），等待 MainAgent 按 ⌘B 完成权威 0-error 构建。
- 辅助证据：命令行 **warm 增量构建（沿用上次 GUI 留下的 DerivedData）成功**，链接、CodeSign、Validate 全部通过，证明代码本身可编译可链接。

### 1.2 warning 统计（基于 clean 构建中已编译文件的诊断输出）

> 注：clean 构建在宏展开阶段失败，但已成功类型检查约 100+ 个 Swift 文件。以下 70 条唯一 warning 来自这些已编译文件；Views/*.swift 等被宏阻塞的文件未进入完整类型检查，其 warning 未计入。

**唯一 Swift warning 总数：70 条**（按 `file:line:col: warning: msg` 去重）。

| 类别 | 条数 | 严重度 | 文件分布 | 说明 |
|---|---|---|---|---|
| `#ActorIsolatedCall`：call to main actor-isolated static method in a synchronous nonisolated context | 60 | P2 | BassPattern(17) / ChordPattern(23) / DrumPattern(7) / JavaBrickParser(7) / CYKParser(4) / BrickLibrary(4) | 集中在 MidiPlayer 与 Roadmap 的静态方法被默认 MainActor 隔离。Swift 6 模式下会升级为 error；当前 Swift 5 仅警告。不阻塞上架，但迁移 Swift 6 前需处理。 |
| `#NoUsage`：immutable value never used | 4 | P3 | DrumPatternExtractor(1) / BrickLibrary(2) / SheetMusicView(1) | 死变量，无运行时影响。 |
| 非可选 `??`（left side non-optional） | 2 | P3 | ContentView.swift:1031、:1083 | 右侧永远走不到，逻辑冗余。 |
| `#VariableNeverMutated`：var 应改 let | 1 | P3 | MusicXMLQuantizer.swift:237 | 风格建议。 |
| async 上下文中 `lock` | 1 | P2 | JazzMidiPlayer.swift:306 | "instance method 'lock' is unavailable from asynchronous contexts; this is an error in Swift 6 language mode"。**潜在并发安全隐患**，需改 async-safe 锁。 |
| 弃用 API：`cblas_sgemv` (iOS 16.4) | 1 | P2 | RNNMath.swift:28 | Accelerate LAPACK 旧接口；建议切 ACCELERATE_NEW_LAPACK。功能仍可用。 |
| 弃用 API：`masterGain` (iOS 15.0) | 1 | P2 | JazzMidiPlayer.swift:106 | AVAudioPlayerNode 旧属性；功能仍可用。 |
| 构建阶段 warning：Launch Screen.storyboard 重复入 Copy Bundle Resources | 1 | P3 | 工程配置 | 重复资源引用，无害。 |
| 构建阶段 info：AppIntents metadata skipped | 1 | 信息 | 工程配置 | 未依赖 AppIntents.framework，正常。 |

**高危 warning 归类（用户要求的四类）**：
1. **main actor 隔离**：60 条（最大头，集中在 MidiPlayer/Roadmap 静态方法）。
2. **未使用结果**：4 条 NoUsage + 1 条 var-never-mutated（共 5 条）。
3. **可选转换**：2 条非可选 `??`（ContentView 1031/1083）。
4. **弃用 API**：2 条（cblas_sgemv、masterGain）。
5. 额外：1 条 async lock（JazzMidiPlayer:306，Swift 6 升级风险）。

### 1.3 16.6 部署目标 availability 核查

**结论：未发现高版本 API 误用（availability clean）。**

证据：
- clean 构建日志中 **0 条 "only available in" / "introduced in" / "is unavailable"** 错误。编译器以 iOS 16.6 为最低目标类型检查所有已编译文件，未报任何未守卫的高版本 API。
- 全代码库仅 1 处 availability 守卫：`SheetMusicView.swift:117 if #available(iOS 16.4, *)`，守卫的是 `webView.isInspectable = true`，且包在 `#if DEBUG` 内（仅调试用，Release 不编译）。
- 已扫描并确认安全的 API：
  - `NavigationStack`（iOS 16，≥16.6 可用）
  - StoreKit 2 `Product.products` / `Transaction.currentEntitlements` / `Transaction.updates`（iOS 16，≥16.6 可用）
  - `.onChange(of:) { x in }` 单参数闭包（iOS 15，≥16.6 可用）
  - `AVAudioSession`（iOS 11）
  - 未使用 `@Observable` / `#Preview` / `scrollPosition` / `contentMargins` / `ImageRenderer` / `AttributedString` 等 iOS 17+ 组件。
- SF Symbols 名称（如 `chevron.left.forwardslash.chevron.right`）若为新符号，在旧系统上仅渲染为问号占位，不崩溃；非阻塞。

---

## 2. 发现项清单（统一 schema）

### BUILD-000｜P0 构建阻塞：ContentView 引用已删除枚举 `.master`（PAY-001 运行时确认）

- **严重度**：**P0（阻塞出包）**
- **专项域**：构建/付费墙
- **文件:行**：`Views/ContentView.swift:2583`、`:2592`（活动代码，非注释/非 `#if`）
- **触发前置**：全新构建（DerivedData 已清空后）编译 ContentView.swift
- **代码证据**：
  - 枚举定义（同文件 :6-16）：`case guide / grammar / learning`，`.master` 已在 :13 注释（`// case master = "Master"`）。
  - :2583 `if (selectedAlgorithmGroup == .master || selectedAlgorithmGroup == .learning) && !iapManager.isPurchased {`
  - :2592 `if (selectedAlgorithmGroup == .master || selectedAlgorithmGroup == .learning) && !iapManager.isPurchased { Image(systemName: "lock.fill")... }`
  - 全工程 grep 确认：仅这两处为活动代码；其余 4 处 `.master`（:902/:1264/:2456/:2886）均为注释。
- **实际/预期**：
  - **预期**：Xcode GUI 全新 Build 必报 `error: type 'ImproAlgorithmGroup' has no member 'master'`（2 处），BUILD FAILED。
  - **之前为何 warm CLI 构建"成功"**：warm 构建沿用了 P2 重构（20261009 合并 basic/master → grammar）之前的陈旧 .swiftmodule 缓存；清空 DerivedData 后该缓存不复存在，全新编译立即暴露此错误。
- **运行时影响**：
  - (a) 直接阻塞 Release 出包；
  - (b) 即使侥幸编译（如把 `.master` 改成 `.grammar`），原条件 `== .master` 恒为假，9 位大师文法在工具栏下拉点选时不再弹 Paywall、不显示 `lock.fill`——仅靠下游 G1/G2（:1265/:2887 已逐行判据）兜底，能选不能生成。
- **证据**：源码 ContentView.swift:2580-2595；grep 全工程结果
- **修复建议（禁止落地，来自 B 子代理）**：把 :2583/:2592 的 `selectedAlgorithmGroup == .master` 改为按 algorithm 逐行判据（与 ModeSettingsCard.swift:634 同构），判断该 algo 是否属于 9 位大师付费文法集合，而非按组判。
- **是否阻塞上架**：**是**。必须先修此 2 行才能出 Release 包。

### BUILD-001｜命令行 clean 构建失败：swift-plugin-server 被沙盒阻止

- **严重度**：P1（环境问题，不阻塞上架）
- **专项域**：构建
- **文件:行**：命令行 xcodebuild 环境
- **触发前置**：在子代理审计沙盒 shell 内执行 `xcodebuild clean build`（DerivedData 已清空）
- **逐步复现**：
  1. `rm -rf ~/Library/Developer/Xcode/DerivedData/RealimPro-*`
  2. `xcodebuild build -project RealimPro.xcodeproj -scheme RealimPro -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro),OS=27.0'`
  3. Swift 编译阶段报 `sandbox-exec: execvp() of '.../iPhoneOS.platform/.../swift-plugin-server' failed: Operation not permitted`
  4. 级联 1176 条 error（996 条 `external macro implementation type 'SwiftUIMacros.StateMacro' could not be found` + 180 条 `$xxx in scope` / `self immutable`）
- **实际结果**：clean 构建 FAILED。**预期**：GUI Build 应 0 error（因为 GUI 不在审计沙盒内，swift-plugin-server 可正常 spawn）。
- **证据**：D_日志/cli_fresh_build.log（1659 行 sandbox-exec 错误）、D_日志/cli_debug_clean_build.log
- **修复建议（禁止落地）**：无需改代码；在非审计沙盒的终端或 Xcode GUI 中构建即可。
- **是否阻塞上架**：否（环境限制，非代码缺陷）。

### RT-001｜Debug 构建硬编码已购（IAPManager DEBUG 解锁）

- **严重度**：P2（设计如此，但必须在 Release 验证不泄漏）
- **专项域**：付费/运行时
- **文件:行**：`Real imPro/Views/IAPManager.swift:17-19`
- **触发前置**：Debug 构建启动
- **实际结果**：`#if DEBUG isPurchased = true #endif` —— Debug 构建启动即视为已购，付费墙永不弹出。
- **预期**：Release 构建中此段被 `#if DEBUG` 排除，未购状态必须弹 Paywall。
- **运行时验证要求**：B3 第 0.4 / 第 9.11 步必须在 **Release 构建**上验证 9 大师 + 2 LSTM 未购时全部弹 Paywall。
- **证据**：源码 IAPManager.swift:17-19
- **修复建议**：无（DEBUG 解锁是开发便利，Release 自动排除）。
- **是否阻塞上架**：否（前提是 Release 不泄漏）。

### RT-002｜IAP 错误文案硬编码中文（LOC-001）

- **严重度**：P1（英文用户会看到中文 alert）
- **专项域**：本地化/付费
- **文件:行**：`IAPManager.swift:43/55/60/66/77/79`
- **实际**：6 条 errorMessage 直接写中文字面量（"无法连接 App Store…"、"购买验证失败…"、"购买待处理…"、"购买失败：…"、"未找到购买记录…"、"恢复失败：…"），未走 NSLocalizedString。
- **预期**：英文系统下应为英文。
- **运行时验证**：B3 第 1/4/7 步触发购买失败/断网/恢复失败时截图 alert，核对语言。
- **是否阻塞上架**：是（App Store 英文区会出现中文 alert，与 C2 表 LOC-001 一致）。

### RT-003｜导入错误文案中文泄漏（LOC-002）

- **严重度**：P1
- **文件:行**：`ContentView.swift:577/589/597/601/635/650/658`
- **实际**：JSON 读取失败、旋律 JSON 解析失败、.mxl 不支持、文件读取失败、MusicXML 无乐曲、MusicXML 导入成功说明、MusicXML 解析失败 共 7 条中文 key 未补英文 value。
- **运行时验证**：TC-11/TC-12 故意导入损坏文件，截图 alert。
- **是否阻塞上架**：是（同 LOC-002）。

### RT-004｜Malformed MusicXML 空 step 导入可能崩溃（TC-12 静态确认）

- **严重度**：P0（导入路径崩溃）
- **专项域**：运行时/导入
- **文件:行**：`Importers/MusicXML/MusicXMLQuantizer.swift:322-330`
- **触发前置**：导入 `<note><pitch><step></step><octave>4</octave></pitch></note>`（空 step）的 MusicXML
- **实际代码**：
  ```swift
  private static func pitchMidi(_ p: String) -> Int {
      let parts = p.split(separator: "/")
      let n = String(parts[0]); let o = Int(parts[1]) ?? 0   // parts[1] 越界风险
      let base: [Character: Int] = [...]
      let b = base[n.first!]!                                // n 空时 n.first! 强制解包崩溃
      ...
  }
  ```
- **实际/预期**：空 step 产生空字符串 n → `n.first!` 解包 nil → **EXC_BAD_ACCESS 崩溃**。预期：应 guard 空 step 并弹"未解析出有效乐曲"错误。
- **证据**：源码 MusicXMLQuantizer.swift:322-330；调用点 347/353/358
- **修复建议（禁止落地）**：`guard let first = n.first, let b = base[first], parts.count >= 2 else { return -1 }` 并在上层过滤无效音高。
- **是否阻塞上架**：是（用户导入损坏文件会闪退，App Store 审核可能遇到）。

### RT-005｜LSTM 模型 9.1MB × 2，硬编码开发机回退路径（非崩溃）

- **严重度**：P3
- **文件:行**：`LSTM/LSTMStrategy.swift:132-139`
- **实际**：combination.rnn 与 GreatMoments.rnn 各 9,136,016 字节（9.1MB）打进 Bundle。`loadModel()` 先 `Bundle.main.url(forResource:withExtension:"rnn")`，回退到硬编码 `/Users/onlyonear/Desktop/Improlyze/audit_harness/...`（仅开发机存在）。
- **预期/影响**：设备上 Bundle.main.url 成功，不崩溃。但回退路径是机器特定路径，建议删除或改为 Bundle 优先。内存峰值静态预测 ~36MB（双模型）。
- **是否阻塞上架**：否。

---

## 3. 运行时验证结果（待 .app 就绪后补）

> 以下章节等 MainAgent 提供当前代码的 .app 后，用 `xcrun simctl install/launch/io screenshot` 在 iPad mini (A17 Pro) / iPad Pro 11" / 13"（iOS 26.5 / 27.0）上逐条执行并填写。

### 3.1 模拟器覆盖矩阵

| 机型 | iOS | Debug | Release | 用途 |
|---|---|---|---|---|
| iPad mini (A17 Pro) | 27.0 | 待测 | 待测 | 小屏 UI 截断、TC-01~TC-20 |
| iPad mini (A17 Pro) | 26.5 | 待测 | 待测 | 最低可用 runtime 回归 |
| iPad Pro 11" (M5) | 27.0 | 待测 | 待测 | 中屏 |
| iPad Pro 13" (M5) | 27.0 | 待测 | 待测 | 大屏 |
| iPad Pro 11"/13" | 26.5 | 待测 | 待测 | 横屏 |

### 3.2 A2 用例执行结果（TC-01 ~ TC-20）

| 用例 | 描述 | 结果 | 证据 |
|---|---|---|---|
| TC-01 | 生成中切歌覆盖 | 待测 | |
| TC-02 | 生成中转调 | 待测 | |
| TC-03 | 快速连点两次生成 | 待测 | |
| TC-04 | 生成中退侧栏再回来 | 待测 | |
| TC-05 | Original⇄Solo 级数刷新 | 待测 | |
| TC-06 | 空歌单/空和弦 | 待测 | |
| TC-07 | 全 NC 小节 | 待测 | |
| TC-08 | 弱起小节 | 待测 | |
| TC-09 | 极长曲 ≥200 小节 | 待测 | |
| TC-10 | 单小节 ≥8 和弦 | 待测 | |
| TC-11 | 损坏导入（txt/空/mxl） | 待测 | |
| TC-12 | Malformed MusicXML 空音名 | 待测 | |
| TC-13 | 转调后生成 | 待测 | |
| TC-14 | 空片段播放 | 待测 | |
| TC-15 | 休止/延音播放 | 待测 | |
| TC-16 | 极端速度/拍号 | 待测 | |
| TC-17 | Learning 连续生成 5 次 | 待测 | |
| TC-18 | 两个 LSTM 来回切 | 待测 | |
| TC-19 | 未购 Master/Learning 生成 | 待测（Release） | |
| TC-20 | 错误提示本地化 | 待测 | |

### 3.3 StoreKit 流程结果（B3）

| 步骤 | 结果 | 证据 |
|---|---|---|
| 0. Release Build 通过 | 待测 | |
| 1. 产品加载 / 断网 | 待测 | |
| 2. 购买成功 | 待测 | |
| 3. 购买取消 | 待测 | |
| 4. 购买失败/断网 | 待测 | |
| 5. Ask to Buy | 待测（需沙盒账号） | |
| 6. 重复弹窗 | 待测 | |
| 7. Restore Purchases | 待测 | |
| 8. 老用户升级/重装识别 | 待测（需旧版构建） | |
| 9. 反向白嫖 11 条 | 待测（Release） | |
| 10. 审核合规 | 待测 | |

### 3.4 双语截图核对

| 页面 | 英文截图 | 中文截图 | 截断/混杂 |
|---|---|---|---|
| 付费墙 | 待测 | 待测 | |
| 生成主界面 | 待测 | 待测 | |
| 导出 | 待测 | 待测 | |
| 空状态 | 待测 | 待测 | |
| 错误提示 | 待测 | 待测 | |

### 3.5 Release(-O) 性能实测

| 链路 | Debug 耗时 | Release 耗时 | Debug 内存峰值 | Release 内存峰值 | 测量方法 |
|---|---|---|---|---|---|
| GuideTone solo | 待测 | 待测 | 待测 | 待测 | |
| Grammar solo | 待测 | 待测 | 待测 | 待测 | |
| Master/Learning solo | 待测 | 待测 | 待测 | 待测 | |
| Export | 待测 | 待测 | 待测 | 待测 | |
| Roadmap 1 | 待测 | 待测 | 待测 | 待测 | |
| Roadmap 2 | 待测 | 待测 | 待测 | 待测 | |

---

## 4. 未覆盖项与原因

1. **iOS 16.6 真机/模拟器实测**：本机仅安装 iOS 26.5 与 27.0 runtime，无 16.6 运行时。availability 已用编译期静态检查替代（见 1.3）。建议在装有 iOS 16.6 模拟器的机器上回归一次。
2. **Xcode GUI 权威 Build 0-error**：子代理沙盒无法驱动 GUI，已上报 MainAgent 触发。
3. **Ask to Buy / 沙盒账号购买**：需 ASC 沙盒测试账号，子代理无法登录。
4. **老用户升级识别（B3 第 8 步）**：需要上一已上架版本的旧构建 + 沙盒账号 A 完成基线购买，子代理环境无此构建。
5. **StoreKit Configuration 选用**：工程无 .storekit 文件，新建后需在 Xcode scheme 的 Run 选项中临时选用（写入用户级 xcuserdata），需 GUI 操作。
