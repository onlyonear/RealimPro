import Foundation

/// 统一 RNG：选择（带 R 标签）与发声（无标签方法，内部记录 V 口径）共用同一连续随机源。
/// 逐位复刻 java.util.Random（LCG，mult 0x5DEECE66D，add 0xB，48 位 mask）。
struct S2RNG {
    private var seed: Int64
    private let mask: Int64 = (1 << 48) - 1
    private let mult: Int64 = 0x5DEECE66D
    private let add: Int64 = 0xB
    var trace: [String] = []

    init(seed: Int64) {
        self.seed = (seed ^ mult) & mask
    }

    private mutating func next(_ bits: Int32) -> Int32 {
        seed = (seed &* mult &+ add) & mask
        return Int32(truncatingIfNeeded: UInt64(bitPattern: seed) >> (48 - bits))
    }

    // MARK: 核心 nextInt（数值口径）

    private mutating func rawNextInt(_ bound: Int) -> Int {
        guard bound > 0 else { return 0 }
        if bound & (bound - 1) == 0 {
            return Int((Int64(bound) &* Int64(next(31))) >> 31)
        }
        while true {
            let bits = next(31)
            let val = bits % Int32(bound)
            if Int32(bound) - val + (bits - val) >= 0 {
                return Int(val)
            }
        }
    }

    private mutating func rawNextDouble() -> Double {
        let a = Int64(next(26)) << 27
        let b = Int64(next(27))
        return Double(a + b) / Double(1 << 53)
    }

    // MARK: 发声用（无标签，记录纯方法格式）

    @discardableResult
    mutating func nextInt(_ bound: Int) -> Int {
        let r = rawNextInt(bound)
        trace.append("nextInt(\(bound))=\(r)")
        return r
    }

    @discardableResult
    mutating func nextDouble() -> Double {
        let r = rawNextDouble()
        trace.append("nextDouble()=\(r)")
        return r
    }

    // MARK: 选择用（带标签，记录 tag|格式）

    @discardableResult
    mutating func nextInt(_ tag: String, _ bound: Int) -> Int {
        let r = rawNextInt(bound)
        trace.append("\(tag)|nextInt(\(bound))=\(r)")
        return r
    }

    @discardableResult
    mutating func nextDouble(_ tag: String) -> Double {
        let r = rawNextDouble()
        trace.append("\(tag)|nextDouble=\(r)")
        return r
    }
}
