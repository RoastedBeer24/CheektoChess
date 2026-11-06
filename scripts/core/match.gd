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
var tutorial := false   # 튜토리얼 연습 판: 준비 시간이 멈춤


## rules: 방 규칙 {fast, augments, hp, gold, prep} (방장이 고름, 없으면 기본)
func _init(players: Array, seed: int, rules: Dictionary = {}) -> void:
	# players: [{id, name, bot}]
	B = rules_balance(rules)
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
			"augs": [], "aug_offer": {}, "aug_st": {}, "style": p.get("style", ""), "avatar": p.get("avatar", ""), "pet": p.get("pet", ""),
		}
	state = {
		"round": 0, "phase": "lobby", "phase_end": 0.0, "players": ps, "pool": pool,
		"battles": [], "next_uid": 1, "log": [], "winner": "", "seed": seed,
		"group": GameData.group_id, "rules": rules, "bal": rules_overrides(rules),
	}


# ─────────────────────────────── 방 규칙 ───────────────────────────────

const HP_CHOICES := [0, 150, 70]          # 0 = 기본
const GOLD_CHOICES := [0, 5, 10]
const PREP_CHOICES := [1.0, 0.7, 1.5]


## 규칙으로 바뀌는 밸런스 값만 (화면에서도 같은 값을 쓰도록 state["bal"] 에 싣는다)
static func rules_overrides(rules: Dictionary) -> Dictionary:
	var base: Dictionary = GameData.balance
	var o := {}
	var hp := int(HP_CHOICES[clampi(int(rules.get("hp", 0)), 0, 2)])
	if hp > 0:
		o["player_hp"] = hp
	var g := int(GOLD_CHOICES[clampi(int(rules.get("gold", 0)), 0, 2)])
	if g > 0:
		o["start_gold"] = int(base["start_gold"]) + g
	var pk := float(PREP_CHOICES[clampi(int(rules.get("prep", 0)), 0, 2)])
	if rules.get("fast", false):
		# 빠른 모드: 체력 60, 준비 시간 짧게, 레벨·골드·경험치를 앞당김
		o["player_hp"] = 60
		pk *= 0.7
		o["start_level"] = int(base["start_level"]) + 1
		o["start_gold"] = int(o.get("start_gold", base["start_gold"])) + 4
		o["xp_per_round"] = int(base.get("xp_per_round", 2)) + 2
	if not is_equal_approx(pk, 1.0):
		o["prep_time"] = roundf(float(base["prep_time"]) * pk)
		o["first_prep_time"] = roundf(float(base.get("first_prep_time", base["prep_time"])) * pk)
	return o


static func rules_balance(rules: Dictionary) -> Dictionary:
	var b: Dictionary = GameData.balance.duplicate(true)
	var o := rules_overrides(rules)
	for k in o:
		b[k] = o[k]
	return b


## 규칙 요약 (대기실 표시용)
static func rules_text(rules: Dictionary) -> String:
	var parts := []
	if rules.get("fast", false):
		parts.append("빠른 모드")
	var hp := int(HP_CHOICES[clampi(int(rules.get("hp", 0)), 0, 2)])
	if hp > 0 and not rules.get("fast", false):
		parts.append("체력 %d" % hp)
	var g := int(GOLD_CHOICES[clampi(int(rules.get("gold", 0)), 0, 2)])
	if g > 0:
		parts.append("시작 골드 +%d" % g)
	var pk := int(clampi(int(rules.get("prep", 0)), 0, 2))
	if pk > 0:
		parts.append(["", "준비 시간 짧게", "준비 시간 길게"][pk])
	if rules.get("augments", false):
		parts.append("증강")
	return "기본 규칙" if parts.is_empty() else " · ".join(parts)


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
					if _auto(pid):
						Bot.play(self, pid, true)
			if phase_left <= 0.0 or _all_humans_ready():
				_start_battle()
		"battle":
			if phase_left <= 0.0 or _all_humans_skipped():
				_end_battle()
		"result":
			if phase_left <= 0.0:
				_start_prep()
		"carousel":
			var car: Dictionary = state["carousel"]
			var who: String = car["order"][car["turn"]] if car["turn"] < car["order"].size() else ""
			# 봇이나 연결이 끊긴 사람은 바로, 사람은 시간이 다 되면 자동으로 고름
			if who != "" and (player(who)["bot"] or not player(who)["connected"]) and phase_left < float(B["carousel_turn"]) - 0.8:
				_carousel_pick(who, Bot.carousel_choice(self, who))
			elif phase_left <= 0.0 and who != "":
				_carousel_pick(who, -1)


## 봇이 대신 행동하는 플레이어 (봇, 또는 연결이 끊긴 사람)
func _auto(pid: String) -> bool:
	var p := player(pid)
	return not p.is_empty() and (p["bot"] or not p["connected"])


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
	# 연결이 끊긴 사람은 탈락시키지 않고 봇이 대신 플레이한다 (언제든 다시 들어오면 이어서)
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
		if has_aug(p, "xp_round") and r > 1:
			_add_xp(p, 2)
		if has_aug(p, "free_reroll"):
			p["aug_st"]["free_rr"] = 2
		if int(p["aug_st"].get("debt_left", 0)) > 0:
			p["aug_st"]["debt_left"] = int(p["aug_st"]["debt_left"]) - 1
		if has_aug(p, "u_mentor") and r > 1:
			_mentor(p)
		_compact_bench(p)
		_refresh_shop(p)
		if state["rules"].get("augments", false) and _in(GameData.augments.get("rounds", []), r):
			p["aug_offer"] = {"options": _roll_augments(p, 3), "rerolled": false}
		if is_artifact_round(r):
			p["art_offer"] = {"options": _roll_artifacts(r, int(B["artifact_choices"])), "rerolled": [false, false, false]}
	state["round_kind"] = "monster" if _in(B.get("monster_rounds", []), r) else "pvp"
	if _in(B.get("carousel_rounds", []), r):
		_start_carousel(r)
		return
	_enter_prep()


