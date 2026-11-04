class_name Match
extends RefCounted
## 한 판의 게임 상태와 규칙. 방장(호스트) 기기에서만 실행된다.
## 상태(state)는 기본 타입(Dictionary/Array/숫자/문자열)만 담아 네트워크로 그대로 보낼 수 있다.
## 모든 플레이어 행동은 command(pid, cmd) 하나로 들어온다.

signal state_changed

var state: Dictionary = {}
var rng := RandomNumberGenerator.new()
var B: Dictionary
var phase_left := 0.0
var _bot_second_done := false


func _init(players: Array, seed: int) -> void:
	# players: [{id, name, bot}]
	B = GameData.balance
	rng.seed = seed
	var pool := {}
	for aid in GameData.roster:
		pool[aid] = int(B["pool_size"][GameData.cost_of[aid] - 1])
	var ps := {}
	for p in players:
		ps[p["id"]] = {
			"id": p["id"], "name": p["name"], "bot": p.get("bot", false),
			"hp": int(B["player_hp"]), "gold": 0, "level": int(B["start_level"]), "xp": 0,
			"streak": 0, "alive": true, "place": 0,
			"shop": [], "locks": [], "bench": _empty_bench(), "board": {}, "inv": [],
			"art_offer": {}, "connected": true, "dc_round": 0, "last_opp": "", "ready": false,
		}
	state = {
		"round": 0, "phase": "lobby", "phase_end": 0.0, "players": ps, "pool": pool,
		"battles": [], "next_uid": 1, "log": [], "winner": "", "seed": seed,
		"group": GameData.group_id,
	}


func _empty_bench() -> Array:
	var a := []
	a.resize(int(B["bench_size"]))
	return a


func _uid() -> int:
	state["next_uid"] += 1
	return state["next_uid"]


func player(pid: String) -> Dictionary:
	return state["players"].get(pid, {})


func alive_players() -> Array:
	var out := []
	for pid in state["players"]:
		if state["players"][pid]["alive"]:
			out.append(pid)
	return out


func _log(msg: String) -> void:
	state["log"].append(msg)
	if state["log"].size() > 40:
		state["log"].pop_front()


# ─────────────────────────────── 라운드 진행 ───────────────────────────────

func start() -> void:
	_start_prep()


## 호스트가 매 프레임 호출한다.
func advance(dt: float) -> void:
	if state["phase"] == "over" or state["phase"] == "lobby":
		return
	phase_left -= dt
	state["phase_end"] = maxf(0.0, phase_left)
	match state["phase"]:
		"prep":
			# 봇은 준비 단계 중간에 한 번 더 행동한다
			if not _bot_second_done and phase_left <= float(B["prep_time"]) * 0.5:
				_bot_second_done = true
				for pid in alive_players():
					if player(pid)["bot"]:
						Bot.play(self, pid, true)
			if phase_left <= 0.0 or _all_humans_ready():
				_start_battle()
		"battle":
			if phase_left <= 0.0 or _all_humans_skipped():
				_end_battle()
		"result":
			if phase_left <= 0.0:
				_start_prep()


func _is_human(pid: String) -> bool:
	var p := player(pid)
	return not p.is_empty() and not p["bot"] and p["connected"]


## 전투를 보고 있는 사람이 모두 "결과 보기"를 눌렀는지
func _all_humans_skipped() -> bool:
	var any_human := false
	for pid in state["players"]:
		var p := player(pid)
		if p["bot"] or not p["connected"] or not p["alive"]:
			continue
		any_human = true
		if not p.get("skip", false):
			return false
	return any_human


func _all_humans_ready() -> bool:
	var any_human := false
	for pid in alive_players():
		var p := player(pid)
		if p["bot"] or not p["connected"]:
			continue
		any_human = true
		if not p["ready"]:
			return false
	return any_human


