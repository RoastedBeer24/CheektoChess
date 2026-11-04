#!/usr/bin/env python3
"""data/roster.json 을 사도 전원으로 만든다 (코스트 1~5 자동 배정).

사용법: python3 tools/build_roster.py
- 이미 roster.json 에 있는 사도의 코스트는 그대로 둔다.
- 나머지는 간단한 점수(엘다인, 이격 사도, 원작 등급 등)로 정렬해 코스트별 목표 인원에 맞춰 배정한다.
- 코스트는 임시값이다. roster.json 에서 직접 고쳐도 된다.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_apostles import slug  # noqa: E402

# 코스트별 목표 비율 (1코스트가 가장 많고 5코스트가 가장 적게)
RATIO = [0.23, 0.23, 0.21, 0.19, 0.14]


def main():
    apostles = json.load(open(os.path.join(ROOT, "data", "apostles.json"), encoding="utf-8"))
    raw = {slug(c["name"].strip()): c for c in json.load(open(os.path.join(ROOT, "data", "raw", "lootandwaifus_characters.json"), encoding="utf-8"))}
    path = os.path.join(ROOT, "data", "roster.json")
    old = {e["id"]: e["cost"] for e in json.load(open(path, encoding="utf-8"))["pool"]}

    n = len(apostles)
    target = [round(n * r) for r in RATIO]
    target[0] += n - sum(target)
    for c in old.values():
        target[c - 1] -= 1

    def score(aid):
        a = apostles[aid]
        s = 0.0
        if a.get("eldyne"):
            s += 3
        if "(" in a["name"]:
            s += 1.5
        if a.get("personality") in ("공명", "이면"):
            s += 3
        s += {"SSR": 1.0, "SR": 0.0, "R": -1.0}.get(raw.get(aid, {}).get("rarity", "SSR"), 0)
        if "3" in a.get("aside", {}):
            s += 0.5
        if a.get("role") == "dealer":
            s += 0.3
        return s

    rest = sorted([aid for aid in apostles if aid not in old], key=lambda a: (score(a), a))
    costs = dict(old)
    i = 0
    for c in range(1, 6):
        for _ in range(max(0, target[c - 1])):
            if i < len(rest):
                costs[rest[i]] = c
                i += 1
    for aid in rest[i:]:
        costs[aid] = 5

    pool = [{"id": aid, "cost": costs[aid]} for aid in sorted(costs, key=lambda a: (costs[a], apostles[a]["name"]))]
    data = {
        "_note": "상점에 나오는 사도 목록(전원). cost 는 상점 코스트(1~5, 임시값). tools/build_roster.py 로 자동 배정했으며 직접 고쳐도 된다.",
        "pool": pool,
    }
    with open(path, "w", encoding="utf-8") as f:
        f.write('{\n "_note": %s,\n "pool": [\n' % json.dumps(data["_note"], ensure_ascii=False))
        f.write(",\n".join('  {"id":"%s","cost":%d}' % (e["id"], e["cost"]) for e in pool))
        f.write("\n ]\n}\n")
    from collections import Counter
    print(len(pool), "명", sorted(Counter(costs.values()).items()))


if __name__ == "__main__":
    main()
