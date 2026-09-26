//
//  BuiltinMelodyLibrary.swift
//  Real imPro
//
//  内置「Classic Jazz / 经典爵士」公共领域曲库加载器（80 首，均发表于 1931 年及以前）。
//
//  设计原则：
//  1. 本文件【只引用】工程已有的类型（JazzSong / JazzPlaylist / GeneratedMeasure /
//     GeneratedNote / MusicTheoryTag），不重复定义、不改动引擎与 solo 算法任何一行。
//  2. 数据来自随包编译的 builtin_classic_jazz.json（离线管线已保证：每小节时值严格守恒、
//     每小节至少一个和弦、弱起已头部补休止、首和弦已对齐拍头）。
//  3. 每首歌同时产出两份对象：
//       - song: JazzSong              —— 和声层，直接喂现有 generateMeasuresWorker(song:) 生成即兴
//       - melody: [GeneratedMeasure]  —— 原曲旋律层（自带 chord/chordSlots），
//                                        直接喂现有 playWithAccompanimentAndGraces(solo:)
//                                        即可「原曲旋律 + 三轨伴奏」同时播放，或交给 SheetMusicView 渲染。
//  4. 主程序的 GeneratedMeasure / GeneratedNote 因含元组与非 Codable 枚举而不可 Codable，
//     故先用可 Codable 的私有 DTO 解码，再一次性转换成主程序类型。
//

import Foundation

// MARK: - 对外模型

/// 一首内置曲：和声层（供生成）+ 旋律层（供原曲显示/播放）成对持有
struct BuiltinClassicSong: Identifiable {
    let id = UUID()
    /// 和声层：现有侧边栏列表、solo 生成算法使用的就是它
    let song: JazzSong
    /// 原曲旋律层：顺序与 song 的小节一一对应
    let melody: [GeneratedMeasure]
    /// 地区分档："global" / "usOnly"
    let regionTag: String
    /// usOnly 自动解禁日（"YYYY-MM-DD"）；global 为 nil
    let unlockDate: String?

    var title: String { song.title }
    var composer: String { song.composer }
}

/// 整个内置曲库
struct BuiltinClassicLibrary {
    /// 英文分组名："Classic Jazz"
    let name: String
    /// 中文分组名："经典爵士"
    let nameZh: String
    let songs: [BuiltinClassicSong]

    /// 用和声层 JazzSong 组装出的播放列表，可直接挂到现有 playlists 中作为一个分组
    var playlist: JazzPlaylist {
        JazzPlaylist(name: name, songs: songs.map { $0.song })
    }

    /// 按 JazzSong 取对应原曲旋律（列表里拿到 song 后用它取旋律）
    func melody(for song: JazzSong) -> [GeneratedMeasure]? {
        songs.first { $0.song.id == song.id }?.melody
    }

    /// 按曲名取原曲旋律（容错：忽略大小写与首尾空格）
    func melody(title: String) -> [GeneratedMeasure]? {
        let target = title.trimmingCharacters(in: .whitespaces).lowercased()
        return songs.first { $0.title.trimmingCharacters(in: .whitespaces).lowercased() == target }?.melody
    }

    /// 按当前设备法域过滤后的曲库：美国区见 global+usOnly，其余区仅见 global；
    /// usOnly 到 unlockDate 自动升 global。用于列表展示；内部 melody 查找仍可走全量。
    func regionFiltered() -> BuiltinClassicLibrary {
        let visible = songs.filter { RegionGate.isVisible(regionTag: $0.regionTag, unlockDate: $0.unlockDate) }
        return BuiltinClassicLibrary(name: name, nameZh: nameZh, songs: visible)
    }
}

// MARK: - 加载入口

enum BuiltinMelodyLibrary {

    /// 随包资源文件名（把 builtin_classic_jazz.json 加入 App Bundle 即可）
    static let fileName = "builtin_classic_jazz"
    static let fileExtension = "json"

    enum LoadError: Error, LocalizedError {
        case fileMissing(String)
        case decodeFailed(Error)
        case empty

        var errorDescription: String? {
            switch self {
            case .fileMissing(let n):   return "内置曲库资源缺失：\(n).\(BuiltinMelodyLibrary.fileExtension)"
            case .decodeFailed(let e):  return "内置曲库解析失败：\(e.localizedDescription)"
            case .empty:                return "内置曲库为空"
            }
        }
    }

    /// 工程入口：从 Bundle 加载（默认主 Bundle）
    static func load(bundle: Bundle = .main) throws -> BuiltinClassicLibrary {
        guard let url = bundle.url(forResource: fileName, withExtension: fileExtension) else {
            throw LoadError.fileMissing(fileName)
        }
        let data = try Data(contentsOf: url)
        return try load(from: data)
    }

    /// 可测试入口：直接喂 JSON Data（单元测试 / 离线验证用）
    static func load(from data: Data) throws -> BuiltinClassicLibrary {
        let dto: LibraryDTO
        do {
            let decoder = JSONDecoder()
            dto = try decoder.decode(LibraryDTO.self, from: data)
        } catch {
            throw LoadError.decodeFailed(error)
        }
        let songs = (dto.songs ?? []).map { SongConverter.convert($0) }
        guard !songs.isEmpty else { throw LoadError.empty }
        return BuiltinClassicLibrary(
            name: dto.playlistName ?? "Classic Jazz",
            nameZh: dto.playlistNameZh ?? "经典爵士",
            songs: songs
        )
    }
}

// MARK: - Codable DTO（全部字段容错 Optional，缺字段不崩）

