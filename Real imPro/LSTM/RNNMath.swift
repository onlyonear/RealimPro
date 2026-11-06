//
//  RNNMath.swift
//  RealimPro
//
//  LSTM P0 —— 薄 Accelerate 张量层（纯 Foundation + Accelerate，无 UIKit）。
//  只实现前向推理需要的算子，口径与原版 Java(mikera/vectorz) 对齐：
//    矩阵乘向量、逐元素加减乘除、标量缩放/平移、negate、reciprocal、
//    exp、tanh、sigmoid、softmax、join、slice、roll、onehot、zeros、sum。
//

import Foundation
import Accelerate

enum RNNMath {

    // MARK: 矩阵 × 向量
    /// y = A · x，A 为 rows×cols 行主序。
    static func gemv(_ a: [Float], rows: Int, cols: Int, _ x: [Float]) -> [Float] {
        var y = [Float](repeating: 0.0, count: rows)
        cblasSgemvWrapper(a: a, rows: rows, cols: cols, x: x, y: &y)
        return y
    }

    private static func cblasSgemvWrapper(a: [Float], rows: Int, cols: Int, x: [Float], y: inout [Float]) {
        a.withUnsafeBufferPointer { pa in
            x.withUnsafeBufferPointer { px in
                y.withUnsafeMutableBufferPointer { py in
                    cblas_sgemv(
                        CblasRowMajor, CblasNoTrans,
                        Int32(rows), Int32(cols),
                        1.0,
                        pa.baseAddress, Int32(cols),
                        px.baseAddress, 1,
                        0.0,
                        py.baseAddress, 1)
                }
            }
        }
    }

    // MARK: 逐元素（返回新数组）
    static func add(_ a: [Float], _ b: [Float]) -> [Float] {
        var out = [Float](repeating: 0.0, count: a.count)
        a.withUnsafeBufferPointer { pa in b.withUnsafeBufferPointer { pb in
            out.withUnsafeMutableBufferPointer { po in
                vDSP_vadd(pa.baseAddress!, 1, pb.baseAddress!, 1, po.baseAddress!, 1, vDSP_Length(a.count))
            }
        }}
        return out
    }

    static func subtract(_ a: [Float], _ b: [Float]) -> [Float] {
        // a - b
        var out = [Float](repeating: 0.0, count: a.count)
        a.withUnsafeBufferPointer { pa in b.withUnsafeBufferPointer { pb in
            out.withUnsafeMutableBufferPointer { po in
                vDSP_vsub(pb.baseAddress!, 1, pa.baseAddress!, 1, po.baseAddress!, 1, vDSP_Length(a.count))
            }
        }}
        return out
    }

    static func multiply(_ a: [Float], _ b: [Float]) -> [Float] {
        var out = [Float](repeating: 0.0, count: a.count)
        a.withUnsafeBufferPointer { pa in b.withUnsafeBufferPointer { pb in
            out.withUnsafeMutableBufferPointer { po in
                vDSP_vmul(pa.baseAddress!, 1, pb.baseAddress!, 1, po.baseAddress!, 1, vDSP_Length(a.count))
            }
        }}
        return out
    }

    /// a / b
    static func divide(_ a: [Float], _ b: [Float]) -> [Float] {
        var out = [Float](repeating: 0.0, count: a.count)
        a.withUnsafeBufferPointer { pa in b.withUnsafeBufferPointer { pb in
            out.withUnsafeMutableBufferPointer { po in
                // vDSP_vdiv(A,IA,B,IB,C) 计算 C = B/A；故 A=分母b、B=分子a → a/b
                vDSP_vdiv(pb.baseAddress!, 1, pa.baseAddress!, 1, po.baseAddress!, 1, vDSP_Length(a.count))
            }
        }}
        return out
    }

    static func scale(_ a: [Float], _ s: Float) -> [Float] {
        var out = [Float](repeating: 0.0, count: a.count)
        var s = s
        a.withUnsafeBufferPointer { pa in out.withUnsafeMutableBufferPointer { po in
            vDSP_vsmul(pa.baseAddress!, 1, &s, po.baseAddress!, 1, vDSP_Length(a.count))
        }}
        return out
    }

