#!/bin/bash
# P3-c 一键回退：恢复 3 个被改文件、删除新增 AccompanimentMix.swift，并做 SHA1 自检。
set -u
PROJ="/Users/onlyonear/Desktop/Improlyze"
BAK="$PROJ/.backup/P3c-20261011"
cd "$PROJ" || exit 9

cp "$BAK/JazzMidiPlayer.swift.bak"        "$PROJ/Real imPro/MidiPlayer/JazzMidiPlayer.swift"
cp "$BAK/StyleChordRenderer.swift.bak"    "$PROJ/Real imPro/MidiPlayer/StyleEngine/StyleChordRenderer.swift"
cp "$BAK/StyleBassRenderer.swift.bak"     "$PROJ/Real imPro/MidiPlayer/StyleEngine/StyleBassRenderer.swift"
rm -f "$PROJ/Real imPro/MidiPlayer/StyleEngine/AccompanimentMix.swift"

echo "== SHA1 自检（应回落到改前基线）=="
shasum -a 1 "$PROJ/Real imPro/MidiPlayer/JazzMidiPlayer.swift" \
            "$PROJ/Real imPro/MidiPlayer/StyleEngine/StyleChordRenderer.swift" \
            "$PROJ/Real imPro/MidiPlayer/StyleEngine/StyleBassRenderer.swift"
# 期望：
# 85f300d2d84e58af32fce7801b950e18a8d19e07  JazzMidiPlayer.swift
# 4603690cbe379fae4552db7896f938109c8a0476  StyleChordRenderer.swift
# 8ad71953817c2390075f373ade15251ec3c8a3bb  StyleBassRenderer.swift
echo "回退完成：请在 Xcode ⇧⌘K Clean Build Folder 后 ⌘B 全量重建。"
