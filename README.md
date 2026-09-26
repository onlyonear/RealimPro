# Real imPro — iOS source code

Real imPro is an iPad application for jazz practice: automatic key/roadmap
analysis, guide-tone lines, full piano voicings, grammar-based and
theme-based solo generation, transform/substitution engines, MIDI
playback with accompaniment, and MusicXML import.

Large parts of this application are a **Swift port of Impro-Visor**
("Improvisation Advisor"), originally created by Prof. Robert Keller and
Harvey Mudd College.

- Upstream project : https://www.cs.hmc.edu/~keller/jazz/improvisor/
- Upstream source  : https://github.com/Impro-Visor/Impro-Visor

## License

Impro-Visor is licensed under the GNU General Public License **version 2,
or (at your option) any later version** (GPL-2.0-or-later). This
derivative work is released under **version 2 of the GPL** (the new code
in this repository is GPL-2.0-only). See [LICENSE](LICENSE) and
[NOTICE](NOTICE).

The bundled components below keep their own licenses; all are
GPL-compatible:

| Component | File | License |
| --- | --- | --- |
| VexFlow | `Real imPro/vexflow-min.js` | MIT |
| music21 (approach reference, no code copied) | `Real imPro/Importers/MusicXML/MusicXMLRepeater.swift` | BSD-3-Clause |
| Chorium custom revision SoundFont | `Real imPro/MidiPlayer/ChoriumRevA.sf2` | freeware by openwrld; redistribution permission requested |

## About selling this software on the App Store

The GPL explicitly permits charging money for copies of the software.
This application is sold on the App Store; that is compatible with the
license, provided every recipient can obtain the complete corresponding
source code. The source is provided here, and every build distributed on
the App Store has (where a snapshot was retained) a matching tag in this
repository — see "Tags" below.

If you cannot access this repository, you may request a machine-readable
copy of the source corresponding to any version you obtained, by writing
to **onearonly@gmail.com**. We will provide it for no more than the cost
of distribution, in line with section 3 of the GPL v2.

## Building

Requirements:

- Xcode (the project was created with the Xcode 26 toolchain)
- iOS/iPadOS deployment target: 16.6
- Target device: iPad (`TARGETED_DEVICE_FAMILY = 2`)

Steps:

1. Open `RealimPro.xcodeproj` in Xcode.
2. Select the `RealimPro` scheme and an iPad destination.
3. Choose your own signing team in the target settings, then build.

There are no package-manager dependencies (no SwiftPM, CocoaPods or
Carthage); all required resources (SoundFont, grammar files, VexFlow) are
bundled inside the `Real imPro` folder.

## Repository layout

```
Real imPro/                  Application source and bundled resources
RealimPro.xcodeproj/         Xcode project
RealimPro-Info.plist         Additional Info.plist settings (URL schemes)
LICENSE                      GNU General Public License v2 text
NOTICE                       Copyright and third-party attribution
PROVENANCE.md                File-by-file origin inventory
```

## Tags

Tags correspond to builds distributed on the App Store:

| Tag | App Store version | Distribution date | Source status |
| --- | --- | --- | --- |
| `v1.0` | 1.0 | 2026-08-19 | Snapshot retained |
| `v1.01` | 1.01 | 2026-08-21 | Snapshot retained |
| — | 1.02 | 2026-08-26 | No snapshot retained; source on request by email |
| `v1.03` | 1.03 | 2026-09-03 | Snapshot retained |
| — | 1.04 | 2026-09-06 | No snapshot retained; source on request by email |
| — | 1.05 | 2026-09-08 | No snapshot retained; source on request by email |
| `v1.06` | 1.06 | 2026-09-17 | Snapshot retained (working files dated up to 2026-09-16) |

The three versions without tags were incremental updates; their source
differs only incrementally from the adjacent tagged versions, and a copy
will be provided on request under the GPL source offer above.

## SoundFont note

The bundled SoundFont is a custom revision of Chorium by **openwrld**
(openwrld@kebi.com), publicly distributed as freeware. Because the GPL
requires recipients to be able to redistribute everything in this
repository, permission to redistribute the SoundFont has been requested
from the author. If that permission is not granted, the SoundFont will be
replaced with one under an explicit permissive license (e.g. GeneralUser
GS or MuseScore General, both MIT-licensed).

## Contact

RealimPro — **onearonly@gmail.com**
