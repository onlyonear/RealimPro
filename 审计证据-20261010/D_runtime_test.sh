#!/bin/bash
# RealimPro 运行时验证脚本 —— 拿到 .app 路径后执行
# 用法: ./runtime_test.sh <AppPath> <SimulatorUDID>
# 例:  ./runtime_test.sh ~/Library/Developer/Xcode/DerivedData/RealimPro-xxx/Build/Products/Debug-iphonesimulator/RealimPro.app 942E8A34-D8C7-4713-A694-80F7AE050008
set -u
APP="$1"
SIM="$2"
EVDIR="/Users/onlyonear/Desktop/Improlyze/审计证据-20261010"
SHOT="$EVDIR/D_截图"
LOG="$EVDIR/D_日志"
BID="wonderbread.realimpro"

echo "=== [1/6] 启动模拟器 ==="
xcrun simctl boot "$SIM" 2>/dev/null || true
sleep 3

echo "=== [2/6] 安装 $APP ==="
xcrun simctl install "$SIM" "$APP" || { echo "INSTALL FAILED"; exit 1; }

echo "=== [3/6] 冷启动计时 ==="
START=$(python3 -c 'import time;print(time.time())')
xcrun simctl launch "$SIM" "$BID" > "$LOG/launch_${SIM}.txt" 2>&1
END=$(python3 -c 'import time;print(time.time())')
python3 -c "print(f'冷启动耗时: {$END-$START:.2f}s')" | tee "$LOG/cold_start_${SIM}.txt"
sleep 5

echo "=== [4/6] 抓取内存峰值 ==="
PID=$(xcrun simctl spawn "$SIM" launchctl list 2>/dev/null | grep -i realimpro | awk '{print $1}' | head -1)
echo "PID=$PID"
xcrun simctl spawn "$SIM" ps -o pid,rss,comm -p "$PID" 2>/dev/null | tee "$LOG/mem_${SIM}.txt"

echo "=== [5/6] 截图 ==="
mkdir -p "$SHOT"
xcrun simctl io "$SIM" screenshot "$SHOT/01_home_${SIM}.png" 2>/dev/null
echo "截图保存到 $SHOT/01_home_${SIM}.png"

echo "=== [6/6] 崩溃日志收集 ==="
ls -la ~/Library/Logs/DiagnosticReports/ 2>/dev/null | grep -i realimpro | head -5
xcrun simctl spawn "$SIM" ls -la /Library/Logs/DiagnosticReports/ 2>/dev/null | grep -i realimpro | head -5

echo "=== 完成。后续 TC-01~TC-20 需 GUI 点击，见 findings.md ==="