    static func addScalar(_ a: [Float], _ s: Float) -> [Float] {
        var out = [Float](repeating: 0.0, count: a.count)
        var s = s
        a.withUnsafeBufferPointer { pa in out.withUnsafeMutableBufferPointer { po in
            vDSP_vsadd(pa.baseAddress!, 1, &s, po.baseAddress!, 1, vDSP_Length(a.count))
        }}
        return out
    }

    static func negate(_ a: [Float]) -> [Float] {
        return scale(a, -1.0)
    }

    static func reciprocal(_ a: [Float]) -> [Float] {
        var out = [Float](repeating: 0.0, count: a.count)
        let ones: [Float] = [1.0]
        a.withUnsafeBufferPointer { pa in out.withUnsafeMutableBufferPointer { po in
            // vDSP_vdiv(A,IA,B,IB,C) = B/A；A=a(分母,stride1)、B=ones(分子,stride0 广播) → 1/a
            vDSP_vdiv(pa.baseAddress!, 1, ones, 0, po.baseAddress!, 1, vDSP_Length(a.count))
        }}
        return out
    }

    // MARK: 一元超越函数（vForce）
    private static func vForce(_ a: [Float],
                               _ body: (UnsafeMutablePointer<Float>, UnsafePointer<Float>, UnsafePointer<Int32>) -> Void) -> [Float] {
        var out = [Float](repeating: 0.0, count: a.count)
        var n = Int32(a.count)
        a.withUnsafeBufferPointer { pa in out.withUnsafeMutableBufferPointer { po in
            _ = body(po.baseAddress!, pa.baseAddress!, &n)
        }}
        return out
    }

    static func exp(_ a: [Float]) -> [Float] {
        return vForce(a) { vvexpf($0, $1, $2) }
    }

    static func tanh(_ a: [Float]) -> [Float] {
        return vForce(a) { vvtanhf($0, $1, $2) }
    }

    /// 逐元素幂（用于温度幂）。
    static func power(_ a: [Float], exponent: Float) -> [Float] {
        var out = [Float](repeating: 0.0, count: a.count)
        for i in 0..<a.count { out[i] = powf(a[i], exponent) }
        return out
    }

    // MARK: 激活函数（口径对齐 Operations.java）
    /// Sigmoid（Operations.java:38-42）：reciprocal(exp(-x)+1)。
    static func sigmoid(_ a: [Float]) -> [Float] {
        let neg = negate(a)
        let e = exp(neg)
        let e1 = addScalar(e, 1.0)
        return reciprocal(e1)
    }

    /// Softmax（Operations.java:45-48）：exp(x) / sum(exp(x))。
    static func softmax(_ a: [Float]) -> [Float] {
        let e = exp(a)
        let s = sum(e)
        return scale(e, 1.0 / s)
    }

    // MARK: 归约
    static func sum(_ a: [Float]) -> Float {
        var result: Float = 0.0
        a.withUnsafeBufferPointer { pa in
            vDSP_sve(pa.baseAddress!, 1, &result, vDSP_Length(a.count))
        }
        return result
    }

    // MARK: 拼接 / 切片 / 滚动 / onehot
    static func join(_ arrays: [Float]...) -> [Float] {
        var total = 0
        for a in arrays { total += a.count }
        var out = [Float](repeating: 0.0, count: total)
        var offset = 0
        for a in arrays {
            out.replaceSubrange(offset..<(offset + a.count), with: a)
            offset += a.count
        }
        return out
    }

    static func slice(_ a: [Float], _ range: Range<Int>) -> [Float] {
        return Array(a[range])
    }

    /// 循环滚动（对齐 NNUtilities.roll，distance 为正向右滚）。
    static func roll(_ a: [Float], distance rawDistance: Int) -> [Float] {
        let n = a.count
        if n == 0 { return a }
        var d = rawDistance % n
        if d < 0 { d += n }
        if d == 0 { return a }
        // part1 = a[n-d ..< n], part2 = a[0 ..< n-d]
        let part1 = Array(a[(n - d)..<n])
        let part2 = Array(a[0..<(n - d)])
        return part1 + part2
    }

    static func onehot(index: Int, length: Int) -> [Float] {
        var out = [Float](repeating: 0.0, count: length)
        if index >= 0 && index < length { out[index] = 1.0 }
        return out
    }

    static func zeros(_ count: Int) -> [Float] {
        return [Float](repeating: 0.0, count: count)
    }
}
