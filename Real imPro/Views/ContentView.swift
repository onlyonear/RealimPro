import SwiftUI

struct ContentView: View {
    // MARK: 算法分组枚举
    enum ImproAlgorithmGroup: String, Equatable {
        case basic = "Basic"
        case master = "Master"
    }

    enum ImproAlgorithmType: String, Equatable {
        // 基础组
        case chordExercise = "Chord+App"
        case colorTone = "Chord+Col"
        
        // 大师组
        case Lick = "Lick"
        case LeeMorgan = "LeeMorgan"
        case charlieParker = "CharliePark"
        //case ColemanHawkins = "ColemanHawkins"
        
        
        /// 映射对应策略实例
        func getStrategyInstance() -> GrammarStrategy? {
            switch self {
            case .chordExercise:   return GrammarStrategy.chord
            case .colorTone:       return GrammarStrategy.color
            case .charlieParker:   return GrammarStrategy.charlieParker
            case .Lick:            return GrammarStrategy.Lick
            //case .ColemanHawkins:  return GrammarStrategy.ColemanHawkins
            case .LeeMorgan:       return GrammarStrategy.LeeMorgan
            }
        }
        
        /// 映射文法文件名
        var grammarFileName: String {
            switch self {
            case .chordExercise:   return "chord"
            case .colorTone:       return "color"
            case .charlieParker:   return "Bebop"
            case .Lick:            return "greatMoments"
            //case .ColemanHawkins:  return "ColemanHawkins-Ballads"
            case .LeeMorgan:           return "Blues"
            }
        }
    }
    // MARK: - 状态管理
    // 当前选中的歌单（根据选中的索引动态获取）
    private var currentPlaylist: JazzPlaylist {
        playlists[selectedPlaylistIndex]
    }
    @State private var selectedSong: JazzSong? = nil
    @State private var generatedSolo: [GeneratedMeasure] = []
    @State private var showAnalysis: Bool = false        // 级数分析开关
    @State private var currentAnalysis: AnalysisResult? = nil  // 当前歌曲的调性分析结果 (PostProcessorFull 方案)
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @EnvironmentObject var iapManager: IAPManager
    
    // 侧边栏显示状态
    @State private var showSidebar = UIScreen.main.bounds.width >= 950
    @State private var showPaywall = false
    @State private var pendingMasterAlgorithm: ImproAlgorithmType? = nil
    private var sidebarAsOverlay: Bool { toolbarSize.width < 950 }

    /// 内容区统一水平边距：乐谱与调音台共用，确保左右对齐
    private var contentHorizontalMargin: CGFloat {
        sidebarAsOverlay ? max(12, (toolbarSize.width - 780) / 2) : 12
    }
    
    private var isVerySmallScreen: Bool {
        UIScreen.main.bounds.width < 800   // mini 竖屏 744pt
    }
    
