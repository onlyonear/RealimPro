#!/bin/bash
# P2.2a 一键回退：撤销「Guide→GuideTone 改名 + mini 竖宽度回收（M92/spacing0/trailing14）」，恢复到 P2.2 最终态
# 用法：bash scripts/rollback_phase2_2a.sh
# 说明：P2.2a 仅改动 ContentView.swift 一个文件（显示名 + mini 竖三处布局常数，未触任何算法/引擎/资源/其它档宽度）。
set -e
ROOT="/Users/onlyonear/Desktop/Improlyze"
cd "$ROOT"

BAK=".backup/ContentView.swift.P22a-guidetone-backup"
DST="Real imPro/Views/ContentView.swift"

if [ ! -f "$BAK" ]; then
  echo "找不到备份 $BAK，终止（未做任何改动）。"; exit 1
fi

echo "回退前当前文件 SHA1："; shasum -a 1 "$DST"
cp "$BAK" "$DST"
echo "已从备份恢复 ContentView.swift。"
echo "回退后 SHA1（应为 f0ceb1d66dbb59644dc85cee8159be563d406007 = P2.2 最终态，菜单显示名恢复 Grammar 时代）："
shasum -a 1 "$DST"
echo
echo "P2.2a 已回退。请在 Xcode GUI 重新 ⌘B Build / ⌘R 运行确认。"
