# RealimPro

RealimPro is an offline, iPad-only jazz practice companion. It turns chord
charts into a playable virtual combo — saxophone, piano, bass and drums — with
automatic accompaniment styles, solo generation, trading (call-and-response)
over a connected MIDI instrument, and interactive sheet music.

Everything runs fully on-device: no account, no network, no telemetry.

## Features

- **Virtual jazz combo** — four General MIDI instruments (melody, piano, bass,
  drums) rendered through an on-device SoundFont and `AVAudioEngine`.
- **Accompaniment styles** — jazz, bossa nova, blues and more, with swing and
  configurable tempo / repeats / count-in.
- **Solo generation** — grammar-based and LSTM-based improvisation, plus a
  "faithful" engine that recreates the style of specific master players.
- **Trading** — connect a MIDI instrument and trade fours/eights with the app
  in real time, with hot-reconnect and passive engines.
- **Master profiles** — pick a named master to drive both the solo engine and
  the mixer instrument.
- **Interactive sheet music** — rendered in-app with VexFlow, with analysis
  modes, transposition and MusicXML import.
- **Built-in library** — curated classic jazz and "for soloist" playlists.

## System Requirements

- iPad, iPadOS **16.6 or later**
- Xcode 26.x or later, Swift 5
- The app builds for the iPad device family (`TARGETED_DEVICE_FAMILY = 2`).

## Getting the Source

```bash
git clone https://github.com/onlyonear/RealimPro.git
cd RealimPro
```

## Getting the SoundFont

The instrument SoundFont is **not included** in this repository because its
redistribution terms are not clearly stated. See `THIRD_PARTY_NOTICES.md`
(section 4) for the full background.

To build and run with sound:

1. Obtain a copy of **`ChoriumRevA.sf2`** (a free SoundFont published by
   openwrld, widely available from SoundFont archives).
2. Place the file at exactly this path inside the project:

   ```
   Real imPro/MidiPlayer/ChoriumRevA.sf2
   ```

3. The file is matched by `.gitignore` and will never be committed.

The project still **compiles without the SoundFont** — it is located at runtime
through `Bundle.main.url(forResource:withExtension:)`. If it is missing, the app
logs a message and simply produces no instrument sound rather than crashing.

## Building

Open the project and build the `RealimPro` scheme:

```bash
open RealimPro.xcodeproj
```

Or build from the command line (signing uses the automatic "Sign to Run Locally"
style; no certificates are stored in the repository):

```bash
xcodebuild -project RealimPro.xcodeproj -scheme RealimPro \
  -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

## Project Layout

```
Real imPro/
  MidiPlayer/      AVAudioEngine setup, samplers, playback and timing
  Views/           SwiftUI interface, mixer, sheets and popovers
  Soloist/         Solo engines, including the faithful master models
  Grammar/         Grammar engine and note conversion
  LSTM/            LSTM inference and bundled model files
  Roadmap/         Parser and Java-aligned (Impro-Visor) port
  Trading/         MIDI input, passthrough and call-and-response
  Importers/       MusicXML import
  Resources/       Accompaniment styles
  grammars/        Grammar rule files
  en.lproj/        English localization
  Assets.xcassets/ App icons and master portraits
RealimPro.xcodeproj/
LICENSE
THIRD_PARTY_NOTICES.md
```

## License

RealimPro is released under the **GNU General Public License v2 (GPL-2.0)**;
the full text is in `LICENSE`. It is derived in part from Impro-Visor
(GPL-2.0-or-later). Third-party components and their licenses are listed in
`THIRD_PARTY_NOTICES.md`.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

## Contact

Maintainer: OnlyOnera — onearonly@gmail.com

If you are a rights holder of any referenced component and would like a notice
corrected or removed, please reach out and it will be handled promptly.
