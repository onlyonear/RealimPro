#!/bin/bash
# P2.3 一键回退：撤销「Mode Settings 卡片美化（完整词 + 问号帮助 + 帮助/致谢入口拆分 + 卡片静态说明行）」，恢复到 P2.2a 最终态
# 用法：bash scripts/rollback_phase2_3.sh
# 说明：P2.3 仅改动 3 个文件（纯 UI/呈现，未触任何算法/引擎/信号流/默认值/持久化键/资源）：
#   - Real imPro/Views/ModeSettingsCard.swift
#   - Real imPro/Views/ChordDictionaryView.swift
#   - Real imPro/Views/ContentView.swift
# LicensesView.swift / BandMixerView.swift 本轮未改。
set -e
ROOT="/Users/onlyonear/Desktop/Improlyze"
cd "$ROOT"

PAIRS=(
  ".backup/ModeSettingsCard.swift.P23-card-beautify-backup|Real imPro/Views/ModeSettingsCard.swift|0b91ce7babea2535a488d6dee553ab44d26136ac"
  ".backup/ChordDictionaryView.swift.P23-card-beautify-backup|Real imPro/Views/ChordDictionaryView.swift|edeffb68a649428b6d8c47ad2adb6fd19fbe288f"
  ".backup/ContentView.swift.P23-card-beautify-backup|Real imPro/Views/ContentView.swift|e37263ff53ccfa703231cba6d0ba284fda29bdf0"
)

for p in "${PAIRS[@]}"; do
  BAK="${p%%|*}"; rest="${p#*|}"; DST="${rest%%|*}"; EXPECT="${rest##*|}"
  if [ ! -f "$BAK" ]; then
    echo "找不到备份 $BAK，终止（未做任何改动）。"; exit 1
  fi
  echo "== 回退 $DST"
  echo "回退前 SHA1："; shasum -a 1 "$DST"
  cp "$BAK" "$DST"
  echo "回退后 SHA1（应为 $EXPECT）："
  shasum -a 1 "$DST"
  echo
done

echo "P2.3 已回退（恢复到 P2.2a 最终态）。请在 Xcode GUI 重新 ⌘B Build / ⌘R 运行确认。"