func _enter_prep() -> void:
	state["phase"] = "prep"
	state["next_pairs"] = _make_pairs() if state.get("round_kind", "pvp") == "pvp" else []
	var r: int = state["round"]
	phase_left = float(B.get("first_prep_time", B["prep_time"])) if r == 1 else float(B["prep_time"])
	if tutorial:
		phase_left = 99999.0
	_log("라운드 %d 준비 시작" % r)
	_bot_second_done = false
	for pid in alive_players():
		if _auto(pid):
			Bot.play(self, pid)
	state_changed.emit()


static func _in(list: Array, r: int) -> bool:
	for x in list:
		if int(x) == r:
			return true
	return false


# ─────────────────────────────── 공유 선택 라운드 ───────────────────────────────
## 체력이 낮은 사람부터 차례로 사도+아티팩트 묶음 하나씩 고른다.

func _start_carousel(r: int) -> void:
	var ids := alive_players()
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = ids[i]
		ids[i] = ids[j]
		ids[j] = t
	ids.sort_custom(func(a, b): return int(player(a)["hp"]) < int(player(b)["hp"]))
	# 선착순 증강: 맨 앞으로
	var firsts := ids.filter(func(x): return has_aug(player(x), "first_pick"))
	for x in firsts:
		ids.erase(x)
	ids = firsts + ids
	var max_cost := clampi(1 + r / 4, 1, 5)
	var opts := []
	for i in ids.size() + 2:
		var cands := []
		for aid in GameData.roster:
			if GameData.cost_of[aid] <= max_cost and GameData.cost_of[aid] >= max_cost - 2 and not is_banned(aid):
				cands.append(aid)
		var aid: String = cands[rng.randi_range(0, cands.size() - 1)]
		opts.append({"aid": aid, "art": _roll_artifact(r), "by": ""})
	state["carousel"] = {"options": opts, "order": ids, "turn": 0}
	state["phase"] = "carousel"
	phase_left = float(B["carousel_turn"])
	_log("라운드 %d 공유 선택" % r)
	state_changed.emit()


func _carousel_pick(pid: String, idx: int) -> void:
	var car: Dictionary = state["carousel"]
	var opts: Array = car["options"]
	if idx < 0 or idx >= opts.size() or opts[idx]["by"] != "":
		idx = -1
		for i in opts.size():
			if opts[i]["by"] == "":
				idx = i
				break
	if idx >= 0:
		var o: Dictionary = opts[idx]
		o["by"] = pid
		var p := player(pid)
		var u := {"uid": _uid(), "aid": o["aid"], "star": 1, "arts": [], "pers": ""}
		state["pool"][o["aid"]] = maxi(0, int(state["pool"].get(o["aid"], 0)) - 1)
		_receive_unit(p, u)
		_compact_bench(p)
		p["inv"].append({"uid": _uid(), "id": o["art"]})
		_log("%s: 공유 선택 %s + %s" % [p["name"], GameData.apostle(o["aid"]).get("name", ""), GameData.artifact(o["art"]).get("name", "")])
	car["turn"] += 1
	if car["turn"] >= car["order"].size():
		_enter_prep()
		return
	phase_left = float(B["carousel_turn"])
	state_changed.emit()


func is_artifact_round(r: int) -> bool:
	for x in B["artifact_rounds"]:
		if int(x) == r:
			return true
	return false


func income(p: Dictionary) -> int:
	var g := int(B["base_income"])
	var imax := int(B["interest_max"]) + (3 if has_aug(p, "interest_cap") else 0)
	if not has_aug(p, "r_hunger"):
		g += mini(int(p["gold"]) / int(B["interest_per"]), imax)
	var s: int = abs(int(p["streak"]))
	var bonus := 0
	for pair in B["streak_bonus"]:
		if s >= int(pair[0]):
			bonus = int(pair[1])
	if has_aug(p, "streak_x2"):
		bonus *= 2
	if int(p.get("aug_st", {}).get("debt_left", 0)) > 0:
		g -= 3
	return maxi(0, g + bonus)


func _start_battle() -> void:
	# 고르지 않은 아티팩트는 첫 번째 선택지로 자동 선택
	for pid in alive_players():
		var p := player(pid)
		if not p["art_offer"].is_empty():
			_cmd_art_pick(p, {"i": 0})
		if not p.get("aug_offer", {}).is_empty():
			_cmd_aug_pick(p, {"i": 0})
	state["phase"] = "battle"
	if state.get("round_kind", "pvp") == "monster":
		_start_monster_battles()
		return
	# 준비 단계 시작 때 미리 정한 대진 (다음 상대 미리보기), 그사이 바뀌었으면 새로
	var pairs: Array = state.get("next_pairs", [])
	if not _pairs_valid(pairs):
		pairs = _make_pairs()
	state["next_pairs"] = []
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
		_tally(result, [a, b if ghost == "" else ""])
		if _is_human(a) or (b != "" and _is_human(b)):
			longest = maxf(longest, float(result["end_time"]))
		battles.append({"a": a, "b": b, "ghost": ghost, "seed": seed, "army_a": army_a, "army_b": army_b,
			"winner": result["winner"], "survivors": result["survivors"], "end_time": result["end_time"],
			"deaths": result.get("deaths", [0, 0])})
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


# ─────────────────────────────── 몬스터 라운드 ───────────────────────────────
## 각자 그림자 몬스터와 싸운다. 연승·연패와 체력은 그대로, 처치 수만큼 골드, 이기면 보상.

