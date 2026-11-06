// 探针2：验证修复方案（逐行判据，与 ModeSettingsCard.swift:634 同构）能正常编译。
import Foundation

enum Group: String, Equatable { case guide, grammar, learning }
enum Algo: String {
    case chordExercise, colorTone, Lick
    case LeeMorgan, charlieParker, billEvans, joePass
    case cannonballAdderley, chetBaker, johnColtrane, milesDavis, redGarland
    case combination, greatMoments
    static let paidGrammar: Set<Algo> = [
        .LeeMorgan, .charlieParker, .billEvans, .joePass,
        .cannonballAdderley, .chetBaker, .johnColtrane, .milesDavis, .redGarland]
    var isPaidGrammar: Bool { Self.paidGrammar.contains(self) }
}

let group: Group = .grammar
let algo: Algo = .billEvans
let isPurchased = false

// 修复后的统一判据
let isPaidRow = (group == .learning) || (group == .grammar && algo.isPaidGrammar)
let shouldShowPaywall = isPaidRow && !isPurchased
print("shouldShowPaywall =", shouldShowPaywall)   // 期望 true