func _start_prep() -> void:
	# 연결이 끊긴 채 라운드가 넘어가면 탈락
	var dc := []
	for pid in alive_players():
		if not player(pid)["connected"] and not player(pid)["bot"]:
			dc.append(pid)
	if not dc.is_empty():
		var remaining := alive_players().size()
		for pid in dc:
			_log("%s 재접속하지 않아 탈락" % player(pid)["name"])
			_eliminate(pid, remaining)
			remaining -= 1
		var alive := alive_players()
		if alive.size() <= 1:
			state["phase"] = "over"
			if alive.size() == 1:
				state["winner"] = alive[0]
				player(alive[0])["place"] = 1
			state_changed.emit()
			return
	state["round"] += 1
	var r: int = state["round"]
	state["phase"] = "prep"
	phase_left = float(B.get("first_prep_time", B["prep_time"])) if r == 1 else float(B["prep_time"])
	state["battles"] = []
	for pid in alive_players():
		var p := player(pid)
		p["ready"] = false
		if r == 1:
			p["gold"] = int(B["start_gold"])
		else:
			p["gold"] += income(p)
			_add_xp(p, int(B["xp_per_round"]))
		_refresh_shop(p)
		if is_artifact_round(r):
			p["art_offer"] = {"options": _roll_artifacts(r, int(B["artifact_choices"])), "rerolled": [false, false, false]}
	_log("라운드 %d 준비 시작" % r)
	_bot_second_done = false
	for pid in alive_players():
		if player(pid)["bot"]:
			Bot.play(self, pid)
	state_changed.emit()


func is_artifact_round(r: int) -> bool:
	for x in B["artifact_rounds"]:
		if int(x) == r:
			return true
	return false


func income(p: Dictionary) -> int:
	var g := int(B["base_income"])
	g += mini(int(p["gold"]) / int(B["interest_per"]), int(B["interest_max"]))
	var s: int = abs(int(p["streak"]))
	var bonus := 0
	for pair in B["streak_bonus"]:
		if s >= int(pair[0]):
			bonus = int(pair[1])
	return g + bonus


func _start_battle() -> void:
	# 고르지 않은 아티팩트는 첫 번째 선택지로 자동 선택
	for pid in alive_players():
		var p := player(pid)
		if not p["art_offer"].is_empty():
			_cmd_art_pick(p, {"i": 0})
	state["phase"] = "battle"
	var ids := alive_players()
	# 섞은 뒤 직전 상대와 겹치지 않게 짝을 맞춘다
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = ids[i]
		ids[i] = ids[j]
		ids[j] = t
	var pairs := []
	var pending := ids.duplicate()
	while pending.size() >= 2:
		var a: String = pending.pop_front()
		var pick := 0
		for k in pending.size():
			if pending[k] != player(a)["last_opp"]:
				pick = k
				break
		var b: String = pending.pop_at(pick)
		pairs.append([a, b, ""])
	if pending.size() == 1:
		# 홀수: 다른 플레이어 보드를 복제한 유령과 싸운다
		var a: String = pending[0]
		var others := alive_players()
		others.erase(a)
		var ghost_of: String = others[rng.randi_range(0, others.size() - 1)] if not others.is_empty() else a
		pairs.append([a, "", ghost_of])
	var battles := []
	var longest := 0.0   # 사람이 참여한 전투 중 가장 긴 시간 (봇끼리의 전투는 기다리지 않음)
	for pr in pairs:
		var a: String = pr[0]
		var b: String = pr[1]
		var ghost: String = pr[2]
		var army_a := army_of(a)
		var army_b := army_of(b if ghost == "" else ghost)
		var seed := rng.randi()
		var result := BattleSim.new(army_a, army_b, seed).run()
		if _is_human(a) or (b != "" and _is_human(b)):
			longest = maxf(longest, float(result["end_time"]))
		battles.append({"a": a, "b": b, "ghost": ghost, "seed": seed, "army_a": army_a, "army_b": army_b,
			"winner": result["winner"], "survivors": result["survivors"], "end_time": result["end_time"]})
		player(a)["last_opp"] = b if ghost == "" else ghost
		if b != "":
			player(b)["last_opp"] = a
	state["battles"] = battles
	# 사람이 참여한 전투가 없으면(전원 봇·관전) 짧게 넘어간다
	phase_left = (longest + 2.5) if longest > 0.0 else 3.0
	state["battle_len"] = phase_left
	for pid in state["players"]:
		player(pid)["skip"] = false
	_log("라운드 %d 전투 시작" % state["round"])
	state_changed.emit()


