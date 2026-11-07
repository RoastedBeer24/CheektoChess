class_name BattleSim
extends RefCounted
## 결정론적 자동 전투 시뮬레이터.
## 같은 입력(양쪽 군대 + seed)이면 어느 기기에서든 같은 결과가 나오도록
## 전투 중 난수는 모두 이 객체의 rng 하나만 쓴다.
##
## 입력 군대: Array of {aid, star, row, slot, arts: [artifact id], pers}
## 결과: {winner: 0|1|-1(무승부), survivors, end_time, events, units}

const DT := 0.1
static var _HANGUL := RegEx.create_from_string("[가-힣]")

var rng := RandomNumberGenerator.new()
var units: Array = []          # 유닛 런타임 상태 (Dictionary)
var events: Array = []         # 연출용 이벤트 목록
var time := 0.0
var deaths := [0, 0]           # 진영별 사망 수
var _tick_count := 0
var _uid_buff := 0
var B: Dictionary
var side_timers: Array = []    # 진영 단위 주기 효과 {side, syn, sec, t, do}
var guardian := [false, false] # 세계수: 처음 쓰러질 아군을 버티게 함 (진영별 1회)
var revive := [{}, {}]         # 유령 늪: 처음 쓰러진 시너지 사도 부활 {syn, pct, delay}
var pending_revive: Array = [] # {i, at, pct}


func _init(army_a: Array, army_b: Array, seed: int) -> void:
	B = GameData.balance
	rng.seed = seed
	_build_side(army_a, 0)
	_build_side(army_b, 1)
	_apply_team_effects()


# ─────────────────────────────── 생성 ───────────────────────────────

func _build_side(army: Array, side: int) -> void:
	for spec in army:
		var aid: String = spec["aid"]
		var a := GameData.apostle(aid)
		var star: int = spec.get("star", 1)
		var u := {
			"i": units.size(), "side": side, "aid": aid, "name": a.get("name", aid),
			"star": star, "row": int(spec["row"]), "slot": int(spec["slot"]),
			"pers": spec.get("pers", ""), "role": a.get("role", "dealer"),
			"dtype": a.get("damage", "physical"), "eldyne": a.get("eldyne", false),
			"base": Rules.base_stats(aid, star),
			"mods": {}, "buffs": [], "shields": [], "status": {},
			"fx": [], "conds": [],
			"alive": true, "sp": 0.0, "atk_timer": 0.6 + 0.05 * int(spec["slot"]),
			"senior_timer": float(B["senior_first"]), "n_attacks": 0, "n_normal_hits": 0,
			"n_hits_taken": 0, "n_skill_hits": 0, "counters": {}, "cds": {}, "once": {},
			"pending_normal": [], "force_crit": false, "invuln": 0.0, "untarget": 0.0,
			"taunt": 0.0, "regens": [], "damaged_by": {}, "power": 1.0, "arts": spec.get("arts", []),
			"monster": spec.get("monster", false), "augs": spec.get("augs", []),
			"grow": int(spec.get("grow", 0)), "bench_n": int(spec.get("bench_n", 0)), "syn_pts": spec.get("syn_pts", {}), "n_skills": 0,
		}
		# 위치·사거리 (이동하며 싸우기): 배치 칸 → 전장 좌표
		var mv: Dictionary = B["move"]
		var p0 := start_xy(side, u["row"], u["slot"])
		u["x"] = p0.x
		u["y"] = p0.y
		var rkey: String = a.get("row", "mid")
		if rkey == "all":
			rkey = GameData.ROWS[u["row"]]
		u["range"] = float(mv["range"].get(rkey, 3.4))
		if u["monster"]:
			# 몬스터: 라운드에 따라 약하게/강하게(mpow), 몬스터마다 배율(mhp·matk), 시너지 없음
			var mp := float(spec.get("mpow", 1.0))
			u["base"]["hp"] *= mp * float(spec.get("mhp", 1.0))
			u["base"]["atk"] *= mp * float(spec.get("matk", 1.0))
			u["scale"] = float(spec.get("scale", 1.0))
			if spec.get("shadow", false):
				u["name"] = "그림자 " + String(u["name"])
		# 실전 경험 증강: 전투를 치른 만큼 공격력·체력
		if int(u["grow"]) > 0:
			Rules.add_mods(u["mods"], {"atk": float(u["grow"]), "hp": float(u["grow"])})
		# 어사이드 1성 (기본 적용)
		Rules.add_mods(u["mods"], Rules.aside1_mods(aid))
		# 사도별 스킬 데이터 (원작 스킬·패시브·어사이드 2/3성·애착)
		var sk: Dictionary = GameData.skill_specs.get(aid, {}) if not u["monster"] else {}
		u["sk"] = {}
		for which in ["fresh", "senior", "enh"]:
			if sk.has(which) and not sk[which].get("do", []).is_empty():
				u["sk"][which] = sk[which]["do"]
		if sk.get("senior", {}).has("cd"):
			u["senior_cd"] = float(sk["senior"]["cd"])
			u["senior_timer"] = minf(float(B["senior_first"]), u["senior_cd"])
		if sk.has("passive"):
			_attach(u, sk["passive"])
		# 어사이드 2성: 데이터가 있으면 그것, 없으면 스킬 위력 증가 (간이)
		if star >= 2:
			if sk.has("aside2"):
				_attach(u, sk["aside2"])
				u["power"] += float(sk["aside2"].get("power", 0)) / 100.0
			else:
				u["power"] += float(B["aside2_skill_power"]) / 100.0
		# 애착: 주인 사도가 장착한 아티팩트
		var favs: Dictionary = GameData.skill_specs.get("_fav", {})
		var fav_done := {}
		for art_id in u["arts"]:
			var fv: Dictionary = favs.get(art_id, {})
			if fv.is_empty() or fv.get("owner", "") != aid or fav_done.has(art_id):
				continue
			fav_done[art_id] = true
			_attach(u, fv)
			var rp: String = fv.get("replace", "")
			if rp != "" and not fv.get("do", []).is_empty():
				u["sk"][rp] = fv["do"]
		# 아티팩트 능력치(항상 중첩) + 부가 효과(nostack 이면 1회)
		var seen_nostack := {}
		for art_id in u["arts"]:
			var art := GameData.artifact(art_id)
			if art.is_empty():
				continue
			Rules.add_mods(u["mods"], art.get("stats", {}))
			if art.get("nostack", false):
				if seen_nostack.has(art_id):
					continue
				seen_nostack[art_id] = true
			for fx in art.get("fx", []):
				var f: Dictionary = fx.duplicate(true)
				f["src_art"] = art_id
				match f["t"]:
					"stat":
						Rules.add_mods(u["mods"], f["mods"])
					"cond":
						u["conds"].append(f)
					_:
						f["k"] = u["fx"].size()
						u["fx"].append(f)
		units.append(u)


