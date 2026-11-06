class_name Bot
extends RefCounted
## 간단한 봇. 준비 단계 시작 시와 중간에 한 번 더 행동한다.
## 모든 행동은 일반 플레이어와 같은 command() 를 거친다.


## 봇 성향 (난이도는 같음): 균형형 / 리롤형(낮은 레벨에서 새로고침으로 합성) /
## 레벨업형(빨리 레벨을 올려 비싼 사도) / 시너지 집중형(한 시너지를 골라 모음)
const STYLES := ["balanced", "reroll", "level", "synergy"]
const STYLE_NAME := {"balanced": "균형형", "reroll": "리롤형", "level": "레벨업형", "synergy": "시너지 집중형", "": "균형형"}


static func style_of(p: Dictionary) -> String:
	var st: String = p.get("style", "")
	return st if STYLES.has(st) else "balanced"


static func play(m: Match, pid: String, second: bool = false) -> void:
	var p := m.player(pid)
	var r: int = m.state["round"]
	var style := style_of(p)
	if not second:
		_pick_augment(m, pid)
		_pick_artifact(m, pid)
	if style == "synergy":
		_update_focus(p)
	# 1) 합성 재료 우선 구매
	_buy_pass(m, pid, "owned")
	# 2) 보드를 채울 사도가 모자라면 시너지 맞는 사도 → 아무 사도
	_buy_pass(m, pid, "synergy")
	_buy_pass(m, pid, "fill")
	# 3) 레벨업: 초반에는 보드 채우기 우선, 이후 이자 구간(10골드)을 지키면서
	var keep := 0 if r <= 3 else (10 if r < 12 else 0)
	if style == "level":
		keep = 0 if r <= 5 else 4
	# 레벨을 올려도 채울 사도가 있을 때만 (1라운드는 사도 구매 우선)
	while r >= 2 and p["gold"] - int(m.B["xp_cost"]) >= keep and p["level"] < _target_level(r, style) and (_unit_count(p) > p["level"] or style == "level"):
		if m.command(pid, {"t": "buy_xp"}) != "":
			break
	_buy_pass(m, pid, "fill")
	# 4) 새로고침: 성향마다 시작 라운드와 남길 골드가 다름 (무료 새로고침은 항상 사용)
	var rr: Array = {"balanced": [8, 30, 5], "reroll": [4, 14, 8], "level": [14, 40, 3], "synergy": [6, 24, 6]}[style]
	var guard := 0
	while guard < 8 and (int(p["aug_st"].get("free_rr", 0)) > 0 or (r >= int(rr[0]) and p["gold"] >= int(rr[1]) + int(m.B["reroll_cost"]) and guard < int(rr[2]))):
		guard += 1
		if m.command(pid, {"t": "reroll"}) != "":
			break
		_buy_pass(m, pid, "owned")
		_buy_pass(m, pid, "synergy")
	_arrange(m, pid)
	_equip(m, pid)
	_merge_artifacts(m, pid)
	_trim_bench(m, pid)
	m.command(pid, {"t": "ready", "on": true})


static func _target_level(r: int, style: String = "balanced") -> int:
	match style:
		"reroll":
			return clampi(2 + r / 3, 2, 7)
		"level":
			return clampi(3 + r / 2, 2, 9)
	return clampi(2 + r / 2, 2, 9)


## 시너지 집중형: 가진 사도에서 가장 많은 시너지(고유 제외)를 목표로
static func _update_focus(p: Dictionary) -> void:
	var counts := {}
	for u in _units_of(p):
		for t in GameData.traits_of(u["aid"]):
			if GameData.synergies.get(t, {}).get("kind", "") == "unique":
				continue
			counts[t] = counts.get(t, 0) + 1
	var best: String = p.get("focus", "")
	var bn: int = counts.get(best, 0)
	for t in counts:
		if counts[t] > bn + 1 or (best == "" and counts[t] > bn):
			best = t
			bn = counts[t]
	p["focus"] = best


static func _units_of(p: Dictionary) -> Array:
	var out := []
	for u in p["bench"]:
		if u != null:
			out.append(u)
	for k in p["board"]:
		out.append(p["board"][k])
	return out