func _end_battle() -> void:
	var r: int = state["round"]
	var base_dmg := int(B["damage_base"]) + r / int(B["damage_per_round_div"])
	for bt in state["battles"]:
		var a := player(bt["a"])
		var b := player(bt["b"]) if bt["b"] != "" else {}
		match int(bt["winner"]):
			0:
				_win(a)
				if not b.is_empty():
					_lose(b, base_dmg + int(bt["survivors"]))
			1:
				_lose(a, base_dmg + int(bt["survivors"]))
				if not b.is_empty():
					_win(b)
			_:
				_lose(a, base_dmg)
				if not b.is_empty():
					_lose(b, base_dmg)
	# 탈락 처리 (체력 0, 또는 접속이 끊긴 채 라운드가 넘어간 플레이어)
	var dead_now := []
	for pid in alive_players():
		var p := player(pid)
		if p["hp"] <= 0:
			dead_now.append(pid)
	var remaining := alive_players().size()
	if dead_now.size() == remaining and remaining > 0:
		# 남은 전원이 동시에 탈락하면 체력이 가장 높은 플레이어가 살아남는다
		var best: String = dead_now[0]
		for pid in dead_now:
			if player(pid)["hp"] > player(best)["hp"]:
				best = pid
		dead_now.erase(best)
		player(best)["hp"] = maxi(1, int(player(best)["hp"]))
	dead_now.sort_custom(func(x, y): return player(x)["hp"] > player(y)["hp"])
	for pid in dead_now:
		_eliminate(pid, remaining)
		remaining -= 1
	var alive := alive_players()
	if alive.size() <= 1:
		state["phase"] = "over"
		if alive.size() == 1:
			state["winner"] = alive[0]
			player(alive[0])["place"] = 1
		_log("게임 종료")
	else:
		state["phase"] = "result"
		phase_left = float(B["result_time"])
	state_changed.emit()


func _win(p: Dictionary) -> void:
	p["streak"] = maxi(1, int(p["streak"]) + 1)
	p["gold"] += 1
	_synergy_reward(p, true)


func _lose(p: Dictionary, dmg: int) -> void:
	p["streak"] = mini(-1, int(p["streak"]) - 1)
	p["hp"] -= dmg
	_synergy_reward(p, false)


## 전투 결과에 따른 시너지 보상 (델리아 탐험대: 골드, n승마다 아티팩트)
func _synergy_reward(p: Dictionary, won: bool) -> void:
	var specs := []
	for k in p["board"]:
		specs.append(p["board"][k])
	var tiers := Rules.active_tiers(Rules.count_traits(specs))
	for name in tiers:
		var tier: int = tiers[name]
		if tier <= 0:
			continue
		var levels: Array = GameData.synergies[name].get("levels", [])
		if tier - 1 >= levels.size():
			continue
		var spec: Dictionary = levels[tier - 1]
		if spec.has("gold"):
			var g := int(spec["gold"].get("win" if won else "lose", 0))
			if g > 0:
				p["gold"] += g
				_log("%s: %s +%d골드" % [p["name"], name, g])
		if spec.has("art_every_wins") and won:
			var key: String = "wins_" + String(name)
			p[key] = int(p.get(key, 0)) + 1
			if p[key] % int(spec["art_every_wins"]) == 0:
				var pool: Array = GameData.artifacts_by_grade.get("common", [])
				if not pool.is_empty():
					p["inv"].append({"uid": _uid(), "id": pool[rng.randi() % pool.size()]})
					_log("%s: %s 보물 발견 (일반 아티팩트)" % [p["name"], name])