func monster_army(r: int, seed_rng: RandomNumberGenerator) -> Array:
	var M: Dictionary = B["monster"]
	var power := float(M["power_base"]) + float(M["power_per_round"]) * r
	var MD: Dictionary = GameData.monsters
	var rule: Dictionary = MD.get("rounds", {}).get(str(r), {})
	if MD.get("list", []).is_empty():
		return _shadow_army(r, seed_rng, power)
	if rule.is_empty():
		# 정해지지 않은 라운드: 라운드에 맞는 종류로
		rule = {"kind": "small", "n": 2} if r <= 1 else ({"kind": "squad"} if r < 6 else ({"kind": "mid", "minions": 3} if r < 13 else {"kind": "boss", "minions": 4}))
	var by_tier := {}
	for mo in MD["list"]:
		by_tier[mo["tier"]] = by_tier.get(mo["tier"], []) + [mo["id"]]
	var pick := func(arr: Array) -> String: return arr[seed_rng.randi_range(0, arr.size() - 1)]
	var ids := []
	match String(rule["kind"]):
		"small":
			for i in int(rule.get("n", 2)):
				ids.append(pick.call(by_tier.get("small", [])))
		"squad":
			var sq: Array = MD.get("squads", [])
			ids = (sq[seed_rng.randi_range(0, sq.size() - 1)] as Array).duplicate()
		"mid", "boss":
			ids.append(pick.call(by_tier.get(String(rule["kind"]), [])))
			var pool: Array = by_tier.get(String(rule.get("minion_tier", "squad" if rule["kind"] == "boss" else "small")), [])
			for i in int(rule.get("minions", 3)):
				ids.append(pick.call(pool))
	var out := []
	var used := {}
	for aid in ids:
		var mo := GameData.monster(aid)
		var row: int = {"front": 0, "mid": 1, "back": 2}.get(mo.get("row", "front"), 0)
		for k in 3:
			if int(used.get(row, 0)) < 3:
				break
			row = (row + 1) % 3
		var slot: int = used.get(row, 0)
		used[row] = slot + 1
		out.append({"aid": aid, "star": 2 if r >= 14 else 1, "row": row, "slot": slot, "arts": [], "pers": "", "monster": true,
			"mpow": power, "mhp": float(mo.get("hp", 1.0)), "matk": float(mo.get("atk", 1.0)), "scale": float(mo.get("size", 1.0))})
	return out


## (몬스터 데이터가 없을 때) 그룹 사도를 어둡게 칠한 그림자 몬스터
func _shadow_army(r: int, seed_rng: RandomNumberGenerator, power: float) -> Array:
	var M: Dictionary = B["monster"]
	var n := clampi(int(M["count_base"]) + int(r * float(M["count_per_round"])), 1, int(M["count_max"]))
	var max_cost := clampi(1 + r / 5, 1, 5)
	var cands := []
	for aid in GameData.roster:
		if GameData.cost_of[aid] <= max_cost:
			cands.append(aid)
	var out := []
	var used := {}
	for i in n:
		var aid: String = cands[seed_rng.randi_range(0, cands.size() - 1)]
		var row: int = {"front": 0, "mid": 1, "back": 2}.get(GameData.apostle(aid).get("row", "mid"), 1)
		for k in 3:
			if int(used.get(row, 0)) < 3:
				break
			row = (row + 1) % 3
		var slot: int = used.get(row, 0)
		used[row] = slot + 1
		out.append({"aid": aid, "star": 2 if r >= 14 else 1, "row": row, "slot": slot, "arts": [], "pers": "", "monster": true, "mpow": power, "shadow": true})
	return out


## 섞은 뒤 직전 상대와 겹치지 않게 짝을 맞춘다. 홀수면 한 명은 다른 플레이어 보드를 복제한 유령과.
func _make_pairs() -> Array:
	var ids := alive_players()
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
		var a: String = pending[0]
		var others := alive_players()
		others.erase(a)
		var ghost_of: String = others[rng.randi_range(0, others.size() - 1)] if not others.is_empty() else a
		pairs.append([a, "", ghost_of])
	return pairs


func _pairs_valid(pairs: Array) -> bool:
	if pairs.is_empty():
		return false
	var alive := alive_players()
	var seen := 0
	for pr in pairs:
		for k in [0, 1]:
			if String(pr[k]) == "":
				continue
			if not alive.has(pr[k]):
				return false
			seen += 1
	return seen == alive.size()


## 다음 상대 (pid → 상대 이름용 정보): {"opp": pid, "ghost": pid} / 몬스터 라운드면 {"monster": true}
func next_opponent(pid: String) -> Dictionary:
	if state.get("round_kind", "pvp") == "monster":
		return {"monster": true}
	for pr in state.get("next_pairs", []):
		if pr[0] == pid:
			return {"opp": pr[1], "ghost": pr[2]}
		if pr[1] == pid:
			return {"opp": pr[0], "ghost": ""}
	return {}


func _start_monster_battles() -> void:
	var r: int = state["round"]
	var battles := []
	var longest := 0.0
	for pid in alive_players():
		var seed := rng.randi()
		var mr := RandomNumberGenerator.new()
		mr.seed = seed
		var army_a := army_of(pid)
		var army_b := monster_army(r, mr)
		var result := BattleSim.new(army_a, army_b, seed).run()
		_tally(result, [pid, ""])
		if _is_human(pid):
			longest = maxf(longest, float(result["end_time"]))
		battles.append({"a": pid, "b": "", "ghost": "", "monster": true, "seed": seed, "army_a": army_a, "army_b": army_b,
			"winner": result["winner"], "survivors": result["survivors"], "end_time": result["end_time"],
			"kills": int(result.get("deaths", [0, 0])[1])})
	state["battles"] = battles
	phase_left = (longest + 2.5) if longest > 0.0 else 3.0
	state["battle_len"] = phase_left
	for pid in state["players"]:
		player(pid)["skip"] = false
	_log("라운드 %d 몬스터 전투" % r)
	state_changed.emit()


func _monster_reward(bt: Dictionary) -> void:
	var p := player(bt["a"])
	var r: int = state["round"]
	var gold := mini(int(bt.get("kills", 0)), int(B["monster"]["kill_gold_max"]))
	if has_aug(p, "monster_x2"):
		gold *= 2
	var art := ""
	if int(bt["winner"]) == 0:
		if r <= 2:
			gold += 1
		else:
			art = _roll_artifact(r)
			p["inv"].append({"uid": _uid(), "id": art})
	p["gold"] += gold
	bt["reward"] = {"gold": gold, "art": art}