func _apply_team_effects() -> void:
	for side in [0, 1]:
		var allies := _side_units(side)
		var enemies := _side_units(1 - side)
		# 시너지 (그룹)
		var specs := []
		for u in allies:
			if not u["monster"]:
				specs.append({"aid": u["aid"], "pers": u["pers"]})
		var counts := Rules.count_traits(specs)
		var side_augs: Array = allies[0]["augs"] if not allies.is_empty() else []
		var emblems := []
		for a in side_augs:
			if a.has("emblem"):
				emblems.append({"id": "emblem", "trait": a["emblem"]})
			elif a.get("id", "") in ["syn_top", "syn_double"]:
				emblems.append({"id": a["id"]})
		Rules.apply_emblems(counts, emblems)
		var tiers := Rules.active_tiers(counts)
		var names: Array = tiers.keys()
		names.sort()   # 결정론: 항상 같은 순서
		for name in names:
			var tier: int = tiers[name]
			if tier <= 0:
				continue
			var syn: Dictionary = GameData.synergies[name]
			var levels: Array = syn.get("levels", [])
			if tier - 1 >= levels.size():
				continue
			var members := []
			for u in allies:
				if _traits(u).has(name):
					members.append(u)
			if members.is_empty():
				continue
			var spec: Dictionary = levels[tier - 1]
			if spec.has("by_pers"):
				# 공명/이면: 시너지 사도가 고른 성격에 따라 (첫 사도 기준)
				spec = spec["by_pers"].get(members[0]["pers"], spec["by_pers"].values()[0])
			_apply_synergy(side, name, spec, members, allies, enemies)
		# 증강 (전투 효과): 시너지 형식 spec 을 아군 전체에
		for a in side_augs:
			var aspec: Dictionary = a.get("spec", {})
			if aspec.is_empty():
				continue
			if aspec.has("cost_mods"):
				for u in allies:
					if int(GameData.cost_of.get(u["aid"], 9)) <= int(aspec["cost_mods"]["max"]):
						_add_static(u, aspec["cost_mods"]["mods"])
			if aspec.has("cost_min_mods"):
				for u in allies:
					if int(GameData.cost_of.get(u["aid"], 0)) >= int(aspec["cost_min_mods"]["min"]):
						_add_static(u, aspec["cost_min_mods"]["mods"])
			if aspec.has("row_start_shield"):
				for u in allies:
					if int(u["row"]) == int(aspec["row_start_shield"]["row"]):
						u["start_shield"] = float(u.get("start_shield", 0.0)) + float(aspec["row_start_shield"]["pct"])
			if aspec.has("row_aug"):
				for u in allies:
					if int(u["row"]) == int(aspec["row_aug"]["row"]):
						u["range"] = float(u["range"]) + float(aspec["row_aug"].get("range", 0.0))
						_add_static(u, aspec["row_aug"].get("mods", {}))
			if aspec.has("full_row_mods"):
				var per_row := {}
				for u in allies:
					per_row[u["row"]] = int(per_row.get(u["row"], 0)) + 1
				for u in allies:
					if int(per_row[u["row"]]) >= int(aspec["full_row_mods"]["n"]):
						_add_static(u, aspec["full_row_mods"]["mods"])
			if aspec.has("kit_mods"):
				for u in allies:
					if u["arts"].size() >= int(aspec["kit_mods"]["n"]):
						_add_static(u, aspec["kit_mods"]["mods"])
			if aspec.has("ace_mods") and not allies.is_empty():
				var ace: Dictionary = allies[0]
				for u in allies:
					var key: int = int(GameData.cost_of.get(u["aid"], 0)) * 10 + int(u["star"])
					if key > int(GameData.cost_of.get(ace["aid"], 0)) * 10 + int(ace["star"]):
						ace = u
				_add_static(ace, aspec["ace_mods"])
			_apply_synergy(side, "증강", aspec, allies, allies, enemies)
		# 어사이드 3성: 데이터가 있으면 그것 (자신/같은 열/아군 전체), 없으면 간이 해석
		for src in allies:
			if src["star"] < 3:
				continue
			var a3: Dictionary = GameData.skill_specs.get(src["aid"], {}).get("aside3", {}) if not src["monster"] else {}
			if not a3.is_empty():
				for u in allies:
					var ok3 := false
					match a3.get("scope", "self"):
						"team":
							ok3 = true
						"row":
							ok3 = u["row"] == src["row"]
						_:
							ok3 = u == src
					if ok3:
						_add_static(u, a3.get("mods", {}))
						_add_static(u, a3.get("team_mods", {}))
				_attach(src, {"fx": a3.get("fx", [])})
				continue
			var eff := Rules.aside3_effect(src["aid"])
			if eff.is_empty():
				continue
			for u in allies:
				var ok := false
				match eff["scope"]:
					"team":
						ok = true
					"same_pers":
						ok = _pers_of(u) == _pers_of(src)
					_:
						ok = u == src
				if ok:
					Rules.add_mods(u["mods"], eff["mods"])
		# 같은 열 오라 (row_aura)
		for src in allies:
			for f in src["fx"]:
				if f["t"] == "row_aura":
					for u in allies:
						if u["row"] == src["row"]:
							Rules.add_mods(u["mods"], f["mods"])
	for u in units:
		u["hp"] = _raw_max_hp(u)
		u["hp"] = max_hp(u)


## 시너지 한 단계의 효과를 적용 (tools/import_group.py 의 levels 형식)
func _apply_synergy(side: int, name: String, spec: Dictionary, members: Array, allies: Array, enemies: Array) -> void:
	for u in members:
		_add_static(u, spec.get("mods", {}))
		var n_arts: int = u["arts"].size()
		if spec.has("per_art") and n_arts > 0:
			var pm := {}
			for k in spec["per_art"]:
				pm[k] = float(spec["per_art"][k]) * n_arts
			_add_static(u, pm)
		if spec.has("per_ally"):
			var others := allies.size() - members.size()
			var pa := {}
			for k in spec["per_ally"]:
				pa[k] = float(spec["per_ally"][k]) * others
			_add_static(u, pa)
		if spec.has("row_counter"):
			u["row_counter"] = spec["row_counter"]
		# 대기석 동료 1명당 (두고 가지 마세요)
		if spec.has("per_bench") and int(u.get("bench_n", 0)) > 0:
			var pb := {}
			for k in spec["per_bench"]:
				pb[k] = float(spec["per_bench"][k]) * int(u["bench_n"])
			_add_static(u, pb)
		# 시너지 사도가 선 열 종류 1개당 (판타지 모험단)
		if spec.has("per_rowkind"):
			var rk := {}
			for m in members:
				rk[m["row"]] = true
			var pr := {}
			for k in spec["per_rowkind"]:
				pr[k] = float(spec["per_rowkind"][k]) * rk.size()
			_add_static(u, pr)
		# 게임 내내 쌓인 시너지 포인트 1점당 (카페 단골)
		if spec.has("per_point"):
			var pts := mini(int(u.get("syn_pts", {}).get(name, 0)), int(spec["per_point"].get("max", 999)))
			var pp := {}
			for k in spec["per_point"]:
				if k != "max":
					pp[k] = float(spec["per_point"][k]) * pts
			_add_static(u, pp)
		# 장착 아티팩트 1개당 아군 전체 (고유)
		if spec.has("team_per_art") and n_arts > 0:
			var tp := {}
			for k in spec["team_per_art"]:
				tp[k] = float(spec["team_per_art"][k]) * n_arts
			for a in allies:
				_add_static(a, tp)
		for fx in spec.get("fx", []):
			var f: Dictionary = fx.duplicate(true)
			f["syn"] = name
			for act in f.get("do", []):
				if act.get("to", "") == "trait":
					act["trait"] = name
			if f["t"] == "cond":
				u["conds"].append(f)
			else:
				f["k"] = u["fx"].size()
				u["fx"].append(f)
	for u in allies:
		_add_static(u, spec.get("team_mods", {}))
		if spec.has("others_mods") and not members.has(u):
			_add_static(u, spec["others_mods"])   # 시너지 사도가 아닌 아군만 (응원)
		# 아군 전체에 붙는 발동 효과 (예: 위기 때 보호막)
		for fx in spec.get("team_fx", []):
			var tf: Dictionary = fx.duplicate(true)
			tf["syn"] = name
			tf["k"] = u["fx"].size()
			u["fx"].append(tf)
	for u in enemies:
		_add_static(u, spec.get("enemy_mods", {}))
	if spec.has("team_arts"):
		var total := 0
		for u in allies:
			total += u["arts"].size()
		if total >= int(spec["team_arts"]["n"]):
			for u in members:
				_add_static(u, spec["team_arts"]["mods"])
	if spec.has("row_mods"):
		var rows := {}
		for u in members:
			rows[u["row"]] = true
		for u in allies:
			if rows.has(u["row"]):
				_add_static(u, spec["row_mods"])
	if spec.has("side_timer"):
		var st: Dictionary = spec["side_timer"].duplicate(true)
		side_timers.append({"side": side, "syn": name, "sec": float(st["sec"]), "t": float(st["sec"]), "do": st["do"],
			"first_do": st.get("first_do", []), "n_then": st.get("n_then", {}), "fired": 0})
	if spec.get("guardian", false):
		guardian[side] = true
	if spec.has("revive"):
		revive[side] = {"syn": name, "pct": float(spec["revive"]["pct"]), "delay": float(spec["revive"]["delay"])}


## 유닛의 시너지 (그림자 몬스터는 없음)
func _traits(u: Dictionary) -> Array:
	return [] if u.get("monster", false) else GameData.traits_of(u["aid"])


## 패시브·어사이드·애착의 능력치(mods)와 발동 효과(fx)를 붙인다
func _attach(u: Dictionary, spec: Dictionary) -> void:
	_add_static(u, spec.get("mods", {}))
	if spec.has("immune"):
		var im: Array = u.get("immune", []).duplicate()
		im.append_array(spec["immune"])
		u["immune"] = im
	for fx in spec.get("fx", []):
		var f: Dictionary = fx.duplicate(true)
		if f["t"] == "cond":
			u["conds"].append(f)
		else:
			f["k"] = u["fx"].size()
			u["fx"].append(f)


func _add_static(u: Dictionary, mods: Dictionary) -> void:
	for k in mods:
		if k == "start_shield":
			u["start_shield"] = u.get("start_shield", 0.0) + float(mods[k])
		else:
			u["mods"][k] = u["mods"].get(k, 0.0) + float(mods[k])


func _pers_of(u: Dictionary) -> String:
	var p: String = GameData.apostle(u["aid"]).get("personality", "")
	if p == "공명" or p == "이면":
		return u["pers"]
	return p


func _side_units(side: int) -> Array:
	var out := []
	for u in units:
		if u["side"] == side:
			out.append(u)
	return out


# ─────────────────────────────── 능력치 ───────────────────────────────