func _eliminate(pid: String, remaining: int) -> void:
	var p := player(pid)
	p["alive"] = false
	p["place"] = remaining
	for u in _all_units(p):
		_return_to_pool(u)
	p["bench"] = _empty_bench()
	p["board"] = {}
	for aid in p["shop"]:
		if aid != "":
			state["pool"][aid] += 1
	p["shop"] = []
	_log("%s 탈락 (%d위)" % [p["name"], remaining])


## 연결 끊김 / 재접속
func set_connected(pid: String, on: bool) -> void:
	var p := player(pid)
	if p.is_empty():
		return
	p["connected"] = on
	if not on:
		p["dc_round"] = state["round"]
		_log("%s 연결 끊김" % p["name"])
	else:
		_log("%s 재접속" % p["name"])
	state_changed.emit()


## 같은 라운드 안이면 재접속 허용
func can_rejoin(pid: String) -> bool:
	var p := player(pid)
	return not p.is_empty() and p["alive"] and not p["connected"] and int(p["dc_round"]) == int(state["round"])


# ─────────────────────────────── 군대 / 유닛 ───────────────────────────────

## 전투용 군대 사양
func army_of(pid: String) -> Array:
	var p := player(pid)
	var out := []
	for key in p["board"]:
		var u: Dictionary = p["board"][key]
		var rs := _parse_key(key)
		var arts := []
		for a in u["arts"]:
			arts.append(a["id"])
		out.append({"aid": u["aid"], "star": u["star"], "row": rs[0], "slot": rs[1], "arts": arts, "pers": u["pers"]})
	return out


static func _parse_key(key: String) -> Array:
	var s := key.split(",")
	return [int(s[0]), int(s[1])]


static func key_of(row: int, slot: int) -> String:
	return "%d,%d" % [row, slot]


func _all_units(p: Dictionary) -> Array:
	var out := []
	for u in p["bench"]:
		if u != null:
			out.append(u)
	for k in p["board"]:
		out.append(p["board"][k])
	return out


func _return_to_pool(u: Dictionary) -> void:
	if state["pool"].has(u["aid"]):
		state["pool"][u["aid"]] += int(pow(3, u["star"] - 1))


func unit_at(p: Dictionary, loc: Dictionary) -> Variant:
	if loc.has("bench"):
		var i := int(loc["bench"])
		if i < 0 or i >= p["bench"].size():
			return null
		return p["bench"][i]
	if loc.has("board"):
		return p["board"].get(loc["board"])
	return null


func _set_at(p: Dictionary, loc: Dictionary, u) -> void:
	if loc.has("bench"):
		p["bench"][int(loc["bench"])] = u
	elif loc.has("board"):
		if u == null:
			p["board"].erase(loc["board"])
		else:
			p["board"][loc["board"]] = u


# ─────────────────────────────── 상점 ───────────────────────────────

## 상점 갱신. 잠근 칸은 그대로 둔다.
func _refresh_shop(p: Dictionary) -> void:
	var n := int(B["shop_size"])
	var locks: Array = p.get("locks", [])
	locks.resize(n)
	var old: Array = p["shop"]
	var shop := []
	for i in n:
		var keep: bool = locks[i] == true and i < old.size() and old[i] != ""
		if keep:
			shop.append(old[i])
		else:
			locks[i] = false
			if i < old.size() and old[i] != "":
				state["pool"][old[i]] += 1
			shop.append("")
	var odds: Array = B["shop_odds"][clampi(int(p["level"]), 1, 9) - 1]
	for i in n:
		if shop[i] == "":
			shop[i] = _roll_unit(odds)
	p["shop"] = shop
	p["locks"] = locks


