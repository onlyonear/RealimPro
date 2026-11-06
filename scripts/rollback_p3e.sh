#!/bin/bash
# P3-e 一键回退：下架 7 伴奏 + 手写/.sty 等响
# 作用：恢复 5 个被改 .swift 到 P3-e 前字节，并把 3 个 mv 走的 .sty 移回 Resources/Styles（.sty 50 → 53）。
set -euo pipefail
ROOT="/Users/onlyonear/Desktop/Improlyze"
BK="$ROOT/.backup/P3e-20261011"
cd "$ROOT"

echo "==> 恢复 5 个生产文件"
cp "$BK/BandMixerView.swift.bak"     "Real imPro/Views/BandMixerView.swift"
cp "$BK/StyleEngine.swift.bak"       "Real imPro/MidiPlayer/StyleEngine/StyleEngine.swift"
cp "$BK/ContentView.swift.bak"       "Real imPro/Views/ContentView.swift"
cp "$BK/JazzMidiPlayer.swift.bak"    "Real imPro/MidiPlayer/JazzMidiPlayer.swift"
cp "$BK/AccompanimentMix.swift.bak"  "Real imPro/MidiPlayer/StyleEngine/AccompanimentMix.swift"

echo "==> 移回 3 个下架的 .sty"
mv "$BK/removed_styles/blues-clair.sty"   "Real imPro/Resources/Styles/"
mv "$BK/removed_styles/waltz-chopin.sty"  "Real imPro/Resources/Styles/"
mv "$BK/removed_styles/african-slow.sty"  "Real imPro/Resources/Styles/"

echo "==> 回退后 SHA1（应与 P3-e 前基线一致）："
shasum -a1 \
  "Real imPro/Views/BandMixerView.swift" \
  "Real imPro/MidiPlayer/StyleEngine/StyleEngine.swift" \
  "Real imPro/Views/ContentView.swift" \
  "Real imPro/MidiPlayer/JazzMidiPlayer.swift" \
  "Real imPro/MidiPlayer/StyleEngine/AccompanimentMix.swift"
echo "生产 .sty 计数：$(ls -1 "Real imPro/Resources/Styles/"*.sty | wc -l | tr -d ' ')（应为 53）"
echo "P3-e 已回退。请在 Xcode 按 ⇧⌘K Clean Build Folder 后重新 Build。"