## 정적 mods + 버프 + 조건부 효과 합계 (%)
func mod(u: Dictionary, key: String, target = null) -> float:
	var v: float = u["mods"].get(key, 0.0)
	for b in u["buffs"]:
		if b["mods"].has(key):
			v += float(b["mods"][key]) * b["stacks"]
		if b.get("maxed", false) and b.get("max_bonus", {}).has(key):
			v += float(b["max_bonus"][key])
	for c in u["conds"]:
		if c["mods"].has(key) and _cond_ok(u, c["cond"], target):
			v += float(c["mods"][key])
	if key == "aspd" and u["status"].has("shock"):
		v -= 20.0
	if key == "heal_in" and u["status"].has("bitter"):
		v -= 50.0
	return v


func _cond_ok(u: Dictionary, cond: String, target) -> bool:
	var parts := cond.split(":")
	match parts[0]:
		"hp_full":
			return u.get("hp", 0.0) >= _raw_max_hp(u) - 0.01
		"hp_ge":
			return u.get("hp", 0.0) / _raw_max_hp(u) * 100.0 >= float(parts[1])
		"has_shield":
			return not u["shields"].is_empty()
		"hp_lt":
			return u.get("hp", 0.0) / _raw_max_hp(u) * 100.0 < float(parts[1])
		"vs_elem":
			return target != null and (target["status"].has("shock") or target["status"].has("burn"))
		"enemies_ge":
			return _alive_count(1 - u["side"]) >= int(parts[1])
		"enemies_eq":
			return _alive_count(1 - u["side"]) == int(parts[1])
		"no_enemy_died":
			return deaths[1 - u["side"]] == 0
		"vs_debuffed":
			return target != null and _has_debuff(target)
		"vs_status":
			return target != null and target["status"].has(parts[1])
		"time_lt":
			return time < float(parts[1])
		"time_ge":
			return time >= float(parts[1])
		"only_trait":
			# 살아 있는 아군이 모두 이 시너지 사도
			for a in _allies(u):
				if not _traits(a).has(parts[1]):
					return false
			return true
	return false


func _has_debuff(u: Dictionary) -> bool:
	if not u["status"].is_empty():
		return true
	for b in u["buffs"]:
		if b.get("debuff", false):
			return true
	return u["mods"].get("def", 0.0) < 0.0


## 조건부 효과를 뺀 최대 HP (조건 판정에서 재귀를 막기 위해 사용)
func _raw_max_hp(u: Dictionary) -> float:
	var v: float = u["mods"].get("hp", 0.0)
	for b in u["buffs"]:
		if b["mods"].has("hp"):
			v += float(b["mods"]["hp"]) * b["stacks"]
	return u["base"]["hp"] * maxf(0.1, 1.0 + v / 100.0)


func max_hp(u: Dictionary) -> float:
	return u["base"]["hp"] * maxf(0.1, 1.0 + mod(u, "hp") / 100.0)


func atk(u: Dictionary) -> float:
	var typed := "patk" if u["dtype"] == "physical" else "matk"
	return u["base"]["atk"] * maxf(0.1, 1.0 + (mod(u, "atk") + mod(u, typed)) / 100.0)


func defense(u: Dictionary, dtype: String) -> float:
	var typed := "pdef" if dtype == "physical" else "mdef"
	return u["base"]["def"] * maxf(0.0, 1.0 + (mod(u, "def") + mod(u, typed)) / 100.0)


func aspd(u: Dictionary) -> float:
	return maxf(0.2, u["base"]["aspd"] * (1.0 + mod(u, "aspd") / 100.0))


func _alive_count(side: int) -> int:
	var n := 0
	for u in units:
		if u["side"] == side and u["alive"] and not u.get("summon", false):
			n += 1
	return n


# ─────────────────────────────── 진행 ───────────────────────────────

func run() -> Dictionary:
	_emit("start", -1, -1, 0)
	for u in units:
		_emit_pos(u)
	# 전투 시작 효과
	for u in units:
		if u.get("start_shield", 0.0) > 0.0:
			_add_shield(u, u, max_hp(u) * u["start_shield"] / 100.0, 8.0, false)
		for f in u["fx"]:
			if f["t"] == "start":
				if f.get("delay", 0) > 0:
					u["counters"]["start_delay_%d" % f["k"]] = float(f["delay"])
				else:
					_run_actions(u, f["do"], null, {})
	var limit: float = B["battle_time_limit"]
	while time < limit:
		_tick_count += 1
		time = _tick_count * DT
		_tick_side()
		for u in units:
			if u["alive"]:
				_update_unit(u)
		if not _spawn_q.is_empty():
			units.append_array(_spawn_q)
			_spawn_q.clear()
		if _tick_count % 3 == 0:
			_emit_sp()
		var a := _alive_count(0)
		var b := _alive_count(1)
		if a == 0 or b == 0:
			break
	var a_alive := _alive_count(0)
	var b_alive := _alive_count(1)
	var winner := -1
	if a_alive > 0 and b_alive == 0:
		winner = 0
	elif b_alive > 0 and a_alive == 0:
		winner = 1
	var survivors := a_alive if winner == 0 else (b_alive if winner == 1 else 0)
	_emit("end", -1, -1, winner)
	return {"winner": winner, "survivors": survivors, "end_time": time, "events": events, "units": unit_snapshots(), "deaths": deaths.duplicate()}


## 진영 단위 주기 효과·부활
func _tick_side() -> void:
	for st in side_timers:
		st["t"] -= DT
		if st["t"] > 0.0:
			continue
		st["t"] += st["sec"]
		for u in units:
			if u["side"] == st["side"] and u["alive"] and _traits(u).has(st["syn"]):
				_run_actions(u, st["do"], null, {})
				st["fired"] = int(st["fired"]) + 1
				if int(st["fired"]) == 1 and not st["first_do"].is_empty():
					_run_actions(u, st["first_do"], null, {})
				if not st["n_then"].is_empty() and int(st["fired"]) == int(st["n_then"]["n"]):
					_run_actions(u, st["n_then"]["do"], null, {})
				break
	var keep := []
	for r in pending_revive:
		if time >= r["at"]:
			var u: Dictionary = units[r["i"]]
			u["alive"] = true
			u["status"] = {}
			u["buffs"] = []
			u["shields"] = []
			u["hp"] = max_hp(u) * r["pct"] / 100.0
			deaths[u["side"]] -= 1
			_emit("revive", u["i"], u["i"], 0, "", u["hp"], 0.0)
		else:
			keep.append(r)
	pending_revive = keep


func unit_snapshots() -> Array:
	var out := []
	for u in units:
		if u.get("summon", false):
			continue   # 소환물은 전투 중 "summon" 이벤트로 나타남
		out.append(_snapshot(u))
	return out


func _snapshot(u: Dictionary) -> Dictionary:
	return {"i": u["i"], "side": u["side"], "aid": u["aid"], "name": u["name"], "star": u["star"],
		"row": u["row"], "slot": u["slot"], "max_hp": max_hp(u), "pers": u["pers"], "monster": u["monster"],
		"summon": u.get("summon", false), "scale": u.get("scale", 1.0)}


var _spawn_q: Array = []


func _update_unit(u: Dictionary) -> void:
	var whole_second := _tick_count % 10 == 0
	# 소환물: 시간이 다 되면 사라짐
	if u.get("summon", false):
		u["life"] = float(u["life"]) - DT
		if u["life"] <= 0.0:
			u["alive"] = false
			u["hp"] = 0.0
			_emit("death", u["i"], u["i"], 0)
			return
	u["cc_immune"] = maxf(0.0, float(u.get("cc_immune", 0.0)) - DT)
	# 시간 경과
	u["invuln"] = maxf(0.0, u["invuln"] - DT)
	u["untarget"] = maxf(0.0, u["untarget"] - DT)
	u["taunt"] = maxf(0.0, u["taunt"] - DT)
	for k in u["cds"].keys():
		u["cds"][k] -= DT
	_expire(u)
	# 지연된 전투 시작 효과
	for key in u["counters"].keys():
		if String(key).begins_with("start_delay_"):
			u["counters"][key] -= DT
			if u["counters"][key] <= 0.0:
				var idx := int(String(key).trim_prefix("start_delay_"))
				u["counters"].erase(key)
				_run_actions(u, u["fx"][idx]["do"], null, {})
	# 상태이상 / 재생 (1초마다)
	if whole_second:
		_tick_status(u)
		if not u["alive"]:
			return
		var regen := mod(u, "regen")
		for r in u["regens"]:
			regen += r["pct"]
		if regen > 0.0:
			_heal(u, u, max_hp(u) * regen / 100.0, false)
		for f in u["fx"]:
			if f["t"] == "per_sec":
				_run_actions(u, f["do"], null, {})
	for f in u["fx"]:
		if f["t"] == "interval":
			var key := "iv_%d" % f["k"]
			u["counters"][key] = float(u["counters"].get(key, float(f.get("from", f["sec"])))) - DT
			if u["counters"][key] <= 0.0:
				u["counters"][key] += 1e9 if f.get("once", false) else float(f["sec"])
				_run_actions(u, f["do"], null, {})
	if u["status"].has("stun") or u["status"].has("freeze"):
		return
	# SP
	u["sp"] += float(B["sp_regen"]) * maxf(0.0, 1.0 + mod(u, "sp_regen") / 100.0) * DT
	var target = _nearest(u)
	if target == null:
		return
	var silenced: bool = u["status"].has("silence")
	# 고학년 스킬 (재사용 대기시간) — 침묵 중에는 쓰지 못함
	u["senior_timer"] -= DT
	if u["senior_timer"] <= 0.0 and silenced:
		u["senior_timer"] = 0.0
	elif u["senior_timer"] <= 0.0:
		u["senior_timer"] = float(u.get("senior_cd", B["senior_cooldown"]))
		_cast(u, "senior")
		return
	# 저학년 스킬 (SP)
	if u["sp"] >= float(B["sp_max"]) and not silenced:
		u["sp"] = 0.0
		_cast(u, "fresh")
		return
	# 사거리 밖이면 다가간다
	if _reach(u, target) > u["range"] + 0.01:
		_move_toward(u, target)
		return
	if u.get("moving", false):
		u["moving"] = false
		_emit_pos(u)
	# 일반 공격
	u["atk_timer"] -= DT
	if u["atk_timer"] <= 0.0:
		u["atk_timer"] = 1.0 / aspd(u)
		_normal_attack(u, target)


