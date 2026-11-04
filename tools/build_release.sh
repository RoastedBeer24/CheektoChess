#!/usr/bin/env bash
# 릴리스 빌드: 업데이트 묶음 + (선택) APK / PC 실행 파일
#   tools/build_release.sh <빌드 번호> [android|linux|windows|packs]...
# APK 서명: 환경 변수 GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD="${1:?빌드 번호를 주세요}"
shift || true
TARGETS=("$@")
[ ${#TARGETS[@]} -eq 0 ] && TARGETS=(packs)
GODOT="${GODOT:-godot}"

"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . -s res://tools/build_packs.gd -- build/packs "$BUILD"
# APK/실행 파일 안에 넣을 기본 묶음
mkdir -p packs
cp build/packs/core.pck build/packs/art.pck packs/
python3 -c "import json;m=json.load(open('build/packs/manifest.json'));m['packs']={k:v for k,v in m['packs'].items() if k in ('core','art')};json.dump(m,open('packs/index.json','w'),ensure_ascii=False)"

for t in "${TARGETS[@]}"; do
  case "$t" in
    packs) ;;
    android) mkdir -p build && "$GODOT" --headless --path . --export-release "Android" build/CheektoChess.apk ;;
    linux) mkdir -p build/linux && "$GODOT" --headless --path . --export-release "Linux" build/linux/CheektoChess.x86_64 ;;
    windows) mkdir -p build/windows && "$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/CheektoChess.exe ;;
    *) echo "알 수 없는 대상: $t"; exit 1 ;;
  esac
done
ls -la build/packs build/*.apk 2>/dev/null || true
