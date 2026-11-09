#!/usr/bin/env python3
"""전투 모션 프레임(PNG) → 사도별 애니메이션 시트(webp) + meta.json

  python3 tools/pack_motions.py <원본 폴더> [사도 id ...]

원본 폴더 구조 (트릭컬 스파인 뷰어의 '파일로 저장' → GIF · ZIP · 전체 프레임 PNG 로 받은 것):
  <원본>/<사도 id>/info.json            {"fps": 8, ...}
  <원본>/<사도 id>/<Anim>/frame_000001.png ...   (512x512, 발 위치 y≈461, 왼쪽을 봄)

넓게 받은 원본 (뷰어 카메라를 키우고 축소해서 받은 것, 512보다 큰 정사각형): 환경 변수 RAW_G 에
  "512 원본 1px 당 받은 원본 px" 배율을 준다 (예: 카메라 1024 + 휠 6칸 ≈ 1.04). 화면 가운데가 같은 점.
  사도마다 모든 프레임이 들어가는 칸 넓이(span, 512 기준 배수)를 정해 잘리지 않게 담는다.

결과: assets/motions/<사도 id>/<Anim>.webp (가로로 프레임을 늘어놓은 시트) + meta.json
  meta.json = {"size": 칸 크기, "fps": 재생 fps, "facing": "left", "feet": 발 위치(0~1), "span": 칸이 덮는 넓이(512 기준 배수, 없으면 1),
               "anims": {"Idle": {"n": 프레임 수, "cols": 시트 열 수}, ...}}
게임은 이 파일들을 그대로(가져오기 없이) 읽는다 (assets/motions/.gdignore).
"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.environ.get("MOTION_OUT") or os.path.join(ROOT, "assets", "motions")
ANIMS = ["Idle", "Move", "Attack1_1", "Skill1_1", "Ultimate1_1", "Die", "Groggy", "Victory"]
SIZE = 192          # 512 칸 → 192 칸 (기준점 유지)
TARGET_FPS = 15.0
QUALITY = 78
MAX_COLS = 12
MAX_FRAMES = 72      # 동작 하나 최대 프레임 — 더 길면 프레임을 솎아 끝까지 재생 (동작별 fps)
FEET = 461 / 512
STD_FEET = 461        # 512 원본에서 발 위치
STD_CX = 256          # 512 원본에서 가운데
STD_H = 360           # 대기 모습 기준 키 (원본 px)
MIN_H, MAX_H = 0.8, 1.15   # 기준 키의 이 비율 밖이면 크기를 맞춤 (너무 작거나 큰 모델)
RAW_G = float(os.environ.get("RAW_G", "0") or 0)   # 넓게 받은 원본의 배율 (0 = 512 그대로)
MAX_CELL = 320        # 칸이 아주 넓은 사도도 시트가 너무 커지지 않게 (넘으면 조금 흐려짐)
PAD = 6               # 칸 가장자리 여백 (512 기준 px)


def raw_g(w):
    """받은 원본 px / 512 기준 px"""
    return RAW_G if RAW_G > 0 else w / 512.0


def to_virtual_box(box, w):
    """원본 좌표 상자 → 512 기준 좌표 상자 (화면 가운데가 같은 점)"""
    g = raw_g(w)
    x0, y0, x1, y1 = box
    return (256 + (x0 - w / 2) / g, 256 + (y0 - w / 2) / g, 256 + (x1 - w / 2) / g, 256 + (y1 - w / 2) / g)


def idle_box(src_dir):
    """대기 첫 프레임에서 사도 모습의 범위 (x0, y0, x1, y1)"""
    d = os.path.join(src_dir, "Idle")
    frames = sorted(f for f in os.listdir(d) if f.endswith(".png"))
    im = Image.open(os.path.join(d, frames[0])).convert("RGBA")
    b = im.getchannel("A").point(lambda a: 255 if a > 16 else 0).getbbox()
    return to_virtual_box(b, im.size[0]) if b else None


def normalizer(src_dir):
    """사도마다 위치·크기를 맞추는 변환 (배율, x 이동, y 이동) — 원본 512 기준"""
    box = idle_box(src_dir)
    if not box:
        return 1.0, 0.0, 0.0
    x0, y0, x1, y1 = box
    h = max(1, y1 - y0)
    s = 1.0
    if h < STD_H * MIN_H:
        s = min(2.0, STD_H * MIN_H / h)
    elif h > STD_H * MAX_H:
        s = STD_H * MAX_H / h
    cx = (x0 + x1) / 2
    return s, STD_CX - cx * s, STD_FEET - y1 * s


def transform(im, norm):
    s, dx, dy = norm
    if abs(s - 1.0) < 0.01 and abs(dx) < 2 and abs(dy) < 2:
        return im
    w = round(512 * s)
    scaled = im.resize((w, w), Image.LANCZOS) if abs(s - 1.0) >= 0.01 else im
    out = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    out.paste(scaled, (round(dx), round(dy)), scaled)
    return out


def _frames_of(src_dir, step):
    out = []
    extra = sorted(x for x in os.listdir(src_dir) if os.path.isdir(os.path.join(src_dir, x)) and x not in ANIMS)
    for anim in ANIMS + extra:   # 몬스터·펫은 Play·Eat 같은 다른 동작도
        d = os.path.join(src_dir, anim)
        if not os.path.isdir(d):
            continue
        frames = sorted(f for f in os.listdir(d) if f.endswith(".png"))[::step]
        if frames:
            out.append((anim, d, frames))
    return out


def pack_one(src_dir: str, aid: str) -> int:
    """src_dir 의 프레임 → assets/motions/<aid>/ (MOTION_OUT 환경 변수로 다른 곳에)"""
    info_path = os.path.join(src_dir, "info.json")
    info = json.load(open(info_path, encoding="utf-8")) if os.path.exists(info_path) else {}
    fps = float(info.get("fps", 15))
    step = max(1, round(fps / TARGET_FPS))
    out_dir = os.path.join(OUT, aid)
    os.makedirs(out_dir, exist_ok=True)
    s, dx, dy = normalizer(src_dir)
    groups = []
    for anim, d, frames in _frames_of(src_dir, step):
        afps = fps / step
        if len(frames) > MAX_FRAMES:
            k = len(frames) / MAX_FRAMES          # 고르게 솎아 길이(초)는 그대로
            frames = [frames[int(i * k)] for i in range(MAX_FRAMES)]
            afps = afps / k
        groups.append((anim, d, frames, afps))
    # 1) 모든 프레임이 들어가는 범위 (512 기준, 크기 보정 후) → 칸 넓이·발 위치
    left = right = top = bottom = 0.0
    raw_edge = 0     # 받은 원본 자체가 가장자리에 닿은(잘렸을) 프레임 수
    for anim, d, frames, afps in groups:
        for f in frames:
            im = Image.open(os.path.join(d, f))
            b = im.getchannel("A").point(lambda a: 255 if a > 16 else 0).getbbox()
            if not b:
                continue
            if b[0] <= 0 or b[1] <= 0 or b[2] >= im.size[0] or b[3] >= im.size[1]:
                raw_edge += 1
            x0, y0, x1, y1 = to_virtual_box(b, im.size[0])
            x0, x1 = x0 * s + dx, x1 * s + dx
            y0, y1 = y0 * s + dy, y1 * s + dy
            left = max(left, STD_CX - x0)
            right = max(right, x1 - STD_CX)
            top = max(top, STD_FEET - y0)
            bottom = max(bottom, y1 - STD_FEET)
    half = max(left, right) + PAD
    need_v = top + bottom + 2 * PAD
    span = max(512.0, 2 * half, need_v)
    if span <= 512.0 and top + PAD <= STD_FEET and bottom + PAD <= 512 - STD_FEET:
        feet = STD_FEET / 512.0
    else:
        slack = span - need_v
        feet = (top + PAD + slack / 2.0) / span
    cell = min(MAX_CELL, int(round(SIZE * span / 512.0)))
    c = cell / span                         # 칸 px / 512 기준 px
    ox, oy = STD_CX - span / 2.0, STD_FEET - feet * span   # 칸 왼쪽 위 (512 기준)
    meta = {"size": cell, "fps": round(fps / step, 3), "facing": "left", "feet": round(feet, 4), "anims": {},
            "norm": [round(s, 3), round(dx, 1), round(dy, 1)]}
    if span > 512.5:
        meta["span"] = round(span / 512.0, 4)
    meta["raw_edge"] = raw_edge
    total = 0
    for anim, d, frames, afps in groups:
        cols = min(len(frames), MAX_COLS)
        rows = (len(frames) + cols - 1) // cols
        sheet = Image.new("RGBA", (cols * cell, rows * cell), (0, 0, 0, 0))
        for i, f in enumerate(frames):
            im = Image.open(os.path.join(d, f)).convert("RGBA")
            w = im.size[0]
            g = raw_g(w)
            a = s * c / g                       # 원본 px → 칸 px
            off_x = c * (s * (256 - w / (2 * g)) + dx - ox)
            off_y = c * (s * (256 - w / (2 * g)) + dy - oy)
            sw = max(1, round(w * a))
            im = im.resize((sw, sw), Image.LANCZOS)
            frame = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
            frame.paste(im, (round(off_x), round(off_y)), im)
            sheet.paste(frame, ((i % cols) * cell, (i // cols) * cell))
        path = os.path.join(out_dir, anim + ".webp")
        sheet.save(path, "WEBP", quality=QUALITY, method=6)
        meta["anims"][anim] = {"n": len(frames), "cols": cols}
        if abs(afps - fps / step) > 0.01:
            meta["anims"][anim]["fps"] = round(afps, 3)
        total += os.path.getsize(path)
    with open(os.path.join(out_dir, "meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False)
    return total


def main():
    src = sys.argv[1]
    ids = sys.argv[2:] or sorted(d for d in os.listdir(src) if os.path.isdir(os.path.join(src, d)))
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, ".gdignore"), "w").close()
    from multiprocessing import Pool
    jobs = [(os.path.join(src, aid), aid) for aid in ids if os.path.isdir(os.path.join(src, aid))]
    with Pool(max(1, (os.cpu_count() or 2))) as pool:
        sizes = pool.starmap(pack_one, jobs)
    for (d, aid), b in zip(jobs, sizes):
        print("%-12s %.2f MB" % (aid, b / 1048576))
    print("합계 %.1f MB (%d명)" % (sum(sizes) / 1048576, len(sizes)))


if __name__ == "__main__":
    main()
