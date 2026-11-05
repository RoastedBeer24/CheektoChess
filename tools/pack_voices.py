#!/usr/bin/env python3
"""전투 보이스(OGG) → assets/voices/<사도 id>/<동작>_<n>.ogg + meta.json

  python3 tools/pack_voices.py <원본 폴더> [사도 id ...]

원본: 트릭컬 스파인 뷰어의 '파일로 저장' → OGG 로 받은 <원본>/<사도 id>/<항목>.ogg
동작과 확실히 연결된 이름만 쓴다 (BasicAttack·PowerAttack·SPSkill·Ultimate·Hit·Die·Spawn·Victory·Defeat, Special 제외).
동작마다 몇 개만 골라 저용량(모노 32kHz Vorbis)으로 다시 인코딩한다 (ffmpeg 필요).
"""
import json
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "voices")
# 동작 → 최대 개수 (게임에서 쓰는 것만)
KEEP = {"SPSkill": 3, "Ultimate": 3, "Die": 2, "Spawn": 2, "Victory": 2, "Defeat": 2, "Hit": 2, "PowerAttack": 2}
NAME_RE = re.compile(r"^(BasicAttack|PowerAttack|SPSkill|Ultimate|Hit|Die|Spawn|Victory|Defeat)(\d*)(.*)$")


def pick(files):
    """동작별로: 세트 번호가 다른 것을 먼저(다양하게), 같은 세트의 다른 녹음은 나중에"""
    by = {}
    for f in sorted(files):
        m = NAME_RE.match(os.path.splitext(f)[0])
        if not m or "Special" in f:
            continue
        by.setdefault(m.group(1), []).append((m.group(2), m.group(3), f))
    out = {}
    for cat, lst in by.items():
        if cat not in KEEP:
            continue
        seen_sets, first, rest = set(), [], []
        for s, tail, f in lst:
            (first if s not in seen_sets else rest).append(f)
            seen_sets.add(s)
        out[cat] = (first + rest)[:KEEP[cat]]
    return out


def encode(src, dst):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", src, "-ac", "1", "-ar", "32000",
                    "-c:a", "libvorbis", "-q:a", "1", dst], check=True)


def pack_one(src_dir, aid):
    files = [f for f in os.listdir(src_dir) if f.endswith(".ogg")]
    chosen = pick(files)
    out_dir = os.path.join(OUT, aid)
    os.makedirs(out_dir, exist_ok=True)
    for f in os.listdir(out_dir):
        os.remove(os.path.join(out_dir, f))
    meta = {}
    jobs = []
    for cat, lst in chosen.items():
        meta[cat] = len(lst)
        for i, f in enumerate(lst):
            jobs.append((os.path.join(src_dir, f), os.path.join(out_dir, "%s_%d.ogg" % (cat, i + 1))))
    with ThreadPoolExecutor(4) as ex:
        list(ex.map(lambda j: encode(*j), jobs))
    with open(os.path.join(out_dir, "meta.json"), "w", encoding="utf-8") as fp:
        json.dump(meta, fp)
    return sum(os.path.getsize(os.path.join(out_dir, f)) for f in os.listdir(out_dir))


def main():
    src = sys.argv[1]
    ids = sys.argv[2:] or sorted(d for d in os.listdir(src) if os.path.isdir(os.path.join(src, d)))
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, ".gdignore"), "w").close()
    total = 0
    for aid in ids:
        d = os.path.join(src, aid)
        if not os.path.isdir(d):
            continue
        b = pack_one(d, aid)
        total += b
        print("%-12s %.0f KB" % (aid, b / 1024))
    print("합계 %.1f MB" % (total / 1048576))


if __name__ == "__main__":
    main()
