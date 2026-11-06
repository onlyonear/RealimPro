#!/bin/bash
# =====================================================================
# P3-c.1 一键回退脚本
# 作用：撤销「手写伴奏增益恢复」修复，把 JazzMidiPlayer.swift 恢复到
#       P3-c 落地后、P3-c.1 之前的状态（SHA1 c7fa2726…）。
# 说明：P3-c.1 只改了 JazzMidiPlayer.swift 一个文件，故回退只需还原它；
#       .sty 分支、AccompanimentMix、两个 renderer 均不受 P3-c.1 影响。
# 回退后请在 Xcode 按 ⇧⌘K (Clean Build Folder) 再 ⌘B 重新构建。
# =====================================================================
set -e

ROOT="/Users/onlyonear/Desktop/Improlyze"
BAK="$ROOT/.backup/P3c1-20261011/JazzMidiPlayer.swift.bak"
DST="$ROOT/Real imPro/MidiPlayer/JazzMidiPlayer.swift"
EXPECT="c7fa27269c3cb5dca2fae74cfe2814f0af3bab4e"

if [ ! -f "$BAK" ]; then
  echo "找不到备份：$BAK"
  exit 1
fi

cp "$BAK" "$DST"
GOT=$(shasum -a 1 "$DST" | awk '{print $1}')

if [ "$GOT" != "$EXPECT" ]; then
  echo "回退后 SHA1 不符：$GOT"
  echo "期望：$EXPECT"
  exit 1
fi

echo "已回退 P3-c.1：JazzMidiPlayer.swift 恢复为 $GOT"
echo "下一步：Xcode ⇧⌘K Clean Build Folder，然后 ⌘B 重新构建。"
