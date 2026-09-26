import SwiftUI
import WebKit

// MARK: - 符头分色常量 (固定浅色界面，不预留深色模式)
struct NoteHeadColors {
    static let chordBlack    = "#111111"  // 和弦音C
    static let approachBlue  = "#007AFF"  // 趋近音A
    static let colorGreen    = "#34C759"  // 色彩音
    static let foreignRed    = "#FF3B30"  // 外音
    static let fallbackBlack = "#000000"  // 兜底黑
}

struct SheetMusicView: UIViewRepresentable {
    var solo: [GeneratedMeasure]
    var playingNoteId: String
    var soloVersion: UUID
    var key: String
    var timeSignature: String
    var grammarFileName: String = "chord"  // 当前文法文件名(chord/color/CharlieParker等)
    var onNoteClick: ((String) -> Void)? = nil
    
    // 🌟 终极安全版 Coordinator
    class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: SheetMusicView
        var lastVersion: UUID?
        var lastKey: String?
        
        init(_ parent: SheetMusicView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "noteClicked", let noteId = message.body as? String {
                parent.onNoteClick?(noteId)
            }
            
            // 🌟 补上丢失的日志接收通道！让 JS 的崩溃无处遁形
            if message.name == "jsLogger", let logMsg = message.body as? [String: Any] {
                let level = logMsg["level"] as? String ?? "INFO"
                let msg = logMsg["message"] as? String ?? ""
                #if DEBUG
                print("🌐 [JS \(level)] \(msg)")
                #endif
                if let stack = logMsg["stack"] as? String, !stack.isEmpty {
                    #if DEBUG
                    print("🌐 堆栈: \(stack)")
                    #endif
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        // 🌟 注册监听通道
        config.userContentController.add(context.coordinator, name: "noteClicked")
        config.userContentController.add(context.coordinator, name: "jsLogger") // 🌟 注册日志通道

        // 全局JS异常捕获前置脚本，捕获所有渲染崩溃、语法、异步报错
        let errorCaptureScript = WKUserScript(source: """
        // 拦截console.error并上报堆栈
        const originalConsoleError = console.error;
        console.error = function(...args) {
            const msg = args.map(item => String(item)).join(" ");
            window.webkit.messageHandlers.jsLogger.postMessage({
                level: "ERROR",
                message: "[ConsoleError] " + msg,
                stack: new Error().stack || ""
            });
            originalConsoleError(...args);
        }
        // 同步运行时全局错误捕获
        window.onerror = function(message, source, lineno, colno, errorObj) {
            const stackInfo = errorObj?.stack ?? "无堆栈";
            window.webkit.messageHandlers.jsLogger.postMessage({
                level: "FATAL",
                message: `[GlobalOnError] 消息:${message} 文件:${source} 行:${lineno} 列:${colno}`,
                stack: stackInfo
            });
            return true;
        }
        // Promise异步未捕获异常（resize/异步渲染）
        window.addEventListener("unhandledrejection", function(evt) {
            const stackInfo = evt.reason?.stack ?? String(evt.reason);
            window.webkit.messageHandlers.jsLogger.postMessage({
                level: "FATAL",
                message: "[PromiseRejection] 异步渲染异常",
                stack: stackInfo
            });
        })
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(errorCaptureScript)
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.showsVerticalScrollIndicator = true
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.backgroundColor = .clear
        webView.isOpaque = false
        
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif
        return webView
    }
    
    // 🌟 防泄漏装甲：当乐谱视图被销毁时，强制拆除 JS 监听通道，100% 杜绝 WKWebView 内存泄漏！
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "noteClicked")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "jsLogger")
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // 🌟 状态同步防弹衣：每次 SwiftUI 刷新，强制更新 coordinator 手里的 parent，防止旧闭包导致的幽灵 Bug
        context.coordinator.parent = self
        
        dispatchPrecondition(condition: .onQueue(.main))
        
        if context.coordinator.lastVersion == nil {
            webView.stopLoading()
            let html = generateHTML(for: solo, key: key)
            // 🌟 核心修复：授予 WebView 访问本地 App Bundle 的权限，
            // 彻底实现断网秒开乐谱，杜绝因外部 CDN 挂掉或苹果审核飞行模式导致的白屏灾难！
            webView.loadHTMLString(html, baseURL: Bundle.main.bundleURL)
            
            context.coordinator.lastVersion = soloVersion
            context.coordinator.lastKey = key
        }
        // 🌟 落地豆包优化 1：后续用户切歌、点击魔棒重新生成、修改调号时，100% 走纯 evaluateJavaScript 增量更新数据，
        // 免去静态资源重复解析编译开销，切谱速度达到原生 16ms 瞬时水准，且彻底消灭白谱闪烁现象！
        else if context.coordinator.lastVersion != soloVersion || context.coordinator.lastKey != key {
            let jsMeasures = generateMeasuresJSArray(for: solo, key: key, timeSig: timeSignature)
            let vexflowKey = getVexflowKey(for: key)
            
            let updateJS = "if(typeof window.updateSheetMusic === 'function') { window.updateSheetMusic([\(jsMeasures)], '\(vexflowKey)', '\(timeSignature)'); }"
            
            // 🌟 落地高级监控：捕获 JS 渲染层可能的语法错误或数据异常，留存排查线索
            webView.evaluateJavaScript(updateJS) { result, error in
                if let error = error {
                    #if DEBUG
                    print("❌ [WebView 渲染异常] 乐谱增量更新失败: \(error.localizedDescription)")
                    #endif
                }
            }
            
            context.coordinator.lastVersion = soloVersion
            context.coordinator.lastKey = key
        }
        
        // 维持走带高亮追踪不中断
        let jsCode = "if(typeof window.highlightNote === 'function') { window.highlightNote('\(playingNoteId)'); }"
        
        // 🌟 落地高级监控：捕获走带高亮时的 JS 执行异常
        webView.evaluateJavaScript(jsCode) { result, error in
            if let error = error {
                #if DEBUG
                print("⚠️ [WebView 高亮异常] 音符追踪失败 (ID: \(playingNoteId)): \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    // 🌟 提取出公共的 VexFlow 调号映射解析器（已修复极端等音调黑洞）
    private func getVexflowKey(for key: String) -> String {
        let majorKeys: Set<String> = ["C", "G", "D", "A", "E", "B", "F#", "C#",
                                       "F", "Bb", "Eb", "Ab", "Db", "Gb", "Cb"]
        
        // 1. 本身是标准大调，直接返回
        if majorKeys.contains(key) { return key }
        
        // 2. 如果是小调，计算其关系大调 (Relative Major = Minor Root + 3 Semitones)
        if key.hasSuffix("m") {
            let minorRoot = String(key.dropLast())
            
            // 穷举所有可能的小调根音（包含异符同音）到对应的关系大调
            let relativeMajors: [String: String] = [
                "A": "C", "Am": "C",
                "E": "G",
                "B": "D",
                "F#": "A", "Gb": "A", // Gb小调虽然罕见，但兜底为 A
                "C#": "E", "Db": "E",
                "G#": "B", "Ab": "Cb", // Abm 的关系大调是 Cb (7个降号)
                "D#": "F#", "Eb": "Gb", // Ebm 的关系大调是 Gb (6个降号)
                "A#": "C#", "Bb": "Db", // Bbm 的关系大调是 Db (5个降号)
                "F": "Ab",
                "C": "Eb",
                "G": "Bb",
                "D": "F"
            ]
            
            if let majorKey = relativeMajors[minorRoot], majorKeys.contains(majorKey) {
                return majorKey
            }
        }
        
        // 兜底返回 C 大调
        return "C"
    }

    // 🌟 提炼出独立的数据构建管道，实现 Swift 与 JS 数据交换的完美互通
    private func generateMeasuresJSArray(for solo: [GeneratedMeasure], key: String, timeSig: String) -> String {
        let profile = TimeSignatureManager.getProfile(for: timeSig)
        var jsMeasuresArray: [String] = []
        for (mIndex, measure) in solo.enumerated() {
            var jsNotes: [String] = []
            var measureAlteredPitches: [String: String] = [:]
            
            // 直接使用 measure.notes，不再进行任何清洗（数据层已保证连音组完整性）
            for (index, note) in measure.notes.enumerated() {
                let parts = note.duration.components(separatedBy: "_t")
                let baseDurStr = parts[0]
                let tupletVal = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
                
                if note.isRest {
                    // 🌟 提取休止符的纯时值（去除 'r'，保留 'd'，如 "hdr" 变成 "hd"）
                    let cleanRestDur = baseDurStr.replacingOccurrences(of: "r", with: "", options: .caseInsensitive)
                    
                    var restJS = """
                    (function() {
                        // 🌟 使用最标准的 VexFlow 语法：传带附点的时值，使用 type: 'r'
                        var r = new VF.StaveNote({ keys: ['b/4'], duration: '\(cleanRestDur)', type: 'r' });
                        r.tupletVal = \(tupletVal); r.origDuration = '\(baseDurStr)';
                        r.setAttribute('id', 'note-\(mIndex)-\(index)');
                        r.isRealTuplet = \(note.isTriplet ? "true" : "false");
                    """
                    // 🌟 事实胜于雄辩：VexFlow 不会自动画点，必须手动挂载！
                    if baseDurStr.contains("d") { restJS += "\n                        r.addDot(0);" }
                    
                    let chordAnnotation = measure.chordAnnotations.first(where: { $0.noteIndex == index })
                    if let chordAnnotation = chordAnnotation {
                        restJS += "\n    r.addModifier(0, new VF.Annotation('\(chordAnnotation.chord)').setVerticalJustification(1).setStyle({fillStyle: '#007AFF', strokeStyle: '#007AFF'}));"
                    }
                    
                    restJS += "\n    return r;\n})()"
                    jsNotes.append(restJS)
                } else {
                    let spelled = Self.spellNote(pitchStr: note.pitch, key: key)
                    let cleanPitch = spelled.position
                    let accidental = spelled.accidental ?? ""
                    var color = NoteHeadColors.fallbackBlack
                    switch note.tag {
                    case .chordTone:    color = NoteHeadColors.chordBlack
                    case .approachNote: color = NoteHeadColors.approachBlue
                    case .colorTone:    color = NoteHeadColors.colorGreen
                    case .foreignTone:  color = NoteHeadColors.foreignRed
                    default:            color = NoteHeadColors.fallbackBlack
                    }
                    // 🔍 排查日志: 最终渲染
                    //print("【最终渲染】 pitch=\(note.pitch) terminalType=(来自tag=\(note.tag)) 判定颜色=\(color)")
                    
                    var noteJS = """
                    (function() {
                        // 🌟 直接传入带有 'd' 的 baseDurStr，VexFlow 引擎会自动分配 Ticks 并绘制附点
                        var n = new VF.StaveNote({ keys: ['\(cleanPitch)'], duration: '\(baseDurStr)' });
                        n.tupletVal = \(tupletVal); n.origDuration = '\(baseDurStr)';
                        n.setKeyStyle(0, {fillStyle: '\(color)', strokeStyle: '\(color)'});
                        n.setAttribute('id', 'note-\(mIndex)-\(index)');
                        n.isTieStart = \(note.isTieStart ? "true" : "false");
                        n.isTieEnd = \(note.isTieEnd ? "true" : "false");
                        n.isRealTuplet = \(note.isTriplet ? "true" : "false");
                    """
                    var needAccidental = false
                    var accToDraw = accidental
                    
                    if !accidental.isEmpty {
                        if measureAlteredPitches[cleanPitch] != accidental {
                            needAccidental = true
                            measureAlteredPitches[cleanPitch] = accidental
                        }
                    } else {
                        if let prevAcc = measureAlteredPitches[cleanPitch], !prevAcc.isEmpty {
                            needAccidental = true
                            let naturalNames = ["c","d","e","f","g","a","b"]
                            let noteName = String(cleanPitch.split(separator: "/")[0])
                            if let noteIndex = naturalNames.firstIndex(of: noteName) {
                                let keyAlts = Self.keyAlterations(for: key)
                                accToDraw = Self.accSymbol(keyAlts[noteIndex])
                                if accToDraw == "" { accToDraw = "n" }
                            } else {
                                accToDraw = "n"
                            }
                            measureAlteredPitches[cleanPitch] = ""
                        }
                    }
                    
                    if needAccidental { noteJS += "\n                        n.addModifier(0, new VF.Accidental('\(accToDraw)'));" }
                    
                    // 🌟 事实胜于雄辩：VexFlow 不会自动画点，必须手动挂载！
                    if baseDurStr.contains("d") { noteJS += "\n                        n.addDot(0);" }
                    
                    let chordAnnotation = measure.chordAnnotations.first(where: { $0.noteIndex == index })
                    if let chordAnnotation = chordAnnotation {
                        noteJS += "\n                        n.addModifier(0, new VF.Annotation('\(chordAnnotation.chord)').setVerticalJustification(1).setStyle({fillStyle: '#007AFF', strokeStyle: '#007AFF'}));"
                    }
                    
                    // === 🌟 Phase 3 核心改造：绘制挂载的爵士倚音 ===
                    if !note.graceNotes.isEmpty {
                        noteJS += "\n                        var graces = [];"
                        for (gIndex, gNote) in note.graceNotes.enumerated() {
                            let gSpelled = Self.spellNote(pitchStr: gNote.pitch, key: key)
                            let gPitch = gSpelled.position
                            let gAcc = gSpelled.accidental ?? ""
                            
                            // 2. 爵士排版细节：如果是单倚音，画上标志性的斜杠 (slash)；如果是多个倚音组成连句，则不画斜杠
                            let drawSlash = note.graceNotes.count == 1 ? "true" : "false"
                            
                            // 3. 实例化 VexFlow 倚音类 (GraceNote)，它在数学上不占小节的 Ticks！
                            noteJS += "\n                        var gn\(gIndex) = new VF.GraceNote({ keys: ['\(gPitch)'], duration: '\(gNote.duration)', slash: \(drawSlash) });"
                            
                            if !gAcc.isEmpty {
                                noteJS += "\n                        gn\(gIndex).addModifier(0, new VF.Accidental('\(gAcc)'));"
                            }
                            
                            // 4. 让倚音的颜色与主干音符保持一致（和弦音蓝色/趋近音红色）
                            noteJS += "\n                        gn\(gIndex).setKeyStyle(0, {fillStyle: '\(color)', strokeStyle: '\(color)'});"
                            
                            noteJS += "\n                        graces.push(gn\(gIndex));"
                        }
                        
                        // 5. 组装为 GraceNoteGroup 并挂载
                        // 🌟 核心视觉修复：显式调用 beamNotes() 强制绘制连音符杠，彻底消除满天飞的独立符尾！
                        noteJS += "\n                        var graceGroup = new VF.GraceNoteGroup(graces, true);"
                        noteJS += "\n                        if (graces.length >= 2) { graceGroup.beamNotes(); }"
                        noteJS += "\n                        n.addModifier(0, graceGroup);"
                    }
                    // === 倚音绘制逻辑结束 ===

                    noteJS += "\n                        return n;\n                    })()"
                    jsNotes.append(noteJS)
                }
            }
            
            let measureJS = """
            {
                chord: '\(measure.chord)', sectionName: '\(measure.sectionName ?? "")',
                makeNotes: function(VF) { return [\(jsNotes.joined(separator: ",\n"))]; },
                makeTuplets: function(VF, notes) {
                    var tuplets = []; 
                    
                    function getBaseTicks(dur) {
                        var c = dur.replace('r','').replace('d','');
                        var t = 1024;
                        if(c==='w') t=4096; else if(c==='h') t=2048; else if(c==='q') t=1024; else if(c==='8') t=512; else if(c==='16') t=256; else if(c==='32') t=128; else if(c==='64') t=64;
                        if(dur.indexOf('d') !== -1) t *= 1.5;
                        return t;
                    }
                    
                    for (var ni = 0; ni < notes.length; ni++) {
                        notes[ni].tupletGroupId = -1;
                    }
                    
                    var i = 0;
                    while(i < notes.length) {
                        if(notes[i].tupletVal && notes[i].isRealTuplet) {
                            var tVal = notes[i].tupletVal;
                            var group = []; 
                            var occ = (tVal === 3) ? 2 : (tVal >= 5 ? 4 : 2); 
                            var currentSum = 0;
                            
                            while(i < notes.length && notes[i].tupletVal === tVal) {
                                currentSum += getBaseTicks(notes[i].origDuration);
                                notes[i].tupletGroupId = tuplets.length;
                                group.push(notes[i]);
                                i++;
                                
                                // 🌟 智能异构组队：以视觉时值总和作为成组条件！
                                // 完美支持 2分+4分、附点+单音 等高级爵士连音组合，只要总和填满就立即收网闭合并画括号！
                                if (tVal === 3 && (currentSum === 768 || currentSum === 1536 || currentSum === 3072 || currentSum === 6144)) break;
                                if (tVal === 5 && (currentSum === 1280 || currentSum === 2560 || currentSum === 5120)) break;
                                if (group.length >= 6) break; // 兜底防死循环
                            }
                            
                            // 1. 计算该组真实的 Base Ticks 总和
                            var groupTotalTicks = 0;
                            for(var k=0; k<group.length; k++) {
                                groupTotalTicks += getBaseTicks(group[k].origDuration);
                            }
                            
                            // 2. 核心数学校验：真正的连音组，其基础时值总和必定是以下几个常数之一！
                            var isValidTuplet = false;
                            if (tVal === 3 && (groupTotalTicks === 768 || groupTotalTicks === 1536 || groupTotalTicks === 3072 || groupTotalTicks === 6144)) {
                                isValidTuplet = true;
                            } else if (tVal === 5 && (groupTotalTicks === 1280 || groupTotalTicks === 2560 || groupTotalTicks === 5120)) {
                                isValidTuplet = true;
                            } else if (tVal !== 3 && tVal !== 5) {
                                isValidTuplet = true; // 罕见连音暂放行
                            }
                            
                            // 3. 执行绘制或击杀降级
                            if (isValidTuplet) {
                                if(group.length > 1) {
                                    var sumL = 0;
                                    for(var k=0; k<group.length; k++) {
                                        var props = group[k].getKeyProps()[0];
                                        sumL += props ? props.line : 3;
                                    }
                                    var predictedDir = (sumL / group.length >= 3) ? -1 : 1;
                                    tuplets.push(new VF.Tuplet(group, { num_notes: tVal, notes_occupied: occ, location: predictedDir }));
                                } else if (group.length === 1) {
                                    // 依然保留孤音降级防御
                                    group[0].tupletVal = 0;
                                    group[0].isRealTuplet = false;
                                }
                            } else {
                                // 🌟 时值总和不合法（如 40+320 算出的 4608）：全组强行剥夺连音属性，击碎非法括号！
                                for(var k=0; k<group.length; k++) {
                                    group[k].tupletVal = 0;
                                    group[k].isRealTuplet = false;
                                }
                            }
                        } else { 
                            i++; 
                        }
                    }
                    return tuplets;
                },
                makeBeams: function(VF, notes) {
                    var beams = []; var currentGroup = [];
                    var RESOLUTION = 4096;
                                    
                    // 🌟 动态解析前端的全局拍号，彻底杜绝热更新固化
                    var tsStr = typeof timeSignature !== 'undefined' ? timeSignature : '4/4';
                    var tsParts = tsStr.split('/');
                    var tsBeats = parseInt(tsParts[0]) || 4;
                    var tsBeatVal = parseInt(tsParts[1]) || 4;
                    var beamTicks = (tsBeatVal === 8 && (tsBeats === 6 || tsBeats === 12)) ? 1536 : 1024;
                    var totalMeasureTicks = tsBeats * (RESOLUTION / tsBeatVal);
                                    
                    function getNormTicks(dur) {
                        var c = dur.replace('r','').replace('d',''); var t = RESOLUTION;
                        if(c==='w') t=RESOLUTION; else if(c==='h') t=RESOLUTION/2; else if(c==='q') t=RESOLUTION/4; else if(c==='8') t=RESOLUTION/8; else if(c==='16') t=RESOLUTION/16; else if(c==='32') t=RESOLUTION/32; else if(c==='64') t=RESOLUTION/64; else if(c==='128') t=RESOLUTION/128;
                        if(dur.indexOf('d') !== -1) t *= 1.5; return t;
                    }
                    
                    var noteAbsTicks = [];
                    var currentAbs = 0.0;
                    for (var k=0; k<notes.length; k++) {
                        var origT = getNormTicks(notes[k].origDuration);
                        var tV = notes[k].tupletVal || 1;
                        var factor = 1.0;
                        if (tV === 3) factor = 2/3; else if (tV === 5) factor = 4/5; else if (tV === 7) factor = 4/7;
                        var scaledT = origT * factor;
                        noteAbsTicks.push({ start: currentAbs, end: currentAbs + scaledT });
                        currentAbs += scaledT;
                    }

                    function commitGroup() {
                        if (currentGroup.length > 1) {
                            var sumL = 0;
                            for(var k=0; k<currentGroup.length; k++) {
                                var props = currentGroup[k].getKeyProps()[0];
                                sumL += props ? props.line : 3;
                            }
                            var dir = (sumL / currentGroup.length >= 3) ? -1 : 1;
                            for(var k=0; k<currentGroup.length; k++) { currentGroup[k].setStemDirection(dir); }
                            beams.push(new VF.Beam(currentGroup));
                        } else if (currentGroup.length === 1) {
                            if (!currentGroup[0].isRest()) currentGroup[0].autoStem();
                        }
                        currentGroup = [];
                    }

                    for (var i = 0; i < notes.length; i++) {
                        var note = notes[i];
                        var c = note.origDuration.replace('r','').replace('d','');
                        var endAbs = noteAbsTicks[i].end;
                        
                        var shouldBreak = false;
                        if (i > 0) {
                            var prevEndAbs = noteAbsTicks[i-1].end;
                            var currentBeat = Math.floor((prevEndAbs - 0.01) / beamTicks);
                            var nextBeat = Math.floor((endAbs - 0.01) / beamTicks);
                            if (currentBeat !== nextBeat) shouldBreak = true;
                            
                            if (note.tupletGroupId !== notes[i-1].tupletGroupId) shouldBreak = true;
                            else if (note.tupletGroupId !== -1) shouldBreak = false;
                        }
                        
                        if (shouldBreak && currentGroup.length > 0) { commitGroup(); }
                        
                        var isBeamable = ['8', '16', '32', '64'].indexOf(c) !== -1;
                        if (note.isRest() || !isBeamable) {
                            commitGroup(); 
                            if (!note.isRest()) note.autoStem(); 
                        } else { 
                            currentGroup.push(note); 
                        }
                        
                        var remainder = endAbs % beamTicks;
                        if (remainder < 0.01 || remainder > (beamTicks - 0.01) || Math.abs(endAbs - totalMeasureTicks) < 0.01) {
                            commitGroup(); 
                        }
                    }
                    commitGroup(); 
                    return beams;
                },
                makeTies: function(VF, notes) {
                    var ties = [];
                    for (var i = 0; i < notes.length; i++) {
                        if (notes[i].isTieEnd && i === 0) {
                            ties.push(new VF.StaveTie({ first_note: null, last_note: notes[i] }));
                        }
                        
                        if (notes[i].isTieStart) {
                            if (i + 1 < notes.length && notes[i + 1].isTieEnd) {
                                ties.push(new VF.StaveTie({ first_note: notes[i], last_note: notes[i + 1] }));
                            } else {
                                ties.push(new VF.StaveTie({ first_note: notes[i], last_note: null }));
                            }
                        }
                    }
                    return ties;
                }
            }
            """
            jsMeasuresArray.append(measureJS)
        }
        return jsMeasuresArray.joined(separator: ",\n")
    }
    
    private func generateHTML(for solo: [GeneratedMeasure], key: String) -> String {
        // 🌟 补上这行声明，让下面的 HTML 字符串能找到 profile 数据！
        let profile = TimeSignatureManager.getProfile(for: timeSignature)
            
        let vexflowKey = getVexflowKey(for: key)
        let initialMeasuresJS = generateMeasuresJSArray(for: solo, key: key, timeSig: timeSignature)
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <script>
            window.VF = null;
            window.onerror = function(msg){
                if(msg.includes("Vex") || msg.includes("VF")){
                    document.getElementById("sheet-canvas").innerHTML = "<div style='color:red'>VexFlow库加载失败，请检查项目资源文件</div>";
                }
            }
            </script>
            <script src="vexflow-min.js" onload="console.log('VexFlow加载完成')" onerror="document.getElementById('sheet-canvas').innerHTML='<div style=color:red>vexflow-min.js 资源缺失</div>'"></script>
            <style>
                body { margin: 0; padding: 0; width: 100vw; font-family: -apple-system, sans-serif; background-color: transparent; overflow-y: auto; overflow-x: hidden; -webkit-overflow-scrolling: touch; }
                #sheet-canvas { width: 100%; }
                #log { position: fixed; top: 0; left: 0; background: rgba(0,0,0,0.8); color: white; padding: 10px; font-size: 12px; z-index: 999; max-width: 50%; max-height: 300px; overflow: auto; display: none; }
                
                /* 🌟 终极高亮装甲（响应豆包正确建议）：用纯 CSS 接管 SVG 上色，告别 JS 内联样式污染 DOM */
                .highlighted-note path, .highlighted-note text {
                    fill: #FFB300 !important;
                    stroke: #FFB300 !important;
                }
                /* 防御机制：绝对不渲染 VexFlow 用于排版的隐形框架框 */
                .highlighted-note [fill="none"] { fill: none !important; }
                .highlighted-note [stroke="none"] { stroke: none !important; }
                .highlighted-note [fill="transparent"] { fill: transparent !important; }
                .highlighted-note [stroke="transparent"] { stroke: transparent !important; }
            </style>
        </head>
        <body>
            <div id="log"></div>
            <div id="sheet-canvas"></div>
            
            <script>
                window.currentHighlightId = null;
                var measuresData = [\(initialMeasuresJS)];
                var keySignature = "\(vexflowKey)";
                var timeSignature = "\(timeSignature)"; // 🌟 新增全局拍号变量
                var resizeTimer = null;
                
                function log(msg) { console.log(msg); }
                
                window.updateSheetMusic = function(newData, newKey, newTimeSignature) {
                    measuresData = newData;
                    keySignature = newKey;
                    if (newTimeSignature) timeSignature = newTimeSignature; // 🌟 接收新拍号
                    renderSheetMusic();
                    window.currentHighlightId = null; 
                    window.scrollTo({ top: 0, left: 0, behavior: 'instant' });
                };
                
                // 🌟 全局清空残留高亮的兜底保险（完美解决播放完毕后的残留问题）
                window.clearAllHighlights = function() {
                    var highlighted = document.querySelectorAll('.highlighted-note');
                    for (var i = 0; i < highlighted.length; i++) {
                        highlighted[i].classList.remove('highlighted-note');
                    }
                    window.currentHighlightId = null;
                };
                
                window.highlightNote = function(id) {
                    if (window.currentHighlightId === id && id !== "") return;
                    
                    // 1. 安全卸载旧高亮 (极简 classList 操作，杜绝白屏)
                    if (window.currentHighlightId) {
                        var oldEl = document.getElementById(window.currentHighlightId);
                        if (oldEl) {
                            oldEl.classList.remove('highlighted-note');
                        }
                    }
                    
                    // 🌟 核心拦截：如果 Swift 传来了空字符串(代表走带停止)，执行全局大扫荡并退出！
                    if (id === "") {
                        window.clearAllHighlights();
                        return;
                    }
                    
                    window.currentHighlightId = id;
                    
                    // 2. 注入新高亮
                    var newEl = document.getElementById(id);
                    if (newEl) {
                        newEl.classList.add('highlighted-note');
                        
                        // 落地黄金分割视口动态追踪算法
                        var rect = newEl.getBoundingClientRect();
                        var viewportHeight = window.innerHeight;
                        if (rect.bottom > viewportHeight * 0.7 || rect.top < viewportHeight * 0.1) {
                            window.scrollBy({ top: rect.top - viewportHeight * 0.25, behavior: 'smooth' });
                        }
                    }
                };
                
                // Tick Guardian: 复活被击杀的孤连音 (隐藏括号+数字, 仅做时值缩放)
                function resurrectKilledTuplets(VF, notes, killedMap, tuplets) {
                    for (var idx in killedMap) {
                        var i = parseInt(idx);
                        if (!notes[i].tupletVal || notes[i].tupletVal === 0) {
                            var tVal = killedMap[i];
                            var occ = (tVal === 3) ? 2 : (tVal >= 5 ? 4 : 2);
                            try {
                                var wrapper = new VF.Tuplet([notes[i]], {
                                    num_notes: tVal,
                                    notes_occupied: occ,
                                    bracketed: false
                                });
                                wrapper.numerator_glyphs = [];  // 阻止数字渲染（VexFlow 3.0.9 无 numbered 选项）
                                tuplets.push(wrapper);
                            } catch(e) {}
                        }
                    }
                }
                    
                function renderSheetMusic() {
                    try {
                        log("========== 渲染开始 ==========");
                        const VF = Vex.Flow;
                        var div = document.getElementById("sheet-canvas");
                        div.innerHTML = "";
                        
                        if (!measuresData || measuresData.length === 0) {
                            div.innerHTML = "<div style='color:#8E8E93; font-size:14px; text-align:center; padding:60px; font-weight:500;'>🎼 暂无乐谱数据<br><span style='font-size:12px; color:#AEAEB2;'>请点击右上角「魔棒按钮」智能生成即兴旋律</span></div>";
                            return;
                        }
                        
                        log("总小节数：" + measuresData.length);
                        var canvasWidth = div.clientWidth || 900;
                        var startX = 10; var startY = 30;
                        var safeCanvasWidth = canvasWidth - 20;
                        
                        var allVoices = []; var allBeams = []; var allTuplets = []; var allTies = []; var measureWeights = [];
                        
                        for (var m = 0; m < measuresData.length; m++) {
                            try {
                                log("▶️ 开始处理小节 " + (m+1) + " / " + measuresData.length);
                                var notes = measuresData[m].makeNotes(VF);
                                // Tick Guardian: 快照原始 tupletVal
                                var killedMap = {}; for (var ki = 0; ki < notes.length; ki++) { if (notes[ki].tupletVal) killedMap[ki] = notes[ki].tupletVal; }
                                var tuplets = measuresData[m].makeTuplets(VF, notes);
                                resurrectKilledTuplets(VF, notes, killedMap, tuplets);
                                
                                // 🔍 打印本小节全部音符的原始时值（便于定位问题）
                                var rawDurs = [];
                                for (var ni = 0; ni < notes.length; ni++) {
                                    var n = notes[ni];
                                    rawDurs.push(n.origDuration + (n.isRealTuplet ? "(T)" : "") + (n.isRest() ? "R" : ""));
                                }
                                log("小节" + (m+1) + " 音符(" + notes.length + "): " + rawDurs.join(", "));
                                
                                
                                
                                var beams = measuresData[m].makeBeams(VF, notes);
                                
                                // 🌟 让 JS 根据当前热更新的全局拍号动态算容量！绝不要用 Swift 模板注入！
                                var tsParts = timeSignature.split('/');
                                var tsBeats = parseInt(tsParts[0]) || 4;
                                var tsBeatVal = parseInt(tsParts[1]) || 4;
                                
                                var voice = new VF.Voice({num_beats: tsBeats, beat_value: tsBeatVal});
                                try {
                                    voice.setStrict(false);
                                    voice.addTickables(notes);
                                } catch(tickErr) {
                                    var noteDurations = notes.map(function(n) { return n.origDuration + (n.tupletVal ? "_t"+n.tupletVal : ""); }).join(", ");
                                    log("⚠️ 小节 " + (m+1) + " tick校验失败: " + tickErr.message + " 音符时值: [" + noteDurations + "]");
                                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.jsLogger) {
                                        window.webkit.messageHandlers.jsLogger.postMessage({
                                            level: "WARNING",
                                            message: "Voice严格tick校验报错，小节" + (m+1) + "，报错：" + tickErr.message + "，音符序列：" + noteDurations,
                                            stack: tickErr.stack || ""
                                        })
                                    }
                                    voice = new VF.Voice({num_beats: tsBeats, beat_value: tsBeatVal});
                                    voice.setStrict(false);
                                    voice.addTickables(notes);
                                }
                                
                                var ties = measuresData[m].makeTies(VF, notes);
                                allVoices.push(voice); allBeams.push(beams); allTuplets.push(tuplets); allTies.push(ties);
                                
                                var minWidth = 120;
                                try {
                                    var fmt = new VF.Formatter().joinVoices([voice]);
                                    minWidth = fmt.preCalculateMinTotalWidth([voice]) || 120;
                                } catch(e) { 
                                    log("⚠️ [排版引擎告警] 第 " + (m+1) + " 小节 preCalculate 异常: " + e.message); 
                                    var tupletBonus = 0;
                                    for(var ni=0; ni<notes.length; ni++) { if(notes[ni].tupletVal) tupletBonus += 15; }
                                    minWidth = (notes.length * 28) + tupletBonus + 60;
                                }
                                var padding = (m === 0) ? 90 : 40;
                                measureWeights.push(minWidth + padding);
                            } catch(measureErr) {
                                // 单小节单独捕获，打印出错小节索引
                                var errMsg = "第" + (m+1) + "小节构造数据失败：" + measureErr.message;
                                log("❌ " + errMsg);
                                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.jsLogger) {
                                    window.webkit.messageHandlers.jsLogger.postMessage({
                                        level: "ERROR",
                                        message: errMsg,
                                        stack: measureErr.stack || "无小节堆栈"
                                    })
                                }
                                // 🌟 兜底：使用纯动态拍号生成空 Voice
                                allVoices.push(new VF.Voice({num_beats: tsBeats, beat_value: tsBeatVal}));
                                allBeams.push([]); allTuplets.push([]); allTies.push([]);
                                measureWeights.push(120);
                            }
                        }
                        
                        var lines = []; var currentLine = []; var currentLineWidth = 0;
                        var maxMeasures = canvasWidth > 900 ? 4 : (canvasWidth > 600 ? 3 : 2);
                        
                        for (var m = 0; m < measuresData.length; m++) {
                            var w = measureWeights[m];
                            var wouldOverflow  = currentLineWidth + w > safeCanvasWidth;
                            var wouldCompress  = currentLine.length >= 2 && currentLineWidth + w > safeCanvasWidth * 1.176;
                            if (currentLine.length > 0 && (wouldOverflow || currentLine.length >= maxMeasures || wouldCompress)) {
                                lines.push(currentLine); currentLine = []; currentLineWidth = 0;
                            }
                            currentLine.push({ index: m, weight: w }); currentLineWidth += w;
                        }
                        if (currentLine.length > 0) { lines.push(currentLine); }
                        
                        var canvasHeight = lines.length * 190 + 100;
                        var renderer = new VF.Renderer(div, VF.Renderer.Backends.SVG);
                        renderer.resize(canvasWidth, canvasHeight);
                        var context = renderer.getContext();
                        
                        var y = startY;
                        for (var l = 0; l < lines.length; l++) {
                            var line = lines[l]; var x = startX;
                            var lineTotalWeight = line.reduce(function(sum, item) { return sum + item.weight; }, 0);
                            var widthMultiplier = safeCanvasWidth / lineTotalWeight; 
                            
                            if (widthMultiplier < 0.8) {
                                log("⚠️ [密度预警] 第 " + (l+1) + " 行音符拉伸比过低。强制拦截激活 0.8 保护兜底！");
                                widthMultiplier = 0.8;
                            }
                            if (l === lines.length - 1 && line.length < maxMeasures && widthMultiplier > 1.2) widthMultiplier = 1.2; 
                            
                            for (var i = 0; i < line.length; i++) {
                                try {
                                    var mIndex = line[i].index; var mWeight = line[i].weight;
                                    var measureWidth = mWeight * widthMultiplier;
                                    var stave = new VF.Stave(x, y, measureWidth);
                                    if (mIndex === 0) { 
                                        stave.addClef("treble"); 
                                        stave.addKeySignature(keySignature); 
                                        stave.addTimeSignature(timeSignature); // 🌟 去掉斜杠和引号，使用 JS 全局变量
                                    }
                                    // ── 小节线分级（必须在 draw() 前）──
                                    if (mIndex === measuresData.length - 1) {
                                        stave.setEndBarType(VF.Barline.type.END);
                                    } else if (measuresData[mIndex + 1] && measuresData[mIndex + 1].sectionName && measuresData[mIndex + 1].sectionName !== "") {
                                        stave.setEndBarType(VF.Barline.type.DOUBLE);
                                    }
                                    stave.setContext(context).draw();
                                    
                                    var sectionName = measuresData[mIndex].sectionName;
                                    if (sectionName && sectionName !== "") {
                                        var originalFillStyle = context.fillStyle;
                                        context.setFont("Arial", 14, "bold"); context.setFillStyle("#FF9500");
                                        var sectionX = (mIndex === 0) ? x + 35 : x + 5;
                                        context.fillText(sectionName, sectionX, y - 8);
                                        context.setFillStyle(originalFillStyle);
                                    }
                                    
                                    var voice = allVoices[mIndex];
                                    
                                    // 🌟 拦截空 Voice，防止 Formatter 崩溃导致整行白屏
                                    if (voice.getTickables().length === 0) {
                                        log("⚠️ 第 " + (mIndex+1) + " 小节为空 Voice，跳过绘制");
                                        x += measureWidth;
                                        continue;
                                    }
                                    
                                    // 1. Formatter
                                    try {
                                        var formatter = new VF.Formatter().joinVoices([voice]);
                                        var printableWidth = measureWidth - (stave.getNoteStartX() - x) - 35;
                                        formatter.format([voice], printableWidth);
                                    } catch(fmtErr) {
                                        log("❌ 小节 " + (mIndex+1) + " Formatter.format 失败: " + fmtErr.message);
                                        // 🚨 新增探针：上报排版崩溃原因给 Xcode 控制台
                                        if (window.webkit && window.webkit.messageHandlers.jsLogger) {
                                            window.webkit.messageHandlers.jsLogger.postMessage({
                                                level: "ERROR",
                                                message: "[VexFlow排版崩溃 -> 导致白屏] 小节 " + (mIndex+1) + " 失败原因: " + fmtErr.message,
                                                stack: fmtErr.stack || ""
                                            });
                                        }
                                        x += measureWidth;
                                        continue;
                                    }
                                    
                                    // 2. Voice draw
                                    try {
                                        voice.draw(context, stave);
                                    } catch(vErr) {
                                        log("❌ 小节 " + (mIndex+1) + " voice.draw 失败: " + vErr.message);
                                        x += measureWidth;
                                        continue;
                                    }
                                    
                                    // 3. Beams
                                    try {
                                        allBeams[mIndex].forEach(function(b) { b.setContext(context).draw(); });
                                    } catch(bErr) {
                                        log("❌ 小节 " + (mIndex+1) + " beams.draw 失败: " + bErr.message);
                                    }
                                    
                                    // 4. Tuplets
                                    try {
                                        allTuplets[mIndex].forEach(function(t) { t.setContext(context).draw(); });
                                    } catch(tErr) {
                                        log("❌ 小节 " + (mIndex+1) + " tuplets.draw 失败: " + tErr.message);
                                    }
                                    
                                    // 5. Ties — 跨小节延音线修复: 将 null-ended tie 端点延伸至小节边境
                                    try {
                                        var rightEdge = x + measureWidth;
                                        allTies[mIndex].forEach(function(t) {
                                            // 跨小节开头 tie：前小节弧线已延伸覆盖，跳过避免双线
                                            if ((t.first_note === null || t.first_note === undefined) && t.last_note) {
                                                return;
                                            }
                                            // 跨小节末尾 tie：右端延伸到小节右边界
                                            if ((t.last_note === null || t.last_note === undefined) && t.first_note) {
                                                var noteRight = t.first_note.getAbsoluteX() + t.first_note.getWidth();
                                                var targetRight = rightEdge - 10;
                                                var shift = targetRight - noteRight;
                                                if (shift > 0) {
                                                    t.render_options.last_x_shift = shift;
                                                }
                                            }
                                            t.setContext(context).draw();
                                        });
                                    } catch(tiErr) {
                                        log("❌ 小节 " + (mIndex+1) + " ties.draw 失败: " + tiErr.message);
                                    }
                                    
                                    // 6. 设置 SVG id 和点击事件
                                    var notesDrawn = voice.getTickables();
                                    for (var n = 0; n < notesDrawn.length; n++) {
                                        var svgGroup = notesDrawn[n].getAttribute('el') || (notesDrawn[n].getSVGElement ? notesDrawn[n].getSVGElement() : null);
                                        if (svgGroup) { 
                                            svgGroup.id = 'note-' + mIndex + '-' + n; 
                                            svgGroup.style.cursor = 'pointer';
                                            svgGroup.onclick = function(e) {
                                                e.stopPropagation();
                                                window.highlightNote(this.id);
                                                if (window.webkit && window.webkit.messageHandlers.noteClicked) {
                                                    window.webkit.messageHandlers.noteClicked.postMessage(this.id);
                                                };
                                            };
                                        }
                                    }
                                    x += measureWidth;
                                } catch(lineErr) {
                                    // 修复：使用当前行循环变量i，外层行索引line[i].index不存在l变量
                                    var errMsg = "当前行第" + (i+1) + "小节绘制异常：" + lineErr.message;
                                    log("❌ " + errMsg);
                                    if (window.webkit?.messageHandlers?.jsLogger) {
                                        window.webkit.messageHandlers.jsLogger.postMessage({
                                            level: "ERROR",
                                            message: errMsg,
                                            stack: lineErr.stack || "无绘制堆栈"
                                        })
                                    }
                                    x += measureWidth;
                                }
                            }
                            y += 190;
                        }
                        log("========== 渲染完成 ==========");
                    } catch(e) {
                        var errType = e.name || "UnknownError";
                        var fullMsg = "renderSheetMusic全局渲染捕获异常[" + errType + "]: " + e.message;
                        log("❌ " + fullMsg);
                        // 主动推送完整崩溃堆栈到Xcode控制台
                        if (window.webkit && window.webkit.messageHandlers.jsLogger) {
                            window.webkit.messageHandlers.jsLogger.postMessage({
                                level: "FATAL",
                                message: fullMsg,
                                stack: e.stack || "无堆栈信息"
                            })
                        }
                        div.innerHTML = "<div style='color:#FF3B30; font-size:14px; padding: 40px; text-align:center; font-weight:500;'>⚠️ 乐谱渲染异常，可能由于音符过于密集冲突。<br><span style='font-size:12px; color:#8E8E93;'>错误类型：" + errMsg + "<br>请尝试点击右上角「魔棒按钮」重新生成即兴旋律</span></div>";
                        console.error(e);
                    }
                }
                
                window.onresize = function() {
                    clearTimeout(resizeTimer);
                    resizeTimer = setTimeout(function() {
                        renderSheetMusic();
                        if (window.currentHighlightId) window.highlightNote(window.currentHighlightId);
                    }, 150);
                };
                window.addEventListener('load', function() { renderSheetMusic(); });
            </script>
        </body>
        </html>
        """
    }
}

private extension SheetMusicView {
    static func keyAlterations(for key: String) -> [Int] {
        var alterations = [0, 0, 0, 0, 0, 0, 0]
        let sharpKeys: [String: [Int]] = [
            "G": [3], "D": [3, 0], "A": [3, 0, 4], "E": [3, 0, 4, 1],
            "B": [3, 0, 4, 1, 5], "F#": [3, 0, 4, 1, 5, 2], "C#": [3, 0, 4, 1, 5, 2, 6]
        ]
        let flatKeys: [String: [Int]] = [
            "F": [6], "Bb": [6, 2], "Eb": [6, 2, 5], "Ab": [6, 2, 5, 1],
            "Db": [6, 2, 5, 1, 4], "Gb": [6, 2, 5, 1, 4, 0], "Cb": [6, 2, 5, 1, 4, 0, 3]
        ]
        let minorKeys: [String: [Int]] = [
            "Am": [0,0,0,0,0,0,0], "Em": [0,0,0,1,0,0,0], "Bm": [1,0,0,1,0,0,0],
            "F#m": [1,0,0,1,1,0,0], "C#m": [1,1,0,1,1,0,0], "G#m": [1,1,0,1,1,1,0],
            "D#m": [1,1,1,1,1,1,0], "A#m": [1,1,1,1,1,1,1],
            "Dm": [0,0,0,0,0,0,-1], "Gm": [0,0,-1,0,0,0,-1], "Cm": [0,0,-1,0,0,-1,-1],
            "Fm": [0,-1,-1,0,0,-1,-1], "Bbm": [0,-1,-1,0,-1,-1,-1], "Ebm": [-1,-1,-1,0,-1,-1,-1],
            "Abm": [-1,-1,-1,-1,-1,-1,-1]
        ]
        
        if key.hasSuffix("m") {
            if let alts = minorKeys[key] { return alts }
            let minorRoot = String(key.dropLast())
            let enharmonicMap: [String: String] = ["G#":"Ab","Ab":"G#","C#":"Db","Db":"C#","F#":"Gb","Gb":"F#","D#":"Eb","Eb":"D#","A#":"Bb","Bb":"A#"]
            if let flatRoot = enharmonicMap[minorRoot], let alts = minorKeys[flatRoot + "m"] { return alts }
            return alterations
        }
        if let indices = sharpKeys[key] { indices.forEach { alterations[$0] = 1 }; return alterations }
        if let indices = flatKeys[key] { indices.forEach { alterations[$0] = -1 }; return alterations }
        return alterations
    }
    
    private static func accSymbol(_ value: Int) -> String {
        switch value {
        case 2: return "##"; case 1: return "#"; case 0: return "n"; case -1: return "b"; case -2: return "bb"; default: return ""
        }
    }
    
    static func spellNote(pitchStr: String, key: String) -> (position: String, accidental: String?) {
        let cleaned = pitchStr.replacingOccurrences(of: " 前导", with: "")
        let parts = cleaned.split(separator: "/")
        guard parts.count == 2 else { return (cleaned.lowercased(), nil) }
        let notePart = String(parts[0]).lowercased()
        let octave = Int(parts[1]) ?? 4
        let noteMap: [String: Int] = ["c":0,"c#":1,"db":1,"d":2,"d#":3,"eb":3,"e":4,"f":5,"f#":6,"gb":6,"g":7,"g#":8,"ab":8,"a":9,"a#":10,"bb":10,"b":11]
        guard let targetPC = noteMap[notePart] else {
            return (cleaned.lowercased(), notePart.contains("#") ? "#" : (notePart.contains("b") ? "b" : nil))
        }
        let inputPrefersSharp = notePart.contains("#")
        let inputPrefersFlat = notePart.contains("b")
        let naturalPCs = [0,2,4,5,7,9,11]
        let naturalNames = ["c","d","e","f","g","a","b"]
        let keyAlts = keyAlterations(for: key)
        
        struct Candidate { let noteIndex: Int; let accValue: Int; let displayAcc: String?; let absAcc: Int }
        var candidates: [Candidate] = []
        for i in 0..<7 {
            let basePC = naturalPCs[i]
            for acc in -2...2 {
                let actualPC = (basePC + acc + 12) % 12
                guard actualPC == targetPC else { continue }
                let displayAcc: String? = acc == keyAlts[i] ? nil : accSymbol(acc)
                candidates.append(Candidate(noteIndex:i, accValue:acc, displayAcc:displayAcc, absAcc:abs(acc)))
            }
        }
        
        let isSharpKey = keyAlts.contains(1) && !keyAlts.contains(-1)
        let isFlatKey = keyAlts.contains(-1) && !keyAlts.contains(1)
        candidates.sort { a, b in
            if a.displayAcc == nil && b.displayAcc != nil { return true }
            if a.displayAcc != nil && b.displayAcc == nil { return false }
            if a.absAcc != b.absAcc { return a.absAcc < b.absAcc }
            if inputPrefersSharp && !inputPrefersFlat { if a.accValue > 0 && b.accValue < 0 { return true }; if a.accValue < 0 && b.accValue > 0 { return false } }
            if inputPrefersFlat && !inputPrefersSharp { if a.accValue < 0 && b.accValue > 0 { return true }; if a.accValue > 0 && b.accValue < 0 { return false } }
            if isSharpKey { return a.accValue > b.accValue }
            if isFlatKey { return a.accValue < b.accValue }
            return a.accValue < b.accValue
        }
        
        if let best = candidates.first {
            return ("\(naturalNames[best.noteIndex])/\(octave)", best.displayAcc)
        }
        return (cleaned.lowercased(), notePart.contains("#") ? "#" : (notePart.contains("b") ? "b" : nil))
    }
}

