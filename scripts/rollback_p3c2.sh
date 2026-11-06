#!/bin/bash
# P3-c.2 回退：恢复 2 个备份文件（移除手写专属响度补偿，回到 P3-e 状态）
set -u
PROJ="/Users/onlyonear/Desktop/Improlyze"
BK="$PROJ/.backup/P3c2-20261011"
cd "$PROJ" || exit 9
cp "$BK/AccompanimentMix.swift.bak" "Real imPro/MidiPlayer/StyleEngine/AccompanimentMix.swift"
cp "$BK/JazzMidiPlayer.swift.bak"        "Real imPro/MidiPlayer/JazzMidiPlayer.swift"
echo "已回退 P3-c.2，回退后 SHA1："
shasum -a 1 "Real imPro/MidiPlayer/StyleEngine/AccompanimentMix.swift" \
            "Real imPro/MidiPlayer/JazzMidiPlayer.swift"
echo "请在 Xcode ⇧⌘K Clean Build Folder 后全量重建。"
