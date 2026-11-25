//
//  RNNModel.swift
//  RealimPro
//
//  LSTM P0 —— 紧凑权重文件 .rnn 的格式定义与运行时加载器（读 / mmap）。
//  .rnn 由离线工具 RNNConverter 生成（Float32 小端、带文件头），设备端不解析 CSV。
//

import Foundation

/// 行主序浮点矩阵。
struct RNNMatrix {
    let rows: Int
    let cols: Int
    let data: [Float]
}

/// 单个 LSTM 层的全部权重。
/// 门顺序固定：0=forget、1=input、2=output、3=activate(candidate)。
struct RNNLSTMWeights {
    static let gateCount = 4
    let gateW: [RNNMatrix]   // 每个门 rows×(外部输入+hidden)
    let gateB: [[Float]]     // 每个门 rows
    let initCell: [Float]    // initialstate 前半
    let initHidden: [Float]  // initialstate 后半
}

/// 单个 Expert（lstm1 → lstm2 → full）。
struct RNNExpertWeights {
    let lstm1: RNNLSTMWeights
    let lstm2: RNNLSTMWeights
    let fullW: RNNMatrix
    let fullB: [Float]
}

/// 整个 .rnn 文件。
struct RNNFile {
    let magic: String
    let version: Int
    let numExperts: Int
    let lowBound: Int
    let highBound: Int
    let experts: [RNNExpertWeights]
}

enum RNNModelLoader {

    /// 以 mmap 方式读取 .rnn（.mappedIfSafe），解析为权重结构。
    static func load(url: URL) throws -> RNNFile {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        var reader = RNNByteReader(data: data)
        return try reader.readFile()
    }
}

// MARK: - 小端字节读取器
struct RNNByteReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(data: Data) {
        self.bytes = Array(data)
    }

    var remaining: Int { bytes.count - offset }

    mutating func readFile() throws -> RNNFile {
        let m0 = try readU8(), m1 = try readU8(), m2 = try readU8(), m3 = try readU8()
        let magic = String(bytes: [m0, m1, m2, m3], encoding: .ascii) ?? ""
        let version = Int(try readU32())
        let numExperts = Int(try readU32())
        let lowBound = Int(try readI32())
        let highBound = Int(try readI32())

        guard magic == "RNN1" else { throw RNNReaderError.badMagic(magic) }

        var experts: [RNNExpertWeights] = []
        experts.reserveCapacity(numExperts)
        for _ in 0..<numExperts {
            let lstm1 = try readLSTM()
            let lstm2 = try readLSTM()
            let fullW = try readMatrix()
            let fullB = try readVector()
            experts.append(RNNExpertWeights(lstm1: lstm1, lstm2: lstm2, fullW: fullW, fullB: fullB))
        }
        return RNNFile(magic: magic, version: version, numExperts: numExperts,
                       lowBound: lowBound, highBound: highBound, experts: experts)
    }

    private mutating func readLSTM() throws -> RNNLSTMWeights {
        var gateW: [RNNMatrix] = []
        var gateB: [[Float]] = []
        gateW.reserveCapacity(4); gateB.reserveCapacity(4)
        for _ in 0..<4 {
            gateW.append(try readMatrix())
            gateB.append(try readVector())
        }
        let initState = try readVector()
        let half = initState.count / 2
        let initCell = Array(initState[0..<half])
        let initHidden = Array(initState[half..<(2 * half)])
        return RNNLSTMWeights(gateW: gateW, gateB: gateB, initCell: initCell, initHidden: initHidden)
    }

    private mutating func readMatrix() throws -> RNNMatrix {
        let rows = Int(try readU32())
        let cols = Int(try readU32())
        let count = rows * cols
        var data = [Float](repeating: 0.0, count: count)
        for i in 0..<count { data[i] = Float(bitPattern: try readU32()) }
        return RNNMatrix(rows: rows, cols: cols, data: data)
    }

    private mutating func readVector() throws -> [Float] {
        let len = Int(try readU32())
        var data = [Float](repeating: 0.0, count: len)
        for i in 0..<len { data[i] = Float(bitPattern: try readU32()) }
        return data
    }

    private mutating func readU8() throws -> UInt8 {
        guard offset < bytes.count else { throw RNNReaderError.unexpectedEOF }
        let v = bytes[offset]; offset += 1
        return v
    }

    private mutating func readU32() throws -> UInt32 {
        guard offset + 4 <= bytes.count else { throw RNNReaderError.unexpectedEOF }
        let v = UInt32(bytes[offset])
              | (UInt32(bytes[offset + 1]) << 8)
              | (UInt32(bytes[offset + 2]) << 16)
              | (UInt32(bytes[offset + 3]) << 24)
        offset += 4
        return v
    }

    private mutating func readI32() throws -> Int32 {
        return Int32(bitPattern: try readU32())
    }
}

enum RNNReaderError: Error, Equatable {
    case badMagic(String)
    case unexpectedEOF
}
