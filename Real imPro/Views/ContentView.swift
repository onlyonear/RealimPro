import SwiftUI

struct ContentView: View {
    // MARK: 算法分组枚举
    // 组名为工具栏直接显示的英文短名（与 Basic/Master 同性质，不走本地化；mini 竖屏 72pt 不截断）
    enum ImproAlgorithmGroup: String, Equatable {
        case guide = "Guide"
        case basic = "Basic"
        case master = "Master"
        // [方案21 20260915] 原第4组 .melody（在原旋律上加花）已下线：Guide/Basic/Master 三组都只从和声生成，
        // 原旋律对照改为五线谱 Original⇄Solo 胶囊（见 displayedMeasures / hasGeneratedImprovisation）。
    }

    // MARK: Guide Tone Line 四档线条预设（仅在组=Guide 时，第二控件显示）
    // direction/maxDuration 显式注入 ImproVisorOriginalGuideToneStrategy；startDegree="1"、音域[60,79] 在 worker 写死
    enum GuideLinePreset: CaseIterable {
        case smooth, rising, falling, busy   // 平滑两拍 / 偏上行两拍 / 偏下行两拍 / 每拍换
        var direction: Int { self == .rising ? 1 : (self == .falling ? -1 : 0) }
        var maxDuration: Int { self == .busy ? 120 : 240 }
        // 闭合态短名（音乐通用英文短词，受 algorithmLabelWidth 95pt 约束不截断）
        var shortName: String {
            switch self { case .smooth: "Smooth"; case .rising: "Rising"; case .falling: "Falling"; case .busy: "Busy" }
        }
        // 下拉行完整描述（中文 key → en.lproj；浮层不占工具栏宽度）
        var fullDisplayName: String {
            switch self {
            case .smooth:  return NSLocalizedString("平滑·每和弦两拍", comment: "")
            case .rising:  return NSLocalizedString("上行·每和弦两拍", comment: "")
            case .falling: return NSLocalizedString("下行·每和弦两拍", comment: "")
            case .busy:    return NSLocalizedString("密集·每拍换音", comment: "")
            }
        }
    }

    enum ImproAlgorithmType: String, Equatable {
        // 基础组
        case chordExercise = "Chord+App"
        case colorTone = "Chord+Col"

        // Great Lick（greatMoments 文法）：下拉显示在 Basic 组（实际分组见下方 currentAlgorithmList）
        case Lick = "Great Lick"

        // 大师组
        case LeeMorgan = "LeeMorgan"
        case charlieParker = "CharliePark"
        case billEvans = "BillEvans"
        case joePass = "JoePass"
        // 2026-09 新增 5 位大师（rawValue 即下拉菜单显示名，英文专有名词不本地化）
        case cannonballAdderley = "Cannonball"
        case chetBaker = "Chet Baker"
        case johnColtrane = "Coltrane"
        case milesDavis = "Miles"
        case redGarland = "Red Garland"
        //case ColemanHawkins = "ColemanHawkins"
        
        
        /// 映射对应策略实例
        func getStrategyInstance() -> GrammarStrategy? {
            switch self {
            case .chordExercise:   return GrammarStrategy.chord
            case .colorTone:       return GrammarStrategy.color
            case .charlieParker:   return GrammarStrategy.charlieParker
            case .billEvans:       return GrammarStrategy.billEvans
            case .joePass:         return GrammarStrategy.joePass
            case .Lick:            return GrammarStrategy.Lick
            //case .ColemanHawkins:  return GrammarStrategy.ColemanHawkins
            case .LeeMorgan:       return GrammarStrategy.LeeMorgan
            case .cannonballAdderley: return GrammarStrategy.cannonballAdderley
            case .chetBaker:       return GrammarStrategy.chetBaker
            case .johnColtrane:    return GrammarStrategy.johnColtrane
            case .milesDavis:      return GrammarStrategy.milesDavis
            case .redGarland:      return GrammarStrategy.redGarland
            }
        }
        
        /// 映射文法文件名
        var grammarFileName: String {
            switch self {
            case .chordExercise:   return "chord"
            case .colorTone:       return "color"
            case .charlieParker:   return "Bebop"
            case .billEvans:       return "BillEvans"
            case .joePass:         return "JoePass"
            case .Lick:            return "greatMoments"
            //case .ColemanHawkins:  return "ColemanHawkins-Ballads"
            case .LeeMorgan:           return "Blues"
            case .cannonballAdderley: return "CannonballAdderley"
            case .chetBaker:       return "ChetBaker"
            case .johnColtrane:    return "JohnColtrane"
            case .milesDavis:      return "MilesDavis"
            case .redGarland:      return "RedGarland"
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
    // 和弦音/色彩音字典页：五线谱界面「屏幕右边缘向左滑」呼出（不占工具栏）
    @State private var showChordDictionary = false
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

    // MARK: - 用户导入的命名歌单（独立持久化：不碰 My Songs 存档，也不碰内置 Classic Jazz）
    private static let importedStoreKey = "importedPlaylists_v1"

    /// 从 UserDefaults 读取用户导入的命名分组（启动一次性载入）
    private static func loadImportedPlaylists() -> [JazzPlaylist] {
        guard let data = UserDefaults.standard.data(forKey: importedStoreKey),
              let list = try? JSONDecoder().decode([JazzPlaylist].self, from: data) else { return [] }
        return list
    }

    /// 把用户导入分组写回 UserDefaults
    private func saveImportedPlaylists() {
        guard let data = try? JSONEncoder().encode(importedPlaylists) else { return }
        UserDefaults.standard.set(data, forKey: Self.importedStoreKey)
    }

    // MARK: - 废纸篓（仅 My Songs / 导入组的“单曲删除”进入；内置 Classic Jazz 不进；整组删除不进）
    private static let trashStoreKey = "trashSongs_v1"

    private static func loadTrash() -> [TrashItem] {
        guard let data = UserDefaults.standard.data(forKey: trashStoreKey),
              let list = try? JSONDecoder().decode([TrashItem].self, from: data) else { return [] }
        return list
    }

    private func saveTrash() {
        guard let data = try? JSONEncoder().encode(trashItems) else { return }
        UserDefaults.standard.set(data, forKey: Self.trashStoreKey)
    }

    /// My Songs 组显示名（playlists[0] 固定为 My Songs）
    private var mySongsPlaylistName: String { NSLocalizedString("My Songs", comment: "") }

    // MARK: - 内置 Classic Jazz 曲库接线（只增不改：不影响 My Songs 的持久化与导入）
    /// 从 Bundle 解码内置库（失败返回 nil，不影响现有任何功能）
    private static func loadBuiltinLibrary() -> BuiltinClassicLibrary? {
        try? BuiltinMelodyLibrary.load()
    }

    /// 内置单曲稳定键（与去重口径一致：标题|作曲家，忽略大小写与首尾空格）
    private func builtinSongKey(_ song: JazzSong) -> String {
        "\(song.title.trimmingCharacters(in: .whitespaces).lowercased())|\(song.composer.trimmingCharacters(in: .whitespaces).lowercased())"
    }

    /// 按“已删除单曲”过滤后构建内置播放列表（每次用当前隐藏集合现算，保证可恢复）
    private func makeBuiltinPlaylist() -> JazzPlaylist? {
        guard let lib = builtinLibrary?.regionFiltered(), !hiddenBuiltinPlaylistNames.contains(lib.name) else { return nil }
        let visible = lib.playlist.songs.filter { !hiddenBuiltinSongKeys.contains(builtinSongKey($0)) }
        guard !visible.isEmpty else { return nil }
        return JazzPlaylist(name: lib.name, songs: visible)
    }

    /// 启动/恢复时把内置组放到 My Songs 之后（永远在 index≥1，避开 savePlaylists 的 playlists[0] 假设）
    private func installBuiltinPlaylistIfNeeded() {
        guard let builtin = makeBuiltinPlaylist() else { return }
        if let idx = playlists.firstIndex(where: { $0.name == builtin.name }) {
            playlists[idx] = builtin   // 单曲隐藏后刷新该组
        } else {
            playlists.append(builtin)  // My Songs 永远保持在 0
        }
    }

    /// 隐藏内置整组（UserDefaults 持久化 + 从内存移除，可经底部菜单恢复）
    private func hideBuiltinPlaylist(named name: String) {
        hiddenBuiltinPlaylistNames.insert(name)
        UserDefaults.standard.set(Array(hiddenBuiltinPlaylistNames), forKey: "hiddenBuiltinPlaylistNames")
        playlists.removeAll { $0.name == name }
        if let sel = selectedSong, playlists.allSatisfy({ !$0.songs.contains(where: { $0.id == sel.id }) }) {
            selectedSong = playlists[0].songs.first
        }
    }

    /// 删除/隐藏内置单曲（持久化稳定键 + 重建该组；不写 My Songs 存档）
    private func hideBuiltinSong(_ song: JazzSong) {
        hiddenBuiltinSongKeys.insert(builtinSongKey(song))
        UserDefaults.standard.set(Array(hiddenBuiltinSongKeys), forKey: "hiddenBuiltinSongKeys")
        installBuiltinPlaylistIfNeeded()
        if selectedSong?.id == song.id {
            selectedSong = playlists[0].songs.first
        }
    }

    /// 恢复内置组（同时清空该组单曲隐藏记录，整组完整回来）
    private func restoreBuiltinPlaylist() {
        guard let lib = builtinLibrary else { return }
        hiddenBuiltinPlaylistNames.remove(lib.name)
        UserDefaults.standard.set(Array(hiddenBuiltinPlaylistNames), forKey: "hiddenBuiltinPlaylistNames")
        hiddenBuiltinSongKeys.removeAll()
        UserDefaults.standard.set(Array(hiddenBuiltinSongKeys), forKey: "hiddenBuiltinSongKeys")
        installBuiltinPlaylistIfNeeded()
    }


    /// 统一稳定 key（标题+作曲家，不区分大小写，去空格）；歌单去重与外部旋律绑定共用同一口径
    private static func normalizedSongKey(title: String, composer: String) -> String {
        "\(title.trimmingCharacters(in: .whitespaces).lowercased())|\(composer.trimmingCharacters(in: .whitespaces).lowercased())"
    }

    /// 统一去重 key（标题+作曲家，不区分大小写，去空格）
    private func dedupKey(for song: JazzSong) -> String {
        Self.normalizedSongKey(title: song.title, composer: song.composer)
    }

    // MARK: 导入即命名分组（排在 My Songs / 内置 Classic Jazz 之后）
    /// 导入组应插入的位置：My Songs(0) 之后、内置 Classic Jazz 之后（内置隐藏时退到 1）
    private func importedInsertionIndex() -> Int {
        if let bn = builtinLibrary?.name, let bi = playlists.firstIndex(where: { $0.name == bn }) {
            return bi + 1
        }
        return 1
    }

    /// 启动时把已存的用户导入组注入到内置组之后；同名刷新、不重复插入，保持导入先后顺序
    private func installImportedPlaylistsIfNeeded() {
        var at = importedInsertionIndex()
        for gp in importedPlaylists {
            if let exist = playlists.firstIndex(where: { $0.name == gp.name }) {
                playlists[exist] = gp
                at = exist + 1
            } else {
                let pos = min(max(at, 0), playlists.count)
                playlists.insert(gp, at: pos)
                at = pos + 1
            }
        }
    }

    /// 启动时扫描 Documents/ImportedMelodies/*.json，重建「来源歌单 →（标题|作曲家 → 旋律）」运行时索引。
    /// 歌曲本身已由 importedPlaylists(UserDefaults) 持久化，这里只补旋律层。
    /// 旋律只绑定到“提供它的那个歌单”，不全局按曲名共享，避免同名 iRealPro 和声单串到别的歌单的旋律。
    private func loadExternalMelodies() {
        let dir = Self.externalMelodyDir
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: f),
                  let lib = try? BuiltinMelodyLibrary.load(from: data) else { continue }
            // 归属与导入路由一致：单曲导入进 My Songs，多首以库名建命名歌单
            let owner = lib.songs.count == 1 ? mySongsPlaylistName : lib.name
            var inner = externalMelodies[owner] ?? [:]
            for bs in lib.songs {
                inner[dedupKey(for: bs.song)] = bs.melody
            }
            externalMelodies[owner] = inner
        }
    }

    /// 把某个导入组的最新内容同步进内存 playlists（同名刷新，否则插到内置组之后）
    private func syncImportedGroupIntoPlaylists(_ gp: JazzPlaylist) {
        if let pi = playlists.firstIndex(where: { $0.name == gp.name }) {
            playlists[pi] = gp
        } else {
            let pos = min(importedInsertionIndex(), playlists.count)
            playlists.insert(gp, at: pos)
        }
    }

    /// 以“命名歌单”形式导入：同名分组组内去重合并，新名字则建组。返回真正新增的歌曲与跳过数。
    @discardableResult
    private func importSongsAsGroup(_ songs: [JazzSong], proposedName: String?) -> (newSongs: [JazzSong], skipped: Int) {
        let raw = (proposedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = raw.isEmpty ? NSLocalizedString("导入的歌单", comment: "") : raw

        if let gi = importedPlaylists.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            // 同名组：组内按 标题+作曲家 去重后追加
            let existKeys = Set(importedPlaylists[gi].songs.map { dedupKey(for: $0) })
            let newSongs = songs.filter { !existKeys.contains(dedupKey(for: $0)) }
            importedPlaylists[gi].songs.append(contentsOf: newSongs)
            saveImportedPlaylists()
            syncImportedGroupIntoPlaylists(importedPlaylists[gi])
            if let first = newSongs.first { selectedSong = first }
            return (newSongs, songs.count - newSongs.count)
        } else {
            // 新组：同一文件内部也先去重
            var seen = Set<String>(), uniq = [JazzSong]()
            for s in songs {
                if seen.insert(dedupKey(for: s)).inserted { uniq.append(s) }
            }
            let gp = JazzPlaylist(name: name, songs: uniq)
            importedPlaylists.append(gp)
            saveImportedPlaylists()
            syncImportedGroupIntoPlaylists(gp)
            if let first = uniq.first { selectedSong = first }
            return (uniq, songs.count - uniq.count)
        }
    }

    /// 单曲（无显式歌单名且仅 1 首）统一导入到 My Songs（Demo 之后），按 标题+作曲家 去重
    @discardableResult
    private func importSingleSongToMySongs(_ song: JazzSong) -> (newSongs: [JazzSong], skipped: Int) {
        let existKeys = Set(playlists[0].songs.map { dedupKey(for: $0) })
        if existKeys.contains(dedupKey(for: song)) {
            return ([], 1)
        }
        playlists[0].songs.append(song)
        savePlaylists()
        selectedSong = song
        return ([song], 0)
    }

    /// 统一导入入口：只要解析出 1 首即视为单曲 → 进 My Songs（忽略歌单名）；多首才按命名歌单导入
    @discardableResult
    private func importSongsUnified(_ songs: [JazzSong], proposedName: String?) -> (newSongs: [JazzSong], skipped: Int) {
        if songs.count == 1 {
            return importSingleSongToMySongs(songs[0])
        }
        return importSongsAsGroup(songs, proposedName: proposedName)
    }

    /// 删除整个用户导入分组（用户数据，直接从存储与内存移除；区别于内置组的“可恢复隐藏”）
    private func deleteImportedGroup(named name: String) {
        importedPlaylists.removeAll { $0.name == name }
        saveImportedPlaylists()
        playlists.removeAll { $0.name == name }
        if let sel = selectedSong, playlists.allSatisfy({ !$0.songs.contains(where: { $0.id == sel.id }) }) {
            selectedSong = playlists[0].songs.first
        }
    }

