#!/usr/bin/env python3
"""받은 펫 모션(info.json) → data/pets.json  (펫 고르기 목록)

  python3 tools/make_pet_data.py <몬스터·펫 원본 폴더>

모션이 실제로 묶여 들어간(assets/motions/pet_*/meta.json 이 있는) 펫만 넣는다.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    src = sys.argv[1]
    out = []
    for d in sorted(os.listdir(src)):
        if not d.startswith("pet_"):
            continue
        info_p = os.path.join(src, d, "info.json")
        if not os.path.exists(info_p) or not os.path.exists(os.path.join(ROOT, "assets", "motions", d, "meta.json")):
            continue
        info = json.load(open(info_p, encoding="utf-8"))
        out.append({"id": d, "name": info.get("name", d), "anims": sorted(info.get("anims", {}).keys())})
    out.sort(key=lambda x: x["name"])
    data = {"_doc": "펫 (트릭컬 스파인 뷰어의 펫 모션). 프로필에서 골라 게임 중 보드 옆에 둔다. tools/make_pet_data.py 가 만든다.", "list": out}
    with open(os.path.join(ROOT, "data", "pets.json"), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    print("펫 %d마리" % len(out))


if __name__ == "__main__":
    main()
