// =====================================================================
// TransformRNG.swift
// [T2] ② Guide Tone & Transform 两档随机源（精确复刻 Java java.util.Random）。
//
// 背景：Java 两层（Transform.applySubstitutionType 外层、Substitution.apply 内层）各做一次
//   Collections.shuffle(list, rnd)，且【内外层共用同一个 java.util.Random 实例】（一条流，
//   调用次序固定）。为同时满足"逐音 1:1 对拍"与"生产真随机听感"，这里提供两档：
//
//   1) JavaLCGRNG(seed:)：48 位线性同余，可注入固定种子，逐位复刻 java.util.Random 与
//      Collections.shuffle，供对拍/回归/单测（deterministic 复现）。
//   2) SystemTransformRNG()：每次生成新建，种子取系统随机并【记录本次种子】，生产用；
//      分布语义与 Java 同为均匀 Fisher-Yates 洗牌；出问题可用记录到的种子改注入 JavaLCGRNG 复现。
//
// 另：TransformRandomMode.deterministic = 不洗牌、保序首取，仅对拍/单测使用，不进生产默认。
//
// 参考（已逐行核对）：java.util.Random(seed){ seed=(s^mult)&mask }；next(bits)；
//   nextInt(bound) 的 2 的幂快路 (bound*(long)next31)>>31 与非 2 幂拒绝采样；
//   Collections.shuffle: for(i=size;i>1;i--) swap(i-1, rnd.nextInt(i))。
// 注意 Swift 运算符优先级：`>>` 高于 `&*`，幂快路必须显式中间量 + 括号，勿内联。
// =====================================================================

import Foundation

/// 统一随机源协议：只需 nextInt 与 Fisher-Yates shuffle
protocol TransformRNG {
    mutating func nextInt(_ bound: Int) -> Int
    mutating func shuffle<T>(_ a: inout [T])
}

/// 选择策略：deterministic=保序首取（对拍/单测）；randomized=weight 装袋后真洗牌（生产）
enum TransformRandomMode {
    case deterministic
    case randomized(TransformRNG)
}

/// 逐位复刻 java.util.Random（48 位 LCG）
struct JavaLCGRNG: TransformRNG {
    private static let mult: Int64 = 0x5DEECE66D
    private static let add: Int64 = 0xB
    private static let mask: Int64 = (1 << 48) - 1
    private var seed: Int64
    /// 本次注入的种子（便于日志/复现）
    let originSeed: Int64

    init(seed s: Int64) {
        self.originSeed = s
        seed = (s ^ JavaLCGRNG.mult) & JavaLCGRNG.mask   // 同 new Random(s) 的种子混淆
    }

    private mutating func next(_ bits: Int32) -> Int32 {
        seed = (seed &* JavaLCGRNG.mult &+ JavaLCGRNG.add) & JavaLCGRNG.mask
        return Int32(truncatingIfNeeded: seed >> (48 - Int(bits)))
    }

    /// 精确复刻 Random.nextInt(bound)（2 的幂快路 + 非幂拒绝采样）
    mutating func nextInt(_ bound: Int) -> Int {
        guard bound > 0 else { return 0 }
        if bound & -bound == bound {
            // 2 的幂：(bound * (long)next(31)) >> 31（显式括号，避开 Swift 优先级坑）
            let x = next(31)
            let prod = Int64(bound) &* Int64(x)
            return Int(prod >> 31)
        }
        let b32 = Int32(bound)
        var bits = next(31), val = bits % b32
        while bits &- val &+ (b32 &- 1) < 0 {   // 拒绝采样
            bits = next(31); val = bits % b32
        }
        return Int(val)
    }

    /// 精确复刻 Collections.shuffle(list, rnd)
    mutating func shuffle<T>(_ a: inout [T]) {
        var i = a.count
        while i > 1 {
            let j = nextInt(i)
            a.swapAt(i - 1, j)
            i -= 1
        }
    }
}

/// 生产档：每次新建、系统随机取种并记录；内部仍是同分布 LCG，保证洗牌语义与 Java 一致
struct SystemTransformRNG: TransformRNG {
    /// 本次实际使用的种子（记录以便复现：用它构造 JavaLCGRNG(seed:) 即可重放）
    let seed: Int64
    private var backing: JavaLCGRNG

    init() {
        let lo = Int(Int32.min), hi = Int(Int32.max)
        let s = Int64(Int.random(in: lo...hi))
        self.seed = s
        self.backing = JavaLCGRNG(seed: s)
    }

    /// 测试/复现用：显式指定种子
    init(seed: Int64) {
        self.seed = seed
        self.backing = JavaLCGRNG(seed: seed)
    }

    mutating func nextInt(_ bound: Int) -> Int { backing.nextInt(bound) }
    mutating func shuffle<T>(_ a: inout [T]) { backing.shuffle(&a) }
}
