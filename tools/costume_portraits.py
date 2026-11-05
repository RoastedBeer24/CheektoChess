#!/usr/bin/env python3
"""의상 유닛·몬스터·펫 초상화: 받은 인게임 모션의 대기(Idle) 첫 프레임에서 얼굴·윗몸을 잘라 assets/portraits/<유닛 id>.webp

  python3 tools/costume_portraits.py <모션 원본 폴더> [유닛 id ...]

원래 초상화와 같은 252px 정사각형, 흰 바탕. (의상 그룹에서 같은 사도의 두 의상을 상점에서 구분하려고)
"""
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "portraits")
SIZE = 252


def make(src_dir, uid):
    d = os.path.join(src_dir, uid, "Idle")
    if not os.path.isdir(d):
        return False
    frames = sorted(f for f in os.listdir(d) if f.endswith(".png"))
    if not frames:
        return False
    im = Image.open(os.path.join(d, frames[0])).convert("RGBA")
    box = im.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox()
    if not box:
        return False
    x0, y0, x1, y1 = box
    h = y1 - y0
    cx = (x0 + x1) / 2
    if uid.startswith("m_") or uid.startswith("pet_"):
        # 몬스터·펫: 몸 전체가 들어오게
        side = int(max(x1 - x0, y1 - y0) * 1.08) + 8
        left = int(cx - side / 2)
        top = int((y0 + y1) / 2 - side / 2)
    else:
        side = int(max(140, min(300, h * 0.62)))
        left = int(cx - side / 2)
        top = int(y0 - side * 0.04)
    crop = im.crop((left, top, left + side, top + side)).resize((SIZE, SIZE), Image.LANCZOS)
    bg = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 255))
    bg.alpha_composite(crop)
    bg.convert("RGB").save(os.path.join(OUT, uid + ".webp"), "WEBP", quality=85)
    return True


def main():
    src = sys.argv[1]
    ids = sys.argv[2:] or sorted(x for x in os.listdir(src) if "__" in x or x.startswith("m_") or x.startswith("pet_"))
    n = sum(1 for uid in ids if make(src, uid))
    print("의상 초상화 %d개" % n)


if __name__ == "__main__":
    main()
