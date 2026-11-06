#!/usr/bin/env python3
"""의상 일러스트(뷰어 '사도' 탭 + 의상, '파일로 저장' PNG) → 초상화 assets/portraits/<유닛 id>.webp

  python3 tools/illust_portraits.py <일러스트 폴더> [유닛 id ...]

얼굴·윗몸이 들어오게 위쪽을 정사각형으로 잘라 252px, 흰 바탕 (원래 초상화와 같은 형식).
"""
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "portraits")
SIZE = 252


def make(src, uid):
    p = os.path.join(src, uid + ".png")
    if not os.path.exists(p):
        return False
    im = Image.open(p).convert("RGBA")
    a = im.getchannel("A").point(lambda v: 255 if v > 40 else 0)
    box = a.getbbox()
    if not box:
        return False
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    side = int(min(w * 0.95, h * 0.62))
    # 위쪽 절반의 몸통 무게 중심으로 가로 위치 (꼬리·소품에 끌려가지 않게)
    top = a.crop((x0, y0, x1, y0 + int(h * 0.5)))
    px = top.load()
    sx = n = 0
    for yy in range(0, top.height, 2):
        for xx in range(0, top.width, 2):
            if px[xx, yy]:
                sx += xx
                n += 1
    cx = x0 + (sx / n if n else w / 2)
    left = int(cx - side / 2)
    ty = int(y0 + h * 0.06)
    crop = im.crop((left, ty, left + side, ty + side)).resize((SIZE, SIZE), Image.LANCZOS)
    bg = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 255))
    bg.alpha_composite(crop)
    bg.convert("RGB").save(os.path.join(OUT, uid + ".webp"), "WEBP", quality=88)
    return True


def main():
    src = sys.argv[1]
    ids = sys.argv[2:] or sorted(f[:-4] for f in os.listdir(src) if f.endswith(".png"))
    print("일러스트 초상화 %d개" % sum(1 for u in ids if make(src, u)))


if __name__ == "__main__":
    main()
