# Real imPro 发布前【稳定性与崩溃/闪退专项】静态审计发现

- 审计日期：2026-10-10
- 审计范围：`/Users/onlyonear/Desktop/Improlyze/Real imPro/`（128 个 Swift 文件，41,552 行）
- 审计方式：只读静态代码审计（未修改任何生产文件）；行号均经实读确认
- 证据口径：除特别标注「运行时实测」外，均为「静态推理」
- 严重度统计：P0 = 0；P1 = 5；P2 = 11

---

## P1（特定操作/边界数据触发，建议本版修复）

### STA-001｜P1｜并发·状态一致性｜切歌不取消后台生成任务，旧曲 Solo 覆盖新曲谱面

- **文件:行**：
  - `Views/ContentView.swift:2304-2338`（`.onChange(of: selectedSong)` 全文）
  - `Views/ContentView.swift:1300-1313`（`generationTask = Task.detached { ... }` 及 `MainActor.run` 回调）
- **触发前置条件**：
  1. 选中一首内置/已导入曲，点「生成」开始后台 Solo 生成（LSTM/grammar 耗时 0.5–5s）；
  2. 在生成完成前，从侧栏切到另一首歌。
- **逐步复现**：
  1. 打开任意内置曲（如 `Autumn Leaves`），点生成，转圈出现（`isGenerating=true`）；
  2. 不等生成完成，立即在侧栏点另一首歌（如 `Blue Bossa`）；
  3. `onChange(selectedSong=Blue Bossa)` 在 2324 行把 `generatedSolo` 铺成 Blue Bossa 的内置原旋律；
  4. 旧任务（Autumn Leaves 的 worker）随后完成，进入 1302 行 `MainActor.run`，1303 行 `self.generatedSolo = result.measures` —— 把 Blue Bossa 的谱面覆盖成 Autumn Leaves 的 Solo。
- **实际结果/预期结果**：谱面显示错误歌曲的 Solo（和弦/音符全错），播放也播错；预期切歌后应取消旧任务、显示新曲。
- **根因**：
  - `onChange(of: selectedSong)`（2304）**没有**调用 `generationTask?.cancel()`，也没有把 `isGenerating` 置 false；
  - 1302–1312 的 `MainActor.run` 回调**没有**像 `refreshKeySections`（1066 行 `guard self.keySectionsToken == token else { return }`）那样做 token 守卫。
- **证据**：静态推理。对比 1061–1074 的 Key Sections 已做 token 防陈旧，generatedSolo 路径缺失同类保护。
- **修复建议（示意，禁止落地）**：
  ```swift
  // 1) 在 runJazzGenerationPipeline 入口捕获 token：
  let genToken = UUID(); generationToken = genToken
  generationTask = Task.detached(priority: .userInitiated) { [self] in
      let result = self.generateMeasuresWorker(...)
      await MainActor.run {
          guard self.generationToken == genToken else { return } // 防陈旧
          self.generatedSolo = result.measures
          ...
      }
  }
  // 2) 在 onChange(of: selectedSong) 开头补：
  generationTask?.cancel(); generationToken = UUID(); isGenerating = false
  ```
- **是否阻塞上架**：否（不崩溃，但会让用户看到错误歌曲音符，属于明显功能缺陷，建议本版修）。

---

### STA-002｜P1｜并发·取消语义｜被取消任务的完成回调仍写 generatedSolo，可能清空当前谱面

- **文件:行**：`Views/ContentView.swift:1454`（`if Task.isCancelled { break }`）、`Views/ContentView.swift:1442`（`var finalMeasures: [GeneratedMeasure] = []`）、`Views/ContentView.swift:1303`（`self.generatedSolo = result.measures`）
- **触发前置条件**：生成任务运行中，用户切走页面（`.onDisappear` 2302 行 `generationTask?.cancel()`）或转调（经 STA-005 路径触发 cancel）。
- **逐步复现**：
  1. 点生成，worker 进入 `repeat { ... }` 重试循环；
  2. 任务被 cancel；
  3. worker 在下一轮循环顶部 1454 行 `if Task.isCancelled { break }` 跳出，此时 `finalMeasures` 仍是 1442 行初始化的空数组 `[]`；
  4. worker 返回 `([], nil)`，1303 行 `self.generatedSolo = []` —— 清空谱面。
