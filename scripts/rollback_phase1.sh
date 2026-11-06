#!/bin/bash
# Real imPro P1（设置卡片化）一键回退：恢复 3 个备份文件 + 删除新卡片文件
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

cp ".backup/GuideLineGenerator.swift.P1-settingscard-backup" "Real imPro/GuideTone/GuideLineGenerator.swift"
cp ".backup/ContentView.swift.P1-settingscard-backup"        "Real imPro/Views/ContentView.swift"
cp ".backup/BandMixerView.swift.P1-settingscard-backup"      "Real imPro/Views/BandMixerView.swift"
rm -f "Real imPro/Views/ModeSettingsCard.swift"

echo "P1 已回退。请在 Xcode 重新 Build 确认。"
