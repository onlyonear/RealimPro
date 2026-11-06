#!/bin/bash
# P3-a 一键回退：恢复 4 个被改生产文件，并删除新增的 StyleEngine 目录与 swing.sty 资源。
# 用法：bash scripts/rollback_p3a.sh
set -e
ROOT="/Users/onlyonear/Desktop/Improlyze"
BAK="$ROOT/.backup/P3a-20261010"
cd "$ROOT"

if [ ! -d "$BAK" ]; then
  echo "未找到备份目录 $BAK，无法回退。"
  exit 1
fi

cp "$BAK/AccompanimentModels.swift"   "$ROOT/Real imPro/MidiPlayer/AccompanimentModels.swift"
cp "$BAK/AccompanimentGenerator.swift" "$ROOT/Real imPro/MidiPlayer/AccompanimentGenerator.swift"
cp "$BAK/JazzMidiPlayer.swift"        "$ROOT/Real imPro/MidiPlayer/JazzMidiPlayer.swift"
cp "$BAK/BandMixerView.swift"         "$ROOT/Real imPro/Views/BandMixerView.swift"

rm -rf "$ROOT/Real imPro/MidiPlayer/StyleEngine"
rm -f  "$ROOT/Real imPro/Resources/Styles/swing.sty"
rmdir  "$ROOT/Real imPro/Resources/Styles" 2>/dev/null || true
rmdir  "$ROOT/Real imPro/Resources"        2>/dev/null || true

echo "P3-a 已回退（4 个生产文件已恢复，新增引擎与 swing.sty 已删除）。"
echo "请在 Xcode ⌘⇧K Clean Build Folder 后重新 ⌘B 验证。"
