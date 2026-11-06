//
//  RNNLSTM.swift
//  RealimPro
//
//  LSTM P0 —— LSTM 单元与 Expert（前向推理），口径对齐：
//    LSTM.java（门顺序 forget/input/output/activate；initialstate 前半 cell、后半 hidden）
//    Expert.java（lstm1 → lstm2 → full；全连接 Operations.None 输出 raw）
//

import Foundation

/// 单个 LSTM 层（reference 类型，持有 cell / hidden 状态）。
final class RNNLSTMCell {
    private let gateW: [RNNMatrix]
    private let gateB: [[Float]]
    private let initCell: [Float]
    private let initHidden: [Float]
    private let hiddenSize: Int

    private var cell: [Float]
    private var hidden: [Float]

    init(weights: RNNLSTMWeights) {
        self.gateW = weights.gateW
        self.gateB = weights.gateB
        self.initCell = weights.initCell
        self.initHidden = weights.initHidden
        self.hiddenSize = weights.initHidden.count
        self.cell = weights.initCell
        self.hidden = weights.initHidden
    }

    func reset() {
        cell = initCell
        hidden = initHidden
    }

    /// 推送一个外部输入向量，返回本层输出（hidden）。
    func step(_ input: [Float]) -> [Float] {
        // LSTM.java:94 —— input.join(result)
        let x = RNNMath.join(input, hidden)

        // 三个 sigmoid 门：forget / input / output（LSTM.java:105-116）
        var gates: [[Float]] = []
        gates.reserveCapacity(3)
        for g in 0..<3 {
            let m = gateW[g]
            var pre = RNNMath.gemv(m.data, rows: m.rows, cols: m.cols, x)
            pre = RNNMath.add(pre, gateB[g])
            gates.append(RNNMath.sigmoid(pre))
        }

        // 候选 activate（tanh）（LSTM.java:118-120）
        let am = gateW[3]
        var candidate = RNNMath.gemv(am.data, rows: am.rows, cols: am.cols, x)
        candidate = RNNMath.add(candidate, gateB[3])
        candidate = RNNMath.tanh(candidate)

        // cell = forget · cell_prev + input · candidate（LSTM.java:123-130）
        let forgotten = RNNMath.multiply(gates[0], cell)
        let written = RNNMath.multiply(gates[1], candidate)
        cell = RNNMath.add(forgotten, written)

        // hidden = output · tanh(cell)（LSTM.java:134-137）
        let cellTanh = RNNMath.tanh(cell)
        hidden = RNNMath.multiply(gates[2], cellTanh)

        return hidden
    }
}

/// 单个 Expert：两层 LSTM + 一个全连接层。
final class RNNExpert {
    private let lstm1: RNNLSTMCell
    private let lstm2: RNNLSTMCell
    private let fullW: RNNMatrix
    private let fullB: [Float]

    init(weights: RNNExpertWeights) {
        self.lstm1 = RNNLSTMCell(weights: weights.lstm1)
        self.lstm2 = RNNLSTMCell(weights: weights.lstm2)
        self.fullW = weights.fullW
        self.fullB = weights.fullB
    }

    func reset() {
        lstm1.reset()
        lstm2.reset()
    }

    /// Expert.process（Expert.java:45-50）。全连接 Operations.None：输出 raw，softmax 在 encoding 内做。
    func process(_ input: [Float]) -> [Float] {
        let v1 = lstm1.step(input)
        let v2 = lstm2.step(v1)
        var out = RNNMath.gemv(fullW.data, rows: fullW.rows, cols: fullW.cols, v2)
        out = RNNMath.add(out, fullB)
        return out
    }
}
