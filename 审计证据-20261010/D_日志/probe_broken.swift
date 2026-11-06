// 探针1：逐字复制 ContentView.swift 的真实枚举定义(:6-16)与 :2583 的比较表达式。
// 目的：用 swiftc 直接证明在只有 3 个 case 的枚举上引用 `.master` 是否为编译错误。
import Foundation

enum ImproAlgorithmGroup: String, Equatable {
    case guide = "GuideTone"
    case grammar = "Grammar"
    case learning = "Learning"
    // case basic = "Basic"
    // case master = "Master"
}

let selectedAlgorithmGroup: ImproAlgorithmGroup = .grammar
let isPurchased = false

// 下面这行逐字对应 ContentView.swift:2583
let blocked = (selectedAlgorithmGroup == .master || selectedAlgorithmGroup == .learning) && !isPurchased
print(blocked)
