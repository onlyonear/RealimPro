import Foundation

/// 真复刻可恢复错误：全部由包装层捕获并据此回退 grammar，禁止 fatalError 崩溃。
/// 对齐 Java generateSoloFromOutline 在无可用 outline 时 return null、Notate 静默跳过的口径。
enum FaithfulError: Error {
    case resourceUnavailable(name: String)      // Bundle 中无该 K3 资源
    case outlineUnavailable(numMeasures: Int)   // 该大师无此小节数的 outline
    case transitionMissing(clusterNumber: Int)  // 转移表缺失
    case clusterNotFound(number: Int)           // RNG 选中的 cluster number 无索引
    case dataPointNoCluster(dp: Int)            // DataPoint 无所属 cluster
    case chordUnavailable(name: String)         // 真实和弦无法解析（对齐 Java null，上层回退 grammar）
}

/// 真复刻合并驱动（K3 版）：读扁平 K3 数据，R1-R9 选择 + 发声共用同一连续 RNG。
/// 算法结构、RNG 调用顺序与 s3 BuildSolo 完全一致，仅把 K1Doc 通用反射替换为索引查表。
enum FaithfulBuildSolo {

    struct Result {
        var notes: MelodyPart2
        var trace: [String]
    }

    /// 工程内核心入口：直接用已从 Bundle 解码的 K3Corpus 构建，算法与 RNG 顺序不变。
    /// - Parameter chordPlan: 当前歌曲每小节真实和弦（来自 roadmap，已按 slot 守恒），
    ///   替代旧版写死的 C–Am7–Dm7–G7 循环。
    static func build(corpus: K3Corpus, numMeasures: Int, seed: Int64,
                      chordPlan: [[MeasureChord]],
                      minPitch: Int = 54, maxPitch: Int = 84,
                      skipMergeTies: Bool = false) throws -> Result {
        var rng = S2RNG(seed: seed)
        guard chordPlan.count == numMeasures else {
            throw FaithfulError.chordUnavailable(name: "plan count mismatch")
        }

        // cluster number -> cluster index
        var numberToIndex: [Int: Int] = [:]
        for (i, c) in corpus.clusters.enumerated() { numberToIndex[c.number] = i }

        // 复刻 generateSoloFromOutline 477-485：只保留 size==numMeasures 的 outline
        let possibleOutlines = corpus.outlines.filter { $0.measures == numMeasures }
        guard !possibleOutlines.isEmpty else { throw FaithfulError.outlineUnavailable(numMeasures: numMeasures) }

        // R1（仅选一次；buildSolo 重启不重选 outline）
        let outlineIndex = rng.nextInt("R1:outline", possibleOutlines.count)
        let outline = possibleOutlines[outlineIndex].sets

        var allNotes = MelodyPart2()

        // 模拟 buildSolo 递归重启（HarnessLickGen 698-705）：RNG 不重置、outline 不重选，
        // 仅 oldPitch 归零并重新从首簇（R2/R3）开始
        var buildAgain = true
        while buildAgain {
            buildAgain = false

            // 首簇（每次重启重新选择）
            let startCS = outline[0]
            var current: Int
            let starters = starterClusters(corpus, cs: startCS)
            if !starters.isEmpty {
                current = starters[rng.nextInt("R2:pickRandomCluster", starters.count)]
            } else {
                current = try randomPoint(corpus, cs: startCS, rng: &rng)
            }

            allNotes = MelodyPart2()
            var oldPitch = 0

            // i == 0：复刻 590-607，无上限 do-while，每次 oldPitch 重置 0，无匹配/无 starter 修复
            let context0 = try FaithfulChordPlan.context(for: chordPlan[0])
            var chosen0 = MelodyPart2()
            while true {
                oldPitch = 0
                let point = randomDataPoint(corpus, cluster: current, rng: &rng)
                let rule = corpus.dataPoints[point].rule
                let (part, endingPitch) = voiceSection(
                    rng: &rng, rule: rule, context: context0,
                    startOldPitch: oldPitch, minPitch: minPitch, maxPitch: maxPitch)
                oldPitch = endingPitch
                chosen0 = part
                if !goesOutOfBounds(part, minPitch, maxPitch) { break }
            }
            allNotes.appendPart(chosen0)

            // i >= 1
            for i in 1..<numMeasures {
                current = try getNextCluster(corpus, currentCluster: current,
                                        csIndex: outline[i], numberToIndex: numberToIndex,
                                        rng: &rng)
                let context = try FaithfulChordPlan.context(for: chordPlan[i])
                // 匹配用 songChords：本小节真实和弦名 + 下一小节第一个真实和弦（对齐旧结构）
                var songChords: [String] = chordPlan[i].map { $0.name }
                if i < numMeasures - 1, let next = chordPlan[i + 1].first {
                    songChords.append(next.name)
                }

                var counter = 0
                let previousPitch = oldPitch
                var chosen = MelodyPart2()
                var ok = false

                while counter < 15 {
                    if counter > 0 { oldPitch = previousPitch }

                    _ = getRandomDataPointWithMatchingChords(
                        corpus, cluster: current, songChords: songChords, rng: &rng)
                    let point = randomDataPoint(corpus, cluster: current, rng: &rng)
                    var rule = corpus.dataPoints[point].rule
                    if corpus.dataPoints[point].starter && rule.contains("slope 0 0") {
                        if rng.nextDouble("V8:bernoulli") > 0.5 {
                            rule = rule.replacingOccurrences(of: "0 0", with: "1 3")
                        } else {
                            rule = rule.replacingOccurrences(of: "0 0", with: "-1 -3")
                        }
                    }

                    let (part, endingPitch) = voiceSection(
                        rng: &rng, rule: rule, context: context,
                        startOldPitch: oldPitch, minPitch: minPitch, maxPitch: maxPitch)
                    oldPitch = endingPitch
                    chosen = part
                    counter += 1
                    if !goesOutOfBounds(part, minPitch, maxPitch) { ok = true; break }
                }

                if !ok {
                    // 重试满 15 次仍越界：整个 buildSolo 重启
                    buildAgain = true
                    break
                }
                allNotes.appendPart(chosen)
            }
        }

        // Faithful 真复刻路径跳过 mergeTies：其双重累加超长在 Java 由 makeConsistent 纠正，
        // 跳过即可保留各小节守恒的原始结构（发声与 Java 最终 1:1），避免紧凑化后切片错位。
        if !skipMergeTies {
            allNotes.mergeTiesAtBoundary()
        }
        return Result(notes: allNotes, trace: rng.trace)
    }

