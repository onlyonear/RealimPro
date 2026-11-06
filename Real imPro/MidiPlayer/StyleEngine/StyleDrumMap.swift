import Foundation

// MARK: - StyleDrumMap
// GM 打击乐名（spaceless，下划线连写）→ MIDI note。
// 对齐 Java MIDIBeast.spacelessDrumName（MIDIBeast.java:270-319）：数组 index + 35，覆盖 MIDI 35–81 共 47 件。
// 关键：swing.sty 底鼓用 Acoustic_Bass_Drum = 35（不是手写 DrumKit.kick 的 36）。
// 本字典为 .sty 引擎独立持有，不修改手写 DrumKit 常量（保护 Simple Swing 等旧风格）。

enum StyleDrumMap {

    /// index 0 → MIDI 35
    static let names: [String] = [
        "Acoustic_Bass_Drum",   // 35
        "Bass_Drum_1",          // 36
        "Side_Stick",           // 37
        "Acoustic_Snare",       // 38
        "Hand_Clap",            // 39
        "Electric_Snare",       // 40
        "Low_Floor_Tom",        // 41
        "Closed_Hi-Hat",        // 42
        "High_Floor_Tom",       // 43
        "Pedal_Hi-Hat",         // 44
        "Low_Tom",              // 45
        "Open_Hi-Hat",          // 46
        "Low-Mid_Tom",          // 47
        "Hi-Mid_Tom",           // 48
        "Crash_Cymbal_1",       // 49
        "High_Tom",             // 50
        "Ride_Cymbal_1",        // 51
        "Chinese_Cymbal",       // 52
        "Ride_Bell",            // 53
        "Tambourine",           // 54
        "Splash_Cymbal",        // 55
        "Cowbell",              // 56
        "Crash_Cymbal_2",       // 57
        "Vibraslap",            // 58
        "Ride_Cymbal_2",        // 59
        "Hi_Bongo",             // 60
        "Low_Bongo",            // 61
        "Mute_Hi_Conga",        // 62
        "Open_Hi_Conga",        // 63
        "Low_Conga",            // 64
        "High_Timbale",         // 65
        "Low_Timbale",          // 66
        "High_Agogo",           // 67
        "Low_Agogo",            // 68
        "Cabasa",               // 69
        "Maracas",              // 70
        "Short_Whistle",        // 71
        "Long_Whistle",         // 72
        "Short_Guiro",          // 73
        "Long_Guiro",           // 74
        "Claves",               // 75
        "Hi_Wood_Block",        // 76
        "Low_Wood_Block",       // 77
        "Mute_Cuica",           // 78
        "Open_Cuica",           // 79
        "Mute_Triangle",        // 80
        "Open_Triangle"         // 81
    ]

    /// 精确匹配优先；失败则按「去空格/下划线/连字符、小写」容错（不同 .sty 写法差异）。
    static func midi(_ spacelessName: String) -> UInt8? {
        let key = spacelessName.trimmingCharacters(in: .whitespaces)
        if let i = names.firstIndex(of: key) { return UInt8(i + 35) }
        let norm = normalize(key)
        if let i = names.firstIndex(where: { normalize($0) == norm }) { return UInt8(i + 35) }
        return nil
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }
}
