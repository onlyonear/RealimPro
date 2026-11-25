//
//  JavaLCG.swift
//  RealimPro
//
//  ThemeWeaver（主题发展）M0：可播种随机源，逐位复刻 java.util.Random 的 48-bit 线性同余。
//
//  背景（见 audit_harness/grammar_final_audit_20260907/reports/C_ThemeWeaver移植方案.md §3）：
//  Java 版 ThemeWeaver 有两条随机流——
//    ① 实例字段 Random random = new Random()（ThemeWeaver.java:179/187）：用/不用主题、选主题、移调距离等；
//    ② Notate.bernoulli(p) = Math.random() > (1-p)（imp/gui/Notate.java）：6 个变形是否命中、方向等。
//  两者底层都是 java.util.Random（48-bit LCG）。本类各实例化一个、给固定种子即可逐音复现，
//  供 L0/L1 对拍；grammar 空当段仍不可播种，只做 L3 统计。
//
//  本文件为 M0 纯新增，不依赖任何 UI/AV，也不改动现有生产文件。
//

import Foundation

struct JavaLCG {

    // MARK: - java.util.Random 常量
    private static let multiplier: Int64 = 0x5DEECE66D            // 25214903917
    private static let addend: Int64 = 0xB                        // 11
    private static let mask: Int64 = (1 << 48) - 1                // 281474976710655
    private static let doubleUnit: Double = 0x1.0p-53             // 1 / 2^53

    private var seed: Int64

    /// 等价 java.util.Random(long seed)：构造时对种子做一次混淆 seed ^= multiplier
    init(seed: Int64) {
        self.seed = (seed ^ JavaLCG.multiplier) & JavaLCG.mask
    }

    // MARK: - 核心 next(bits)，等价 protected int next(int bits)
    /// 注意：seed 已被 mask 到 48 位（最高位为 0），这里用逻辑右移；再截断为 Int32。
    mutating func next(_ bits: Int32) -> Int32 {
        seed = (seed &* JavaLCG.multiplier &+ JavaLCG.addend) & JavaLCG.mask
        let shifted = seed >> Int64(48 - Int(bits))
        return Int32(truncatingIfNeeded: shifted)
    }

    /// nextInt()：全范围 32 位（ThemeWeaver 未直接使用，保留以备）
    mutating func nextInt() -> Int32 { next(32) }

    /// 等价 int nextInt(int bound)，bound 必须为正；含 2 的幂快路径与“取到可整除”循环
    mutating func nextInt(bound: Int32) -> Int32 {
        precondition(bound > 0, "nextInt bound must be positive (java semantics)")
        let b = Int64(bound)
        // 2 的幂快路径：(bound * (long)next(31)) >> 31
        if b & -b == b {
            return Int32((b &* Int64(next(31))) >> 31)
        }
        // 常规路径：bits - val + (bound-1) >= 0 时接受（消除取模偏置）
        var bits = next(31)
        var val = bits % Int32(bound)
        while bits &- val &+ (bound &- 1) < 0 {
            bits = next(31)
            val = bits % Int32(bound)
        }
        return val
    }

    /// 等价 double nextDouble()：((long)next(26)<<27 + next(27)) * 2^-53
    mutating func nextDouble() -> Double {
        let hi = Int64(next(26)) << 27
        let lo = Int64(next(27))
        return Double(hi + lo) * JavaLCG.doubleUnit
    }

    /// 等价 Notate.bernoulli(p)：Math.random() > (1 - p)
    /// - Parameter p: 命中概率，取值 [0,1]
    /// - Returns: 是否命中
    mutating func bernoulli(_ p: Double) -> Bool {
        return nextDouble() > (1.0 - p)
    }
}
