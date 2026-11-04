#!/usr/bin/env python3
"""전투 모션 프레임(PNG) → 사도별 애니메이션 시트(webp) + meta.json

  python3 tools/pack_motions.py <원본 폴더> [사도 id ...]

원본 폴더 구조 (트릭컬 스파인 뷰어의 '파일로 저장' → GIF · ZIP · 전체 프레임 PNG 로 받은 것):
  <원본>/<사도 id>/info.json            {"fps": 8, ...}
  <원본>/<사도 id>/<Anim>/frame_000001.png ...   (512x512, 발 위치 y≈461, 왼쪽을 봄)

결과: assets/motions/<사도 id>/<Anim>.webp (가로로 프레임을 늘어놓은 시트) + meta.json
  meta.json = {"size": 칸 크기, "fps": 재생 fps, "facing": "left", "feet": 발 위치(0~1),
               "anims": {"Idle": {"n": 프레임 수, "cols": 시트 열 수}, ...}}
게임은 이 파일들을 그대로(가져오기 없이) 읽는다 (assets/motions/.gdignore).
"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "motions")
ANIMS = ["Idle", "Move", "Attack1_1", "Skill1_1", "Ultimate1_1", "Die", "Groggy"]
SIZE = 192          # 512 칸 → 192 칸 (기준점 유지)
TARGET_FPS = 8.0
QUALITY = 78
MAX_COLS = 12
FEET = 461 / 512


def pack_one(src_dir: str, aid: str) -> int:
    info_path = os.path.join(src_dir, "info.json")
    info = json.load(open(info_path, encoding="utf-8")) if os.path.exists(info_path) else {}
    fps = float(info.get("fps", 15))
    step = max(1, round(fps / TARGET_FPS))
    out_dir = os.path.join(OUT, aid)
    os.makedirs(out_dir, exist_ok=True)
    meta = {"size": SIZE, "fps": round(fps / step, 3), "facing": "left", "feet": round(FEET, 4), "anims": {}}
    total = 0
    for anim in ANIMS:
        d = os.path.join(src_dir, anim)
        if not os.path.isdir(d):
            continue
        frames = sorted(f for f in os.listdir(d) if f.endswith(".png"))[::step]
        if not frames:
            continue
        cols = min(len(frames), MAX_COLS)
        rows = (len(frames) + cols - 1) // cols
        sheet = Image.new("RGBA", (cols * SIZE, rows * SIZE), (0, 0, 0, 0))
        for i, f in enumerate(frames):
            im = Image.open(os.path.join(d, f)).convert("RGBA")
            if im.size != (512, 512):
                im = im.resize((512, 512), Image.LANCZOS)
            im = im.resize((SIZE, SIZE), Image.LANCZOS)
            sheet.paste(im, ((i % cols) * SIZE, (i // cols) * SIZE))
        path = os.path.join(out_dir, anim + ".webp")
        sheet.save(path, "WEBP", quality=QUALITY, method=6)
        meta["anims"][anim] = {"n": len(frames), "cols": cols}
        total += os.path.getsize(path)
    with open(os.path.join(out_dir, "meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False)
    return total


def main():
    src = sys.argv[1]
    ids = sys.argv[2:] or sorted(d for d in os.listdir(src) if os.path.isdir(os.path.join(src, d)))
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, ".gdignore"), "w").close()
    grand = 0
    for aid in ids:
        d = os.path.join(src, aid)
        if not os.path.isdir(d):
            print("없음:", aid)
            continue
        b = pack_one(d, aid)
        grand += b
        print("%-12s %.2f MB" % (aid, b / 1048576))
    print("합계 %.1f MB" % (grand / 1048576))


if __name__ == "__main__":
    main()