func _roll_unit(odds: Array) -> String:
	var roll := rng.randf() * 100.0
	var cost := 1
	var acc := 0.0
	for i in odds.size():
		acc += float(odds[i])
		if roll < acc:
			cost = i + 1
			break
	# 해당 코스트에 남은 게 없으면 낮은 코스트로
	for c in range(cost, 0, -1):
		var cands := []
		var total := 0
		for aid in GameData.roster:
			if GameData.cost_of[aid] == c and state["pool"][aid] > 0:
				cands.append(aid)
				total += state["pool"][aid]
		if total == 0:
			continue
		var pick := rng.randi_range(0, total - 1)
		for aid in cands:
			pick -= state["pool"][aid]
			if pick < 0:
				state["pool"][aid] -= 1
				return aid
	return ""


func _add_xp(p: Dictionary, amt: int) -> void:
	p["xp"] += amt
	var table: Array = B["xp_to_next"]
	while p["level"] < int(B["max_level"]) and p["xp"] >= int(table[p["level"] - 1]):
		p["xp"] -= int(table[p["level"] - 1])
		p["level"] += 1
	if p["level"] >= int(B["max_level"]):
		p["xp"] = 0


func xp_needed(p: Dictionary) -> int:
	if p["level"] >= int(B["max_level"]):
		return 0
	return int(B["xp_to_next"][p["level"] - 1])


func sell_value(u: Dictionary) -> int:
	return GameData.cost_of.get(u["aid"], 1) * int(pow(3, u["star"] - 1))


# ─────────────────────────────── 명령 처리 ───────────────────────────────

## 플레이어 명령. 성공하면 "" , 실패하면 사유 문자열을 돌려준다.
func command(pid: String, cmd: Dictionary) -> String:
	var p := player(pid)
	if p.is_empty() or not p["alive"]:
		return "참가 중이 아님"
	var t: String = cmd.get("t", "")
	if t == "lock":
		var li := int(cmd.get("i", -1))
		if li < 0 or li >= p["shop"].size() or p["shop"][li] == "":
			return "빈 칸"
		var locks: Array = p.get("locks", [])
		locks.resize(p["shop"].size())
		locks[li] = bool(cmd.get("on", true))
		p["locks"] = locks
		state_changed.emit()
		return ""
	if t == "skip":
		if state["phase"] != "battle":
			return "전투 중이 아님"
		p["skip"] = true
		state_changed.emit()
		return ""
	var prep_only := ["buy", "sell", "move", "reroll", "buy_xp", "art_reroll", "art_pick", "equip", "art_merge", "ready"]
	if prep_only.has(t) and state["phase"] != "prep":
		return "준비 단계가 아님"
	var err := ""
	match t:
		"buy": err = _cmd_buy(p, cmd)
		"sell": err = _cmd_sell(p, cmd)
		"move": err = _cmd_move(p, cmd)
		"reroll": err = _cmd_reroll(p)
		"buy_xp": err = _cmd_buy_xp(p)
		"art_reroll": err = _cmd_art_reroll(p, cmd)
		"art_pick": err = _cmd_art_pick(p, cmd)
		"equip": err = _cmd_equip(p, cmd)
		"art_merge": err = _cmd_art_merge(p, cmd)
		"ready":
			p["ready"] = bool(cmd.get("on", true))
		_:
			err = "알 수 없는 명령"
	if err == "":
		state_changed.emit()
	return err


