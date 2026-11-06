#!/usr/bin/env bash
# P2.3c 一键回退：仅还原 Guide 设置卡标题 "GuideTone Settings" -> "Guide Settings"
# 还原 ModeSettingsCard.swift 到 P2.3c 改前（= P2.3b 落地态，SHA1 6787123d）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$ROOT/Real imPro/Views/ModeSettingsCard.swift"
BACKUP="$ROOT/.backup/ModeSettingsCard.swift.P23c-title-backup"
EXPECT="6787123d66ebe930220773ef72c64f49bde9b80b"

if [ ! -f "$BACKUP" ]; then
  echo "❌ 备份不存在：$BACKUP"
  exit 1
fi

GOT="$(shasum "$BACKUP" | awk '{print $1}')"
if [ "$GOT" != "$EXPECT" ]; then
  echo "❌ 备份 SHA1 校验失败：期望 $EXPECT，实际 $GOT"
  exit 1
fi

cp "$BACKUP" "$FILE"
echo "✅ 已回退 ModeSettingsCard.swift 至 P2.3b 落地态（标题恢复 \"Guide Settings\"）。"
echo "请在 Xcode 重新 Build（⌘B）。"