- **实际结果/预期结果**：切页/转调后谱面被清空成白谱；预期取消后不应覆盖当前显示。
- **证据**：静态推理。worker 在 cancel 时返回空 finalMeasures，回调无守卫直接赋值。
- **修复建议（示意）**：在 1303 行前加 `guard !Task.isCancelled, self.generationToken == genToken else { return }`；或在 worker 内 cancel 时返回 nil 结果，回调识别后跳过赋值。
- **是否阻塞上架**：否。

---

### STA-003｜P1｜并发·任务句柄竞态｜陈旧任务完成块把 generationTask 置 nil，抹掉新任务句柄

- **文件:行**：`Views/ContentView.swift:1311`（`self.generationTask = nil`）、`Views/ContentView.swift:2302`（`.onDisappear { generationTask?.cancel() }`）
- **触发前置条件**：快速连续点两次生成（或生成中转调触发新任务）。
- **逐步复现**：
  1. 点生成 → TaskA 赋给 `generationTask`；
  2. 再点生成 → 1297 行 `generationTask?.cancel()` 取消 TaskA，1300 行 TaskB 赋给 `generationTask`；
  3. TaskA 先完成，进入 1311 行 `self.generationTask = nil` —— 此时 `self.generationTask` 指向 TaskB，于是 TaskB 的句柄被置 nil；
  4. 用户立即切页，2302 行 `generationTask?.cancel()` 为 nil 空操作，TaskB 继续在后台跑（白白耗 CPU，且其回调仍会写 generatedSolo）。
- **实际结果/预期结果**：后台任务泄漏、切页后仍在跑；预期旧任务完成块不应触碰当前句柄。
- **证据**：静态推理。1311 行无条件置 nil，未判断 `generationTask === self`。
- **修复建议（示意）**：
  ```swift
  await MainActor.run {
      guard self.generationToken == genToken else { return }
      ...
      if self.generationTask != nil { self.generationTask = nil } // token 守卫后再清
  }
  ```
- **是否阻塞上架**：否。

---

### STA-004｜P1｜边界·导入崩溃｜MusicXML pitchMidi 对空音名/malformed pitch 强制解包崩溃

- **文件:行**：`Importers/MusicXML/MusicXMLQuantizer.swift:326`（`let b = base[n.first!]!`）
- **触发前置条件**：用户通过「文件」App 导入一个 malformed 的 .musicxml/.xml，其中某音符的 `<step>` 为空或 pitch 字符串形如 `/4`（音名部分为空）。
- **逐步复现**：
  1. 构造一个最小 MusicXML，包含 `<note><pitch><step></step><octave>4</octave></pitch>...</note>`（空 step）；
  2. App 内导入，走到 `repairDanglingTies`（347/353/358 行）调用 `pitchMidi(h.pitch)`；
  3. `pitchMidi` 内 `parts[0]` 为空串，`n.first!` 解包空字符串崩溃。
- **实际结果/预期结果**：App 闪退；预期应优雅拒绝该文件并提示「无法解析」。
- **证据**：静态推理。322–328 行 `pitchMidi(_ p:)` 直接 `n.first!`，无空串守卫；调用方 347/353/358 传入的 `h.pitch`/`n.pitch` 来自用户文件，不可信。
- **修复建议（示意）**：
  ```swift
  private static func pitchMidi(_ p: String) -> Int {
      let parts = p.split(separator: "/")
      guard let n = parts.first.map(String.init), let first = n.first else { return 60 } // 兜底中央C
      ...
  }
  ```
- **是否阻塞上架**：否（需用户构造异常文件才触发；但 App Store 审核机若随机导入文件可能命中，建议修）。

---

### STA-005｜P1｜并发·状态一致性｜生成中转调被 guard 静默丢弃，旧任务以旧调完成后覆盖新调谱面

