# Real imPro（iPadOS）发布前 · 付费墙安全 / 威胁建模审计 — 发现清单

- 审计对象：`/Users/onlyonear/Desktop/Improlyze/Real imPro/`（生产代码，只读）
- 审计日期：2026-10-10
- 付费口径：非订阅 / 非消耗型，一次购买终身解锁；Guide 免费；Grammar 的 9 位大师文法与 Learning（2 个 LSTM）同档付费。
- 审计方式：静态威胁建模为主（逐行实读 + grep 全量定位）。StoreKit 实操由运行时子代理按 `B3_付费运行时验证步骤.md` 执行。
- 纪律：未修改/移动/删除任何生产文件；未改开关默认值或付费归属；本报告内所有「修复代码」均为示意，未落地。

---

## 0. 结论速览

- **不能白嫖（生成层面）**：两道「生成拦截」(`ContentView.swift:1265` 与 `:2887`) 统一使用 `currentSelectionRequiresPurchase && !iapManager.isPurchased`，覆盖 9 位大师文法 + 2 个 LSTM；未购点生成会被拦下并弹 `PaywallView`。
- **entitlement 做法正确**：完全来自 `Transaction.currentEntitlements`（StoreKit 2，仅 `.verified` 命中 productID），**无任何 UserDefaults/@AppStorage 本地已购布尔**，无法靠改偏好、断网、改系统时间、重装白嫖。
- **Release 不泄漏 DEBUG 解锁**：`IAPManager.swift:17-19` 的 `#if DEBUG isPurchased = true` 在 Release 配置下被编译剔除（pbxproj Release 块未定义 `DEBUG` 宏）。
- **唯一 P0**：`ContentView.swift:2583` 与 `:2592` 仍引用已删除的枚举 case `.master`（Grammar 合并重构残留）。这既疑似导致 Release 编译失败，又使工具栏下拉的「二级选择拦截 / 锁图标」对 9 位大师文法整体失效（靠下游 G1/G2 兜底，不构成免费生成，但必须修）。
- **Restore 有入口且正确**：`PaywallView` 有 Restore Purchase，走 `AppStore.sync()` + 重校 `currentEntitlements`。
- **老用户升级（P0 项）无迁移负担**：因 entitlement 是账号侧 `Transaction.currentEntitlements`、本地零键，同 Apple ID 重装/换机/恢复自动识别；唯一前提是 product id 与上一版保持一致（需在 ASC 侧核对）。

---

## P0

### PAY-001 ｜工具栏算法下拉仍引用已删除枚举 `.master`（疑似 Release 编译失败 + 二级付费锁失效）
- 严重度：**P0**
- 专项域：付费墙
- 文件:行：`Views/ContentView.swift:2583`、`:2592`（对照：枚举定义 `:6-16`，`.master` 已在 `:13` 注释删除；统一判据 `:908-914`）
- 触发前置条件：Release（或任意）构建；展开工具栏「Grammar 组算法下拉菜单」(`:2580` Menu)。
- 逐步复现：
  1. 当前 worktree `ImproAlgorithmGroup` 仅含 `.guide / .grammar / .learning`（`:8-10`），`.master` 已注释（`:13`）。
  2. `:909` 的 `switch selectedAlgorithmGroup` 无 `default`、仅列三个新 case——能编译，反证 `.master` 已不存在。
  3. 但 `:2583`（下拉点选回调）与 `:2592`（锁图标）是**非 `#if` 包裹的活动代码**，仍写 `if (selectedAlgorithmGroup == .master || selectedAlgorithmGroup == .learning) && !iapManager.isPurchased { … }`。