# ─────────────────────────────── 이동 ───────────────────────────────

func _dist(a: Dictionary, b: Dictionary) -> float:
	return Vector2(a["x"], a["y"]).distance_to(Vector2(b["x"], b["y"]))


## 공격 거리: 두 사도 사이의 실제 거리 (사거리 원 안에 들어오면 공격)
func _reach(a: Dictionary, b: Dictionary) -> float:
	return Vector2(a["x"], a["y"]).distance_to(Vector2(b["x"], b["y"]))


## 전장 크기 (가로: 양 진영 끝에서 끝, 세로: 3줄)
static func field_size() -> Vector2:
	var mv: Dictionary = GameData.balance["move"]
	return Vector2(float(mv["field_w"]), 1.4 + 2.0 * float(mv["slot_h"]))


## 배치 칸 → 처음 위치. 왼쪽 진영(0)은 왼쪽 끝에서, 오른쪽 진영(1)은 오른쪽 끝에서 시작
static func start_xy(side: int, row: int, slot: int) -> Vector2:
	var mv: Dictionary = GameData.balance["move"]
	var x := float(mv["margin"]) + (2 - row) * float(mv["col_w"])
	if side == 1:
		x = float(mv["field_w"]) - x
	return Vector2(x, 0.7 + slot * float(mv["slot_h"]))


## 목표: 도발 중인 적 우선, 그다음 공격 거리가 가장 가까운 적 (앞줄부터 맞붙음)
func _nearest(u: Dictionary) -> Variant:
	# 혼란: 공격 대상이 무작위 (아군일 수도) — 혼란이 걸릴 때 한 번 정해 둔다
	if u["status"].has("confuse"):
		var ct = u.get("confuse_t", null)
		if ct == null or not ct["alive"]:
			var all := []
			for e in units:
				if e != u and e["alive"] and _targetable(e):
					all.append(e)
			ct = all[rng.randi() % all.size()] if not all.is_empty() else null
			u["confuse_t"] = ct
		if ct != null:
			return ct
	elif u.has("confuse_t"):
		u.erase("confuse_t")
	var best = null
	var best_d := INF
	var taunting := false
	for e in units:
		if e["side"] == u["side"] or not _targetable(e):
			continue
		var t: bool = e["taunt"] > 0.0 and not u.get("immune", []).has("taunt")
		if taunting and not t:
			continue
		var d := _reach(u, e)
		if (t and not taunting) or d < best_d - 0.0001:
			best = e
			best_d = d
			taunting = taunting or t
	return best


## 목표 적을 향해 곧장(대각선·위아래 포함) 걸어가 사거리에 들어오면 멈춘다.
## 다른 사도와 몸이 겹치면 옆으로 밀려나 비켜 선다 (아군끼리는 spacing, 적과는 body 간격).
func _move_toward(u: Dictionary, target: Dictionary) -> void:
	var mv: Dictionary = B["move"]
	var p := Vector2(u["x"], u["y"])
	var goal := Vector2(target["x"], target["y"])
	var d := p.distance_to(goal)
	var step := minf(float(mv["speed"]) * DT, d - float(u["range"]))
	if step <= 0.0 or d < 0.001:
		return
	var dir := (goal - p) / d
	var np := p + dir * step
	# 몸 겹침 풀기: 가까운 사도에게서 밀려나되, 목표 쪽으로 가는 성분은 남긴다
	for o in units:
		if o == u or not o["alive"]:
			continue
		var q := Vector2(o["x"], o["y"])
		var gap := float(mv["spacing"]) if o["side"] == u["side"] else float(mv["body"])
		var off := np - q
		var dist := off.length()
		if dist < gap:
			var push := off / dist if dist > 0.001 else Vector2(0, 1 if u["i"] % 2 == 0 else -1)
			# 정면으로 막히면 옆(위/아래)으로 비켜 돌아간다
			if push.dot(dir) < -0.7:
				push = Vector2(-dir.y, dir.x) * (1.0 if (u["i"] + int(o["i"])) % 2 == 0 else -1.0)
			np += push * (gap - dist) * 0.6
	var fs := field_size()
	np.x = clampf(np.x, 0.2, fs.x - 0.2)
	np.y = clampf(np.y, 0.3, fs.y - 0.3)
	if np.distance_to(p) < 0.0005:
		return
	u["x"] = np.x
	u["y"] = np.y
	u["moving"] = true
	if _tick_count % 2 == 0:
		_emit_pos(u)


## SP 막대 표시용: 10칸 단위로 바뀔 때만 기록 (연출 전용, 계산에는 영향 없음)
func _emit_sp() -> void:
	var mx := float(B["sp_max"])
	for u in units:
		if not u["alive"] or u.get("summon", false):
			continue
		var b := clampi(int(float(u["sp"]) / mx * 10.0), 0, 10)
		if b != int(u.get("spb", -1)):
			u["spb"] = b
			_emit("sp", u["i"], -1, b)


func _emit_pos(u: Dictionary) -> void:
	_emit("pos", u["i"], -1, [snappedf(u["x"], 0.01), snappedf(u["y"], 0.01)])


func _expire(u: Dictionary) -> void:
	var keep := []
	for b in u["buffs"]:
		if b["until"] > time:
			keep.append(b)
	u["buffs"] = keep
	var sh := []
	for s in u["shields"]:
		if s["until"] > time and s["amt"] > 0.0:
			sh.append(s)
	u["shields"] = sh
	for k in u["status"].keys():
		if u["status"][k]["until"] <= time:
			u["status"].erase(k)
	var rg := []
	for r in u["regens"]:
		if r["until"] > time:
			rg.append(r)
	u["regens"] = rg


func _tick_status(u: Dictionary) -> void:
	for s in ["burn", "bitter", "poison"]:
		if u["status"].has(s):
			var st: Dictionary = u["status"][s]
			var src: Dictionary = units[st["src"]]
			var pct: float = {"burn": 20.0, "bitter": 10.0, "poison": 15.0}[s]
			var amt := atk(src) * pct / 100.0 * (1.0 + mod(src, "status_dmg") / 100.0)
			_apply_damage(src, u, amt, "status", false)
			if not u["alive"]:
				return


# ─────────────────────────────── 타겟 ───────────────────────────────

func _targetable(u: Dictionary) -> bool:
	return u["alive"] and u["untarget"] <= 0.0


## mode: "front"(가장 앞 열), "back"(가장 뒤 열), "low"(HP 비율 최저)
func _pick_target(u: Dictionary, mode: String) -> Variant:
	var enemies := []
	for e in units:
		if e["side"] != u["side"] and _targetable(e):
			enemies.append(e)
	if enemies.is_empty():
		return null
	for e in enemies:
		if e["taunt"] > 0.0 and mode == "front":
			return e
	match mode:
		"low":
			var best = enemies[0]
			for e in enemies:
				if e["hp"] / max_hp(e) < best["hp"] / max_hp(best):
					best = e
			return best
		"back":
			var best_row := -1
			for e in enemies:
				best_row = maxi(best_row, e["row"])
			return _closest_slot(enemies, best_row, u["slot"])
		_:
			var best_row := 99
			for e in enemies:
				best_row = mini(best_row, e["row"])
			return _closest_slot(enemies, best_row, u["slot"])


func _closest_slot(enemies: Array, row: int, slot: int) -> Variant:
	var best = null
	var best_d := 99
	for e in enemies:
		if e["row"] != row:
			continue
		var d: int = abs(e["slot"] - slot)
		if d < best_d:
			best_d = d
			best = e
	return best


func _enemies_in_row(u: Dictionary, row: int) -> Array:
	var out := []
	for e in units:
		if e["side"] != u["side"] and e["alive"] and e["row"] == row:
			out.append(e)
	return out


func _allies(u: Dictionary, include_self: bool = true) -> Array:
	var out := []
	for a in units:
		if a["side"] == u["side"] and a["alive"] and (include_self or a != u):
			out.append(a)
	return out