func _end_battle() -> void:
	var r: int = state["round"]
	var base_dmg := int(B["damage_base"]) + r / int(B["damage_per_round_div"])
	for bt in state["battles"]:
		if bt.get("monster", false):
			_monster_reward(bt)
			continue
		var a := player(bt["a"])
		var b := player(bt["b"]) if bt["b"] != "" else {}
		# 현상금: 쓰러뜨린 적 1명마다 1골드 (최대 4)
		var dth: Array = bt.get("deaths", [0, 0])
		if has_aug(a, "b_bounty"):
			a["gold"] += mini(4, int(dth[1]))
		if not b.is_empty() and has_aug(b, "b_bounty"):
			b["gold"] += mini(4, int(dth[0]))
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
		_aug_after_battle(a, bt, 0)
		_syn_after_battle(a, bt, 0)
		if not b.is_empty():
			_aug_after_battle(b, bt, 1)
			_syn_after_battle(b, bt, 1)
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
	var gm: Dictionary = p["aug_st"].get("gamble", {})
	if not gm.is_empty():
		gm["won"] = int(gm["won"]) + 1
		if int(gm["won"]) >= 3:
			p["aug_st"].erase("gamble")
			p["gold"] += 15
			p["inv"].append({"uid": _uid(), "id": _random_of_grade("legend")})
			_log("%s 도박사 성공! 전설 아티팩트 + 15골드" % p["name"])


func _lose(p: Dictionary, dmg: int) -> void:
	p["streak"] = mini(-1, int(p["streak"]) - 1)
	if p["aug_st"].get("insurance", false):
		p["aug_st"].erase("insurance")
		_log("%s 보험으로 체력 피해 없음" % p["name"])
	else:
		p["hp"] -= dmg
	_synergy_reward(p, false)
	if p["aug_st"].has("gamble"):
		p["aug_st"].erase("gamble")
	if has_aug(p, "lose_xp"):
		_add_xp(p, 4)


## 전투 결과에 따른 시너지 보상 (델리아 탐험대: 골드, n승마다 아티팩트)
func _synergy_reward(p: Dictionary, won: bool) -> void:
	var specs := []
	for k in p["board"]:
		specs.append(p["board"][k])
	var tiers := Rules.active_tiers(Rules.apply_emblems(Rules.count_traits(specs), p.get("augs", [])))
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


## 플레이어 전투 뒤 시너지 보상 (볼스패닉): 처치 약탈 골드, 야근 수당, 끝까지 생존 골드, 퀘스트 진행, 단골 포인트
func _syn_after_battle(p: Dictionary, bt: Dictionary, side: int) -> void:
	var specs := []
	for k in p["board"]:
		specs.append(p["board"][k])
	var tiers := Rules.active_tiers(Rules.apply_emblems(Rules.count_traits(specs), p.get("augs", [])))
	var won := int(bt["winner"]) == side
	var kills := int(bt.get("deaths", [0, 0])[1 - side])
	for name in tiers:
		var tier: int = tiers[name]
		var levels: Array = GameData.synergies.get(name, {}).get("levels", [])
		if tier <= 0 or tier - 1 >= levels.size():
			continue
		var spec: Dictionary = levels[tier - 1]
		var g := 0
		if spec.has("gold_kills") and won:
			g += mini(kills / int(spec["gold_kills"]["per"]), int(spec["gold_kills"]["max"]))
		if spec.has("gold_overtime") and float(bt.get("end_time", 0.0)) >= float(spec["gold_overtime"]["t"]):
			g += int(spec["gold_overtime"]["g"])
		if spec.has("gold_survive") and won:
			g += int(spec["gold_survive"])
		if g > 0:
			p["gold"] += g
			_log("%s: %s +%d골드" % [p["name"], name, g])
		if spec.get("points_round", false):
			if not p.has("syn_pts"):
				p["syn_pts"] = {}
			p["syn_pts"][name] = int(p["syn_pts"].get(name, 0)) + 1
		if spec.has("quest"):
			if not p.has("quest"):
				p["quest"] = {}
			var q: Dictionary = p["quest"].get(name, {"n": 0, "step": 0})
			q["n"] = int(q["n"]) + kills * int(spec["quest"].get("mult", 1))
			var steps: Array = spec["quest"]["steps"]
			while int(q["step"]) < steps.size() and int(q["n"]) >= int(steps[q["step"]]):
				var reward: String = spec["quest"]["rewards"][q["step"]]
				q["step"] = int(q["step"]) + 1
				match reward:
					"gold":
						p["gold"] += 6
					"art":
						p["inv"].append({"uid": _uid(), "id": _random_of_grade("advanced")})
					"rare":
						p["inv"].append({"uid": _uid(), "id": _random_of_grade("rare")})
				_log("%s: %s 퀘스트 %d단계 완료!" % [p["name"], name, q["step"]])
			p["quest"][name] = q


func _eliminate(pid: String, remaining: int) -> void:
	var p := player(pid)
	p["alive"] = false
	p["place"] = remaining
	p["last_board"] = p["board"].duplicate(true)   # 기록·통계용 (탈락 직전 보드)
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
		_log("%s 연결 끊김 — 다시 들어올 때까지 봇이 대신 플레이" % p["name"])
	else:
		_log("%s 재접속" % p["name"])
	state_changed.emit()


## 탈락하지 않았으면 언제든 재접속 허용 (끊긴 동안은 봇이 대신 플레이)
func can_rejoin(pid: String) -> bool:
	var p := player(pid)
	return not p.is_empty() and p["alive"] and not p["connected"]


# ─────────────────────────────── 방장 넘기기 ───────────────────────────────
## 상태(state) + 방장만 가진 값(난수 상태 등)을 state 안에 함께 실어 보낸다.
## 방장이 나가면 참가자 중 한 명이 마지막으로 받은 state 로 Match 를 이어서 만든다.

func pack_host_meta() -> void:
	state["_host_meta"] = {"rng": rng.state, "seed": rng.seed, "bot2": _bot_second_done, "phase_left": phase_left}