    // MARK: 废纸篓操作（仅单曲删除进入）
    /// 单曲删除 → 移入废纸篓（My Songs / 导入组）。内置 Classic Jazz 不经过这里。
    private func moveSongToTrash(_ song: JazzSong, from playlist: JazzPlaylist) {
        let sourceName = playlist.name
        if let pi = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists[pi].songs.removeAll { $0.id == song.id }
        }
        if sourceName == mySongsPlaylistName {
            savePlaylists()
        } else if let ii = importedPlaylists.firstIndex(where: { $0.name == sourceName }),
                  let pi = playlists.firstIndex(where: { $0.name == sourceName }) {
            importedPlaylists[ii].songs = playlists[pi].songs
            saveImportedPlaylists()
        }
        let key = dedupKey(for: song)
        if !trashItems.contains(where: { dedupKey(for: $0.song) == key }) {
            trashItems.insert(TrashItem(song: song, sourcePlaylist: sourceName), at: 0)
            saveTrash()
        }
        if let sel = selectedSong, sel.id == song.id {
            selectedSong = playlists[0].songs.first
        }
    }

    /// 清空 My Songs（Demo 保留在第一位），其余单曲全部移入废纸篓
    private func clearMySongsToTrash() {
        guard playlists.indices.contains(0), playlists[0].songs.count > 1 else { return }
        let userSongs = Array(playlists[0].songs.dropFirst())
        for s in userSongs {
            let key = dedupKey(for: s)
            if !trashItems.contains(where: { dedupKey(for: $0.song) == key }) {
                trashItems.append(TrashItem(song: s, sourcePlaylist: mySongsPlaylistName))
            }
        }
        playlists[0].songs = [JazzPlaylist.demoSong]
        savePlaylists()
        saveTrash()
        if let sel = selectedSong, !playlists[0].songs.contains(where: { $0.id == sel.id }) {
            selectedSong = playlists[0].songs.first
        }
    }

    /// 恢复废纸篓单曲到原组；原导入组已被整组删除时兜底回到 My Songs
    private func restoreTrashItem(_ item: TrashItem) {
        let key = dedupKey(for: item.song)
        var target = item.sourcePlaylist
        if target != mySongsPlaylistName, !playlists.contains(where: { $0.name == target }) {
            target = mySongsPlaylistName
        }
        if let pi = playlists.firstIndex(where: { $0.name == target }) {
            let exist = Set(playlists[pi].songs.map { dedupKey(for: $0) })
            if !exist.contains(key) {
                playlists[pi].songs.append(item.song)  // My Songs 的 Demo 恒为 [0]，追加在末尾
            }
            if target == mySongsPlaylistName {
                savePlaylists()
            } else if let ii = importedPlaylists.firstIndex(where: { $0.name == target }) {
                importedPlaylists[ii].songs = playlists[pi].songs
                saveImportedPlaylists()
            }
        }
        trashItems.removeAll { $0.id == item.id }
        saveTrash()
    }

    /// 废纸篓单曲永久删除
    private func permanentlyDeleteTrashItem(_ item: TrashItem) {
        trashItems.removeAll { $0.id == item.id }
        saveTrash()
    }

    /// 清空废纸篓（永久，不可恢复）
    private func emptyTrash() {
        trashItems.removeAll()
        saveTrash()
    }

    /// 文件导入结果
    private struct FileImportResult {
        var songs: [JazzSong]
        var error: String?
        var groupName: String? = nil
        /// 外部旋律 JSON 导入时携带的「标题|作曲家 → 原旋律」索引（仅本文件；iRealPro 导入为 nil）
        var externalMelodies: [String: [GeneratedMeasure]]? = nil
        /// MusicXML 成功导入后的说明（风格固定 / 速度）；其余导入为 nil
        var reportNote: String? = nil
    }