- 实际/预期结果：
  - (a) 静态推断：`ImproAlgorithmGroup` 无成员 `.master`，Swift 应报 `has no member 'master'`，**当前 worktree 无法编译，阻塞 Release 出包**（与 `:909` 的穷举 switch 互斥，二者不可能同时成立）。
  - (b) 即使侥幸可编译：条件在新模型下 `selectedAlgorithmGroup` 只可能是 `.grammar`（9 位大师文法现并入此组），`== .master` 恒为假 → 整条件退化为仅拦 `.learning`。**Grammar 下拉里点选 9 位大师文法不再触发 pending/Paywall、也不显示 `lock.fill`**；仅靠下游 G1/G2 生成门兜底（能选不能生成）。
- 证据（静态推理）：git status 该文件为 `AM`（已暂存 + 工作区又改）；`git diff` 显示本次重构删掉了 `case master = "Master"` 与 `.master` 的 `.background/.foreground` 旧引用，但新增的工具栏 Menu 块仍带 `.master` 判断——典型重构漏改。运行时/build 确认步骤见 B3「构建验证」。
- 修复建议（示意，**勿落地**）：把工具栏下拉条件改为与 `ModeSettingsCard.swift:634` 同构的逐行判据：
  ```swift
  Button {
      let isPaidRow = (selectedAlgorithmGroup == .learning)
                   || (selectedAlgorithmGroup == .grammar && algo.isPaidGrammar)
      if isPaidRow && !iapManager.isPurchased {
          pendingMasterAlgorithm = algo
          showPaywall = true
      } else { selectedAlgorithm = algo }
  } label: {
      HStack {
          Text(algo.rawValue)
          if ((selectedAlgorithmGroup == .learning)
              || (selectedAlgorithmGroup == .grammar && algo.isPaidGrammar))
             && !iapManager.isPurchased {
              Image(systemName: "lock.fill").font(.caption2)
          }
          // checkmark 保持
      }
  }
  ```
- 是否阻塞上架：**是（先出包/后审核）**。须先确认能否编译；若能编译，则二级锁与 G1/G2 口径不一致，须统一。

---

## P1

### PAY-002 ｜付费流程错误文案为硬编码中文，界面却是英文（交叉-本地化）
- 严重度：**P1**
- 专项域：付费墙 × 本地化
- 文件:行：`Views/IAPManager.swift:43`（"无法连接 App Store…"）、`:55`（"购买验证失败，请重试"）、`:60`（"购买待处理…"）、`:66`（"购买失败：…"）、`:77`（"未找到购买记录…"）、`:79`（"恢复失败：…"）
- 触发前置条件：非中文 locale 用户在 `PaywallView` 遇到断网/失败/恢复无果。
- 实际/预期：`PaywallView` 全英文（"Unlock Master Algorithms" / "Restore Purchase"），但 `.alert` 弹出的 `errorMessage` 是中文硬编码 → 英文用户看到中文错误弹窗。功能不崩，但体验/合规不专业。
- 证据（静态推理）：`IAPManager.swift` 全文 `errorMessage = "…"` 直写中文字面量；`PaywallView.swift:79` 直接 `Text(iapManager.errorMessage ?? "")`。标注「交叉-本地化」，本地化子代理应同步记录。
- 修复建议（示意）：错误文案走 `NSLocalizedString` / String Catalog，与 App 其余英文文案同一本地化表。
- 是否阻塞上架：建议上架前修（不强制，易被审核/用户差评）。

### PAY-003 ｜付费墙缺少「价格说明 / 条款 / 隐私政策」入口与功能说明单薄
- 严重度：**P1**
- 专项域：付费墙 × 审核合规
- 文件:行：`Views/PaywallView.swift:16-19`（仅两条 FeatureRow）、`:52-63`（Restore）
- 实际/预期：`PaywallView` 有动态价格 `product.displayPrice`(:34) 与 Restore 入口，但**未展示 Terms of Use（EULA）/ Privacy Policy 链接**，功能说明仅两行。含 IAP 的 App 审核要求可访问隐私政策；付费墙通常需明示订阅/一次性规则（此处是一次性终身，描述正确）。
- 证据（静态推理）：`PaywallView.swift` 无任何 `Link`/外链到隐私或条款；`LicensesView.swift:14,22` 的外链是开源致谢（GitHub / hmc.edu），不是隐私政策。
- 修复建议（示意）：在 PaywallView 底部加 Privacy Policy / Terms（EULA）链接；确认 App 内（设置）已有隐私政策页。
- 是否阻塞上架：视 App 是否已有隐私政策页而定——若设置里已有，降 P2；若全 App 无隐私政策页，则审核必拒（P0 合规）。需运行时/设置页确认。