static func from_state(s: Dictionary) -> Match:
	var m := Match.new([], 0, s.get("rules", {}))
	m.state = s.duplicate(true)
	var meta: Dictionary = m.state.get("_host_meta", {})
	m.rng.seed = int(meta.get("seed", 1))
	m.rng.state = int(meta.get("rng", 0))
	m._bot_second_done = bool(meta.get("bot2", false))
	m.phase_left = float(m.state.get("phase_end", meta.get("phase_left", 10.0)))
	return m


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
	# 대기석 인원·시너지 포인트 (볼스패닉 시너지용 — 0 이면 넣지 않아 예전 기록과 같음)
	var bench_n := 0
	for b in p["bench"]:
		if b != null:
			bench_n += 1
	for spec in out:
		if bench_n > 0:
			spec["bench_n"] = bench_n
		if not p.get("syn_pts", {}).is_empty():
			spec["syn_pts"] = p["syn_pts"].duplicate()
	var augs := battle_augs(p)
	if not augs.is_empty():
		for spec in out:
			spec["augs"] = augs
	return out


## 전투에 쓰이는 증강 효과 (시너지 형식 spec). 조건·수량이 있는 것은 지금 상태로 계산해 넣는다.
func battle_augs(p: Dictionary) -> Array:
	var out := []
	for a in p.get("augs", []):
		var id: String = a["id"]
		if id == "emblem":
			out.append({"id": id, "emblem": a.get("trait", "")})
			continue
		if id == "b_underdog" and int(p["hp"]) > 50:
			continue
		if id == "b_cheer":
			var n := 0
			for u in p["bench"]:
				if u != null:
					n += 1
			if n > 0:
				out.append({"id": id, "spec": {"team_mods": {"atk": 3 * n}}})
			continue
		var d: Dictionary = GameData.augment(id)
		if d.has("spec"):
			out.append({"id": id, "spec": d["spec"]})
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
	# 인연: 첫 칸(잠기지 않았으면)에 내가 가진 사도
	if has_aug(p, "fated") and locks[0] != true:
		var owned := []
		for u in _all_units(p):
			if int(u["star"]) < 3 and int(state["pool"].get(u["aid"], 0)) > 0 and not owned.has(u["aid"]) and not is_banned(u["aid"]):
				owned.append(u["aid"])
		if not owned.is_empty():
			var pick: String = owned[rng.randi_range(0, owned.size() - 1)]
			if shop[0] != "":
				state["pool"][shop[0]] += 1
			state["pool"][pick] -= 1
			shop[0] = pick
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
			if GameData.cost_of[aid] == c and state["pool"][aid] > 0 and not is_banned(aid):
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
	var err := _command(pid, cmd)
	var pc := player(pid)
	if not pc.is_empty() and pc["bench"].size() > int(B["bench_size"]):
		_compact_bench(pc)
		state_changed.emit()
	return err


func _command(pid: String, cmd: Dictionary) -> String:
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
	if t == "carousel_pick":
		if state["phase"] != "carousel":
			return "공유 선택 중이 아님"
		var car: Dictionary = state["carousel"]
		if car["turn"] >= car["order"].size() or car["order"][car["turn"]] != pid:
			return "아직 내 차례가 아님"
		var ci := int(cmd.get("i", -1))
		if ci < 0 or ci >= car["options"].size() or car["options"][ci]["by"] != "":
			return "이미 가져간 묶음"
		_carousel_pick(pid, ci)
		return ""
	var prep_only := ["buy", "sell", "move", "reroll", "buy_xp", "art_reroll", "art_pick", "equip", "art_merge", "ready", "aug_pick", "aug_reroll", "undo_sell"]
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
		"undo_sell": err = _cmd_undo_sell(p)
		"aug_pick": err = _cmd_aug_pick(p, cmd)
		"aug_reroll": err = _cmd_aug_reroll(p)
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
		return not p["board"].has(to["board"]) and can_place_p(p, aid, rs[0]) and p["board"].size() < board_cap(p)
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
	if star + 1 >= 3:
		# ★3 이 나온 사도는 이 게임에서 더는 등장하지 않음 (모든 사람의 상점·공유 선택)
		if not state.has("banned"):
			state["banned"] = {}
		state["banned"][aid] = true
		for pid in state["players"]:
			var q: Dictionary = state["players"][pid]
			for k in q.get("shop", []).size():
				if q["shop"][k] == aid:
					q["shop"][k] = ""
					state["pool"][aid] += 1
	_set_at(p, keep, merged)
	_log("%s %s %d성 합성" % [p["name"], GameData.apostle(aid).get("name", aid), star + 1])
	if has_aug(p, "merge_gold"):
		p["gold"] += 2
	_try_merge(p, aid, star + 1)


## 되돌리기: 이번 준비 단계에서 마지막으로 판 사도를 판 값 그대로 다시 사 온다 (실수 방지)
func _cmd_undo_sell(p: Dictionary) -> String:
	var ls: Dictionary = p.get("last_sold", {})
	if ls.is_empty() or int(ls.get("round", -1)) != int(state["round"]):
		return "되돌릴 판매가 없음"
	var free: int = p["bench"].find(null)
	if free < 0:
		return "대기석이 가득 참"
	var u: Dictionary = ls["unit"]
	var need := int(ls["value"])
	if p["gold"] < need:
		return "골드 부족"
	var n := int(pow(3, int(u["star"]) - 1))
	if int(state["pool"].get(u["aid"], 0)) < n:
		return "남은 사도가 없음"
	p["gold"] -= need
	state["pool"][u["aid"]] -= n
	u["arts"] = []
	p["bench"][free] = u
	p["last_sold"] = {}
	_try_merge(p, u["aid"], int(u["star"]))
	return ""


