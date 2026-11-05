#!/usr/bin/env python3
"""앱 아이콘 만들기 (안드로이드 적응형 아이콘 + Windows .ico + 기본 아이콘)

  python3 tools/make_icons.py

원본: tools/icon_src/erpin_idle.png (에르핀 대기 모션 첫 프레임, 512x512 투명 배경)
결과:
  assets/icon.png            512  둥근 사각형 완성 아이콘 (Godot 프로젝트·창 아이콘, 안드로이드 옛 기기용)
  assets/icon_fg.png         432  안드로이드 적응형 앞 그림 (캐릭터, 가운데 안전 영역 264px 안에 얼굴)
  assets/icon_bg.png         432  안드로이드 적응형 배경 (남색 + 금색 체스판)
  assets/icon_mono.png       432  안드로이드 13 테마 아이콘 (흰 실루엣)
  assets/icon.ico            16~256  Windows (16·24·32 는 얼굴만 크게)
"""
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "icon_src", "erpin_idle.png")
OUT = os.path.join(ROOT, "assets")
SS = 4  # 도형 그릴 때 확대 배율 (매끈한 가장자리)

NAVY_TOP = (38, 52, 96)
NAVY_BOT = (14, 19, 38)
GOLD = (255, 196, 84)

# 원본(512)에서 쓸 부분: 지팡이 보석·왕관·얼굴·윗몸
CROP_FULL = (92, 44, 392, 344)    # 300x300
CROP_FACE = (160, 96, 336, 272)   # 176x176 (작은 아이콘용)


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def background(n: int) -> Image.Image:
    """남색 세로 그라데이션 + 가운데 빛 + 옅은 금색 체스판"""
    img = Image.new("RGBA", (n, n))
    px = img.load()
    for y in range(n):
        for x in range(n):
            t = y / (n - 1)
            c = lerp(NAVY_TOP, NAVY_BOT, t)
            d = math.hypot(x - n * 0.5, y - n * 0.42) / (n * 0.55)
            glow = max(0.0, 1.0 - d) ** 2 * 0.55
            c = lerp(c, (92, 110, 170), glow)
            px[x, y] = c + (255,)
    # 체스판: 아래쪽일수록 진하게
    board = Image.new("RGBA", (n * SS, n * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(board)
    cells = 8
    cs = n * SS / cells
    for j in range(cells):
        for i in range(cells):
            if (i + j) % 2 == 0:
                a = int(14 + 34 * (j / (cells - 1)) ** 1.5)
                d.rectangle((i * cs, j * cs, (i + 1) * cs, (j + 1) * cs), fill=GOLD + (a,))
    board = board.resize((n, n), Image.LANCZOS)
    img.alpha_composite(board)
    return img


def character(crop, n: int, pad: float = 0.0) -> Image.Image:
    """원본에서 crop 부분을 n 크기로 (pad: 테두리 여백 비율)"""
    src = Image.open(SRC).convert("RGBA")
    part = src.crop(crop)
    inner = round(n * (1 - 2 * pad))
    part = part.resize((inner, inner), Image.LANCZOS)
    out = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    out.alpha_composite(part, (round(n * pad), round(n * pad)))
    return out


def outline(img: Image.Image, width: int, color) -> Image.Image:
    """캐릭터 뒤에 테두리(작은 크기에서도 배경과 구분)"""
    a = img.getchannel("A").filter(ImageFilter.MaxFilter(width * 2 + 1))
    a = a.filter(ImageFilter.GaussianBlur(width * 0.4))
    o = Image.new("RGBA", img.size, color + (0,))
    o.putalpha(a)
    o.alpha_composite(img)
    return o


def rounded_mask(n: int, r: float) -> Image.Image:
    m = Image.new("L", (n * SS, n * SS), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, n * SS - 1, n * SS - 1), radius=r * n * SS, fill=255)
    return m.resize((n, n), Image.LANCZOS)


def framed(n: int, crop, border: float, radius: float = 0.22) -> Image.Image:
    """둥근 사각형 완성 아이콘: 배경 + 캐릭터 + 금색 테두리"""
    img = background(n)
    ch = outline(character(crop, n), max(1, round(n / 128)), (10, 14, 30))
    img.alpha_composite(ch)
    # 금색 테두리
    if border > 0:
        ring = Image.new("RGBA", (n * SS, n * SS), (0, 0, 0, 0))
        d = ImageDraw.Draw(ring)
        w = border * n * SS
        d.rounded_rectangle((0, 0, n * SS - 1, n * SS - 1), radius=radius * n * SS,
                            outline=GOLD + (255,), width=round(w))
        img.alpha_composite(ring.resize((n, n), Image.LANCZOS))
    img.putalpha(ImageChops.multiply(img.getchannel("A"), rounded_mask(n, radius)))
    return img


def main():
    # 안드로이드 적응형 (108dp = 432px, 보이는 영역 72dp = 288px, 항상 보이는 원 66dp = 264px)
    bg = background(432)
    bg.save(os.path.join(OUT, "icon_bg.png"))
    fg = outline(character(CROP_FULL, 432, pad=0.19), 3, (10, 14, 30))
    fg.save(os.path.join(OUT, "icon_fg.png"))
    # 테마 아이콘: 실루엣이 아니라 선(어두운 윤곽선)만 — 알아볼 수 있는 그림으로
    ch = character(CROP_FULL, 432, pad=0.19)
    lum = ch.convert("L")
    alpha = ch.getchannel("A")
    lines = ImageChops.multiply(lum.point(lambda v: 255 if v < 120 else 0), alpha.point(lambda a: 255 if a > 128 else 0))
    lines = lines.filter(ImageFilter.MaxFilter(3))
    mono = Image.new("RGBA", fg.size, (255, 255, 255, 0))
    mono.putalpha(lines)
    mono.save(os.path.join(OUT, "icon_mono.png"))

    # 완성 아이콘 (프로젝트·창·안드로이드 옛 기기)
    framed(512, CROP_FULL, 0.035).save(os.path.join(OUT, "icon.png"))

    # Windows .ico: 큰 크기는 전체, 작은 크기는 얼굴
    sizes = [256, 128, 64, 48, 32, 24, 16]
    imgs = []
    for s in sizes:
        big = 512
        im = framed(big, CROP_FULL if s >= 48 else CROP_FACE, 0.035 if s >= 48 else 0.06,
                    radius=0.22 if s >= 48 else 0.18)
        im = im.resize((s, s), Image.LANCZOS)
        if s <= 32:
            im = im.filter(ImageFilter.UnsharpMask(radius=0.6, percent=60, threshold=1))
        imgs.append(im)
    imgs[0].save(os.path.join(OUT, "icon.ico"), format="ICO", sizes=[(s, s) for s in sizes],
                 append_images=imgs[1:])
    print("아이콘 생성 완료")


if __name__ == "__main__":
    main()