## 증강 고르기: 성향에 맞는 종류를 우선, 시너지 집중형은 목표 시너지 상징을 가장 우선
static func _pick_augment(m: Match, pid: String) -> void:
	var p := m.player(pid)
	var off: Dictionary = p.get("aug_offer", {})
	if off.is_empty():
		return
	var pref: Dictionary = {
		"balanced": {"battle": 3.0, "grow": 2.0, "econ": 1.5, "unit": 1.5, "syn": 1.0},
		"reroll": {"unit": 3.0, "econ": 2.5, "battle": 1.5, "grow": 1.0, "syn": 1.0},
		"level": {"econ": 3.0, "grow": 2.0, "battle": 1.5, "unit": 1.0, "syn": 1.0},
		"synergy": {"syn": 3.0, "battle": 2.0, "unit": 1.5, "econ": 1.0, "grow": 1.0},
	}[style_of(p)]
	var best := 0
	var best_v := -1.0
	for i in off["options"].size():
		var a: Dictionary = off["options"][i]
		var kind: String = GameData.augment(a["id"]).get("kind", "grow")
		var v: float = float(pref.get(kind, 1.0)) + m.rng.randf() * 1.2
		if a["id"] == "emblem":
			v += 4.0 if a.get("trait", "") == p.get("focus", "") else 0.0
		if kind == "risk" and int(p["hp"]) < 35:
			v -= 2.0   # 체력이 낮으면 위험한 증강은 피한다
		if v > best_v:
			best_v = v
			best = i
	m.command(pid, {"t": "aug_pick", "i": best})


static func _unit_count(p: Dictionary) -> int:
	var n: int = p["board"].size()
	for u in p["bench"]:
		if u != null:
			n += 1
	return n


static func _owned(p: Dictionary, aid: String) -> int:
	var n := 0
	for u in p["bench"]:
		if u != null and u["aid"] == aid:
			n += 1
	for k in p["board"]:
		if p["board"][k]["aid"] == aid:
			n += 1
	return n


## 보드 사도들의 성격·종족과 겹치는지
static func _fits(p: Dictionary, aid: String) -> bool:
	var mine := {}
	for k in p["board"]:
		for t in GameData.traits_of(p["board"][k]["aid"], p["board"][k]["pers"]):
			mine[t] = true
	for t in GameData.traits_of(aid, ""):
		if mine.has(t):
			return true
	return false


## mode: owned(합성 재료) / synergy(시너지 맞는 사도) / fill(보드 채우기)
static func _buy_pass(m: Match, pid: String, mode: String) -> void:
	var p := m.player(pid)
	var r: int = m.state["round"]
	for i in p["shop"].size():
		var aid: String = p["shop"][i]
		if aid == "":
			continue
		var cost: int = GameData.cost_of[aid]
		if p["gold"] < cost:
			continue
		var owned := _owned(p, aid)
		var need: bool = _unit_count(p) < int(p["level"]) + 1
		match mode:
			"owned":
				if owned == 0:
					continue
			"synergy":
				var focus_hit: bool = style_of(p) == "synergy" and p.get("focus", "") != "" and GameData.traits_of(aid).has(p["focus"])
				if owned > 0 or not (_fits(p, aid) or focus_hit) or cost > int(p["level"]) / 2 + (3 if focus_hit else 2):
					continue
				# 이자 구간을 지키되 보드가 비면 무시
				if not need and p["gold"] - cost < (10 if r >= 4 else 0):
					continue
			"fill":
				if not need or cost > maxi(1, int(p["level"]) / 2 + 1):
					continue
		if p["bench"].find(null) < 0 and owned < 2:
			continue
		m.command(pid, {"t": "buy", "i": i})


## 가장 강한 유닛들을 레벨만큼 보드에 올린다
static func _arrange(m: Match, pid: String) -> void:
	var p := m.player(pid)
	# 보드의 유닛을 모두 대기석으로 내렸다가 다시 배치 (대기석 공간이 허락하는 만큼)
	var units := []
	for i in p["bench"].size():
		if p["bench"][i] != null:
			units.append({"loc": {"bench": i}, "u": p["bench"][i]})
	for k in p["board"]:
		units.append({"loc": {"board": k}, "u": p["board"][k]})
	units.sort_custom(func(a, b): return _value(a["u"]) > _value(b["u"]))
	var want := units.slice(0, mini(units.size(), Match.board_cap(p)))
	# 보드에 있지만 뽑히지 않은 유닛은 내린다
	for e in units:
		if e["loc"].has("board") and not want.has(e):
			var free: int = p["bench"].find(null)
			if free >= 0:
				m.command(pid, {"t": "move", "from": e["loc"], "to": {"bench": free}})
	# 성격: 보드에서 가장 많은 성격으로
	var pers := _main_personality(p)
	for e in units:
		if p["board"].size() >= Match.board_cap(p):
			break
		var u: Dictionary = e["u"]
		var from := _find(p, u["uid"])
		if from.is_empty() or from.has("board"):
			continue
		var cell := _free_cell(m, p, u["aid"])
		if cell == "":
			continue   # 그 열이 가득 차면 다음 사도로
		var opts := GameData.personality_options(u["aid"])
		var chosen: String = pers if opts.has(pers) else (opts[0] if not opts.is_empty() else "")
		m.command(pid, {"t": "move", "from": from, "to": {"board": cell}, "pers": chosen})