func _lowest_ally(u: Dictionary) -> Variant:
	var best = null
	for a in _allies(u):
		if best == null or a["hp"] / max_hp(a) < best["hp"] / max_hp(best):
			best = a
	return best


# ─────────────────────────────── 행동 ───────────────────────────────

func _normal_attack(u: Dictionary, target: Dictionary) -> void:
	u["n_attacks"] += 1
	var enh_every: int = maxi(2, int(B["enhanced_every"]) - int(mod(u, "enh_freq")))
	var kind := "enh" if u["n_attacks"] % enh_every == 0 else "normal"
	var mult := float(B["enhanced_mult"]) * 100.0 if kind == "enh" else 100.0
	# "n번째 공격마다 치명타" 류 (pre)
	for f in u["fx"]:
		if f["t"] == "normal_n" and f.get("pre", false):
			if (u["n_normal_hits"] + 1) % int(f["n"]) == 0:
				_run_actions(u, f["do"], target, {})
	var opts := {}
	if not u["pending_normal"].is_empty():
		opts["pending"] = u["pending_normal"]
		u["pending_normal"] = []
	# 장난감 망원경
	for f in u["fx"]:
		if f["t"] == "telescope":
			var frac := float(u["row"] + target["row"]) / 4.0
			var key := "normal" if kind == "normal" else "enh"
			var bonus := lerpf(float(f[key + "_min"]), float(f[key + "_max"]), frac)
			if kind == "normal" and u["eldyne"]:
				bonus *= 2.0
			opts["bonus"] = opts.get("bonus", 0.0) + bonus
	u["sp"] += float(B["sp_per_attack"])
	_emit("attack", u["i"], target["i"], 1 if kind == "enh" else 0)
	if target["status"].has("blind") and rng.randf() < 0.5:
		_emit("miss", u["i"], target["i"], 0)
		return
	var dealt := deal(u, target, mult, kind, opts)
	if dealt <= 0.0:
		return
	u["n_normal_hits"] += 1
	# 강화 공격 추가 효과 (사도별)
	if kind == "enh" and u["sk"].has("enh") and target["alive"]:
		_skill_do(u, u["sk"]["enh"], 1.0, target)
	# 주변 적에게 튀는 공격 (splash %)
	var splash := mod(u, "splash")
	if splash > 0.0:
		for e in _enemies_in_row(u, target["row"]):
			if e != target and absi(int(e["slot"]) - int(target["slot"])) == 1:
				deal(u, e, mult * splash / 100.0, "extra", {})
	# 일반 공격 적중 효과
	for f in u["fx"]:
		match f["t"]:
			"normal_hit":
				if not _ready(u, f):
					continue
				if f.has("chance") and rng.randf() * 100.0 >= float(f["chance"]):
					continue
				_mark(u, f)
				_run_actions(u, f["do"], target, {"dealt": dealt})
			"normal_n":
				if f.get("pre", false):
					continue
				if u["n_normal_hits"] % int(f["n"]) == 0 and _ready(u, f):
					_mark(u, f)
					_run_actions(u, f["do"], target, {"dealt": dealt})
	# 대기 중이던 다음 일반 공격 효과
	for p in opts.get("pending", []):
		if p.has("extra") and target["alive"]:
			deal(u, target, float(p["extra"]), "extra", {})
		if p.has("stun") and target["alive"]:
			_add_status(u, target, "stun", float(p["stun"]))
		if p.has("status") and target["alive"]:
			_add_status(u, target, p["status"]["s"], float(p["status"]["dur"]))
		if p.has("row_status"):
			for e in _enemies_in_row(u, target["row"]):
				_add_status(u, e, p["row_status"]["s"], float(p["row_status"]["dur"]))


func _cast(u: Dictionary, which: String) -> void:
	var a := GameData.apostle(u["aid"])
	var sname: String = a.get("skills", {}).get(which, {}).get("name", "")
	if not _HANGUL.search(sname):
		sname = "저학년 스킬" if which == "fresh" else "고학년 스킬"
	_emit("skill", u["i"], -1, 0 if which == "fresh" else 1, sname)
	var p: float = u["power"]
	if u["sk"].has(which):
		_after_cast(u, which, _skill_do(u, u["sk"][which], p))
		return
	var row: String = a.get("row", "mid")
	if row == "all":
		row = GameData.ROWS[u["row"]]
	var hit_targets := []
	match u["role"]:
		"dealer":
			if which == "fresh":
				match row:
					"front":
						var t = _pick_target(u, "front")
						if t != null:
							hit_targets = _enemies_in_row(u, t["row"])
							for e in hit_targets:
								deal(u, e, 200.0 * p, which, {})
					"mid":
						var t = _pick_target(u, "front")
						if t != null:
							hit_targets = [t]
							deal(u, t, 350.0 * p, which, {})
					_:
						var t = _pick_target(u, "back")
						if t != null:
							hit_targets = [t]
							deal(u, t, 300.0 * p, which, {})
			else:
				match row:
					"front":
						for e in units:
							if e["side"] != u["side"] and e["alive"]:
								hit_targets.append(e)
						for e in hit_targets:
							deal(u, e, 150.0 * p, which, {})
					"mid":
						var t = _pick_target(u, "front")
						if t != null:
							hit_targets = _enemies_in_row(u, t["row"])
							for e in hit_targets:
								deal(u, e, 220.0 * p, which, {})
					_:
						var t = _pick_target(u, "low")
						if t != null:
							hit_targets = [t]
							deal(u, t, 480.0 * p, which, {})
		"tank":
			if which == "fresh":
				_add_shield(u, u, max_hp(u) * 0.30 * p, 5.0, true)
				u["taunt"] = 3.0
				_emit("buff", u["i"], u["i"], 0, "도발")
			else:
				var t = _pick_target(u, "front")
				if t != null:
					hit_targets = _enemies_in_row(u, t["row"])
					for e in hit_targets:
						deal(u, e, 130.0 * p, which, {})
						if e["alive"]:
							_add_status(u, e, "stun", 1.5)
				_add_buff(u, u, {"dmg_taken": -30}, 5.0, "tank_senior", 1, false)
		"support":
			if which == "fresh":
				var t = _lowest_ally(u)
				if t != null:
					_heal(u, t, atk(u) * 2.6 * p, true)
			else:
				for al in _allies(u):
					_heal(u, al, atk(u) * 1.1 * p, true)
					_add_buff(u, al, {"dmg": 20 * p}, 6.0, "support_senior", 1, false)
	_after_cast(u, which, hit_targets)


## 스킬 적중·사용 발동 효과
func _after_cast(u: Dictionary, which: String, hit_targets: Array) -> void:
	for e in hit_targets:
		for f in u["fx"]:
			if f["t"] == "skill_hit" and (not f.has("which") or f["which"] == which):
				_run_actions(u, f["do"], e, {})
	# 스킬 사용 효과
	u["n_skills"] = int(u.get("n_skills", 0)) + 1
	for f in u["fx"]:
		if f["t"] == "skill" and (f["which"] == "any" or f["which"] == which):
			_run_actions(u, f["do"], null, {})
		elif f["t"] == "skill_n" and int(u["n_skills"]) % int(f["n"]) == 0 and (not f.get("once", false) or int(u["n_skills"]) == int(f["n"])):
			_run_actions(u, f["do"], null, {})


# ─────────────────────────────── 피해 / 회복 ───────────────────────────────

## 피해 계산 후 적용. kind: normal / enh / fresh / senior / extra / status / reflect
func deal(src: Dictionary, dst: Dictionary, mult_pct: float, kind: String, opts: Dictionary) -> float:
	if not dst["alive"] or not src["alive"] and kind != "status" and not opts.get("dead_ok", false):
		return 0.0
	var raw := atk(src) * mult_pct / 100.0
	var dm := mod(src, "dmg", dst) + mod(src, "dmg_out", dst)
	if kind == "normal" or kind == "enh":
		dm += mod(src, "normal_dmg", dst)
	if kind == "enh":
		dm += mod(src, "enh_dmg", dst)
	if kind == "fresh" or kind == "senior":
		dm += mod(src, "skill_dmg", dst) + mod(src, kind + "_dmg", dst)
	if src["dtype"] == "magic":
		dm += mod(src, "magic_dmg", dst)
	dm += float(opts.get("bonus", 0.0))
	for p in opts.get("pending", []):
		dm += float(p.get("bonus", 0.0))
	var amt := raw * maxf(0.0, 1.0 + dm / 100.0)
	# 방어력
	var d := defense(dst, src["dtype"])
	amt *= 100.0 / (100.0 + d)
	# 받는 피해
	var taken := mod(dst, "dmg_taken")
	if kind == "normal" or kind == "enh":
		taken += mod(dst, "dmg_taken_normal")
	amt *= maxf(0.1, 1.0 + taken / 100.0)
	# 치명타
	var crit := false
	if kind != "status" and kind != "reflect":
		var chance := float(B["base_crit"]) * (1.0 + mod(src, "crit", dst) / 100.0) / (1.0 + maxf(0.0, mod(dst, "critres")) / 100.0)
		if src["force_crit"] or rng.randf() < chance:
			crit = true
			src["force_crit"] = false
			var cm := float(B["base_critdmg"]) * (1.0 + mod(src, "critdmg", dst) / 100.0) / (1.0 + maxf(0.0, mod(dst, "critdmgres")) / 100.0)
			cm = maxf(1.0, cm) * (1.0 + mod(src, "crit_final") / 100.0) * maxf(0.1, 1.0 + mod(dst, "crit_dmg_taken") / 100.0)
			amt *= cm
	amt = maxf(1.0, round(amt))
	return _apply_damage(src, dst, amt, kind, crit)


