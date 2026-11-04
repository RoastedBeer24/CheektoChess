#!/usr/bin/env python3
"""그룹 구성 페이지(claude.ai 아티팩트)의 저장 데이터 → data/groups.json

  python3 tools/import_group.py <그룹 문서 JSON> [그룹 id]

- 그룹 문서 JSON: 아티팩트 DB 의 groups/<id> 문서 (ArtifactData get 결과 파일) 또는 페이지의 '내보내기' JSON.
- 시너지 효과의 '게임 동작'(levels)은 아래 LEVELS 에 시너지 이름별로 적는다. 페이지의 효과 글은 표시용.
- 이미 groups.json 에 같은 id 의 그룹이 있으면 교체, 없으면 추가.

levels 형식 (단계마다 하나, 높은 단계만 적용 — 필요한 효과는 각 단계에 모두 적는다):
  mods        시너지 사도 능력치 (%)            team_mods / enemy_mods  아군 전체 / 적 전체
  per_art     시너지 사도의 장착 아티팩트 1개당 능력치
  team_arts   {"n": 아군 장착 아티팩트 합계 이상, "mods": 시너지 사도 능력치}
  per_ally    전투 시작 시 시너지 사도를 뺀 아군 1명당 능력치 (시너지 사도에게)
  row_mods    시너지 사도가 있는 열마다 그 열의 아군 능력치 (열마다 한 번)
  fx          시너지 사도에게 붙는 효과 (아티팩트 fx 와 같은 형식 + interval/ally_death/death_self)
  side_timer  {"sec", "do"}: 진영 단위 주기 효과 (살아 있는 시너지 사도 중 첫 번째가 시전)
  guardian    아군이 처음 쓰러질 피해를 받으면 HP 1로 버티고 무적 (전투당 1회)
  revive      {"pct", "delay"}: 처음 쓰러진 시너지 사도가 부활 (전투당 1회)
  row_counter {"chance", "pct"}: 시너지 사도와 같은 열 아군이 맞으면 확률로 반격
  gold        {"win", "lose"}: 라운드 결과 골드 (매치에서 처리), art_every_wins: n승마다 일반 아티팩트
  by_pers     {성격: 위 형식}: 시너지 사도가 고른 성격(공명/이면)에 따라 다른 효과
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

COLORS = {
    "털 부락": "e8a25c", "델리아 탐험대": "d9c38a", "에르피엔": "ffd166", "세계수 교단": "7fd88f",
    "믿을 녀석 하나 없는 차가운 도시": "8cc4ff", "사료스탕스": "ff8a65", "뜨거운 도시의 믿을만한 녀석": "ff6f6f",
    "정령산": "6fe0d0", "유령 늪": "b58cff", "폐쇄적인 수집가": "f0b6ff", "벨리티엔": "c58cff",
}
UNIQUE_COLOR = "ffb13b"
# 좁은 곳(상점 카드·시너지 목록)에 쓰는 짧은 이름
SHORT = {
    "믿을 녀석 하나 없는 차가운 도시": "차가운 도시", "뜨거운 도시의 믿을만한 녀석": "뜨거운 도시",
    "누구를 위하여 기도를 올리나": "기도", "최소한 잼은 발라줘": "잼 빵", "엘리아스 오디세이아": "오디세이아",
    "언젠가 다시 찾아온 타이밍": "타이밍", "우회 루틴! 차원을 넘어 그대에게": "우회 루틴",
    "얼어붙은 너의 이름 위에": "빙결", "홀로 선 존재는 어디에도 없이": "홀로 선 존재", "다이아몬드의 단련": "단련",
    "멜트다운 버터": "멜트다운",
}

def trait_heal(pct):
    return {"a": "heal", "to": "trait", "pct": pct}

LEVELS = {
    "털 부락": [
        {"mods": {"aspd": 10}},
        {"mods": {"aspd": 20}, "fx": [{"t": "kill", "do": [trait_heal(8)]}]},
        {"mods": {"aspd": 25}, "fx": [{"t": "kill", "do": [trait_heal(10), {"a": "buff", "to": "trait", "mods": {"atk": 5}, "dur": 999, "key": "fur_hunt", "stack": 5}]}]},
    ],
    "델리아 탐험대": [
        {"mods": {"start_shield": 20}, "gold": {"win": 1, "lose": 0}},
        {"mods": {"start_shield": 20}, "gold": {"win": 2, "lose": 1}},
        {"mods": {"start_shield": 20}, "gold": {"win": 3, "lose": 1}, "art_every_wins": 3},
    ],
    "에르피엔": [
        {"mods": {"sp_regen": 30}},
        {"mods": {"sp_regen": 60, "skill_dmg": 20}},
        {"mods": {"sp_regen": 100, "skill_dmg": 35}, "fx": [{"t": "skill", "which": "any", "do": [{"a": "heal", "to": "lowest", "pct": 8}]}]},
    ],
    "세계수 교단": [
        {"side_timer": {"sec": 4, "do": [{"a": "heal", "to": "lowest", "pct": 7}]}},
        {"mods": {"heal_out": 30}, "side_timer": {"sec": 3, "do": [{"a": "heal", "to": "lowest", "pct": 10}]}},
        {"mods": {"heal_out": 50}, "side_timer": {"sec": 2, "do": [{"a": "heal", "to": "lowest", "pct": 13}]}, "guardian": True},
    ],
    "믿을 녀석 하나 없는 차가운 도시": [
        {"mods": {"crit": 40}},
        {"mods": {"crit": 75, "critdmg": 20}},
        {"mods": {"crit": 95, "critdmg": 35}, "fx": [{"t": "normal_hit", "do": [{"a": "execute", "below": 10}]}, {"t": "skill_hit", "do": [{"a": "execute", "below": 10}]}]},
    ],
    "사료스탕스": [
        {"fx": [{"t": "ally_death", "do": [{"a": "buff", "to": "self", "mods": {"atk": 8}, "dur": 999, "key": "resist", "stack": 5}]}]},
        {"fx": [{"t": "ally_death", "do": [{"a": "buff", "to": "self", "mods": {"atk": 12}, "dur": 999, "key": "resist", "stack": 5}]},
                {"t": "cond", "cond": "hp_lt:50", "mods": {"dmg_taken": -15}}]},
        {"fx": [{"t": "ally_death", "do": [{"a": "buff", "to": "self", "mods": {"atk": 14}, "dur": 999, "key": "resist", "stack": 5}]},
                {"t": "cond", "cond": "hp_lt:50", "mods": {"dmg_taken": -15}},
                {"t": "death_self", "do": [{"a": "shield", "to": "trait", "pct": 20, "dur": 8}]}]},
    ],
    "뜨거운 도시의 믿을만한 녀석": [
        {"row_mods": {"atk": 8}},
        {"row_mods": {"atk": 15, "dmg_taken": -8}},
        {"row_mods": {"atk": 25, "dmg_taken": -15}, "row_counter": {"chance": 20, "pct": 60}},
    ],
    "정령산": [
        {"fx": [{"t": "normal_hit", "chance": 20, "do": [{"a": "status", "s": "shock", "dur": 2}]}]},
        {"fx": [{"t": "normal_hit", "chance": 30, "do": [{"a": "status", "s": "shock", "dur": 2}]},
                {"t": "cond", "cond": "vs_elem", "mods": {"dmg": 15}}]},
        {"fx": [{"t": "normal_hit", "chance": 40, "do": [{"a": "status_rand", "s": ["shock", "burn"], "dur": 3}]},
                {"t": "cond", "cond": "vs_elem", "mods": {"dmg": 30}}]},
    ],
    "유령 늪": [
        {"enemy_mods": {"aspd": -10}},
        {"enemy_mods": {"aspd": -18}, "fx": [{"t": "normal_hit", "chance": 30, "do": [{"a": "status", "s": "blind", "dur": 2}]},
                                             {"t": "start", "do": [{"a": "untarget", "dur": 1.5}]}]},
        {"enemy_mods": {"aspd": -25}, "fx": [{"t": "normal_hit", "chance": 30, "do": [{"a": "status", "s": "blind", "dur": 2}]},
                                             {"t": "start", "do": [{"a": "untarget", "dur": 2}]}], "revive": {"pct": 40, "delay": 2}},
    ],
    "폐쇄적인 수집가": [
        {"mods": {"hp": 8}, "per_art": {"atk": 5, "hp": 5}},
        {"mods": {"hp": 12}, "per_art": {"atk": 8, "hp": 8, "def": 10}},
        {"mods": {"hp": 15}, "per_art": {"atk": 12, "hp": 12, "def": 20}, "team_arts": {"n": 6, "mods": {"dmg": 10}}},
    ],
    "벨리티엔": [
        {"mods": {"magic_dmg": 15}},
        {"mods": {"magic_dmg": 30}, "fx": [{"t": "skill_hit", "do": [{"a": "debuff", "to": "target", "mods": {"mdef": -20}, "dur": 4, "key": "belit"}]}]},
        {"mods": {"magic_dmg": 45}, "team_mods": {"magic_dmg": 10}, "fx": [{"t": "skill_hit", "do": [{"a": "debuff", "to": "target", "mods": {"mdef": -35}, "dur": 4, "key": "belit"}]}]},
    ],
    # ── 고유
    "멜트다운 버터": [
        {"fx": [{"t": "hp_below", "pct": 50, "do": [{"a": "buff", "to": "self", "mods": {"aspd": 80, "dmg_taken": -30, "splash": 50}, "dur": 4, "key": "melt"}]}]},
    ],
    "누구를 위하여 기도를 올리나": [
        {"by_pers": {
            "순수": {"team_mods": {"heal_in": 25}, "side_timer": {"sec": 6, "do": [{"a": "heal", "to": "allies", "pct": 4}]}},
            "우울": {"fx": [{"t": "start", "do": [{"a": "status", "to": "enemies", "s": "bitter", "dur": 4}]}],
                     "side_timer": {"sec": 6, "do": [{"a": "status", "to": "enemies", "s": "bitter", "dur": 4}]}},
        }},
    ],
    "최소한 잼은 발라줘": [
        {"fx": [{"t": "skill", "which": "any", "do": [{"a": "buff", "to": "allies", "mods": {"aspd": 15}, "dur": 4, "key": "jam", "stack": 2}]},
                {"t": "death_self", "do": [{"a": "debuff", "to": "allies", "mods": {"atk": -10}, "dur": 999, "key": "jam_sulk"}]}]},
    ],
    "엘리아스 오디세이아": [
        {"fx": [{"t": "kill", "do": [{"a": "strike", "mode": "back", "pct": 150}, {"a": "buff", "to": "self", "mods": {"atk": 10}, "dur": 999, "key": "odyssey", "stack": 5}]}]},
    ],
    "언젠가 다시 찾아온 타이밍": [
        {"fx": [{"t": "interval", "sec": 6, "do": [{"a": "crit_now"}, {"a": "next_normal", "bonus": 100}]}]},
    ],
    "우회 루틴! 차원을 넘어 그대에게": [
        {"fx": [{"t": "interval", "sec": 5, "do": [{"a": "shield_atk", "to": "lowest", "pct": 150, "dur": 5}, {"a": "buff", "to": "lowest", "mods": {"dmg_taken": -20}, "dur": 3, "key": "r41"}]}]},
    ],
    "얼어붙은 너의 이름 위에": [
        {"fx": [{"t": "skill_hit", "do": [{"a": "status", "to": "target", "s": "freeze", "dur": 1.5}]}]},
    ],
    "홀로 선 존재는 어디에도 없이": [
        {"per_ally": {"dmg_taken": -5}, "fx": [{"t": "death_self", "do": [{"a": "shield", "to": "allies", "pct": 20, "dur": 8}]}]},
    ],
    "다이아몬드의 단련": [
        {"fx": [{"t": "damaged", "do": [{"a": "buff", "to": "self", "mods": {"def": 6, "atk": 2}, "dur": 999, "key": "dia", "stack": 20}]},
                {"t": "hits_taken_n", "n": 20, "do": [{"a": "invuln", "dur": 3}, {"a": "clear_buff", "key": "dia"}]}]},
    ],
}

# 게임 동작에 맞춘 효과 글 (페이지 글과 다르면 이쪽을 씀 — 페이지에도 다시 반영)
EFFECT = {
    "사료스탕스": "끝까지 저항 — 동료가 쓰러질수록 사료스탕스가 거세진다.\n2명: 아군이 쓰러질 때마다 사료스탕스 공격력 +8% (최대 5중첩)\n4명: 공격력 +12%씩, HP 50% 이하일 때 받는 피해 -15%\n6명: 공격력 +14%씩, HP 50% 이하일 때 받는 피해 -15%, 사료스탕스가 쓰러지면 남은 사료스탕스 전원 최대 HP 20% 보호막",
    "털 부락": "무리 사냥 — 털 부락 사도의 공격 속도가 오르고, 적을 쓰러뜨리면 사냥감을 나눠 먹는다.\n2명: 공격 속도 +10%\n4명: 공격 속도 +20%, 적 처치 시 털 부락 전원 최대 HP 8% 회복\n6명: 공격 속도 +25%, 적 처치 시 털 부락 전원 최대 HP 10% 회복 + 공격력 +5% (전투 중 중첩, 최대 5)",
    "에르피엔": "왕국의 축제 — 에르피엔 사도의 SP가 빨리 차서 저학년 스킬을 자주 쓴다.\n2명: SP 회복 +30%\n4명: SP 회복 +60%, 스킬 피해 +20%\n6명: SP 회복 +100%, 스킬 피해 +35%, 스킬을 쓸 때마다 HP가 가장 낮은 아군 최대 HP 8% 회복",
    "세계수 교단": "세계수의 가호 — 교단이 주기적으로 가장 위태로운 아군을 치유한다.\n2명: 4초마다 HP가 가장 낮은 아군 최대 HP 7% 회복\n4명: 3초마다 10% 회복, 교단 사도 치유량 +30%\n6명: 2초마다 13% 회복, 치유량 +50%, 아군이 처음 쓰러질 피해를 받으면 대신 HP 1로 버티고 1.5초 무적 (전투당 1회)",
    "유령 늪": "늪의 수렁 — 적의 발을 묶고, 늪의 유령은 쉽게 사라지지 않는다.\n2명: 적 전체 공격 속도 -10%\n4명: 적 전체 공격 속도 -18%, 유령 늪 사도는 전투 시작 1.5초 동안 대상 지정 불가, 일반 공격이 30% 확률로 눈가림 2초\n6명: 적 전체 공격 속도 -25%, 시작 2초 대상 지정 불가, 눈가림, 처음 쓰러진 유령 늪 사도가 2초 뒤 HP 40%로 다시 일어남 (전투당 1회)",
    "믿을 녀석 하나 없는 차가운 도시": "각자도생 — 믿을 건 자기 칼끝뿐. 치명타가 강해지고 약한 적은 놓치지 않는다.\n2명: 치명타 +40% (기본 12% → 약 17%)\n4명: 치명타 +75% (약 21%), 치명 피해 +20%\n6명: 치명타 +95% (약 23%), 치명 피해 +35%, 공격·스킬에 맞아 HP 10% 이하가 된 적을 처형",
    "델리아 탐험대": "보물 발견 — 탐험 성과로 골드를 챙긴다. (라운드가 끝날 때 지급)\n2명: 탐험대원 전투 시작 시 최대 HP 20% 보호막, 승리 시 +1골드\n3명: 보호막, 승리 시 +2골드, 패배 시 +1골드\n4명: 보호막, 승리 시 +3골드, 패배 시 +1골드, 3번 이길 때마다 보관함에 일반 아티팩트 1개",
    "폐쇄적인 수집가": "수집 본능 — 모은 것이 곧 힘. 장착한 아티팩트가 많을수록 강해진다.\n2명: 수집가 사도 HP +8%, 아티팩트 1개당 공격력 +5%, HP +5%\n4명: HP +12%, 1개당 공격력 +8%, HP +8%, 방어력 +10%\n6명: HP +15%, 1개당 공격력 +12%, HP +12%, 방어력 +20%, 아군이 장착한 아티팩트가 모두 6개 이상이면 수집가 전원 피해 +10%",
    "최소한 잼은 발라줘": "에르핀이 스킬을 쓸 때마다 아군 전체에 잼 바른 빵: 4초 동안 공격 속도 +15% (빵이 남아 있을 때 또 받으면 +30%까지). 빵을 못 받으면 투정 — 에르핀이 쓰러지면 아군 전체 공격력 -10%.",
    "언젠가 다시 찾아온 타이밍": "6초마다 '타이밍': 리뉴아의 다음 공격이 반드시 치명타이며 피해 +100%.",
    "홀로 선 존재는 어디에도 없이": "벨라는 혼자가 아니다: 전투 시작 시 함께 선 아군 1명당 받는 피해 -5%. 벨라가 쓰러지면 아군 전체 최대 HP 20% 보호막.",
    "다이아몬드의 단련": "다야가 피해를 받을 때마다 단련 1중첩 (최대 20): 방어력 +6%, 공격력 +2%. 20번 맞을 때마다 3초 무적 후 단련 초기화.",
    "얼어붙은 너의 이름 위에": "아야의 스킬에 맞은 적은 1.5초 빙결(행동 불가). 빙결된 적이 다시 공격받으면 빙결이 깨지며 아야 공격력 80% 추가 피해.",
}


def main():
    src = sys.argv[1]
    gid = sys.argv[2] if len(sys.argv) > 2 else "g1"
    raw = json.load(open(src, encoding="utf-8"))
    d = raw.get("data", raw)
    if "groups" in d:   # 내보내기 JSON
        g = d["groups"][0]
        slots = {}
        for u in g["units"]:
            slots.setdefault(str(u["cost"]), []).append({"a": u["id"], "t": u.get("traits", []), "m": u.get("note", "")})
        traits = [{"id": t["id"], "kind": t["kind"], "name": t["name"], "tiers": "/".join(map(str, t["tiers"])), "effect": t.get("effect", "")} for t in g["synergies"]]
        name, pool, odds = g["name"], g["pool_size"], g["shop_odds"]
    else:               # 페이지 DB 문서
        slots, traits, name = d["slots"], d["traits"], d["name"]
        pool = [int(d["pool"][str(c)]) for c in range(1, 6)]
        odds = d["odds"]
    by_id = {t["id"]: t for t in traits}
    units = []
    used = set()
    for c in range(1, 6):
        for s in slots.get(str(c), []):
            if not s.get("a"):
                continue
            names = [by_id[x]["name"].strip() for x in s.get("t", []) if x and x in by_id and by_id[x]["name"].strip()]
            units.append({"id": s["a"], "cost": c, "traits": names})
            used.update(names)
    syns = []
    for t in traits:
        nm = t["name"].strip()
        if not nm or nm not in used:
            continue
        tiers = [int(x) for x in str(t["tiers"]).replace(",", "/").split("/") if x.strip().isdigit()]
        lv = LEVELS.get(nm)
        if lv is None:
            print("경고: 동작이 정의되지 않은 시너지:", nm)
            lv = [{} for _ in tiers]
        if len(lv) != len(tiers):
            print("경고: 단계 수 불일치:", nm, tiers, len(lv))
        syns.append({"id": t["id"], "name": nm, "short": SHORT.get(nm, nm), "kind": t["kind"], "tiers": tiers,
                     "color": COLORS.get(nm, UNIQUE_COLOR if t["kind"] == "unique" else "c0c4d6"),
                     "effect": EFFECT.get(nm, t.get("effect", "")), "levels": lv})
    group = {"id": gid, "name": name, "pool_size": pool, "shop_odds": odds, "units": units, "synergies": syns}
    path = os.path.join(ROOT, "data", "groups.json")
    data = {"_note": "그룹: 판에 쓰는 사도·코스트·시너지. tools/import_group.py 로 그룹 구성 페이지에서 가져온다.", "groups": []}
    if os.path.exists(path):
        data = json.load(open(path, encoding="utf-8"))
    data["groups"] = [x for x in data["groups"] if x["id"] != gid] + [group]
    data["groups"].sort(key=lambda x: x["id"])
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    print("%s: 사도 %d명, 시너지 %d개 → %s" % (name, len(units), len(syns), path))


if __name__ == "__main__":
    main()
