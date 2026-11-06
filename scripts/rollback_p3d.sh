#!/bin/bash
# P3-d 回退：恢复 3 个代码文件（StyleEngine / BandMixerView / StyleBassRenderer）+ 删除 10 个新增 .sty，
# 然后请在 Xcode 手动 ⇧⌘K Clean Build Folder 后 ⌘B 验证。
set -u
ROOT="/Users/onlyonear/Desktop/Improlyze"
BK="$ROOT/.backup/P3d-20261011"
DST="$ROOT/Real imPro"
NEW_STY=(ballad bossa bossaA bossaB waltz waltz-chopin waltz-parisienne african african-slow african3)

echo "== 恢复代码文件（SHA1 校验） =="
restore() {
  local rel="$1"; local want="$2"
  cp "$BK/$(basename "$rel").bak" "$DST/$rel"
  local got; got=$(shasum -a 1 "$DST/$rel" | awk '{print $1}')
  if [ "$got" = "$want" ]; then
    echo "OK   $rel"
  else
    echo "SHA1 MISMATCH $rel got=$got want=$want"
    exit 9
  fi
}
restore "MidiPlayer/StyleEngine/StyleEngine.swift"       "63abdedfd19198c940805546a5d762dfa2c035af"
restore "Views/BandMixerView.swift"                     "890397d6424dd3135c6b08e14db579c4e810e1e1"
restore "MidiPlayer/StyleEngine/StyleBassRenderer.swift" "a3a663f88091428fddc53cb426fe7bbc545d0578"

echo "== 删除 P3-d 新增的 10 个 .sty =="
for f in "${NEW_STY[@]}"; do
  if [ -f "$DST/Resources/Styles/$f.sty" ]; then
    rm -f "$DST/Resources/Styles/$f.sty" && echo "rm $f.sty"
  else
    echo "skip $f.sty（不存在）"
  fi
done
echo "剩余 .sty 数：$(ls -1 "$DST/Resources/Styles"/*.sty | wc -l | tr -d ' ')（应为 43）"
echo "请在 Xcode 手动 ⇧⌘K Clean Build Folder 后 ⌘B 验证。"
