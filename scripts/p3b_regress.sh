#!/bin/bash
# P3-b 落地回归：用【生产】StyleEngine（含 H1/H2）+ 终版口径 main.swift 重跑风格。
# P3-b.1 下架 3 风格（shuffle-light / rock-triplet / rock-triplet-2）后，期望：CLEAN=43 / WARN=0 / CRASH=0 / MISSING=0。
set -u
PROJ="/Users/onlyonear/Desktop/Improlyze"
STYDIR="/Users/onlyonear/Desktop/Impro-Visor-master/styles"
WORK="/tmp/stybatch"
BIN="$WORK/probe_p3b"

echo "== 编译【生产引擎】（含 P3-b H1/H2）=="
cd "$PROJ" || exit 9
swiftc \
  "Real imPro/MidiPlayer/StyleEngine/"*.swift \
  "Real imPro/MidiPlayer/AccompanimentModels.swift" \
  "Real imPro/MidiPlayer/Pattern.swift" \
  "Real imPro/MidiPlayer/DrumPattern.swift" "Real imPro/MidiPlayer/DrumPatternExtractor.swift" \
  "Real imPro/MidiPlayer/ChordPattern.swift" "Real imPro/MidiPlayer/ChordPatternExtractor.swift" \
  "Real imPro/FullVoicing/"*.swift \
  "$WORK/main.swift" -o "$BIN" 2> "$WORK/build_p3b.log"
if [ ! -x "$BIN" ]; then
  echo "COMPILE FAIL"; grep -E "error:" "$WORK/build_p3b.log" | head -40; exit 9
fi
echo "编译成功"; echo

ITEMS=(
  "Swing|swing" "Swing|swing-backbeat" "Swing|swing-square-comp" "Swing|swing-substitute"
  "Swing|swing-BarryHarris" "Swing|swing-BobbyTimmons" "Swing|swing-BudPowell"
  "Swing|swing-HoraceSilver" "Swing|swing-RedGarland" "Swing|swing-SonnyClark" "Swing|swing-TadDameron"
  # P3-b.1 下架 shuffle-light，旧码封存："Shuffle|shuffle" "Shuffle|shuffle-cloppety" "Shuffle|shuffle-light"
  "Shuffle|shuffle" "Shuffle|shuffle-cloppety"
  "Shuffle|boogie-shuffle-1" "Shuffle|boogie-shuffle-2"
  "Rock|rock-50s" "Rock|rock-6-8" "Rock|rock-brushes" "Rock|rock-calypso" "Rock|rock-heavy-even"
  "Rock|rock-light" "Rock|rock-light-even" "Rock|rock-medium" "Rock|rock-medium-even"
  # P3-b.1 下架两个 Triplet Rock，旧码封存："Rock|rock-slow" "Rock|rock-triplet" "Rock|rock-triplet-2" "Rock|folk-rock"
  "Rock|rock-slow" "Rock|folk-rock"
  "Latin|latin" "Latin|latin-enhanced" "Latin|latin-fast" "Latin|latin-new" "Latin|latin-plain"
  "Latin|latin-with-guiro" "Latin|latin-2-3-son-clave" "Latin|latin-3-2-son-clave"
  "Latin|latin-pedal-bass-1" "Latin|latin-pedal-bass-2"
  "Funk|funk" "Funk|funk-disco"
  "Blues|pop-blues" "Blues|senor-blues" "Blues|blues-clair"
  "TwoBeat|two-beat" "Tango|tango"
)
CLEAN=0; WARN=0; CRASH=0; MISS=0
: > "$WORK/results_p3b.txt"; : > "$WORK/warnings_p3b.txt"
for it in "${ITEMS[@]}"; do
  cat="${it%%|*}"; f="${it##*|}"; file="$STYDIR/$f.sty"
  if [ ! -f "$file" ]; then echo "MISSING  [$cat] $f" | tee -a "$WORK/results_p3b.txt"; MISS=$((MISS+1)); continue; fi
  out=$(perl -e 'alarm shift; exec @ARGV' 30 "$BIN" "$file" 2>&1); code=$?
  if [ $code -eq 0 ]; then echo "CLEAN    [$cat] ${out#OK }" >> "$WORK/results_p3b.txt"; CLEAN=$((CLEAN+1))
  elif [ $code -eq 1 ]; then echo "WARN     [$cat] ${out#OK }" >> "$WORK/results_p3b.txt"; echo "[$cat] ${out#OK }" >> "$WORK/warnings_p3b.txt"; WARN=$((WARN+1))
  elif [ $code -eq 2 ] || [ $code -eq 3 ]; then echo "PARSEFAIL[$cat] $out" | tee -a "$WORK/results_p3b.txt"; CRASH=$((CRASH+1))
  else echo "CRASH($code)[$cat] $f :: $out" | tee -a "$WORK/results_p3b.txt"; echo "[$cat] $f $out" >> "$WORK/warnings_p3b.txt"; CRASH=$((CRASH+1)); fi
done
echo "================ P3-b 生产引擎回归汇总 ================"
echo "CLEAN=$CLEAN  WARN=$WARN  CRASH/PARSEFAIL=$CRASH  MISSING=$MISS  总计=${#ITEMS[@]}"
[ -s "$WORK/warnings_p3b.txt" ] && { echo "---- 告警 ----"; cat "$WORK/warnings_p3b.txt"; }
echo "---- 8 位大师 Swing 鼓（期望 d 非空 end7680）----"
grep -E "swing-(BarryHarris|BobbyTimmons|BudPowell|HoraceSilver|RedGarland|SonnyClark|TadDameron|substitute)" "$WORK/results_p3b.txt"
echo "---- swing 本体 / backbeat / square（扁平不回归）----"
grep -E "CLEAN    \[Swing\] swing \||swing-backbeat|swing-square-comp" "$WORK/results_p3b.txt"