---

## P2

### PAY-004 ｜退款/撤销（revocation）未把 isPurchased 复位为 false
- 严重度：**P2**
- 文件:行：`Views/IAPManager.swift:83-96`（`listenForTransactions`）
- 实际/预期：`.verified` 命中 productID 时只 `isPurchased = true; finish()`，未判断 `txn.revocationDate`。若会话进行中被退款/撤销，本会话仍解锁，**下次启动** `checkCurrentEntitlements`（`:33-39`，自动排除已撤销）才会回落到未购。
- 证据（静态推理）：`Transaction.updates` 在撤销时会投递该交易；当前分支无条件 `= true`。非消耗型退款罕见，实际影响低。
- 修复建议（示意）：
  ```swift
  case .verified(let txn):
      guard txn.productID == Self.productID else { break }
      if txn.revocationDate != nil || txn.expirationDate ?? .distantPast < Date() {
          isPurchased = false
      } else { isPurchased = true }
      await txn.finish()
  ```
- 是否阻塞上架：否。

### PAY-005 ｜切组进 Learning 组直接选中付费 LSTM（.combination），无二级拦截
- 严重度：**P2**
- 文件:行：`Views/ContentView.swift:2504-2507`
- 实际/预期：未购用户切到 Learning 组时，`selectedAlgorithm` 被恢复/默认成 `.combination`（付费 LSTM），切组动作本身不弹付费墙。下游 G1/G2（`:1265`/`:2887`）在点「生成」时仍正确拦截，故不构成免费生成；仅是防御纵深与「进入即静默选中付费模型」的体验不一致。
- 证据（静态推理）：`:2495-2510` 切组 switch 无 `isPurchased` 判断；生成门 `currentSelectionRequiresPurchase` 对 `.learning` 恒 `true`。
- 修复建议（可选）：切到 Learning 未购时不预置付费模型，或与 LearningSettingsCard 一致在生成门兜底即可（现状已兜底）。
- 是否阻塞上架：否。

### PAY-006 ｜PaywallView 死代码 onChange(of: errorMessage) 空闭包
- 严重度：**P2**
- 文件:行：`Views/PaywallView.swift:70-72`
- 实际/预期：`.onChange(of: iapManager.errorMessage) { msg in if … { } }` 空体，无效果。不影响功能。
- 修复建议（可选）：删除空闭包。
- 是否阻塞上架：否。

---

## 已核实为「正确 / 无问题」（不计入缺陷）

