#!/bin/bash
# P2 一键回退：撤销 Basic/Master→Grammar 合并，恢复 P1.5a 后状态
# 用法：bash scripts/rollback_phase2.sh
set -e
ROOT="/Users/onlyonear/Desktop/Improlyze"
cd "$ROOT"
cp ".backup/ContentView.swift.P2-grammar-merge-backup"      "Real imPro/Views/ContentView.swift"
cp ".backup/ModeSettingsCard.swift.P2-grammar-merge-backup" "Real imPro/Views/ModeSettingsCard.swift"
echo "P2 已回退（ContentView / ModeSettingsCard 恢复到 P1.5a）。请在 Xcode GUI 重新 Build。"
shasum -a 1 "Real imPro/Views/ContentView.swift" "Real imPro/Views/ModeSettingsCard.swift"