- **文件:行**：`Views/ContentView.swift:1270`（`guard !isGenerating else { return }`）、`Views/ContentView.swift:2339-2345`（`.onChange(of: selectedKey)` 在 `didGenerateInCurrentGroup` 时调 `runJazzGenerationPipeline(jumpToSolo: false)`）
- **触发前置条件**：生成进行中（`isGenerating=true`），用户转动调轮盘。
- **逐步复现**：
  1. 点生成，转圈中；
  2. 转调轮盘从 C 转到 F；
  3. 2345 行调 `runJazzGenerationPipeline(jumpToSolo:false)`，但 1270 行 `guard !isGenerating` 直接 return —— 既不取消旧任务，也不起新任务；
  4. 旧任务以 C 调的 `songToUse` 完成，1303 行写入 generatedSolo；UI 此时 `selectedKey=F`，`displayedMeasures`（941）按 F 调显示，但 generatedSolo 里的音符是 C 调生成的 → 级数/音符错位。
- **实际结果/预期结果**：转调后级数不刷新、音符与调号不匹配（历史「级数不刷新」缺陷的残留变体）；预期生成中转调应排队或取消重跑。
- **证据**：静态推理。
- **修复建议（示意）**：转调时若 `isGenerating`，先 `generationTask?.cancel()` 并把目标调号记下，旧任务 cancel 后再以新调号重跑；或直接在 2345 行先 cancel 再调 pipeline（pipeline 内 1297 本就会 cancel，但 1270 的 guard 挡住了入口）。
- **是否阻塞上架**：否。

---

## P2（健壮性/性能/防御性，不阻塞上架）

### STA-006｜P2｜性能·内存｜LSTM 模型每次生成全量重载，无缓存

- **文件:行**：`LSTM/LSTMStrategy.swift:132-143`（`loadModel()`）、`LSTM/LSTMStrategy.swift:47`（`generateSolo` 每次调 `loadModel()`）
- **现象**：每次点 Learning 生成，都重新 `Data(contentsOf: url, options: [.mappedIfSafe])` 读 9.1MB `.rnn` 并解析为权重结构。两个模型（Combination/GreatMoments）各 9.1MB。
- **影响**：每次生成多付一次磁盘 mmap + 全量 Float 解析耗时（后台线程，不卡 UI）；切模型/重复生成重复 IO。
- **证据**：静态推理。`RNNFile` 未做 static 缓存。
- **修复建议（示意）**：`LSTMStrategy` 内加 `private static var cache: [String: RNNFile] = [:]`，按 modelName 缓存。
- **是否阻塞上架**：否。

### STA-007｜P2｜内存｜RNNModel mmap 后立即 Array(data) 全量拷贝，未真正利用 mmap

- **文件:行**：`LSTM/RNNModel.swift:50`（`Data(contentsOf: url, options: [.mappedIfSafe])`）、`LSTM/RNNModel.swift:62`（`self.bytes = Array(data)`）
- **现象**：声明用 `.mappedIfSafe`（mmap），但 62 行立即 `Array(data)` 把 9.1MB 整段拷贝成 `[UInt8]`，随后 109/116 行再拷成 `[Float]`。峰值内存 ≈ 9.1MB(UInt8) + ~9.1MB(Float) ≈ 18MB/模型，且 mmap 的「按需分页」优势失效。
- **影响**：单模型 18MB 常驻；两个模型并存 ~36MB。iPad 24G 内存下不构成 Jetsam 风险，但与注释「mmap」意图不符。
- **证据**：静态推理。
- **修复建议（示意）**：`RNNByteReader` 直接持有 `Data` 并用 `data.withUnsafeBytes` 读，避免 `Array(data)`；或缓存后释放 Data。
- **是否阻塞上架**：否。

### STA-008｜P2｜崩溃源·防御｜activeStrategy! 强制解包