func _cmd_buy(p: Dictionary, cmd: Dictionary) -> String:
	var i := int(cmd.get("i", -1))
	if i < 0 or i >= p["shop"].size() or p["shop"][i] == "":
		return "빈 칸"
	var aid: String = p["shop"][i]
	var cost: int = GameData.cost_of[aid]
	if p["gold"] < cost:
		return "골드 부족"
	# 놓을 곳: 지정한 칸(끌어다 놓기)이 비어 있고 놓을 수 있으면 그곳, 아니면 빈 대기석
	var dest := {}
	var to: Dictionary = cmd.get("to", {})
	if not to.is_empty() and _valid_empty_target(p, aid, to):
		dest = to
	else:
		var free: int = p["bench"].find(null)
		if free >= 0:
			dest = {"bench": free}
	if dest.is_empty() and _count_copies(p, aid, 1) < 2:
		# 대기석이 가득 차도 바로 합성되면 구매 가능
		return "대기석이 가득 참"
	p["gold"] -= cost
	p["shop"][i] = ""
	if i < p.get("locks", []).size():
		p["locks"][i] = false
	var u := {"uid": _uid(), "aid": aid, "star": 1, "arts": [], "pers": ""}
	if not dest.is_empty():
		_set_at(p, dest, u)
		_fix_pers(u, dest, String(cmd.get("pers", "")))
		_try_merge(p, aid, 1)
	else:
		_try_merge(p, aid, 1, u)
	return ""


## 구매한 사도를 바로 놓을 수 있는 빈칸인지
func _valid_empty_target(p: Dictionary, aid: String, to: Dictionary) -> bool:
	if to.has("bench"):
		var b := int(to["bench"])
		return b >= 0 and b < p["bench"].size() and p["bench"][b] == null
	if to.has("board"):
		var rs := _parse_key(String(to["board"]))
		if rs[0] < 0 or rs[0] >= int(B["board_rows"]) or rs[1] < 0 or rs[1] >= int(B["board_slots"]):
			return false
		return not p["board"].has(to["board"]) and GameData.can_place(aid, rs[0]) and p["board"].size() < int(p["level"])
	return false


func _count_copies(p: Dictionary, aid: String, star: int) -> int:
	var n := 0
	for u in _all_units(p):
		if u["aid"] == aid and u["star"] == star:
			n += 1
	return n


## 같은 사도·같은 성급 3명이 모이면 합성. extra: 아직 자리에 놓이지 않은 유닛.
func _try_merge(p: Dictionary, aid: String, star: int, extra = null) -> void:
	if star >= 3:
		return
	var locs := []
	for k in p["board"]:
		var u: Dictionary = p["board"][k]
		if u["aid"] == aid and u["star"] == star:
			locs.append({"board": k})
	for i in p["bench"].size():
		var u = p["bench"][i]
		if u != null and u["aid"] == aid and u["star"] == star:
			locs.append({"bench": i})
	var have := locs.size() + (1 if extra != null else 0)
	if have < 3:
		return
	var keep: Dictionary = locs[0]
	var kept: Dictionary = unit_at(p, keep)
	var used := [kept]
	for n in range(1, mini(3, locs.size())):
		used.append(unit_at(p, locs[n]))
		_set_at(p, locs[n], null)
	if extra != null and used.size() < 3:
		used.append(extra)
	# 합성: 재료들의 아티팩트는 모두 보관함으로
	for u in used:
		for a in u["arts"]:
			p["inv"].append(a)
	var merged := {"uid": _uid(), "aid": aid, "star": star + 1, "arts": [], "pers": kept["pers"]}
	_set_at(p, keep, merged)
	_log("%s %s %d성 합성" % [p["name"], GameData.apostle(aid).get("name", aid), star + 1])
	_try_merge(p, aid, star + 1)


func _cmd_sell(p: Dictionary, cmd: Dictionary) -> String:
	var loc: Dictionary = cmd.get("loc", {})
	var u = unit_at(p, loc)
	if u == null:
		return "유닛 없음"
	p["gold"] += sell_value(u)
	for a in u["arts"]:
		p["inv"].append(a)
	_return_to_pool(u)
	_set_at(p, loc, null)
	return ""


