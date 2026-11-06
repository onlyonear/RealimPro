#!/bin/bash
# P2.2 一键回退：撤销顶部工具栏「Settings 图标化 + 44×44 热区」改动，恢复到 P2.1 落地后状态
# 用法：bash scripts/rollback_phase2_2.sh
# 说明：P2.2 仅改动 ContentView.swift 一个文件（纯 UI/接线，未触任何算法/引擎/资源）。
set -e
ROOT="/Users/onlyonear/Desktop/Improlyze"
cd "$ROOT"

BAK=".backup/ContentView.swift.P22-toolbar-hitarea-backup"
DST="Real imPro/Views/ContentView.swift"

if [ ! -f "$BAK" ]; then
  echo "找不到备份 $BAK，终止（未做任何改动）。"; exit 1
fi

echo "回退前当前文件 SHA1："; shasum -a 1 "$DST"
cp "$BAK" "$DST"
echo "已从备份恢复 ContentView.swift。"
echo "回退后 SHA1（应为 ee2b7997aa0acfc02346a0af735e3e8ecf631b9a = P2.1 落地后）："
shasum -a 1 "$DST"
echo
echo "P2.2 已回退。请在 Xcode GUI 重新 ⌘B Build / ⌘R 运行确认。"
