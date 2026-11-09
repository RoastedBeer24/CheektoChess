#!/usr/bin/env python3
"""모션 시트 잘림 검사: 프레임마다 칸 가장자리에 그림이 닿는지 센다 (닿으면 원본이 잘렸을 가능성).

  python3 tools/motion_edge_check.py [모션 폴더=assets/motions] [--top N]
가장자리에 닿은 프레임이 있는 모델 수와, 비율이 높은 모델 목록을 출력한다.
"""
import json
import os
import sys

from PIL import Image


def check(root, aid, thr=40):
    meta = json.load(open(os.path.join(root, aid, "meta.json")))
    S = int(meta["size"])
    tot = bad = 0
    raw = int(meta.get("raw_edge", 0))   # 원본에서 이미 잘린 프레임 (묶을 때 기록)
    for an, inf in meta["anims"].items():
        p = os.path.join(root, aid, an + ".webp")
        if not os.path.exists(p):
            continue
        a = Image.open(p).getchannel("A")
        cols = int(inf["cols"])
        for i in range(int(inf["n"])):
            x, y = (i % cols) * S, (i // cols) * S
            c = a.crop((x, y, x + S, y + S))
            edges = [c.crop((0, 0, 1, S)), c.crop((S - 1, 0, S, S)), c.crop((0, 0, S, 1)), c.crop((0, S - 1, S, S))]
            tot += 1
            if any(e.getextrema()[1] > thr for e in edges):
                bad += 1
    return max(bad, raw), tot


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    root = args[0] if args else "assets/motions"
    top = 20
    if "--top" in sys.argv:
        top = int(sys.argv[sys.argv.index("--top") + 1])
    res = []
    for aid in sorted(os.listdir(root)):
        if os.path.exists(os.path.join(root, aid, "meta.json")):
            b, t = check(root, aid)
            res.append((b / max(1, t), aid, b, t))
    res.sort(reverse=True)
    hit = [r for r in res if r[2] > 0]
    print("모델 %d개 중 가장자리에 닿은 프레임이 있는 모델 %d개 (10%% 이상 %d개)" % (len(res), len(hit), sum(1 for r in res if r[0] >= 0.1)))
    for r in res[:top]:
        if r[2]:
            print("  %5.1f%%  %-24s %d/%d" % (100 * r[0], r[1], r[2], r[3]))


if __name__ == "__main__":
    main()