func _cmd_move(p: Dictionary, cmd: Dictionary) -> String:
	var from: Dictionary = cmd.get("from", {})
	var to: Dictionary = cmd.get("to", {})
	var u = unit_at(p, from)
	if u == null:
		return "유닛 없음"
	if to.has("board"):
		var rs := _parse_key(to["board"])
		if rs[0] < 0 or rs[0] >= int(B["board_rows"]) or rs[1] < 0 or rs[1] >= int(B["board_slots"]):
			return "잘못된 칸"
	elif to.has("bench"):
		if int(to["bench"]) < 0 or int(to["bench"]) >= p["bench"].size():
			return "잘못된 칸"
	else:
		return "잘못된 칸"
	var other = unit_at(p, to)
	# 열 제한 검사
	if to.has("board") and not GameData.can_place(u["aid"], _parse_key(to["board"])[0]):
		return "%s은(는) %s에만 배치할 수 있음" % [GameData.apostle(u["aid"])["name"], GameData.ROW_NAME[GameData.apostle(u["aid"])["row"]]]
	if other != null and from.has("board") and not GameData.can_place(other["aid"], _parse_key(from["board"])[0]):
		return "자리를 바꿀 수 없는 열"
	# 보드 인원 제한
	if to.has("board") and not from.has("board") and other == null and p["board"].size() >= int(p["level"]):
		return "보드 인원 제한 (레벨 %d)" % p["level"]
	_set_at(p, from, other)
	_set_at(p, to, u)
	# 공명/이면: 보드에 올릴 때 성격 선택, 대기석으로 내리면 초기화
	_fix_pers(u, to, String(cmd.get("pers", "")))
	if other != null:
		_fix_pers(other, from, "")
	return ""


func _fix_pers(u: Dictionary, loc: Dictionary, wanted: String) -> void:
	var opts := GameData.personality_options(u["aid"])
	if opts.is_empty():
		u["pers"] = ""
		return
	if loc.has("bench"):
		u["pers"] = ""
	elif wanted != "" and opts.has(wanted):
		u["pers"] = wanted
	elif u["pers"] == "":
		u["pers"] = opts[0]


func _cmd_reroll(p: Dictionary) -> String:
	if p["gold"] < int(B["reroll_cost"]):
		return "골드 부족"
	p["gold"] -= int(B["reroll_cost"])
	_refresh_shop(p)
	return ""


func _cmd_buy_xp(p: Dictionary) -> String:
	if p["level"] >= int(B["max_level"]):
		return "최대 레벨"
	if p["gold"] < int(B["xp_cost"]):
		return "골드 부족"
	p["gold"] -= int(B["xp_cost"])
	_add_xp(p, int(B["xp_amount"]))
	return ""


# ─────────────────────────────── 아티팩트 ───────────────────────────────

func _roll_artifacts(r: int, n: int) -> Array:
	var out := []
	for i in n:
		out.append(_roll_artifact(r, out))
	return out


func _roll_artifact(r: int, avoid: Array = []) -> String:
	var odds: Dictionary = B["artifact_odds"].get(str(r), B["artifact_odds"].values()[-1])
	var roll := rng.randf() * 100.0
	var acc := 0.0
	var grade := "common"
	for g in B["grade_order"]:
		acc += float(odds.get(g, 0))
		if roll < acc:
			grade = g
			break
	return _random_of_grade(grade, avoid)


func _random_of_grade(grade: String, avoid: Array = []) -> String:
	var list: Array = GameData.artifacts_by_grade.get(grade, [])
	var cands := []
	for id in list:
		if not avoid.has(id):
			cands.append(id)
	if cands.is_empty():
		cands = list
	return cands[rng.randi_range(0, cands.size() - 1)]


func _cmd_art_reroll(p: Dictionary, cmd: Dictionary) -> String:
	var off: Dictionary = p["art_offer"]
	if off.is_empty():
		return "선택할 아티팩트 없음"
	var i := int(cmd.get("i", -1))
	if i < 0 or i >= off["options"].size():
		return "잘못된 칸"
	if off["rerolled"][i]:
		return "이미 다시 뽑은 칸"
	off["rerolled"][i] = true
	var others: Array = off["options"].duplicate()
	others.remove_at(i)
	off["options"][i] = _roll_artifact(state["round"], others)
	return ""


