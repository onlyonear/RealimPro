#!/bin/bash
# P1.5 一键回退：色彩分层独立（卡片管源头 / 调音台管 Transform 最终整流）
# 用法：bash scripts/rollback_phase1_5.sh
set -e
ROOT="/Users/onlyonear/Desktop/Improlyze"
cd "$ROOT"
cp ".backup/ContentView.swift.P1.5-colorlayer-backup" "Real imPro/Views/ContentView.swift"
cp ".backup/BandMixerView.swift.P1.5-colorlayer-backup" "Real imPro/Views/BandMixerView.swift"
cp ".backup/ModeSettingsCard.swift.P1.5-colorlayer-backup" "Real imPro/Views/ModeSettingsCard.swift"
cp ".backup/GrammarStrategy.swift.P1.5-colorlayer-backup" "Real imPro/Grammar/GrammarStrategy.swift"
cp ".backup/GrammarLickGlue.swift.P1.5-colorlayer-backup" "Real imPro/Grammar/GrammarLickGlue.swift"
echo "P1.5 已回退，请在 Xcode GUI 重新 Build（Product > Build）"