    /// 命令行/工程外便捷入口：从文件路径加载 K3 后构建。
    static func runFull(k3Path: String, numMeasures: Int, seed: Int64,
                        chordPlan: [[MeasureChord]],
                        minPitch: Int = 54, maxPitch: Int = 84) throws -> Result {
        let corpus = try K3Corpus.load(path: k3Path)
        return try build(corpus: corpus, numMeasures: numMeasures, seed: seed,
                         chordPlan: chordPlan,
                         minPitch: minPitch, maxPitch: maxPitch)
    }

    // MARK: 发声

    private static func voiceSection(rng: inout S2RNG, rule: String, context: ChordContext,
                                    startOldPitch: Int,
                                    minPitch: Int, maxPitch: Int) -> (MelodyPart2, Int) {
        let sectionTop = SExprParser.parse(rule)
        let section = reorganize(sectionTop)[0]
        var last = MelodyPart2()
        var endingPitch = startOldPitch
        for innerAttempt in 0..<MELODY_GEN_LIMIT {
            let state = LickGenState(rng: rng, minPitch: minPitch, maxPitch: maxPitch,
                                    avoidRepeats: true, doNotSwitchOctave: true)
            state.position = 0
            state.oldPitch = startOldPitch
            fillMelodyHelper(state: state, section: section, context: context,
                             minPitch: minPitch, maxPitch: maxPitch, attempt: innerAttempt)
            rng = state.rng
            last = state.result
            endingPitch = state.oldPitch
            if last.lowest >= minPitch - 1 && last.highest <= maxPitch + 1 {
                return (last, endingPitch)
            }
        }
        return (last, endingPitch)
    }

    private static func goesOutOfBounds(_ p: MelodyPart2, _ minPitch: Int, _ maxPitch: Int) -> Bool {
        p.lowest < minPitch || p.highest > maxPitch
    }

    // MARK: 和弦匹配（R6/R7）

    private static func getRandomDataPointWithMatchingChords(
        _ corpus: K3Corpus, cluster: Int, songChords: [String], rng: inout S2RNG) -> Int {
        let dps = corpus.clusters[cluster].dataPoints
        var matching: [Int] = []
        for dp in dps where chordsMatch(corpus.dataPoints[dp].chordList, songChords) {
            matching.append(dp)
        }
        if matching.isEmpty {
            return randomDataPoint(corpus, cluster: cluster, rng: &rng)
        }
        let percentMatching = Double(matching.count) / Double(dps.count)
        let r = rng.nextDouble("R6:matchThreshold")
        if r < percentMatching * 3 {
            let p = rng.nextInt("R7:matchedPick", matching.count)
            return matching[p]
        }
        return randomDataPoint(corpus, cluster: cluster, rng: &rng)
    }

    private static func chordsMatch(_ dpChords: [String], _ songChords: [String]) -> Bool {
        if dpChords.count != songChords.count { return false }
        for i in 0..<dpChords.count {
            // 口径对齐 Java：比较各自序列内"相邻和弦的相对根音移动距离"（转调不变），
            // 而非 dp 与 song 对应和弦的绝对根音是否相同
            if i > 0 {
                let dpMove = getDistance(dpChords[i], dpChords[i - 1])
                let songMove = getDistance(songChords[i], songChords[i - 1])
                if dpMove != songMove { return false }
            }
            if !typesMatch(dpChords[i], songChords[i]) { return false }
        }
        return true
    }