static func _value(u: Dictionary) -> float:
	return u["star"] * 10.0 + GameData.cost_of.get(u["aid"], 1) + u["arts"].size()


static func _find(p: Dictionary, uid: int) -> Dictionary:
	for i in p["bench"].size():
		if p["bench"][i] != null and int(p["bench"][i]["uid"]) == uid:
			return {"bench": i}
	for k in p["board"]:
		if int(p["board"][k]["uid"]) == uid:
			return {"board": k}
	return {}


static func _free_cell(m: Match, p: Dictionary, aid: String) -> String:
	var rows := []
	for r in int(m.B["board_rows"]):
		if Match.can_place_p(p, aid, r):
			rows.append(r)
	for r in rows:
		for s in [1, 0, 2]:
			var k := Match.key_of(r, s)
			if not p["board"].has(k):
				return k
	return ""


static func _main_personality(p: Dictionary) -> String:
	var counts := {}
	for k in p["board"]:
		var per: String = GameData.apostle(p["board"][k]["aid"]).get("personality", "")
		if GameData.PERSONALITIES.has(per):
			counts[per] = counts.get(per, 0) + 1
	var best := ""
	var n := -1
	for per in counts:
		if counts[per] > n:
			n = counts[per]
			best = per
	return best


static func _pick_artifact(m: Match, pid: String) -> void:
	var p := m.player(pid)
	var off: Dictionary = p["art_offer"]
	if off.is_empty():
		return
	var order: Array = m.B["grade_order"]
	# 가장 낮은 등급 칸을 한 번 다시 뽑는다
	var worst := 0
	for i in off["options"].size():
		if order.find(GameData.artifact(off["options"][i])["grade"]) < order.find(GameData.artifact(off["options"][worst])["grade"]):
			worst = i
	m.command(pid, {"t": "art_reroll", "i": worst})
	off = p["art_offer"]
	var best := 0
	for i in off["options"].size():
		if order.find(GameData.artifact(off["options"][i])["grade"]) > order.find(GameData.artifact(off["options"][best])["grade"]):
			best = i
	m.command(pid, {"t": "art_pick", "i": best})


static func _equip(m: Match, pid: String) -> void:
	var p := m.player(pid)
	var guard := 0
	while not p["inv"].is_empty() and guard < 10:
		guard += 1
		var best_loc := {}
		var best_v := -1.0
		for k in p["board"]:
			var u: Dictionary = p["board"][k]
			if u["arts"].size() >= Match.art_slots(u["aid"]):
				continue
			var v: float = _value(u) - u["arts"].size() * 3.0
			if v > best_v:
				best_v = v
				best_loc = {"board": k}
		if best_loc.is_empty():
			return
		if m.command(pid, {"t": "equip", "art": p["inv"][0]["uid"], "loc": best_loc}) != "":
			return


static func _merge_artifacts(m: Match, pid: String) -> void:
	var p := m.player(pid)
	var by_grade := {}
	for a in p["inv"]:
		var g: String = GameData.artifact(a["id"])["grade"]
		if g == "legend":
			continue
		if by_grade.has(g):
			m.command(pid, {"t": "art_merge", "a": by_grade[g], "b": a["uid"]})
			return
		by_grade[g] = a["uid"]


## 대기석이 가득 차면 가치가 낮은 유닛을 판다
static func _trim_bench(m: Match, pid: String) -> void:
	var p := m.player(pid)
	if p["bench"].find(null) >= 0:
		return
	var worst := -1
	var wv := 999.0
	for i in p["bench"].size():
		var u = p["bench"][i]
		if u != null and _owned(p, u["aid"]) == 1 and _value(u) < wv:
			wv = _value(u)
			worst = i
	if worst >= 0:
		m.command(pid, {"t": "sell", "loc": {"bench": worst}})


## 공유 선택: 이미 가진 사도(합성) > 보드 시너지와 겹치는 사도 > 비싼 사도
static func carousel_choice(m: Match, pid: String) -> int:
	var p := m.player(pid)
	var opts: Array = m.state["carousel"]["options"]
	var have := {}
	for u in m._all_units(p):
		have[u["aid"]] = have.get(u["aid"], 0) + 1
	var mine := {}
	for k in p["board"]:
		for t in GameData.traits_of(p["board"][k]["aid"]):
			mine[t] = true
	var best := -1
	var best_score := -999.0
	for i in opts.size():
		if opts[i]["by"] != "":
			continue
		var aid: String = opts[i]["aid"]
		var score := float(GameData.cost_of.get(aid, 1))
		score += 6.0 * have.get(aid, 0)
		for t in GameData.traits_of(aid):
			if mine.has(t):
				score += 3.0
		score += 0.5 * ["common", "advanced", "rare", "legend"].find(GameData.artifact(opts[i]["art"]).get("grade", "common"))
		if score > best_score:
			best_score = score
			best = i
	return best
