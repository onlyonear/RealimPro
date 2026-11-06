#!/bin/bash
set -euo pipefail
cd "/Users/onlyonear/Desktop/Improlyze"
B=".backup/P1-20261010"
cp "$B/Real imPro/Views/ContentView.swift"                    "Real imPro/Views/ContentView.swift"
cp "$B/Real imPro/Views/IAPManager.swift"                     "Real imPro/Views/IAPManager.swift"
cp "$B/Real imPro/Importers/MusicXML/MusicXMLQuantizer.swift" "Real imPro/Importers/MusicXML/MusicXMLQuantizer.swift"
cp "$B/Real imPro/Importers/MusicXML/MusicXMLImporter.swift"  "Real imPro/Importers/MusicXML/MusicXMLImporter.swift"
cp "$B/Real imPro/Importers/MusicXML/MusicXMLRepeater.swift"  "Real imPro/Importers/MusicXML/MusicXMLRepeater.swift"
cp "$B/Real imPro/en.lproj/Localizable.strings"               "Real imPro/en.lproj/Localizable.strings"
rm -f "Real imPro/PrivacyInfo.xcprivacy"
echo "P1 已全部回退；请在 Xcode Clean Build Folder 后重新 ⌘B。"
