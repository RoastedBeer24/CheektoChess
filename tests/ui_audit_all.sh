#!/bin/bash
# 여러 화면 크기에서 ui_audit 를 돌린다. 하나라도 문제가 있으면 끝에 실패로 표시.
#   bash tests/ui_audit_all.sh [캡처 폴더]
cd "$(dirname "$0")/.."
total=0
for cfg in "2220x1080 1.35" "2220x1080 1.3" "2340x1080 1.35" "2340x1080 1.3" "2400x1080 1.35" "1920x1080 1.0" "1366x768 1.0"; do
  set -- $cfg
  res=$1; sc=$2; w=${res%x*}; h=${res#*x}
  out=""
  [ -n "$AUDIT_SHOTS" ] && out="$AUDIT_SHOTS/${res}_$sc"
  line=$(CHEEKTO_UI_SCALE=$sc timeout 300 xvfb-run -a -s "-screen 0 ${w}x${h}x24" godot --path . --rendering-driver opengl3 --resolution $res res://tests/ui_audit.tscn ${out:+-- $out} 2>&1 | grep -E "^AUDIT|UI AUDIT DONE")
  n=$(echo "$line" | grep -o "fails=[0-9]*" | cut -d= -f2)
  echo "== $res x$sc : ${n:-오류}"
  echo "$line" | grep "^AUDIT" | head -8
  total=$((total + ${n:-1}))
done
echo "ALL AUDIT DONE total=$total"
