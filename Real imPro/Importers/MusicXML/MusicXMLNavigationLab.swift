#if DEBUG
import Foundation

// MARK: - G4 导航记号 DEBUG Lab（D.S. / D.C. / Coda / Fine）
// 自包含测试夹具（内联 XML，不依赖 bundle 资源）。在 LLDB 里触发：
//   expr -l Swift -- MusicXMLNavigationLab.run()
// 金标准：手算双盲 + 外审封存 + Gemini 独立锚点（Senza ripetizione 语义 A）。
enum MusicXMLNavigationLab {

    private static let header = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="3.1">
      <part-list><score-part id="P1"><part-name>Lead</part-name></score-part></part-list>
      <part id="P1">
    """
    private static let footer = "</part></score-partwise>"

    private static func meas(_ n: Int, _ body: String) -> String {
        "<measure number=\"\(n)\">\(body)</measure>"
    }
    private static func attrs() -> String {
        "<attributes><divisions>4</divisions><key><fifths>0</fifths></key>"
        + "<time><beats>4</beats><beat-type>4</beat-type></time>"
        + "<clef><sign>G</sign><line>2</line></clef></attributes>"
    }
    private static func note(_ step: String, _ oct: Int, alter: Int? = nil) -> String {
        let al = alter.map { "<alter>\($0)</alter>" } ?? ""
        let h = "<harmony><root><root-step>C</root-step></root><kind>major</kind></harmony>"
        return h + "<note><pitch><step>\(step)</step>\(al)<octave>\(oct)</octave></pitch>"
            + "<duration>16</duration><type>whole</type></note>"
    }

    // MARK: 四首合规谱
    private static func nav1() -> String {
        var x = header
        x += meas(1, attrs() + note("C", 4))
        x += meas(2, "<direction><direction-type><segno id=\"segno1\"/></direction-type></direction>" + note("D", 4))
        x += meas(3, note("E", 4))
        x += meas(4, "<direction><direction-type><words>To Coda</words></direction-type><sound tocoda=\"coda1\"/></direction>" + note("F", 4))
        x += meas(5, note("G", 4))
        x += meas(6, "<direction><direction-type><words>D.S. al Coda</words></direction-type><sound dalsegno=\"segno1\"/></direction>" + note("A", 4))
        x += meas(7, "<direction><direction-type><coda id=\"coda1\"/></direction-type></direction>" + note("C", 5))
        x += meas(8, note("B", 4))
        return x + footer
    }

    // 无点缩写：words 写 "DS"（无点、无 sound），仍须识别为 D.S.
    private static func noDotDS() -> String {
        var x = header
        x += meas(1, attrs() + note("C", 4))
        x += meas(2, "<direction><direction-type><segno id=\"segno1\"/></direction-type></direction>" + note("D", 4))
        x += meas(3, note("E", 4))
        x += meas(4, "<direction><direction-type><words>DS</words></direction-type></direction>" + note("F", 4))
        x += meas(5, note("G", 4))
        return x + footer
    }

    // 负用例：普通单词 Heads/Rides 不得被无点正则误判为导航
    private static func negativeWords() -> String {
        var x = header
        x += meas(1, attrs() + note("C", 4))
        x += meas(2, "<direction><direction-type><words>Heads</words></direction-type></direction>" + note("D", 4))
        x += meas(3, "<direction><direction-type><words>Rides</words></direction-type></direction>" + note("E", 4))
        x += meas(4, note("F", 4))
        return x + footer
    }

    // 负用例：只有 segno 字形、无任何 D.S./D.C. 指令（模拟 Het_dorp/Patsy）。
    // hasNav 会因字形为 true，但没有可执行跳转，navigationNotExpanded 必须为 false（不弹横幅）。
    private static func segnoOnly() -> String {
        var x = header
        x += meas(1, attrs() + note("C", 4))
        x += meas(2, "<direction><direction-type><segno id=\"s1\"/></direction-type></direction>" + note("D", 4))
        x += meas(3, note("E", 4))
        x += meas(4, "<direction><direction-type><segno id=\"s2\"/></direction-type></direction>" + note("F", 4))
        x += meas(5, note("G", 4))
        return x + footer
    }

    // 负用例：segno 字形 + 独立 Fine 文字、但无任何 D.S./D.C. 跳转（模拟 Patsy）。
    // 孤立 Fine 没有跳回配合，播放上无意义；navigationNotExpanded 必须为 false（不弹横幅）。
    private static func fineOnly() -> String {
        var x = header
        x += meas(1, attrs() + note("C", 4))
        x += meas(2, "<direction><direction-type><segno id=\"s1\"/></direction-type></direction>" + note("D", 4))
        x += meas(3, note("E", 4))
        x += meas(4, "<direction><direction-type><words>Fine</words></direction-type></direction>" + note("F", 4))
        x += meas(5, note("G", 4))
        return x + footer
    }

    private static func nav3() -> String {
        var x = header
        x += meas(1, attrs() + "<barline location=\"left\"><repeat direction=\"forward\"/></barline>" + note("C", 4))
        x += meas(2, "<direction><direction-type><segno id=\"segno1\"/></direction-type></direction>" + note("C", 4, alter: 1))
        x += meas(3, note("D", 4))
        x += meas(4, "<barline location=\"right\"><repeat direction=\"backward\"/></barline>" + note("D", 4, alter: 1))
        x += meas(5, note("E", 4))
        x += meas(6, note("F", 4))
        x += meas(7, "<direction><direction-type><words>D.S.</words></direction-type><sound dalsegno=\"segno1\"/></direction>" + note("F", 4, alter: 1))
        x += meas(8, note("G", 4))
        x += meas(9, note("G", 4, alter: 1))
        x += meas(10, note("A", 4))
        return x + footer
    }

    private static func nav4() -> String {
        var x = header
        x += meas(1, attrs() + "<barline location=\"left\"><repeat direction=\"forward\"/></barline>" + note("C", 4))
        x += meas(2, note("C", 4, alter: 1))
        x += meas(3, "<barline location=\"right\"><repeat direction=\"backward\"/></barline>" + note("D", 4))
        x += meas(4, note("D", 4, alter: 1))
        x += meas(5, "<direction><direction-type><words>Fine</words></direction-type></direction>" + note("E", 4))
        x += meas(6, note("F", 4))
        x += meas(7, note("F", 4, alter: 1))
        x += meas(8, "<direction><direction-type><words>D.C. al Fine</words></direction-type><sound dacapo=\"yes\"/></direction>" + note("G", 4))
        return x + footer
    }

    private static func nav6() -> String {
        var x = header
        x += meas(1, attrs() + note("C", 4))
        x += meas(2, "<direction><direction-type><segno id=\"segno1\"/></direction-type></direction>" + note("C", 4, alter: 1))
        x += meas(3, note("D", 4))
        x += meas(4, note("D", 4, alter: 1))
        x += meas(5, note("E", 4))
        x += meas(6, note("F", 4))
        x += meas(7, "<direction><direction-type><coda id=\"codaMark\"/></direction-type></direction><direction><direction-type><words>To Coda</words></direction-type><sound tocoda=\"coda1\"/></direction>" + note("F", 4, alter: 1))
        x += meas(8, note("G", 4))
        x += meas(9, note("G", 4, alter: 1))
        x += meas(10, "<direction><direction-type><words>D.S. al Coda</words></direction-type><sound dalsegno=\"segno1\"/></direction>" + note("A", 4))
        x += meas(11, "<direction><direction-type><coda id=\"coda1\"/></direction-type></direction>" + note("A", 4, alter: 1))
        x += meas(12, note("B", 4))
        return x + footer
    }

    // MARK: 运行
    @discardableResult
    static func run() -> Bool {
        func log(_ s: String) { print(s); NSLog(s) }
        let cases: [(String, String, [Int])] = [
            ("Nav1 DS al Coda", nav1(), [0,1,2,3,4,5,1,2,3,6,7]),
            ("Nav3 Repeat + DS", nav3(), [0,1,2,3,0,1,2,3,4,5,6,1,2,3,4,5,6,7,8,9]),
            ("Nav4 Repeat + DC Fine", nav4(), [0,1,2,0,1,2,3,4,5,6,7,0,1,2,3,4]),
            ("Nav6 Two Coda DS", nav6(), [0,1,2,3,4,5,6,7,8,9,1,2,3,4,5,6,10,11]),
            ("NoDot DS", noDotDS(), [0,1,2,3,1,2,3,4]),
        ]
        var fail = 0
        for (name, xml, expected) in cases {
            do {
                let r = try MusicXMLImporter.importSong(data: xml.data(using: .utf8)!, fallbackTitle: "t")
                let bars = (r.song["measures"] as? [Any])?.count ?? -1
                let mm = r.song["measureMap"] as? [Int] ?? []
                if bars == expected.count, mm == expected {
                    log("✅ \(name): bars=\(bars)")
                } else {
                    fail += 1
                    log("❌ \(name): bars=\(bars) 期望=\(expected.count) map=\(mm)")
                }
            } catch {
                fail += 1
                log("❌ \(name) 抛错: \(error)")
            }
        }

        // 不合规降级
        let bad: [(String, [MXRawMeasure])] = [
            ("缺Segno", [rawMeasure([MXNavDirective(kind: .dalSegno(segnoId: nil))])]),
            ("Segno在Dir后", [
                rawMeasure([MXNavDirective(kind: .dalSegno(segnoId: nil))]),
                rawMeasure(marks: [MXNavMark(kind: .segno, id: nil)]),
            ]),
        ]
        for (name, raws) in bad {
            let id = Array(0..<raws.count)
            let r = MusicXMLRepeater.applyNavigation(map: id, raw: raws)
            if r.applied { fail += 1; log("❌ \(name) 未降级") }
            else { log("✅ \(name): 已降级") }
        }

        // 负用例：普通单词不得触发 hasNav，navigationNotExpanded 应为 false，map 保持线性
        do {
            let r = try MusicXMLImporter.importSong(data: negativeWords().data(using: .utf8)!, fallbackTitle: "t")
            let navNotExp = r.song["navigationNotExpanded"] as? Bool ?? true
            let mm = r.song["measureMap"] as? [Int] ?? []
            if !navNotExp && mm == [0,1,2,3] {
                log("✅ 负用例 Heads/Rides: 未误判，hasNav=false")
            } else {
                fail += 1
                log("❌ 负用例: navigationNotExpanded=\(navNotExp) map=\(mm)")
            }
        } catch {
            fail += 1; log("❌ 负用例抛错: \(error)")
        }

        // 负用例：segno-only 无指令 → 不弹横幅（navigationNotExpanded=false），map 保持线性
        do {
            let r = try MusicXMLImporter.importSong(data: segnoOnly().data(using: .utf8)!, fallbackTitle: "t")
            let navNotExp = r.song["navigationNotExpanded"] as? Bool ?? true
            let mm = r.song["measureMap"] as? [Int] ?? []
            if !navNotExp && mm == [0,1,2,3,4] {
                log("✅ 负用例 Segno-only: 无指令不弹横幅")
            } else {
                fail += 1
                log("❌ 负用例 Segno-only: navigationNotExpanded=\(navNotExp) map=\(mm)")
            }
        } catch {
            fail += 1; log("❌ 负用例 Segno-only 抛错: \(error)")
        }

        // 负用例：fine-only（segno + 独立 Fine，无 D.S./D.C.）→ 不弹横幅，map 保持线性
        do {
            let r = try MusicXMLImporter.importSong(data: fineOnly().data(using: .utf8)!, fallbackTitle: "t")
            let navNotExp = r.song["navigationNotExpanded"] as? Bool ?? true
            let mm = r.song["measureMap"] as? [Int] ?? []
            if !navNotExp && mm == [0,1,2,3,4] {
                log("✅ 负用例 Fine-only: 无 D.S./D.C. 不弹横幅")
            } else {
                fail += 1
                log("❌ 负用例 Fine-only: navigationNotExpanded=\(navNotExp) map=\(mm)")
            }
        } catch {
            fail += 1; log("❌ 负用例 Fine-only 抛错: \(error)")
        }

        log(fail == 0 ? "MusicXMLNavigationLab ALL PASS" : "MusicXMLNavigationLab FAIL \(fail)")
        return fail == 0
    }

    /// App 启动时调用；带启动参数 `-navLab` 才在正常运行时上下文跑一遍（LLDB 因 debug dylib
    /// 分离无法直接引用本类型，故走启动参数）。无参数日常运行什么都不做。
    static func checkLaunchEnvironment() {
        guard ProcessInfo.processInfo.arguments.contains("-navLab") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            _ = run()
        }
    }

    private static func rawMeasure(_ directives: [MXNavDirective] = [],
                                  marks: [MXNavMark] = []) -> MXRawMeasure {
        let m = MXRawMeasure()
        m.navDirectives = directives
        m.navMarks = marks
        return m
    }
}
#endif
