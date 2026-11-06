extends Node
## 그룹 하나로 봇 8명 게임을 여러 판: 오류 없이 끝나는지, 시너지별 발동 횟수·1위 보드 시너지
##   godot --headless --path . res://tests/group_games.tscn -- <그룹 id> [판 수]
func _ready():
	App.start(get_tree().root)
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var gid: String = args[0] if args.size() > 0 else "g2"
	var games := int(args[1]) if args.size() > 1 else 4
	GameData.set_group(gid)
	var act := {}
	var top := {}
	var place_sum := {}
	var place_n := {}
	for g in games:
		var players := []
		for i in 8:
			players.append({"id": "p%d" % i, "name": "봇%d" % i, "bot": true})
		var m := Match.new(players, 500 + g)
		m.start()
		var guard := 0
		var last := 0
		while m.state["phase"] != "over" and guard < 200000:
			guard += 1
			m.advance(0.25)
			if m.state["phase"] == "battle" and int(m.state["round"]) != last:
				last = int(m.state["round"])
				for bt in m.state["battles"]:
					if bt.get("monster", false):
						continue
					for side in 2:
						var army: Array = bt["army_a"] if side == 0 else bt["army_b"]
						var tiers := Rules.active_tiers(Rules.count_traits(army))
						for n in tiers:
							if int(tiers[n]) <= 0:
								continue
							var key: String = "%s %d단" % [UI.syn_short(n), int(tiers[n])]
							var w: Dictionary = top.get(key, {"n": 0, "w": 0})
							w["n"] += 1
							w["w"] += 1 if int(bt["winner"]) == side else 0
							top[key] = w
		# 마지막 보드 기준: 시너지별 평균 순위
		for pid in m.state["players"]:
			var p: Dictionary = m.state["players"][pid]
			var specs := []
			for k in p["board"]:
				specs.append(p["board"][k])
			var tiers := Rules.active_tiers(Rules.count_traits(specs))
			for n in tiers:
				if int(tiers[n]) > 0:
					act[n] = int(act.get(n, 0)) + 1
					place_sum[n] = int(place_sum.get(n, 0)) + int(p["place"])
					place_n[n] = int(place_n.get(n, 0)) + 1
		print("판 %d: 라운드 %d, 1위 %s" % [g + 1, m.state["round"], m.state["players"][m.state.get("winner", "p0")]["name"]])
	var names := act.keys()
	names.sort_custom(func(a, b): return float(place_sum[a]) / place_n[a] < float(place_sum[b]) / place_n[b])
	for n in names:
		print("  %-24s 발동 %3d  평균 순위 %.2f" % [UI.syn_short(n), act[n], float(place_sum[n]) / place_n[n]])
	print("— 전투 승률 (시너지·단계별, 10전 이상) —")
	var keys := top.keys().filter(func(k): return int(top[k]["n"]) >= 10)
	keys.sort_custom(func(a, b): return float(top[a]["w"]) / top[a]["n"] > float(top[b]["w"]) / top[b]["n"])
	for k in keys:
		print("  %-28s %3d%% (%d전)" % [k, int(100.0 * top[k]["w"] / top[k]["n"]), top[k]["n"]])
	print("GROUP GAMES DONE")
	get_tree().quit()