- **文件:行**：`Views/ContentView.swift:1458`（`activeStrategy!.generateSolo(for: roadmap)`）
- **现象**：1377–1436 行 if-else 全分支都给 `activeStrategy` 赋值，grammar 分支 1417 行 `guard let ... else { return ([], nil) }` 提前返回；故 1458 行实际不可为 nil。
- **影响**：仅防御性风险，当前无输入路径命中。
- **证据**：静态推理。
- **修复建议（示意）**：改 `guard let activeStrategy else { return ([], nil) }`。
- **是否阻塞上架**：否。

### STA-009｜P2｜崩溃源·边界｜Transformation.swift 空模板/空段 first!

- **文件:行**：`TransformEngine/Transformation.swift:54-55`（`matchTemplate.first!.note.midiPitch`、`segment.first!.note.midiPitch`）
- **现象**：43 行 guard 了 `segment.count == matchTemplate.count`，但未判 `count > 0`。若规则库某条 matchTemplate 为空数组，或上层传入空 segment，54 行 `first!` 崩溃。
- **影响**：规则库为打包资源，正常非空；空 segment 需上层异常调用。理论可达，实际未发现输入路径。
- **证据**：静态推理。
- **修复建议（示意）**：43 行后补 `guard count > 0 else { return false }`。
- **是否阻塞上架**：否。

### STA-010｜P2｜崩溃源·边界｜TrendDetector.ncps.first!

- **文件:行**：`TransformEngine/TrendDetector.swift:285`（`var bestNCP = trend.ncps.first!`）
- **现象**：`importantNote(trend:...)` 若 `trend.ncps` 为空则崩溃。调用方 275 行遍历 `sections`，空 section 理论可达。
- **影响**：理论可达，需构造空 ncps 趋势段。
- **证据**：静态推理。
- **修复建议（示意）**：285 行前 `guard let first = trend.ncps.first else { return TransformEngine.NoteChordPair() }`。
- **是否阻塞上架**：否。

### STA-011｜P2｜崩溃源·边界｜GrammarStrategy segment 空 chordBlocks.first!

- **文件:行**：`Grammar/GrammarStrategy.swift:270`（`let startChord = section.chordBlocks.first!`）
- **现象**：`.segment` 分支遍历 sections，若某 section 的 chordBlocks 为空则崩溃。
- **影响**：理论可达。
- **证据**：静态推理。
- **修复建议（示意）**：270 行改 `guard let startChord = section.chordBlocks.first else { continue }`。
- **是否阻塞上架**：否。

### STA-012｜P2｜崩溃源·不可达｜GlobalOptimalGuideToneStrategy Viterbi 回溯强制解包

- **文件:行**：`CoreEngine/JazzStrategy.swift:275`（`currentPitch = dp[i][currentPitch]!.prevPitch!`）
- **现象**：若某和弦 `getAllChordTones` 返回空候选，`dp[0]` 为空，`bestFinalPitch` 保持 -1，275 行 `dp[i][-1]!` 崩溃。
- **可达性**：该策略类未在 `getStrategyInstance()`（ContentView.swift:65）映射，UI 不可达；仅为死代码/未来扩展。
- **证据**：静态推理。
- **修复建议（示意）**：264 行后 `guard bestFinalPitch >= 0 else { return [] }`。
- **是否阻塞上架**：否。

### STA-013｜P2｜崩溃源·边界｜LSTM 起始把位 next(upperBound:) 当区间≤0 崩溃

- **文件:行**：`LSTM/LSTMStrategy.swift:77`（`Int(seedGen.next(upperBound: UInt64(file.highBound - file.lowBound)))`）
- **现象**：若 `.rnn` 文件头 `highBound <= lowBound`，`next(upperBound: 0)` 运行时 trap。
- **影响**：打包文件头正常（highBound>lowBound）；仅当资源损坏/被替换时触发。
- **证据**：静态推理。
- **修复建议（示意）**：76 行前 `let span = max(1, file.highBound - file.lowBound)`。
- **是否阻塞上架**：否。

### STA-014｜P2｜内存·边界｜RNNModel.readMatrix 无上限分配

