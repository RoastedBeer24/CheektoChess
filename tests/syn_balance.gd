extends Node
## 시너지 균형 대략 확인: 시너지마다 해당 사도(최대 9명, 모자라면 다른 1~2코 사도로 채움)로 팀을 만들어 서로 맞붙인다.
##   godot --headless --path . res://tests/syn_balance.tscn

func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var _ga := OS.get_cmdline_user_args()
	if _ga.size() > 0:
		GameData.set_group(_ga[0])
	var teams := {}
	var fillers := []
	for aid in GameData.roster:
		if GameData.cost_of[aid] <= 2 and GameData.traits_of(aid).size() == 1:
			fillers.append(aid)
	for name in GameData.synergies:
		if GameData.synergies[name].get("kind", "") == "unique":
			continue
		var ids := []
		for aid in GameData.roster:
			if GameData.traits_of(aid).has(name):
				ids.append(aid)
		ids = ids.slice(0, 9)
		var fi := 0
		while ids.size() < 7 and fi < fillers.size():
			if not ids.has(fillers[fi]) and not GameData.traits_of(fillers[fi]).has(name):
				ids.append(fillers[fi])
			fi += 1
		teams[name] = _army(ids.slice(0, 7))
	var names: Array = teams.keys()
	var res := {}
	for n in names:
		var on := _winrate(n, teams, names)
		# 이 팀의 시너지만 끄기: 해당 사도들의 시너지 목록에서 이 시너지를 잠시 뺀다
		var saved := {}
		for aid in GameData.group_traits:
			if GameData.group_traits[aid].has(n):
				saved[aid] = GameData.group_traits[aid]
				var copy: Array = GameData.group_traits[aid].duplicate()
				copy.erase(n)
				GameData.group_traits[aid] = copy
		var off := _winrate(n, teams, names)
		for aid in saved:
			GameData.group_traits[aid] = saved[aid]
		var cost := 0
		for u in teams[n]:
			cost += GameData.cost_of[u["aid"]]
		res[n] = [on, off, cost]
	names.sort_custom(func(a, b): return res[a][0] - res[a][1] > res[b][0] - res[b][1])
	for n in names:
		print("BAL %-22s 켬 %5.1f%%  끔 %5.1f%%  효과 %+5.1f%%p  팀 코스트 %d" % [n, res[n][0], res[n][1], res[n][0] - res[n][1], res[n][2]])
	get_tree().quit()


func _winrate(n: String, teams: Dictionary, names: Array) -> float:
	var w := 0
	var g := 0
	for m in names:
		if m == n:
			continue
		for seed in range(1, 9):
			var r := BattleSim.new(teams[n], teams[m], seed * 13 + m.length()).run()
			g += 1
			if r["winner"] == 0:
				w += 1
	return 100.0 * w / g


func _army(ids: Array) -> Array:
	var out := []
	var slots := {}
	for aid in ids:
		var a := GameData.apostle(aid)
		var row: int = {"front": 0, "mid": 1, "back": 2}.get(a.get("row", "mid"), 1)
		for k in 3:
			if slots.get(row, 0) < 3:
				break
			row = (row + 1) % 3
		var sl: int = slots.get(row, 0)
		slots[row] = sl + 1
		out.append({"aid": aid, "star": 2, "row": row, "slot": sl, "arts": [], "pers": "순수" if aid == "joanne" else ""})
	return out
