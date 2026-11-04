#!/usr/bin/env python3
"""원본 사도 데이터(data/raw)를 게임용 data/apostles.json 으로 변환한다.

사용법: python3 tools/build_apostles.py
- 원작 능력치는 쓰지 않는다. 성격/종족/열/역할/공격 타입/스킬·어사이드 설명만 가져온다.
- 실제 게임 수치(코스트 등)는 data/roster.json 에서 정한다.
"""
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "data", "raw")

PERSONALITY = {
    "Composed": "냉정", "Madness": "광기", "Innocence": "순수",
    "Vivacious": "활발", "Depressed": "우울", "Resonance": "공명",
}
RACE = {
    "Elementals": "정령", "Werebeasts": "수인", "Elves": "엘프", "Mystic": "미스틱",
    "Sprites": "요정", "Witches": "마녀", "Dragons": "용족", "Phantoms": "유령",
}
ROW = {"Front": "front", "Middle": "mid", "Back": "back", "All rows": "all"}
ROLE = {"DPS": "dealer", "Tank": "tank", "Support": "support"}
DAMAGE = {"Physical": "physical", "Magic": "magic"}
SKILL_KIND = {
    "Freshman Skill": "fresh", "Senior Skill": "senior",
    "Normal ATK": "normal", "Passive": "passive",
}
# 원본 데이터 오류 보정 (영문 이름 -> 한글 이름)
NAME_FIX = {"Yomi": "요미"}


def fill_values(entry):
    """[종류, 이름, 설명(, 레벨별 수치)] 형식을 (종류, 이름, 설명) 으로 정리한다.
    수치가 있으면 %1, %2 ... 를 1레벨 값으로 치환한다 (게임 전체에 레벨 없음)."""
    kind, name, desc = entry[0], entry[1], entry[2]
    if len(entry) > 3 and isinstance(entry[3], list):
        for i, vals in enumerate(entry[3]):
            if vals:
                desc = desc.replace("%%%d" % (i + 1), str(vals[0]).rstrip("%"))
    return kind, name, desc


def slug(name: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
    return s


def main():
    chars = json.load(open(os.path.join(RAW, "lootandwaifus_characters.json"), encoding="utf-8"))
    eldyne = set(json.load(open(os.path.join(RAW, "eldyne_names.json"), encoding="utf-8")))
    out = {}
    for c in chars:
        en = c["name"].strip()
        kr = NAME_FIX.get(en) or c.get("kr_name")
        if not kr:
            # 한글 이름이 없는 사도(트릭컬 리바이브 미등장)는 제외
            continue
        el = c.get("element")
        if isinstance(el, list):
            personality = "이면"
            options = [PERSONALITY[e] for e in el]
        else:
            personality = PERSONALITY[el]
            options = ["순수", "냉정", "광기", "활발", "우울"] if personality == "공명" else []
        skills = {}
        for entry in c.get("skill_description") or []:
            kind, name, desc = fill_values(entry)
            k = SKILL_KIND.get(kind)
            if k:
                skills[k] = {"name": name if name != "Normal ATK" else "일반 공격", "desc": desc}
        aside = {}
        for entry in c.get("yearning") or []:
            star, name, desc = fill_values(entry)
            aside[star[0]] = {"name": name, "desc": desc}
        aid = slug(en)
        out[aid] = {
            "id": aid,
            "name": kr,
            "name_en": en,
            "personality": personality,
            "personality_options": options,
            "race": RACE[c["race"]],
            "eldyne": en in eldyne,
            "row": ROW[c["position"]],
            "role": ROLE[c["role"]],
            "damage": DAMAGE[c["damage"]],
            "skills": skills,
            "aside": aside,
        }
    path = os.path.join(ROOT, "data", "apostles.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print(f"{len(out)}명 저장: {path}")


if __name__ == "__main__":
    main()