- **文件:行**：`LSTM/RNNModel.swift:108-109`（`let count = rows * cols; var data = [Float](repeating: 0.0, count: count)`）
- **现象**：`rows`/`cols` 直接来自文件头 U32，未设上限。损坏/篡改的 .rnn 可声明超大矩阵导致 OOM。
- **影响**：打包文件可信；仅资源异常时风险。
- **证据**：静态推理。
- **修复建议（示意）**：加 `guard count < 20_000_000 else { throw RNNReaderError.badMagic("matrix too large") }`。
- **是否阻塞上架**：否。

### STA-015｜P2｜内存·回调｜onExternalPlaybackChange 闭包在单例持久化

- **文件:行**：`Views/ContentView.swift:2246-2249`（`JazzMidiPlayer.shared.onExternalPlaybackChange = { ... self.isPlaying = ... }`）
- **现象**：在 `.onAppear` 设置，`.onDisappear` 未置 nil。JazzMidiPlayer 是单例，闭包持久存在。因 ContentView 是 struct（值类型），无经典引用循环，但闭包捕获的 @State 包装器指向旧视图状态。
- **影响**：轻微，不崩溃；onNotePlay 在 2941 行有置 nil，onExternalPlaybackChange 没有。
- **证据**：静态推理。
- **修复建议（示意）**：`.onDisappear` 补 `JazzMidiPlayer.shared.onExternalPlaybackChange = nil`。
- **是否阻塞上架**：否。

### STA-016｜P2｜崩溃源·一致性｜worker 内 measureDurations 下标无边界检查

- **文件:行**：`Views/ContentView.swift:1335`（`let measureDurations = actualSong.measureDurations[measureIndex]`）
- **现象**：同文件 1036/1093/1233/1624 行均用 `measureIndex < actualSong.measureDurations.count ? ... : [4.0]` 守卫，唯独 1335 行裸下标。JazzSong init（JazzSong.swift:29-36）会在 `measureDurations` 整体为空时自愈平均分配，故当前所有构造路径（IReal 解析 710-721 对齐、BuiltinMelodyLibrary 250-258 同循环、transposeSong 4469 直接拷贝）均对齐。
- **影响**：防御性不一致；若未来新增构造器传入「半填充」measureDurations（count < measures.count），init 不兜底（仅在整体空时兜底），1335 行会越界崩溃。
- **证据**：静态推理。
- **修复建议（示意）**：1335 行改为与 1233 行相同的三目守卫。
- **是否阻塞上架**：否。

---

## 已排查并确认安全的项（不计入发现）

- `try!`：仅 `Importers/MusicXML/MusicXMLParser.swift:128`，静态 `NSRegularExpression` 编译常量，运行时不失败。
- `as!`：0 处。
- `fatalError`：0 处（仅 ThemeWeaver 注释提及）。
- `precondition`：2 处均在 `ThemeWeaver/`（暂停功能，不在本次范围）。
- `assert`：4 处均在 DEBUG 构建，Release 不触发。
- `@IBOutlet`：0（SwiftUI App）。
- `URL(string:"常量")!`：`Views/LicensesView.swift:14-15`，常量字符串，安全。
- `Bundle.main.url(forResource:)` 资源缺失：全部用 `guard let`/`if let` 优雅返回（Grammar.swift:156、BrickDictionaryParser.swift:116、JavaBrickParser.swift:521、BuiltinMelodyLibrary.swift:97、JazzMidiPlayer.swift:65）。
- 导入异常路径：`importFromFile`（ContentView.swift:570-626）全用 `try?` + do/catch + 空结果守卫；MusicXML 解压 .mxl 明确提示不支持。
- 空歌单/空 Solo 播放：`JazzMidiPlayer.playWithAccompaniment` 409 行 `guard !solo.isEmpty else { return }`。
- 数组越界：`JazzMidiPlayer` startIndex 用 `max(0, min(...))` 钳制；`hasCrossGridTie`/`hasOrphanTieStart` 用 `notes.count - 1`/`measures.count - 1` 安全循环。
- 解析器 `while !input.isEmpty`（IRealProParser:227）：每轮至少 `removeFirst()` 前进，不死循环。
- `safeSleep`（JazzMidiPlayer:303）：cancel 检查 + `targetNs <= now` break，不死循环。