func _cmd_sell(p: Dictionary, cmd: Dictionary) -> String:
	var loc: Dictionary = cmd.get("loc", {})
	var u = unit_at(p, loc)
	if u == null:
		return "유닛 없음"
	var val := sell_value(u)
	p["gold"] += val
	for a in u["arts"]:
		p["inv"].append(a)
	p["last_sold"] = {"round": int(state["round"]), "value": val, "unit": {"uid": u["uid"], "aid": u["aid"], "star": u["star"], "arts": [], "pers": u.get("pers", "")}}
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
	if to.has("board") and not can_place_p(p, u["aid"], _parse_key(to["board"])[0]):
		return "%s %s 전용" % [GameData.josa(GameData.apostle(u["aid"])["name"], "은", "는"), GameData.ROW_NAME[GameData.apostle(u["aid"])["row"]]]
	if other != null and from.has("board") and not can_place_p(p, other["aid"], _parse_key(from["board"])[0]):
		return "자리를 바꿀 수 없는 열"
	# 보드 인원 제한
	if to.has("board") and not from.has("board") and other == null and p["board"].size() >= board_cap(p):
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
	if int(p["aug_st"].get("free_rr", 0)) > 0:
		p["aug_st"]["free_rr"] = int(p["aug_st"]["free_rr"]) - 1
		_refresh_shop(p)
		return ""
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
	if u["arts"].size() >= art_slots(u["aid"]):
		return "장착 칸이 가득 참 (최대 %d개)" % art_slots(u["aid"])
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


# ─────────────────────────────── 증강 ───────────────────────────────

# ─────────────────────────────── 게임 MVP ───────────────────────────────
## 전투 결과를 사도별로 쌓는다 (플레이어 → 사도 id → 준 피해·받은 피해·막은 피해·회복·처치·전투 수)
func _tally(result: Dictionary, owners: Array) -> void:
	var units: Array = result.get("units", [])
	var by_i := {}
	for u in units:
		by_i[int(u["i"])] = u
	var acc := {}
	var shield := {}
	for e in result.get("events", []):
		var kind: String = e[1]
		if kind == "dmg":
			_tally_add(acc, by_i, int(e[2]), "dealt", float(e[4]))
			_tally_add(acc, by_i, int(e[3]), "taken", float(e[4]))
			var before: float = shield.get(int(e[3]), 0.0)
			if float(e[7]) < before:
				_tally_add(acc, by_i, int(e[3]), "blocked", before - float(e[7]))
			shield[int(e[3])] = float(e[7])
		elif kind == "shield":
			shield[int(e[3])] = float(e[7])
		elif kind == "heal":
			_tally_add(acc, by_i, int(e[2]), "heal", float(e[4]))
		elif kind == "death" and int(e[2]) != int(e[3]):
			_tally_add(acc, by_i, int(e[2]), "kills", 1.0)
	for u in units:
		var side := int(u["side"])
		var pid: String = owners[side] if side < owners.size() else ""
		if pid == "" or u.get("summon", false) or u.get("monster", false):
			continue
		var p := player(pid)
		if p.is_empty():
			continue
		if not p.has("mvp"):
			p["mvp"] = {}
		var aid: String = u["aid"]
		var st: Dictionary = p["mvp"].get(aid, {"dealt": 0.0, "taken": 0.0, "blocked": 0.0, "heal": 0.0, "kills": 0.0, "battles": 0})
		var a: Dictionary = acc.get(int(u["i"]), {})
		for k in ["dealt", "taken", "blocked", "heal", "kills"]:
			st[k] = roundf(float(st[k]) + float(a.get(k, 0.0)))
		st["battles"] = int(st["battles"]) + 1
		st["star"] = maxi(int(st.get("star", 1)), int(u.get("star", 1)))
		p["mvp"][aid] = st


func _tally_add(acc: Dictionary, by_i: Dictionary, i: int, key: String, v: float) -> void:
	if not by_i.has(i):
		return
	if not acc.has(i):
		acc[i] = {}
	acc[i][key] = float(acc[i].get(key, 0.0)) + v


## 종합 점수 (준 피해 + 회복 + 막은 피해·받은 피해 일부 + 처치·출전 보너스)
static func mvp_score(st: Dictionary) -> float:
	return float(st.get("dealt", 0)) + float(st.get("heal", 0)) + 0.8 * float(st.get("blocked", 0)) \
		+ 0.3 * float(st.get("taken", 0)) + 120.0 * float(st.get("kills", 0)) + 40.0 * float(st.get("battles", 0))


## 플레이어의 MVP 사도 n명: [[aid, 기록], ...] 점수 높은 순
static func mvp_top(p: Dictionary, n: int = 3) -> Array:
	var rows := []
	for aid in p.get("mvp", {}):
		rows.append([aid, p["mvp"][aid]])
	rows.sort_custom(func(x, y): return mvp_score(x[1]) > mvp_score(y[1]))
	return rows.slice(0, n)


func is_banned(aid: String) -> bool:
	return state.get("banned", {}).has(aid)


static func has_aug(p: Dictionary, id: String) -> bool:
	for a in p.get("augs", []):
		if a["id"] == id:
			return true
	return false


## 사도 한 명의 아티팩트 칸 (기본 3, 고유 시너지 'art_slot_plus' 가 있으면 +1)
static func art_slots(aid: String) -> int:
	var n := int(GameData.balance["artifact_slots"])
	for t in GameData.traits_of(aid):
		var lv: Array = GameData.synergies.get(t, {}).get("levels", [])
		if not lv.is_empty() and int(lv[0].get("art_slot_plus", 0)) > 0:
			n += int(lv[0]["art_slot_plus"])
	return n


## 보드 인원 = 레벨 (+ 확장 보드)
static func board_cap(p: Dictionary) -> int:
	return int(p["level"]) + (1 if has_aug(p, "board_plus") else 0) + (1 if has_aug(p, "r_hunger") else 0)


## 열 제한 (자유 배치 증강이면 아무 열)
static func can_place_p(p: Dictionary, aid: String, row: int) -> bool:
	return has_aug(p, "free_row") or GameData.can_place(aid, row)


func _roll_augments(p: Dictionary, n: int) -> Array:
	var pool := []
	for a in GameData.augments.get("list", []):
		if a["id"] != "emblem" and has_aug(p, a["id"]):
			continue
		pool.append(a["id"])
	var out := []
	var guard := 0
	while out.size() < n and not pool.is_empty() and guard < 100:
		guard += 1
		var id: String = pool[rng.randi_range(0, pool.size() - 1)]
		pool.erase(id)
		if id == "emblem":
			var traits: Array = GameData.synergies.keys().filter(func(t): return GameData.synergies[t].get("kind", "") != "unique")
			traits.sort()
			if traits.is_empty():
				continue
			out.append({"id": "emblem", "trait": traits[rng.randi_range(0, traits.size() - 1)]})
		else:
			out.append({"id": id})
	return out


