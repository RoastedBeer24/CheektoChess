class_name Bot
extends RefCounted
## 간단한 봇. 준비 단계 시작 시 한 번 행동한다. 모든 행동은 일반 플레이어와 같은 command() 를 거친다.


static func play(m: Match, pid: String) -> void:
	var p := m.player(pid)
	var r: int = m.state["round"]
	_pick_artifact(m, pid)
	# 1) 이미 가진 사도(합성 재료) 우선 구매, 그다음 싼 사도
	_buy_pass(m, pid, true)
	# 2) 레벨업: 이자 구간을 지키면서
	var keep := 10 if r < 10 else 0
	while p["gold"] - int(m.B["xp_cost"]) >= keep + 4 and p["level"] < _target_level(r):
		if m.command(pid, {"t": "buy_xp"}) != "":
			break
	_buy_pass(m, pid, false)
	# 3) 후반에는 남는 골드로 새로고침
	var guard := 0
	while r >= 8 and p["gold"] >= 30 + int(m.B["reroll_cost"]) and guard < 5:
		guard += 1
		m.command(pid, {"t": "reroll"})
		_buy_pass(m, pid, true)
	_arrange(m, pid)
	_equip(m, pid)
	_merge_artifacts(m, pid)
	_trim_bench(m, pid)
	m.command(pid, {"t": "ready", "on": true})


static func _target_level(r: int) -> int:
	return clampi(2 + r / 2, 2, 9)


static func _owned(p: Dictionary, aid: String) -> int:
	var n := 0
	for u in p["bench"]:
		if u != null and u["aid"] == aid:
			n += 1
	for k in p["board"]:
		if p["board"][k]["aid"] == aid:
			n += 1
	return n


static func _buy_pass(m: Match, pid: String, only_owned: bool) -> void:
	var p := m.player(pid)
	var keep := 10 if m.state["round"] < 10 else 2
	for i in p["shop"].size():
		var aid: String = p["shop"][i]
		if aid == "":
			continue
		var cost: int = GameData.cost_of[aid]
		var owned := _owned(p, aid)
		if only_owned and owned == 0:
			continue
		if not only_owned and cost > maxi(1, p["level"] / 2 + 1):
			continue
		if p["gold"] - cost < keep and owned == 0:
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
	var want := units.slice(0, mini(units.size(), int(p["level"])))
	# 보드에 있지만 뽑히지 않은 유닛은 내린다
	for e in units:
		if e["loc"].has("board") and not want.has(e):
			var free: int = p["bench"].find(null)
			if free >= 0:
				m.command(pid, {"t": "move", "from": e["loc"], "to": {"bench": free}})
	# 성격: 보드에서 가장 많은 성격으로
	var pers := _main_personality(p)
	for e in want:
		if e["loc"].has("board"):
			continue
		var u: Dictionary = e["u"]
		var from := _find(p, u["uid"])
		if from.is_empty():
			continue
		var cell := _free_cell(m, p, u["aid"])
		if cell == "":
			continue
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
		if GameData.can_place(aid, r):
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
			if u["arts"].size() >= int(m.B["artifact_slots"]):
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
