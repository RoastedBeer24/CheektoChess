# 사도 스킬 데이터 형식 (data/skill_specs.json)

그룹 사도의 원작 스킬·어사이드·애착 효과를 게임 동작으로 옮긴 데이터. 전투 계산(scripts/core/battle_sim.gd)이 읽는다.
원작 수치는 참고만 한다 — 우리 게임 규모에 맞춰 줄인다 (아래 '크기 기준').

```json
{
  "<사도 id>": {
    "fresh":  {"do": [동작...], "note": "원작 설명을 어떻게 해석했는지 한 줄"},
    "senior": {"do": [동작...], "cd": 재사용 대기(초, 생략하면 기본값), "note": "..."},
    "passive": {"mods": {...}, "fx": [...], "note": "..."},
    "enh": {"do": [동작...], "note": "강화 공격(4번째 일반 공격) 추가 효과 (없으면 생략)"},
    "aside2": {"mods": {...}, "fx": [...], "power": 30, "note": "..."},
    "aside3": {"mods": {...}, "team_mods": {...}, "scope": "self|team|row|same_row_type", "fx": [...], "note": "..."}
  },
  "_fav": {
    "<아티팩트 id>": {"owner": "<사도 id>", "mods": {...}, "fx": [...], "replace": "fresh|senior|enh|", "do": [동작...], "note": "..."}
  }
}
```

## 동작 (do 안의 원소)
| a | 필드 | 뜻 |
|---|---|---|
| dmg | to, pct, hits(기본 1), dtype(생략=사도 공격 타입), status:{s,dur,chance} | 피해 (공격력 × pct%). hits 이면 pct 를 hits 번에 나눠 줌 |
| heal | to, pct_atk 또는 pct_hp | 회복 (공격력 × pct_atk% 또는 대상 최대 HP × pct_hp%) |
| shield | to, pct_atk 또는 pct_hp, dur | 보호막 |
| buff | to, mods, dur, stack(기본 1), key | 아군 버프 (mods 는 % 단위) |
| debuff | to, mods, dur, key | 적 약화 |
| status | to, s(stun/burn/bitter/shock/blind/freeze), dur, chance | 상태이상 |
| taunt | dur | 도발 |
| invuln / untarget | dur | 무적 / 대상 지정 불가 (자신) |
| sp | to, pct | SP 회복 (최대 SP 의 %) |
| cleanse | to | 기절·빙결 해제 |
| execute | to, below | HP below% 이하 적 처형 |

## 대상 (to)
- 적: `front`(가장 앞 열에서 가까운 적), `back`(가장 뒤 열), `low`(HP 비율 가장 낮은 적), `high_atk`(공격력 가장 높은 적),
  `row_front`(가장 앞 열 적 전체), `row_back`(가장 뒤 열 적 전체), `all`(적 전체), `random:N`(무작위 N명, 중복 가능), `around:front`(가장 앞 적과 그 위아래 칸)
- 아군: `self`, `lowest`(HP 비율 가장 낮은 아군), `allies`(아군 전체), `row`(같은 열 아군), `front_ally`(가장 앞 열 아군 전체),
  `back_ally`(가장 뒤 열 아군 전체), `random_ally:N`

## mods 키 (모두 %)
atk, patk, matk, hp, def, pdef, mdef, aspd, crit, critdmg, dmg, dmg_taken, skill_dmg, fresh_dmg, senior_dmg, normal_dmg, enh_dmg,
magic_dmg, heal_out, heal_in, shield_in, sp_regen, critres, regen(초당 최대 HP %)

## fx (발동 효과) — 아티팩트·시너지와 같은 형식
`{"t": 발동 조건, ..., "do": [동작...]}` (fx 안의 동작은 엔진 동작: buff/debuff/shield(pct=최대HP%)/heal(pct=최대HP%)/status/extra(pct)/sp(amt)/invuln/untarget/execute 등)
발동 조건: start, normal_hit(chance), normal_n(n), kill, damaged, hits_taken_n(n), hp_below(pct, 1회), skill(which: fresh|senior|any), skill_hit, interval(sec), ally_death, death_self, cond(cond, mods)

## 크기 기준 (중요)
- 지금 공통 스킬: 딜러 저학년 200~350%, 고학년 150~480%(대상 수에 따라), 탱커 보호막 최대 HP 30%, 서포터 회복 공격력 260%.
- 원작 % 는 우리 수치보다 훨씬 크다. **대상 1명 기준 저학년 총 피해 250~400%, 고학년 총 피해 350~600%** 안에서,
  여러 명을 때리면 1명당 피해를 그만큼 줄인다 (적 전체 = 1명 기준의 40~50%).
- 버프·디버프는 3~8초, 수치 10~40%. 기절은 1~2초. 보호막 최대 HP 15~35%.
- 원작 설명이 우리 게임에 없는 개념(이동, 소환, 밀치기 등)이면 가장 비슷한 효과로 바꾸고 note 에 적는다.
