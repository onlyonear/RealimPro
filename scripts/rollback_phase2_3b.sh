#!/bin/bash
# rollback_phase2_3b.sh
# 一键回退 P2.3b（设置卡自定义紧凑卡片 + Range 子页重做）
# 恢复到 P2.3 落地态：
#   ModeSettingsCard.swift = 51af3480dd50a9794b28bd3bd909a3d5a83d228c
#   ContentView.swift      = c030744f592b824ead096a6e2604ac360813c694
# ChordDictionaryView.swift 本轮未改，不回退。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIEWS="$ROOT/Real imPro/Views"
BACKUP="$ROOT/.backup"

MODE_BAK="$BACKUP/ModeSettingsCard.swift.P23b-compact-card-backup"
CONTENT_BAK="$BACKUP/ContentView.swift.P23b-compact-card-backup"

MODE_EXPECT="51af3480dd50a9794b28bd3bd909a3d5a83d228c"
CONTENT_EXPECT="c030744f592b824ead096a6e2604ac360813c694"

echo "==> 回退 P2.3b，恢复 P2.3 落地态"

for bak in "$MODE_BAK" "$CONTENT_BAK"; do
  if [ ! -f "$bak" ]; then
    echo "错误：找不到备份 $bak" >&2
    exit 1
  fi
done

cp "$MODE_BAK" "$VIEWS/ModeSettingsCard.swift"
cp "$CONTENT_BAK" "$VIEWS/ContentView.swift"

echo "==> 回退后 SHA1 核对："
MODE_GOT="$(shasum -a 1 "$VIEWS/ModeSettingsCard.swift" | awk '{print $1}')"
CONTENT_GOT="$(shasum -a 1 "$VIEWS/ContentView.swift" | awk '{print $1}')"
echo "  ModeSettingsCard.swift = $MODE_GOT"
echo "  ContentView.swift      = $CONTENT_GOT"

ok=1
if [ "$MODE_GOT" != "$MODE_EXPECT" ]; then
  echo "错误：ModeSettingsCard.swift SHA1 不匹配（期望 $MODE_EXPECT）" >&2; ok=0
fi
if [ "$CONTENT_GOT" != "$CONTENT_EXPECT" ]; then
  echo "错误：ContentView.swift SHA1 不匹配（期望 $CONTENT_EXPECT）" >&2; ok=0
fi

if [ "$ok" -eq 1 ]; then
  echo "==> 回退完成，SHA1 全部匹配 P2.3 落地态。请在 Xcode 重新 Build。"
else
  exit 1
fi