private struct LibraryDTO: Codable {
    let playlistName: String?
    let playlistNameZh: String?
    let songCount: Int?
    let songs: [SongDTO]?
}

private struct SongDTO: Codable {
    let title: String?
    let composer: String?
    let key: String?
    let timeSignature: String?
    let style: String?
    let tempo: Int?
    let regionTag: String?      // "global" / "usOnly"（缺省按 global）
    let unlockDate: String?     // "YYYY-MM-DD"，usOnly 到该日升为 global
    let measures: [MeasureDTO]?
}

private struct MeasureDTO: Codable {
    let chord: String?
    let notes: [NoteDTO]?
    let chordAnnotations: [ChordAnnotationDTO]?
    let sectionName: String?
    let slotsPerMeasure: Int?
    let chordSlots: [ChordSlotDTO]?
}

private struct NoteDTO: Codable {
    let pitch: String?
    let isRest: Bool?
    let duration: String?
    let isTriplet: Bool?
    let isTieStart: Bool?
    let isTieEnd: Bool?
}

private struct ChordSlotDTO: Codable {
    let chord: String?
    let startSlot: Int?
}

private struct ChordAnnotationDTO: Codable {
    let chord: String?
    let noteIndex: Int?
}

// MARK: - DTO -> 主程序类型转换

private enum SongConverter {

    static func convert(_ dto: SongDTO) -> BuiltinClassicSong {
        let measureDTOs = dto.measures ?? []
        let melody = measureDTOs.map { makeMeasure($0) }
        let song = makeJazzSong(dto, measures: measureDTOs, melody: melody)
        return BuiltinClassicSong(
            song: song,
            melody: melody,
            regionTag: (dto.regionTag ?? "global").lowercased(),
            unlockDate: dto.unlockDate
        )
    }

    // MARK: 旋律层
    private static func makeMeasure(_ dto: MeasureDTO) -> GeneratedMeasure {
        let notes = (dto.notes ?? []).map { makeNote($0) }

        let annotations: [(chord: String, noteIndex: Int)] = (dto.chordAnnotations ?? []).compactMap { a in
            guard let chord = a.chord else { return nil }
            return (chord: chord, noteIndex: a.noteIndex ?? 0)
        }

        let spm = dto.slotsPerMeasure ?? 480
        var slots: [(chord: String, startSlot: Int)] = (dto.chordSlots ?? []).compactMap { c in
            guard let chord = c.chord else { return nil }
            return (chord: chord, startSlot: c.startSlot ?? 0)
        }
        // 兜底：完全没有 chordSlots 时，用顶层主和弦在拍头占满整小节
        if slots.isEmpty {
            slots = [(chord: dto.chord ?? "", startSlot: 0)]
        }

        return GeneratedMeasure(
            chord: dto.chord ?? slots.first?.chord ?? "",
            notes: notes,
            chordAnnotations: annotations,
            sectionName: dto.sectionName,
            slotsPerMeasure: spm,
            chordSlots: slots
        )
    }

    private static func makeNote(_ dto: NoteDTO) -> GeneratedNote {
        // 原曲旋律不是算法生成的，没有和弦音/经过音等乐理标签，统一标 .unknown。
        // 五线谱上色策略属于显示层决策，后续如需着色可在渲染时按当前和弦实时计算 tag。
        GeneratedNote(
            pitch: dto.pitch ?? "B/4",
            tag: .unknown,
            isRest: dto.isRest ?? false,
            duration: dto.duration ?? "q",
            isTriplet: dto.isTriplet ?? false,
            isTieStart: dto.isTieStart ?? false,
            isTieEnd: dto.isTieEnd ?? false
        )
    }

    // MARK: 和声层（反推 JazzSong，喂现有 solo 生成算法）
    private static func makeJazzSong(_ dto: SongDTO, measures: [MeasureDTO], melody: [GeneratedMeasure]) -> JazzSong {
        var chordMeasures: [[String]] = []
        var durations: [[Double]] = []
        var sectionMarkers: [Int: String] = [:]

        for (index, m) in measures.enumerated() {
            let spm = Double(m.slotsPerMeasure ?? 480)
            let rawSlots = m.chordSlots ?? []
            let validSlots = rawSlots.compactMap { c -> (chord: String, startSlot: Int)? in
                guard let chord = c.chord else { return nil }
                return (chord, c.startSlot ?? 0)
            }

            if validSlots.isEmpty {
                // 兜底：用顶层主和弦占满整小节
                chordMeasures.append([m.chord ?? ""])
                durations.append([spm / 120.0])
            } else {
                chordMeasures.append(validSlots.map { $0.chord })
                var barDurations: [Double] = []
                for (k, slot) in validSlots.enumerated() {
                    let end = k + 1 < validSlots.count
                        ? Double(validSlots[k + 1].startSlot)
                        : spm
                    barDurations.append((end - Double(slot.startSlot)) / 120.0) // slot -> 拍（120 slot = 1 拍）
                }
                durations.append(barDurations)
            }

            if let section = m.sectionName {
                sectionMarkers[index] = section
            }
        }

        return JazzSong(
            title: dto.title ?? "Unknown",
            composer: dto.composer ?? "",
            style: dto.style ?? "Medium Swing",
            tempo: dto.tempo ?? 120,
            key: dto.key ?? "C",
            timeSignature: dto.timeSignature ?? "4/4",
            measures: chordMeasures,
            measureDurations: durations,   // 必须显式传入，否则 JazzSong 会按和弦数平均分配
            sectionMarkers: sectionMarkers
        )
    }
}