func _apply_damage(src: Dictionary, dst: Dictionary, amt: float, kind: String, crit: bool) -> float:
	if not dst["alive"]:
		return 0.0
	if dst["invuln"] > 0.0:
		_emit("immune", src["i"], dst["i"], 0)
		return 0.0
	var left := amt
	for s in dst["shields"]:
		var take := minf(s["amt"], left)
		s["amt"] -= take
		left -= take
		if left <= 0.0:
			break
	dst["hp"] -= left
	dst["damaged_by"][src["i"]] = time
	_emit("dmg", src["i"], dst["i"], amt, kind + ("!" if crit else ""), maxf(0.0, dst["hp"]), _shield_total(dst))
	var direct := kind != "status" and kind != "reflect"
	if direct:
		dst["sp"] += float(B["sp_per_hit_taken"])
		dst["n_hits_taken"] += 1
		if kind == "fresh" or kind == "senior":
			src["n_skill_hits"] += 1
			for f in src["fx"]:
				if f["t"] == "skill_hits_n" and src["n_skill_hits"] % int(f["n"]) == 0 and dst["alive"]:
					_run_actions(src, f["do"], dst, {})
	if dst["hp"] <= 0.0 and guardian[dst["side"]]:
		# 세계수의 가호: 처음 쓰러질 아군을 HP 1로 버티게 함
		guardian[dst["side"]] = false
		dst["hp"] = 1.0
		dst["invuln"] = maxf(dst["invuln"], 1.5)
		_emit("buff", dst["i"], dst["i"], 0, "세계수의 가호")
	if dst["hp"] <= 0.0:
		_kill(src, dst)
		return amt
	# 빙결: 다시 공격받으면 깨지며 추가 피해
	if direct and dst["status"].has("freeze") and src["side"] != dst["side"]:
		var fz: Dictionary = dst["status"]["freeze"]
		dst["status"].erase("freeze")
		var caster: Dictionary = units[fz["src"]]
		if caster["alive"]:
			deal(caster, dst, 80.0, "extra", {})
		if not dst["alive"]:
			return amt
	# 같은 열 반격 (뜨거운 도시)
	if direct and kind != "counter" and src["alive"] and src["side"] != dst["side"]:
		for m in units:
			if m["alive"] and m["side"] == dst["side"] and m["row"] == dst["row"] and m.has("row_counter"):
				if rng.randf() * 100.0 < float(m["row_counter"]["chance"]):
					deal(m, src, float(m["row_counter"]["pct"]), "counter", {})
					break
	# 피격 효과
	for f in dst["fx"]:
		match f["t"]:
			"damaged":
				if _ready(dst, f):
					_mark(dst, f)
					_run_actions(dst, f["do"], src, {})
			"hits_taken_n":
				if direct and dst["n_hits_taken"] % int(f["n"]) == 0:
					_run_actions(dst, f["do"], src, {})
			"hp_below":
				var key := "hpb_%d" % f["k"]
				if not dst["once"].has(key) and dst["hp"] / max_hp(dst) * 100.0 <= float(f["pct"]):
					dst["once"][key] = true
					_run_actions(dst, f["do"], src, {})
	return amt


func _kill(src: Dictionary, dst: Dictionary) -> void:
	dst["alive"] = false
	dst["hp"] = 0.0
	_emit("death", src["i"], dst["i"], 0)
	if dst.get("summon", false):
		return   # 소환물은 처치 수·쓰러짐 효과에 넣지 않음
	deaths[dst["side"]] += 1
	# 쓰러질 때 효과 / 아군이 쓰러졌을 때 효과
	for f in dst["fx"]:
		if f["t"] == "death_self":
			if f.get("first_only", false) and int(deaths[dst["side"]]) != 1:
				continue   # 그 진영에서 처음 쓰러진 사도만 (마지막 불꽃)
			_run_actions(dst, f["do"], src, {"dead_ok": true})
	for u in units:
		if u["alive"] and u["side"] == dst["side"]:
			for f in u["fx"]:
				if f["t"] == "ally_death":
					_run_actions(u, f["do"], dst, {})
	for u in units:
		if not u["alive"]:
			continue
		for f in u["fx"]:
			if f["t"] == "any_death":
				_run_actions(u, f["do"], dst, {})
			elif f["t"] == "last_of_trait" and u["side"] == dst["side"] and _traits(dst).has(String(f["syn"])) and not u["once"].has("last_%d" % f["k"]):
				var left := 0
				for a in _allies(u):
					if _traits(a).has(String(f["syn"])):
						left += 1
				if left == 1:
					u["once"]["last_%d" % f["k"]] = true
					_run_actions(u, f["do"], null, {})
	# 유령 늪: 처음 쓰러진 시너지 사도 부활
	var rv: Dictionary = revive[dst["side"]]
	if not rv.is_empty() and _traits(dst).has(rv["syn"]):
		revive[dst["side"]] = {}
		pending_revive.append({"i": dst["i"], "at": time + rv["delay"], "pct": rv["pct"]})
	for u in units:
		if not u["alive"] or u["side"] == dst["side"]:
			continue
		for f in u["fx"]:
			if f["t"] != "kill":
				continue
			var ok: bool = u == src
			if not ok and f.get("assist", false):
				ok = dst["damaged_by"].has(u["i"]) and time - float(dst["damaged_by"][u["i"]]) <= 3.0
			if ok:
				_run_actions(u, f["do"], dst, {})


func _heal(src: Dictionary, dst: Dictionary, amt: float, from_skill: bool, overflow_shield: float = 0.0) -> void:
	if not dst["alive"]:
		return
	var v := amt * maxf(0.0, 1.0 + mod(src, "heal_out") / 100.0) * maxf(0.0, 1.0 + mod(dst, "heal_in") / 100.0)
	if dst["status"].has("poison"):
		v *= 0.7   # 중독: 받는 회복 -30%
	var mh := max_hp(dst)
	var over := maxf(0.0, dst["hp"] + v - mh)
	dst["hp"] = minf(mh, dst["hp"] + v)
	_emit("heal", src["i"], dst["i"], round(v), "", dst["hp"], _shield_total(dst))
	if overflow_shield > 0.0 and over > 0.0:
		_add_shield(src, dst, over, overflow_shield, false)
	if from_skill:
		for f in src["fx"]:
			if f["t"] == "heal_given":
				_run_actions(src, f["do"], dst, {})


func _add_shield(src: Dictionary, dst: Dictionary, amt: float, dur: float, from_skill: bool) -> void:
	var v := amt * maxf(0.0, 1.0 + mod(src, "shield_out") / 100.0) * maxf(0.0, 1.0 + mod(dst, "shield_in") / 100.0)
	dst["shields"].append({"amt": v, "until": time + dur})
	_emit("shield", src["i"], dst["i"], round(v), "", dst["hp"], _shield_total(dst))
	if from_skill:
		for f in src["fx"]:
			if f["t"] == "shield_given":
				_run_actions(src, f["do"], dst, {})


func _add_buff(src: Dictionary, dst: Dictionary, mods: Dictionary, dur: float, key: String, max_stack: int, debuff: bool, max_bonus: Dictionary = {}) -> void:
	if key == "":
		_uid_buff += 1
		key = "b%d" % _uid_buff
	for b in dst["buffs"]:
		if b["key"] == key:
			b["until"] = time + dur
			b["stacks"] = mini(b["stacks"] + 1, max_stack)
			b["maxed"] = b["stacks"] >= max_stack and max_stack > 1
			return
	dst["buffs"].append({"key": key, "mods": mods, "until": time + dur, "stacks": 1, "debuff": debuff,
		"max_bonus": max_bonus, "maxed": max_stack == 1 and not max_bonus.is_empty()})


func _add_status(src: Dictionary, dst: Dictionary, s: String, dur: float) -> void:
	if not dst["alive"]:
		return
	if dst["invuln"] > 0.0 and (s == "stun" or s == "freeze"):
		return
	# 면역: 상태 이상 면역 시간(cc_immune) 또는 사도 고유 면역(immune 목록)
	if (float(dst.get("cc_immune", 0.0)) > 0.0 and s in ["stun", "freeze", "silence", "blind", "confuse"]) or dst.get("immune", []).has(s):
		_emit("resist", src["i"], dst["i"], 0, s)
		return
	dst["status"][s] = {"until": time + dur, "src": src["i"]}
	_emit("status", src["i"], dst["i"], dur, s)
	for f in src["fx"]:
		if f["t"] == "status_inflict":
			_run_actions(src, f["do"], dst, {})
	if s == "stun":
		for f in dst["fx"]:
			if f["t"] == "stunned" and _ready(dst, f):
				_mark(dst, f)
				_run_actions(dst, f["do"], src, {})


