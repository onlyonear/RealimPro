#!/bin/bash
# =====================================================================
# P3-b 一键回退脚本：撤销「二级菜单 + 46 .sty 风格批量移植」
# 回退后状态 = P3-a 验收关闭时：
#   - StyleParser.swift / StyleEngine.swift / BandMixerView.swift 恢复到 P3-b 改前备份
#   - Resources/Styles/ 只保留 P3-a 的 swing.sty（删除 P3-b 新增的 45 个 .sty）
#   - P3-a 的 11 个 StyleEngine 引擎文件、swing.sty、其余全部文件保持不动
# 注意：本脚本不删除 scripts/p3b_regress.sh 与 .backup/（证据保留，不进 App 包）
# 回退完成后请在 Xcode 用 ⌘B 重新构建（GUI 为准）。
# =====================================================================
set -u

PROJ="/Users/onlyonear/Desktop/Improlyze"
BK="$PROJ/.backup/P3b-20261011"
ENG_DIR="$PROJ/Real imPro/MidiPlayer/StyleEngine"
STY_DIR="$PROJ/Real imPro/Resources/Styles"

# P3-b 改前三文件基线 SHA1（与《P3-b 逐 hunk diff》§1 一致）
BASE_PARSER="e6441954f99c8ca6175a1fd1366ec8e88ea70bbb"
BASE_ENGINE="f7f64f0050dcd967afef2f83a29974a025c81efa"
BASE_MIXER="3f7b8151d6c185c6c89b73ad67d1e3da4f1179f9"

cd "$PROJ" || { echo "工程目录不存在: $PROJ"; exit 9; }

# 0. 备份完整性检查
for f in StyleParser.swift StyleEngine.swift BandMixerView.swift; do
  if [ ! -f "$BK/$f" ]; then echo "缺少备份，中止: $BK/$f"; exit 9; fi
done
echo "[1/3] 备份齐全，恢复三个生产文件..."
cp "$BK/StyleParser.swift" "$ENG_DIR/StyleParser.swift"
cp "$BK/StyleEngine.swift"  "$ENG_DIR/StyleEngine.swift"
cp "$BK/BandMixerView.swift" "$PROJ/Real imPro/Views/BandMixerView.swift"

echo "[2/3] 校验恢复后 SHA1（应与基线一致）..."
ok=1
chk() { # $1=文件 $2=期望sha1
  got=$(shasum -a 1 "$1" | awk '{print $1}')
  if [ "$got" = "$2" ]; then echo "  OK   $(basename "$1") $got"; else echo "  MISMATCH $(basename "$1") got=$got want=$2"; ok=0; fi
}
chk "$ENG_DIR/StyleParser.swift" "$BASE_PARSER"
chk "$ENG_DIR/StyleEngine.swift"  "$BASE_ENGINE"
chk "$PROJ/Real imPro/Views/BandMixerView.swift" "$BASE_MIXER"

echo "[3/3] 删除 P3-b 新增的 45 个 .sty（保留 P3-a 的 swing.sty）..."
before=$(find "$STY_DIR" -name '*.sty' | wc -l | tr -d ' ')
find "$STY_DIR" -name '*.sty' ! -name 'swing.sty' -delete
after=$(find "$STY_DIR" -name '*.sty' | wc -l | tr -d ' ')
echo "  回退前 .sty 数=$before，回退后 .sty 数=$after（期望 1：仅 swing.sty）"

echo
if [ "$ok" = "1" ] && [ "$after" = "1" ]; then
  echo "✅ P3-b 已回退到 P3-a 状态。请在 Xcode ⌘B 重新构建确认。"
  exit 0
else
  echo "⚠️ 回退完成但校验异常，请人工核对上方 MISMATCH / .sty 计数。"
  exit 1
fi