    /// Documents/ImportedMelodies：持久化外部导入的旋律 JSON（GeneratedMeasure 不可 Codable，
    /// 故存原始文件，启动时再解码建索引）。
    private static var externalMelodyDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("ImportedMelodies", isDirectory: true)
    }

    private static func persistExternalMelodyFile(data: Data, name: String) {
        let dir = externalMelodyDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        try? data.write(to: dir.appendingPathComponent("\(safe).json"), options: .atomic)
    }

    /// 从文件 URL 读取并解析（后台线程）：.json 走旋律库解码器；其余走 iReal Pro 解析
    private static func importFromFile(url: URL) -> FileImportResult {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        // —— 旋律 JSON 导入分支 ——
        if url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url) else {
                return FileImportResult(songs: [], error: NSLocalizedString("无法读取 JSON 文件。", comment: ""))
            }
            do {
                let lib = try BuiltinMelodyLibrary.load(from: data)
                var mel: [String: [GeneratedMeasure]] = [:]
                for bs in lib.songs {
                    mel[Self.normalizedSongKey(title: bs.song.title, composer: bs.song.composer)] = bs.melody
                }
                persistExternalMelodyFile(data: data, name: lib.name)
                return FileImportResult(songs: lib.playlist.songs, error: nil,
                                        groupName: lib.name, externalMelodies: mel)
            } catch {
                return FileImportResult(songs: [], error: NSLocalizedString("旋律 JSON 解析失败。", comment: ""))
            }
        }

        // —— MusicXML 导入分支 —— .mxl(压缩)二期；.musicxml 直接走；.xml 先嗅探 <score-partwise>
        let ext = url.pathExtension.lowercased()
        if ext == "mxl" {
            return FileImportResult(songs: [], error: NSLocalizedString(
                "暂不支持压缩的 .mxl 文件，请在“文件”App 中解压或另存为 .musicxml/.xml 后再导入。", comment: ""))
        }
        if ext == "musicxml" {
            guard let data = try? Data(contentsOf: url) else {
                return FileImportResult(songs: [], error: NSLocalizedString("无法读取文件。", comment: ""))
            }
            return Self.importMusicXML(data: data, url: url)
        }
        if ext == "xml", let data = try? Data(contentsOf: url) {
            let head = String(data: data.prefix(8192), encoding: .utf8) ?? ""
            if head.contains("score-partwise") {
                return Self.importMusicXML(data: data, url: url)
            }
            // 非 score-partwise 的 .xml：当作普通文本，继续走下面的 iReal Pro 解析
        }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return FileImportResult(songs: [], error: NSLocalizedString("无法读取文件，请确认文件编码为 UTF-8。", comment: ""))
        }

        let parsed = IRealProParser.parseHTML(html: content)
        if parsed.isEmpty {
            return FileImportResult(songs: [], error: NSLocalizedString("文件中未找到有效的 iReal Pro 乐谱。", comment: ""))
        }

        let songs = parsed.map { IRealProParser.toJazzSong($0) }
        // 仅 1 首视为单曲（不带歌单名 → 进 My Songs）；多首才用文件名（去扩展名，如 ireal.txt -> "ireal"）做歌单名
        let groupName: String? = songs.count == 1 ? nil : url.deletingPathExtension().lastPathComponent
        return FileImportResult(songs: songs, error: nil, groupName: groupName)
    }

    /// MusicXML → 解码为曲库 → 落库 ImportedMelodies，返回带旋律索引的导入结果
    private static func importMusicXML(data: Data, url: URL) -> FileImportResult {
        let fallback = url.deletingPathExtension().lastPathComponent
        do {
            let json = try MusicXMLImporter.libraryForApp(data: data, fallbackTitle: fallback)
            let lib = try BuiltinMelodyLibrary.load(from: json)
            guard let first = lib.songs.first else {
                return FileImportResult(songs: [], error: NSLocalizedString("MusicXML 中未解析出有效乐曲。", comment: ""))
            }
            // 唯一文件名（标题|作曲家），重导覆盖、不同曲不互相覆盖
            let key = Self.normalizedSongKey(title: first.title, composer: first.composer)
            let safe = ("mx_" + key)
                .replacingOccurrences(of: "|", with: "_")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ":", with: "_")
            persistExternalMelodyFile(data: json, name: safe)
            var mel: [String: [GeneratedMeasure]] = [:]
            for bs in lib.songs {
                mel[Self.normalizedSongKey(title: bs.title, composer: bs.composer)] = bs.melody
            }
            let tempo = first.song.tempo
            let note = String(format: NSLocalizedString(
                "已导入《%@》。MusicXML 无可靠风格字段，伴奏统一按 Medium Swing（中等摇摆）处理；速度 %d BPM。原曲旋律与和弦可直接显示、播放与即兴。",
                comment: ""), first.title, tempo)
            return FileImportResult(songs: lib.playlist.songs, error: nil, groupName: nil,
                                    externalMelodies: mel, reportNote: note)
        } catch let e as MusicXMLImportError {
            return FileImportResult(songs: [], error: e.description)
        } catch {
            return FileImportResult(songs: [], error: NSLocalizedString(
                "MusicXML 解析失败，请确认是单 Part 的 lead sheet（和弦+旋律）。", comment: ""))
        }
    }

    /// 处理文件导入结果：以命名歌单形式落库（同名合并去重），再决定提示
    private func handleImportResult(_ result: FileImportResult) {
        if let error = result.error, result.songs.isEmpty {
            fileImportError = error
            importReportNote = nil
            importedTotalCount = 0
            importSkippedCount = 0
            mixedAlertCount = 0
            showImportResultAlert = true
            return
        }

        fileImportError = nil
        importReportNote = result.reportNote

        // 外部旋律 JSON：旋律并入“来源歌单”作用域（iRealPro 导入为 nil，无操作）。
        // 归属与导入路由一致：单曲进 My Songs、多首进命名歌单；不再全局按曲名挂旋律。
        if let em = result.externalMelodies {
            let owner = result.songs.count == 1 ? mySongsPlaylistName : (result.groupName ?? mySongsPlaylistName)
            var inner = externalMelodies[owner] ?? [:]
            inner.merge(em) { (_, new) in new }
            externalMelodies[owner] = inner
        }

        let outcome = importSongsUnified(result.songs, proposedName: result.groupName)
        importSkippedCount = outcome.skipped
        importedTotalCount = outcome.newSongs.count
        mixedAlertCount = outcome.newSongs.filter { $0.hasMixedTimeSignature }.count

        let hasMixed = mixedAlertCount > 0
        let hasSkipped = importSkippedCount > 0
        let hasNew = importedTotalCount > 0
        showImportResultAlert = hasMixed || hasSkipped || !hasNew || (importReportNote != nil)
    }

    /// 从 irealb:// 链接提取歌单名：=== 分隔的第一段若不是一首合法歌曲（字段不足）即为歌单名
    private func playlistName(fromIRealURL urlString: String) -> String? {
        var s = urlString
            .replacingOccurrences(of: "irealb://", with: "")
            .replacingOccurrences(of: "irealbook://", with: "")
        s = s.removingPercentEncoding ?? s
        guard let first = s.components(separatedBy: "===").first else { return nil }
        // 一首合法歌曲段至少含 title=composer=style=key=music 共 4 个以上 '='
        if first.filter({ $0 == "=" }).count >= 4 { return nil }
        let n = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? nil : n
    }

    /// 处理 URL Scheme 导入 (irealb:// 或 irealbook://)
    private func handleURLImport(_ url: URL) {
        let urlString = url.absoluteString
        guard urlString.hasPrefix("irealb://") || urlString.hasPrefix("irealbook://") else { return }

        isLoadingFile = true
        DispatchQueue.global(qos: .userInitiated).async {
            let parsed = IRealProParser.parsePlaylist(url: urlString)
            let songs = parsed.map { IRealProParser.toJazzSong($0) }
            let groupName = self.playlistName(fromIRealURL: urlString)

            DispatchQueue.main.async {
                isLoadingFile = false
                if songs.isEmpty {
                    handleImportResult(FileImportResult(
                        songs: [],
                        error: NSLocalizedString("Failed to parse iReal Pro link.", comment: "")
                    ))
                } else {
                    handleImportResult(FileImportResult(songs: songs, error: nil, groupName: groupName))
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
    @State private var importReportNote: String? = nil // MusicXML 成功导入说明（风格/速度）
    @State private var playlists: [JazzPlaylist] = ContentView.loadPlaylists()
    @State private var importedPlaylists: [JazzPlaylist] = ContentView.loadImportedPlaylists()
    @State private var selectedPlaylistIndex = 0

    // MARK: - 内置 Classic Jazz（公共领域80首，Bundle 加载；加载失败为 nil 时该功能整体优雅缺席）
    @State private var builtinLibrary: BuiltinClassicLibrary? = ContentView.loadBuiltinLibrary()
    /// 外部导入旋律索引（来自 Documents/ImportedMelodies，启动重建）：
    /// [来源歌单名: [标题|作曲家(小写): 旋律]]；旋律只在其来源歌单内命中，不跨歌单串
    @State private var externalMelodies: [String: [String: [GeneratedMeasure]]] = [:]
    // 整组隐藏记录（按组名）；内置组每次启动由 Bundle 重建，故用 UserDefaults 持久化“隐藏”
    @State private var hiddenBuiltinPlaylistNames: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "hiddenBuiltinPlaylistNames") ?? [])
    // 内置单曲删除记录（稳定键 = 标题|作曲家，不用易变的 UUID）
    @State private var hiddenBuiltinSongKeys: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "hiddenBuiltinSongKeys") ?? [])
    // 废纸篓（My Songs / 导入组的单曲删除先进入这里，可恢复；内置组不进）
    @State private var trashItems: [TrashItem] = ContentView.loadTrash()
    // 当前是否正显示“内置原曲旋律”（仅用于此状态下禁用转调；非界面标签）
    @State private var isShowingBuiltinMelody = false

    // 音域范围
    @State private var lowNoteMidi: Int = 60    // 最低音 MIDI（默认 C4，中央C）
    @State private var highNoteMidi: Int = 81   // 最高音 MIDI（默认 A5）
    
    // 钢琴键盘高亮的音符（MIDI 编号集合）
    @State private var activeMidiNotes: Set<Int> = []
    
    // 追踪播放游标 ID 以及曲谱更新版本
    @State private var playingNoteId: String = ""
    @State private var soloVersion: UUID = UUID()
    @State private var hasGeneratedSolo: Bool = false // 🌟 区分屏幕上当前是“骨架谱”还是“真实的 Solo”
   @State private var isGenerating: Bool = false       // 🌟 P0-1: 生成中状态（防重入 + 转圈遮罩）
   @State private var generationTask: Task<Void, Never>? // 🌟 P0-1: 后台生成任务句柄（离开页面/切歌时可取消）
        #if DEBUG
        @State private var debugLSTM: Bool = false   // [LSTM P1] DEBUG-only 调试开关（默认关）
        #endif
    
    // 🌟 新增：播放状态机与跳转锚点
    @State private var isPlaying: Bool = false
    @State private var isPaused: Bool = false
    @State private var startMeasureIndex: Int = 0
    
    // MARK: - 设置面板开关
    @State private var showSettings = false
    
    // MARK: - 🎵 算法分组 & 选择（顶部栏专用）
    @State private var selectedAlgorithmGroup: ImproAlgorithmGroup = .basic
    @State private var selectedAlgorithm: ImproAlgorithmType = .chordExercise
    @State private var selectedGuidePreset: GuideLinePreset = .smooth  // Guide 组四档线条，默认平滑两拍
    @AppStorage("transformEnabled") private var enableTransform: Bool = false  // [Hunk10] 调音台圆点，默认关
    @AppStorage("transformMusician") private var selectedTransformMusician: String = TransformMusicianRegistry.defaultMusician  // [Hunk10] guide/grammar 两链共用，默认 My
    @AppStorage("guideColorEnabled") private var guideColorEnabled: Bool = false  // [Guide Color 圆点 20260914] Guide 整流色彩档，默认关；仅 Guide 且 TRANSFORM 点亮时生效
    // [默认值翻转 20260925] Basic/Master 整流「是否启用色彩」：默认 false=Java spell-only，手动点亮才加色彩。
    //   旧值封存（原默认 true=grammar 默认带色彩、听感零变化）：@AppStorage("grammarColorEnabled") ... = true
    //   关 → grammar 整流走 Java 出厂 spell-only（RectifyMode.javaSpellOnly）。与 guideColorEnabled 分键、切组互不污染。
    @AppStorage("grammarColorEnabled") private var grammarColorEnabled: Bool = false  // 默认 false=Java spell-only，手动点亮才加色彩
    // 整流(Rectify)固定为"全拍对齐原版"(.allBeats)，不再提供 UI 切换；
    // 三档逻辑仍保留在 GrammarLickGlue.swift，调试时改下方 grammarStrategy.rectifyMode 赋值即可。
    // D4 色彩音池档位（conservative 基础 / full 扩展全量），调音台切换
    @AppStorage("colorModeRaw") private var colorModeRaw: String = ColorPaletteMode.conservative.rawValue
    // [方案21 20260915] Original 原旋律 ⇄ Solo 即兴 显示源（三组通用；当前曲自带旋律且已生成即兴才出胶囊）
    // showOriginalMelody：true=显示曲库原旋律（按需取、转调感知、永不加花）；false=显示生成缓存 generatedSolo。切换只换显示、不重新随机。
    @State private var showOriginalMelody: Bool = true
    // hasGeneratedImprovisation：是否【已通过 Guide/Basic/Master worker 成功生成过即兴】（选曲铺原旋律不算，
    // 区别于铺原旋律也会置 true 的 hasGeneratedSolo）；换曲/切组置 false。胶囊出现条件 = 自带旋律 && 本标记。
    @State private var hasGeneratedImprovisation: Bool = false
    // didGenerateInCurrentGroup：当前组内用户是否点过生成（转调时区分"只是铺了原旋律" vs "已生成该组 solo"）
    @State private var didGenerateInCurrentGroup: Bool = false
    // Q4 八度盲听已定稿（2026-09-06）：真机对比后固定 Smooth（听感更佳）、放弃 Leaps(rooted)，调音台入口已封存。
    // 恢复 A/B 时：取消下行注释，并恢复 generateMeasuresWorker 的 octaveRaw 传参、注入，以及 BandMixerView 的 OCTAVE Menu。
    // @AppStorage("octaveModeRaw") private var octaveModeRaw: String = OctavePlacementMode.smooth.rawValue
    
    /// 根据当前分组，动态返回下拉算法列表
    private var currentAlgorithmList: [ImproAlgorithmType] {
        switch selectedAlgorithmGroup {
        case .guide:
            // Guide 组第二控件显示四档线条预设，不用语法列表（GuideLinePreset）
            return []
        case .basic:
            // Great Lick 放在两个基础练习之后（由 Master 组移入，Basic 免费、不走付费墙）
            return [.chordExercise, .colorTone, .Lick]
        case .master:
            // Master 下拉按【显示名字符长度由短到长】排序，长度相同再按字母序（稳定、可预测）；
            // 日后增删大师文法会自动按此规则排序，无需手写顺序。
            let masterList: [ImproAlgorithmType] = [.LeeMorgan, .charlieParker, .billEvans, .joePass,
                                                    .johnColtrane, .milesDavis, .cannonballAdderley,
                                                    .chetBaker, .redGarland]
            return masterList.sorted {
                let len0 = $0.rawValue.count, len1 = $1.rawValue.count
                if len0 != len1 { return len0 < len1 }
                return $0.rawValue < $1.rawValue
            }
        }
    }

    // MARK: - [方案21] 旋律可用性 + 统一显示源
    /// 当前选中歌曲是否带内置原曲旋律（无旋律=导入/iRealPro，不出现 Original/Solo 对照胶囊）
    /// 统一按歌曲取原旋律：先查内置 Classic Jazz，再查外部导入旋律索引。
    private func melody(for song: JazzSong) -> [GeneratedMeasure]? {
        // 内置 Classic Jazz：按歌曲对象 id 精确匹配（不会串到导入曲）
        if let m = builtinLibrary?.melody(for: song) { return m }
        // 外部导入旋律：只在“这首歌所属的那个歌单”里按 标题|作曲家 命中；
        // iRealPro 歌单从不提供旋律，同名 iRealPro 曲不会再错误挂上别的歌单的旋律。
        let key = dedupKey(for: song)
        if let owner = playlists.first(where: { $0.songs.contains { $0.id == song.id } })?.name {
            return externalMelodies[owner]?[key]
        }
        return nil
    }

    private var hasMelodyForCurrentSong: Bool {
        guard let s = selectedSong else { return false }
        return melody(for: s) != nil
    }

    /// 当前【真正用于显示/播放/高亮】的小节：
    /// - 正在对照「原旋律」(showOriginalMelody) 且本曲自带旋律、且已生成过即兴：按需从曲库取原旋律，
    ///   并按 selectedKey 整体半音转调（原旋律不缓存；方案21 R3：音符与和弦载体同步转）；
    /// - 其余情况（未生成即兴、或正在看 Solo）：返回生成缓存 generatedSolo（Guide/Basic/Master 结果，Transform/Color 照常作用其上）。
    /// 写入仍只写 generatedSolo；所有显示/播放/高亮读取点统一读本属性，保证切换显示时同源、不重新随机。
    private var displayedMeasures: [GeneratedMeasure] {
        if showOriginalMelody, hasGeneratedImprovisation, hasMelodyForCurrentSong,
           let s = selectedSong, let orig = melody(for: s) {
            if s.key != selectedKey {
                return MelodyTransformAdapter.transposeMeasures(
                    orig,
                    by: Self.semitoneDifference(from: s.key, to: selectedKey),
                    preferSharps: Self.isSharpKey(selectedKey))
            }
            return orig
        }
        return generatedSolo
    }

    // [方案21] 原 melody 专用失效函数 invalidateMelodyEmbellishIfNeeded 已删除：
    // Guide/Basic/Master 改乐手/圆点本就"下次点生成才生效"，不自动清结果（保证 Basic/Master 逐音行为不变）。


    
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

    /// [新增 2026-09-23] 只计算并返回某首歌在指定调下的级数分析（不改显示、不填休止）。
    /// 供「铺原旋律」分支选歌/转调时刷新 currentAnalysis，避免 #按钮显示上一首的陈旧分析。
    /// 与 generateEmptyRoadmap 的分析构建逻辑同源（过滤空/NC、带 section 标记、按调号显式主调）。
    private func buildSongAnalysis(forSong song: JazzSong, key: String) -> AnalysisResult {
        let workSong = (song.key == key) ? song : Self.transposeSong(song, to: key)
        let timeSig = workSong.timeSignature ?? "4/4"
        let tsNum = Int(timeSig.split(separator: "/").first ?? "4") ?? 4
        let roadmap = JazzRoadmap(title: workSong.title, tempo: workSong.tempo)
        for (measureIndex, measureChords) in workSong.measures.enumerated() {
            let measureDurations = measureIndex < workSong.measureDurations.count
                ? workSong.measureDurations[measureIndex] : [4.0]
            let pairs = zip(measureChords, measureDurations).filter { chord, _ in
                let clean = chord.trimmingCharacters(in: .whitespacesAndNewlines)
                return !clean.isEmpty && clean != "NC" && clean != "N.C."
            }
            for (chordName, duration) in pairs {
                let cleanChord = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
                let isSectionStart = workSong.sectionMarkers[measureIndex] != nil
                roadmap.append(block: ChordBlock(name: cleanChord, duration: duration,
                                                 isSectionStart: isSectionStart))
            }
        }
        let keyInfo = KeyParser.parseKey(key)
        return PostProcessorFull.analyze(roadmap: roadmap,
                                         tonicPC: keyInfo.tonicPC,
                                         mode: keyInfo.mode,
                                         beatsPerMeasure: Double(tsNum))
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

            // 小节内每个有效和弦 + 相对小节起点的 slot（拍数×120），供伴奏按段跟上小节内多和声
            var measureChordSlots: [(chord: String, startSlot: Int)] = []
            do {
                var accumulated = 0
                for (ci, ch) in measureChords.enumerated() {
                    let clean = ch.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty && clean != "NC" && clean != "N.C." {
                        measureChordSlots.append((chord: clean, startSlot: accumulated))
                    }
                    let d = ci < durations.count ? durations[ci] : 4.0
                    accumulated += Int(d * 120.0)
                }
            }
            
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
                slotsPerMeasure: slotsPerMeasure,
                chordSlots: measureChordSlots
            ))
        }
        
        // 🔍 诊断增强：模拟 VexFlow ticks 累加，检查每个小节是否合法
        #if DEBUG
        dprint("========== 小节 ticks 预检查 ==========")
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
                dprint("❌ 小节 \(mi+1) ticks 异常: 计算值=\(ticks) (目标=\(expectedTicks), diff=\(diff))")
                for (ni, n) in m.notes.enumerated() {
                    #if DEBUG
                    dprint("  音符\(ni): \(n.pitch) dur=\(n.duration) isTri=\(n.isTriplet)")
                    #endif
                }
            } else {
                #if DEBUG
                dprint("✅ 小节 \(mi+1) ticks=\(ticks) 合法")
                #endif
            }
        }
        #if DEBUG
        dprint("========================================")
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
    // MARK: - 🎵 Solo 生成（后台异步，不阻塞主线程）
    // [方案21] jumpToSolo=true：用户点生成键，生成后切到 Solo；false：转调重算，只刷新 Solo 缓存、不抢当前 Original/Solo 视图
    private func runJazzGenerationPipeline(jumpToSolo: Bool = true) {
        guard let song = selectedSong else { return }
        // 最底层保险：任何路径调用 Master 算法都必须先购买
        if selectedAlgorithmGroup == .master && !iapManager.isPurchased {
            pendingMasterAlgorithm = selectedAlgorithm
            showPaywall = true
            return
        }
        guard !isGenerating else { return }

        let key = selectedKey
        let algorithm = selectedAlgorithm
        let group = selectedAlgorithmGroup
        let guidePreset = selectedGuidePreset
        let transform = enableTransform
        let transformMusician = selectedTransformMusician  // [Hunk10] 两链共用所选乐手
        let colorRaw = colorModeRaw
        let guideColor = guideColorEnabled  // [Guide Color 圆点] 捕获到后台线程（仅 Guide 整流三态用）
        let grammarColor = grammarColorEnabled  // [Grammar Color 圆点 20260925] 捕获到后台线程（grammar spell-only 分流用）
        // Q4 定稿固定 Smooth，不再从 UI 读 octaveRaw（恢复 A/B 时取消注释并同步下方调用/签名/注入）
        // let octaveRaw = octaveModeRaw
        // 转调在主线程快速完成（纯值操作），重计算全部放后台
        let songToUse: JazzSong = (song.key == key) ? song : Self.transposeSong(song, to: key)

        generationTask?.cancel()
        isGenerating = true

        generationTask = Task.detached(priority: .userInitiated) { [self] in
            let result = self.generateMeasuresWorker(song: songToUse, key: key, group: group, algorithm: algorithm, guidePreset: guidePreset, enableTransform: transform, transformMusician: transformMusician, colorRaw: colorRaw, guideColorEnabled: guideColor, grammarColorEnabled: grammarColor)
            await MainActor.run {
                self.generatedSolo = result.measures
                self.soloVersion = UUID()
                self.currentAnalysis = result.analysis
                // [方案21] 任意组生成成功 → 标记"有即兴"（胶囊据此出现）；显式点生成跳 Solo，转调重算(jumpToSolo=false)保持当前视图
                self.hasGeneratedImprovisation = true
                if jumpToSolo { self.showOriginalMelody = false }
                self.isGenerating = false
                self.generationTask = nil
            }
        }
    }

    /// 重计算主体（纯函数，不触碰 @State；nonisolated 确保在后台线程执行）
    nonisolated private func generateMeasuresWorker(song: JazzSong, key: String, group: ImproAlgorithmGroup = .basic, algorithm: ImproAlgorithmType, guidePreset: GuideLinePreset = .smooth, enableTransform: Bool, transformMusician: String, colorRaw: String, guideColorEnabled: Bool = false, grammarColorEnabled: Bool = false) -> (measures: [GeneratedMeasure], analysis: AnalysisResult?) {  // [默认值翻转] grammarColorEnabled 旧默认 true 封存，现 false=Java spell-only
        let actualSong = song   // 调用方已完成转调
        let isGuide = (group == .guide)   // Guide Tone Line 分支：走引导音策略，不走 grammar 专属 mode/合并

        // 1. 初始化大脑 Roadmap
        let roadmap = JazzRoadmap(title: actualSong.title, tempo: actualSong.tempo)
        #if DEBUG
        dprint("🎵 小节数: \(actualSong.measures.count), 时值数组数: \(actualSong.measureDurations.count)")
        #endif
        for (i, m) in actualSong.measures.enumerated() {
            let d = actualSong.measureDurations[i]
            #if DEBUG
            dprint("小节 \(i): 和弦数 \(m.count), 时值数 \(d.count), 时值: \(d)")
            #endif
        }
        for (measureIndex, measureChords) in actualSong.measures.enumerated() {
            let measureDurations = actualSong.measureDurations[measureIndex]
            if isGuide {
                // [Guide F1] 保留 NC/N.C.（N.C. 归一为 NC）连同其时值，全 NC 小节也不跳过：
                // 引导音策略对 NC 产出"整段时长单个休止"(G7)，休止后下一和弦重起首音(G10)；
                // 若像 grammar 路径那样 filter 掉，会丢 slot、破坏小节对齐且 G10 永不触发。
                for (index, rawChord) in measureChords.enumerated() {
                    let cleanChord = rawChord.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanChord.isEmpty else { continue }
                    let duration = index < measureDurations.count ? measureDurations[index] : 4.0
                    let guideName = (cleanChord == "N.C.") ? "NC" : cleanChord
                    let isSectionStart = (index == 0) && (actualSong.sectionMarkers[measureIndex] != nil)
                    roadmap.append(block: ChordBlock(name: guideName, duration: duration, isSectionStart: isSectionStart))
                }
            } else {
            // 把和弦和对应的时值打包，然后过滤出有效和弦（Basic/Master 原逻辑逐字保留，硬回归不得改）
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
                #if DEBUG
                dprint("🔍 [ROADMAP] 小节\(measureIndex) 和弦\(index): \(cleanChord) duration=\(duration)拍")
                #endif
            }
            }
        }

        // 2. 🎯 根据选中算法构造策略 + 设置Transform模式
        // [Hunk10] 两条链路共用所选乐手：grammar 经此全局（Transform.swift 内读取 javaAlignedMusician），
        // guide 经下方 GuideTransformBridge 显式传参。生成有 !isGenerating 互斥，单条生成内无竞争。
        TransformEngine.javaAlignedMusician = transformMusician
        let activeStrategy: JazzImproStrategy?
        if isGuide {
            // [Guide F2] 走已与原版逐音对齐的引导音线策略；不触碰 grammar 专属的
            // transformMode/rectifyMode/colorMode/octaveMode（引导音策略没有这些属性）。
            let guideStrategy = ImproVisorOriginalGuideToneStrategy()
            guideStrategy.direction   = guidePreset.direction    // 四档：0 / +1 / -1 / 0
            guideStrategy.maxDuration = guidePreset.maxDuration  // 四档：240 / 240 / 240 / 120
            guideStrategy.startDegree = "1"                      // 显式起始级=1，不吃类自带 "3"
            guideStrategy.lowLimit    = 60                       // 显式音域 [60,79]（对齐原版高音谱默认）
            guideStrategy.highLimit   = 79                       // 不吃类自带 40–84
            // allowColor=true 是【有意偏离原版出厂 false】的更丰富产品形态：启用色彩音，
            // 该形态已在 288 矩阵+29 首(18470 音)与 blind2 四档逐音 1:1 验证。
            // 绑定约束：色彩音取自词汇表 color 集合，必须与 useGuideToneVocabulary=true 同批
            // （旧族级 color 覆盖仅 47–83%，只开色彩而不翻词汇表会取错音）。
            guideStrategy.allowColor  = true
            activeStrategy = guideStrategy
        } else {
        // [LSTM P1] DEBUG 调试分支可改走 LSTM（默认关）；Release 恒 false、正常用户路径走不到。
        #if DEBUG
        let useLSTM = LSTMDebugSwitch.useLSTM
        #else
        let useLSTM = false
        #endif
        if useLSTM {
            activeStrategy = LSTMStrategy()
        } else {
        guard let grammarStrategy = algorithm.getStrategyInstance() else { return ([], nil) }
        grammarStrategy.transformMode = enableTransform ? .grammarWithTransform : .rawGrammar
        // 整流固定为全拍对齐原版（三档逻辑保留在 GrammarLickGlue，调试可在此改 .strongBeat/.off）
        // [Grammar Color 圆点 20260925] 圆点 ON（默认）→ .allBeats 一音不变；OFF → .javaSpellOnly（Java 出厂 spell-only）
        grammarStrategy.rectifyMode = grammarColorEnabled ? .allBeats : .javaSpellOnly
        grammarStrategy.colorMode = ColorPaletteMode(rawValue: colorRaw) ?? .conservative
        // Q4 盲听定稿（2026-09-06）：固定 Smooth（就近上一音，真机听感更佳）；Leaps/rooted 已放弃、算法保留备查。
        grammarStrategy.octaveMode = .smooth
        activeStrategy = grammarStrategy
        }
        }
        var analysis: AnalysisResult? = nil   // 🌟 调性分析结果，通过返回值带回主线程
        
        // ── 排版兜底：生成 Solo 后检查 Slot 守恒，不通过则重新生成（最多 5 次）──
        let maxRetries = 5
        var retryCount = 0
        var finalMeasures: [GeneratedMeasure] = []   // 🌟 P0-1: 暂存最终结果，循环结束后返回主线程
        var finalPhysicalNotes: [PhysicalNote] = []
        var hasLayoutWarning = false
        var hasCrossGrid = false
        var hasOrphanTie = false

        // ⏱️ 性能分析: 管线总起点
        let perfPipelineStart = CFAbsoluteTimeGetCurrent()
        var perfTotalGenTime: Double = 0
        var perfTotalPostTime: Double = 0

        repeat {
            if Task.isCancelled { break }   // 🌟 P0-1: 支持后台任务取消（离开页面/切歌时立即停止重试）
            // ⏱️ 单次 generateSolo 耗时
            let perfGenStart = CFAbsoluteTimeGetCurrent()
            // [方案21] 原 melody 物理化分支已删：Guide/Basic/Master 统一由策略生成。
            let physicalNotes: [PhysicalNote] = activeStrategy!.generateSolo(for: roadmap)
            var producedNotes = physicalNotes
            // [Hunk10] Guide & Transform：圆点开时，对 08 单线骨架走【同一套】Java 对齐通用内核加花，
            // 并走 guide 专用 spell-only 整流；圆点关时 producedNotes==骨架，08 单线逐音不变（不经过桥）。
            // 接桥在重试循环内：每次重试都用 SystemTransformRNG 取新种子，符合"每次生成可复现记录种子"的设计。
            if isGuide && enableTransform {
                // [Guide Color 圆点] 三态：圆点关→.off(spell-only，出厂)；点亮→按 COLOR 下拉 conservative/full
                let gColor: GuideRectifyColorMode = {
                    guard guideColorEnabled else { return .off }
                    return (ColorPaletteMode(rawValue: colorRaw) == .full) ? .full : .conservative
                }()
                producedNotes = GuideTransformBridge.apply(
                    producedNotes,
                    chordBlocks: roadmap.flattenRoadmap(),
                    musician: transformMusician,
                    mode: .randomized(SystemTransformRNG()),
                    rectifyColorMode: gColor)
            }
            finalPhysicalNotes = producedNotes
            let perfGenElapsed = (CFAbsoluteTimeGetCurrent() - perfGenStart) * 1000
            perfTotalGenTime += perfGenElapsed

            // ⏱️ 单次后处理(量化+排版+校验)耗时
            let perfPostStart = CFAbsoluteTimeGetCurrent()

            // [Guide F3] 引导音跨和弦同音在原版是两个独立音头/符头，不做相邻同音合并
            // （33 首实测 md240 有 14.8%、md120 有 8.8% 相邻同音，合并会与原版逐音不一致）；
            // Basic/Master 仍走原兜底合并（approach 碎片渲染需要）。
            if !isGuide {
                finalPhysicalNotes = LightPostProcessor.mergeAdjacent(finalPhysicalNotes)  // 兜底相邻同音合并，防止渲染分裂
            }


        //dprint("🎼 [架构日志] 策略选择: \(activeStrategy.name) | 成功生成物理音符数: \(finalPhysicalNotes.count)")
        
       // 🌟 诊断探针：拦截并打印被 VexFlow 屠宰前的原始物理时值
        //dprint("==================================================")
        //dprint("🕵️‍♂️ [底层数据透视] 准备切割的小节总数: \(actualSong.measures.count)")
        let rawDurations = finalPhysicalNotes.map { String($0.durationSlots) }.joined(separator: ", ")
        //dprint("⏱️ 所有原始物理音符的时值数组 (Slots):")
        //dprint("[\(rawDurations)]")
        //dprint("==================================================")
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
                //dprint("【PhysicalNote来到CV】 type=\(type(of: pNote)) midi=\(pNote.midiPitch) terminalType=\(pNote.terminalType ?? "nil")")
                globalEnriched.append(EnrichedNote(midiPitch: pNote.midiPitch, durationSlots: pNote.durationSlots, gracePitches: pendingGraces, terminalType: pNote.terminalType))
                // 🔍 排查日志: EnrichedNote透传
                //dprint("【EnrichedNote透传】 midi=\(pNote.midiPitch) terminalType=\(pNote.terminalType ?? "nil")")
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
        // [2026-09-23 弱起对齐补丁·新增] 前置空小节（pickup）数量：这些小节不占 roadmap 内容，
        // 引擎 solo 从首个真和弦小节起算；切分时前 pickup 小节整小节补休止、不消费生成流，
        // 使引擎栏 k 落进显示小节 k+pickup（与级数分析、整流和弦上下文对齐）。
        let pickupMeasureCount = SongMeasureMap.leadingPickupCount(actualSong.measures)

        var pendingTie = false // 🌟 恢复跨小节连线状态追踪！
        var measurePendingTie: [Bool] = [] // 🔍 TIE BUG 追踪：捕获每小节进入时的 pendingTie

        // [旧码封存 2026-09-23] 原循环表头不感知弱起，导致 32 栏 solo 被切进 33 小节、整体左移：
        // for _ in 0..<totalMeasures {
        for mIndex in 0..<totalMeasures {
            measurePendingTie.append(pendingTie) // 🔍 快照：进入本小节前的跨小节连线状态
            // [2026-09-23 弱起对齐补丁·新增] 弱起小节：生成内容不覆盖，整小节休止，不消费 globalEnriched
            if mIndex < pickupMeasureCount {
                measureRawChunks.append([EnrichedNote(midiPitch: -1,
                                                      durationSlots: profile.slotsPerMeasure,
                                                      gracePitches: [])])
                continue
            }
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
            // [Guide F3] 量化层等长同音合并同样跳过（保留两个独立符头）；跨小节连线由上方切片阶段处理，不依赖此合并
            let mergedNotes = isGuide ? quantizedNotes : GridQuantizer.mergeAdjacentEnriched(quantizedNotes)
            let splitNotes = GridQuantizer.splitCrossBeatDots(mergedNotes, beatSize: 120)
            // 调试：步骤 S - splitCrossBeatDots 后（跨拍拆分后 tie 快照）
            if measurePendingTie[measureIndex] && (rawChunks.first?.isRest ?? false) {
                #if DEBUG
                dprint("⚠️ [TIE BUG 追踪] 小节 \(measureIndex+1) - 步骤 S：splitCrossBeatDots 后")
                #endif
                for (si, sn) in splitNotes.enumerated() {
                    #if DEBUG
                    dprint("  音符 \(si): pitch=\(sn.midiPitch), dur=\(sn.durationSlots), isTieStart=\(sn.isTieStart), isTieEnd=\(sn.isTieEnd)")
                    #endif
                }
            }
            // 🔍 排查日志: 量化后音符terminalType
            for (qi, qn) in splitNotes.enumerated() {
                //dprint("【量化后音符】 idx=\(qi) midi=\(qn.midiPitch) terminalType=\(qn.terminalType ?? "nil")")
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
                // 非和弦音 → 色彩音优先（绿 > 蓝）：趋近音验证通过后，
                // 是色彩音→标绿，是避免音→标蓝；趋近音验证失败→用 groundTruth
                else if noteTag == .approachNote {
                    // terminalType=="A" 的趋近音：级进验证（≤2半音）
                    if let nextPitch = nextNonRestPitch, isStepwiseApproach(qNote.midiPitch, nextPitch) {
                        // 趋近音验证通过：色彩音优先（绿 > 蓝）
                        if case .colorTone = groundTruth {
                            noteTag = .colorTone  // 色彩音+趋近音 → 绿色
                        } else {
                            // 保留趋近音标签(蓝色) — 避免音+趋近音
                        }
                    } else {
                        noteTag = groundTruth
                    }
                } else {
                    // 非 A 终端（X/L/S 等）：声学趋近检测
                    // 若与下一非休止音 ±1 半音级进（对齐 Java Note.adjacentPitch）即趋近；
                    // 方案甲：合法落点对齐吸附层 / Java RectifyPitchesCommand 的 usableTones =
                    // 和弦音 + 色彩音（spell + color）——下一音是和弦音【或色彩音】都算解决，
                    // 因此"半音蹭到绿色彩音"的外音标为蓝色趋近，而不是红色避免音（看到=听到）。
                    // 注意：跨和弦趋近可能漏判（此处检查当前和弦 activeChord，rectify 检查下一音位置和弦），本次不动。
                    if let nextPitch = nextNonRestPitch,
                       abs(nextPitch - qNote.midiPitch) == 1 {
                        let nextTag = detectMusicTheoryTag(midiPitch: nextPitch, chordName: activeChord)
                        if nextTag == .chordTone || nextTag == .colorTone {
                            // 声学趋近音验证通过：色彩音优先（绿 > 蓝）
                            if case .colorTone = groundTruth {
                                noteTag = .colorTone  // 自身就是色彩音+趋近 → 绿色
                            } else {
                                noteTag = .approachNote  // 避免音半音解决到和弦/色彩音 → 蓝色趋近
                            }
                        } else {
                            noteTag = groundTruth
                        }
                    } else {
                        noteTag = groundTruth
                    }
                }
                
                // 🔍 排查日志（诊断"色彩音被标蓝"：蓝趋近/红外音都打印判色所用和弦与时间窗，零行为改动）
                if noteTag == .foreignTone || noteTag == .chordTone || noteTag == .approachNote {
                    let groundTruth2 = detectMusicTheoryTag(midiPitch: qNote.midiPitch, chordName: activeChord)
                    #if DEBUG
                    let dbgPC = ((qNote.midiPitch % 12) + 12) % 12
                    let dbgWindows = chordStartSlots.map { "\($0.chord)@\($0.startSlot)" }.joined(separator: ",")
                    dprint("🔍 [TAG-TRACE] midi=\(qNote.midiPitch) pc=\(dbgPC) activeChord=\(activeChord) slotInMeasure=\(currentSlotsInMeasure) windows=[\(dbgWindows)] terminal=\(qNote.terminalType ?? "nil") next=\(nextNonRestPitch.map(String.init) ?? "nil") → tag=\(noteTag) groundTruth=\(groundTruth2)")
                    #endif
                }
                //dprint("【最终输出音符】 和弦=\(activeChord) midi=\(qNote.midiPitch) terminalType=\(qNote.terminalType ?? "nil") → tag=\(noteTag)")
                
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
                slotsPerMeasure: slotsPerMeasure,
                chordSlots: chordStartSlots
            ))
        }

        // ==============================================================
        // 🌟 联合探针：出厂前全景核对单 (采用无损 Slots 核验)
        //dprint("\n================ 🎼 Swift端: 乐谱生成最终核对清单 ================")
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
            dprint("小节 \(mi + 1) | 总 Slots: \(totalSlots)")
            #endif
            #if DEBUG
            dprint("  ↳ 音符 (\(measure.notes.count)个): \(noteDetails.joined(separator: ", "))")
            #endif

            if totalSlots != profile.slotsPerMeasure {
                dprint("  ❌ [排版警告] 本小节 Slots 不守恒！偏差: \(totalSlots - profile.slotsPerMeasure)")
                hasLayoutWarning = true
            }
        }
        #if DEBUG
        dprint("==============================================================\n")
        #endif
        
        // 🔍 跨网格 tie 检测——异常时触发重试
        if hasCrossGridTie(in: tempMeasures) {
            #if DEBUG
            dprint("⚠️ [跨网格tie] 检测到跨网格延音线，第 \(retryCount + 1) 次重试")
            #endif
            hasCrossGrid = true
        }
        
        // 🔍 悬挂 tie 检测——异常时触发重试
        if hasOrphanTieStart(in: tempMeasures) {
            #if DEBUG
            dprint("⚠️ [悬挂tie] 检测到悬挂延音线，第 \(retryCount + 1) 次重试")
            #endif
            hasOrphanTie = true
        }
        
        // ── 级数分析：生成调性分析数据（复用已构建的 roadmap，用歌曲调号作为显式主调）──
        // [Guide F4] 级数分析红线：PostProcessorFull 假设 NC 已在构建前过滤（见其 NOCHORD 注释）。
        // Guide 的生成 roadmap 保留了 NC，故分析另用一条剔除 NC 的副本；非 Guide 的 roadmap 本就无 NC，原样传入（硬回归零变化）。
        // 另：选歌/转调时的空谱分析在 generateEmptyRoadmap()，那里本就自建过滤 roadmap，无需改动。
        let analysisRoadmap: JazzRoadmap
        if isGuide {
            let filtered = JazzRoadmap(title: roadmap.title, tempo: roadmap.tempo)
            for block in roadmap.flattenRoadmap() where block.name != "NC" { filtered.append(block: block) }
            analysisRoadmap = filtered
        } else {
            analysisRoadmap = roadmap
        }
        let keyInfo = KeyParser.parseKey(key)
        analysis = PostProcessorFull.analyze(
            roadmap: analysisRoadmap,
            tonicPC: keyInfo.tonicPC,
            mode: keyInfo.mode,
            beatsPerMeasure: Double(tsNum)
        )
        
        // 🌟 全局反向趋近音推导（对齐 Java Coloration.determineColor 反向推导机制）
        // 正向遍历所有音符：如果当前音是和弦音/色彩音(approachable)，
        // 且前一个非休止符与当前音半音相邻(±1半音)，且前一音不是和弦音，
        // 且前一音在反拍上（正拍/强拍不标趋近音，对齐 Java Generator.offbeat gate），
        // 则把前一音标记为趋近音(蓝色)——即使它原本是避免音/外音。
        // 这解决了"非A终端生成的音在音高关系上起到趋近音作用却被标为避免音"的问题。
        let slotsPerBeat = 120  // 一拍=四分音符=120 slots
        let strongBeatsPerMeasure = tsNum <= 3 ? 1 : (tsNum % 2 == 0 ? 2 : (tsNum % 3 == 0 ? 3 : 1))
        let totalSlotsPerMeasure = tempMeasures.first?.slotsPerMeasure ?? 480
        let timeBetweenStrongBeats = totalSlotsPerMeasure / strongBeatsPerMeasure
        
        var prevNonRest: (measureIdx: Int, noteIdx: Int, midi: Int, isOffBeat: Bool)? = nil
        for mi in 0..<tempMeasures.count {
            var slotInMeasure = 0  // 当前音符在小节内的 slot 位置
            for ni in 0..<tempMeasures[mi].notes.count {
                let note = tempMeasures[mi].notes[ni]
                let noteSlots = durationToSlots(note.duration) ?? 60
                
                if !note.isRest {
                    let currMidi = midiNumber(from: note.pitch) ?? -1
                    if currMidi >= 0 {
                        // 拍位判断：正拍(slot%120==0) 或 强拍 → 不标趋近音
                        let isOnBeat = slotInMeasure % slotsPerBeat == 0
                        let isStrongBeat = slotInMeasure % timeBetweenStrongBeats == 0
                        let isOffBeat = !isOnBeat && !isStrongBeat
                        
                        // 当前音是和弦音或色彩音 → 检查前一个非休止符是否半音趋近
                        // 且前一个音必须在反拍上
                        if note.tag == .chordTone || note.tag == .colorTone {
                            if let prev = prevNonRest,
                               prev.isOffBeat,
                               abs(prev.midi - currMidi) == 1 {
                                // 2026-09-06 修复（色彩音优先，绿>蓝）：
                                // 反向回填只应作用于【真正的外音/避免音(foreign)】。原条件只排除了和弦音，
                                // 没排除色彩音，导致主判定(L874/L894)已正确标绿的色彩音（如 B7 的 11 音 E，
                                // 半音蹭向五音 F#），仅因"在反拍+半音趋近"就被覆盖成蓝色趋近音，与主判定
                                // "色彩音优先"自相矛盾。现同时排除 colorTone：合法色彩音保持绿色，
                                // 只有外音半音解决到稳定音时才回填为蓝色趋近。
                                let prevTag = tempMeasures[prev.measureIdx].notes[prev.noteIdx].tag
                                if prevTag != .chordTone && prevTag != .colorTone {
                                    tempMeasures[prev.measureIdx].notes[prev.noteIdx].tag = .approachNote
                                }
                            }
                        }
                        
                        prevNonRest = (mi, ni, currMidi, isOffBeat)
                    }
                }
                slotInMeasure += noteSlots
            }
        }

        // ⏱️ 后处理耗时结束
        let perfPostElapsed = (CFAbsoluteTimeGetCurrent() - perfPostStart) * 1000
        perfTotalPostTime += perfPostElapsed

        finalMeasures = tempMeasures   // 🌟 P0-1: 暂存本次结果，循环结束后通过返回值带回主线程

        retryCount += 1
        } while (hasLayoutWarning || hasCrossGrid || hasOrphanTie) && retryCount < maxRetries

        // ⏱️ 性能分析: 管线总耗时 + 重试次数
        let perfPipelineElapsed = (CFAbsoluteTimeGetCurrent() - perfPipelineStart) * 1000
        dprint("⏱️ [PERF] === 管线总览 === 总耗时: \(String(format: "%.1f", perfPipelineElapsed))ms | " +
              "重试次数: \(retryCount)/\(maxRetries) | " +
              "generateSolo累计: \(String(format: "%.1f", perfTotalGenTime))ms | " +
              "后处理累计: \(String(format: "%.1f", perfTotalPostTime))ms | " +
              "最终音符数: \(finalPhysicalNotes.count) | " +
              "layoutWarning: \(hasLayoutWarning) crossGrid: \(hasCrossGrid) orphanTie: \(hasOrphanTie)")
        return (finalMeasures, analysis)
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
                                builtinPlaylistName: builtinLibrary?.name,
                                onDeleteBuiltinSong: { song in hideBuiltinSong(song) },
                                onHideBuiltinPlaylist: { name in hideBuiltinPlaylist(named: name) },
                                onRestoreBuiltinPlaylist: { restoreBuiltinPlaylist() },
                                importedPlaylistNames: Set(importedPlaylists.map { $0.name }),
                                onDeleteImportedGroup: { name in deleteImportedGroup(named: name) },
                                trashItems: trashItems,
                                onMoveSongToTrash: { song, pl in moveSongToTrash(song, from: pl) },
                                onClearMySongs: { clearMySongsToTrash() },
                                onRestoreTrashItem: { item in restoreTrashItem(item) },
                                onDeleteTrashItem: { item in permanentlyDeleteTrashItem(item) },
                                onEmptyTrash: { emptyTrash() }
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
                                builtinPlaylistName: builtinLibrary?.name,
                                onDeleteBuiltinSong: { song in hideBuiltinSong(song) },
                                onHideBuiltinPlaylist: { name in hideBuiltinPlaylist(named: name) },
                                onRestoreBuiltinPlaylist: { restoreBuiltinPlaylist() },
                                importedPlaylistNames: Set(importedPlaylists.map { $0.name }),
                                onDeleteImportedGroup: { name in deleteImportedGroup(named: name) },
                                trashItems: trashItems,
                                onMoveSongToTrash: { song, pl in moveSongToTrash(song, from: pl) },
                                onClearMySongs: { clearMySongsToTrash() },
                                onRestoreTrashItem: { item in restoreTrashItem(item) },
                                onDeleteTrashItem: { item in permanentlyDeleteTrashItem(item) },
                                onEmptyTrash: { emptyTrash() }
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
                        // [方案19] 此处只判断"有无内容"来决定是否逼 WebView 重排，不读取具体音，
                        // 故保持读缓存 generatedSolo（原旋律态 L1770 也写入它、同样非空）；不改读 displayedMeasures。
                        if !generatedSolo.isEmpty {
                            soloVersion = UUID()
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            // 和弦音/色彩音字典：右边缘向左滑呼出（与左侧曲目栏镜像对称，不占用工具栏、不压五线谱 WebView 滚谱）
            .overlay(alignment: .trailing) {
                ZStack(alignment: .trailing) {
                    if showChordDictionary {
                        Color.black.opacity(0.22)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.22)) { showChordDictionary = false }
                            }
                            .transition(.opacity)
                        Group {
                            if geometry.size.width < 1000 {
                                // 竖屏 iPad / 紧凑分屏：全屏页，避免左侧露出一条乐谱
                                ChordDictionaryView(isPresented: $showChordDictionary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                // 横屏 iPad：右侧抽屉，留出左侧乐谱上下文（五列内容，适当加宽）
                                ChordDictionaryView(isPresented: $showChordDictionary)
                                    .frame(width: min(780, geometry.size.width * 0.96))
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        .background(Color(.systemGroupedBackground))
                        .shadow(color: Color.black.opacity(0.18), radius: 18, x: -4, y: 0)
                        .transition(.move(edge: .trailing))
                    } else {
                        // 仅屏幕右边缘热区；垂直方向排除顶部导航栏与底部控制栏（56pt），
                        // 避免边缘手势拦截底部 Solo 生成等按钮的点击（mini6 真机手指接触面积大易误触发）
                        EdgePanProxy(edge: .right) {
                            withAnimation(.easeInOut(duration: 0.25)) { showChordDictionary = true }
                        }
                        .frame(width: 24)
                        .padding(.top, 60)
                        .padding(.bottom, 76)
                        .ignoresSafeArea()
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: showChordDictionary)
            }
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
                    // 统一入口：仅 1 首且无歌单名→My Songs；否则同名分组合并、新名字建组
                    let outcome = importSongsUnified(songs, proposedName: name)
                    importSkippedCount = outcome.skipped
                    importedTotalCount = outcome.newSongs.count
                    mixedAlertCount = outcome.newSongs.filter { $0.hasMixedTimeSignature }.count

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
                } else if let note = importReportNote {
                    Text(note)
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
            // 音频中断（来电/Siri/闹钟）或耳机拔出时，同步播放按钮状态（与用户手动点暂停同语义）
            JazzMidiPlayer.shared.onExternalPlaybackChange = { isPlaying, isPaused in
                self.isPlaying = isPlaying
                self.isPaused = isPaused
            }
            installBuiltinPlaylistIfNeeded()   // 把 Classic Jazz 追加到 My Songs 之后
            installImportedPlaylistsIfNeeded() // 用户导入的命名歌单排在 Classic Jazz 之后
            loadExternalMelodies()             // 重建外部导入旋律索引
            if selectedSong == nil {
                selectedSong = currentPlaylist.songs.first
            }
            if let song = selectedSong {
                tempo = song.tempo
                selectedKey = song.key
                selectedStyle = matchStyleMode(from: song.style)
            }
        }
        #if DEBUG
        .task {
            // [LSTM P1] DEBUG-only 测试钩子：仅当启动参数含 -lstm / -autogen 时动作，正常路径惰性。
            let dbgArgs = ProcessInfo.processInfo.arguments
            if dbgArgs.contains("-lstm") {
                LSTMDebugSwitch.useLSTM = true
                debugLSTM = true
            }
            if dbgArgs.contains("-landscape") {
                DebugOrientationDelegate.forceLandscapeIfNeeded()
            }
            if let si = dbgArgs.firstIndex(of: "-song"), si + 1 < dbgArgs.count {
                let needle = dbgArgs[si + 1]
                installBuiltinPlaylistIfNeeded()
                var found = playlists.flatMap({ $0.songs }).first(where: { ($0.title ?? "").localizedCaseInsensitiveContains(needle) })
                if found == nil {
                    for _ in 0..<20 {
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        installBuiltinPlaylistIfNeeded()
                        found = playlists.flatMap({ $0.songs }).first(where: { ($0.title ?? "").localizedCaseInsensitiveContains(needle) })
                        if found != nil { break }
                    }
                }
                if let match = found {
                    selectedSong = match
                    tempo = match.tempo
                    selectedKey = match.key
                }
            }
            if dbgArgs.contains("-autogen") {
                for _ in 0..<30 where selectedSong == nil {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
                let jumpToSolo: Bool = !dbgArgs.contains("-showoriginal")
                runJazzGenerationPipeline(jumpToSolo: jumpToSolo)
            }
        }
        #endif
        .onDisappear {
            generationTask?.cancel()   // 🌟 P0-1: 离开页面时取消后台生成，避免白跑
        }
        .onChange(of: selectedSong) { newSong in
            if let song = newSong {
                // [方案21] 换曲：尚无新即兴→胶囊隐藏，默认看原旋律，重置本组已生成标记
                self.hasGeneratedImprovisation = false
                self.showOriginalMelody = true
                self.didGenerateInCurrentGroup = false
                tempo = song.tempo
                selectedKey = song.key
                selectedStyle = matchStyleMode(from: song.style)

                JazzMidiPlayer.shared.stop()
                playingNoteId = ""
                activeMidiNotes = []

                // 🌟 新增2：顺手修复切歌时的 UI 播放按钮状态残留 Bug
                self.isPlaying = false
                self.isPaused = false

                if let builtinMelody = melody(for: song) {
                    // 内置 Classic Jazz：直接铺原曲旋律（自带和弦），选完即可看、即可播放，不走骨架/算法
                    self.generatedSolo = builtinMelody
                    self.hasGeneratedSolo = true   // 让播放控制可用（它们只认这个开关）
                    self.isShowingBuiltinMelody = true
                    self.soloVersion = UUID()
                    // [新增 2026-09-23] 铺原旋律分支此前不刷新级数，#按钮会显示上一首的陈旧分析；此处按本曲重建
                    self.currentAnalysis = self.buildSongAnalysis(forSong: song, key: self.selectedKey)
                } else {
                    // 用户导入的 iRealPro 歌：维持现状——先出和弦骨架，等用户点生成
                    self.isShowingBuiltinMelody = false
                    self.hasGeneratedSolo = false
                    self.generateEmptyRoadmap()
                }
            }
        }
        .onChange(of: selectedKey) { newKey in
            if let originalKey = selectedSong?.key, newKey != originalKey {
                // [方案21] 三组统一：已在本组生成→按新调重算 Solo 缓存（不抢当前 Original/Solo 视图）；
                // 只铺了原旋律未生成→整数半音转原旋律（R3：音符与和弦载体同步转）；纯骨架→刷新骨架。
                if didGenerateInCurrentGroup {
                    // Guide/Basic/Master 已在本组点过生成 → 重跑对应算法（Transform 开则取新随机，属既有行为）
                    runJazzGenerationPipeline(jumpToSolo: false)
                } else if let s = selectedSong, let orig = melody(for: s) {
                    // 仅铺了内置原旋律、从未在本组生成 → 转原旋律继续铺，不跳成 guide/grammar solo
                    let semis = Self.semitoneDifference(from: originalKey, to: newKey)
                    self.generatedSolo = MelodyTransformAdapter.transposeMeasures(
                        orig, by: semis, preferSharps: Self.isSharpKey(newKey))
                    self.soloVersion = UUID()
                    // [新增 2026-09-23] 原旋律未生成即转调：级数同步换到新调（与选歌分支同根因的对称路径）
                    self.currentAnalysis = self.buildSongAnalysis(forSong: s, key: newKey)
                } else {
                    // 只是一张骨架谱：转调后仅刷新和弦骨架（原行为）
                    generateEmptyRoadmap()
                }
            }
        }
        .onChange(of: tempo) { newTempo in
            // 实时调整播放速度（播放中也能调）
            JazzMidiPlayer.shared.setTempo(Double(newTempo))
        }
        // [方案21] 原 4 个 melody 加花失效 onChange（乐手/圆点/色彩档变化即回退原旋律）已删除：
        // Guide/Basic/Master 改这些设置统一"下次点生成生效"，不自动清当前结果。
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
    
    // MARK: - 🌟 P0-2 触觉反馈（工具栏按钮用）
    private func triggerImpactHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    // MARK: - 顶部工具栏
    private var topToolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                // ===== 左栏 280pt =====
                if horizontalSizeClass != .compact {
                HStack(spacing: 12) {
                    Button(action: {
                        triggerImpactHaptic(.light)   // 🌟 P0-2
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSidebar.toggle()
                        }
                    }) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(showSidebar ? .accentColor : .secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    
                    Text(selectedSong?.title ?? NSLocalizedString("未选择歌曲", comment: ""))
                        .font(.system(size: sidebarAsOverlay ? (isVerySmallScreen ? 13 : 14) : 15, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        // P2 工具栏紧凑化：竖屏收窄歌名（标签尺寸均不变），为右侧播放/生成键腾位；mini 80、11寸竖 96
                        .frame(width: sidebarAsOverlay ? (isVerySmallScreen ? 80 : 96) : nil, alignment: .leading)
                }
                .padding(.horizontal, 18)
                .frame(width: sidebarAsOverlay ? nil : 280, alignment: .leading)
                }
                
                // ===== 右栏 =====
                HStack(spacing: 12) {
                if selectedSong != nil {
                    // 算法组
                    HStack(spacing: 12) {
                    // 算法组：Guide/Basic/Master 下拉（宽度沿用 segmentedControlMaxWidth，零横向增长）
                    Menu {
                        ForEach([ImproAlgorithmGroup.guide, .basic, .master], id: \.self) { grp in
                            Button {
                                selectedAlgorithmGroup = grp
                                // [方案21] 切到新组即视为新组未生成：三个标记一并重置，转调分支判断才干净；胶囊隐藏直到新组生成
                                didGenerateInCurrentGroup = false
                                hasGeneratedImprovisation = false
                                showOriginalMelody = true
                                // 仅当当前选中算法不属于目标组时才回退到该组第一项（保留用户在 Master/Basic 的已选）；
                                // guide 无语法列表，不回退
                                if grp != .guide {
                                    let targetList = currentAlgorithmList
                                    if !targetList.contains(selectedAlgorithm) {
                                        selectedAlgorithm = targetList.first ?? .chordExercise
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(grp.rawValue)
                                    if grp == selectedAlgorithmGroup { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedAlgorithmGroup.rawValue)
                                .font(.system(size: labelFontSize, weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down").font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: segmentedControlMaxWidth)
                    }
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(6)
                    .frame(maxWidth: segmentedControlMaxWidth)
                    .layoutPriority(0)
                    
                    if selectedAlgorithmGroup == .guide {
                        // Guide 组：第二控件=四档线条预设（免费，无锁；样式宽度与语法 Menu 一致）
                        Menu {
                            ForEach(GuideLinePreset.allCases, id: \.self) { preset in
                                Button {
                                    selectedGuidePreset = preset
                                } label: {
                                    HStack {
                                        Text(preset.fullDisplayName)
                                        if preset == selectedGuidePreset { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing:4) {
                                Text(selectedGuidePreset.shortName)
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
                    } else {
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
                    } // 第二控件按组切换（Guide 预设 / Basic-Master 语法）
                    // P2：保留算法组弹性（窄屏时保护算法 Menu 不被压缩截断），其宽度由收窄歌名+生成键右边距腾出
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
                    // [方案19] 不再因"正在看内置原旋律"禁用转调：原旋律/即兴均跟随 selectedKey
                    // （Melody 走 pipeline 转原旋律或重加花；Guide/Basic/Master 未生成时转原旋律，见 onChange(selectedKey)）

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
                
                // 播放控制——常驻（P2b：三键间距 12→16，略微松开、降低相邻误触）
                HStack(spacing: 16) {
                    Button(action: {
                        triggerImpactHaptic(.light)   // 🌟 P0-2
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
                                          measureIndex < self.displayedMeasures.count,
                                          noteIndex < self.displayedMeasures[measureIndex].notes.count else { return }
                                    let note = self.displayedMeasures[measureIndex].notes[noteIndex]
                                    if !note.isRest, let midi = self.midiNumber(from: note.pitch) {
                                        self.activeMidiNotes = [midi]
                                    } else {
                                        self.activeMidiNotes = []
                                    }
                                }
                            }
                            JazzMidiPlayer.shared.playWithAccompaniment(
                                solo: displayedMeasures,   // [方案19] 播放跟随当前显示源（原旋律/即兴）
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
                            .foregroundColor(hasGeneratedSolo && !displayedMeasures.isEmpty && !(isPlaying && !isPaused) ? .accentColor : .gray)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(isPlaying && !isPaused || !hasGeneratedSolo || displayedMeasures.isEmpty)
                    
                    Button(action: {
                        triggerImpactHaptic(.light)   // 🌟 P0-2
                        JazzMidiPlayer.shared.pause()
                        isPaused = true
                        isPlaying = false
                    }) {
                        Image(systemName: "pause.fill")
                            .font(.title3)
                            .foregroundColor(isPlaying && hasGeneratedSolo && !displayedMeasures.isEmpty ? .accentColor : .gray)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(!isPlaying || !hasGeneratedSolo || displayedMeasures.isEmpty)
                    
                    Button(action: {
                        triggerImpactHaptic(.light)   // 🌟 P0-2
                        JazzMidiPlayer.shared.stop()
                        isPlaying = false
                        isPaused = false
                        playingNoteId = ""
                        startMeasureIndex = 0
                        activeMidiNotes = []
                    }) {
                        Image(systemName: "stop.fill")
                            .font(.title3)
                            .foregroundColor(hasGeneratedSolo && !displayedMeasures.isEmpty ? .accentColor : .gray)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(!hasGeneratedSolo || displayedMeasures.isEmpty)
                }

            // 🌟 P0-2: 分隔线左右留白 12→8，为生成键 44pt 热区腾水平空间（纯装饰，不影响信息控件）
            Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 1, height: 22).padding(.horizontal, 8)
            #if DEBUG
            Button(action: {
                debugLSTM.toggle()
                LSTMDebugSwitch.useLSTM = debugLSTM
            }) {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundColor(debugLSTM ? .green : .gray)
            }
            .buttonStyle(PressableButtonStyle())
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            #endif

            Button(action: {
                triggerImpactHaptic(.medium)   // 🌟 P0-2
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
                self.didGenerateInCurrentGroup = true   // [方案19] 标记本组已生成（转调时据此决定重跑算法 vs 转原旋律）
                self.isShowingBuiltinMelody = false   // 进入即兴态，解除原曲态的转调禁用
                self.runJazzGenerationPipeline()
            }) {
                Image(systemName: "wand.and.stars")
                    .font(.title3)
                    .foregroundColor(selectedSong == nil ? .gray : .orange)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(selectedSong == nil || isGenerating)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            // P2b：竖屏生成键离右边缘 16pt（在 P2 的 20 基础上向右回移一点点，仍不贴边），横屏维持 8
            .padding(.trailing, toolbarSize.height > toolbarSize.width ? 16 : 8)
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
            solo: displayedMeasures,   // [方案19] 渲染跟随当前显示源（原旋律/即兴）
            playingNoteId: playingNoteId,
            soloVersion: soloVersion,
            key: selectedKey,
            timeSignature: selectedSong?.timeSignature ?? "4/4",
            grammarFileName: selectedAlgorithm.grammarFileName,
            showAnalysis: showAnalysis,
            analysis: currentAnalysis,
            pickupMeasureCount: SongMeasureMap.leadingPickupCount(selectedSong?.measures ?? []),
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
    /// 当前选中歌是否来自内置 Classic Jazz 分组（按"所在组名 + 歌对象 ID"判断，不按歌名）。
    /// 用途：内置歌隐藏级数分析(#)按钮 —— 分析引擎 PostProcessorFull 不识增三/slash/11，而这些和弦在 solo/演奏侧已正确处理。
    /// 用户自己导入的同名 iRealPro 曲是另一个对象/另一个 ID，在导入组里，不会被误伤。
    private var selectedSongIsFromBuiltin: Bool {
        guard let song = selectedSong, let lib = builtinLibrary else { return false }
        return playlists.contains { $0.name == lib.name && $0.songs.contains { $0.id == song.id } }
    }

    @ViewBuilder
    private var mainContent: some View {
        ZStack(alignment: .leading) {
            // 主内容
            if let song = selectedSong {
                VStack(spacing: 0) {
                    // 乐谱展示区（🌟 移除外层 SwiftUI ScrollView，让 WebView 接管全面积原生滚动，打通高精度自适应视口）
                    ZStack {
                        if displayedMeasures.isEmpty {
                            Color.clear
                        } else {
                            sheetMusicView
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.white)
                                .cornerRadius(12)
                                .overlay(alignment: .topLeading) {
                                    // 级数分析开关（左上角，独立模块，不影响现有布局）
                                    // 内置 Classic Jazz 歌不显示：分析引擎不识增三/slash/11，按分组归属判断
                                    if !displayedMeasures.isEmpty && !selectedSongIsFromBuiltin {
                                        Button(action: {
                                            triggerImpactHaptic(.light)   // 🌟 P0-2
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
                                                .frame(width: 44, height: 44)   // 🌟 P0-2: 透明热区44pt，视觉圆保持30pt
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(PressableButtonStyle())
                                        .padding(.top, 8)
                                        .padding(.leading, 12)
                                        .help("显示/隐藏级数分析")
                                    }
                                }
                                .overlay(alignment: .topTrailing) {
                                    if !displayedMeasures.isEmpty {
                                        NoteColorLegendView()
                                    }
                                }
                                // [方案21] 原旋律 ⇄ 即兴 Solo 对照：当前曲自带旋律、且已生成过即兴才出现（与算法组无关）；
                                // 只换显示源、不重新随机。浮于乐谱顶部居中，不占底部播放工具栏（避开 top-leading 分析钮/top-trailing 图例）。
                                .overlay(alignment: .top) {
                                    if hasMelodyForCurrentSong && hasGeneratedImprovisation {
                                        Picker("", selection: $showOriginalMelody) {
                                            Text(NSLocalizedString("原旋律", comment: "")).tag(true)
                                            Text(NSLocalizedString("即兴", comment: "")).tag(false)
                                        }
                                        .pickerStyle(.segmented)
                                        .frame(width: 168)
                                        .padding(.top, 8)
                                        .onChange(of: showOriginalMelody) { _ in
                                            JazzMidiPlayer.shared.stop()
                                            playingNoteId = ""
                                            isPlaying = false
                                            isPaused = false
                                            soloVersion = UUID()   // 只刷新渲染，不触发生成
                                        }
                                    }
                                }
                                .shadow(color: Color.black.opacity(0.08), radius: 5, x: 0, y: 3)
                                // 切到内置 Classic Jazz 歌时自动关掉级数分析（按钮已隐藏，避免色块残留）
                                .onChange(of: selectedSong?.id) { _ in
                                    if selectedSongIsFromBuiltin { showAnalysis = false }
                                }
                        }
                        // 🌟 P0-1: 生成中转圈遮罩（仅 ProgressView，无文字/无按钮，乐谱区中央）
                        if isGenerating {
                            ProgressView()
                                .scaleEffect(1.3)
                                .padding(28)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, contentHorizontalMargin)
                    .padding(.top, 12)

                    // 底部：乐队混音总控台
                    BandMixerView(
                        saxVolume: $saxVolume, pianoVolume: $pianoVolume,
                        bassVolume: $bassVolume, drumVolume: $drumVolume,
                        saxMuted: $saxMuted, pianoMuted: $pianoMuted,
                        bassMuted: $bassMuted, drumMuted: $drumMuted,
                        selectedStyle: $selectedStyle,
                        isExpanded: $showMixer,
                        enableTransform: $enableTransform,
                        selectedTransformMusician: $selectedTransformMusician,
                        guideColorEnabled: $guideColorEnabled,                 // [Guide Color 圆点]
                        grammarColorEnabled: $grammarColorEnabled,             // [Grammar Color 圆点 20260925]
                        // [Grammar Color 圆点 20260925] Color 圆点资格扩为 Guide + Basic/Master：
                        //   isColorDotEligible=true=Guide（仍要求 TRANSFORM 点亮）；false=Basic/Master（不要求 TRANSFORM）。
                        isColorDotEligible: selectedAlgorithmGroup == .guide,
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
                    dprint("🔍 [ContentView] 风格切换: \(newStyle.rawValue)")
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
                            solo: displayedMeasures,   // [方案19] 热重载播放跟随当前显示源
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
                              measureIndex < self.displayedMeasures.count,
                              noteIndex < self.displayedMeasures[measureIndex].notes.count else {
                            return
                        }
                        
                        let note = self.displayedMeasures[measureIndex].notes[noteIndex]
                        if !note.isRest, let midi = self.midiNumber(from: note.pitch) {
                            self.activeMidiNotes = [midi]
                        } else {
                            self.activeMidiNotes = []
                        }
                    }
                }
                // 换成调用我们即将新增的全乐队播放方法
                JazzMidiPlayer.shared.playWithAccompaniment(solo: displayedMeasures, bpm: Double(selectedSong?.tempo ?? 120), style: selectedStyle.rawValue)  // [方案19] 跟随显示源
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

// MARK: - 废纸篓条目（被删歌曲 + 原始所属组名，供恢复）
struct TrashItem: Identifiable, Codable {
    var id = UUID()
    let song: JazzSong
    let sourcePlaylist: String
}

// MARK: - 📋 侧边栏视图
struct SidebarView: View {
    @Binding var playlists: [JazzPlaylist]
    @Binding var selectedPlaylistIndex: Int
    @Binding var selectedSong: JazzSong?
    var onImportFromFile: () -> Void
    var onImportFromLink: () -> Void
    // 内置 Classic Jazz 分组相关（默认 nil = 没有内置库，行为与旧版完全一致）
    var builtinPlaylistName: String? = nil
    var onDeleteBuiltinSong: ((JazzSong) -> Void)? = nil
    var onHideBuiltinPlaylist: ((String) -> Void)? = nil
    var onRestoreBuiltinPlaylist: (() -> Void)? = nil
    // 用户导入的命名分组（默认空 = 无；这些组支持整组删除）
    var importedPlaylistNames: Set<String> = []
    var onDeleteImportedGroup: ((String) -> Void)? = nil
    // 废纸篓（仅 My Songs / 导入组的单曲删除进入；内置组不进）
    var trashItems: [TrashItem] = []
    var onMoveSongToTrash: ((JazzSong, JazzPlaylist) -> Void)? = nil  // 单曲移入废纸篓
    var onClearMySongs: (() -> Void)? = nil                          // 清空 My Songs（保留 Demo）
    var onRestoreTrashItem: ((TrashItem) -> Void)? = nil             // 恢复废纸篓单曲
    var onDeleteTrashItem: ((TrashItem) -> Void)? = nil              // 废纸篓单曲永久删
    var onEmptyTrash: (() -> Void)? = nil                            // 清空废纸篓

    // 待确认的删除动作（统一一个弹窗承载多种删除）
    private enum PendingDeletion {
        case userSong(JazzSong, JazzPlaylist)  // 用户组单曲（My Songs / 导入组）：移入废纸篓，带上所属分组
        case builtinSong(JazzSong)             // 内置单曲：持久化隐藏（不进废纸篓）
        case builtinGroup(String)              // 内置整组：持久化隐藏（可恢复）
        case importedGroup(String)             // 导入整组：直接彻底删除（不进废纸篓）
        case mySongsClear                      // 清空 My Songs（保留 Demo，其余进废纸篓）
        case trashSong(TrashItem)              // 废纸篓单曲：永久删除
        case emptyTrash                        // 清空废纸篓：永久删除
    }
    @State private var pendingDeletion: PendingDeletion? = nil
    @State private var showDeleteConfirm = false        // 删除确认弹窗
    @State private var pendingRestore: TrashItem? = nil // 待恢复的废纸篓条目（恢复确认弹窗）
    @State private var searchText = ""
    @State private var trashCollapsed = false           // 废纸篓分组折叠态
    // 用“折叠集合”：默认空 = 全部展开，新增分组也自动展开，无需额外同步
    @State private var collapsedPlaylists: Set<UUID> = []
    // 首次出现时把所有分组强制收起（重启后默认全收，不记忆上次展开态）
    @State private var didInitialCollapse = false

    var currentPlaylist: JazzPlaylist {
        playlists[selectedPlaylistIndex]
    }

    /// 组内按搜索词过滤（标题/作曲家）
    private func filteredSongs(in playlist: JazzPlaylist) -> [JazzSong] {
        guard !searchText.isEmpty else { return playlist.songs }
        return playlist.songs.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.composer.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// 搜索时隐藏无匹配的分组
    private var visiblePlaylists: [JazzPlaylist] {
        playlists.filter { !filteredSongs(in: $0).isEmpty }
    }

    private func isBuiltin(_ playlist: JazzPlaylist) -> Bool {
        playlist.name == builtinPlaylistName
    }

    /// My Songs 固定为 playlists[0]
    private func isMySongs(_ playlist: JazzPlaylist) -> Bool {
        playlists.firstIndex(where: { $0.id == playlist.id }) == 0
    }

    /// Demo 固定为 My Songs 的第一首，写死不可删
    private func isDemo(_ song: JazzSong, in playlist: JazzPlaylist) -> Bool {
        isMySongs(playlist) && playlist.songs.first?.id == song.id
    }

    /// 废纸篓按搜索词过滤（标题/作曲家）
    private var filteredTrashItems: [TrashItem] {
        guard !searchText.isEmpty else { return trashItems }
        return trashItems.filter {
            $0.song.title.localizedCaseInsensitiveContains(searchText) ||
            $0.song.composer.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func toggleCollapse(_ id: UUID) {
        if collapsedPlaylists.contains(id) { collapsedPlaylists.remove(id) }
        else { collapsedPlaylists.insert(id) }
    }

    private func confirmDeletion() {
        guard let pending = pendingDeletion else { return }
        switch pending {
        case .userSong(let song, let playlist):
            onMoveSongToTrash?(song, playlist)
        case .builtinSong(let song):
            onDeleteBuiltinSong?(song)
        case .builtinGroup(let name):
            onHideBuiltinPlaylist?(name)
        case .importedGroup(let name):
            onDeleteImportedGroup?(name)
        case .mySongsClear:
            onClearMySongs?()
        case .trashSong(let item):
            onDeleteTrashItem?(item)
        case .emptyTrash:
            onEmptyTrash?()
        }
        pendingDeletion = nil
    }

    private var deleteMessage: String {
        switch pendingDeletion {
        case .userSong(let s, _):
            return String(format: NSLocalizedString("将「%@」移入废纸篓？", comment: ""), s.title)
        case .builtinSong(let s):
            return String(format: NSLocalizedString("确定要删除「%@」吗？", comment: ""), s.title)
        case .builtinGroup(let name):
            return String(format: NSLocalizedString("确定要隐藏整个「%@」列表吗？可在下方菜单恢复。", comment: ""), name)
        case .importedGroup(let name):
            return String(format: NSLocalizedString("确定删除整个「%@」歌单及其全部歌曲吗？此操作不可恢复。", comment: ""), name)
        case .mySongsClear:
            return NSLocalizedString("确定清空 My Songs 中除 Demo 外的全部歌曲吗？这些歌曲会移入废纸篓，可随时恢复。", comment: "")
        case .trashSong(let item):
            return String(format: NSLocalizedString("确定永久删除「%@」吗？此操作不可恢复。", comment: ""), item.song.title)
        case .emptyTrash:
            return NSLocalizedString("确定清空废纸篓吗？其中所有歌曲将被永久删除，此操作不可恢复。", comment: "")
        case .none:
            return ""
        }
    }

    /// 内置组当前是否被隐藏（隐藏后底部菜单显示“恢复”）
    private var builtinGroupHidden: Bool {
        guard let name = builtinPlaylistName else { return false }
        return !playlists.contains { $0.name == name }
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
            .onAppear {
                // 重启后默认全部收起，仅首次执行一次；运行中用户可自由展开/收起
                guard !didInitialCollapse else { return }
                didInitialCollapse = true
                collapsedPlaylists = Set(playlists.map { $0.id })
                trashCollapsed = true
            }

            Divider()

            // 分组歌曲列表：每个播放列表一个可折叠分组（组标题行 + 展开后的歌曲行）
            List(selection: $selectedSong) {
                ForEach(visiblePlaylists, id: \.id) { playlist in
                    PlaylistGroupHeader(
                        name: playlist.name,
                        count: playlist.songs.count,
                        isExpanded: !collapsedPlaylists.contains(playlist.id)
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .contentShape(Rectangle())
                    .onTapGesture { toggleCollapse(playlist.id) }
                    .swipeActions(edge: .trailing) {
                        // 内置分组：左滑整组隐藏（可恢复）；
                        // My Songs：左滑清空除 Demo 外的全部歌曲（组与 Demo 保留，歌曲进废纸篓）；
                        // 用户导入分组：左滑整组彻底删除（不可恢复）。
                        if isBuiltin(playlist) {
                            Button(role: .destructive) {
                                pendingDeletion = .builtinGroup(playlist.name)
                                showDeleteConfirm = true
                            } label: {
                                Label(NSLocalizedString("隐藏列表", comment: ""), systemImage: "eye.slash")
                            }
                        } else if isMySongs(playlist) {
                            if playlist.songs.count > 1 {
                                Button(role: .destructive) {
                                    pendingDeletion = .mySongsClear
                                    showDeleteConfirm = true
                                } label: {
                                    Label(NSLocalizedString("清空", comment: ""), systemImage: "trash")
                                }
                            }
                        } else if importedPlaylistNames.contains(playlist.name) {
                            Button(role: .destructive) {
                                pendingDeletion = .importedGroup(playlist.name)
                                showDeleteConfirm = true
                            } label: {
                                Label(NSLocalizedString("删除列表", comment: ""), systemImage: "trash")
                            }
                        }
                    }

                    if !collapsedPlaylists.contains(playlist.id) {
                        ForEach(filteredSongs(in: playlist), id: \.id) { song in
                            SongRow(song: song, isSelected: selectedSong?.id == song.id)
                                .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedSong = song
                                }
                                .swipeActions(edge: .trailing) {
                                    // 内置单曲：隐藏（不进废纸篓）；My Songs 的 Demo：无删除按钮（写死不可删）；其余用户单曲：移入废纸篓
                                    if isBuiltin(playlist) {
                                        Button(role: .destructive) {
                                            pendingDeletion = .builtinSong(song)
                                            showDeleteConfirm = true
                                        } label: {
                                            Label(NSLocalizedString("删除", comment: ""), systemImage: "trash")
                                        }
                                    } else if !isDemo(song, in: playlist) {
                                        Button(role: .destructive) {
                                            pendingDeletion = .userSong(song, playlist)
                                            showDeleteConfirm = true
                                        } label: {
                                            Label(NSLocalizedString("删除", comment: ""), systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    }
                }

                // 废纸篓分组（独立于 playlists：不参与播放/选中，点按弹恢复，可永久删或整篓清空）
                if !filteredTrashItems.isEmpty {
                    PlaylistGroupHeader(
                        name: NSLocalizedString("废纸篓", comment: ""),
                        count: trashItems.count,
                        isExpanded: !trashCollapsed
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .contentShape(Rectangle())
                    .onTapGesture { trashCollapsed.toggle() }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDeletion = .emptyTrash
                            showDeleteConfirm = true
                        } label: {
                            Label(NSLocalizedString("清空", comment: ""), systemImage: "trash.slash")
                        }
                    }

                    if !trashCollapsed {
                        ForEach(filteredTrashItems) { item in
                            SongRow(song: item.song, isSelected: false)
                                .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))
                                .contentShape(Rectangle())
                                .opacity(0.65)
                                .onTapGesture {
                                    pendingRestore = item
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        pendingDeletion = .trashSong(item)
                                        showDeleteConfirm = true
                                    } label: {
                                        Label(NSLocalizedString("永久删除", comment: ""), systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .alert(
                NSLocalizedString("删除", comment: ""),
                isPresented: $showDeleteConfirm
            ) {
                Button(NSLocalizedString("取消", comment: ""), role: .cancel) {
                    pendingDeletion = nil
                }
                Button(NSLocalizedString("删除", comment: ""), role: .destructive) {
                    confirmDeletion()
                }
            } message: {
                Text(deleteMessage)
            }
            // 废纸篓单曲：点按弹“恢复到初始列表”确认
            .alert(
                NSLocalizedString("恢复", comment: ""),
                isPresented: Binding(
                    get: { pendingRestore != nil },
                    set: { if !$0 { pendingRestore = nil } }
                )
            ) {
                Button(NSLocalizedString("取消", comment: ""), role: .cancel) {
                    pendingRestore = nil
                }
                Button(NSLocalizedString("恢复", comment: "")) {
                    if let item = pendingRestore { onRestoreTrashItem?(item) }
                    pendingRestore = nil
                }
            } message: {
                Text(NSLocalizedString("您想将它恢复到初始播放列表吗？", comment: ""))
            }

            Divider()

            // 底部操作栏（用原生 Menu：无需维护 isPresented 开关，每次点击都由系统直接弹出，
            // 规避 confirmationDialog 在导入引发重绘后开关/锚点失效、第二次点击无反应的问题）
            HStack {
                Menu {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onImportFromFile()
                    } label: {
                        Label(NSLocalizedString("从文件导入", comment: ""), systemImage: "folder")
                    }
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onImportFromLink()
                    } label: {
                        Label(NSLocalizedString("从链接导入", comment: ""), systemImage: "link")
                    }
                    // 内置组被隐藏后，在此恢复（仅菜单项，不改变底部栏布局与尺寸）
                    if builtinGroupHidden {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onRestoreBuiltinPlaylist?()
                        } label: {
                            Label(NSLocalizedString("恢复经典爵士", comment: ""), systemImage: "arrow.uturn.backward")
                        }
                    }
                } label: {
                    Label(NSLocalizedString("导入曲谱", comment: ""), systemImage: "square.and.arrow.down")
                        .font(.caption)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - 播放列表分组标题行（组名 + 数量 + 右侧展开箭头）
struct PlaylistGroupHeader: View {
    let name: String
    let count: Int
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.15), value: isExpanded)
                .frame(width: 12)
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
            Text("· \(count)")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.08))
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
                            
                            // 仅多首才需要歌单名；单曲统一进 My Songs，不显示名称框
                            if parsedSongs.count > 1 {
                                TextField(NSLocalizedString("歌单名称", comment: ""), text: $playlistName)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
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
        // 只对第一个识别到的 iRealPro 链接解析一次，避免 string/url/data 三条路径重复解析
        var handledLink: String? = nil
        
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
                    if handledLink == nil { handledLink = text }
                }
            }
            
            // 尝试 URL
            if let url = pasteboard.url {
                infoLines.append("🔗 URL：\(url.absoluteString)")
                infoLines.append("")
                
                if url.absoluteString.hasPrefix("irealb://") || url.absoluteString.hasPrefix("irealbook://") {
                    infoLines.append("✅ 检测到 iReal Pro URL，尝试解析...")
                    if handledLink == nil { handledLink = url.absoluteString }
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
                                if handledLink == nil { handledLink = str }
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
        // 找到链接：保持转圈，交给后台 tryParse，解析完成后再关闭；没找到：立即关闭并显示空状态
        if let link = handledLink {
            tryParse(link)
        } else {
            isDetecting = false
        }
    }
    
    private func tryParse(_ urlString: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let parsed = IRealProParser.parsePlaylist(url: urlString)
            
            DispatchQueue.main.async {
                if !parsed.isEmpty {
                    parsedSongs = parsed.map { IRealProParser.toJazzSong($0) }
                    // 单曲统一进 My Songs（不使用歌单名）；多首保持默认歌单名，由用户在下方编辑
                    clipboardInfo += "\n🎉 解析成功！找到 \(parsed.count) 首歌"
                } else {
                    clipboardInfo += "\n❌ 解析失败，没有找到歌曲"
                }
                // 后台解析到此结束（无论成败），关闭「正在检测剪贴板...」转圈
                isDetecting = false
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
    // D4: 染色跟随用户选择的色彩档位（full 时 b9/#9 等全量变化音也归为绿色色彩音，做到看到=听到）
    let viewPalette = ColorPaletteMode(rawValue: colorModeRaw) ?? .conservative
    let colorPCs = Set(quality.colorIntervals(for: chordName, palette: viewPalette).map { ($0 + rpc) % 12 })
    if colorPCs.contains(pc) { return .colorTone }
    // 非和弦/色彩音不做事后推断 — 趋近音由 Grammar 终端类型唯一决定
    return .foreignTone
}

/// 验证趋近音与目标音是否构成半音级进关系（对齐Java原版: ±1半音, 不含全音）
func isStepwiseApproach(_ appPitch: Int, _ targetPitch: Int) -> Bool {
    guard appPitch >= 0, targetPitch >= 0 else { return false }
    return abs(appPitch - targetPitch) == 1
}

/// 解析和弦根音的pitch class
    func chordRootPC(_ name: String) -> Int {
    let normalized = name
        .replacingOccurrences(of: "♭", with: "b")
        .replacingOccurrences(of: "♯", with: "#")
    let c = Array(normalized); guard !c.isEmpty else { return 0 }
    var s = String(c[0]).uppercased()
    if c.count > 1, c[1] == "#" || c[1] == "b" { s.append(c[1]) }
    let m: [String:Int] = [
        "C": 0, "B#": 0,
        "C#": 1, "Db": 1,
        "D": 2,
        "D#": 3, "Eb": 3,
        "E": 4, "Fb": 4,
        "F": 5, "E#": 5,
        "F#": 6, "Gb": 6,
        "G": 7,
        "G#": 8, "Ab": 8,
        "A": 9,
        "A#": 10, "Bb": 10,
        "B": 11, "Cb": 11
    ]
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
    static let tupletSlots = [320, 160, 96, 80, 72, 48, 40, 24, 20, 10]  // 10 = 32分三连音 (15*2/3)

    // MARK: - 🐛 野值调试 (Wild Value Detection)
    // 合法时值 = 15 的倍数 OR 在 tupletSlots 中；其余均为"野值"
    #if DEBUG
    static let debugWildValues = true
    #else
    static let debugWildValues = false
    #endif

    static func _dbg_isLegalDuration(_ dur: Int) -> Bool {
        if dur <= 0 { return true } // 0/负值会被后续 removeAll 清理，不算野值
        if dur % 15 == 0 { return true }
        return tupletSlots.contains(dur)
    }

    /// 将原始时值映射到目标网格的对应时值（BGL 回退机制用）
    /// - Parameters:
    ///   - dur: 原始时值（slots）
    ///   - grid: 目标网格类型 ("triplet" / "quint" / "straight")
    /// - Returns: 映射后的时值
    private static func projectDuration(_ dur: Int, to grid: String) -> Int {
        switch grid {
        case "triplet":
            switch dur {
            case 15: return 20    // 32分 → 16分三连音
            case 24: return 20    // 16分五连音 → 16分三连音
            case 30: return 40    // 16分 → 8分三连音
            case 48: return 40    // 8分五连音 → 8分三连音
            case 60: return 40    // 8分 → 8分三连音
            case 72: return 80    // 附点8分五连音 → 4分三连音
            case 90: return 80    // 附点8分 → 4分三连音
            case 96: return 80    // 4分五连音 → 4分三连音
            default: return dur
            }
        case "quint":
            switch dur {
            case 15: return 24    // 32分 → 16分五连音
            case 20: return 24    // 16分三连音 → 16分五连音
            case 30: return 48    // 16分 → 8分五连音
            case 40: return 48    // 8分三连音 → 8分五连音
            case 60: return 48    // 8分 → 8分五连音
            case 80: return 96    // 4分三连音 → 4分五连音
            case 90: return 96    // 附点8分 → 4分五连音
            default: return dur
            }
        default: // straight
            switch dur {
            case 20: return 30    // 16分三连音 → 16分
            case 24: return 30    // 16分五连音 → 16分
            case 40: return 30    // 8分三连音 → 16分
            case 48: return 60    // 8分五连音 → 8分
            case 80: return 60    // 4分三连音 → 8分
            case 96: return 90    // 4分五连音 → 附点8分
            default: return dur
            }
        }
    }

    static func _dbg_checkWildValues(_ label: String, _ notes: [EnrichedNote]) {
        guard debugWildValues else { return }
        for (i, n) in notes.enumerated() {
            if !_dbg_isLegalDuration(n.durationSlots) {
                let prev = i > 0 ? "prev=\(notes[i-1].durationSlots)" : "prev=nil"
                let next = i < notes.count-1 ? "next=\(notes[i+1].durationSlots)" : "next=nil"
                dprint("🐛 [WILD] \(label) 音符[\(i)] pitch=\(n.midiPitch) dur=\(n.durationSlots) (\(prev), \(next))")
            }
        }
    }

    static func _dbg_checkWildValuesTuples(_ label: String, _ notes: [(pitch: Int, start: Int, end: Int, graces: [Int], origTieStart: Bool, origTieEnd: Bool, terminalType: String?)]) {
        guard debugWildValues else { return }
        for (i, n) in notes.enumerated() {
            let dur = n.end - n.start
            if !_dbg_isLegalDuration(dur) {
                let prev = i > 0 ? "prev=\(notes[i-1].end - notes[i-1].start)" : "prev=nil"
                let next = i < notes.count-1 ? "next=\(notes[i+1].end - notes[i+1].start)" : "next=nil"
                dprint("🐛 [WILD] \(label) 音符[\(i)] pitch=\(n.pitch) dur=\(dur) (\(prev), \(next))")
            }
        }
    }
    
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
                    isTieStart:    note.isTieStart,  // 取后音的（指向下一个音），前音→后音内部消化
                    isTieEnd:      last.isTieEnd,    // 取前音的（来自前一个音），后音←前音内部消化
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
            dprint("⚠️ [TIE BUG 追踪] 小节 ?? - 步骤 0：原始输入")
            #endif
            for (ni, nn) in notes.enumerated() {
                #if DEBUG
                dprint("  音符 \(ni): pitch=\(nn.midiPitch), dur=\(nn.durationSlots), isTieStart=\(nn.isTieStart), isTieEnd=\(nn.isTieEnd)")
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
            
            let grid = 15
            let snapStart = isTuplet ? rawStart : Int(round(Double(rawStart) / Double(grid))) * grid
            var snapEnd = isTuplet ? rawEnd : Int(round(Double(rawEnd) / Double(grid))) * grid
            
            if !isTuplet && snapEnd <= snapStart { snapEnd = snapStart + grid }
            
            let finalStart = max(0, min(profile.slotsPerMeasure, snapStart))
            let finalEnd = max(0, min(profile.slotsPerMeasure, snapEnd))
            
            if finalEnd > finalStart {
                snappedNotes.append((note.midiPitch, finalStart, finalEnd, note.gracePitches, note.isTieStart, note.isTieEnd, note.terminalType))
            }
        }
        // 调试：步骤 1 - 30 网格吸附后
        if debugMode {
            #if DEBUG
            dprint("⚠️ [TIE BUG 追踪] 小节 ?? - 步骤 1：30 网格吸附后")
            #endif
            for (si, sn) in snappedNotes.enumerated() {
                #if DEBUG
                dprint("  音符 \(si): pitch=\(sn.pitch), dur=\(sn.end - sn.start), isTieStart=\(sn.origTieStart), isTieEnd=\(sn.origTieEnd)")
                #endif
            }
        }
        // 🐛 D1: 15-grid 吸附后野值检测
        _dbg_checkWildValuesTuples("D1_15grid_snap", snappedNotes)
        
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
                // 兜底时值锁定为 15 (32分音符)，允许 32 分跑句以标准符杠组呈现
                filledNotes.append((sn.pitch, currentStart, max(currentStart + 15, sn.end), sn.graces, sn.origTieStart, sn.origTieEnd, sn.terminalType))
                pointer = max(currentStart + 15, sn.end)
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
            dprint("⚠️ [TIE BUG 追踪] 小节 ?? - 步骤 2：缝隙吸收后")
            #endif
            for (fi, fn) in filledNotes.enumerated() {
                #if DEBUG
                dprint("  音符 \(fi): pitch=\(fn.pitch), dur=\(fn.end - fn.start), isTieStart=\(fn.origTieStart), isTieEnd=\(fn.origTieEnd)")
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
                
                // P0 修复：isLastSlice 需同时考虑 sliceDur 被钳位填满小节的情况
                // 原逻辑只看 nextBoundary >= finalEnd，但 sliceDur 被 L3239-3241 钳位后，
                // 非末尾片(nextBoundary<finalEnd)可能填满 480 slots，带着虚假的 tieStart=true，
                // 而后续应该带 tieEnd 的片因 L3209 totalSlots>=480 break 永远不会被创建 → 悬挂延音线
                let isLastSlice = (nextBoundary >= finalEnd) 
                    || (totalSlots + sliceDur >= profile.slotsPerMeasure)
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
            dprint("⚠️ [TIE BUG 追踪] 小节 ?? - 步骤 4：强拍切割器后")
            #endif
            for (si, sn) in slicedNotes.enumerated() {
                #if DEBUG
                dprint("  音符 \(si): pitch=\(sn.midiPitch), dur=\(sn.durationSlots), isTieStart=\(sn.isTieStart), isTieEnd=\(sn.isTieEnd)")
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
            dprint("⚠️ [TIE BUG 追踪] 小节 ?? - 步骤 5：音符融合阶段后")
            #endif
            for (fi, fn) in finalResult.enumerated() {
                #if DEBUG
                dprint("  音符 \(fi): pitch=\(fn.midiPitch), dur=\(fn.durationSlots), isTieStart=\(fn.isTieStart), isTieEnd=\(fn.isTieEnd)")
                #endif
            }
        }
        // 🐛 D2: 音符融合后野值检测
        _dbg_checkWildValues("D2_amalgamation", finalResult)
        
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
            dprint("⚠️ [TIE BUG 追踪] 小节 ?? - 步骤 6：强行守恒 480 后")
            #endif
            for (fi, fn) in finalResult.enumerated() {
                #if DEBUG
                dprint("  音符 \(fi): pitch=\(fn.midiPitch), dur=\(fn.durationSlots), isTieStart=\(fn.isTieStart), isTieEnd=\(fn.isTieEnd)")
                #endif
            }
        }
        // 🐛 D3: 480守恒后野值检测
        _dbg_checkWildValues("D3_480conservation", finalResult)

        // ==========================================================
        // 🌟 终极防线 2：误差扩散 (消除非 15 倍数的毛刺)
        // 连音音符保持精确时值不参与舍入，误差跨连音传递给后续普通音
        // ==========================================================
        var error = 0
        for i in 0..<finalResult.count {
            // 连音音符保持精确时值，不参与舍入；error 不变（跨连音传递，不丢弃）
            if tupletSlots.contains(finalResult[i].durationSlots) {
                continue
            }
            let dur = finalResult[i].durationSlots + error
            let roundedDur = Int(round(Double(dur) / 15.0)) * 15
            error = dur - roundedDur
            finalResult[i].durationSlots = roundedDur
        }
        // 尾部误差兜底：优先找最后一个非连音音符承载，避免破坏连音精确时值
        if error != 0 && !finalResult.isEmpty {
            var targetIdx = finalResult.count - 1
            while targetIdx > 0 && tupletSlots.contains(finalResult[targetIdx].durationSlots) {
                targetIdx -= 1
            }
            finalResult[targetIdx].durationSlots += error
        }

        // 调试：步骤 7 - 误差扩散后
        if debugMode {
            #if DEBUG
            dprint("⚠️ [TIE BUG 追踪] 小节 ?? - 步骤 7：误差扩散后")
            #endif
            for (fi, fn) in finalResult.enumerated() {
                #if DEBUG
                dprint("  音符 \(fi): pitch=\(fn.midiPitch), dur=\(fn.durationSlots), isTieStart=\(fn.isTieStart), isTieEnd=\(fn.isTieEnd)")
                #endif
            }
        }
        // 🐛 D4: 误差扩散后野值检测
        _dbg_checkWildValues("D4_error_diffusion", finalResult)

        // 🐛 [修复] "消除孤立10"逻辑已删除：
        // 原逻辑认为"10无法合法渲染"，但 JS 端 getExactVexFlowDuration 早已映射 10→"32_t3"
        // (ContentView.swift:319)，10 是合法的 32 分三连音，不应被合并到邻音。
        // 且 10 已加入 tupletSlots，误差扩散会跳过它保持精确时值。

        // ==========================================================
        // 🌟 终极防线 3.2：消除孤立的 15-slot (32分) 音符
        // 爵士乐记谱中 32 分几乎总是 2-4 个成组出现（符杠连接）；
        // 单个 32 分夹在长音中间会造成谱面"毛刺"，合并到邻音保证整洁。
        // 合并后总时长守恒（15 slot 转移到邻音）。
        // ==========================================================
        for i in (0..<finalResult.count).reversed() {
            if finalResult[i].durationSlots == 15 {
                let prevIs15 = i > 0 && finalResult[i-1].durationSlots == 15
                let nextIs15 = i < finalResult.count - 1 && finalResult[i+1].durationSlots == 15
                if !prevIs15 && !nextIs15 {
                    let orphan = finalResult[i]
                    if i > 0 {
                        // ── 方向 1：合并到前一个音 A ──
                        // 内部消化：只要 A 有 tieStart 就清除（A.tieStart 指向 B，合并后必然内部消化）
                        if finalResult[i-1].isTieStart {
                            finalResult[i-1].isTieStart = false
                        }
                        // 跨音转移：B 有 tieStart（指向 B 的下一个音，不是 A）→ 转移给 A
                        if orphan.isTieStart {
                            finalResult[i-1].isTieStart = true
                        }
                        finalResult[i-1].durationSlots += 15
                        finalResult[i].durationSlots = 0
                    } else if i < finalResult.count - 1 {
                        // ── 方向 2：合并到后一个音 C ──
                        // 跨音转移：B 有 tieEnd（指向 B 的前一个音，跨小节）→ 转移给 C
                        if orphan.isTieEnd {
                            finalResult[i+1].isTieEnd = true
                        }
                        // 内部消化：B 的 tieStart 指向的就是 C 本身（B 的下一个音）
                        // 合并 B→C 后这对延音线被内部消化，不转移 B 的 tieStart
                        // C 原有的 tieStart（指向 C 的下一个音）保持不变
                        finalResult[i+1].durationSlots += 15
                        finalResult[i].durationSlots = 0
                    }
                }
            }
        }
        finalResult.removeAll { $0.durationSlots <= 0 }

        // 调试：步骤 8 - 消除孤立的 10 后
        if debugMode {
            #if DEBUG
            dprint("⚠️ [TIE BUG 追踪] 小节 ?? - 步骤 8：消除孤立的 10 后")
            #endif
            for (fi, fn) in finalResult.enumerated() {
                #if DEBUG
                dprint("  音符 \(fi): pitch=\(fn.midiPitch), dur=\(fn.durationSlots), isTieStart=\(fn.isTieStart), isTieEnd=\(fn.isTieEnd)")
                #endif
            }
        }
        // 🐛 D5: 孤立10/15消除后野值检测
        _dbg_checkWildValues("D5_isolated_merge", finalResult)

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
                let tripletVals: Set<Int> = [20, 40, 80, 160, 320]
                let quintVals: Set<Int> = [24, 48, 72, 96]
                let straightVals: Set<Int> = [15, 30, 60, 90, 120, 180, 240]
                let hasTriplet = segment.contains { tripletVals.contains($0.durationSlots) }
                let hasQuint = segment.contains { quintVals.contains($0.durationSlots) }
                let hasStraight = segment.contains { straightVals.contains($0.durationSlots) }

                // 3. 只有当两种及以上网格在同一拍内混用时才介入修正
                let mixedGridCount = (hasTriplet ? 1 : 0) + (hasQuint ? 1 : 0) + (hasStraight ? 1 : 0)
                if mixedGridCount >= 2 {
                    let tripletCount = segment.filter { tripletVals.contains($0.durationSlots) }.count
                    let quintCount = segment.filter { quintVals.contains($0.durationSlots) }.count
                    let straightCount = segment.filter { straightVals.contains($0.durationSlots) }.count
                    // 三连音/五连音/普通音三方计数，多数派为目标网格
                    let counts = [(tripletCount, "triplet"), (quintCount, "quint"), (straightCount, "straight")]
                    let majorityGrid = counts.max(by: { $0.0 < $1.0 })!.1
                    
                    // 回退顺序：多数派优先 → straight（记谱最通用）→ triplet → quint
                    let priorityOrder = ["straight", "triplet", "quint"]
                    let otherGrids = priorityOrder.filter { $0 != majorityGrid }
                    let tryOrder = [majorityGrid] + otherGrids
                    
                    var unified = false
                    for tryGrid in tryOrder {

                        // 4. 生成目标时值映射（使用提取的独立函数）
                        var projectedDurations: [Int] = []
                        var expectedTotal = 0
                        for note in segment {
                            let targetDur = GridQuantizer.projectDuration(note.durationSlots, to: tryGrid)
                            projectedDurations.append(targetDur)
                            expectedTotal += targetDur
                        }

                        // 5. 计算亏空/盈余，并平均摊派到这一拍的每一个音符
                        let deficit = 120 - expectedTotal
                        let count = segment.count
                        if count > 0 {
                            let adjustmentPerNote = deficit / count
                            let remainder = deficit % count
                            
                            // 预检查：均摊补偿后所有值是否合法
                            var allLegal = true
                            for i in 0..<count {
                                var finalSlots = projectedDurations[i] + adjustmentPerNote
                                if i == count - 1 { finalSlots += remainder }
                                if !GridQuantizer._dbg_isLegalDuration(finalSlots) {
                                    allLegal = false
                                    break
                                }
                            }
                            
                            if allLegal {
                                // 写入结果
                                for i in 0..<count {
                                    var finalSlots = projectedDurations[i] + adjustmentPerNote
                                    if i == count - 1 { finalSlots += remainder }
                                    finalResult[beatStart + i].durationSlots = max(15, finalSlots)
                                }
                                unified = true
                                // 日志：成功
                                if GridQuantizer.debugWildValues {
                                    dprint("🐛 [BGL] beatStart=\(beatStart) unified=\(tryGrid) (majority=\(majorityGrid)) deficit=\(deficit) adj/note=\(adjustmentPerNote) rem=\(remainder) count=\(count)")
                                    for i in 0..<count {
                                        let orig = segment[i].durationSlots
                                        let proj = projectedDurations[i]
                                        var comp = proj + adjustmentPerNote
                                        if i == count - 1 { comp += remainder }
                                        dprint("   音[\(i)] \(orig)→\(proj)→\(max(15, comp))")
                                    }
                                }
                                break // 成功，跳出回退循环
                            } else {
                                // 日志：该网格失败，继续尝试下一个
                                if GridQuantizer.debugWildValues {
                                    dprint("🐛 [BGL] beatStart=\(beatStart) try=\(tryGrid) FAILED(illegal), trying next... deficit=\(deficit) projected=\(projectedDurations)")
                                }
                            }
                        }
                    }
                    
                    if !unified {
                        // 所有网格都失败，保留原混合网格（兜底，与当前行为一致）
                        if GridQuantizer.debugWildValues {
                            dprint("🐛 [BGL] beatStart=\(beatStart) ALL GRIDS FAILED, keeping original mixed grid")
                        }
                    }
                }
            }

            beatStart = beatEnd
        }

        // 调试：步骤 9 - 拍子网格锁后
        if debugMode {
            #if DEBUG
            dprint("⚠️ [TIE BUG 追踪] 小节 ?? - 步骤 9：拍子网格锁后")
            #endif
            for (fi, fn) in finalResult.enumerated() {
                #if DEBUG
                dprint("  音符 \(fi): pitch=\(fn.midiPitch), dur=\(fn.durationSlots), isTieStart=\(fn.isTieStart), isTieEnd=\(fn.isTieEnd)")
                #endif
            }
        }
        // 🐛 D6: BeatGridLock后野值检测
        _dbg_checkWildValues("D6_beat_grid_lock", finalResult)

        // ==========================================================
        // 🌟 终极防线 4：安全无损切片 (弗罗贝尼乌斯分解)
        // 遇到 50 自动无损拆为 30 + 20，用延音线缝合，音高 100% 保护
        // ==========================================================
        let exactMappableSlots = [480, 360, 320, 240, 180, 160, 120, 96, 90, 80, 72, 60, 48, 40, 30, 24, 20, 15, 10]  // +10 = 32分三连音
        let splitSlots = [480, 360, 240, 120, 90, 80, 60, 48, 40, 30, 24, 20, 15, 10]  // +10 = 32分三连音
        
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
                // 修复：残片小于最小可分值(15)时，合并到上一个碎片，避免 take=20 初始值 overshoot
                if take > remaining {
                    if !pieces.isEmpty {
                        pieces[pieces.count - 1].durationSlots += remaining
                    } else {
                        // 极端情况：原始值 <15 且无碎片可合并，直接创建一个碎片
                        pieces.append(EnrichedNote(
                            midiPitch: note.midiPitch,
                            durationSlots: remaining,
                            gracePitches: note.gracePitches,
                            isTieStart: note.isTieStart,
                            isTieEnd: note.isTieEnd,
                            terminalType: note.terminalType
                        ))
                    }
                    remaining = 0
                    break
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
            // 🐛 FROB详细日志：记录每个被拆分的音符
            if GridQuantizer.debugWildValues {
                let pieceVals = pieces.map { String($0.durationSlots) }.joined(separator: "+")
                let hasNeg = remaining < 0
                dprint("🐛 [FROB] orig=\(note.durationSlots) pitch=\(note.midiPitch) → [\(pieceVals)] remainingAfter=\(remaining)\(hasNeg ? " ⚠️NEGATIVE!" : "")")
            }
            
            // 🐛 [FROB] 混合网格回退已删除（方案A）：
            // 原逻辑检测到 pieces 同时含连音值+标准值时，用最接近的标准值 rounded 替换整个音符，
            // 但 rounded 可能与原始值不同（如 140→120 丢20、216→240 增24），直接破坏总时长守恒，
            // 导致 layoutWarning=true → 5次满重试 → 性能浪费5倍。
            // BGL（Beat Grid Lock）已处理一拍内的混合网格统一；Frobenius 拆出的少量混合网格
            // （如 [120,20]、[120,96]）可正常渲染，无需回退。删除后 Frobenius 拆分本身守恒。
            safeResult.append(contentsOf: pieces)
        }
        
        // 调试：步骤 10 - frobeniusSplit 后
        if debugMode {
            #if DEBUG
            dprint("⚠️ [TIE BUG 追踪] 小节 ?? - 步骤 10：frobeniusSplit 后")
            #endif
            for (si, sn) in safeResult.enumerated() {
                #if DEBUG
                dprint("  音符 \(si): pitch=\(sn.midiPitch), dur=\(sn.durationSlots), isTieStart=\(sn.isTieStart), isTieEnd=\(sn.isTieEnd)")
                #endif
            }
        }
        // 🐛 D7: Frobenius后最终输出野值检测
        _dbg_checkWildValues("D7_final_output", safeResult)
        // 🐛 修复3: Frobenius 前后总时长校验（安全网）
        if GridQuantizer.debugWildValues {
            let beforeTotal = finalResult.reduce(0) { $0 + $1.durationSlots }
            let afterTotal = safeResult.reduce(0) { $0 + $1.durationSlots }
            if beforeTotal != afterTotal {
                dprint("⚠️ [FROB] 总时长不守恒! before=\(beforeTotal) after=\(afterTotal) diff=\(afterTotal - beforeTotal)")
            }
        }
        
        return safeResult
    }
}

// MARK: - 🌟 P0-2: 通用按压态按钮样式（按下变暗+轻微缩放，松开回弹；纯渲染变换，不影响布局）
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.4 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
