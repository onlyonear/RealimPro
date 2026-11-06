#!/bin/bash
# P3-f 一键回退：下架最后 3 个手写 Simple 伴奏（Simple Shuffle/Afro/Bossa）
set -euo pipefail
PROJ="/Users/onlyonear/Desktop/Improlyze"
BK="$PROJ/.backup/P3f-20261011"
cp "$BK/BandMixerView.swift.bak" "$PROJ/Real imPro/Views/BandMixerView.swift"
cp "$BK/ContentView.swift.bak"   "$PROJ/Real imPro/Views/ContentView.swift"
echo "已回退 P3-f。回退后 SHA1 应为："
echo "  BandMixerView 721e930ac5cc021a604c8c88c24e4c81c1acf5d7"
echo "  ContentView    d69d1afae158c618fcd022bf7fd31f53787c1a40"
shasum -a 1 "$PROJ/Real imPro/Views/BandMixerView.swift" "$PROJ/Real imPro/Views/ContentView.swift"
echo "请在 Xcode ⇧⌘K Clean Build Folder 后重新构建。"
