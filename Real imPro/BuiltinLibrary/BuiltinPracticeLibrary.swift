import Foundation

// MARK: - 内置练习曲集（10 首经典和声走向）
/// 固定不可隐藏，选歌自动匹配伴奏型
/// 歌名用练习曲名称（不是真实曲名），作者统一标 Practice
struct BuiltinPracticeLibrary {
    let name: String = "Practice"
    let songs: [JazzSong]
    
    init() {
        self.songs = BuiltinPracticeLibrary.makeSongs()
    }
    
    var playlist: JazzPlaylist {
        JazzPlaylist(name: name, songs: songs)
    }
    
    // MARK: - 10 首练习曲
    private static func makeSongs() -> [JazzSong] {
        // 辅助函数：快速构建 4/4 拍、每小节一个和弦的歌
        func song(_ title: String, _ style: String, _ key: String, _ tempo: Int, _ chords: [String], timeSig: String = "4/4") -> JazzSong {
            let measures = chords.map { [$0] }
            return JazzSong(
                title: title,
                composer: "Practice",
                style: style,
                tempo: tempo,
                key: key,
                timeSignature: timeSig,
                measures: measures
            )
        }
        
        return [
            // 1. Ballad
            song("Ballad", "Ballad", "F", 60, [
                "Fmaj7", "Dm7", "Gm7", "C7",
                "Fmaj7", "Bbm7", "Eb7", "Abmaj7",
                "Dm7", "Gm7", "C7", "Fmaj7",
                "Bbm7", "Eb7", "Am7", "D7"
            ]),
            
            // 2. Blues (12 小节布鲁斯)
            song("Blues", "Shuffle", "A", 90, [
                "A7", "A7", "A7", "A7",
                "D7", "D7", "A7", "A7",
                "E7", "D7", "A7", "E7"
            ]),
            
            // 3. Jazz Blues (12 小节，更复杂的和弦)
            song("Jazz Blues", "Shuffle", "A", 90, [
                "A7", "Dm7", "A7", "A7",
                "Dm7", "D7b9", "A7", "A7",
                "F#m7b5", "B7b9", "Em7", "A7"
            ]),
            
            // 4. Bossa
            song("Bossa", "Bossa Nova", "Cm", 120, [
                "Cm7", "Fm7", "Dm7b5", "G7",
                "Cm7", "Fm7", "Dm7b5", "G7",
                "Ebmaj7", "Cm7", "Fm7", "Bb7",
                "Cm7", "Fm7", "Dm7b5", "G7"
            ]),
            
            // 5. Latin
            song("Latin", "Latin", "Bb", 180, [
                "Bbmaj7", "Am7", "D7", "Gmaj7",
                "Cm7", "F7", "Bbmaj7", "Gm7",
                "Cm7", "F7", "Bbmaj7", "D7",
                "Gm7", "C7", "F7", "Bbmaj7"
            ]),
            
            // 6. Major 251 进行练习
            song("Major 251", "Medium Swing", "C", 90, [
                "Dm7", "G7", "Cmaj7", "Cmaj7",
                "Dm7", "G7", "Cmaj7", "Cmaj7",
                "Dm7", "G7", "Cmaj7", "Cmaj7",
                "Dm7", "G7", "Cmaj7", "Cmaj7"
            ]),
            
            // 7. Minor 251 进行练习
            song("Minor 251", "Medium Swing", "Cm", 100, [
                "Dm7b5", "G7b9", "Cm7", "Cm7",
                "Dm7b5", "G7b9", "Cm7", "Cm7",
                "Dm7b5", "G7b9", "Cm7", "Cm7",
                "Dm7b5", "G7b9", "Cm7", "Cm7"
            ]),
            
            // 8. Pop-Rock
            song("Pop-Rock", "Rock Pop", "Am", 70, [
                "Am7", "Dm7", "Gmaj7", "Cmaj7",
                "Fmaj7", "Bdim7", "E7", "Am7",
                "Am7", "Dm7", "Gmaj7", "Cmaj7",
                "Fmaj7", "Bdim7", "E7", "Am7"
            ]),
            
            // 9. Rhythm Changes (32 小节 AABA)
            song("Rhythm Changes", "Medium Up Swing", "Bb", 120, [
                // A 段 (8 小节)
                "Bbmaj7", "Ebm7", "A7", "Dm7",
                "Gm7", "C7", "Fm7", "Bb7",
                // A 段重复
                "Bbmaj7", "Ebm7", "A7", "Dm7",
                "Gm7", "C7", "Fm7", "Bb7",
                // B 段 (8 小节)
                "Ebm7", "Bb7", "Ebm7", "Bb7",
                "Ebm7", "Bb7", "Am7", "D7",
                // A 段重复
                "Bbmaj7", "Ebm7", "A7", "Dm7",
                "Gm7", "C7", "Fm7", "Bb7"
            ]),
            
            // 10. Waltz (3/4 拍)
            song("Waltz", "Waltz", "Ab", 120, [
                "Abmaj7", "Cm7", "Fm7",
                "Bbm7", "Eb7", "Abmaj7",
                "Dbmaj7", "Gm7b5", "C7",
                "Fm7", "Bbm7", "Eb7",
                "Abmaj7", "Cm7", "Fm7",
                "Bbm7", "Eb7", "Abmaj7",
                "Dbmaj7", "Gm7b5", "C7",
                "Fm7", "Bbm7", "Eb7"
            ], timeSig: "3/4"),
        ]
    }
}
