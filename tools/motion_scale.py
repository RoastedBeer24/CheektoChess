#!/usr/bin/env python3
"""사도 모션 크기 맞추기 → data/motion_scale.json  {사도 id: 배율}

  python3 tools/motion_scale.py

assets/motions/<id>/Idle.webp 첫 프레임에서 '몸 높이'(가로로 충분히 넓은 줄만 — 지팡이·무기·이펙트 끝은 제외)를 재서
기준 키에 맞춘다. 원작의 자연스러운 키 차이는 조금(±) 남기고, 너무 작거나 큰 모델만 맞춘다.
덩치가 큰 비인간형(나무 골렘·벌 등)은 OVERRIDE 로 직접 줄인다.
게임 데이터(core 묶음)라서 모션 묶음을 다시 받지 않아도 바뀐다.
"""
import json
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(ROOT, "assets", "motions")
OUT = os.path.join(ROOT, "data", "motion_scale.json")
TARGET_MIN, TARGET_MAX = 134, 150     # 192px 칸 기준 몸 높이 허용 범위
OVERRIDE = {"bigwood": 0.84, "jubee": 0.82}


def body_h(path, cell):
    im = Image.open(path).convert("RGBA").crop((0, 0, cell, cell))
    a = im.getchannel("A").load()
    rows = [sum(1 for x in range(cell) if a[x, y] > 40) for y in range(cell)]
    mx = max(rows) or 1
    body = [y for y, r in enumerate(rows) if r >= 0.22 * mx]
    return (body[-1] - body[0]) if body else 0


def main():
    out = {}
    for aid in sorted(os.listdir(D)):
        p = os.path.join(D, aid, "Idle.webp")
        if aid.startswith("m_") or aid.startswith("pet_") or not os.path.exists(p):   # 몬스터·펫은 monsters.json 의 size 로
            continue
        cell = json.load(open(os.path.join(D, aid, "meta.json"))).get("size", 192)
        h = body_h(p, cell)
        s = 1.0
        if h and h < TARGET_MIN:
            s = TARGET_MIN / h
        elif h > TARGET_MAX:
            s = TARGET_MAX / h
        s *= OVERRIDE.get(aid, 1.0)
        if abs(s - 1.0) >= 0.02:
            out[aid] = round(s, 3)
        print("%-12s 몸 %3d → x%.2f" % (aid, h, s))
    json.dump(out, open(OUT, "w"), ensure_ascii=False, indent=1, sort_keys=True)
    print("%d명 보정" % len(out))


if __name__ == "__main__":
    main()
