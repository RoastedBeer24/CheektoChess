class_name BattleSim
extends RefCounted
## 결정론적 자동 전투 시뮬레이터.
## 같은 입력(양쪽 군대 + seed)이면 어느 기기에서든 같은 결과가 나오도록
## 전투 중 난수는 모두 이 객체의 rng 하나만 쓴다.
##
## 입력 군대: Array of {aid, star, row, slot, arts: [artifact id], pers}
## 결과: {winner: 0|1|-1(무승부), survivors, end_time, events, units}

const DT := 0.1

var rng := RandomNumberGenerator.new()
var units: Array = []          # 유닛 런타임 상태 (Dictionary)
var events: Array = []         # 연출용 이벤트 목록
var time := 0.0
var deaths := [0, 0]           # 진영별 사망 수
var _tick_count := 0
var _uid_buff := 0
var B: Dictionary


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
		}
		# 어사이드 1성 (기본 적용)
		Rules.add_mods(u["mods"], Rules.aside1_mods(aid))
		# 어사이드 2성: 스킬 위력 증가 (간이)
		if star >= 2:
			u["power"] += float(B["aside2_skill_power"]) / 100.0
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
		# 시너지
		var specs := []
		for u in allies:
			specs.append({"aid": u["aid"], "pers": u["pers"]})
		var counts := Rules.count_traits(specs)
		var tiers := Rules.active_tiers(counts)
		for name in tiers:
			var tier: int = tiers[name]
			if tier <= 0:
				continue
			var syn: Dictionary = GameData.synergies[name]
			var mods: Dictionary = syn["mods"][tier - 1]
			match syn["scope"]:
				"trait":
					for u in allies:
						if GameData.traits_of(u["aid"], u["pers"]).has(name):
							_add_static(u, mods)
				"team":
					for u in allies:
						_add_static(u, mods)
				"enemy":
					for u in enemies:
						_add_static(u, mods)
		# 어사이드 3성 (간이)
		for src in allies:
			if src["star"] < 3:
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
		if u["side"] == side and u["alive"]:
			n += 1
	return n


# ─────────────────────────────── 진행 ───────────────────────────────

func run() -> Dictionary:
	_emit("start", -1, -1, 0)
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
		for u in units:
			if u["alive"]:
				_update_unit(u)
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
	return {"winner": winner, "survivors": survivors, "end_time": time, "events": events, "units": unit_snapshots()}


func unit_snapshots() -> Array:
	var out := []
	for u in units:
		out.append({"i": u["i"], "side": u["side"], "aid": u["aid"], "name": u["name"], "star": u["star"],
			"row": u["row"], "slot": u["slot"], "max_hp": max_hp(u), "pers": u["pers"]})
	return out


func _update_unit(u: Dictionary) -> void:
	var whole_second := _tick_count % 10 == 0
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
	if u["status"].has("stun"):
		return
	# SP
	u["sp"] += float(B["sp_regen"]) * maxf(0.0, 1.0 + mod(u, "sp_regen") / 100.0) * DT
	var target = _pick_target(u, "front")
	if target == null:
		return
	# 고학년 스킬 (재사용 대기시간)
	u["senior_timer"] -= DT
	if u["senior_timer"] <= 0.0:
		u["senior_timer"] = float(B["senior_cooldown"])
		_cast(u, "senior")
		return
	# 저학년 스킬 (SP)
	if u["sp"] >= float(B["sp_max"]):
		u["sp"] = 0.0
		_cast(u, "fresh")
		return
	# 일반 공격
	u["atk_timer"] -= DT
	if u["atk_timer"] <= 0.0:
		u["atk_timer"] = 1.0 / aspd(u)
		_normal_attack(u, target)


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
	for s in ["burn", "bitter"]:
		if u["status"].has(s):
			var st: Dictionary = u["status"][s]
			var src: Dictionary = units[st["src"]]
			var pct := 20.0 if s == "burn" else 10.0
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
	var enh_every: int = B["enhanced_every"]
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
	var sname: String = a.get("skills", {}).get(which, {}).get("name", "저학년 스킬" if which == "fresh" else "고학년 스킬")
	_emit("skill", u["i"], -1, 0 if which == "fresh" else 1, sname)
	var p: float = u["power"]
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
	# 스킬 적중 카운트 효과
	for e in hit_targets:
		for f in u["fx"]:
			if f["t"] == "skill_hit" and (not f.has("which") or f["which"] == which):
				_run_actions(u, f["do"], e, {})
	# 스킬 사용 효과
	for f in u["fx"]:
		if f["t"] == "skill" and (f["which"] == "any" or f["which"] == which):
			_run_actions(u, f["do"], null, {})