    private static func typesMatch(_ c1: String, _ c2: String) -> Bool {
        func typeOf(_ c: String) -> String {
            if c.count == 1 { return "maj" }
            return String(c.dropFirst(rootOf(c).count))
        }
        return typeOf(c1) == typeOf(c2)
    }

    private static func rootOf(_ c: String) -> String {
        if c.count == 1 { return c }
        let second = c[c.index(after: c.startIndex)]
        if second == "#" || second == "b" { return String(c.prefix(2)) }
        return String(c.prefix(1))
    }

    private static let roots: [String: Int] = [
        "C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5,
        "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11
    ]

    private static func getDistance(_ c1: String, _ c2: String) -> Int {
        (roots[rootOf(c1)] ?? 0) - (roots[rootOf(c2)] ?? 0)
    }

    // MARK: 选簇（R5/R5b）

    private static func getNextCluster(_ corpus: K3Corpus, currentCluster: Int,
                                      csIndex: Int, numberToIndex: [Int: Int],
                                      rng: inout S2RNG) throws -> Int {
        let currentNumber = corpus.clusters[currentCluster].number
        guard let t = transitionObject(corpus, currentNumber: currentNumber) else {
            throw FaithfulError.transitionMissing(clusterNumber: currentNumber)
        }
        let cs = corpus.clusterSets[csIndex]
        var nextClusters: [Int] = []
        for r in cs.relatives { nextClusters.append(corpus.clusters[r].number) }
        nextClusters.append(corpus.clusters[cs.original].number)

        let next = getNextStateFiltered(t, possibilities: nextClusters, rng: &rng)
        if next == -1 {
            // R5b：s1 改造版 ClusterSet.getRandomCluster() 已收敛到 HarnessRNG（可种子化、
            // 消耗主 RNG），nextInt(relatives.size+1)，末位=original 否则 relatives。
            return randomCluster(corpus, cs: csIndex, rng: &rng)
        }
        guard let idx = numberToIndex[next] else { throw FaithfulError.clusterNotFound(number: next) }
        return idx
    }

    private static func transitionObject(_ corpus: K3Corpus, currentNumber: Int) -> K3Transition? {
        for t in corpus.transitions where t.state == currentNumber { return t }
        return corpus.transitions.first
    }

    private static func getNextStateFiltered(_ t: K3Transition, possibilities: [Int],
                                            rng: inout S2RNG) -> Int {
        var st: [Int] = []
        var pr: [Double] = []
        for pos in possibilities {
            for (j, ns) in t.nextStates.enumerated() where ns == pos {
                st.append(ns); pr.append(t.probabilities[j])
            }
        }
        if st.isEmpty { return -1 }
        var sums: [Double] = []
        var acc: Double = 0
        for p in pr { acc += p; sums.append(acc) }
        let rand = rng.nextDouble("R5:getNextStateFiltered")
        for i in 0..<sums.count - 1 where rand < sums[i] { return st[i] }
        return st.last!
    }

    /// s1 改造版 getRandomCluster：HarnessRNG.nextInt(relatives.size+1)，末位=original，否则 relatives
    private static func randomCluster(_ corpus: K3Corpus, cs: Int, rng: inout S2RNG) -> Int {
        let set = corpus.clusterSets[cs]
        let p = rng.nextInt("R5b:getRandomCluster", set.relatives.count + 1)
        if p == set.relatives.count { return set.original }
        return set.relatives[p]
    }

    // MARK: 选择辅助

    private static func randomDataPoint(_ corpus: K3Corpus, cluster: Int,
                                       rng: inout S2RNG) -> Int {
        let dps = corpus.clusters[cluster].dataPoints
        return dps[rng.nextInt("R4:getRandomDataPoint", dps.count)]
    }

    private static func containsStarter(_ corpus: K3Corpus, cluster: Int) -> Bool {
        corpus.clusters[cluster].dataPoints.contains { corpus.dataPoints[$0].starter }
    }

    private static func starterClusters(_ corpus: K3Corpus, cs: Int) -> [Int] {
        let set = corpus.clusterSets[cs]
        var out: [Int] = []
        if containsStarter(corpus, cluster: set.original) { out.append(set.original) }
        for r in set.relatives where containsStarter(corpus, cluster: r) { out.append(r) }
        return out
    }

    private static func randomPoint(_ corpus: K3Corpus, cs: Int, rng: inout S2RNG) throws -> Int {
        let points = corpus.clusterSets[cs].points
        let dp = points[rng.nextInt("R3:getRandomPoint", points.count)]
        // R3 选中 DataPoint 所属簇（mCluster 语义）；K3 用其所在 cluster 反查
        return try cluster(ofDataPoint: dp, corpus: corpus)
    }

    private static func cluster(ofDataPoint dp: Int, corpus: K3Corpus) throws -> Int {
        for (i, c) in corpus.clusters.enumerated() where c.dataPoints.contains(dp) { return i }
        throw FaithfulError.dataPointNoCluster(dp: dp)
    }
}
