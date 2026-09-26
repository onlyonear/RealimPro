import Foundation

// MARK: - iReal Pro 解析结果模型
struct IRealParsedSong {
    var title: String
    var composer: String
    var style: String
    var key: String
    var tempo: Int          // 速度（BPM）
    var rawChords: String
    var measures: [[String]]  // 按小节组织的和弦
    var measureDurations: [[Double]]  // 每个和弦的时值（拍数），和 measures 一一对应
    var timeSignature: String
    var sectionMarkers: [Int: String]  // 🌟 段落标记：[小节索引: 段落名，如 "A", "B", "C"]
    var hasMixedTimeSignature: Bool = false
}

// MARK: - 🏆 标准实现版 iReal Pro 解析器
class IRealProParser {
    
    // MARK: - 音乐数据前缀标记
    private static let musicPrefix = "1r34LbKcu7"
    
    // MARK: - 1. 批量解析 HTML 文件歌单
    static func parseHTML(html: String) -> [IRealParsedSong] {
        var allSongs: [IRealParsedSong] = []
        
        let pattern = "irealb://([^\"]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return allSongs }
        
        let nsString = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            let encodedUrl = nsString.substring(with: match.range(at: 1))
            let songs = parsePlaylist(url: "irealb://" + encodedUrl)
            allSongs.append(contentsOf: songs)
        }
        return allSongs
    }
    
    // MARK: - 2. 解析混淆 URL
    static func parsePlaylist(url: String) -> [IRealParsedSong] {
        var cleanURL = url.replacingOccurrences(of: "irealb://", with: "")
        cleanURL = cleanURL.replacingOccurrences(of: "irealbook://", with: "")
        
        // ✅ 关键修复：先整体解码，再分割
        // iReal Pro URL 是 percent encoded 的，必须先整体 decode
        // 否则字段分割可能有问题，导致 BPM 等字段读不到
        let decodedURL = cleanURL.removingPercentEncoding ?? cleanURL
        
        let songStrings = decodedURL.components(separatedBy: "===")
        var songs: [IRealParsedSong] = []
        
        for songStr in songStrings {
            if songStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            
            // 按一个或多个等号分割
            let parts = songStr.split(separator: "=", omittingEmptySubsequences: false)
                .map { String($0) }
                .filter { !$0.isEmpty }
            
            var title = "", composer = "", style = "", key = "", music = "", tempo = 120
            
            if parts.count >= 5 {
                title = parts[0].removingPercentEncoding ?? parts[0]
                composer = parts[1].removingPercentEncoding ?? parts[1]
                style = parts[2].removingPercentEncoding ?? parts[2]
                key = parts[3].removingPercentEncoding ?? parts[3]
                
                // 找到音乐数据部分（以musicPrefix开头）
                if let musicIndex = parts.firstIndex(where: { $0.hasPrefix(musicPrefix) }) {
                    music = parts[musicIndex].removingPercentEncoding ?? parts[musicIndex]
                    
                    // ✅ 超鲁棒方案：遍历音乐数据之后的所有字段，从中提取数字
                    // 找到第一个 40-300 之间的数字就是 BPM
                    // 为什么这么做：
                    // - JavaScript 的 parseInt("120bpm") = 120，但 Swift 的 Int("120bpm") = nil
                    // - BPM 可能带单位、小数点、或其他字符
                    // - 音乐数据是混淆字符串、compStyle是文字、transpose是-12~12、repeats是0~5
                    // - 只有 BPM 是 40-300 之间的数字
                    for i in (musicIndex + 1)..<parts.count {
                        let decoded = parts[i].removingPercentEncoding ?? parts[i]
                        // 只提取数字部分
                        let digits = decoded.filter { $0.isNumber }
                        if !digits.isEmpty, let t = Int(digits), t >= 40, t <= 300 {
                            tempo = t
                            break
                        }
                    }
                    
                    // 兜底1：如果音乐数据之后没找到，再往前找找
                    if tempo == 120 {
                        for i in 0..<musicIndex {
                            let decoded = parts[i].removingPercentEncoding ?? parts[i]
                            let digits = decoded.filter { $0.isNumber }
                            if !digits.isEmpty, let t = Int(digits), t >= 40, t <= 300 {
                                tempo = t
                                break
                            }
                        }
                    }
                    
                    // ✅ 兜底2：全字段遍历（最后保险）
                    // 不管 BPM 在哪个位置，遍历所有字段找
                    if tempo == 120 {
                        for part in parts {
                            let decoded = part.removingPercentEncoding ?? part
                            let digits = decoded.filter { $0.isNumber }
                            if !digits.isEmpty, let t = Int(digits), t >= 40, t <= 300 {
                                tempo = t
                                break
                            }
                        }
                    }
                }
                
                // 终极兜底：从 style 里提取
                if tempo == 120 {
                    tempo = Self.extractTempo(from: style)
                }
            }
            
            if !music.isEmpty {
                // 去掉前缀
                let musicData = String(music.dropFirst(musicPrefix.count))
                
                // ✅ 标准实现：字符交换反混淆
                let unscrambledData = unscramble(musicData)
                
                // ✅ 标准实现：基于规则的和弦解析
                let (measures, durations, timeSignature, sectionMarkers, hasMixed) = parseMusic(unscrambledData)
                
                let parsedSong = IRealParsedSong(
                    title: title.isEmpty ? "Unknown Title" : title,
                    composer: composer.isEmpty ? "Unknown Composer" : composer,
                    style: style,
                    key: key,
                    tempo: tempo,
                    rawChords: unscrambledData,
                    measures: measures,
                    measureDurations: durations,
                    timeSignature: timeSignature,
                    sectionMarkers: sectionMarkers,
                    hasMixedTimeSignature: hasMixed
                )
                songs.append(parsedSong)
            }
        }
        return songs
    }
    
    static func parse(url: String) -> IRealParsedSong? {
        return parsePlaylist(url: url).first
    }
    
    // MARK: - 3. ✅ 标准实现反混淆算法（字符交换，非矩阵转置）
    private static func unscramble(_ obfuscated: String) -> String {
        var s = obfuscated
        var result = ""
        
        while s.count > 50 {
            let index = s.index(s.startIndex, offsetBy: 50)
            let p = String(s[..<index])
            s = String(s[index...])
            
            if s.count < 2 {
                // 剩余不足2字符时，当前块不混淆
                result += p
            } else {
                result += obfusc50(p)
            }
        }
        result += s
        return result
    }
    
    /// 50字符块的混淆/反混淆（对称操作，交换两次恢复原状）
    private static func obfusc50(_ s: String) -> String {
        var chars = Array(s)
        guard chars.count == 50 else { return s }
        
        // 1. 前5个字符 ↔ 后5个字符 交换
        for i in 0..<5 {
            let temp = chars[i]
            chars[i] = chars[49 - i]
            chars[49 - i] = temp
        }
        
        // 2. 第10-23个字符 ↔ 第26-39个字符 交换
        for i in 10..<24 {
            let temp = chars[i]
            chars[i] = chars[49 - i]
            chars[49 - i] = temp
        }
        
        return String(chars)
    }
    
    // MARK: - 4. ✅ 标准实现音乐解析器
    private static func parseMusic(_ raw: String) -> (measures: [[String]], durations: [[Double]], timeSignature: String, sectionMarkers: [Int: String], hasMixedTimeSignature: Bool) {
        var measures: [[String]] = []
        var allDurations: [[Double]] = []
        var firstTimeSignature: String? = nil
        var uniqueTimeSignatures = Set<String>()
        var timeSignature = "44"
        var lastChord: String? = nil
        
        // 反复记号相关状态
        var startRepeatLocation = 0
        var endRepeatLocation: Int? = nil
        
        // 🌟 段落标记收集
        var sectionMarkers: [Int: String] = [:]
        
        // 单元格位置跟踪（用于计算和弦时值）
        var currentCell: Double = 0
        var currentChordStarts: [Double] = []
        
        var input = raw

        // ===== 探针：P0 初始化 =====
        #if DEBUG
        dprint("[DIFF] 初始化完成: m=\(measures.count) d=\(allDurations.count) diff=\(measures.count - allDurations.count) (正常应为0或1)")
        #endif

        while !input.isEmpty {
            var matched = false

            // 规则0: <...> 文本注释——跳过全部内容，不计入任何单元格
            if !matched, input.hasPrefix("<") {
                if let endIndex = input.firstIndex(of: ">") {
                    input = String(input[input.index(after: endIndex)...])
                } else {
                    input.removeFirst()
                }
                matched = true
            }
            
            // 规则1: XyQ 空格（占1个单元格）
            if input.hasPrefix("XyQ") {
                currentCell += 1
                input.removeFirst(3)
                matched = true
            }
            
            // 规则1.5: 普通空格字符（占1个单元格）
            if !matched, let first = input.first, first == " " {
                currentCell += 1
                input.removeFirst(1)
                matched = true
            }
            
            // 规则2: 段落标记 *A, *B, *C...
            if !matched, let first = input.first, first == "*" {
                if input.count >= 2 {
                    let sectionChar = input[input.index(after: input.startIndex)]
                    let sectionName = String(sectionChar)
                    // 记录段落开始的小节索引
                    // 如果还没有小节（音乐开头），段落从第0小节开始
                    // 否则，段落从当前正在处理的小节开始
                    let sectionStartMeasure = measures.isEmpty ? 0 : max(0, measures.count - 1)
                    sectionMarkers[sectionStartMeasure] = sectionName
                    input.removeFirst(2)
                    matched = true
                }
            }
            
            // 规则3: 拍号 T44, T34...
            if !matched, let first = input.first, first == "T" {
                let digits = input.dropFirst().prefix { $0.isNumber }
                if !digits.isEmpty {
                    let sig = String(digits)
                    if firstTimeSignature == nil {
                        firstTimeSignature = sig
                    }
                    uniqueTimeSignatures.insert(sig)
                    timeSignature = sig
                    input.removeFirst(1 + digits.count)
                    matched = true
                }
            }
            
            // 规则4: 单小节反复 x
            if !matched, input.hasPrefix("x") {
                if measures.count >= 2 {
                    measures[measures.count - 1] = measures[measures.count - 2]
                    // ✅ 修复：直接追加时值副本，确保 measures 与 allDurations 同步增长
                    if !allDurations.isEmpty {
                        allDurations.append(allDurations.last!)
                    }
                }
                // ===== 探针：P0 规则4 =====
                #if DEBUG
                dprint("[DIFF] 规则4-x: m=\(measures.count) d=\(allDurations.count) diff=\(measures.count - allDurations.count) (正常应为1)")
                #endif
                input.removeFirst(1)
                matched = true
            }
            
            // 规则5: Kcl 重复上一小节并创建新小节
            if !matched, input.hasPrefix("Kcl") {
                if measures.count >= 1 {
                    measures.append(measures[measures.count - 1])
                    if !allDurations.isEmpty {
                        allDurations.append(allDurations.last!)
                    } else {
                        let beats = Double(timeSignature.first?.wholeNumberValue ?? 4)
                        allDurations.append([beats])
                    }
                }
                // ===== 探针：P0 规则5 =====
                #if DEBUG
                dprint("[DIFF] 规则5-Kcl: m=\(measures.count) d=\(allDurations.count) diff=\(measures.count - allDurations.count) (正常应为1)")
                #endif
                input.removeFirst(3)
                matched = true
            }
            
            // 规则6: 双小节反复 r
            if !matched, input.hasPrefix("r") {
                if measures.count >= 3 {
                    measures[measures.count - 1] = measures[measures.count - 3]
                    measures.append(measures[measures.count - 2])
                    // ✅ 修复：直接追加两个时值副本，不再错误地修改上一个小节的时值
                    if allDurations.count >= 2 {
                        allDurations.append(allDurations[allDurations.count - 2])
                        allDurations.append(allDurations[allDurations.count - 2])
                    }
                }
                // ===== 探针：P0 规则6 =====
                #if DEBUG
                dprint("[DIFF] 规则6-r: m=\(measures.count) d=\(allDurations.count) diff=\(measures.count - allDurations.count) (正常应为1)")
                #endif
                input.removeFirst(1)
                matched = true
            }
            
            // 规则7: Y 垂直空格
            if !matched, let first = input.first, first == "Y" {
                while let first = input.first, first == "Y" {
                    input.removeFirst()
                }
                matched = true
            }
            
            // 规则8: n = N.C. 无和弦
            if !matched, input.hasPrefix("n") {
                if measures.isEmpty { measures.append([]) }
                measures[measures.count - 1].append("N.C.")
                // ===== 探针：P0 规则8 + P1 N.C. =====
                #if DEBUG
                dprint("[NC] 命中N.C.小节，当前measures数=\(measures.count)")
                #endif
                #if DEBUG
                dprint("[DIFF] 规则8-NC: m=\(measures.count) d=\(allDurations.count) diff=\(measures.count - allDurations.count) (正常应为1)")
                #endif
                input.removeFirst(1)
                matched = true
            }
            
            // 规则9: p 休止符
            if !matched, input.hasPrefix("p") {
                input.removeFirst(1)
                matched = true
            }
            
            // 规则10: U 结束小节
            if !matched, input.hasPrefix("U") {
                input.removeFirst(1)
                matched = true
            }
            
            // 规则11: S Segno
            if !matched, input.hasPrefix("S") {
                input.removeFirst(1)
                matched = true
            }
            
            // 规则12: Q Coda
            if !matched, input.hasPrefix("Q") {
                input.removeFirst(1)
                matched = true
            }
            
            // 规则13: { 开始反复
            if !matched, input.hasPrefix("{") {
                if !currentChordStarts.isEmpty {
                    let durations = calculateChordDurations(starts: currentChordStarts, timeSignature: timeSignature)
                    allDurations.append(durations)
                } else if measures.last?.first == "N.C." {
                    let beats = Double(timeSignature.first?.wholeNumberValue ?? 4)
                    allDurations.append([beats])
                }
                
                if measures.isEmpty || !measures.last!.isEmpty {
                    measures.append([])
                }
                startRepeatLocation = measures.count - 1
                endRepeatLocation = nil
                // 重置当前小节状态
                currentChordStarts = []
                currentCell = 0
                
                // ===== 探针：P0 规则13 =====
                #if DEBUG
                dprint("[DIFF] 规则13-braceOpen: m=\(measures.count) d=\(allDurations.count) diff=\(measures.count - allDurations.count) (正常应为1)")
                #endif
                input.removeFirst(1)
                matched = true
            }
            
            // 规则14: } 结束反复
            if !matched, input.hasPrefix("}") {
                if !currentChordStarts.isEmpty {
                    let durations = calculateChordDurations(starts: currentChordStarts, timeSignature: timeSignature)
                    allDurations.append(durations)
                } else if measures.last?.first == "N.C." {
                    let beats = Double(timeSignature.first?.wholeNumberValue ?? 4)
                    allDurations.append([beats])
                }
                
                let endLoc = endRepeatLocation ?? measures.count
                let repeatedSection = Array(measures[startRepeatLocation..<endLoc])
                measures.append(contentsOf: repeatedSection)
                
                // 同时复制反复部分的时值
                if startRepeatLocation < allDurations.count && endLoc <= allDurations.count {
                    let repeatedDurations = Array(allDurations[startRepeatLocation..<endLoc])
                    allDurations.append(contentsOf: repeatedDurations)
                }
                
                measures.append([])
                currentChordStarts = []
                currentCell = 0
                
                // ===== 探针：P0 规则14 + P1 反复 =====
                #if DEBUG
                dprint("[REPEAT] 复制范围: start=\(startRepeatLocation) end=\(endLoc) 复制数量=\(endLoc - startRepeatLocation)")
                #endif
                #if DEBUG
                dprint("[REPEAT] allDurations范围检查: startValid=\(startRepeatLocation < allDurations.count - (endLoc - startRepeatLocation)) endValid=\((endLoc) <= allDurations.count - (endLoc - startRepeatLocation))")
                #endif
                #if DEBUG
                dprint("[DIFF] 规则14-braceClose: m=\(measures.count) d=\(allDurations.count) diff=\(measures.count - allDurations.count) (正常应为1)")
                #endif
                input.removeFirst(1)
                matched = true
            }
            
            // 规则15: LZ| 或 LZ 小节线
            if !matched, input.hasPrefix("LZ|") {
                if !currentChordStarts.isEmpty {
                    let durations = calculateChordDurations(starts: currentChordStarts, timeSignature: timeSignature)
                    allDurations.append(durations)
                } else if measures.last?.first == "N.C." {
                    let beats = Double(timeSignature.first?.wholeNumberValue ?? 4)
                    allDurations.append([beats])
                }
                
                if measures.isEmpty || !measures.last!.isEmpty {
                    measures.append([])
                }
                // 重置当前小节状态
                currentChordStarts = []
                currentCell = 0
                
                // ===== 探针：P0 规则15a =====
                #if DEBUG
                dprint("[DIFF] 规则15a-LZbar: m=\(measures.count) d=\(allDurations.count) diff=\(measures.count - allDurations.count) (正常应为1)")
                #endif
                input.removeFirst(3)
                matched = true
            }
            if !matched, input.hasPrefix("LZ") {
                if !currentChordStarts.isEmpty {
                    let durations = calculateChordDurations(starts: currentChordStarts, timeSignature: timeSignature)
                    allDurations.append(durations)
                } else if measures.last?.first == "N.C." {
                    let beats = Double(timeSignature.first?.wholeNumberValue ?? 4)
                    allDurations.append([beats])
                }
                
                if measures.isEmpty || !measures.last!.isEmpty {
                    measures.append([])
                }
                // 重置当前小节状态
                currentChordStarts = []
                currentCell = 0
                
                // ===== 探针：P0 规则15b =====
                #if DEBUG
                dprint("[DIFF] 规则15b-LZ: m=\(measures.count) d=\(allDurations.count) diff=\(measures.count - allDurations.count) (正常应为1)")
                #endif
                input.removeFirst(2)
                matched = true
            }
            
            // 规则16: | 小节线
            if !matched, input.hasPrefix("|") {
                if !currentChordStarts.isEmpty {
                    let durations = calculateChordDurations(starts: currentChordStarts, timeSignature: timeSignature)
                    allDurations.append(durations)
                } else if measures.last?.first == "N.C." {
                    let beats = Double(timeSignature.first?.wholeNumberValue ?? 4)
                    allDurations.append([beats])
                }
                
                if measures.isEmpty || !measures.last!.isEmpty {
                    measures.append([])
                }
                // 重置当前小节状态
                currentChordStarts = []
                currentCell = 0
                
                // ===== 探针：P0 规则16 =====
                #if DEBUG
                dprint("[DIFF] 规则16-bar: m=\(measures.count) d=\(allDurations.count) diff=\(measures.count - allDurations.count) (正常应为1)")
                #endif
                input.removeFirst(1)
                matched = true
            }
            
            // 规则17: [ 双小节线开始
            if !matched, input.hasPrefix("[") {
                if !currentChordStarts.isEmpty {
                    let durations = calculateChordDurations(starts: currentChordStarts, timeSignature: timeSignature)
                    allDurations.append(durations)
                } else if measures.last?.first == "N.C." {
                    let beats = Double(timeSignature.first?.wholeNumberValue ?? 4)
                    allDurations.append([beats])
                }
                
                if measures.isEmpty || !measures.last!.isEmpty {
                    measures.append([])
                }
                // 重置当前小节状态
                currentChordStarts = []
                currentCell = 0
                
                // ===== 探针：P0 规则17 =====
                #if DEBUG
                dprint("[DIFF] 规则17-doubleLeft: m=\(measures.count) d=\(allDurations.count) diff=\(measures.count - allDurations.count) (正常应为1)")
                #endif
                input.removeFirst(1)
                matched = true
            }
            
            // 规则18: ] 双小节线结束
            if !matched, input.hasPrefix("]") {
                if !currentChordStarts.isEmpty {
                    let durations = calculateChordDurations(starts: currentChordStarts, timeSignature: timeSignature)
                    allDurations.append(durations)
                } else if measures.last?.first == "N.C." {
                    let beats = Double(timeSignature.first?.wholeNumberValue ?? 4)
                    allDurations.append([beats])
                }
                
                if measures.isEmpty || !measures.last!.isEmpty {
                    measures.append([])
                }
                // 重置当前小节状态
                currentChordStarts = []
                currentCell = 0
                
                // ===== 探针：P0 规则18 =====
                #if DEBUG
                dprint("[DIFF] 规则18-doubleRight: m=\(measures.count) d=\(allDurations.count) diff=\(measures.count - allDurations.count) (正常应为1)")
                #endif
                input.removeFirst(1)
                matched = true
            }
            
            // 规则19: N1, N2... 编号结尾
            if !matched, let first = input.first, first == "N" {
                let digits = input.dropFirst().prefix { $0.isNumber }
                if !digits.isEmpty, let ending = Int(digits) {
                    if ending == 1 {
                        endRepeatLocation = measures.count - 1
                    }
                    input.removeFirst(1 + digits.count)
                    matched = true
                }
            }
            
            // 规则20: Z 终止线
            if !matched, input.hasPrefix("Z") {
                if !currentChordStarts.isEmpty {
                    let durations = calculateChordDurations(starts: currentChordStarts, timeSignature: timeSignature)
                    allDurations.append(durations)
                } else if measures.last?.first == "N.C." {
                    let beats = Double(timeSignature.first?.wholeNumberValue ?? 4)
                    allDurations.append([beats])
                }
                
                if measures.isEmpty || !measures.last!.isEmpty {
                    measures.append([])
                }
                // 重置当前小节状态
                currentChordStarts = []
                currentCell = 0
                
                // ===== 探针：P0 规则20 =====
                #if DEBUG
                dprint("[DIFF] 规则20-finalBar: m=\(measures.count) d=\(allDurations.count) diff=\(measures.count - allDurations.count) (正常应为1)")
                #endif
                input.removeFirst(1)
                matched = true
            }
            
            // 规则21: 替代和弦（圆括号括起来的），直接跳过（播放器会忽略替代和弦）
            if !matched, input.hasPrefix("(") {
                if let endIndex = input.firstIndex(of: ")") {
                    // 跳过整个括号内容
                    input = String(input[input.index(after: endIndex)...])
                } else {
                    // 没有右括号，直接跳过左括号
                    input.removeFirst()
                }
                matched = true
            }
            
            // 规则22: 和弦匹配 (A-G 或 W 开头)（占1个单元格）
            if !matched {
                let chordMatch = matchChord(input)
                if let chordMatch = chordMatch {
                    if measures.isEmpty {
                        measures.append([])
                        currentChordStarts = []
                        currentCell = 0
                    }
                    
                    var chord = chordMatch.chord
                    // W = 隐形斜杠和弦，继承上一个和弦的根音
                    if chord.hasPrefix("W"), let last = lastChord {
                        chord = chord.replacingOccurrences(of: "W", with: last)
                    } else {
                        // 记录根音（去掉斜杠部分）
                        if let slashIndex = chord.firstIndex(of: "/") {
                            lastChord = String(chord[..<slashIndex])
                        } else {
                            lastChord = chord
                        }
                    }
                    
                    // 记录和弦的起始单元格位置
                    currentChordStarts.append(currentCell)
                    currentCell += 1
                    
                    measures[measures.count - 1].append(chord)
                    input.removeFirst(chordMatch.length)
                    matched = true
                }
            }
            
            // 都没匹配上，跳过一个字符
            if !matched && !input.isEmpty {
                input.removeFirst()
            }
        }
        
        // 处理最后一个小节的时值
        if !currentChordStarts.isEmpty {
            let durations = calculateChordDurations(starts: currentChordStarts, timeSignature: timeSignature)
            allDurations.append(durations)
        } else if measures.last?.first == "N.C." {
            let beats = Double(timeSignature.first?.wholeNumberValue ?? 4)
            allDurations.append([beats])
        } else if !measures.isEmpty && measures.last!.isEmpty && allDurations.count < measures.count {
            allDurations.append([])
        }

        // ===== 探针：P0 末尾 =====
        #if DEBUG
        dprint("[DIFF] 解析结束(收尾后): m=\(measures.count) d=\(allDurations.count) diff=\(measures.count - allDurations.count)")
        #endif
        
        // 🔧 智能对齐：提取所有非空的时值数组，和非空小节一一对应
        // 解决连续小节线导致的错位问题
        let nonEmptyDurations = allDurations.filter { !$0.isEmpty }
        let nonEmptyMeasures = measures.filter { !$0.isEmpty }
        let beatsPerMeasure = Double(timeSignature.first?.wholeNumberValue ?? 4)

        // ===== 探针：P1 对齐 =====
        #if DEBUG
        dprint("[ALIGN] 过滤前: m=\(measures.count) d=\(allDurations.count)")
        #endif
        
        // 🌟 建立原始索引 → 新索引的映射（过滤空小节后索引会变）
        var indexMapping: [Int: Int] = [:]
        var newIndex = 0
        for (i, measure) in measures.enumerated() {
            if !measure.isEmpty {
                indexMapping[i] = newIndex
                newIndex += 1
            }
        }
        
        // 🌟 调整段落标记的索引
        var adjustedSectionMarkers: [Int: String] = [:]
        for (originalIndex, name) in sectionMarkers {
            if let newIdx = indexMapping[originalIndex] {
                adjustedSectionMarkers[newIdx] = name
            }
        }
        
        var finalMeasures: [[String]] = []
        var finalDurations: [[Double]] = []
        
        for (i, measure) in nonEmptyMeasures.enumerated() {
            finalMeasures.append(measure)
            
            if i < nonEmptyDurations.count && nonEmptyDurations[i].count == measure.count {
                // 数量一致，用真实时值
                finalDurations.append(nonEmptyDurations[i])
            } else {
                // 数量不一致，兜底用平均分配
                let count = measure.count
                finalDurations.append(Array(repeating: beatsPerMeasure / Double(count), count: count))
            }
        }

        // ===== 探针：P1 对齐后 =====
        #if DEBUG
        dprint("[ALIGN] 过滤后: m=\(finalMeasures.count) d=\(finalDurations.count)")
        #endif
        
        timeSignature = firstTimeSignature ?? timeSignature
        let hasMixed = uniqueTimeSignatures.count > 1

        return (finalMeasures, finalDurations, timeSignature, adjustedSectionMarkers, hasMixed)
    }
    
    // MARK: - 辅助：计算和弦时值
    private static func calculateChordDurations(starts: [Double], timeSignature: String) -> [Double] {
        guard !starts.isEmpty else { return [] }
        
        // 拍号格式："44" = 4/4, "34" = 3/4, "128" = 12/8
        let tsChars = Array(timeSignature)
        let numerStr: String
        let denomStr: String
        if tsChars.count >= 3 {
            numerStr = String(tsChars[0]) + String(tsChars[1])
            denomStr = String(tsChars[2])
        } else {
            numerStr = String(tsChars[0])
            denomStr = String(tsChars[1])
        }
        guard tsChars.count >= 2,
              let beatsPerMeasure = Double(numerStr),
              let beatUnit = Double(denomStr) else {
            // 默认 4/4 拍：4个单元格，每个1拍
            return calculateDurations(starts: starts, totalCells: 4, beatsPerCell: 1.0)
        }
        
        // 总单元格数 = 拍号分子（每小节拍数）
        // 每个单元格的拍数 = 4.0 / 拍号分母（比如 4/4 拍 = 1拍，6/8 拍 = 0.5拍）
        let totalCells = beatsPerMeasure
        let beatsPerCell = 4.0 / beatUnit
        
        return calculateDurations(starts: starts, totalCells: totalCells, beatsPerCell: beatsPerCell)
    }
    
    private static func calculateDurations(starts: [Double], totalCells: Double, beatsPerCell: Double) -> [Double] {
        var durations: [Double] = []
        
        for i in 0..<starts.count {
            let start = starts[i]
            let end: Double
            if i < starts.count - 1 {
                end = starts[i + 1]
            } else {
                end = totalCells
            }
            let cellDuration = end - start
            let beatDuration = cellDuration * beatsPerCell
            durations.append(beatDuration)
        }
        
        return durations
    }
    
    /// 匹配和弦
    private static func matchChord(_ input: String) -> (chord: String, length: Int)? {
        let chars = Array(input)
        guard !chars.isEmpty else { return nil }
        
        // 根音必须是 A-G 或 W
        let firstChar = chars[0]
        guard (firstChar.isUppercase && "A" <= firstChar && firstChar <= "G") || firstChar == "W" else {
            return nil
        }
        
        var i = 1
        
        // 升降号
        if i < chars.count && (chars[i] == "#" || chars[i] == "b") {
            i += 1
        }
        
        // 后缀字符: + - ^ h o b # s u a d l t 数字
        let suffixChars: Set<Character> = ["+", "-", "^", "h", "o", "b", "#", "s", "u", "a", "d", "l", "t", "%", "j", "e"]
        
        while i < chars.count {
            let c = chars[i]
            if c.isNumber || suffixChars.contains(c) {
                i += 1
            } else {
                break
            }
        }
        
        // 斜杠和弦
        if i < chars.count && chars[i] == "/" {
            i += 1
            // 低音音符
            if i < chars.count && chars[i].isUppercase && "A" <= chars[i] && chars[i] <= "G" {
                i += 1
                // 低音升降号
                if i < chars.count && (chars[i] == "#" || chars[i] == "b") {
                    i += 1
                }
            }
        }
        
        let chord = String(chars[0..<i])
        return (chord, i)
    }
    
    // MARK: - 辅助：从 style 字符串中提取/推断 BPM
    private static func extractTempo(from style: String) -> Int {
        // 1. 先尝试从 style 文本中直接提取数字（比如 "Slow Swing 120"）
        let digits = style.filter { $0.isNumber }
        if let tempo = Int(digits), tempo >= 40, tempo <= 300 {
            return tempo
        }
        
        // 2. 根据风格关键词精准匹配 iReal Pro 默认 BPM
        // 注意：更具体的风格要放在前面，避免被通用关键词提前匹配
        let lowercased = style.lowercased()
        
        if lowercased.contains("ballad swing") {
            return 60
        }
        if lowercased.contains("slow swing") {
            return 80
        }
        if lowercased.contains("medium up swing") {
            return 160
        }
        if lowercased.contains("medium swing") {
            return 120
        }
        if lowercased.contains("up tempo swing") {
            return 240
        }
        if lowercased.contains("afro 12/8") || lowercased.contains("afro 12-8") {
            return 110
        }
        if lowercased.contains("even 8ths") {
            return 140
        }
        if lowercased.contains("bossa nova") {
            return 140
        }
        if lowercased.contains("shuffle") {
            return 90
        }
        if lowercased.contains("samba") {
            return 200
        }
        if lowercased.contains("funk") {
            return 140
        }
        if lowercased.contains("latin") {
            return 180
        }
        if lowercased.contains("rock") {
            return 70
        }
        
        // 3. 通用关键词兜底
        if lowercased.contains("swing") {
            return 120
        }
        if lowercased.contains("slow") {
            return 80
        }
        if lowercased.contains("medium") {
            return 120
        }
        if lowercased.contains("up") || lowercased.contains("fast") || lowercased.contains("bebop") {
            return 180
        }
        if lowercased.contains("ballad") {
            return 60
        }
        
        // 4. 最终兜底默认值
        return 120
    }
    
    // MARK: - 5. 转换为 JazzSong 模型
    static func toJazzSong(_ parsed: IRealParsedSong) -> JazzSong {
        // 和弦后缀标准化
        let standardizedMeasures = parsed.measures.map { chords in
            chords.map { standardizeChordShorthand($0) }
        }
        
        return JazzSong(
            title: parsed.title,
            composer: parsed.composer,
            style: parsed.style,
            tempo: parsed.tempo,
            key: standardizeKey(parsed.key),
            timeSignature: formatTimeSignature(parsed.timeSignature),
            measures: standardizedMeasures,
            measureDurations: parsed.measureDurations,
            sectionMarkers: parsed.sectionMarkers,
            hasMixedTimeSignature: parsed.hasMixedTimeSignature
        )
    }
    
    /// 拍号格式转换："44" → "4/4"，"128" → "12/8"
    private static func formatTimeSignature(_ raw: String) -> String {
        // 2 字符拍号
        guard raw.count == 2, let first = raw.first, let last = raw.last else {
            // 3 字符拍号 (如 "128" → "12/8")
            if raw.count == 3, let denom = raw.last {
                let numer = raw.prefix(raw.count - 1)
                return "\(numer)/\(denom)"
            }
            return "4/4"
        }
        return "\(first)/\(last)"
    }
    
    // 调号标准化
    private static func standardizeKey(_ key: String) -> String {
        var k = key
        // 把小调的 - 换成 m
        if k.hasSuffix("-") {
            k = String(k.dropLast()) + "m"
        }
        // G# → Ab 等音映射（G# major = Ab major，G# minor = Ab minor）
        if k.hasPrefix("G#") {
            k = k.replacingOccurrences(of: "G#", with: "Ab")
        }
        return k
    }
    
    // MARK: - 6. 和弦后缀标准化（可选）
    static func standardizeChordShorthand(_ ireal: String) -> String {
        var std = ireal
        
        // 半减七系列
        std = std.replacingOccurrences(of: "-7b5", with: "m7b5")
        std = std.replacingOccurrences(of: "h7", with: "m7b5")
        std = std.replacingOccurrences(of: "h9", with: "m9b5")
        std = std.replacingOccurrences(of: "h", with: "m7b5")
        std = std.replacingOccurrences(of: "-b5", with: "m7b5")
        
        // 减和弦系列
        std = std.replacingOccurrences(of: "o7", with: "dim7")
        std = std.replacingOccurrences(of: "o", with: "dim")
        
        // 大和弦系列
        std = std.replacingOccurrences(of: "^7#5", with: "maj7#5")
        std = std.replacingOccurrences(of: "^7b5", with: "maj7b5")
        std = std.replacingOccurrences(of: "^9#11", with: "maj9#11")
        std = std.replacingOccurrences(of: "^13", with: "maj13")
        std = std.replacingOccurrences(of: "^9", with: "maj9")
        std = std.replacingOccurrences(of: "^7", with: "maj7")
        std = std.replacingOccurrences(of: "^69", with: "maj69")
        std = std.replacingOccurrences(of: "^6", with: "maj6")
        std = std.replacingOccurrences(of: "^", with: "maj")
        
        // 小和弦系列
        std = std.replacingOccurrences(of: "-13", with: "m13")
        std = std.replacingOccurrences(of: "-11", with: "m11")
        std = std.replacingOccurrences(of: "-9#11", with: "m9#11")
        std = std.replacingOccurrences(of: "-9", with: "m9")
        std = std.replacingOccurrences(of: "-7#5", with: "m7#5")
        std = std.replacingOccurrences(of: "-7", with: "m7")
        std = std.replacingOccurrences(of: "-69", with: "m69")
        std = std.replacingOccurrences(of: "-6", with: "m6")
        std = std.replacingOccurrences(of: "-", with: "m")
        
        // 属七挂留系列
        std = std.replacingOccurrences(of: "sus", with: "sus4")
        std = std.replacingOccurrences(of: "sus44", with: "sus4")
        std = std.replacingOccurrences(of: "sus42", with: "sus2")
        
        // 属七变化系列
        std = std.replacingOccurrences(of: "7alt", with: "7alt")
        std = std.replacingOccurrences(of: "7#9#5", with: "7#9#5")
        std = std.replacingOccurrences(of: "7#9b5", with: "7#9b5")
        std = std.replacingOccurrences(of: "7b9#5", with: "7b9#5")
        std = std.replacingOccurrences(of: "7b9b5", with: "7b9b5")
        std = std.replacingOccurrences(of: "7#9", with: "7#9")
        std = std.replacingOccurrences(of: "7b9", with: "7b9")
        std = std.replacingOccurrences(of: "7#5", with: "7#5")
        std = std.replacingOccurrences(of: "7b5", with: "7b5")
        std = std.replacingOccurrences(of: "9#11", with: "9#11")
        std = std.replacingOccurrences(of: "9b5", with: "9b5")
        std = std.replacingOccurrences(of: "13#11", with: "13#11")
        std = std.replacingOccurrences(of: "13b9", with: "13b9")
        
        // 增和弦系列
        std = std.replacingOccurrences(of: "aug", with: "aug")
        std = std.replacingOccurrences(of: "+", with: "aug")
        
        // 加音和弦
        std = std.replacingOccurrences(of: "add9", with: "add9")
        std = std.replacingOccurrences(of: "add11", with: "add11")
        
        // 六九和弦
        std = std.replacingOccurrences(of: "69", with: "69")
        
        return std
    }
}
