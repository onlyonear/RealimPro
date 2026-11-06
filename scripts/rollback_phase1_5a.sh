#!/bin/bash
# P1.5a 一键回退：仅撤销「胶囊常驻 + 切链路复位 Transform」两处 UI 微调，保留 P1.5 全部改动
# 用法：bash scripts/rollback_phase1_5a.sh
set -e
ROOT="/Users/onlyonear/Desktop/Improlyze"
cd "$ROOT"
cp ".backup/BandMixerView.swift.P1.5a-capsule-backup" "Real imPro/Views/BandMixerView.swift"
cp ".backup/ContentView.swift.P1.5a-groupreset-backup" "Real imPro/Views/ContentView.swift"
echo "P1.5a 已回退（P1.5 保留），请在 Xcode GUI 重新 Build（Product > Build）"
