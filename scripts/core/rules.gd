class_name Rules
extends RefCounted
## 전투/UI 가 함께 쓰는 공용 규칙: 시너지 계산, 사도 기본 능력치, 어사이드 해석.


## 보드 위 유닛 목록(각 원소 {aid, pers})으로 시너지 인원 수를 센다 (그룹 시너지).
## 같은 사도는 한 번만 센다.
static func count_traits(units: Array) -> Dictionary:
	var seen := {}
	var counts := {}
	for u in units:
		var key: String = u["aid"]
		if seen.has(key):
			continue
		seen[key] = true
		for t in GameData.traits_of(key):
			if t == "":
				continue
			counts[t] = counts.get(t, 0) + 1
	return counts


## 상징 증강: 그 시너지 사도가 1명 이상이면 인원 +1
static func apply_emblems(counts: Dictionary, augs: Array) -> Dictionary:
	for a in augs:
		if a.get("id", "") == "emblem" and counts.get(a.get("trait", ""), 0) > 0:
			counts[a["trait"]] += 1
	return counts


## 시너지 이름 -> 발동 단계(0 = 미발동, 1~)
static func active_tiers(counts: Dictionary) -> Dictionary:
	var out := {}
	for name in counts:
		var syn: Dictionary = GameData.synergies.get(name, {})
		if syn.is_empty():
			continue
		var tier := 0
		var tiers: Array = syn["tiers"]
		for i in tiers.size():
			if counts[name] >= int(tiers[i]):
				tier = i + 1
		out[name] = tier
	return out


## 사도 기본 능력치 (원작 수치 미사용: 역할/열/코스트/성급으로 계산)
static func base_stats(aid: String, star: int) -> Dictionary:
	var b: Dictionary = GameData.balance
	var a := GameData.apostle(aid)
	var role: Dictionary = b["unit_base"][a.get("role", "dealer")]
	var rowm: Dictionary = b["row_mult"][a.get("row", "mid")]
	var cost: int = GameData.cost_of.get(aid, 1)
	var cs := 1.0 + float(b["cost_scale"]) * (cost - 1)
	var sm: float = b["star_mult"][clampi(star, 1, 3) - 1]
	return {
		"hp": float(role["hp"]) * rowm["hp"] * cs * sm,
		"atk": float(role["atk"]) * rowm["atk"] * cs * sm,
		"def": float(role["def"]) * (1.0 + 0.1 * (cost - 1)),
		"aspd": float(role["aspd"]),
		"crit": float(b["base_crit"]),
		"critdmg": float(b["base_critdmg"]),
	}


const _STAT_WORDS := [
	# [키워드(한), 키워드(영), 능력치 키] — 긴 표현부터 검사한다
	["치명 피해 저항", "crit dmg resistance", "critdmgres"],
	["치명타 저항", "crit resistance", "critres"],
	["치명 피해", "crit dmg", "critdmg"],
	["치명타", "crit", "crit"],
	["물리 공격력", "physical atk", "patk"],
	["마법 공격력", "magical atk", "matk"],
	["물리 방어력", "physical def", "pdef"],
	["마법 방어력", "magical def", "mdef"],
	["공격 속도", "attack speed", "aspd"],
	["최대 hp", "max hp", "hp"],
	["공격력", "atk", "atk"],
	["방어력", "def", "def"],
]


## 문장에서 언급된 능력치 키 목록을 뽑는다 (어사이드 1성 해석용)
static func parse_stat_words(text: String) -> Array:
	var t := text.to_lower()
	var out := []
	for w in _STAT_WORDS:
		for kw in [w[0], w[1]]:
			while t.find(kw) >= 0:
				if not out.has(w[2]):
					out.append(w[2])
				t = t.replace(kw, "#")
	return out


## 어사이드 1성: 언급된 능력치 +N% (자신)
static func aside1_mods(aid: String) -> Dictionary:
	var a := GameData.apostle(aid)
	var desc: String = a.get("aside", {}).get("1", {}).get("desc", "")
	var bonus: float = GameData.balance["aside1_stat_bonus"]
	var out := {}
	for k in parse_stat_words(desc):
		out[k] = bonus
	return out


## 어사이드 3성 간이 해석: {scope: "team"/"same_pers"/"self", mods}
static func aside3_effect(aid: String) -> Dictionary:
	var a := GameData.apostle(aid)
	var desc: String = a.get("aside", {}).get("3", {}).get("desc", "")
	if desc == "":
		return {}
	var t := desc.to_lower()
	var scope := "self"
	if t.find("같은 성격") >= 0 or t.find("same personality") >= 0:
		scope = "same_pers"
	elif t.find("아군") >= 0 or t.find("allies") >= 0:
		scope = "team"
	var mods := {}
	if t.find("받는 피해") >= 0 or t.find("incoming") >= 0:
		mods["dmg_taken"] = -8
	if t.find("주는 피해") >= 0 or t.find("피해량") >= 0 or t.find("outgoing") >= 0 or t.find("damage") >= 0:
		mods["dmg"] = 8
	if t.find("공격 속도") >= 0 or t.find("attack speed") >= 0:
		mods["aspd"] = 10
	if t.find("치명") >= 0 or t.find("crit") >= 0:
		mods["crit"] = 15
		mods["critdmg"] = 8
	var sp_re := RegEx.create_from_string("\\bsp")
	if sp_re.search(t) != null:
		mods["sp_regen"] = 12
	if t.find("회복") >= 0 or t.find("recover") >= 0 or t.find("heal") >= 0:
		mods["heal_in"] = 15
	if t.find("방어력") >= 0 or t.find("defense") >= 0:
		mods["def"] = 12
	if t.find("공격력") >= 0 or t.find("atk") >= 0:
		mods["atk"] = 8
	if mods.is_empty():
		mods["dmg"] = 8
	return {"scope": scope, "mods": mods}


static func add_mods(into: Dictionary, mods: Dictionary, mult: float = 1.0) -> void:
	for k in mods:
		into[k] = into.get(k, 0.0) + float(mods[k]) * mult
