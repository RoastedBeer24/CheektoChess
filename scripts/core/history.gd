class_name History
extends RefCounted
## 게임 기록 (user://history.json): 끝난 게임마다 순위·그룹·최종 보드·시너지를 남기고 통계를 낸다.

const PATH := "user://history.json"
const MAX_GAMES := 200


static func load_all() -> Array:
	if not FileAccess.file_exists(PATH):
		return []
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return d if typeof(d) == TYPE_ARRAY else []


## 게임이 끝났을 때 한 번 호출 (같은 seed 는 한 번만 기록)
static func record(state: Dictionary, my_pid: String, mode: String) -> void:
	var p: Dictionary = state.get("players", {}).get(my_pid, {})
	if p.is_empty():
		return
	var games := load_all()
	var seed := int(state.get("seed", 0))
	for g in games:
		if int(g.get("seed", -1)) == seed:
			return
	var board := []
	var specs := []
	for k in p.get("board", {}):
		var u: Dictionary = p["board"][k]
		board.append({"aid": u["aid"], "star": int(u["star"])})
		specs.append(u)
	var tiers := Rules.active_tiers(Rules.count_traits(specs))
	var syns := []
	for n in tiers:
		if int(tiers[n]) > 0:
			syns.append(n)
	games.append({
		"date": Time.get_datetime_string_from_system(false, true),
		"seed": seed, "mode": mode, "group": GameData.group_name(state.get("group", GameData.group_id)),
		"players": state.get("players", {}).size(), "place": int(p.get("place", 0)) if int(p.get("place", 0)) > 0 else 1,
		"round": int(state.get("round", 0)), "board": board, "synergies": syns,
	})
	if games.size() > MAX_GAMES:
		games = games.slice(games.size() - MAX_GAMES)
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(games))


## 통계: {games, wins, top4, avg_place, apostles: [[aid, 횟수]...], synergies: [[이름, 횟수]...]}
static func stats() -> Dictionary:
	var games := load_all()
	var wins := 0
	var top4 := 0
	var place_sum := 0
	var ap := {}
	var sy := {}
	for g in games:
		var pl := int(g.get("place", 0))
		place_sum += pl
		if pl == 1:
			wins += 1
		if pl <= 4:
			top4 += 1
		for u in g.get("board", []):
			ap[u["aid"]] = ap.get(u["aid"], 0) + 1
		for s in g.get("synergies", []):
			sy[s] = sy.get(s, 0) + 1
	var al := []
	for k in ap:
		al.append([k, ap[k]])
	al.sort_custom(func(a, b): return a[1] > b[1])
	var sl := []
	for k in sy:
		sl.append([k, sy[k]])
	sl.sort_custom(func(a, b): return a[1] > b[1])
	return {"games": games.size(), "wins": wins, "top4": top4,
		"avg_place": (float(place_sum) / games.size()) if not games.is_empty() else 0.0,
		"apostles": al, "synergies": sl}