func _cmd_art_pick(p: Dictionary, cmd: Dictionary) -> String:
	var off: Dictionary = p["art_offer"]
	if off.is_empty():
		return "선택할 아티팩트 없음"
	var i := int(cmd.get("i", 0))
	if i < 0 or i >= off["options"].size():
		return "잘못된 칸"
	p["inv"].append({"uid": _uid(), "id": off["options"][i]})
	p["art_offer"] = {}
	return ""


## 아티팩트 위치: 보관함이면 {"inv": idx}, 장착 중이면 {"loc": 유닛 위치, "slot": idx}
func find_art(p: Dictionary, art_uid: int) -> Dictionary:
	for i in p["inv"].size():
		if int(p["inv"][i]["uid"]) == art_uid:
			return {"inv": i, "art": p["inv"][i]}
	for k in p["board"]:
		var u: Dictionary = p["board"][k]
		for j in u["arts"].size():
			if int(u["arts"][j]["uid"]) == art_uid:
				return {"unit": u, "slot": j, "art": u["arts"][j]}
	for u in p["bench"]:
		if u == null:
			continue
		for j in u["arts"].size():
			if int(u["arts"][j]["uid"]) == art_uid:
				return {"unit": u, "slot": j, "art": u["arts"][j]}
	return {}


func _remove_art(p: Dictionary, where: Dictionary) -> void:
	if where.has("inv"):
		p["inv"].remove_at(where["inv"])
	else:
		where["unit"]["arts"].remove_at(where["slot"])


## 장착: 보관함의 아티팩트만 장착할 수 있다 (장착 후 임의 해제 불가)
func _cmd_equip(p: Dictionary, cmd: Dictionary) -> String:
	var where := find_art(p, int(cmd.get("art", -1)))
	if where.is_empty() or not where.has("inv"):
		return "보관함에 없는 아티팩트"
	var u = unit_at(p, cmd.get("loc", {}))
	if u == null:
		return "유닛 없음"
	if u["arts"].size() >= int(B["artifact_slots"]):
		return "장착 칸이 가득 참 (최대 %d개)" % int(B["artifact_slots"])
	_remove_art(p, where)
	u["arts"].append(where["art"])
	return ""


## 같은 등급 2개 → 다음 등급 무작위 1개 (보관함으로). 장착 중인 것도 재료로 쓸 수 있다.
func _cmd_art_merge(p: Dictionary, cmd: Dictionary) -> String:
	var ua := int(cmd.get("a", -1))
	var ub := int(cmd.get("b", -1))
	if ua == ub:
		return "서로 다른 아티팩트 2개가 필요함"
	var wa := find_art(p, ua)
	var wb := find_art(p, ub)
	if wa.is_empty() or wb.is_empty():
		return "아티팩트 없음"
	var ga: String = GameData.artifact(wa["art"]["id"])["grade"]
	var gb: String = GameData.artifact(wb["art"]["id"])["grade"]
	if ga != gb:
		return "등급이 다름"
	var ng := GameData.next_grade(ga)
	if ng == "":
		return "전설 등급은 합성할 수 없음"
	# 인덱스가 밀리지 않도록 뒤쪽부터 제거
	var first := wa
	var second := wb
	if wa.has("inv") and wb.has("inv") and wb["inv"] > wa["inv"]:
		first = wb
		second = wa
	_remove_art(p, first)
	second = find_art(p, int(second["art"]["uid"]))
	_remove_art(p, second)
	var new_id := _random_of_grade(ng)
	p["inv"].append({"uid": _uid(), "id": new_id})
	_log("%s 아티팩트 합성 → %s" % [p["name"], GameData.artifact(new_id)["name"]])
	return ""