func _ready(u: Dictionary, f: Dictionary) -> bool:
	var key := "cd_%d" % f["k"]
	if f.get("once", false) and u["once"].has(key):
		return false
	return u["cds"].get(key, 0.0) <= 0.0


func _mark(u: Dictionary, f: Dictionary) -> void:
	var key := "cd_%d" % f["k"]
	if f.has("cd"):
		u["cds"][key] = float(f["cd"])
	if f.get("once", false):
		u["once"][key] = true


# ─────────────────────────────── 효과 실행 ───────────────────────────────

func _resolve_to(u: Dictionary, to: String, target, trait_name: String = "") -> Array:
	match to:
		"self":
			return [u]
		"row":
			var out := []
			for a in _allies(u):
				if a["row"] == u["row"]:
					out.append(a)
			return out
		"allies":
			return _allies(u)
		"lowest":
			var lo = _lowest_ally(u)
			return [lo] if lo != null else []
		"enemies":
			var out := []
			for e in units:
				if e["side"] != u["side"] and e["alive"]:
					out.append(e)
			return out
		"trait":
			var out := []
			for a in _allies(u):
				if _traits(a).has(String(trait_name)):
					out.append(a)
			return out
		"target":
			return [target] if target != null and target["alive"] else []
		"random_enemy":
			var es := []
			for e in units:
				if e["side"] != u["side"] and e["alive"] and not e.get("summon", false):
					es.append(e)
			return [es[rng.randi() % es.size()]] if not es.is_empty() else []
		"lowest_enemy":
			var lo = null
			for e in units:
				if e["side"] != u["side"] and e["alive"] and (lo == null or e["hp"] < lo["hp"]):
					lo = e
			return [lo] if lo != null else []
		"high_atk_ally":
			var hi = null
			for a in _allies(u):
				if hi == null or atk(a) > atk(hi):
					hi = a
			return [hi] if hi != null else []
		"summons":
			var out := []
			for a in _allies(u):
				if a.get("summon", false) and int(a.get("owner", -1)) == int(u["i"]):
					out.append(a)
			return out
		"debuffed_ally":
			for a in _allies(u):
				if _has_debuff(a):
					return [a]
			var lo2 = _lowest_ally(u)
			return [lo2] if lo2 != null else []
	return [u]


func _run_actions(u: Dictionary, actions: Array, target, ctx: Dictionary) -> void:
	for act in actions:
		if not u["alive"] and act["a"] != "debuff" and not ctx.get("dead_ok", false):
			return
		match act["a"]:
			"buff":
				for d in _resolve_to(u, act.get("to", "self"), target, act.get("trait", "")):
					_add_buff(u, d, act["mods"], float(act["dur"]), act.get("key", ""), int(act.get("stack", 1)), false, act.get("max_bonus", {}))
					_emit("buff", u["i"], d["i"], 0, GameData.artifact(act.get("key", "")).get("name", ""))
			"debuff":
				for d in _resolve_to(u, act.get("to", "target"), target, act.get("trait", "")):
					_add_buff(u, d, act["mods"], float(act["dur"]), act.get("key", ""), int(act.get("stack", 1)), true)
			"clear_buff":
				var keep := []
				for b in u["buffs"]:
					if b["key"] != act["key"]:
						keep.append(b)
				u["buffs"] = keep
			"shield":
				for d in _resolve_to(u, act.get("to", "self"), target, act.get("trait", "")):
					_add_shield(u, d, max_hp(d) * float(act["pct"]) / 100.0, float(act["dur"]), false)
			"heal":
				for d in _resolve_to(u, act.get("to", "self"), target, act.get("trait", "")):
					_heal(u, d, max_hp(d) * float(act["pct"]) / 100.0, false, float(act.get("overflow_shield", 0.0)))
			"lifesteal":
				_heal(u, u, float(ctx.get("dealt", 0.0)) * float(act["pct"]) / 100.0, false)
			"regen":
				u["regens"].append({"pct": float(act["pct"]), "until": time + float(act["dur"])})
			"invuln":
				u["invuln"] = maxf(u["invuln"], float(act["dur"]))
				_emit("buff", u["i"], u["i"], 0, "무적")
			"untarget":
				u["untarget"] = maxf(u["untarget"], float(act["dur"]))
				_emit("buff", u["i"], u["i"], 0, "타겟 해제")
			"taunt":
				u["taunt"] = maxf(float(u["taunt"]), float(act["dur"]))
				_emit("buff", u["i"], u["i"], 0, "도발")
			"extra":
				if target != null and target["alive"]:
					deal(u, target, float(act["pct"]), "extra", {})
			"status":
				for d in _resolve_to(u, act.get("to", "target"), target, act.get("trait", "")):
					_add_status(u, d, act["s"], float(act["dur"]))
			"next_normal":
				u["pending_normal"].append(act)
			"crit_now":
				u["force_crit"] = true
			"sp":
				u["sp"] += float(act["amt"])
			"sp_pct":
				u["sp"] += float(B["sp_max"]) * float(act["pct"]) / 100.0
			"cleanse":
				for d in _resolve_to(u, act.get("to", "self"), target, act.get("trait", "")):
					_cleanse(d)
			"dispel":
				for d in _resolve_to(u, act.get("to", "enemies"), target, act.get("trait", "")):
					_dispel(d)
			"cd":
				for d in _resolve_to(u, act.get("to", "self"), target, act.get("trait", "")):
					d["senior_timer"] = maxf(0.0, float(d["senior_timer"]) + float(act["sec"]))
			"cc_immune":
				u["cc_immune"] = maxf(float(u.get("cc_immune", 0.0)), float(act["dur"]))
				_emit("buff", u["i"], u["i"], 0, "상태 이상 면역")
			"summon":
				_summon(u, act)
			"break_shield":
				if target != null and not target["shields"].is_empty():
					target["shields"].pop_front()
			"execute":
				if target != null and target["alive"] and target["hp"] / max_hp(target) * 100.0 <= float(act["below"]) and target["invuln"] <= 0.0:
					_emit("execute", u["i"], target["i"], 0)
					_kill(u, target)
			"status_rand":
				var choices: Array = act["s"]
				for d in _resolve_to(u, act.get("to", "target"), target, act.get("trait", "")):
					_add_status(u, d, choices[rng.randi() % choices.size()], float(act["dur"]))
			"shield_atk":
				for d in _resolve_to(u, act.get("to", "self"), target, act.get("trait", "")):
					_add_shield(u, d, atk(u) * float(act["pct"]) / 100.0, float(act["dur"]), false)
			"strike":
				var t = _pick_target(u, act.get("mode", "back"))
				if t != null:
					deal(u, t, float(act["pct"]), "extra", {})
			"buff_rand":
				# 무작위 버프 n개 (같은 것은 겹치지 않게): choices 중에서 골라 mult 배
				var ch: Array = act["choices"].duplicate()
				var mult := float(act.get("mult", 1.0))
				for k in mini(int(act.get("n", 1)), ch.size()):
					var pick: Dictionary = ch[rng.randi() % ch.size()]
					ch.erase(pick)
					var mm := {}
					for key in pick:
						mm[key] = float(pick[key]) * mult
					for d in _resolve_to(u, act.get("to", "self"), target, act.get("trait", "")):
						_add_buff(u, d, mm, float(act.get("dur", 999)), "show_%d" % k, 1, false)
			"wave":
				# 적 전체에 시전자 공격력의 pct% 피해 (파도)
				for e in units.duplicate():
					if e["side"] != u["side"] and e["alive"]:
						deal(u, e, float(act["pct"]), "extra", {"dead_ok": ctx.get("dead_ok", false)})
			"extra_maxhp":
				if target != null and target["alive"]:
					_apply_damage(u, target, maxf(1.0, round(max_hp(u) * float(act["pct"]) / 100.0)), "extra", false)
			"aura_damage":
				var t = _pick_target(u, "front")
				if t != null:
					for e in _enemies_in_row(u, t["row"]):
						_apply_damage(u, e, maxf(1.0, round(max_hp(u) * float(act["pct_maxhp"]) / 100.0)), "reflect", false)


## 상태 해제: 상태 이상과 약화 효과를 모두 지움
func _cleanse(t: Dictionary) -> void:
	for s in ["stun", "freeze", "burn", "poison", "silence", "shock", "bitter", "blind", "confuse"]:
		t["status"].erase(s)
	var keep := []
	for b in t["buffs"]:
		if not b.get("debuff", false):
			keep.append(b)
	t["buffs"] = keep