func _cmd_aug_reroll(p: Dictionary) -> String:
	var off: Dictionary = p.get("aug_offer", {})
	if off.is_empty():
		return "고를 증강이 없음"
	if off.get("rerolled", false):
		return "이미 다시 뽑음"
	off["options"] = _roll_augments(p, 3)
	off["rerolled"] = true
	return ""


func _cmd_aug_pick(p: Dictionary, cmd: Dictionary) -> String:
	var off: Dictionary = p.get("aug_offer", {})
	if off.is_empty():
		return "고를 증강이 없음"
	var i := int(cmd.get("i", -1))
	if i < 0 or i >= off["options"].size():
		return "잘못된 선택"
	var a: Dictionary = off["options"][i]
	p["aug_offer"] = {}
	p["augs"].append(a)
	_apply_aug_now(p, a)
	_log("%s 증강: %s" % [p["name"], GameData.augment_name(a)])
	return ""


## 고른 즉시 효과
func _apply_aug_now(p: Dictionary, a: Dictionary) -> void:
	match String(a["id"]):
		"gold_now":
			p["gold"] += 18
		"debt":
			p["gold"] += 30
			p["aug_st"]["debt_left"] = 5
		"free_reroll":
			p["aug_st"]["free_rr"] = 2
		"rookie3":
			_give_unit(p, 3, 2)
		"talent4":
			_give_unit(p, 4, 1)
			p["gold"] += 5
		"heal_hp":
			p["hp"] = mini(int(B["player_hp"]), int(p["hp"]) + 25)
		"arts2":
			for k in 2:
				p["inv"].append({"uid": _uid(), "id": _random_of_grade("advanced")})
		"art_rare":
			p["inv"].append({"uid": _uid(), "id": _random_of_grade("rare")})
			p["gold"] += 5
		"gamble":
			p["aug_st"]["gamble"] = {"won": 0}
		"insurance":
			p["aug_st"]["insurance"] = true
		"r_glass":
			p["hp"] = maxi(1, int(p["hp"]) - 15)
		"r_cursed":
			p["hp"] = maxi(1, int(p["hp"]) - 12)
			p["inv"].append({"uid": _uid(), "id": _random_of_grade("legend")})
		"r_allin":
			p["aug_st"]["allin"] = int(p["gold"])
			p["gold"] = 0
		"u_upgrade":
			_upgrade_best(p)
		"u_reshape":
			for k in 2:
				_reshape_one(p)
		"u_twin":
			_twin(p)


# ─────────────────────────────── 증강 2차: 퀘스트 · 모험 · 사도 변형 ───────────────────────────────

## 플레이어 전투가 끝난 뒤 (승패 처리 후): 퀘스트 확인, 올인 정산
func _aug_after_battle(p: Dictionary, bt: Dictionary, side: int) -> void:
	if p.is_empty() or p.get("augs", []).is_empty():
		return
	var won := int(bt["winner"]) == side
	var dth: Array = bt.get("deaths", [0, 0])
	var st: Dictionary = p["aug_st"]
	if has_aug(p, "q_flawless") and won and int(dth[side]) == 0:
		p["gold"] += 2
		_log("%s 무결점 승리 +2골드" % p["name"])
	if has_aug(p, "q_streak") and not st.get("q_streak", false) and int(p["streak"]) >= 3:
		st["q_streak"] = true
		p["gold"] += 8
		for k in 2:
			p["inv"].append({"uid": _uid(), "id": _random_of_grade("advanced")})
		_log("%s 연승 행진 달성! 고급 아티팩트 2개 + 8골드" % p["name"])
	if has_aug(p, "q_maxsyn") and not st.get("q_maxsyn", false) and won and _has_max_synergy(p):
		st["q_maxsyn"] = true
		p["gold"] += 10
		for k in 2:
			p["inv"].append({"uid": _uid(), "id": _random_of_grade("rare")})
		_log("%s 시너지 완성 달성! 희귀 아티팩트 2개 + 10골드" % p["name"])
	if has_aug(p, "q_star2") and not st.get("q_star2", false):
		var n := 0
		for k in p["board"]:
			if int(p["board"][k]["star"]) >= 2:
				n += 1
		if n >= 5:
			st["q_star2"] = true
			_give_unit(p, 4, 2)
			_log("%s 합성 장인 달성! 4코스트 ★2 사도" % p["name"])
	if st.has("allin"):
		var bet := int(st["allin"])
		st.erase("allin")
		if won:
			p["gold"] += bet * 2
			_log("%s 올인 성공! +%d골드" % [p["name"], bet * 2])
		else:
			_log("%s 올인 실패" % p["name"])


## 보드에 최고 단계로 발동한 일반 시너지가 있는지
func _has_max_synergy(p: Dictionary) -> bool:
	var specs := []
	for k in p["board"]:
		specs.append(p["board"][k])
	var tiers := Rules.active_tiers(Rules.apply_emblems(Rules.count_traits(specs), p.get("augs", [])))
	for n in tiers:
		var syn: Dictionary = GameData.synergies.get(n, {})
		if syn.get("kind", "") != "unique" and int(tiers[n]) > 0 and int(tiers[n]) >= syn.get("tiers", []).size():
			return true
	return false


## 가장 비싼 ★1 사도 (보드 우선) 를 ★2 로
func _upgrade_best(p: Dictionary) -> void:
	var best = null
	for u in _all_units(p):
		if int(u["star"]) == 1 and (best == null or GameData.cost_of.get(u["aid"], 1) > GameData.cost_of.get(best["aid"], 1)):
			best = u
	if best == null:
		p["gold"] += 6
		return
	best["star"] = 2
	_try_merge(p, best["aid"], 2)