    // MARK: - 工具栏尺寸感知（横竖屏自适应字号）
    private struct ToolbarSizeKey: PreferenceKey {
        static let defaultValue: CGSize = .zero
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
            value = nextValue()
        }
    }
    
    @State private var toolbarSize: CGSize = .zero
    
    private var labelFontSize: CGFloat {
        let w = toolbarSize.width
        let h = toolbarSize.height
        if h > w {
            if w < 800 { return 11 }      // mini 竖屏
            if w < 950 { return 12 }      // 11" 竖屏
            return 15                      // 13" 竖屏
        } else {
            if h < 900 { return 13 }      // mini / 11" 横屏
            return 15                      // 13" 横屏
        }
    }
    
    private var showCompactLabels: Bool {
        toolbarSize.height > toolbarSize.width && toolbarSize.width < 800
    }

    /// Basic/Master 分段控件最大宽度（仅容纳文字，横屏不拉伸）
    private var segmentedControlMaxWidth: CGFloat {
        if showCompactLabels { return 72 }
        return labelFontSize >= 15 ? 140 : 124
    }

    /// 语法标签宽度（容纳最长的 CharliePark，不截断）
    private var algorithmLabelWidth: CGFloat {
        if isVerySmallScreen { return 95 }
        if toolbarSize.width < 950 { return 105 }
        return 115
    }
    
    // MARK: - 持久化
    private static var saveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("playlists.json")
    }
    
    private static func loadPlaylists() -> [JazzPlaylist] {
        guard let data = try? Data(contentsOf: saveURL),
              let loadedSongs = try? JSONDecoder().decode([JazzSong].self, from: data),
              !loadedSongs.isEmpty else {
            return [.demoPlaylist]
        }
        return [JazzPlaylist(name: NSLocalizedString("My Songs", comment: ""), songs: [JazzPlaylist.demoSong] + loadedSongs)]
    }
    
    private func savePlaylists() {
        let userSongs = Array(playlists[0].songs.dropFirst())
        guard let data = try? JSONEncoder().encode(userSongs) else { return }
        try? data.write(to: ContentView.saveURL)
    }

    /// 统一去重 key（标题+作曲家，不区分大小写，去空格）
    private func dedupKey(for song: JazzSong) -> String {
        "\(song.title.trimmingCharacters(in: .whitespaces).lowercased())|\(song.composer.trimmingCharacters(in: .whitespaces).lowercased())"
    }

    /// 文件导入结果
    private struct FileImportResult {
        var songs: [JazzSong]
        var error: String?
    }

    /// 从文件 URL 读取并解析 iReal Pro 歌曲（后台线程调用）
    private static func importFromFile(url: URL) -> FileImportResult {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return FileImportResult(songs: [], error: NSLocalizedString("无法读取文件，请确认文件编码为 UTF-8。", comment: ""))
        }

        let parsed = IRealProParser.parseHTML(html: content)
        if parsed.isEmpty {
            return FileImportResult(songs: [], error: NSLocalizedString("文件中未找到有效的 iReal Pro 乐谱。", comment: ""))
        }

        let songs = parsed.map { IRealProParser.toJazzSong($0) }
        return FileImportResult(songs: songs, error: nil)
    }

    /// 处理文件导入结果：去重、导入、提示
    private func handleImportResult(_ result: FileImportResult) {
        if let error = result.error, result.songs.isEmpty {
            fileImportError = error
            importedTotalCount = 0
            importSkippedCount = 0
            mixedAlertCount = 0
            showImportResultAlert = true
            return
        }

        fileImportError = nil

        let existingKeys = Set(playlists[selectedPlaylistIndex].songs.map { dedupKey(for: $0) })
        let newSongs = result.songs.filter { !existingKeys.contains(dedupKey(for: $0)) }
        importSkippedCount = result.songs.count - newSongs.count

        if !newSongs.isEmpty {
            playlists[selectedPlaylistIndex].songs.append(contentsOf: newSongs)
            savePlaylists()
            if let firstSong = newSongs.first {
                selectedSong = firstSong
            }
        }

        importedTotalCount = newSongs.count
        mixedAlertCount = newSongs.filter { $0.hasMixedTimeSignature }.count

        let hasMixed = mixedAlertCount > 0
        let hasSkipped = importSkippedCount > 0
        let hasNew = importedTotalCount > 0
        showImportResultAlert = hasMixed || hasSkipped || !hasNew
    }

    /// 处理 URL Scheme 导入 (irealb:// 或 irealbook://)
    private func handleURLImport(_ url: URL) {
        let urlString = url.absoluteString
        guard urlString.hasPrefix("irealb://") || urlString.hasPrefix("irealbook://") else { return }

        isLoadingFile = true
        DispatchQueue.global(qos: .userInitiated).async {
            let parsed = IRealProParser.parsePlaylist(url: urlString)
            let songs = parsed.map { IRealProParser.toJazzSong($0) }

            DispatchQueue.main.async {
                isLoadingFile = false
                if songs.isEmpty {
                    handleImportResult(FileImportResult(
                        songs: [],
                        error: NSLocalizedString("Failed to parse iReal Pro link.", comment: "")
                    ))
                } else {
                    handleImportResult(FileImportResult(songs: songs, error: nil))
                }
            }
        }
    }

    @State private var showImportSheet = false
    @State private var showImportResultAlert = false
    @State private var importSkippedCount = 0
    @State private var mixedAlertCount = 0
    @State private var importedTotalCount = 0
    @State private var showFilePicker = false        // 🌟 系统文件选择器
    @State private var isLoadingFile = false         // 🌟 文件导入 loading
    @State private var fileImportError: String? = nil // 🌟 文件级错误消息
    @State private var playlists: [JazzPlaylist] = ContentView.loadPlaylists()
    @State private var selectedPlaylistIndex = 0
    
    // 音域范围
    @State private var lowNoteMidi: Int = 60    // 最低音 MIDI（默认 C4，中央C）
    @State private var highNoteMidi: Int = 81   // 最高音 MIDI（默认 A5）
    
    // 钢琴键盘高亮的音符（MIDI 编号集合）
    @State private var activeMidiNotes: Set<Int> = []
    
    // 追踪播放游标 ID 以及曲谱更新版本
    @State private var playingNoteId: String = ""
    @State private var soloVersion: UUID = UUID()
    @State private var hasGeneratedSolo: Bool = false // 🌟 区分屏幕上当前是“骨架谱”还是“真实的 Solo”
    
    // 🌟 新增：播放状态机与跳转锚点
    @State private var isPlaying: Bool = false
    @State private var isPaused: Bool = false
    @State private var startMeasureIndex: Int = 0
    
    // MARK: - 设置面板开关
    @State private var showSettings = false
    
    // MARK: - 🎵 算法分组 & 选择（顶部栏专用）
    @State private var selectedAlgorithmGroup: ImproAlgorithmGroup = .basic
    @State private var selectedAlgorithm: ImproAlgorithmType = .chordExercise
    @State private var enableTransform = false  // 暂时隐藏, 仅Grammar内部使用
    
    /// 根据当前分组，动态返回下拉算法列表
    private var currentAlgorithmList: [ImproAlgorithmType] {
        switch selectedAlgorithmGroup {
        case .basic:
            return [.chordExercise, .colorTone]
        case .master:
            return [.Lick, .LeeMorgan, .charlieParker ]
        }
    }
    
    
    
    // MARK: - 🎵 播放与调号设置
    @State private var tempo: Int = 120
    @State private var selectedKey: String = "C"
    
    // MARK: - 🎛️ 调音台状态
    @State private var saxVolume: Float     = 0.8
    @State private var pianoVolume: Float   = 0.8
    @State private var bassVolume: Float    = 0.8
    @State private var drumVolume: Float    = 0.8
    @State private var saxMuted: Bool       = false
    @State private var pianoMuted: Bool     = false
    @State private var bassMuted: Bool      = false
    @State private var drumMuted: Bool      = false
    @State private var selectedStyle: MixerDisplayMode = .swing
    @State private var showMixer: Bool      = true
    
    // MARK: - 🎵 辅助：时值转换与空谱表骨架生成
    // 🌟 全新上帝视角映射引擎：无论传入什么数字，必定返回在数学上绝对匹配的 (字符串, 连音修饰)
    private func getExactVexFlowDuration(for slots: Int, isRest: Bool) -> (dur: String, tuplet: Int) {
        var dur = "32"
        var tup = 0
        
        switch slots {
        case 480...Int.max: dur = "w"; tup = 0
        case 360...479: dur = "hd"; tup = 0
        case 320...359: dur = "w"; tup = 3    // 480 * 2/3 = 320
        case 240...319: dur = "h"; tup = 0
        case 180...239: dur = "qd"; tup = 0
        case 160...179: dur = "h"; tup = 3    // 240 * 2/3 = 160
        case 120...159: dur = "q"; tup = 0
        case 96...119: dur = "q"; tup = 5     // 120 * 4/5 = 96
        case 90...95: dur = "8d"; tup = 0
        case 80...89: dur = "q"; tup = 3      // 120 * 2/3 = 80
        case 72...79: dur = "8d"; tup = 5     // 90 * 4/5 = 72
        case 60...71: dur = "8"; tup = 0
        case 48...59: dur = "8"; tup = 5      // 60 * 4/5 = 48
        case 45...47: dur = "16d"; tup = 0
        case 40...44: dur = "8"; tup = 3      // 60 * 2/3 = 40
        case 30...39: dur = "16"; tup = 0
        case 24...29: dur = "16"; tup = 5     // 30 * 4/5 = 24
        case 20...23: dur = "16"; tup = 3     // 30 * 2/3 = 20
        case 15...19: dur = "32"; tup = 0
        case 12...14: dur = "32"; tup = 5     // 15 * 4/5 = 12 (自愈 483 bug)
        case 10...11: dur = "32"; tup = 3     // 15 * 2/3 = 10 (自愈 482 bug)
        case 7...9: dur = "64"; tup = 0
        case 5...6: dur = "64"; tup = 3
        default: dur = "128"; tup = 0
        }
        
        if isRest { dur += "r" }
        return (dur, tup)
    }

    private func generateEmptyRoadmap() {
        guard let song = selectedSong else {
            generatedSolo.removeAll()
            return
        }
        
        let actualSong = (song.key == selectedKey) ? song : Self.transposeSong(song, to: selectedKey)
        let timeSig = actualSong.timeSignature ?? "4/4"
        let tsParts = timeSig.split(separator: "/")
        let tsNum = Int(tsParts.first ?? "4") ?? 4
        let tsBeat = Int(tsParts.last ?? "4") ?? 4
        let slotsPerMeasure = tsNum * (480 / tsBeat)
        let profile = TimeSignatureManager.getProfile(for: timeSig)
        var tempMeasures: [GeneratedMeasure] = []
        
        for (measureIndex, measureChords) in actualSong.measures.enumerated() {
            // 🌟 修复类型不匹配：measureDurations 存储的是拍数(Double，如 4.0 拍)，而不是 slots(480)
            let durations = measureIndex < actualSong.measureDurations.count ? actualSong.measureDurations[measureIndex] : [4.0]
            let sectionName = actualSong.sectionMarkers[measureIndex]
            var measureNotes: [GeneratedNote] = []
            var chordAnnotations: [(chord: String, noteIndex: Int)] = []
            
            let validChords = measureChords.filter {
                let clean = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return !clean.isEmpty && clean != "NC" && clean != "N.C."
            }
            let mainChord = validChords.first ?? ""
            
            var currentSlotsInMeasure = 0
            var chordIndex = 0
            var noteIndexCounter = 0
            
            // 用休止符完美按照和弦时值填满小节，构建完美的铅字排版骨架
            while currentSlotsInMeasure < profile.slotsPerMeasure {
                let takeSlots: Int
                let currentChord: String
                
                if chordIndex < durations.count {
                    let chordSlots = Int(durations[chordIndex] * 120.0)
                    takeSlots = min(chordSlots, profile.slotsPerMeasure - currentSlotsInMeasure)
                    currentChord = measureChords[chordIndex]
                    chordIndex += 1
                } else {
                    takeSlots = profile.slotsPerMeasure - currentSlotsInMeasure
                    currentChord = ""
                }
                
                guard takeSlots > 0 else { continue }
                
                let cleanChord = currentChord.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanChord.isEmpty && cleanChord != "NC" && cleanChord != "N.C." {
                    chordAnnotations.append((chord: cleanChord, noteIndex: noteIndexCounter))
                }
                
                // 🌟 核心修复：引入安全分块机制 (Chunking)，防止时值超过 VexFlow 最大支持的全音符(480)导致 Ticks 丢失！
                var remainingTake = takeSlots
                let standards = [480, 360, 240, 180, 120, 90, 60, 30, 15]
                
                while remainingTake > 0 {
                    var chunk = remainingTake
                    for std in standards {
                        if std <= remainingTake {
                            chunk = std
                            break
                        }
                    }
                    
                    let vf = self.getExactVexFlowDuration(for: chunk, isRest: true)
                    let encodedDuration = vf.tuplet > 0 ? "\(vf.dur)_t\(vf.tuplet)" : vf.dur
                    
                    measureNotes.append(GeneratedNote(
                        pitch: "B/4", tag: .chordTone, isRest: true,
                        duration: encodedDuration,
                        isTriplet: vf.tuplet > 0, 
                        isTieStart: false, isTieEnd: false
                    ))
                    
                    remainingTake -= chunk
                    noteIndexCounter += 1
                }
                
                currentSlotsInMeasure += takeSlots
            }
            tempMeasures.append(GeneratedMeasure(
                chord: mainChord, notes: measureNotes,
                chordAnnotations: chordAnnotations, sectionName: sectionName,
                slotsPerMeasure: slotsPerMeasure
            ))
        }
        
        // 🔍 诊断增强：模拟 VexFlow ticks 累加，检查每个小节是否合法
        #if DEBUG
        print("========== 小节 ticks 预检查 ==========")
        #endif
        for (mi, m) in tempMeasures.enumerated() {
            let ticks = m.notes.reduce(0.0) { total, note in
                let parts = note.duration.components(separatedBy: "_t")
                let durWithDot = parts[0].replacingOccurrences(of: "r", with: "")
                // 🌟 把附点也剥离干净，拿到纯净的基础字母做 switch！
                let baseDur = durWithDot.replacingOccurrences(of: "d", with: "") 
                let tupletVal = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
                var baseTicks: Double = 4096
                switch baseDur {
                case "w": baseTicks = 4096
                case "h": baseTicks = 2048
                case "q": baseTicks = 1024
                case "8": baseTicks = 512
                case "16": baseTicks = 256
                case "32": baseTicks = 128
                case "64": baseTicks = 64
                case "128": baseTicks = 32
                default: baseTicks = 1024
                }
                if durWithDot.contains("d") { baseTicks *= 1.5 }
                if tupletVal == 3 { baseTicks *= 2.0/3.0 }
                else if tupletVal == 5 { baseTicks *= 4.0/5.0 }
                else if tupletVal == 7 { baseTicks *= 4.0/7.0 }
                return total + baseTicks
            }
            // 基于 1个四分音符 = 120 slots = 1024 ticks 的绝对映射关系计算本小节标准 Ticks
            let expectedTicks = Double(profile.slotsPerMeasure) / 120.0 * 1024.0
            let diff = abs(ticks - expectedTicks)
            if diff > 0.1 {
                print("❌ 小节 \(mi+1) ticks 异常: 计算值=\(ticks) (目标=\(expectedTicks), diff=\(diff))")
                for (ni, n) in m.notes.enumerated() {
                    #if DEBUG
                    print("  音符\(ni): \(n.pitch) dur=\(n.duration) isTri=\(n.isTriplet)")
                    #endif
                }
            } else {
                #if DEBUG
                print("✅ 小节 \(mi+1) ticks=\(ticks) 合法")
                #endif
            }
        }
        #if DEBUG
        print("========================================")
        #endif
        
        // ── 级数分析：生成调性分析数据（用歌曲调号作为显式主调，不再用首和弦推断）──
        let roadmap = JazzRoadmap(title: actualSong.title, tempo: actualSong.tempo)
        for (measureIndex, measureChords) in actualSong.measures.enumerated() {
            let measureDurations = measureIndex < actualSong.measureDurations.count ? actualSong.measureDurations[measureIndex] : [4.0]
            let chordDurationPairs = zip(measureChords, measureDurations)
                .filter { chord, _ in
                    let clean = chord.trimmingCharacters(in: .whitespacesAndNewlines)
                    return !clean.isEmpty && clean != "NC" && clean != "N.C."
                }
            for (chordName, duration) in chordDurationPairs {
                let cleanChord = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
                let isSectionStart = actualSong.sectionMarkers[measureIndex] != nil
                roadmap.append(block: ChordBlock(name: cleanChord, duration: duration, isSectionStart: isSectionStart))
            }
        }
        let keyInfo = KeyParser.parseKey(selectedKey)
        self.currentAnalysis = PostProcessorFull.analyze(
            roadmap: roadmap,
            tonicPC: keyInfo.tonicPC,
            mode: keyInfo.mode,
            beatsPerMeasure: Double(tsNum)
        )
        
        self.generatedSolo = tempMeasures
        self.soloVersion = UUID()
    }
    
    // MARK: - 🎷 核心即兴算法管线
    private func runJazzGenerationPipeline() {
        guard let song = selectedSong else { return }
        
        // 最底层保险：任何路径调用 Master 算法都必须先购买
        if selectedAlgorithmGroup == .master && !iapManager.isPurchased {
            pendingMasterAlgorithm = selectedAlgorithm
            showPaywall = true
            return
        }
        
        // 如果调号不同，先把整首歌转调到目标调
        let actualSong: JazzSong
        if song.key == selectedKey {
            actualSong = song
        } else {
            actualSong = Self.transposeSong(song, to: selectedKey)
        }
        
        // 1. 初始化大脑 Roadmap
        let roadmap = JazzRoadmap(title: actualSong.title, tempo: actualSong.tempo)
        #if DEBUG
        print("🎵 小节数: \(actualSong.measures.count), 时值数组数: \(actualSong.measureDurations.count)")
        #endif
        for (i, m) in actualSong.measures.enumerated() {
            let d = actualSong.measureDurations[i]
            #if DEBUG
            print("小节 \(i): 和弦数 \(m.count), 时值数 \(d.count), 时值: \(d)")
            #endif
        }
        for (measureIndex, measureChords) in actualSong.measures.enumerated() {
            // 把和弦和对应的时值打包，然后过滤出有效和弦
            let measureDurations = actualSong.measureDurations[measureIndex]
            let chordDurationPairs = zip(measureChords, measureDurations)
                .filter { chord, _ in
                    let clean = chord.trimmingCharacters(in: .whitespacesAndNewlines)
                    return !clean.isEmpty && clean != "NC" && clean != "N.C."
                }
            let validChords = chordDurationPairs.map { $0.0 }
            let durations = chordDurationPairs.map { $0.1 }
            
            guard !validChords.isEmpty else { continue }
            
            for (index, chordName) in validChords.enumerated() {
                let cleanChord = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
                let duration = durations[index]
                // 🌟 检查当前小节是不是段落开始，如果是，给第一个和弦打上标记
                let isSectionStart = (index == 0) && (actualSong.sectionMarkers[measureIndex] != nil)
                roadmap.append(block: ChordBlock(name: cleanChord, duration: duration, isSectionStart: isSectionStart))
            }
        }
        
        // 2. 🎯 根据选中算法构造策略 + 设置Transform模式
        guard let grammarStrategy = selectedAlgorithm.getStrategyInstance() else { return }
        grammarStrategy.transformMode = enableTransform ? .grammarWithTransform : .rawGrammar
        let activeStrategy: JazzImproStrategy = grammarStrategy
        
        // ── 排版兜底：生成 Solo 后检查 Slot 守恒，不通过则重新生成（最多 5 次）──
        let maxRetries = 5
        var retryCount = 0
        var tempMeasures: [GeneratedMeasure] = []
        var finalPhysicalNotes: [PhysicalNote] = []
        var hasLayoutWarning = false
        var hasCrossGrid = false
        var hasOrphanTie = false
        
        repeat {
            let physicalNotes = activeStrategy.generateSolo(for: roadmap)
            finalPhysicalNotes = physicalNotes
            
            finalPhysicalNotes = LightPostProcessor.mergeAdjacent(finalPhysicalNotes)  // 兜底相邻同音合并，防止渲染分裂


        //print("🎼 [架构日志] 策略选择: \(activeStrategy.name) | 成功生成物理音符数: \(finalPhysicalNotes.count)")
        
       // 🌟 诊断探针：拦截并打印被 VexFlow 屠宰前的原始物理时值
        //print("==================================================")
        //print("🕵️‍♂️ [底层数据透视] 准备切割的小节总数: \(actualSong.measures.count)")
        let rawDurations = finalPhysicalNotes.map { String($0.durationSlots) }.joined(separator: ", ")
        //print("⏱️ 所有原始物理音符的时值数组 (Slots):")
        //print("[\(rawDurations)]")
        //print("==================================================")
        // 3. 将物理音符翻译为前端渲染及 MIDI 播放器可看懂的 GeneratedMeasure
        
        // ==============================================================
        // 🌟 Phase 2: 倚音全局预处理 (剥离 <= 15 的碎片)
        var globalEnriched: [EnrichedNote] = []
        var pendingGraces: [Int] = [] // 🌟 缓存区：暂存属于下一个主干音的倚音音高
        
        for pNote in finalPhysicalNotes {
            if pNote.durationSlots <= 15 && pNote.midiPitch >= 0 {
                // 1. 数学时值补偿：把被偷走的 slots 还给前一个音符（维持网格绝对对齐）
                if !globalEnriched.isEmpty && !globalEnriched[globalEnriched.count - 1].isRest {
                    globalEnriched[globalEnriched.count - 1].durationSlots += pNote.durationSlots
                }
                // 2. 视觉排版脱钩：将音高暂存，准备挂载给【下一个】主干音！
                pendingGraces.append(pNote.midiPitch)
            } else {
                // 遇到主干音：将之前缓存的趋近音全部挂载给它，实现完美的先现引导！
                // 🔍 排查: pNote运行时类型确认
                //print("【PhysicalNote来到CV】 type=\(type(of: pNote)) midi=\(pNote.midiPitch) terminalType=\(pNote.terminalType ?? "nil")")
                globalEnriched.append(EnrichedNote(midiPitch: pNote.midiPitch, durationSlots: pNote.durationSlots, gracePitches: pendingGraces, terminalType: pNote.terminalType))
                // 🔍 排查日志: EnrichedNote透传
                //print("【EnrichedNote透传】 midi=\(pNote.midiPitch) terminalType=\(pNote.terminalType ?? "nil")")
                pendingGraces = [] // 清空缓存
            }
        }

        let timeSig = actualSong.timeSignature ?? "4/4"
        let tsParts = timeSig.split(separator: "/")
        let tsNum = Int(tsParts.first ?? "4") ?? 4
        let tsBeat = Int(tsParts.last ?? "4") ?? 4
        let slotsPerMeasure = tsNum * (480 / tsBeat)
        let profile = TimeSignatureManager.getProfile(for: timeSig)
        // 🌟 Phase 3: 绝对数学切片 (将全局流按小节无情切分为 480 slots 的生肉)
        var measureRawChunks: [[EnrichedNote]] = []
        var noteIdx = 0
        var remainingSlots = 0
        var currentGNote: EnrichedNote? = nil
        let totalMeasures = actualSong.measures.count
        
        var pendingTie = false // 🌟 恢复跨小节连线状态追踪！
        var measurePendingTie: [Bool] = [] // 🔍 TIE BUG 追踪：捕获每小节进入时的 pendingTie

        for _ in 0..<totalMeasures {
            measurePendingTie.append(pendingTie) // 🔍 快照：进入本小节前的跨小节连线状态
            var chunksInMeasure: [EnrichedNote] = []
            var slotsInMeasure = 0

            while slotsInMeasure < profile.slotsPerMeasure {
                if remainingSlots <= 0 {
                    if noteIdx < globalEnriched.count {
                        currentGNote = globalEnriched[noteIdx]
                        remainingSlots = currentGNote!.durationSlots
                        noteIdx += 1
                    } else {
                        remainingSlots = profile.slotsPerMeasure - slotsInMeasure
                        currentGNote = EnrichedNote(midiPitch: -1, durationSlots: remainingSlots, gracePitches: [])
                    }
                }

                guard let note = currentGNote else { break }
                let spaceLeft = profile.slotsPerMeasure - slotsInMeasure
                let take = min(remainingSlots, spaceLeft)

                let isFirstSlice = (remainingSlots == note.durationSlots)
                let isLastSlice = (take == remainingSlots) // 音符已完全放进本小节

                var currentTieStart = false
                var currentTieEnd = false

                // 🌟 承接上一小节抛过来的延音线
                if pendingTie && !note.isRest {
                    currentTieEnd = true
                    pendingTie = false
                }
                // 🌟 如果音符没放完（被小节线无情切断），向下一小节抛出延音线
                if !isLastSlice && !note.isRest {
                    currentTieStart = true
                    pendingTie = true
                }

                let graces = isFirstSlice ? note.gracePitches : []
                chunksInMeasure.append(EnrichedNote(
                    midiPitch: note.midiPitch,
                    durationSlots: take,
                    gracePitches: graces,
                    isTieStart: currentTieStart, // 注入给量化器
                    isTieEnd: currentTieEnd,      // 注入给量化器
                    terminalType: note.terminalType
                ))

                slotsInMeasure += take
                remainingSlots -= take
            }
            measureRawChunks.append(chunksInMeasure)
        }

        // 🌟 Phase 4: 网格量化与 UI 数据映射
        var tempMeasures: [GeneratedMeasure] = []

        for measureIndex in 0..<totalMeasures {
            let sectionName = actualSong.sectionMarkers[measureIndex]
            var measureNotes: [GeneratedNote] = []
            var chordAnnotations: [(chord: String, noteIndex: Int)] = []

            // 获取本小节和弦槽位
            var mainChord = ""
            var chordStartSlots: [(chord: String, startSlot: Int)] = []
            if measureIndex < actualSong.measures.count {
                let chords = actualSong.measures[measureIndex]
                let durations = measureIndex < actualSong.measureDurations.count ? actualSong.measureDurations[measureIndex] : [4.0]
                var accumulatedSlots = 0
                for (idx, ch) in chords.enumerated() {
                    let clean = ch.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty && clean != "NC" && clean != "N.C." {
                        if mainChord.isEmpty { mainChord = clean }
                        chordStartSlots.append((chord: clean, startSlot: accumulatedSlots))
                    }
                    let dur = idx < durations.count ? durations[idx] : 4.0
                    accumulatedSlots += Int(dur * 120.0)
                }
            }

            // 🚀 核心大招：调用 GridQuantizer 获取完全符合乐理规范的音符碎片！
            let rawChunks = measureRawChunks[measureIndex]
            let quantizedNotes = GridQuantizer.quantize(notes: rawChunks, profile: profile, hasPendingTie: measurePendingTie[measureIndex])
            let mergedNotes = GridQuantizer.mergeAdjacentEnriched(quantizedNotes)
            let splitNotes = GridQuantizer.splitCrossBeatDots(mergedNotes, beatSize: 120)
            // 调试：步骤 S - splitCrossBeatDots 后（跨拍拆分后 tie 快照）
            if measurePendingTie[measureIndex] && (rawChunks.first?.isRest ?? false) {
                #if DEBUG
                print("⚠️ [TIE BUG 追踪] 小节 \(measureIndex+1) - 步骤 S：splitCrossBeatDots 后")
                #endif
                for (si, sn) in splitNotes.enumerated() {
                    #if DEBUG
                    print("  音符 \(si): pitch=\(sn.midiPitch), dur=\(sn.durationSlots), isTieStart=\(sn.isTieStart), isTieEnd=\(sn.isTieEnd)")
                    #endif
                }
            }
            // 🔍 排查日志: 量化后音符terminalType
            for (qi, qn) in splitNotes.enumerated() {
                //print("【量化后音符】 idx=\(qi) midi=\(qn.midiPitch) terminalType=\(qn.terminalType ?? "nil")")
            }

            var currentSlotsInMeasure = 0
            var nextChordIndex = 0

            for qNote in splitNotes {
                let nextNonRestPitch: Int? = {
                    let nextIdx = measureNotes.count + 1
                    for j in nextIdx..<splitNotes.count {
                        if splitNotes[j].midiPitch >= 0 { return splitNotes[j].midiPitch }
                    }
                    return nil
                }()
                // 绑定和弦记号
                while nextChordIndex < chordStartSlots.count && currentSlotsInMeasure >= chordStartSlots[nextChordIndex].startSlot {
                    chordAnnotations.append((chord: chordStartSlots[nextChordIndex].chord, noteIndex: measureNotes.count))
                    nextChordIndex += 1
                }

                // 获取 VexFlow 标准时值 (此时 qNote.durationSlots 必然是合法的标准值或白名单上的连音)
                let vf = self.getExactVexFlowDuration(for: qNote.durationSlots, isRest: qNote.isRest)
                // 🌟 恢复：如果解析出 tuplet 值，则加上 _t 尾缀供 JS 端识别
                let encodedDuration = vf.tuplet > 0 ? "\(vf.dur)_t\(vf.tuplet)" : vf.dur

                // 计算音高拼写
                let pitchStr: String
                var activeChord = mainChord  // 提到外部作用域
                if qNote.isRest {
                    pitchStr = "B/4"
                } else {
                    if nextChordIndex > 0 && nextChordIndex - 1 < chordStartSlots.count {
                        activeChord = chordStartSlots[nextChordIndex - 1].chord
                    } else if !chordStartSlots.isEmpty {
                        activeChord = chordStartSlots[0].chord
                    }
                    var useFlats = false
                    if activeChord.contains("b") || (activeChord.hasPrefix("F") && !activeChord.hasPrefix("F#")) { useFlats = true }
                    else if activeChord.hasPrefix("Cm") || activeChord.hasPrefix("Dm") || activeChord.hasPrefix("Gm") { useFlats = true }

                    let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
                    let flatNames  = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
                    let noteNames = useFlats ? flatNames : sharpNames
                    let safePitch = max(0, min(127, qNote.midiPitch))
                    let octave = (safePitch / 12) - 1
                    let pitchClass = ((safePitch % 12) + 12) % 12
                    pitchStr = "\(noteNames[pitchClass])/\(octave)"
                }

                // 挂载倚音
                var generatedGraces: [GeneratedGraceNote] = []
                // 🌟 乐理排版升级：单倚音用带斜杠的 8 分音符，连续倚音组强制用无斜杠的 16 分音符双符杠排版！
                let graceDur = qNote.gracePitches.count >= 2 ? "16" : "8"
                for gp in qNote.gracePitches {
                    let gpStr = self.pitchForMIDI(gp, chordStartSlots: chordStartSlots, currentSlotsInMeasure: currentSlotsInMeasure, mainChord: mainChord, nextChordIndex: nextChordIndex)
                    generatedGraces.append(GeneratedGraceNote(pitch: gpStr, duration: graceDur, isRest: false))
                }

                // 使用 GrammarNoteConverter 透传的 terminalType，不再从 MIDI 音高反推
                var noteTag: MusicTheoryTag = tagFromTerminalType(qNote.terminalType)
                // 和弦音 → 永远黑色（最高优先级）
                let groundTruth = detectMusicTheoryTag(midiPitch: qNote.midiPitch, chordName: activeChord)
                if case .chordTone = groundTruth {
                    noteTag = .chordTone
                }
                // 非和弦音 → groundTruth 覆盖（趋近音需通过级进验证才保留蓝色）
                else if noteTag == .approachNote, let nextPitch = nextNonRestPitch {
                    if !isStepwiseApproach(qNote.midiPitch, nextPitch) {
                        noteTag = groundTruth
                    }
                } else if noteTag != .approachNote {
                    noteTag = groundTruth
                }
                
                // 🔍 排查日志: 标签判定结果
                if noteTag == .foreignTone || noteTag == .chordTone {
                    let groundTruth2 = detectMusicTheoryTag(midiPitch: qNote.midiPitch, chordName: activeChord)
                    #if DEBUG
                    print("🔍 [TAG-TRACE] pitch=\(qNote.midiPitch) chord=\(activeChord) terminal=\(qNote.terminalType ?? "nil") → tag=\(noteTag) groundTruth=\(groundTruth2)")
                    #endif
                }
                //print("【最终输出音符】 和弦=\(activeChord) midi=\(qNote.midiPitch) terminalType=\(qNote.terminalType ?? "nil") → tag=\(noteTag)")
                
                measureNotes.append(GeneratedNote(
                    pitch: pitchStr,
                    tag: noteTag,
                    isRest: qNote.isRest,
                    duration: encodedDuration,
                    isTriplet: vf.tuplet > 0, // 🌟 恢复：真正通知 VexFlow 这是一组需要画连音括号的音符！
                    isTieStart: qNote.isTieStart,
                    isTieEnd: qNote.isTieEnd,
                    graceNotes: generatedGraces
                ))

                currentSlotsInMeasure += qNote.durationSlots
            }

            tempMeasures.append(GeneratedMeasure(
                chord: mainChord,
                notes: measureNotes,
                chordAnnotations: chordAnnotations,
                sectionName: sectionName,
                slotsPerMeasure: slotsPerMeasure
            ))
        }

        // ==============================================================
        // 🌟 联合探针：出厂前全景核对单 (采用无损 Slots 核验)
        //print("\n================ 🎼 Swift端: 乐谱生成最终核对清单 ================")
        hasLayoutWarning = false
        hasCrossGrid = false
        hasOrphanTie = false
        for (mi, measure) in tempMeasures.enumerated() {
            var totalSlots = 0
            var noteDetails: [String] = []

            for note in measure.notes {
                let parts = note.duration.components(separatedBy: "_t")
                let base = parts[0].replacingOccurrences(of: "r", with: "").replacingOccurrences(of: "d", with: "")
                let hasDot = parts[0].contains("d")
                let tup = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
                
                var baseSlot = 120
                switch base {
                case "w": baseSlot = 480; case "h": baseSlot = 240; case "q": baseSlot = 120
                case "8": baseSlot = 60; case "16": baseSlot = 30; case "32": baseSlot = 15; default: break
                }
                if hasDot { baseSlot = Int(Double(baseSlot) * 1.5) }
                
                if tup == 3 { baseSlot = Int(Double(baseSlot) * 2.0/3.0) }
                else if tup == 5 { baseSlot = Int(Double(baseSlot) * 4.0/5.0) }
                else if tup == 7 { baseSlot = Int(Double(baseSlot) * 4.0/7.0) }
                
                totalSlots += baseSlot
                let tieStr = note.isTieStart ? "->" : (note.isTieEnd ? "<-" : "")
                let restStr = note.isRest ? "R" : ""
                noteDetails.append("[\(note.duration)\(restStr)\(tieStr) | \(baseSlot)s]")
            }

            #if DEBUG
            print("小节 \(mi + 1) | 总 Slots: \(totalSlots)")
            #endif
            #if DEBUG
            print("  ↳ 音符 (\(measure.notes.count)个): \(noteDetails.joined(separator: ", "))")
            #endif

            if totalSlots != profile.slotsPerMeasure {
                print("  ❌ [排版警告] 本小节 Slots 不守恒！偏差: \(totalSlots - profile.slotsPerMeasure)")
                hasLayoutWarning = true
            }
        }
        #if DEBUG
        print("==============================================================\n")
        #endif
        
        // 🔍 跨网格 tie 检测——异常时触发重试
        if hasCrossGridTie(in: tempMeasures) {
            #if DEBUG
            print("⚠️ [跨网格tie] 检测到跨网格延音线，第 \(retryCount + 1) 次重试")
            #endif
            hasCrossGrid = true
        }
        
        // 🔍 悬挂 tie 检测——异常时触发重试
        if hasOrphanTieStart(in: tempMeasures) {
            #if DEBUG
            print("⚠️ [悬挂tie] 检测到悬挂延音线，第 \(retryCount + 1) 次重试")
            #endif
            hasOrphanTie = true
        }
        
        // ── 级数分析：生成调性分析数据（复用已构建的 roadmap，用歌曲调号作为显式主调）──
        let keyInfo = KeyParser.parseKey(selectedKey)
        self.currentAnalysis = PostProcessorFull.analyze(
            roadmap: roadmap,
            tonicPC: keyInfo.tonicPC,
            mode: keyInfo.mode,
            beatsPerMeasure: Double(tsNum)
        )
        
        self.generatedSolo = tempMeasures
        self.soloVersion = UUID()
        
        retryCount += 1
        } while (hasLayoutWarning || hasCrossGrid || hasOrphanTie) && retryCount < maxRetries
    }
    
    // MARK: - 跨网格 tie 检测
    private func hasCrossGridTie(in measures: [GeneratedMeasure]) -> Bool {
        for measure in measures {
            let notes = measure.notes
            for i in 0..<(notes.count - 1) {
                let a = notes[i], b = notes[i + 1]
                guard a.isTieStart, b.isTieEnd, !a.isRest, !b.isRest else { continue }
                guard let aSlots = durationToSlots(a.duration),
                      let bSlots = durationToSlots(b.duration) else { continue }
                let aStandard = GridQuantizer.standardSlots.contains(aSlots)
                let bStandard = GridQuantizer.standardSlots.contains(bSlots)
                if aStandard != bStandard { return true }
            }
        }
        return false
    }
    
    private func hasOrphanTieStart(in measures: [GeneratedMeasure]) -> Bool {
        for i in 0..<(measures.count - 1) {
            let currNotes = measures[i].notes
            let nextNotes = measures[i + 1].notes
            guard let last = currNotes.last, last.isTieStart, !last.isRest else { continue }
            guard let first = nextNotes.first else { return true }
            if first.isRest { return true }
            if !first.isTieEnd { return true }
            if last.pitch != first.pitch { return true }
        }
        return false
    }
    
    private func durationToSlots(_ dur: String) -> Int? {
        let cleaned = dur.replacingOccurrences(of: "_t3", with: "")
                         .replacingOccurrences(of: "_t5", with: "")
        let hasDot = cleaned.hasSuffix("d")
        let base = hasDot ? String(cleaned.dropLast()) : cleaned
        var slots = 0
        switch base {
        case "w": slots = 480
        case "h": slots = 240
        case "q": slots = 120
        case "8": slots = 60
        case "16": slots = 30
        case "32": slots = 15
        default: return nil
        }
        if hasDot { slots = slots * 3 / 2 }
        return slots
    }
    
    // MARK: - 辅助：根据 MIDI 音高与当前和弦信息生成正确的拼写字符串
    private func pitchForMIDI(_ midi: Int, chordStartSlots: [(chord: String, startSlot: Int)], currentSlotsInMeasure: Int, mainChord: String, nextChordIndex: Int) -> String {
        var activeChord = mainChord
        if nextChordIndex > 0 && nextChordIndex - 1 < chordStartSlots.count {
            activeChord = chordStartSlots[nextChordIndex - 1].chord
        } else if !chordStartSlots.isEmpty {
            activeChord = chordStartSlots[0].chord
        }
        var useFlats = false
        if activeChord.contains("b") || (activeChord.hasPrefix("F") && !activeChord.hasPrefix("F#")) {
            useFlats = true
        } else if activeChord.hasPrefix("Cm") || activeChord.hasPrefix("Dm") || activeChord.hasPrefix("Gm") {
            useFlats = true
        }
        let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let flatNames  = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
        let noteNames = useFlats ? flatNames : sharpNames
        let safePitch = max(0, min(127, midi))
        let octave = (safePitch / 12) - 1
        let pitchClass = ((safePitch % 12) + 12) % 12
        let name = noteNames[pitchClass]
        return "\(name)/\(octave)"
    }

    
    var body: some View {
        GeometryReader { geometry in
            NavigationStack {
                VStack(spacing: 0) {
                    // 顶部工具栏（一直都有侧边栏按钮）
                topToolbar
                
                Divider()
                
                // 主内容区
                if sidebarAsOverlay {
                    // === <950pt：overlay 模式 ===
                    ZStack(alignment: .leading) {
                        mainContent
                            .frame(maxWidth: .infinity)
                        
                        if showSidebar {
                            Color.black.opacity(0.3)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showSidebar = false
                                    }
                                }
                            
                            SidebarView(
                                playlists: $playlists,
                                selectedPlaylistIndex: $selectedPlaylistIndex,
                                selectedSong: $selectedSong,
                                onImportFromFile: { showFilePicker = true },
                                onImportFromLink: { showImportSheet = true },
                                onDeleteSong: { savePlaylists() }
                            )
                            .frame(width: 280)
                            .background(Color(.systemBackground))
                            .transition(.move(edge: .leading))
                            .zIndex(1)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: showSidebar)
                } else {
                    // === ≥950pt：内联模式——与当前完全相同 ===
                    HStack(spacing: 0) {
                        if showSidebar {
                            SidebarView(
                                playlists: $playlists,
                                selectedPlaylistIndex: $selectedPlaylistIndex,
                                selectedSong: $selectedSong,
                                onImportFromFile: { showFilePicker = true },
                                onImportFromLink: { showImportSheet = true },
                                onDeleteSong: { savePlaylists() }
                            )
                            .frame(width: 280)
                            .transition(.move(edge: .leading))
                            
                            Divider()
                        }
                        
                        mainContent
                            .frame(maxWidth: .infinity)
                    }
                    .animation(.easeInOut(duration: 0.2), value: showSidebar)
                    .onChange(of: showSidebar) { _ in
                        if !generatedSolo.isEmpty {
                            soloVersion = UUID()
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            // 设置面板
            .sheet(isPresented: $showSettings) {
                SettingsView(
                    lowNoteMidi: $lowNoteMidi,
                    highNoteMidi: $highNoteMidi
                )
            }
            // 导入乐谱弹窗
            .sheet(isPresented: $showImportSheet) {
                ImportPlaylistView { name, songs in
                    // 去重导入：用 标题+作曲家 判断（不区分大小写、去空格）
                    let existingKeys = Set(playlists[selectedPlaylistIndex].songs.map { dedupKey(for: $0) })
                    let newSongs = songs.filter { !existingKeys.contains(dedupKey(for: $0)) }
                    importSkippedCount = songs.count - newSongs.count
                    
                    if !newSongs.isEmpty {
                        playlists[selectedPlaylistIndex].songs.append(contentsOf: newSongs)
                        savePlaylists()
                        if let firstSong = newSongs.first {
                            selectedSong = firstSong
                        }
                    }
                    
                    importedTotalCount = newSongs.count
                    mixedAlertCount = newSongs.filter { $0.hasMixedTimeSignature }.count
                    
                    // 5 路提示：仅 New>0 + 无混合 + 无跳过 = 不弹窗
                    let hasMixed = mixedAlertCount > 0
                    let hasSkipped = importSkippedCount > 0
                    let hasNew = importedTotalCount > 0
                    showImportResultAlert = hasMixed || hasSkipped || !hasNew
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView {
                    showPaywall = false
                    if let pending = pendingMasterAlgorithm {
                        selectedAlgorithm = pending
                        pendingMasterAlgorithm = nil
                    }
                }
                .environmentObject(iapManager)
            }
            // 系统文件选择器（从文件导入）
            .sheet(isPresented: $showFilePicker) {
                DocumentPickerView { url in
                    showFilePicker = false
                    isLoadingFile = true
                    DispatchQueue.global(qos: .userInitiated).async {
                        let result = Self.importFromFile(url: url)
                        DispatchQueue.main.async {
                            isLoadingFile = false
                            handleImportResult(result)
                        }
                    }
                }
            }
            .alert(NSLocalizedString("Import Complete", comment: ""), isPresented: $showImportResultAlert) {
                Button("OK") {}
            } message: {
                if let fileError = fileImportError {
                    Text(fileError)
                } else if importedTotalCount == 0 {
                    Text(NSLocalizedString("All songs already exist.", comment: ""))
                } else if mixedAlertCount > 0 && importSkippedCount > 0 {
                    Text(String(format: NSLocalizedString(
                        "Successfully imported %d songs, skipped %d duplicates. %d songs with mixed time signatures are partially supported.",
                        comment: ""), importedTotalCount, importSkippedCount, mixedAlertCount))
                } else if mixedAlertCount > 0 {
                    Text(String(format: NSLocalizedString(
                        "Successfully imported %d songs. %d songs with mixed time signatures are partially supported (shown in primary time signature).",
                        comment: ""), importedTotalCount, mixedAlertCount))
                } else {
                    Text(String(format: NSLocalizedString(
                        "Successfully imported %d songs, skipped %d duplicates.",
                        comment: ""), importedTotalCount, importSkippedCount))
                }
            }
        }
        // 启动时默认选中第一首歌
        .onAppear {
            if selectedSong == nil {
                selectedSong = currentPlaylist.songs.first
            }
            if let song = selectedSong {
                tempo = song.tempo
                selectedKey = song.key
                selectedStyle = matchStyleMode(from: song.style)
            }
        }
        .onChange(of: selectedSong) { newSong in
            if let song = newSong {
                tempo = song.tempo
                selectedKey = song.key
                selectedStyle = matchStyleMode(from: song.style)
                
                // 🌟 核心优化：切歌后不再清空白屏，而是极速生成带有和弦标记的“骨架谱”，彻底消除加载焦虑！
                self.hasGeneratedSolo = false
                self.generateEmptyRoadmap()
                
                JazzMidiPlayer.shared.stop()
                playingNoteId = ""
                activeMidiNotes = []
                
                // 🌟 新增2：顺手修复切歌时的 UI 播放按钮状态残留 Bug
                self.isPlaying = false
                self.isPaused = false
            }
        }
        .onChange(of: selectedKey) { newKey in
            if let originalKey = selectedSong?.key, newKey != originalKey {
                // 如果是真实Solo，转调后重新生成；如果只是一张骨架谱，转调后仅仅刷新和弦的骨架
                if hasGeneratedSolo {
                    runJazzGenerationPipeline()
                } else {
                    generateEmptyRoadmap()
                }
            }
        }
        .onChange(of: tempo) { newTempo in
            // 实时调整播放速度（播放中也能调）
            JazzMidiPlayer.shared.setTempo(Double(newTempo))
        }
        .onChange(of: horizontalSizeClass) { newSizeClass in
            if newSizeClass == .compact {
                withAnimation { showSidebar = false }
            }
        }
        .overlay {
            if isLoadingFile {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text(NSLocalizedString("正在导入…", comment: ""))
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    }
            }
        }
        .preference(key: ToolbarSizeKey.self, value: geometry.size)
    }
    .onPreferenceChange(ToolbarSizeKey.self) { size in
        toolbarSize = size
    }
    .onOpenURL { url in handleURLImport(url) }
}

// MARK: - 智能风格嗅探
    private func matchStyleMode(from style: String) -> MixerDisplayMode {
        let lower = style.lowercased()
        if lower.contains("waltz") || lower.contains("3/4") { return .waltz }
        if lower.contains("bossa") { return .bossa }
        if lower.contains("latin") || lower.contains("samba") || lower.contains("rhumba") || lower.contains("mambo") { return .latin }
        if lower.contains("afro") || lower.contains("african") { return .afro }
        if lower.contains("ballad") { return .ballad }
        if lower.contains("blues") || lower.contains("shuffle") { return .blues }
        return .swing
    }
    
    // MARK: - 顶部工具栏
    private var topToolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                // ===== 左栏 280pt =====
                if horizontalSizeClass != .compact {
                HStack(spacing: 12) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSidebar.toggle()
                        }
                    }) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(showSidebar ? .accentColor : .secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    
                    Text(selectedSong?.title ?? NSLocalizedString("未选择歌曲", comment: ""))
                        .font(.system(size: sidebarAsOverlay ? (isVerySmallScreen ? 13 : 14) : 15, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: sidebarAsOverlay ? (isVerySmallScreen ? 120 : 140) : nil, alignment: .leading)
                }
                .padding(.horizontal, 18)
                .frame(width: sidebarAsOverlay ? nil : 280, alignment: .leading)
                }
                
                // ===== 右栏 =====
                HStack(spacing: 12) {
                if selectedSong != nil {
                    // 算法组
                    HStack(spacing: 12) {
                    HStack(spacing: 0) {
                        Button {
                            selectedAlgorithmGroup = .basic
                            selectedAlgorithm = currentAlgorithmList.first!
                        } label: {
                            Text(showCompactLabels ? "B" : ImproAlgorithmGroup.basic.rawValue)
                                .font(.system(size: labelFontSize, weight: .medium))
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selectedAlgorithmGroup == .basic ? Color.accentColor : Color.clear)
                                .foregroundColor(selectedAlgorithmGroup == .basic ? .white : .primary)
                        }
                        Button {
                            selectedAlgorithmGroup = .master
                            if let firstAlgo = currentAlgorithmList.first {
                                selectedAlgorithm = firstAlgo
                            }
                        } label: {
                            Text(showCompactLabels ? "M" : ImproAlgorithmGroup.master.rawValue)
                                .font(.system(size: labelFontSize, weight: .medium))
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selectedAlgorithmGroup == .master ? Color.accentColor : Color.clear)
                                .foregroundColor(selectedAlgorithmGroup == .master ? .white : .primary)
                        }
                    }
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(6)
                    .frame(maxWidth: segmentedControlMaxWidth)
                    .layoutPriority(0)
                    
                    Menu {
                        ForEach(currentAlgorithmList, id: \.self) { algo in
                            Button {
                                if selectedAlgorithmGroup == .master && !iapManager.isPurchased {
                                    pendingMasterAlgorithm = algo
                                    showPaywall = true
                                } else {
                                    selectedAlgorithm = algo
                                }
                            } label: {
                                HStack {
                                    Text(algo.rawValue)
                                    if selectedAlgorithmGroup == .master && !iapManager.isPurchased {
                                        Image(systemName: "lock.fill").font(.caption2)
                                    }
                                    if algo == selectedAlgorithm {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing:4) {
                            Text(selectedAlgorithm.rawValue)
                                .font(.system(size: isVerySmallScreen ? 12 : 13, weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName:"chevron.down")
                                .font(.caption)
                        }
                        .padding(.horizontal,8)
                        .padding(.vertical,6)
                        .frame(width: algorithmLabelWidth)
                        .background(Color.gray.opacity(0.12))
                        .cornerRadius(6)
                    }
                    .layoutPriority(0)
                    }.frame(maxWidth: .infinity)
                    
                    // 调号
                    HStack(spacing: isVerySmallScreen ? 3 : 6) {
                    Menu {
                        Picker(NSLocalizedString("调号", comment: ""), selection: $selectedKey) {
                            Group {
                                Text("C").tag("C")
                                Text("G").tag("G")
                                Text("D").tag("D")
                                Text("A").tag("A")
                                Text("E").tag("E")
                                Text("B").tag("B")
                                Text("F#").tag("F#")
                                Text("C#").tag("C#")
                            }
                            Group {
                                Text("F").tag("F")
                                Text("Bb").tag("Bb")
                                Text("Eb").tag("Eb")
                                Text("Ab").tag("Ab")
                                Text("Db").tag("Db")
                                Text("Gb").tag("Gb")
                                Text("Cb").tag("Cb")
                            }
                        }
                    } label: {
                        VStack(spacing: 0) {
                            Text(selectedKey)
                                .font(.system(size: isVerySmallScreen ? 12 : 13, weight: .medium))
                        }
                        .frame(width: isVerySmallScreen ? 28 : 36)
                    }
                    .buttonStyle(.plain)
                    
                    Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 1, height: 22).padding(.horizontal, 3)
                    
                    // BPM
                    HStack(spacing: 2) {
                        Button { if tempo > 40 { tempo -= 5 } } label: {
                            Image(systemName: "minus")
                                .font(.system(size: isVerySmallScreen ? 12 : 13, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: isVerySmallScreen ? 28 : 32, height: isVerySmallScreen ? 28 : 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        VStack(spacing: 0) {
                            Text("\(tempo)").font(.system(size: isVerySmallScreen ? 12 : 13, weight: .medium))
                        }.frame(width: isVerySmallScreen ? 28 : 36)
                        
                        Button { if tempo < 240 { tempo += 5 } } label: {
                            Image(systemName: "plus")
                                .font(.system(size: isVerySmallScreen ? 12 : 13, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: isVerySmallScreen ? 28 : 32, height: isVerySmallScreen ? 28 : 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 1, height: 22).padding(.horizontal, 3)
                    
                    // 拍号
                    VStack(spacing: 2) {
                        Text(selectedSong?.timeSignature ?? "4/4")
                            .font(.system(size: isVerySmallScreen ? 12 : 13, weight: .medium))
                        if selectedSong?.hasMixedTimeSignature == true {
                            Text("Mixed")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                        }
                    }.frame(width: isVerySmallScreen ? 28 : 36)
                    }
                    .layoutPriority(0.5)
                } else {
                    Spacer()
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            
                
                Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 1, height: 22).padding(.horizontal, 12)
                
                // 播放控制——常驻
                HStack(spacing: 12) {
                    Button(action: {
                        if isPaused {
                            JazzMidiPlayer.shared.resume()
                            isPaused = false
                            isPlaying = true
                        } else {
                            JazzMidiPlayer.shared.onNotePlay = { noteId in
                                DispatchQueue.main.async {
                                    if noteId.isEmpty {
                                        self.playingNoteId = ""
                                        self.isPlaying = false
                                        self.isPaused = false
                                        self.activeMidiNotes = []
                                        return
                                    }
                                    self.playingNoteId = noteId
                                    let parts = noteId.split(separator: "-")
                                    guard parts.count == 3,
                                          let measureIndex = Int(parts[1]),
                                          let noteIndex = Int(parts[2]),
                                          measureIndex < self.generatedSolo.count,
                                          noteIndex < self.generatedSolo[measureIndex].notes.count else { return }
                                    let note = self.generatedSolo[measureIndex].notes[noteIndex]
                                    if !note.isRest, let midi = self.midiNumber(from: note.pitch) {
                                        self.activeMidiNotes = [midi]
                                    } else {
                                        self.activeMidiNotes = []
                                    }
                                }
                            }
                            JazzMidiPlayer.shared.playWithAccompaniment(
                                solo: generatedSolo,
                                bpm: Double(tempo),
                                style: selectedStyle.rawValue,
                                startMeasure: startMeasureIndex
                            )
                            isPlaying = true
                            isPaused = false
                        }
                    }) {
                        Image(systemName: "play.fill")
                            .font(.title3)
                            .foregroundColor(hasGeneratedSolo && !generatedSolo.isEmpty && !(isPlaying && !isPaused) ? .accentColor : .gray)
                    }
                    .buttonStyle(.plain)
                    .disabled(isPlaying && !isPaused || !hasGeneratedSolo || generatedSolo.isEmpty)
                    
                    Button(action: {
                        JazzMidiPlayer.shared.pause()
                        isPaused = true
                        isPlaying = false
                    }) {
                        Image(systemName: "pause.fill")
                            .font(.title3)
                            .foregroundColor(isPlaying && hasGeneratedSolo && !generatedSolo.isEmpty ? .accentColor : .gray)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isPlaying || !hasGeneratedSolo || generatedSolo.isEmpty)
                    
                    Button(action: {
                        JazzMidiPlayer.shared.stop()
                        isPlaying = false
                        isPaused = false
                        playingNoteId = ""
                        startMeasureIndex = 0
                        activeMidiNotes = []
                    }) {
                        Image(systemName: "stop.fill")
                            .font(.title3)
                            .foregroundColor(hasGeneratedSolo && !generatedSolo.isEmpty ? .accentColor : .gray)
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasGeneratedSolo || generatedSolo.isEmpty)
                }

            Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 1, height: 22).padding(.horizontal, 12)
            
            Button(action: {
                if selectedAlgorithmGroup == .master && !iapManager.isPurchased {
                    pendingMasterAlgorithm = selectedAlgorithm
                    showPaywall = true
                    return
                }
                generatedSolo.removeAll()
                JazzMidiPlayer.shared.stop()
                self.playingNoteId = ""
                self.startMeasureIndex = 0
                self.isPlaying = false
                self.isPaused = false
                self.hasGeneratedSolo = true
                self.runJazzGenerationPipeline()
            }) {
                Image(systemName: "wand.and.stars")
                    .font(.title3)
                    .foregroundColor(selectedSong == nil ? .gray : .orange)
            }
            .buttonStyle(.plain)
            .disabled(selectedSong == nil)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .padding(.trailing, 16)
            }
            .padding(.vertical, 8)
            
            Divider()
        }
        .frame(height: 56)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - 五线谱视图
    private var sheetMusicView: some View {
        SheetMusicView(
            solo: generatedSolo,
            playingNoteId: playingNoteId,
            soloVersion: soloVersion,
            key: selectedKey,
            timeSignature: selectedSong?.timeSignature ?? "4/4",
            grammarFileName: selectedAlgorithm.grammarFileName,
            showAnalysis: showAnalysis,
            analysis: currentAnalysis,
            onNoteClick: { noteId in
                // 🌟 核心修复：先解除播放器的回调绑定！
                // 彻底断绝 stop() 异步发出的空字符串清理信号，防止它误伤和覆盖我们刚刚手动点选的高亮 ID！
                JazzMidiPlayer.shared.onNotePlay = nil
                
                self.playingNoteId = noteId
                let parts = noteId.split(separator: "-")
                if parts.count == 3, let mIndex = Int(parts[1]) {
                    self.startMeasureIndex = mIndex
                    // 每次用户手动点选新位置时，重置并停止旧的播放进度
                    JazzMidiPlayer.shared.stop()
                    self.isPlaying = false
                    self.isPaused = false
                    self.activeMidiNotes = []
                }
            }
        )
    }
    
    
    // MARK: - 主内容区
    @ViewBuilder
    private var mainContent: some View {
        ZStack(alignment: .leading) {
            // 主内容
            if let song = selectedSong {
                VStack(spacing: 0) {
                    // 乐谱展示区（🌟 移除外层 SwiftUI ScrollView，让 WebView 接管全面积原生滚动，打通高精度自适应视口）
                    if generatedSolo.isEmpty {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        sheetMusicView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(alignment: .topLeading) {
                                // 级数分析开关（左上角，独立模块，不影响现有布局）
                                if !generatedSolo.isEmpty {
                                    Button(action: {
                                        showAnalysis.toggle()
                                        // 触发 SheetMusicView 重新渲染（JS 端根据 showAnalysis 决定是否画色块/级数）
                                        soloVersion = UUID()
                                    }) {
                                        Image(systemName: showAnalysis ? "number.circle.fill" : "number.circle")
                                            .font(.system(size: 18))
                                            .foregroundColor(showAnalysis ? .accentColor : .gray)
                                            .frame(width: 30, height: 30)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 8)
                                    .padding(.leading, 12)
                                    .help("显示/隐藏级数分析")
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                if !generatedSolo.isEmpty {
                                    NoteColorLegendView()
                                }
                            }
                            .shadow(color: Color.black.opacity(0.08), radius: 5, x: 0, y: 3)
                            .padding(.horizontal, contentHorizontalMargin)
                            .padding(.top, 12)
                    }

                    // 底部：乐队混音总控台
                    BandMixerView(
                        saxVolume: $saxVolume, pianoVolume: $pianoVolume,
                        bassVolume: $bassVolume, drumVolume: $drumVolume,
                        saxMuted: $saxMuted, pianoMuted: $pianoMuted,
                        bassMuted: $bassMuted, drumMuted: $drumMuted,
                        selectedStyle: $selectedStyle,
                        isExpanded: $showMixer,
                        isPlaying: isPlaying
                    )
                    .padding(.horizontal, contentHorizontalMargin)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
                .onChange(of: saxVolume)   { v in JazzMidiPlayer.shared.updateTrackVolume(track: 0, volume: v, isMuted: saxMuted) }
                .onChange(of: pianoVolume) { v in JazzMidiPlayer.shared.updateTrackVolume(track: 1, volume: v, isMuted: pianoMuted) }
                .onChange(of: bassVolume)  { v in JazzMidiPlayer.shared.updateTrackVolume(track: 2, volume: v, isMuted: bassMuted) }
                .onChange(of: drumVolume)  { v in JazzMidiPlayer.shared.updateTrackVolume(track: 3, volume: v, isMuted: drumMuted) }
                .onChange(of: saxMuted)    { m in JazzMidiPlayer.shared.updateTrackVolume(track: 0, volume: saxVolume, isMuted: m) }
                .onChange(of: pianoMuted)  { m in JazzMidiPlayer.shared.updateTrackVolume(track: 1, volume: pianoVolume, isMuted: m) }
                .onChange(of: bassMuted)   { m in JazzMidiPlayer.shared.updateTrackVolume(track: 2, volume: bassVolume, isMuted: m) }
                .onChange(of: drumMuted)   { m in JazzMidiPlayer.shared.updateTrackVolume(track: 3, volume: drumVolume, isMuted: m) }
               // 🌟 新增：监听伴奏风格切换，实现无缝热重载
                .onChange(of: selectedStyle) { newStyle in
                    #if DEBUG
                    print("🔍 [ContentView] 风格切换: \(newStyle.rawValue)")
                    #endif
                    guard hasGeneratedSolo, (isPlaying || isPaused) else { return }
                    
                    var currentMeasure = startMeasureIndex
                    if !playingNoteId.isEmpty {
                        let parts = playingNoteId.split(separator: "-")
                        if parts.count >= 2, let m = Int(parts[1]) {
                            currentMeasure = m
                        }
                    }
                    
                    if isPaused {
                        // 🌟 核心修复：如果是暂停状态，绝不自动发声！
                        // 悄悄停止底层旧引擎，但保留 UI 上的高亮位置
                        JazzMidiPlayer.shared.stop()
                        
                        // 把下次点击播放的起点，对齐到当前暂停的小节
                        self.startMeasureIndex = currentMeasure
                        
                        // 状态重置为“未播放”，等待用户手动点击播放按钮
                        self.isPaused = false
                        self.isPlaying = false
                    } else {
                        // 🌟 如果当前正在热烈播放中，则直接无缝热重载新风格！
                        // 必须使用 tempo，保留用户手动调节的实时速度
                        JazzMidiPlayer.shared.playWithAccompaniment(
                            solo: generatedSolo,
                            bpm: Double(tempo),
                            style: newStyle.rawValue,
                            startMeasure: currentMeasure
                        )
                        self.isPlaying = true
                        self.isPaused = false
                    }
                }
            } else {
                VStack {
                    Spacer()
                    Text(NSLocalizedString("请从左侧选择一首歌曲", comment: ""))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            
            // 侧边栏隐藏时，左侧边缘的呼出按钮（仅 compact 模式显示）
            if !showSidebar && horizontalSizeClass == .compact {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSidebar = true
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 20, height: 60)
                        .background(Color.blue)
                        .cornerRadius(4)
                }
                .padding(.leading, 2)
                .transition(.opacity)
            }
        }
    }
    
    // MARK: - 和弦进行概览
    private func chordOverview(for song: JazzSong) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(song.measures.enumerated()), id: \.offset) { _, measureChords in
                    // 每个小节的和弦用斜杠连起来显示
                    let chordText = measureChords.joined(separator: " / ")
                    Text(chordText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }
            }
        }
    }
    
    // MARK: - 钢琴键盘辅助
    private func midiNumber(from pitch: String) -> Int? {
        // pitch 格式如 "C/4", "F#/4", "Bb/3"
        let cleaned = pitch.replacingOccurrences(of: " 前导", with: "")
        let parts = cleaned.split(separator: "/")
        guard parts.count == 2 else { return nil }
        
        var noteName = String(parts[0]).lowercased()
        let octave = Int(parts[1]) ?? 4
        
        // 统一音名格式
        noteName = noteName.replacingOccurrences(of: "b", with: "b")
        noteName = noteName.replacingOccurrences(of: "#", with: "#")
        
        let noteMap: [String: Int] = [
            "c": 0, "c#": 1, "db": 1,
            "d": 2, "d#": 3, "eb": 3,
            "e": 4,
            "f": 5, "f#": 6, "gb": 6,
            "g": 7, "g#": 8, "ab": 8,
            "a": 9, "a#": 10, "bb": 10,
            "b": 11
        ]
        
        guard let noteValue = noteMap[noteName] else { return nil }
        // MIDI 编号 = (八度 + 1) * 12 + 音名数值
        return (octave + 1) * 12 + noteValue
    }
    
    // MARK: - 播放控制
    private var playbackControls: some View {
        HStack(spacing: 12) {
            Button(action: {
                JazzMidiPlayer.shared.onNotePlay = { noteId in
                    DispatchQueue.main.async {
                        self.playingNoteId = noteId
                        
                        // 解析音符 ID，更新钢琴键盘高亮
                        let parts = noteId.split(separator: "-")
                        guard parts.count == 3,
                              let measureIndex = Int(parts[1]),
                              let noteIndex = Int(parts[2]),
                              measureIndex < self.generatedSolo.count,
                              noteIndex < self.generatedSolo[measureIndex].notes.count else {
                            return
                        }
                        
                        let note = self.generatedSolo[measureIndex].notes[noteIndex]
                        if !note.isRest, let midi = self.midiNumber(from: note.pitch) {
                            self.activeMidiNotes = [midi]
                        } else {
                            self.activeMidiNotes = []
                        }
                    }
                }
                // 换成调用我们即将新增的全乐队播放方法
                JazzMidiPlayer.shared.playWithAccompaniment(solo: generatedSolo, bpm: Double(selectedSong?.tempo ?? 120), style: selectedStyle.rawValue)
            }) {
                Label(NSLocalizedString("播放", comment: ""), systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            
            Button(action: {
                JazzMidiPlayer.shared.stop()
                self.playingNoteId = ""
            }) {
                Label(NSLocalizedString("停止", comment: ""), systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
    }
}

// MARK: - 📋 侧边栏视图
struct SidebarView: View {
    @Binding var playlists: [JazzPlaylist]
    @Binding var selectedPlaylistIndex: Int
    @Binding var selectedSong: JazzSong?
    var onImportFromFile: () -> Void
    var onImportFromLink: () -> Void
    var onDeleteSong: (() -> Void)? = nil
    
    @State private var showImportMenu = false
    @State private var songToDelete: JazzSong? = nil   // 🌟 待删除歌曲
    @State private var showDeleteConfirm = false        // 🌟 删除确认弹窗
    @State private var searchText = ""
    @State private var expandedPlaylists: Set<UUID> = []
    
    var currentPlaylist: JazzPlaylist {
        playlists[selectedPlaylistIndex]
    }
    
    var filteredSongs: [JazzSong] {
        if searchText.isEmpty {
            return currentPlaylist.songs
        } else {
            return currentPlaylist.songs.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.composer.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    /// 删除歌曲：从播放列表移除 → 更新选中状态 → 持久化回调
    private func deleteSong(_ song: JazzSong) {
        let target = playlists[selectedPlaylistIndex]
        guard let index = target.songs.firstIndex(where: { $0.id == song.id }) else { return }

        let wasSelected = (selectedSong?.id == song.id)
        playlists[selectedPlaylistIndex].songs.remove(at: index)

        if wasSelected {
            let remaining = playlists[selectedPlaylistIndex].songs
            if remaining.isEmpty {
                selectedSong = nil
            } else if index < remaining.count {
                selectedSong = remaining[index]
            } else {
                selectedSong = remaining.last
            }
        }

        onDeleteSong?()
    }

    var body: some View {
        VStack(spacing: 0) {

            
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(NSLocalizedString("搜索歌曲", comment: ""), text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
            
            Divider()
            
            // 歌曲列表
            List(filteredSongs, selection: $selectedSong) { song in
                SongRow(song: song, isSelected: selectedSong?.id == song.id)
                    .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSong = song
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            songToDelete = song
                            showDeleteConfirm = true
                        } label: {
                            Label(NSLocalizedString("删除", comment: ""), systemImage: "trash")
                        }
                    }
            }
            .listStyle(.plain)
            .alert(
                NSLocalizedString("删除歌曲", comment: ""),
                isPresented: $showDeleteConfirm,
                presenting: songToDelete
            ) { song in
                Button(NSLocalizedString("取消", comment: ""), role: .cancel) {
                    songToDelete = nil
                }
                Button(NSLocalizedString("删除", comment: ""), role: .destructive) {
                    deleteSong(song)
                    songToDelete = nil
                }
            } message: { song in
                Text(String(format: NSLocalizedString("确定要删除「%@」吗？", comment: ""), song.title))
            }
            
            Divider()
            
            // 底部操作栏
            HStack {
                Button { showImportMenu = true } label: {
                    Label(NSLocalizedString("导入曲谱", comment: ""), systemImage: "square.and.arrow.down")
                        .font(.caption)
                }
                .confirmationDialog(
                    NSLocalizedString("导入曲谱", comment: ""),
                    isPresented: $showImportMenu,
                    titleVisibility: .visible
                ) {
                    Button(NSLocalizedString("从文件导入", comment: "")) { onImportFromFile() }
                    Button(NSLocalizedString("从链接导入", comment: "")) { onImportFromLink() }
                    Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
        .onAppear {
            // 默认展开所有歌单
            for playlist in playlists {
                expandedPlaylists.insert(playlist.id)
            }
        }
    }
}
// MARK: - 歌曲行视图
struct SongRow: View {
    let song: JazzSong
    let isSelected: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(song.title)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .bold : .regular)
                    if song.hasMixedTimeSignature {
                        Text("⚠️")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                if !song.composer.isEmpty {
                    Text("\(song.composer) · \(song.style)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Text("\(song.tempo)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - ⚙️ 设置面板视图
struct SettingsView: View {
    @Binding var lowNoteMidi: Int
    @Binding var highNoteMidi: Int
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Text(NSLocalizedString("算法选择已移动至顶部工具栏", comment: ""))
                    .foregroundColor(.secondary)
                
                Section(NSLocalizedString("音域范围", comment: "")) {
                    VStack(spacing:8) {
                        HStack {
                            Text(NSLocalizedString("最低音 MIDI:", comment: "") + " \(lowNoteMidi)")
                            Spacer()
                            Text(NSLocalizedString("最高音 MIDI:", comment: "") + " \(highNoteMidi)")
                        }
                        PianoRangeView(lowMidi: lowNoteMidi, highMidi: highNoteMidi)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("⚙️ 即兴参数设置", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("完成", comment: "")) {
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}

// MARK: - MIDI 转音名辅助函数
private func midiToNoteName(_ midi: Int) -> String {
    let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    let octave = (midi / 12) - 1
    let noteIndex = midi % 12
    return "\(noteNames[noteIndex])\(octave)"
}

// MARK: - 🎹 钢琴音域可视化组件
struct PianoRangeView: View {
    let lowMidi: Int
    let highMidi: Int
    
    // 显示的键盘范围（C2 到 C7，共 5 个八度）
    private let displayStart = 36  // C2
    private let displayEnd = 84    // C6
    
    var body: some View {
        GeometryReader { geometry in
            let whiteKeyCount = numberOfWhiteKeys(from: displayStart, to: displayEnd)
            let whiteKeyWidth = geometry.size.width / CGFloat(whiteKeyCount)
            let whiteKeyHeight = geometry.size.height
            
            ZStack(alignment: .topLeading) {
                // 白键
                HStack(spacing: 1) {
                    ForEach(displayStart...displayEnd, id: \.self) { midi in
                        if isWhiteKey(midi) {
                            let isInRange = midi >= lowMidi && midi <= highMidi
                            Rectangle()
                                .fill(isInRange ? Color.blue.opacity(0.3) : Color.white)
                                .border(Color.gray.opacity(0.3), width: 0.5)
                        }
                    }
                }
                
                // 黑键（覆盖在白键上面）
                HStack(spacing: 0) {
                    ForEach(displayStart...displayEnd, id: \.self) { midi in
                        if !isWhiteKey(midi) {
                            let isInRange = midi >= lowMidi && midi <= highMidi
                            let blackKeyWidth = whiteKeyWidth * 0.6
                            let blackKeyHeight = whiteKeyHeight * 0.6
                            
                            Rectangle()
                                .fill(isInRange ? Color.blue.opacity(0.7) : Color.black)
                                .frame(width: blackKeyWidth, height: blackKeyHeight)
                                .offset(x: -blackKeyWidth / 2)
                        } else {
                            Spacer()
                                .frame(width: whiteKeyWidth - 1)
                        }
                    }
                }
            }
        }
        .background(Color.gray.opacity(0.1))
        .cornerRadius(4)
    }
    
    // 判断是否是白键
    private func isWhiteKey(_ midi: Int) -> Bool {
        let note = midi % 12
        return [0, 2, 4, 5, 7, 9, 11].contains(note)
    }
    
    // 计算白键数量
    private func numberOfWhiteKeys(from: Int, to: Int) -> Int {
        var count = 0
        for midi in from...to {
            if isWhiteKey(midi) {
                count += 1
            }
        }
        return count
    }
}
// MARK: - 📥 导入弹窗视图（侦探版）
struct ImportPlaylistView: View {
    @Environment(\.dismiss) var dismiss
    @State private var clipboardInfo: String = NSLocalizedString("点下方按钮检测剪贴板", comment: "")
    @State private var isDetecting = false
    @State private var parsedSongs: [JazzSong] = []
    @State private var playlistName = NSLocalizedString("导入的歌单", comment: "")
    @State private var errorMessage = ""
    
    var onImport: (String, [JazzSong]) -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 加载中
                    if isDetecting {
                        ProgressView(NSLocalizedString("正在检测剪贴板...", comment: ""))
                            .padding(.top, 40)
                    }
                    
                    // 错误提示
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                            .padding(.top, 20)
                    }
                    
                    // 未检测到歌曲
                    if !isDetecting && parsedSongs.isEmpty && errorMessage.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                            Text(NSLocalizedString("剪贴板中没有找到 iReal Pro 乐谱", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(NSLocalizedString("请先在 iReal Pro 中复制乐谱，再回到这里", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 40)
                    }
                    
                    // 解析结果
                    if !parsedSongs.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(NSLocalizedString("✅ 解析成功", comment: ""))
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                                Spacer()
                                Text("\(parsedSongs.count) \(NSLocalizedString("首歌", comment: ""))")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                            }
                            
                            TextField(NSLocalizedString("歌单名称", comment: ""), text: $playlistName)
                                .textFieldStyle(.roundedBorder)
                            
                            VStack(spacing: 0) {
                                ForEach(parsedSongs.prefix(5), id: \.id) { song in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(song.title)
                                            .font(.subheadline)
                                        Text("\(song.composer) · \(song.measures.count) \(NSLocalizedString("小节", comment: ""))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal)
                                    
                                    Divider().padding(.leading)
                                }
                            }
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                        .padding(.horizontal)
                        
                        Button(action: {
                            onImport(playlistName, parsedSongs)
                            dismiss()
                        }) {
                            HStack {
                                Spacer()
                                Text(NSLocalizedString("确认导入", comment: ""))
                                    .fontWeight(.bold)
                                Spacer()
                            }
                            .padding(.vertical, 14)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                }
                .padding(.top, 20)
            }
            .background(Color(.systemBackground))
            .navigationTitle(NSLocalizedString("导入乐谱", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                detectClipboard()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("取消", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func detectClipboard() {
        isDetecting = true
        errorMessage = ""
        parsedSongs = []
        
        let pasteboard = UIPasteboard.general
        var infoLines: [String] = []
        
        // 1. 基本信息
        infoLines.append("📋 剪贴板项目数：\(pasteboard.items.count)")
        infoLines.append("")
        
        // 2. 遍历所有项目
        for (index, item) in pasteboard.items.enumerated() {
            infoLines.append("--- 项目 \(index + 1) ---")
            
            let typeNames = item.keys.map { String($0) }
            infoLines.append("类型列表：\(typeNames.joined(separator: ", "))")
            infoLines.append("")
            
            // 3. 尝试读取各种常见格式
            // 尝试纯文本
            if let text = pasteboard.string {
                infoLines.append("📝 纯文本：\(text.prefix(100))")
                infoLines.append("   总长度：\(text.count)")
                infoLines.append("")
                
                // 如果看起来像 iReal Pro 链接，直接尝试解析
                if text.hasPrefix("irealb://") || text.hasPrefix("irealbook://") {
                    infoLines.append("✅ 检测到 iReal Pro 链接，尝试解析...")
                    tryParse(text)
                }
            }
            
            // 尝试 URL
            if let url = pasteboard.url {
                infoLines.append("🔗 URL：\(url.absoluteString)")
                infoLines.append("")
                
                if url.absoluteString.hasPrefix("irealb://") || url.absoluteString.hasPrefix("irealbook://") {
                    infoLines.append("✅ 检测到 iReal Pro URL，尝试解析...")
                    tryParse(url.absoluteString)
                }
            }
            
            // 4. 遍历所有类型，看看能不能读出字符串
            for typeName in typeNames {
                if let value = pasteboard.value(forPasteboardType: typeName) {
                    infoLines.append("📦 类型 [\(typeName)]：\(Swift.type(of: value))")
                    
                    // 如果是 Data，试试转成字符串
                    if let data = value as? Data {
                        if let str = String(data: data, encoding: .utf8) {
                            infoLines.append("   转 UTF8 字符串：\(str.prefix(80))")
                            
                            if str.hasPrefix("irealb://") || str.hasPrefix("irealbook://") {
                                infoLines.append("   ✅ 这是 iReal Pro 链接！")
                                tryParse(str)
                            }
                        } else {
                            infoLines.append("   数据长度：\(data.count) 字节")
                        }
                    }
                    // 如果是字符串，直接显示
                    else if let str = value as? String {
                        infoLines.append("   内容：\(str.prefix(80))")
                    }
                }
            }
            
            infoLines.append("")
        }
        
        clipboardInfo = infoLines.joined(separator: "\n")
        isDetecting = false
    }
    
    private func tryParse(_ urlString: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let parsed = IRealProParser.parsePlaylist(url: urlString)
            
            DispatchQueue.main.async {
                if !parsed.isEmpty {
                    parsedSongs = parsed.map { IRealProParser.toJazzSong($0) }
                    if parsedSongs.count == 1 {
                        playlistName = parsedSongs[0].title
                    }
                    clipboardInfo += "\n🎉 解析成功！找到 \(parsed.count) 首歌"
                } else {
                    clipboardInfo += "\n❌ 解析失败，没有找到歌曲"
                }
            }
        }
    }
}
// MARK: - 🎹 钢琴键盘视图（支持音域范围拖动调整）
struct PianoKeyboardView: View {
    let activeNotes: Set<Int>          // 当前高亮的 MIDI 音符编号
    @Binding var lowNoteMidi: Int      // 音域下限（可拖动调整）
    @Binding var highNoteMidi: Int     // 音域上限（可拖动调整）
    
    // 88键钢琴范围：A0 (MIDI 21) 到 C8 (MIDI 108)
    private let startMidi = 21
    private let endMidi = 108
    
    // 最小音域间距（1个八度 = 12个半音）
    private let minRange = 12
    
    // 拖动状态
    @State private var isDragging = false
    @State private var draggingEdge: DraggingEdge? = nil
    
    private enum DraggingEdge {
        case low
        case high
    }
    
    var body: some View {
        GeometryReader { geometry in
            let totalWhiteKeys = whiteKeyMidis.count
            let whiteKeyWidth = geometry.size.width / CGFloat(totalWhiteKeys)
            let blackKeyWidth = whiteKeyWidth * 0.62
            let blackKeyHeight = geometry.size.height * 0.62
            
            ZStack(alignment: .topLeading) {
                // 白键层
                HStack(spacing: 0) {
                    ForEach(whiteKeyMidis, id: \.self) { midi in
                        // 修改ZStack内布局，把C音标记从顶部改到底部、红条上方
                        ZStack(alignment: .bottom) {
                            Rectangle()
                                .fill(whiteKeyColor(for: midi))
                            Rectangle()
                                .stroke(Color.gray.opacity(0.4), lineWidth: 0.5)
                            
                            // C音音高标记：放在底部红条上方，避开黑键遮挡
                            if midi % 12 == 0 {
                                VStack(spacing: 2) {
                                    Spacer()
                                    Text(midiToNoteName(midi))
                                        .font(.system(size: 9, weight: midi == 60 ? .bold : .regular))
                                        .foregroundColor(midi == 60 ? .orange : .gray)
                                }
                                .padding(.bottom, 14) // 给下方红条留出空间
                            }
                            
                            // 端点红色标记条（最底部）
                            if midi == lowNoteMidi || midi == highNoteMidi {
                                Rectangle()
                                    .fill(Color.red)
                                    .frame(height: 10)
                                    .padding(.bottom, 2)
                            }
                        }
                        .frame(width: whiteKeyWidth, height: geometry.size.height)
                    }
                }
                
                // 音域范围半透明填充层
                rangeFillView(whiteKeyWidth: whiteKeyWidth, height: geometry.size.height)
                
                // 黑键层
                ForEach(blackKeyMidis, id: \.self) { midi in
                    let whiteKeysBefore = numberOfWhiteKeys(from: startMidi, to: midi - 1)
                    let xPosition = CGFloat(whiteKeysBefore) * whiteKeyWidth - blackKeyWidth / 2
                    
                    ZStack(alignment: .bottom) {
                        Rectangle()
                            .fill(blackKeyColor(for: midi))
                        
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                        
                        // 黑键上的端点标记
                        if midi == lowNoteMidi || midi == highNoteMidi {
                            Rectangle()
                                .fill(Color.red)
                                .frame(height: 8)
                                .padding(.bottom, 2)
                        }
                    }
                    .frame(width: blackKeyWidth, height: blackKeyHeight)
                    .offset(x: xPosition)
                }
                
                // 拖动时的浮动音高标签
                if isDragging, let edge = draggingEdge {
                    let labelMidi = edge == .low ? lowNoteMidi : highNoteMidi
                    let centerX = xCenterFor(midi: labelMidi, whiteKeyWidth: whiteKeyWidth)
                    
                    VStack(spacing: 2) {
                        Text(midiToNoteName(labelMidi))
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.red)
                            .cornerRadius(8)
                        
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }
                    .offset(x: centerX - 25, y: -38)
                    .animation(.interactiveSpring(response: 0.15), value: centerX)
                }
                
                // 手势识别层（长按 + 拖动）
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        LongPressGesture(minimumDuration: 0.25)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onChanged { value in
                                switch value {
                                case .first(true):
                                    break  // 长按触发中
                                case .second(true, let drag):
                                    if let drag = drag {
                                        handleDragChange(
                                            value: drag,
                                            whiteKeyWidth: whiteKeyWidth
                                        )
                                    }
                                default:
                                    break
                                }
                            }
                            .onEnded { _ in
                                handleDragEnd()
                            }
                    )
            }
        }
        .frame(height: 100)
        .background(Color(.systemGray4))
        .cornerRadius(4)
    }
    
    // MARK: - 音域范围填充视图
    private func rangeFillView(whiteKeyWidth: CGFloat, height: CGFloat) -> some View {
        let startX = xStartFor(midi: lowNoteMidi, whiteKeyWidth: whiteKeyWidth)
        let endX = xEndFor(midi: highNoteMidi, whiteKeyWidth: whiteKeyWidth)
        
        return Rectangle()
            .fill(Color.red.opacity(0.12))
            .frame(width: endX - startX, height: height)
            .offset(x: startX)
    }
    
    // MARK: - 颜色计算
    private func whiteKeyColor(for midi: Int) -> Color {
        if activeNotes.contains(midi) {
            return Color(red: 0.2, green: 0.6, blue: 1.0)
        }
        if midi == 60 { // 中央C 特殊标记色（淡橙）
            return Color.orange.opacity(0.15)
        }
        return .white
    }
    
    private func blackKeyColor(for midi: Int) -> Color {
        if activeNotes.contains(midi) {
            return Color(red: 0.2, green: 0.6, blue: 1.0)
        }
        return .black
    }
    
    // MARK: - 手势处理
    private func handleDragChange(value: DragGesture.Value, whiteKeyWidth: CGFloat) {
        let location = value.location
        
        // 首次进入拖动：确定拖动的是哪一端
        if !isDragging {
            let lowCenter = xCenterFor(midi: lowNoteMidi, whiteKeyWidth: whiteKeyWidth)
            let highCenter = xCenterFor(midi: highNoteMidi, whiteKeyWidth: whiteKeyWidth)
            
            let distanceToLow = abs(location.x - lowCenter)
            let distanceToHigh = abs(location.x - highCenter)
            
            // 判定阈值：2个白键宽度内才算点中端点
            let threshold = whiteKeyWidth * 2.0
            
            if distanceToLow < threshold && distanceToLow <= distanceToHigh {
                draggingEdge = .low
                isDragging = true
                triggerImpactHaptic(.medium)
            } else if distanceToHigh < threshold {
                draggingEdge = .high
                isDragging = true
                triggerImpactHaptic(.medium)
            } else {
                // 长按位置不在端点附近，不进入拖动
                return
            }
        }
        
        // 拖动中：更新音高
        guard isDragging, let edge = draggingEdge else { return }
        
        let touchedMidi = midiAt(x: location.x, whiteKeyWidth: whiteKeyWidth)
        let clampedMidi = max(startMidi, min(endMidi, touchedMidi))
        
        if edge == .low {
            // 最低音不能超过最高音减最小间距
            let newLow = min(clampedMidi, highNoteMidi - minRange)
            if newLow != lowNoteMidi {
                lowNoteMidi = newLow
                triggerSelectionHaptic()
            }
        } else {
            // 最高音不能低于最低音加最小间距
            let newHigh = max(clampedMidi, lowNoteMidi + minRange)
            if newHigh != highNoteMidi {
                highNoteMidi = newHigh
                triggerSelectionHaptic()
            }
        }
    }
    
    private func handleDragEnd() {
        if isDragging {
            triggerImpactHaptic(.light)
        }
        isDragging = false
        draggingEdge = nil
    }
    
    // MARK: - 触觉反馈
    private func triggerImpactHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
    
    private func triggerSelectionHaptic() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
    
    // MARK: - 位置计算
    private func xStartFor(midi: Int, whiteKeyWidth: CGFloat) -> CGFloat {
        if isWhiteKey(midi) {
            let whiteKeysBefore = numberOfWhiteKeys(from: startMidi, to: midi - 1)
            return CGFloat(whiteKeysBefore) * whiteKeyWidth
        } else {
            // 黑键：起始位置为前一个白键的起始加上偏移
            let whiteKeysBefore = numberOfWhiteKeys(from: startMidi, to: midi - 1)
            let blackKeyWidth = whiteKeyWidth * 0.62
            return CGFloat(whiteKeysBefore) * whiteKeyWidth - blackKeyWidth / 2
        }
    }
    
    private func xEndFor(midi: Int, whiteKeyWidth: CGFloat) -> CGFloat {
        if isWhiteKey(midi) {
            let whiteKeysBefore = numberOfWhiteKeys(from: startMidi, to: midi)
            return CGFloat(whiteKeysBefore) * whiteKeyWidth
        } else {
            let whiteKeysBefore = numberOfWhiteKeys(from: startMidi, to: midi - 1)
            let blackKeyWidth = whiteKeyWidth * 0.62
            return CGFloat(whiteKeysBefore) * whiteKeyWidth + blackKeyWidth / 2
        }
    }
    
    private func xCenterFor(midi: Int, whiteKeyWidth: CGFloat) -> CGFloat {
        (xStartFor(midi: midi, whiteKeyWidth: whiteKeyWidth) +
         xEndFor(midi: midi, whiteKeyWidth: whiteKeyWidth)) / 2
    }
    
    /// 根据 x 坐标计算对应的 MIDI 音高（支持黑白键）
    private func midiAt(x: CGFloat, whiteKeyWidth: CGFloat) -> Int {
        let whiteKeys = whiteKeyMidis
        let whiteKeyIndex = Int(x / whiteKeyWidth)
        
        guard whiteKeyIndex >= 0 else { return startMidi }
        guard whiteKeyIndex < whiteKeys.count else { return endMidi }
        
        let whiteMidi = whiteKeys[whiteKeyIndex]
        let offsetInWhiteKey = x - CGFloat(whiteKeyIndex) * whiteKeyWidth
        let blackKeyWidth = whiteKeyWidth * 0.62
        
        // 检查左侧黑键区域
        if offsetInWhiteKey < blackKeyWidth / 2 && whiteKeyIndex > 0 {
            let prevWhiteMidi = whiteKeys[whiteKeyIndex - 1]
            // 如果两个白键相差2个半音（全音），中间有黑键
            if whiteMidi - prevWhiteMidi == 2 {
                return prevWhiteMidi + 1
            }
        }
        
        // 检查右侧黑键区域
        if offsetInWhiteKey > whiteKeyWidth - blackKeyWidth / 2 && whiteKeyIndex < whiteKeys.count - 1 {
            let nextWhiteMidi = whiteKeys[whiteKeyIndex + 1]
            if nextWhiteMidi - whiteMidi == 2 {
                return whiteMidi + 1
            }
        }
        
        return whiteMidi
    }
    
    // MARK: - 辅助函数
    private var whiteKeyMidis: [Int] {
        (startMidi...endMidi).filter { isWhiteKey($0) }
    }
    
    private var blackKeyMidis: [Int] {
        (startMidi...endMidi).filter { !isWhiteKey($0) }
    }
    
    private func isWhiteKey(_ midi: Int) -> Bool {
        let note = midi % 12
        return [0, 2, 4, 5, 7, 9, 11].contains(note)
    }
    
    private func numberOfWhiteKeys(from start: Int, to end: Int) -> Int {
        var count = 0
        for midi in start...end {
            if isWhiteKey(midi) {
                count += 1
            }
        }
        return count
    }
}
// MARK: - 转调辅助函数
private extension ContentView {
    
    /// 判断是否为升号调（决定和弦根音用升号还是降号拼写）
    static func isSharpKey(_ key: String) -> Bool {
        let flatKeys: Set<String> = [
            "F", "Bb", "Eb", "Ab", "Db", "Gb", "Cb",
            "Fm", "Bbm", "Ebm", "Abm", "Dbm", "Gbm", "Cbm"
        ]
        return !flatKeys.contains(key)
    }
    
    /// 调名 → pitch class（0=C, 1=C#/Db ... 11=B）
    static func keyToPitchClass(_ key: String) -> Int? {
        let rootName: String
        if key.hasSuffix("m") {
            rootName = String(key.dropLast())
        } else {
            rootName = key
        }
        
        let keyMap: [String: Int] = [
            "C": 0, "C#": 1, "Db": 1,
            "D": 2, "D#": 3, "Eb": 3,
            "E": 4,
            "F": 5, "F#": 6, "Gb": 6,
            "G": 7, "G#": 8, "Ab": 8,
            "A": 9, "A#": 10, "Bb": 10,
            "B": 11
        ]
        
        return keyMap[rootName]
    }
    
    /// 计算两个调之间的半音差（正数=升高，负数=降低，取最短路径）
    static func semitoneDifference(from fromKey: String, to toKey: String) -> Int {
        guard let fromPC = keyToPitchClass(fromKey),
              let toPC = keyToPitchClass(toKey) else {
            return 0
        }
        var diff = toPC - fromPC
        if diff > 6 { diff -= 12 }
        if diff < -6 { diff += 12 }
        return diff
    }
    
    /// 拆分和弦名 → (根音, 后缀)，例如 "F#m7b5" → ("F#", "m7b5")
    static func splitChord(_ chord: String) -> (root: String, suffix: String)? {
        let trimmed = chord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        var rootEndIndex = trimmed.index(after: trimmed.startIndex)
        
        // 第二个字符如果是 # 或 b，说明根音带升降号
        if trimmed.count > 1 {
            let secondChar = trimmed[trimmed.index(after: trimmed.startIndex)]
            if secondChar == "#" || secondChar == "b" {
                rootEndIndex = trimmed.index(trimmed.startIndex, offsetBy: 2)
            }
        }
        
        let root = String(trimmed[..<rootEndIndex])
        let suffix = String(trimmed[rootEndIndex...])
        return (root, suffix)
    }
    
    /// 转调单个根音（根据目标调决定用升号还是降号）
    static func transposeRoot(_ root: String, by semitones: Int, preferSharps: Bool) -> String {
        let rootMap: [String: Int] = [
            "C": 0, "C#": 1, "Db": 1,
            "D": 2, "D#": 3, "Eb": 3,
            "E": 4,
            "F": 5, "F#": 6, "Gb": 6,
            "G": 7, "G#": 8, "Ab": 8,
            "A": 9, "A#": 10, "Bb": 10,
            "B": 11
        ]
        
        guard let pc = rootMap[root] else { return root }
        
        let newPC = (pc + semitones + 12) % 12
        
        let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let flatNames  = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
        
        return preferSharps ? sharpNames[newPC] : flatNames[newPC]
    }
    
    /// 转调单个和弦（根音移动，后缀不变）
    static func transposeChord(_ chord: String, by semitones: Int, preferSharps: Bool) -> String {
        guard let (root, suffix) = splitChord(chord) else { return chord }
        let newRoot = transposeRoot(root, by: semitones, preferSharps: preferSharps)
        return newRoot + suffix
    }
    
    /// 转调整首歌曲（所有和弦 + 调号，时值不变）
    static func transposeSong(_ song: JazzSong, to newKey: String) -> JazzSong {
        let semitones = semitoneDifference(from: song.key, to: newKey)
        let preferSharps = isSharpKey(newKey)
        
        let transposedMeasures = song.measures.map { measure in
            measure.map { chord in
                transposeChord(chord, by: semitones, preferSharps: preferSharps)
            }
        }
        
        return JazzSong(
            title: song.title,
            composer: song.composer,
            style: song.style,
            tempo: song.tempo,
            key: newKey,
            measures: transposedMeasures,
            measureDurations: song.measureDurations
        )
    }
}
// MARK: - 辅助：根据小节内和弦数量自动分配每个和弦的拍数（4/4拍）
/// 前短后长原则：前面的和弦变化快（时值短），后面的和弦稳定（时值长）
private func vexFlowTicks(for encodedDuration: String) -> Double {
    let parts = encodedDuration.components(separatedBy: "_t")
    // 1. 先剥离休止符标记
    let durWithDot = parts[0].replacingOccurrences(of: "r", with: "")
    // 2. 🌟 关键修复：剥离附点标记字母 'd'，获取纯净的基础时值用来做 switch 匹配
    let baseDur = durWithDot.replacingOccurrences(of: "d", with: "")
    let tupletVal = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
    
    var baseTicks: Double = 4096
    // 3. 使用纯净的 baseDur 匹配，这样 "8d" 就能正确匹配到 "8" 了
    switch baseDur {
    case "w":  baseTicks = 4096
    case "h":  baseTicks = 2048
    case "q":  baseTicks = 1024
    case "8":  baseTicks = 512
    case "16": baseTicks = 256
    case "32": baseTicks = 128
    case "64": baseTicks = 64
    case "128":baseTicks = 32
    default:   baseTicks = 1024
    }
    
    // 4. 判断原始字符串是否包含附点
    if durWithDot.contains("d") { baseTicks *= 1.5 }
    
    // 5. 连音缩放
    if tupletVal == 3 { baseTicks *= 2.0/3.0 }
    else if tupletVal == 5 { baseTicks *= 4.0/5.0 }
    else if tupletVal == 7 { baseTicks *= 4.0/7.0 }
    
    return baseTicks
}

private extension ContentView {
    // MARK: - terminalType → MusicTheoryTag 映射 (GrammarNoteConverter 透传链路)
    func tagFromTerminalType(_ raw: String?) -> MusicTheoryTag {
        guard let raw = raw else { return .colorTone }
        switch raw {
        case "C":                    return .chordTone
        case "A":                    return .approachNote
        case "L", "S", "H":          return .colorTone
        case "X", "Y":               return .foreignTone
        default:                     return .colorTone
        }
    }
    
    // MARK: - 乐理标签检测: 根据MIDI音高和和弦名判断音符类型
    func detectMusicTheoryTag(midiPitch: Int, chordName: String) -> MusicTheoryTag {
    guard !chordName.isEmpty, midiPitch >= 0 else { return .chordTone }
    let quality = ChordQuality(chordName: chordName)
    let rpc = chordRootPC(chordName)
    let pc = ((midiPitch % 12) + 12) % 12
    
    // 和弦音: root, 3rd, 5th, 7th (含alt如 b5, #5)
    let chordPCs = Set(quality.chordIntervals.map { ($0 + rpc) % 12 })
    if chordPCs.contains(pc) { return .chordTone }
    let colorPCs = Set(quality.colorIntervals(for: chordName).map { ($0 + rpc) % 12 })
    if colorPCs.contains(pc) { return .colorTone }
    // 非和弦/色彩音不做事后推断 — 趋近音由 Grammar 终端类型唯一决定
    return .foreignTone
}

/// 验证趋近音与目标音是否构成级进关系（半音或全音）
func isStepwiseApproach(_ appPitch: Int, _ targetPitch: Int) -> Bool {
    guard appPitch >= 0, targetPitch >= 0 else { return false }
    return abs(appPitch - targetPitch) <= 2
}

/// 解析和弦根音的pitch class
    func chordRootPC(_ name: String) -> Int {
    let normalized = name
        .replacingOccurrences(of: "♭", with: "b")
        .replacingOccurrences(of: "♯", with: "#")
    let c = Array(normalized); guard !c.isEmpty else { return 0 }
    var s = String(c[0]).uppercased()
    if c.count > 1, c[1] == "#" || c[1] == "b" { s.append(c[1]) }
    let m: [String:Int] = ["C":0,"C#":1,"Db":1,"D":2,"Eb":3,"E":4,"F":5,"F#":6,"G":7,"Ab":8,"A":9,"Bb":10,"B":11]
    return m[s] ?? 0
    }
}

// MARK: - 🌟 倚音预处理专属数据结构
struct EnrichedNote {
    var midiPitch: Int
    var durationSlots: Int
    var isRest: Bool { midiPitch < 0 }
    var gracePitches: [Int]
    var isTieStart: Bool = false // 🌟 新增：网格量化后生成的延音线起点
    var isTieEnd: Bool = false   // 🌟 新增：网格量化后生成的延音线终点
    var terminalType: String? = nil  // 透传自 PhysicalNote，供符头分色
}

// MARK: - 🌟 网格量化与强拍切割引擎 (Grid Quantizer)
struct GridQuantizer {
    static let standardSlots = [480, 360, 240, 180, 120, 90, 60, 30]
    static let tupletSlots = [320, 160, 96, 80, 72, 48, 40]
    
    /// 量化后兜底：合并在强拍切割中被打散的相邻同音碎片
    static func mergeAdjacentEnriched(_ notes: [EnrichedNote]) -> [EnrichedNote] {
        guard notes.count > 1 else { return notes }
        var result: [EnrichedNote] = []
        for note in notes {
            guard let last = result.last,
                  last.midiPitch == note.midiPitch,
                  last.midiPitch >= 0 else {
                result.append(note); continue
            }

            if last.durationSlots == note.durationSlots {
                // 等长 → 合并
                let merged = EnrichedNote(
                    midiPitch:     last.midiPitch,
                    durationSlots: last.durationSlots + note.durationSlots,
                    gracePitches:  last.gracePitches + note.gracePitches,
                    isTieStart:    last.isTieStart || note.isTieStart,
                    isTieEnd:      last.isTieEnd   || note.isTieEnd,
                    terminalType:  note.terminalType ?? last.terminalType
                )
                result[result.count - 1] = merged
            } else {
                // 不等长 → 标记延音线
                result[result.count - 1].isTieStart = true
                var tiedNote = note
                tiedNote.isTieEnd = true
                result.append(tiedNote)
            }
        }
        return result
    }
    
    // MARK: - 跨拍附点音符拆分——确保乐谱规范性
    static func splitCrossBeatDots(_ notes: [EnrichedNote], beatSize: Int) -> [EnrichedNote] {
        var output: [EnrichedNote] = []
        var pos = 0
        
        for note in notes {
            let dur = note.durationSlots
            let offset = pos % beatSize
            let startsOnBeat = offset == 0
            let crossesBeat = offset + dur > beatSize
            let shouldSplit = !startsOnBeat && crossesBeat
            
            if !shouldSplit {
                output.append(note)
                pos += dur
                continue
            }
            
            let origStart = note.isTieStart
            let origEnd = note.isTieEnd
            let isRest = note.midiPitch < 0
            var remaining = dur
            var fragOffset = offset
            var fragments: [(dur: Int, tieStart: Bool, tieEnd: Bool)] = []
            
            while remaining > 0 {
                let chunk = beatSize - fragOffset
                if remaining <= chunk {
                    fragments.append((remaining, false, false))
                    remaining = 0
                } else {
                    fragments.append((chunk, false, false))
                    remaining -= chunk
                    fragOffset = 0
                }
            }
            
            let fst = 0, lst = fragments.count - 1
            fragments[fst].tieEnd   = isRest ? false : origEnd
            fragments[fst].tieStart = isRest ? false : true
            fragments[lst].tieEnd   = isRest ? false : true
            fragments[lst].tieStart = isRest ? false : origStart
            if lst > 1 {
                for i in 1..<lst {
                    fragments[i].tieEnd   = isRest ? false : true
                    fragments[i].tieStart = isRest ? false : true
                }
            }
            
            for (i, f) in fragments.enumerated() {
                output.append(EnrichedNote(
                    midiPitch: note.midiPitch,
                    durationSlots: f.dur,
                    gracePitches: i == 0 ? note.gracePitches : [],
                    isTieStart: f.tieStart,
                    isTieEnd: f.tieEnd,
                    terminalType: note.terminalType
                ))
            }
            
            pos += dur
        }
        
        return output
    }

    // ============================================================
    // ⚠️ 调试探针：TIE BUG 追踪（保留备用）
    // 作用：检测到跨小节 tie 异常时，打印详细的步骤日志，方便调试
    // 状态：正常情况下完全不执行，不影响性能
    // 触发条件：hasPendingTie=true 且 第一个音符是休止符（极低概率 < 5%）
    // 注意：这是调试用的临时代码，不是业务逻辑
    // ============================================================
    static func quantize(notes: [EnrichedNote], profile: MetreProfile, hasPendingTie: Bool = false) -> [EnrichedNote] {
        // hasPendingTie：调试用，标记上一小节是否有未完成的跨小节 tie，用于触发调试日志
        let debugMode = hasPendingTie && (notes.first?.isRest ?? false)
        if debugMode {
            #if DEBUG
            print("⚠️ [TIE BUG 追踪] 小节 ?? - 步骤 0：原始输入")
            #endif
            for (ni, nn) in notes.enumerated() {
                #if DEBUG
                print("  音符 \(ni): pitch=\(nn.midiPitch), dur=\(nn.durationSlots), isTieStart=\(nn.isTieStart), isTieEnd=\(nn.isTieEnd)")
                #endif
            }
        }
        var snappedNotes: [(pitch: Int, start: Int, end: Int, graces: [Int], origTieStart: Bool, origTieEnd: Bool, terminalType: String?)] = []
        var currentAbs = 0
        
        // 1. 绝对时间轴映射与 30 网格铁腕吸附
        for note in notes {
            let rawStart = currentAbs
            let rawEnd = currentAbs + note.durationSlots
            currentAbs = rawEnd
            
            let isTuplet = tupletSlots.contains(note.durationSlots)
            
            let snapStart = isTuplet ? rawStart : Int(round(Double(rawStart) / 30.0)) * 30
            var snapEnd = isTuplet ? rawEnd : Int(round(Double(rawEnd) / 30.0)) * 30
            
            if !isTuplet && snapEnd <= snapStart { snapEnd = snapStart + 30 }
            
            let finalStart = max(0, min(profile.slotsPerMeasure, snapStart))
            let finalEnd = max(0, min(profile.slotsPerMeasure, snapEnd))
            
            if finalEnd > finalStart {
                snappedNotes.append((note.midiPitch, finalStart, finalEnd, note.gracePitches, note.isTieStart, note.isTieEnd, note.terminalType))
            }
        }
        // 调试：步骤 1 - 30 网格吸附后
        if debugMode {
            #if DEBUG
            print("⚠️ [TIE BUG 追踪] 小节 ?? - 步骤 1：30 网格吸附后")
            #endif
            for (si, sn) in snappedNotes.enumerated() {
                #if DEBUG
                print("  音符 \(si): pitch=\(sn.pitch), dur=\(sn.end - sn.start), isTieStart=\(sn.origTieStart), isTieEnd=\(sn.origTieEnd)")
                #endif
            }
        }
        
        // 2. 🌟 终极改良：缝隙吸收 (Gap Absorption)
        var filledNotes: [(pitch: Int, start: Int, end: Int, graces: [Int], origTieStart: Bool, origTieEnd: Bool, terminalType: String?)] = []
        var pointer = 0
        
        for sn in snappedNotes {
            var currentStart = sn.start
            
            if currentStart > pointer {
                let gap = currentStart - pointer
                if standardSlots.contains(gap) || tupletSlots.contains(gap) {
                    filledNotes.append((-1, pointer, currentStart, [], false, false, nil))
                    pointer = currentStart
                } else {
                    currentStart = pointer
                }
            }
            
            if currentStart >= pointer {
                // 🌟 彻底清除 32分音符历史遗留，兜底时值严格锁定为 30 (16分音符)！
                filledNotes.append((sn.pitch, currentStart, max(currentStart + 30, sn.end), sn.graces, sn.origTieStart, sn.origTieEnd, sn.terminalType))
                pointer = max(currentStart + 30, sn.end)
            } else {
                let newStart = pointer
                if sn.end > newStart {
                    filledNotes.append((sn.pitch, newStart, sn.end, sn.graces, sn.origTieStart, sn.origTieEnd, sn.terminalType))
                    pointer = sn.end
                }
            }
        }
        // 调试：步骤 2 - 缝隙吸收后
        if debugMode {
            #if DEBUG
            print("⚠️ [TIE BUG 追踪] 小节 ?? - 步骤 2：缝隙吸收后")
            #endif
            for (fi, fn) in filledNotes.enumerated() {
                #if DEBUG
                print("  音符 \(fi): pitch=\(fn.pitch), dur=\(fn.end - fn.start), isTieStart=\(fn.origTieStart), isTieEnd=\(fn.origTieEnd)")
                #endif
            }
        }
        
        // 2.5 休止符合并 (打扫战场)
        var mergedNotes: [(pitch: Int, start: Int, end: Int, graces: [Int], origTieStart: Bool, origTieEnd: Bool, terminalType: String?)] = []
        for fn in filledNotes {
            if fn.pitch < 0, !mergedNotes.isEmpty, mergedNotes.last!.pitch < 0 {
                let mergedEnd = max(mergedNotes[mergedNotes.count - 1].end, fn.end)
                mergedNotes[mergedNotes.count - 1].end = mergedEnd
            } else {
                mergedNotes.append(fn)
            }
        }
        
        // 3. 🌟 绝对守恒的强拍切割器
        var slicedNotes: [EnrichedNote] = []
        var totalSlots = 0
        
        // 安全提取动态边界
        let b1 = profile.beatBoundaries.count > 0 ? profile.beatBoundaries[0] : 120
        let b2 = profile.beatBoundaries.count > 1 ? profile.beatBoundaries[1] : 0
        let b3 = profile.beatBoundaries.count > 2 ? profile.beatBoundaries[2] : 0
        let b4 = profile.beatBoundaries.count > 3 ? profile.beatBoundaries[3] : 0

        for fn in mergedNotes {
            if totalSlots >= profile.slotsPerMeasure { break }
            
            var currentStart = fn.start
            let finalEnd = fn.end
            var isFirstSlice = true
            let isTupletChunk = tupletSlots.contains(finalEnd - currentStart)
            
            while currentStart < finalEnd {
                if totalSlots >= profile.slotsPerMeasure { break }
                
                var nextBoundary = finalEnd
                
                if !isTupletChunk {
                    if b2 > 0 && currentStart < b2 && finalEnd > b2 { nextBoundary = b2 }
                    else if currentStart > 0 && currentStart < b1 && finalEnd > b1 { nextBoundary = b1 }
                    else if b3 > 0 && currentStart > b2 && currentStart < b3 && finalEnd > b3 { nextBoundary = b3 }
                    else if b4 > 0 && currentStart > b3 && currentStart < b4 && finalEnd > b4 { nextBoundary = b4 }
                    
                    var sliceDuration = nextBoundary - currentStart
                    if !standardSlots.contains(sliceDuration) && !tupletSlots.contains(sliceDuration) {
                        var found = false
                        for std in standardSlots {
                            if std < sliceDuration {
                                sliceDuration = std
                                nextBoundary = currentStart + std
                                found = true
                                break
                            }
                        }
                        if !found {
                            sliceDuration = 30
                            nextBoundary = currentStart + 30
                        }
                    }
                }
                
                var sliceDur = nextBoundary - currentStart
                
                if totalSlots + sliceDur > profile.slotsPerMeasure {
                    sliceDur = profile.slotsPerMeasure - totalSlots
                }
                
                let isLastSlice = (nextBoundary >= finalEnd)
                let tieStart = (!isLastSlice || fn.origTieStart) && (fn.pitch >= 0)
                let tieEnd = (!isFirstSlice || fn.origTieEnd) && (fn.pitch >= 0)
                
                if sliceDur > 0 {
                    slicedNotes.append(EnrichedNote(
                        midiPitch: fn.pitch,
                        durationSlots: sliceDur,
                        gracePitches: isFirstSlice ? fn.graces : [],
                        isTieStart: tieStart,
                        isTieEnd: tieEnd,
                        terminalType: fn.terminalType
                    ))
                    totalSlots += sliceDur
                }
                
                currentStart = nextBoundary
                isFirstSlice = false
            }
        }
        // 调试：步骤 4 - 强拍切割器后
        if debugMode {
            #if DEBUG
            print("⚠️ [TIE BUG 追踪] 小节 ?? - 步骤 4：强拍切割器后")
            #endif
            for (si, sn) in slicedNotes.enumerated() {
                #if DEBUG
                print("  音符 \(si): pitch=\(sn.midiPitch), dur=\(sn.durationSlots), isTieStart=\(sn.isTieStart), isTieEnd=\(sn.isTieEnd)")
                #endif
            }
        }
        
        // 🌟 4. 新增的音符融合阶段 (Note Amalgamation)
        // 专门处理由于缝隙吸收和对齐引发的同音高碎片
        var finalResult: [EnrichedNote] = []
        for sn in slicedNotes {
            if !finalResult.isEmpty {
                let lastIdx = finalResult.count - 1
                let lastNote = finalResult[lastIdx]
                
                // 如果前一个音符通过 tie 连接到当前音符，并且音高完全一致
                if lastNote.isTieStart && sn.isTieEnd && lastNote.midiPitch == sn.midiPitch {
                    let combinedDuration = lastNote.durationSlots + sn.durationSlots
                    
                    // 确保融合后的音符是一个标准的乐谱时值，并且不会越过 240（隐形小节线）
                    // 假设一个音从 0 到 120，另一个从 120 到 240，结合就是 240，不会触发越线。
                    if standardSlots.contains(combinedDuration) || tupletSlots.contains(combinedDuration) {
                        finalResult[lastIdx].durationSlots = combinedDuration
                        // 继承当前片段的结尾连线状态
                        finalResult[lastIdx].isTieStart = sn.isTieStart
                        // 将两者的 gracePitches 合并（理论上 sn 不应该有 gracePitches，但为防万一）
                        finalResult[lastIdx].gracePitches.append(contentsOf: sn.gracePitches)
                        continue
                    }
                }
            }
            finalResult.append(sn)
        }
        
        // ==========================================================
        // 调试：步骤 5 - 音符融合阶段后
        if debugMode {
            #if DEBUG
            print("⚠️ [TIE BUG 追踪] 小节 ?? - 步骤 5：音符融合阶段后")
            #endif
            for (fi, fn) in finalResult.enumerated() {
                #if DEBUG
                print("  音符 \(fi): pitch=\(fn.midiPitch), dur=\(fn.durationSlots), isTieStart=\(fn.isTieStart), isTieEnd=\(fn.isTieEnd)")
                #endif
            }
        }
        
        // 🌟 终极防线 1：强行守恒 480 slots (尾部精准修剪/填充)
        // ==========================================================
        var currentFinalSlots = finalResult.reduce(0) { $0 + $1.durationSlots }
        
        if currentFinalSlots < profile.slotsPerMeasure {
            let gap = profile.slotsPerMeasure - currentFinalSlots
            finalResult.append(EnrichedNote(midiPitch: -1, durationSlots: gap, gracePitches: [], isTieStart: false, isTieEnd: false))
        } else if currentFinalSlots > profile.slotsPerMeasure {
            var overflow = currentFinalSlots - profile.slotsPerMeasure
            for i in (0..<finalResult.count).reversed() {
                if overflow <= 0 { break }
                if finalResult[i].durationSlots > overflow {
                    finalResult[i].durationSlots -= overflow
                    overflow = 0
                } else {
                    overflow -= finalResult[i].durationSlots
                    finalResult[i].durationSlots = 0
                }
            }
            finalResult.removeAll { $0.durationSlots <= 0 }
        }
        // 调试：步骤 6 - 强行守恒 480 后
        if debugMode {
            #if DEBUG
            print("⚠️ [TIE BUG 追踪] 小节 ?? - 步骤 6：强行守恒 480 后")
            #endif
            for (fi, fn) in finalResult.enumerated() {
                #if DEBUG
                print("  音符 \(fi): pitch=\(fn.midiPitch), dur=\(fn.durationSlots), isTieStart=\(fn.isTieStart), isTieEnd=\(fn.isTieEnd)")
                #endif
            }
        }

        // ==========================================================
        // 🌟 终极防线 2：误差扩散 (消除非 10 倍数的毛刺，如 15, 5)
        // 确保所有数字都是 10 的倍数，绝不产生 32 分音符碎片
        // ==========================================================
        var error = 0
        for i in 0..<finalResult.count {
            let dur = finalResult[i].durationSlots + error
            let roundedDur = Int(round(Double(dur) / 10.0)) * 10
            error = dur - roundedDur
            finalResult[i].durationSlots = roundedDur
        }
        // 将最后一点误差塞给最后一个音符，确保绝对 480 守恒
        if error != 0 && !finalResult.isEmpty {
            finalResult[finalResult.count - 1].durationSlots += error
        }

        // 调试：步骤 7 - 误差扩散后
        if debugMode {
            #if DEBUG
            print("⚠️ [TIE BUG 追踪] 小节 ?? - 步骤 7：误差扩散后")
            #endif
            for (fi, fn) in finalResult.enumerated() {
                #if DEBUG
                print("  音符 \(fi): pitch=\(fn.midiPitch), dur=\(fn.durationSlots), isTieStart=\(fn.isTieStart), isTieEnd=\(fn.isTieEnd)")
                #endif
            }
        }

        // ==========================================================
        // 🌟 终极防线 3：消除孤立的 10 (因为 10 无法合法渲染)
        // 遇到 10，直接合并到相邻音符，宁可轻微延长，绝不白屏崩溃
        // ==========================================================
        for i in (0..<finalResult.count).reversed() {
            if finalResult[i].durationSlots == 10 {
                if i > 0 {
                    finalResult[i - 1].durationSlots += 10
                    finalResult[i].durationSlots = 0
                } else if i < finalResult.count - 1 {
                    finalResult[i + 1].durationSlots += 10
                    finalResult[i].durationSlots = 0
                }
            }
        }
        finalResult.removeAll { $0.durationSlots <= 0 }

        // 调试：步骤 8 - 消除孤立的 10 后
        if debugMode {
            #if DEBUG
            print("⚠️ [TIE BUG 追踪] 小节 ?? - 步骤 8：消除孤立的 10 后")
            #endif
            for (fi, fn) in finalResult.enumerated() {
                #if DEBUG
                print("  音符 \(fi): pitch=\(fn.midiPitch), dur=\(fn.durationSlots), isTieStart=\(fn.isTieStart), isTieEnd=\(fn.isTieEnd)")
                #endif
            }
        }

        // ==========================================================
        // 🌟 终极防线 3.5：拍子网格锁 (Beat Grid Lock) — 补偿分摊版
        // 扫描每 120 Slots (一拍)，若发现三连音(20/40/80)与
        // 十六分音符(30/60/90)混用，则将整拍统一为一种网格，
        // 并自动通过分摊补偿保持绝对守恒，绝不丢失音符。
        // ==========================================================
        var beatStart = 0
        while beatStart < finalResult.count {
            var beatSlots = 0
            var beatEnd = beatStart

            // 1. 框选出满 120 slots 的一个完整拍子
            while beatEnd < finalResult.count && beatSlots < 120 {
                beatSlots += finalResult[beatEnd].durationSlots
                beatEnd += 1
            }

            // 2. 仅处理刚好构成一拍的片段（防止末尾不完整拍被误处理）
            if beatSlots == 120 {
                let segment = Array(finalResult[beatStart..<beatEnd])
                let hasTriplet = segment.contains { [20, 40, 80].contains($0.durationSlots) }
                let hasStraight = segment.contains { [30, 60, 90].contains($0.durationSlots) }

                // 3. 只有当两种网格在同一拍内混用时才介入修正
                if hasTriplet && hasStraight {
                    let tripletCount = segment.filter { [20, 40, 80].contains($0.durationSlots) }.count
                    let straightCount = segment.filter { [30, 60, 90].contains($0.durationSlots) }.count
                    let targetIsTriplet = tripletCount >= straightCount

                    // 4. 生成目标时值映射，暂不修改原数组
                    var projectedDurations: [Int] = []
                    var expectedTotal = 0
                    for note in segment {
                        let dur = note.durationSlots
                        let targetDur: Int
                        if targetIsTriplet {
                            switch dur {
                            case 30: targetDur = 40
                            case 60: targetDur = 40
                            case 90: targetDur = 80
                            default: targetDur = dur
                            }
                        } else {
                            switch dur {
                            case 40: targetDur = 30
                            case 20: targetDur = 30
                            case 80: targetDur = 60
                            default: targetDur = dur
                            }
                        }
                        projectedDurations.append(targetDur)
                        expectedTotal += targetDur
                    }

                    // 5. 计算亏空/盈余，并平均摊派到这一拍的每一个音符
                    let deficit = 120 - expectedTotal
                    let count = segment.count
                    if count > 0 {
                        let adjustmentPerNote = deficit / count
                        let remainder = deficit % count

                        for i in 0..<count {
                            var finalSlots = projectedDurations[i] + adjustmentPerNote
                            if i == count - 1 { finalSlots += remainder }
                            // 安全下线保护：不低于最小的合法时值 20 slots
                            finalResult[beatStart + i].durationSlots = max(20, finalSlots)
                        }
                    }
                }
            }

            beatStart = beatEnd
        }

        // 调试：步骤 9 - 拍子网格锁后
        if debugMode {
            #if DEBUG
            print("⚠️ [TIE BUG 追踪] 小节 ?? - 步骤 9：拍子网格锁后")
            #endif
            for (fi, fn) in finalResult.enumerated() {
                #if DEBUG
                print("  音符 \(fi): pitch=\(fn.midiPitch), dur=\(fn.durationSlots), isTieStart=\(fn.isTieStart), isTieEnd=\(fn.isTieEnd)")
                #endif
            }
        }

        // ==========================================================
        // 🌟 终极防线 4：安全无损切片 (弗罗贝尼乌斯分解)
        // 遇到 50 自动无损拆为 30 + 20，用延音线缝合，音高 100% 保护
        // ==========================================================
        let exactMappableSlots = [480, 360, 320, 240, 180, 160, 120, 96, 90, 80, 72, 60, 48, 40, 30, 20]
        let splitSlots = [480, 360, 240, 120, 90, 80, 60, 40, 30, 20]
        
        var safeResult: [EnrichedNote] = []
        
        for note in finalResult {
            var remaining = note.durationSlots
            
            // 如果已经在 VexFlow 的安全白名单里，直接通过
            if exactMappableSlots.contains(remaining) {
                safeResult.append(note)
                continue
            }
            
            var pieces: [EnrichedNote] = []
            while remaining > 0 {
                var take = 20
                for std in splitSlots where std <= remaining {
                    // 核心数学算法：确保切完后剩下的数绝不能是孤立的 10！
                    if (remaining - std) != 10 {
                        take = std
                        break
                    }
                }
                
                let isFirst = pieces.isEmpty
                let isLast = (remaining - take == 0)
                
                pieces.append(EnrichedNote(
                    midiPitch: note.midiPitch,
                    durationSlots: take,
                    gracePitches: isFirst ? note.gracePitches : [], // 倚音全挂在第一块
                    isTieStart: !isLast || note.isTieStart,         // 自动缝合碎片起点
                    isTieEnd: !isFirst || note.isTieEnd             // 自动缝合碎片终点
                ))
                remaining -= take
            }
            
            // 禁止跨网格拆分：同时含三连音值和标准值 → 回退舍入为标准时值
            let tripletVals: Set<Int> = [20, 40, 80, 160, 320]
            let hasTriplet = pieces.contains { tripletVals.contains($0.durationSlots) }
            let hasStandard = pieces.contains { !tripletVals.contains($0.durationSlots) }
            if hasTriplet && hasStandard {
                let standardSlots = exactMappableSlots.filter { !tripletVals.contains($0) && ![48, 72, 96].contains($0) }
                let rounded = standardSlots.min(by: { abs($0 - note.durationSlots) < abs($1 - note.durationSlots) }) ?? 60
                safeResult.append(EnrichedNote(
                    midiPitch: note.midiPitch,
                    durationSlots: rounded,
                    gracePitches: note.gracePitches,
                    isTieStart: note.isTieStart,
                    isTieEnd: note.isTieEnd,
                    terminalType: note.terminalType
                ))
                continue
            }
            
            safeResult.append(contentsOf: pieces)
        }
        
        // 调试：步骤 10 - frobeniusSplit 后
        if debugMode {
            #if DEBUG
            print("⚠️ [TIE BUG 追踪] 小节 ?? - 步骤 10：frobeniusSplit 后")
            #endif
            for (si, sn) in safeResult.enumerated() {
                #if DEBUG
                print("  音符 \(si): pitch=\(sn.midiPitch), dur=\(sn.durationSlots), isTieStart=\(sn.isTieStart), isTieEnd=\(sn.isTieEnd)")
                #endif
            }
        }
        
        return safeResult
    }
}
