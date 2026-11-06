#!/bin/bash
# =====================================================================
# P3-b.1 一键回退脚本
# 作用：撤销「下架 Light Shuffle / Triplet Rock / Triplet Rock 2（46→43）」
# 回退后状态 = P3-b（46 风格）
# 用法：bash scripts/rollback_p3b1.sh
# 回退完成后请在 Xcode 执行 Product > Clean Build Folder（⇧⌘K）再 ⌘B
# =====================================================================
set -euo pipefail

ROOT="/Users/onlyonear/Desktop/Improlyze"
BK="$ROOT/.backup/P3b1-20261011"
STY_DIR="$ROOT/Real imPro/Resources/Styles"
SE="$ROOT/Real imPro/MidiPlayer/StyleEngine/StyleEngine.swift"
BM="$ROOT/Real imPro/Views/BandMixerView.swift"
REG="$ROOT/scripts/p3b_regress.sh"

EXPECT_SE="26111d768fe7c89ce15a34842e2a87107d0d8004"   # P3-b 后 StyleEngine
EXPECT_BM="c849ee0eb08358e2d28e95a4154c1f798dd214c2"   # P3-b 后 BandMixerView

cd "$ROOT"

echo "== 1/4 恢复两个生产 .swift（旧码=P3-b 基线）=="
cp "$BK/StyleEngine.swift.bak" "$SE"
cp "$BK/BandMixerView.swift.bak" "$BM"

echo "== 2/4 还原回归探针脚本（ITEMS=46）=="
cp "$BK/p3b_regress.sh.bak" "$REG"

echo "== 3/4 移回 3 个被下架的 .sty（幂等：已在位则跳过）=="
for f in shuffle-light.sty rock-triplet.sty rock-triplet-2.sty; do
  if [ -f "$BK/removed_styles/$f" ]; then
    mv "$BK/removed_styles/$f" "$STY_DIR/$f"
    echo "   移回 $f"
  else
    echo "   $f 已在位或备份缺失，跳过"
  fi
done

echo "== 4/4 SHA1 与计数自检 =="
GOT_SE=$(shasum -a 1 "$SE" | awk '{print $1}')
GOT_BM=$(shasum -a 1 "$BM" | awk '{print $1}')
[ "$GOT_SE" = "$EXPECT_SE" ] && echo "  StyleEngine   SHA1 ✓ ($GOT_SE)" || { echo "  StyleEngine   SHA1 ✗ 得到 $GOT_SE 期望 $EXPECT_SE"; exit 1; }
[ "$GOT_BM" = "$EXPECT_BM" ] && echo "  BandMixerView SHA1 ✓ ($GOT_BM)" || { echo "  BandMixerView SHA1 ✗ 得到 $GOT_BM 期望 $EXPECT_BM"; exit 1; }
N=$(find "$STY_DIR" -name '*.sty' | wc -l | tr -d ' ')
echo "  Styles 目录 .sty 数 = $N（期望 46）"
[ "$N" = "46" ] || { echo "  计数不符 ✗"; exit 1; }

echo
echo "回退完成（=P3-b，46 风格）。请在 Xcode ⇧⌘K Clean Build Folder 后 ⌘B 重建。"