# ─────────────────────────────── 피해 / 회복 ───────────────────────────────

## 피해 계산 후 적용. kind: normal / enh / fresh / senior / extra / status / reflect
func deal(src: Dictionary, dst: Dictionary, mult_pct: float, kind: String, opts: Dictionary) -> float:
	if not dst["alive"] or not src["alive"] and kind != "status":
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
	if dst["hp"] <= 0.0:
		_kill(src, dst)
		return amt
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
	deaths[dst["side"]] += 1
	_emit("death", src["i"], dst["i"], 0)
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
	if dst["invuln"] > 0.0 and s == "stun":
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

func _resolve_to(u: Dictionary, to: String, target) -> Array:
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
		"target":
			return [target] if target != null and target["alive"] else []
	return [u]


func _run_actions(u: Dictionary, actions: Array, target, ctx: Dictionary) -> void:
	for act in actions:
		if not u["alive"] and act["a"] != "debuff":
			return
		match act["a"]:
			"buff":
				for d in _resolve_to(u, act.get("to", "self"), target):
					_add_buff(u, d, act["mods"], float(act["dur"]), act.get("key", ""), int(act.get("stack", 1)), false, act.get("max_bonus", {}))
					_emit("buff", u["i"], d["i"], 0, GameData.artifact(act.get("key", "")).get("name", ""))
			"debuff":
				for d in _resolve_to(u, act.get("to", "target"), target):
					_add_buff(u, d, act["mods"], float(act["dur"]), act.get("key", ""), int(act.get("stack", 1)), true)
			"clear_buff":
				var keep := []
				for b in u["buffs"]:
					if b["key"] != act["key"]:
						keep.append(b)
				u["buffs"] = keep
			"shield":
				for d in _resolve_to(u, act.get("to", "self"), target):
					_add_shield(u, d, max_hp(d) * float(act["pct"]) / 100.0, float(act["dur"]), false)
			"heal":
				for d in _resolve_to(u, act.get("to", "self"), target):
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
			"extra":
				if target != null and target["alive"]:
					deal(u, target, float(act["pct"]), "extra", {})
			"status":
				for d in _resolve_to(u, act.get("to", "target"), target):
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
				u["status"].erase("stun")
			"break_shield":
				if target != null and not target["shields"].is_empty():
					target["shields"].pop_front()
			"execute":
				if target != null and target["alive"] and target["hp"] / max_hp(target) * 100.0 <= float(act["below"]) and target["invuln"] <= 0.0:
					_emit("execute", u["i"], target["i"], 0)
					_kill(u, target)
			"aura_damage":
				var t = _pick_target(u, "front")
				if t != null:
					for e in _enemies_in_row(u, t["row"]):
						_apply_damage(u, e, maxf(1.0, round(max_hp(u) * float(act["pct_maxhp"]) / 100.0)), "reflect", false)


func _shield_total(u: Dictionary) -> float:
	var t := 0.0
	for s in u["shields"]:
		t += s["amt"]
	return round(t)


## 이벤트: [시간, 종류, 시전자, 대상, 값, 추가 정보, 대상 HP(-1=없음), 대상 보호막]
func _emit(kind: String, src: int, dst: int, value, extra: String = "", hp: float = -1.0, sh: float = 0.0) -> void:
	events.append([snappedf(time, 0.01), kind, src, dst, value, extra, round(hp), sh])
