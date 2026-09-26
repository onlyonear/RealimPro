import Foundation

// MARK: - 完整规则 voicing 引擎门面（有状态: 记住上一和声做声部连接）
/// 对齐 ChordPattern.getVoicingAndExtensionList L1050-1089 的规则分支:
/// 词库模板 -> choose; 为空则 generateVoicings 兜底 -> 再 choose; 并列候选由 RNG 取一。
/// 注: Java 的 getVoicings(root,key,"preferred") 因无 "preferred" 类型模板恒为空, 是死代码, 不实现。
final class FullVoicingEngine {
    var requestType: JazzVoicingType = .open
    var lowMidi: Int = 50    // swing 默认 chord-low d- = D3
    var highMidi: Int = 69   // swing 默认 chord-high a  = A4
    private(set) var lastVoicing: [Int] = []
    private let rng: VoicingRNG

    init(rng: VoicingRNG = SystemVoicingRNG()) { self.rng = rng }

    func reset() { lastVoicing = [] }

    /// - Parameters:
    ///   - form: 规范形式名(以 C 为根, 如 C7b13)
    ///   - rootRise: 实际根音相对 C 的半音 0..11
    /// - Returns: 本和弦应弹的绝对 MIDI 组(已排序由调用方/外层保证); 无候选时返回 nil
    @discardableResult
    func voicing(forForm form: String, rootRise: Int) -> [Int]? {
        let lib = ChordFormVoicing.libraryCandidates(form: form, rootRise: rootRise, requestType: requestType)
        var good = VoicingPlacer.choose(lastChord: lastVoicing, candidates: lib, low: lowMidi, high: highMidi)
        if good.isEmpty {
            let gen = ChordFormVoicing.generatedCandidates(form: form, rootRise: rootRise)
            good = VoicingPlacer.choose(lastChord: lastVoicing, candidates: gen, low: lowMidi, high: highMidi)
        }
        guard !good.isEmpty else { return nil }
        let chosen = good[rng.nextIndex(good.count)]
        lastVoicing = chosen.notes
        return chosen.notes
    }
}