## 무작위 사도 하나를 코스트 +1 사도로 (같은 별, 아티팩트 유지)
func _reshape_one(p: Dictionary) -> void:
	var cands := _all_units(p).filter(func(u): return GameData.cost_of.get(u["aid"], 1) < 5 and int(u["star"]) <= 2)
	if cands.is_empty():
		return
	var u: Dictionary = cands[rng.randi_range(0, cands.size() - 1)]
	var need := int(pow(3, int(u["star"]) - 1))
	var to_cost: int = GameData.cost_of.get(u["aid"], 1) + 1
	var row := -1
	for k in p["board"]:
		if p["board"][k] == u:
			row = _parse_key(k)[0]
	var opts := []
	for aid in state["pool"]:
		if GameData.cost_of.get(aid, 0) == to_cost and int(state["pool"][aid]) >= need and not is_banned(aid) and (row < 0 or can_place_p(p, aid, row)):
			opts.append(aid)
	opts.sort()
	if opts.is_empty():
		return
	var nid: String = opts[rng.randi_range(0, opts.size() - 1)]
	_return_to_pool(u)
	state["pool"][nid] -= need
	u["aid"] = nid
	u["pers"] = ""
	_try_merge(p, nid, int(u["star"]))


## 가장 비싼 사도(★2 이하)의 같은 별 복제를 대기석에
func _twin(p: Dictionary) -> void:
	var best = null
	for u in _all_units(p):
		if int(u["star"]) <= 2 and (best == null or GameData.cost_of.get(u["aid"], 1) * int(u["star"]) > GameData.cost_of.get(best["aid"], 1) * int(best["star"])):
			best = u
	if best == null:
		p["gold"] += 6
		return
	var need := int(pow(3, int(best["star"]) - 1))
	if int(state["pool"].get(best["aid"], 0)) < need or is_banned(best["aid"]):
		p["gold"] += 6
		return
	state["pool"][best["aid"]] -= need
	_receive_unit(p, {"uid": _uid(), "aid": best["aid"], "star": int(best["star"]), "arts": [], "pers": ""})


## 멘토링: 라운드마다 보드에서 가장 싼 ★1 사도의 같은 사도 1장을 대기석에
func _mentor(p: Dictionary) -> void:
	var best = null
	for k in p["board"]:
		var u: Dictionary = p["board"][k]
		if int(u["star"]) == 1 and (best == null or GameData.cost_of.get(u["aid"], 1) < GameData.cost_of.get(best["aid"], 1)):
			best = u
	if best == null or int(state["pool"].get(best["aid"], 0)) < 1 or is_banned(best["aid"]):
		return
	state["pool"][best["aid"]] -= 1
	_receive_unit(p, {"uid": _uid(), "aid": best["aid"], "star": 1, "arts": [], "pers": ""})


# ─────────────────────────────── 대기석 넘침 칸 ───────────────────────────────
## 대기석이 가득 찬 상태에서 사도를 받으면(공유 선택·증강 등) 대기석 끝에 임시 칸을 최대 2개까지 붙인다.
## 빈칸이 생기면 임시 칸의 사도가 그리로 옮겨지고 임시 칸은 없어진다.
const BENCH_OVERFLOW := 2


## 받은 사도를 대기석에 (빈칸 → 임시 칸). 못 넣으면 false
func _bench_put(p: Dictionary, u: Dictionary) -> bool:
	var size := int(B["bench_size"])
	for i in mini(size, p["bench"].size()):
		if p["bench"][i] == null:
			p["bench"][i] = u
			return true
	if p["bench"].size() < size + BENCH_OVERFLOW:
		p["bench"].append(u)
		return true
	return false


## 임시 칸의 사도를 빈 대기석으로 옮기고, 빈 임시 칸은 없앤다
func _compact_bench(p: Dictionary) -> void:
	var size := int(B["bench_size"])
	var b: Array = p["bench"]
	if b.size() <= size:
		return
	for i in range(size, b.size()):
		if b[i] == null:
			continue
		var free := b.find(null)
		if free >= 0 and free < size:
			b[free] = b[i]
			b[i] = null
	while b.size() > size and b[-1] == null:
		b.pop_back()
	# 가운데가 빈 임시 칸도 정리
	var keep := b.slice(0, size)
	for i in range(size, b.size()):
		if b[i] != null:
			keep.append(b[i])
	p["bench"] = keep


## 받은 사도를 넣는다: 대기석·임시 칸 → 바로 합성 → 그래도 안 되면 골드 (사도는 풀로 돌려놓음)
func _receive_unit(p: Dictionary, u: Dictionary) -> void:
	if _bench_put(p, u):
		_try_merge(p, u["aid"], int(u["star"]))
		return
	if int(u["star"]) == 1 and _count_copies(p, u["aid"], 1) >= 2:
		_try_merge(p, u["aid"], 1, u)
		return
	var g: int = GameData.cost_of.get(u["aid"], 1) * int(pow(3, int(u["star"]) - 1))
	p["gold"] += g
	_return_to_pool(u)
	_log("%s: 대기석이 가득 차 %s 을(를) %d골드로 바꿈" % [p["name"], GameData.apostle(u["aid"]).get("name", ""), g])
	p["notice"] = {"t": "대기석이 가득 차 %s 을(를) %d골드로 바꿨습니다" % [GameData.apostle(u["aid"]).get("name", ""), g], "n": int(p.get("notice", {}).get("n", 0)) + 1}


## 무작위 cost 코스트 사도 ★star 를 대기석에 (자리가 없으면 그 값만큼 골드)
func _give_unit(p: Dictionary, cost: int, star: int) -> void:
	var cands := []
	for aid in state["pool"]:
		if GameData.cost_of.get(aid, 0) == cost and int(state["pool"][aid]) >= (3 if star == 2 else 1) and not is_banned(aid):
			cands.append(aid)
	cands.sort()
	if cands.is_empty():
		p["gold"] += cost * (3 if star == 2 else 1)
		return
	var aid: String = cands[rng.randi_range(0, cands.size() - 1)]
	state["pool"][aid] -= 3 if star == 2 else 1
	_receive_unit(p, {"uid": _uid(), "aid": aid, "star": star, "arts": [], "pers": ""})