## 강화 해제: 적의 이로운 효과(버프·보호막)를 지움
func _dispel(t: Dictionary) -> void:
	var keep := []
	for b in t["buffs"]:
		if b.get("debuff", false) or float(b["until"]) - time > 900.0:
			keep.append(b)   # 약화 효과와 전투 내내 가는 효과(시너지·패시브 누적)는 남김
	t["buffs"] = keep
	t["shields"] = []
	_emit("buff", -1, t["i"], 0, "강화 해제")


## 소환: 시전자 옆에 작은 분신/친구를 잠시 불러냄 (기본 공격만, 시간이 다 되면 사라짐)
## {"a": "summon", "n": 2, "hp_pct": 35, "atk_pct": 45, "dur": 10, "name": "꿀벌", "scale": 0.55}
func _summon(u: Dictionary, act: Dictionary) -> void:
	var n := int(act.get("n", 1))
	for k in n:
		var s: Dictionary = u.duplicate(true)
		s["i"] = units.size() + _spawn_q.size()
		s["name"] = String(act.get("name", u["name"] + "의 분신"))
		s["summon"] = true
		s["owner"] = u["i"]
		s["life"] = float(act.get("dur", 10.0))
		s["scale"] = float(act.get("scale", 0.6))
		s["base"] = u["base"].duplicate()
		s["base"]["hp"] = float(u["base"]["hp"]) * float(act.get("hp_pct", 35)) / 100.0
		s["base"]["atk"] = float(u["base"]["atk"]) * float(act.get("atk_pct", 40)) / 100.0
		s["mods"] = {}
		s["buffs"] = []
		s["shields"] = []
		s["status"] = {}
		s["fx"] = []
		s["conds"] = []
		s["sk"] = {}
		s["arts"] = []
		s["sp"] = 0.0
		s["senior_timer"] = 999.0
		s["taunt"] = 0.0
		s["regens"] = []
		s["counters"] = {}
		s["cds"] = {}
		s["once"] = {}
		s["pending_normal"] = []
		s["role"] = "dealer"
		s["range"] = float(B["move"]["range"]["front"])
		s["y"] = clampf(float(u["y"]) + (0.45 if k % 2 == 0 else -0.45), 0.3, field_size().y - 0.3)
		s["x"] = float(u["x"]) + (0.4 if u["side"] == 0 else -0.4)
		s["hp"] = max_hp(s)
		s["alive"] = true
		_spawn_q.append(s)
		_emit("summon", u["i"], s["i"], _snapshot(s))
		_emit_pos(s)


# ─────────────────────────────── 사도별 스킬 ───────────────────────────────

## 스킬 동작 실행 (docs/SKILL_SPEC.md). 피해를 준 적 목록을 돌려준다 (스킬 적중 효과용).
func _skill_do(u: Dictionary, acts: Array, power: float, forced_target = null) -> Array:
	var hit := []
	for act in acts:
		if not u["alive"]:
			break
		var a: String = act["a"]
		var to: String = act.get("to", "")
		if to == "":
			to = "front" if a in ["dmg", "debuff", "status", "execute"] else "self"
		var targets: Array = [forced_target] if forced_target != null and to in ["front", "low", "back", "high_atk"] else _skill_targets(u, to)
		match a:
			"dmg":
				var hits := maxi(1, int(act.get("hits", 1)))
				var per := float(act["pct"]) * power / hits
				for t in targets:
					for h in hits:
						if not t["alive"]:
							break
						var kind := "fresh" if acts == u["sk"].get("fresh") else ("senior" if acts == u["sk"].get("senior") else "extra")
						if deal(u, t, per, kind, {}) > 0.0 and not hit.has(t):
							hit.append(t)
					if act.has("status") and t["alive"]:
						var st: Dictionary = act["status"]
						if rng.randf() * 100.0 < float(st.get("chance", 100)):
							_add_status(u, t, st["s"], float(st["dur"]))
			"heal":
				for t in targets:
					var amt := atk(u) * float(act["pct_atk"]) / 100.0 * power if act.has("pct_atk") else max_hp(t) * float(act.get("pct_hp", 0)) / 100.0
					_heal(u, t, amt, true)
			"shield":
				for t in targets:
					var amt := atk(u) * float(act["pct_atk"]) / 100.0 * power if act.has("pct_atk") else max_hp(t) * float(act.get("pct_hp", 0)) / 100.0
					_add_shield(u, t, amt, float(act.get("dur", 5.0)), true)
			"buff", "debuff":
				for t in targets:
					_add_buff(u, t, act["mods"], float(act.get("dur", 4.0)), String(act.get("key", "")), int(act.get("stack", 1)), a == "debuff")
				if a == "buff" and not targets.is_empty():
					_emit("buff", u["i"], targets[0]["i"], 0, "")
			"status":
				for t in targets:
					if rng.randf() * 100.0 < float(act.get("chance", 100)):
						_add_status(u, t, act["s"], float(act["dur"]))
			"taunt":
				u["taunt"] = maxf(u["taunt"], float(act.get("dur", 3.0)))
				_emit("buff", u["i"], u["i"], 0, "도발")
			"invuln":
				u["invuln"] = maxf(u["invuln"], float(act.get("dur", 1.0)))
				_emit("buff", u["i"], u["i"], 0, "무적")
			"untarget":
				u["untarget"] = maxf(u["untarget"], float(act.get("dur", 1.0)))
			"sp":
				for t in targets:
					t["sp"] += float(B["sp_max"]) * float(act.get("pct", 0)) / 100.0
			"cleanse":
				for t in targets:
					_cleanse(t)
			"dispel":
				for t in targets:
					_dispel(t)
			"cd":
				for t in targets:
					t["senior_timer"] = maxf(0.0, float(t["senior_timer"]) + float(act["sec"]))
			"cc_immune":
				for t in targets:
					t["cc_immune"] = maxf(float(t.get("cc_immune", 0.0)), float(act.get("dur", 3.0)))
				if not targets.is_empty():
					_emit("buff", u["i"], targets[0]["i"], 0, "상태 이상 면역")
			"summon":
				_summon(u, act)
			"execute":
				for t in targets:
					if t["alive"] and t["hp"] / max_hp(t) * 100.0 <= float(act.get("below", 10)) and t["invuln"] <= 0.0:
						_emit("execute", u["i"], t["i"], 0)
						_kill(u, t)
	return hit


## 스킬 대상 (docs/SKILL_SPEC.md 의 대상 이름)
func _skill_targets(u: Dictionary, to: String) -> Array:
	var foes := []
	for e in units:
		if e["side"] != u["side"] and _targetable(e):
			foes.append(e)
	var friends := _allies(u)
	var parts := to.split(":")
	match parts[0]:
		"self":
			return [u]
		"front", "back", "low":
			var t = _pick_target(u, parts[0])
			return [t] if t != null else []
		"high_atk":
			var best = null
			for e in foes:
				if best == null or atk(e) > atk(best):
					best = e
			return [best] if best != null else []
		"row_front", "row_back":
			if foes.is_empty():
				return []
			var r := 99 if parts[0] == "row_front" else -1
			for e in foes:
				r = mini(r, e["row"]) if parts[0] == "row_front" else maxi(r, e["row"])
			var out := []
			for e in foes:
				if e["row"] == r:
					out.append(e)
			return out
		"all":
			return foes
		"random":
			var n := int(parts[1]) if parts.size() > 1 else 1
			var out := []
			if not foes.is_empty():
				for i in n:
					out.append(foes[rng.randi() % foes.size()])
			return out
		"around":
			var t = _pick_target(u, parts[1] if parts.size() > 1 else "front")
			if t == null:
				return []
			var out := [t]
			for e in foes:
				if e != t and e["row"] == t["row"] and absi(int(e["slot"]) - int(t["slot"])) <= 1:
					out.append(e)
			return out
		"lowest":
			var lo = _lowest_ally(u)
			return [lo] if lo != null else []
		"allies":
			return friends
		"row":
			var out := []
			for a in friends:
				if a["row"] == u["row"]:
					out.append(a)
			return out
		"front_ally", "back_ally":
			if friends.is_empty():
				return []
			var r := 99 if parts[0] == "front_ally" else -1
			for a in friends:
				r = mini(r, a["row"]) if parts[0] == "front_ally" else maxi(r, a["row"])
			var out := []
			for a in friends:
				if a["row"] == r:
					out.append(a)
			return out
		"random_ally":
			var n := int(parts[1]) if parts.size() > 1 else 1
			var out := []
			for i in n:
				out.append(friends[rng.randi() % friends.size()])
			return out
	return []


func _shield_total(u: Dictionary) -> float:
	var t := 0.0
	for s in u["shields"]:
		t += s["amt"]
	return round(t)


## 이벤트: [시간, 종류, 시전자, 대상, 값, 추가 정보, 대상 HP(-1=없음), 대상 보호막]
func _emit(kind: String, src: int, dst: int, value, extra: String = "", hp: float = -1.0, sh: float = 0.0) -> void:
	events.append([snappedf(time, 0.01), kind, src, dst, value, extra, round(hp), sh])
