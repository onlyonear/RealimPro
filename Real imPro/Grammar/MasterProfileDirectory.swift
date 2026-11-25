//
//  MasterProfileDirectory.swift
//  Real imPro · 大师头像介绍卡数据层（纯静态展示数据，不含任何生成逻辑）
//
//  为 Grammar 设置卡的头像介绍卡提供「头像 + 标题（生卒）+ 生平/风格正文」。
//  事实来源：《大师文案事实核实清单》（Wikipedia/AllMusic/Britannica 交叉核实，生卒零容错）。
//  3 个基本语法头像指向 LaunchIcon；Tom Harrell Waltzes 复用 Tom Harrell 头像。
//  本期英文，专有名词不本地化；正文沿用 ModeBlurb 直接英文字面量的既有模式。
//

import SwiftUI

// MARK: - 大师/语法介绍数据

struct MasterProfile: Equatable {
    let avatarImageName: String
    let title: String
    let bio: String
}

// MARK: - 目录（穷尽 switch：未来 ImproAlgorithmType 新增 case 时编译器强制补全）

enum MasterProfileDirectory {

    /// 返回某个算法/语法对应的头像介绍卡数据。
    static func profile(for algorithm: ContentView.ImproAlgorithmType) -> MasterProfile {
        switch algorithm {

        // ── 3 个基本语法（LaunchIcon，无生卒）──
        case .chordExercise:
            return MasterProfile(
                avatarImageName: "LaunchIcon",
                title: "Chord+App",
                bio: "Rule-based practice grammar. Builds lines from chord tones with approach notes — a clear, beginner-friendly way to hear chord-to-chord voice leading without named-master style.")
        case .colorTone:
            return MasterProfile(
                avatarImageName: "LaunchIcon",
                title: "Chord+Col",
                bio: "Rule-based grammar. Adds selected color tones (9ths, 11ths, 13ths) to chord tones, giving lines a richer, more extended sound.")
        case .Lick:
            return MasterProfile(
                avatarImageName: "LaunchIcon",
                title: "Great Lick",
                bio: "Rule-based grammar. Stitches together classic bebop phrases (named \"bricks\"), so you practice time-tested lines rather than a single master's style.")

        // ── Alto Sax（6）──
        case .charlieParker:
            return MasterProfile(
                avatarImageName: "CharlieParker",
                title: "Charlie Parker (1920–1955)",
                bio: "Alto saxophonist with blazing technique, advanced harmonies, passing and altered chords. The founding genius of bebop; behind KoKo, Billie's Bounce and Ornithology, and known to all as \"Bird.\"")
        case .cannonballAdderley:
            return MasterProfile(
                avatarImageName: "CannonballAdderley",
                title: "Cannonball Adderley (1928–1975)",
                bio: "Alto saxophonist with a warm, blues-soaked, gospel-tinged tone and fast, soulful phrasing. A defining voice of hard bop and soul jazz; featured on Miles Davis' Kind of Blue and known for Mercy, Mercy, Mercy.")
        case .artPepper:
            return MasterProfile(
                avatarImageName: "ArtPepper",
                title: "Art Pepper (1925–1982)",
                bio: "Alto saxophonist with a pure, bright, intensely emotional tone, broken phrases and off-center accents. A leading voice of West Coast cool jazz; heard on Art Pepper Meets the Rhythm Section and the memoir Straight Life.")
        case .jackieMcLean:
            return MasterProfile(
                avatarImageName: "JackieMcLean",
                title: "Jackie McLean (1931–2006)",
                bio: "Alto saxophonist with a sharp, biting, angular sound that moved from hard bop to the avant-garde. Also a revered educator who founded the Jackie McLean Institute at the Hartt School.")
        case .vincentHerring:
            return MasterProfile(
                avatarImageName: "VincentHerring",
                title: "Vincent Herring (b. 1964)",
                bio: "Alto saxophonist with a fiery, soulful, deep-blues style in the Cannonball Adderley tradition. A nine-year veteran of Nat Adderley's band and a Grammy winner with the Mingus Big Band.")
        case .kennyGarrett:
            return MasterProfile(
                avatarImageName: "KennyGarrett",
                title: "Kenny Garrett (b. 1960)",
                bio: "Alto saxophonist with elastic, aggressive phrasing steeped in gospel, soul and world music. A veteran of Miles Davis' late band and a 2023 NEA Jazz Master.")

        // ── Piano（7）──
        case .billEvans:
            return MasterProfile(
                avatarImageName: "BillEvans",
                title: "Bill Evans (1929–1980)",
                bio: "Pianist with impressionist harmonies, block chords and singing, lyrical lines. A transformative voice of modal jazz; he reshaped the piano trio and played on Miles Davis' Kind of Blue.")
        case .budPowell:
            return MasterProfile(
                avatarImageName: "BudPowell",
                title: "Bud Powell (1924–1966)",
                bio: "Pianist with a virtuosic, hard-hitting right hand that earned him the name \"the Charlie Parker of the piano.\" A foundational bebop composer behind Un Poco Loco and Tempus Fugue-It.")
        case .tommyFlanagan:
            return MasterProfile(
                avatarImageName: "TommyFlanagan",
                title: "Tommy Flanagan (1930–2001)",
                bio: "Pianist with an elegant, refined touch and one of jazz's finest trio leaders. Longtime accompanist and musical director for Ella Fitzgerald, and heard on Saxophone Colossus and Giant Steps.")
        case .kennyBarron:
            return MasterProfile(
                avatarImageName: "KennyBarron",
                title: "Kenny Barron (b. 1943)",
                bio: "Pianist with graceful, lyrical playing and Latin and Caribbean rhythms. A 2010 NEA Jazz Master known for People Time with Stan Getz and the group Sphere.")
        case .keithJarrrett:
            // 注意：case 名为 keithJarrrett（三 r），图片资源为 KeithJarrett（两 r）
            return MasterProfile(
                avatarImageName: "KeithJarrett",
                title: "Keith Jarrett (b. 1945)",
                bio: "Pianist known for free improvisation, solo concerts and gospel-and-blues invention, with perfect pitch. Creator of The Köln Concert and the long-running standards trio.")
        case .redGarland:
            return MasterProfile(
                avatarImageName: "RedGarland",
                title: "Red Garland (1923–1984)",
                bio: "Pianist with a relaxed, swinging style built on his signature block chords. The anchor of Miles Davis' first great quintet, and an amateur boxer on the side.")
        case .cedarWalton:
            return MasterProfile(
                avatarImageName: "CedarWalton",
                title: "Cedar Walton (1934–2013)",
                bio: "Hard bop pianist, composer and arranger with the Messengers in his roots. Writer of Bolivia, Mosaic and Firm Roots, and a 2010 NEA Jazz Master.")

        // ── Guitar（5）──
        case .joePass:
            return MasterProfile(
                avatarImageName: "JoePass",
                title: "Joe Pass (1929–1994)",
                bio: "Guitarist who wove walking bass, counterpoint and chord-melody into solo guitar. A master of unaccompanied jazz on Virtuoso, and a partner to Ella Fitzgerald.")
        case .wesMontgomery:
            return MasterProfile(
                avatarImageName: "WesMontgomery",
                title: "Wes Montgomery (1923–1968)",
                bio: "Guitarist with a warm, signature sound from thumb-picking and octave lines. A hard bop and soul-jazz voice on The Incredible Jazz Guitar, with a Grammy for Goin' Out My Head.")
        case .patMartino:
            return MasterProfile(
                avatarImageName: "PatMartino",
                title: "Pat Martino (1944–2021)",
                bio: "Guitarist with flowing long lines, a full-bodied tone and his \"minor conversion\" technique. Remarkably relearned the guitar after memory-loss surgery and returned to the stage.")
        case .grantGreen:
            return MasterProfile(
                avatarImageName: "GrantGreen",
                title: "Grant Green (1935–1979)",
                bio: "Guitarist with a horn-like single-line approach rooted in the blues, avoiding dense chromatic runs. A soul-jazz voice on Idle Moments and Green Street.")
        case .kennyBurrell:
            return MasterProfile(
                avatarImageName: "KennyBurrell",
                title: "Kenny Burrell (b. 1931)",
                bio: "Guitarist with warm, restrained, melodic playing and a deep blues feel. A 2005 NEA Jazz Master known for Midnight Blue and his work at UCLA.")

        // ── Tenor Sax（17）──
        case .johnColtrane:
            return MasterProfile(
                avatarImageName: "JohnColtrane",
                title: "John Coltrane (1926–1967)",
                bio: "Tenor saxophonist known for \"sheets of sound,\" the Coltrane changes and a deeply spiritual drive. A revolutionary from hard bop to free jazz on Giant Steps and A Love Supreme.")
        case .wayneShorter:
            return MasterProfile(
                avatarImageName: "WayneShorter",
                title: "Wayne Shorter (1933–2023)",
                bio: "Tenor saxophonist with a concise, personal tone and one of jazz's great composers. A Weather Report co-founder and veteran of Miles Davis' second great quintet; writer of Speak No Evil.")
        case .sonnyRollins:
            return MasterProfile(
                avatarImageName: "SonnyRollins",
                title: "Sonny Rollins (1930–2026)",
                bio: "Tenor saxophonist known for sprawling improvisations, calypso and folk tunes, and witty musical quotations. The \"Saxophone Colossus\" behind St. Thomas, Oleo and Doxy.")
        case .stanGetz:
            return MasterProfile(
                avatarImageName: "StanGetz",
                title: "Stan Getz (1927–1991)",
                bio: "Tenor saxophonist with a warm, lyrical sound called simply \"The Sound.\" He brought bossa nova to the world with The Girl from Ipanema.")
        case .joeHenderson:
            return MasterProfile(
                avatarImageName: "JoeHenderson",
                title: "Joe Henderson (1937–2001)",
                bio: "Tenor saxophonist with distinctive, understated phrasing and a composer's mind. Known for Page One, Blue Bossa and Inner Urge.")
        case .dexterGordon:
            return MasterProfile(
                avatarImageName: "DexterGordon",
                title: "Dexter Gordon (1923–1990)",
                bio: "Tenor saxophonist with a big, broad tone, laid-back timing and endless musical quotations. An Oscar nominee for the film Round Midnight and a 1986 NEA Jazz Master.")
        case .warneMarsh:
            return MasterProfile(
                avatarImageName: "WarneMarsh",
                title: "Warne Marsh (1927–1987)",
                bio: "Tenor saxophonist with long, pure lines and vertical improvisation that refused stock licks. A Lennie Tristano disciple and a quiet influence on later generations.")
        case .oliverNelson:
            return MasterProfile(
                avatarImageName: "OliverNelson",
                title: "Oliver Nelson (1932–1975)",
                bio: "Tenor saxophonist, composer and arranger who moved into film and television. Creator of The Blues and the Abstract Truth and the standard Stolen Moments.")
        case .georgeColeman:
            return MasterProfile(
                avatarImageName: "GeorgeColeman",
                title: "George Coleman (b. 1935)",
                bio: "Tenor saxophonist with a muscular, soulful sound and Memphis roots. Heard with Miles Davis on My Funny Valentine and on Herbie Hancock's Maiden Voyage; a 2015 NEA Jazz Master.")
        case .jimmyHeath:
            return MasterProfile(
                avatarImageName: "JimmyHeath",
                title: "Jimmy Heath (1926–2020)",
                bio: "Tenor saxophonist known for lyrical playing, big-band arranging and composing, nicknamed \"Little Bird.\" One of the Heath Brothers and a longtime Queens College educator.")
        case .wardellGray:
            return MasterProfile(
                avatarImageName: "WardellGray",
                title: "Wardell Gray (1921–1955)",
                bio: "Tenor saxophonist and a fluent bridge between swing and bebop. Remembered for the tenor duel The Chase with Dexter Gordon.")
        case .bobBerg:
            return MasterProfile(
                avatarImageName: "BobBerg",
                title: "Bob Berg (1951–2002)",
                bio: "Tenor saxophonist with a powerful, Coltrane-influenced voice across hard bop and fusion. A veteran of Miles Davis' 1980s band and groups led by Horace Silver and Chick Corea.")
        case .daveLiebman:
            return MasterProfile(
                avatarImageName: "DaveLiebman",
                title: "Dave Liebman (b. 1946)",
                bio: "Tenor and soprano saxophonist and a soprano specialist with a strong Coltrane legacy. He played with Elvin Jones and Miles Davis, and is a 2011 NEA Jazz Master.")
        case .colemanHawkins:
            return MasterProfile(
                avatarImageName: "ColemanHawkins",
                title: "Coleman Hawkins (1904–1969)",
                bio: "Tenor saxophonist with arpeggio-based improvisation and a rich vibrato that made him the founding father of the jazz saxophone. Immortalized by his 1939 Body and Soul.")
        case .lesterYoung:
            return MasterProfile(
                avatarImageName: "LesterYoung",
                title: "Lester Young (1909–1959)",
                bio: "Tenor saxophonist with a relaxed, cool tone and his trademark pork-pie hat, the opposite of Hawkins. A Count Basie star who paved the way for cool jazz.")
        case .joeLovano:
            return MasterProfile(
                avatarImageName: "JoeLovano",
                title: "Joe Lovano (b. 1952)",
                bio: "Tenor saxophonist and multi-instrumentalist with an adventurous, wide-ranging voice. A Paul Motian trio veteran, Berklee chair and Grammy winner.")
        case .richPerry:
            return MasterProfile(
                avatarImageName: "RichPerry",
                title: "Rich Perry (b. 1955)",
                bio: "Tenor saxophonist with a lyrical, modern approach. A longtime member of the Vanguard Jazz Orchestra and Maria Schneider's band.")

        // ── Trumpet（11）──
        case .LeeMorgan:
            return MasterProfile(
                avatarImageName: "LeeMorgan",
                title: "Lee Morgan (1938–1972)",
                bio: "Trumpeter with a bright, sharp attack shaped by Clifford Brown. A Jazz Messenger who scored a crossover hit with The Sidewinder.")
        case .dizzyGillespie:
            return MasterProfile(
                avatarImageName: "DizzyGillespie",
                title: "Dizzy Gillespie (1917–1993)",
                bio: "Trumpeter with dazzling technique, an extended range and daring leaps, his bell bent upward. A bebop and Afro-Cuban pioneer behind A Night in Tunisia and Manteca.")
        case .freddieHubbard:
            return MasterProfile(
                avatarImageName: "FreddieHubbard",
                title: "Freddie Hubbard (1938–2008)",
                bio: "Trumpeter with ferocious technique and a burnished tone. A Jazz Messenger known for Red Clay and Ready for Freddie.")
        case .artFarmer:
            return MasterProfile(
                avatarImageName: "ArtFarmer",
                title: "Art Farmer (1928–1999)",
                bio: "Trumpeter with a lyrical, warm style who championed the flugelhorn and the flumpet. Co-founder of the Jazztet and a 1999 NEA Jazz Master.")
        case .woodyShaw:
            return MasterProfile(
                avatarImageName: "WoodyShaw",
                title: "Woody Shaw (1944–1989)",
                bio: "Trumpeter and virtuoso who expanded the instrument's harmonic and technical frontiers. Heard on Blackstone Legacy and Rosewood.")
        case .kennyDorham:
            return MasterProfile(
                avatarImageName: "KennyDorham",
                title: "Kenny Dorham (1924–1972)",
                bio: "Trumpeter with a clear, pure, lyrical and often underrated voice. A founding Messenger who wrote Blue Bossa and Una Mas.")
        case .royHargrove:
            return MasterProfile(
                avatarImageName: "RoyHargrove",
                title: "Roy Hargrove (1969–2018)",
                bio: "Trumpeter who crossed hard bop into Latin, hip-hop and R&B. A two-time Grammy winner for Habana and Directions in Music.")
        case .blueMitchell:
            return MasterProfile(
                avatarImageName: "BlueMitchell",
                title: "Blue Mitchell (1930–1979)",
                bio: "Trumpeter with a direct, lightly swinging, lyrical style. A Horace Silver veteran and a prolific voice on organ-combo sessions.")
        case .chetBaker:
            return MasterProfile(
                avatarImageName: "ChetBaker",
                title: "Chet Baker (1929–1988)",
                bio: "Trumpeter with gentle trumpet and soft vocals, the \"Prince of Cool.\" Known for Chet Baker Sings and My Funny Valentine.")
        case .milesDavis:
            return MasterProfile(
                avatarImageName: "MilesDavis",
                title: "Miles Davis (1926–1991)",
                bio: "Trumpeter with a soft, dark, vibrato-free tone built on space and melody. An endlessly restless innovator from Birth of the Cool to Kind of Blue and Bitches Brew.")
        case .cliffordBrown:
            return MasterProfile(
                avatarImageName: "CliffordBrown",
                title: "Clifford Brown (1930–1956)",
                bio: "Trumpeter with a warm, full tone and flawless bebop harmony. Co-led the Max Roach quintet and wrote Joy Spring and Daahoud before his death at 25.")

        // ── Trombone（3）──
        case .jjJohnson:
            return MasterProfile(
                avatarImageName: "JJJohnson",
                title: "J.J. Johnson (1924–2001)",
                bio: "Trombonist whose speed and precision made bebop speak on the trombone, plus skilled arranging. Remembered for the Jay and Kai partnership and the Shaft score.")
        case .bobBrookmeyer:
            return MasterProfile(
                avatarImageName: "BobBrookmeyer",
                title: "Bob Brookmeyer (1929–2011)",
                bio: "Valve trombonist and cool-jazz composer and arranger. A Gerry Mulligan Quartet veteran and an eight-time Grammy nominee.")
        case .billWatrous:
            return MasterProfile(
                avatarImageName: "BillWatrous",
                title: "Bill Watrous (1939–2018)",
                bio: "Trombonist and technical master with a fluid, effortless tone. Leader of the Manhattan Wildlife Refuge big band.")

        // ── Other（4 项）──
        case .gerryMulligan:
            return MasterProfile(
                avatarImageName: "GerryMulligan",
                title: "Gerry Mulligan (1927–1996)",
                bio: "Baritone saxophonist with a light, airy tone on the bulky baritone and a gift for arranging. His piano-less quartet with Chet Baker defined cool jazz; he also arranged for Birth of the Cool.")
        case .tomHarrell:
            return MasterProfile(
                avatarImageName: "TomHarrell",
                title: "Tom Harrell (b. 1946)",
                bio: "Trumpeter and flugelhornist with harmonically sophisticated, lyrical playing blending Clifford Brown's power with Chet Baker's tenderness. A Horace Silver and Phil Woods veteran, and 2018 JJA Trumpeter of the Year.")
        case .tomHarrellWaltzes:
            return MasterProfile(
                avatarImageName: "TomHarrell",
                title: "Tom Harrell Waltzes (b. 1946)",
                bio: "The same trumpeter and flugelhornist, heard in 3/4 time. A waltz-focused set of his lyrical, harmonically rich lines.")
        case .nickBrignola:
            return MasterProfile(
                avatarImageName: "NickBrignola",
                title: "Nick Brignola (1936–2002)",
                bio: "Baritone saxophonist with fluid, powerful playing shaped by Harry Carney. Known for Baritone Madness and L.A. Bound.")

        // ── 2 LSTM（穷尽兜底：Learning 卡保留 ModeBlurb，不会实际展示本数据）──
        case .combination:
            return MasterProfile(
                avatarImageName: "LaunchIcon",
                title: "Combination",
                bio: "A neural model trained on many jazz masters.")
        case .greatMoments:
            return MasterProfile(
                avatarImageName: "LaunchIcon",
                title: "Great Moments",
                bio: "A neural model trained on selected jazz solos.")
        }
    }

    /// Grammar 卡当前应展示的 profile：随 Use Soloist / Use Grammar 切换。
    /// - Use Grammar：取 selectedAlgorithm。
    /// - Use Soloist：取 selectedResource 对应大师（Motif 经 fallbackAlgorithm 归一）。
    static func currentProfile(useSoloist: Bool,
                               selectedAlgorithm: ContentView.ImproAlgorithmType,
                               selectedResource: String) -> MasterProfile {
        if useSoloist,
           let descriptor = SoloistResourceDirectory.descriptor(for: selectedResource) {
            return profile(for: descriptor.fallbackAlgorithm)
        }
        return profile(for: selectedAlgorithm)
    }
}
