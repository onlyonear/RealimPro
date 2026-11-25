//
//  SoloistRuntime.swift
//  Real imPro · Soloist 运行时（离线自解析，K2-7 生产接入）
//
//  加载离线转换出的 *-soloist.json（由 audit_harness 的 package_runtime.py 生成）：
//  - points   ：每个 DataPoint 的骨架（首音 + 事件序列，含时值）
//  - outlines ：每小节候选 point 索引
//  - verifiedSizes：门 4 逐小节数实测通过的曲式白名单（只有列表内的小节数才允许启用）
//  - softminT ：该份语料选点用的 softmin 温度（本批 3.0）
//
//  运行时不解析 mObjData 字符串，也不依赖任何 Java 类。
//

import Foundation

// MARK: 事件

/// 一个骨架事件：休止或发声（发声带真实音高与音类）
enum SoloistEvent: Equatable {
    case rest(duration: Int)
    case tone(kind: String, lo: Int, hi: Int, realPitch: Int, pitchClass: Int,
              duration: Int)

    var durationSlots: Int {
        switch self {
        case .rest(let d): return d
        case .tone(_, _, _, _, _, let d): return d
        }
    }
}

// MARK: Point（一个大师真实小节的骨架）

struct SoloistPoint: Equatable {
    let firstPitch: Int        // 真实第一个发声音高（起始音区基准）
    let events: [SoloistEvent]
}

// MARK: Outline

struct SoloistRuntimeOutline: Equatable {
    let measures: Int
    let candidates: [[Int]]    // 每小节一组 point 索引
}

// MARK: Runtime

struct SoloistRuntime: Equatable {
    let file: String
    let points: [SoloistPoint]
    let outlines: [SoloistRuntimeOutline]
    /// 门 4 白名单：只允许这些小节数启用。空数组 = 本份语料本批不启用（永远回退 grammar）
    let verifiedSizes: Set<Int>
    /// softmin 温度
    let softminT: Double
    /// 真实 delta 频率（当前方案 C 不消费，保留数据以便后续扩展）
    let deltaWeights: [Int: Int]
    /// K2-7b 音域围栏中心：该份语料全音符绝对 MIDI 均值四舍五入
    /// （JSON 带 pitchCenter 字段则按字段，否则加载时现算，值确定）
    let pitchCenter: Int

    /// 可用的精确等长轮廓（D2：必须等长，不做近似；且必须落在白名单内）
    func outlines(measuring measures: Int) -> [SoloistRuntimeOutline] {
        guard verifiedSizes.contains(measures) else { return [] }
        return outlines.filter { $0.measures == measures }
    }

    /// 本份语料在运行时真正会启用的曲式
    var effectiveSizes: [Int] {
        Array(Set(outlines.map { $0.measures }).intersection(verifiedSizes)).sorted()
    }
}

// MARK: 加载

enum SoloistRuntimeError: Error, CustomStringConvertible {
    case cannotReadFile(String)
    case invalidJSON
    case invalidStructure(String)

    var description: String {
        switch self {
        case .cannotReadFile(let p): return "无法读取 runtime: \(p)"
        case .invalidJSON: return "runtime JSON 非法"
        case .invalidStructure(let m): return "runtime 结构缺失: \(m)"
        }
    }
}

enum SoloistRuntimeLoader {

    static let defaultSoftminT: Double = 3.0

    static func load(contentsOf url: URL) throws -> SoloistRuntime {
        guard let data = try? Data(contentsOf: url) else {
            throw SoloistRuntimeError.cannotReadFile(url.path)
        }
        return try load(jsonData: data)
    }

    static func load(jsonData data: Data) throws -> SoloistRuntime {
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw SoloistRuntimeError.invalidJSON
        }
        guard let root = obj as? [String: Any] else {
            throw SoloistRuntimeError.invalidStructure("root")
        }
        guard let rawPoints = root["points"] as? [[String: Any]],
              let rawOL = root["outlines"] as? [[String: Any]] else {
            throw SoloistRuntimeError.invalidStructure("points/outlines")
        }

        let sp = rawPoints.map(parsePoint)
        let ol: [SoloistRuntimeOutline] = rawOL.map { raw in
            let measures = (raw["measures"] as? Int) ?? 0
            let cands = (raw["candidates"] as? [[Any]])?.map {
                $0.compactMap { $0 as? Int }
            } ?? []
            return SoloistRuntimeOutline(measures: measures, candidates: cands)
        }

        // verifiedSizes：字段存在就按字段（可能是空数组=全部禁用）；
        // 字段缺失（例如 headless 调试用的中间产物）则默认放开全部尺寸。
        let verified: Set<Int>
        if let raw = root["verifiedSizes"] as? [Any] {
            verified = Set(raw.compactMap { $0 as? Int })
        } else if root.keys.contains("verifiedSizes") {
            verified = []
        } else {
            verified = Set(ol.map { $0.measures })
        }

        let softminT = (root["softminT"] as? Double) ?? defaultSoftminT

        let rawDW = root["deltaWeights"] as? [String: Int] ?? [:]
        var dw: [Int: Int] = [:]
        for (k, v) in rawDW { if let d = Int(k) { dw[d] = v } }

        // 音域中心：优先用打包时写入的字段；缺失时按全音符绝对 MIDI 均值现算
        let computedCenter: Int = {
            var sum = 0, count = 0
            for p in sp {
                for e in p.events {
                    if case .tone(_, _, _, let rp, _, _) = e { sum += rp; count += 1 }
                }
            }
            guard count > 0 else { return 60 }
            return Int((Double(sum) / Double(count)).rounded())
        }()
        let pitchCenter = (root["pitchCenter"] as? Int) ?? computedCenter

        return SoloistRuntime(
            file: (root["file"] as? String) ?? "",
            points: sp,
            outlines: ol,
            verifiedSizes: verified,
            softminT: softminT,
            deltaWeights: dw,
            pitchCenter: pitchCenter)
    }

    private static func parsePoint(_ raw: [String: Any]) -> SoloistPoint {
        let firstPitch = (raw["firstPitch"] as? Int) ?? 0
        let rawEvents = raw["events"] as? [[String: Any]] ?? []
        let events: [SoloistEvent] = rawEvents.map { e in
            let d = (e["d"] as? Int) ?? 0
            if (e["k"] as? String) == "R" {
                return .rest(duration: d)
            }
            return .tone(
                kind: (e["k"] as? String) ?? "C",
                lo: (e["lo"] as? Int) ?? 0,
                hi: (e["hi"] as? Int) ?? 0,
                realPitch: (e["p"] as? Int) ?? 0,
                pitchClass: (e["pc"] as? Int) ?? 0,
                duration: d)
        }
        return SoloistPoint(firstPitch: firstPitch, events: events)
    }
}