| 项 | 结论 | 证据 |
|---|---|---|
| StoreKit 版本 | StoreKit 2（`Product.products` / `Transaction.currentEntitlements` / `Transaction.updates` / `AppStore.sync` / `txn.finish`） | `IAPManager.swift:30,34,48,74,84` |
| 产品类型 | 代码侧按「非消耗型终身」处理（无消耗/无续期逻辑，finish 一次即止）；**ASC 侧须配为 Non-Consumable** | `IAPManager.swift` 全文 |
| product id | `com.realimpro.master.lifetime`（bundle id `wonderbread.realimpro`，前缀不同属允许，勿与 bundle id 强绑） | `IAPManager.swift:7`；pbxproj `PRODUCT_BUNDLE_IDENTIFIER = wonderbread.realimpro` |
| entitlement 来源 | 仅 `Transaction.currentEntitlements` 的 `.verified`；**无本地已购布尔** | `IAPManager.swift:33-39`；全仓 grep 无 `@AppStorage("…purchase/pro/unlock…")` |
| DEBUG 解锁是否泄漏 Release | 否。Release build 配置未定义 `DEBUG` 宏/编译条件 | pbxproj Release 块（`:213-268`）无 `GCC_PREPROCESSOR_DEFINITIONS`/`SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG`；Debug 块才有 |
| 购买成功发货 | `.success(.verified)` → `isPurchased=true; txn.finish()`，发货+收尾正确 | `IAPManager.swift:52-53` |
| unverified 处理 | 不 finish、不解锁，置错误返回 | `IAPManager.swift:54-55`；监听侧 `:90-94` 仅 DEBUG 日志、不 finish |
| 用户取消 | `.userCancelled` 静默返回，不报错 | `IAPManager.swift:57-58` |
| pending / ask-to-buy | 置「待处理」文案返回；批准后由常驻 `Transaction.updates` 投递并 finish | `IAPManager.swift:59-61,83-96` |
| 交易监听持久 | init 内启动常驻 Task（`loadProduct → checkCurrentEntitlements → listenForTransactions`），单例 `IAPManager.shared`，App 启动后持续有效 | `IAPManager.swift:21-26,83-96`；`ImprolyzeApp.swift:41` `@StateObject` |
| finish 时机 | 仅 verified 成功路径 finish，无漏发货/重复发货（finish 后不再经 updates 重投） | `IAPManager.swift:53,88` |
| Restore 入口 | `PaywallView` 有 Restore Purchase → `AppStore.sync()` + 重校 entitlement | `PaywallView.swift:52-63`；`IAPManager.swift:71-81` |
| 老用户升级/换机/重装 | entitlement 账号侧、本地零键，同 Apple ID 自动识别；**前提 product id 与上一版一致** | `IAPManager.swift:33-39` |
| URL scheme 白嫖 | `irealb://` / `irealbook://` 仅解析导入歌单（`handleURLImport`），不触碰 `selectedAlgorithm`/`isPurchased` | `ContentView.swift:710-733,2392`；Info.plist 注册两 scheme |
| 快捷操作 / 外接键盘 | 全仓无 `UIApplicationShortcutItem` / `.keyboardShortcut`，无此旁路 | grep 无命中 |
| LSTM DEBUG 开关 | `LSTMDebugSwitch` 整体 `#if DEBUG`（LSTMStrategy.swift:21-26）；Release 走 `useLSTM=false` | `ContentView.swift:1409-1413` |
| 外部支付/引导网页支付 | 无外部支付 SDK；UI 中外链仅开源致谢（GitHub/hmc.edu），无 PayPal/Stripe/支付宝等 | `LicensesView.swift:14,22` |
| RegionGate | 是 storefront 商店区控制**内置曲可见性**（版权分级），**不是付费墙**，不纳入付费口径 | `BuiltinLibrary/RegionGate.swift` |

---

## 需在 App Store Connect 侧核对清单（代码内无法验证）

1. 产品 `com.realimpro.master.lifetime` 已在 ASC 创建，且挂在 App（bundle `wonderbread.realimpro`，Team `S64L8HJ82T`）下。
2. 产品类型 = **Non-Consumable（非消耗型）**，不得误设为 Auto-Renewable / Non-Renewing Subscription / Consumable。
3. 该 product id 与**上一已上架版本使用的 product id 完全一致**（老用户识别依赖它）。
4. 状态为「准备提交 / 已 cleared for sale」，价格档位与展示名称本地化齐备。
5. App 元数据含可访问的 **Privacy Policy URL**（对应 PAY-003）。
6. 无 `.storekit` 配置文件（工程内已确认）→ 运行时本地购买测试需用沙盒账号，或临时新增 StoreKit Configuration（不入库）。
