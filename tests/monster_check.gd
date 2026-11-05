extends Node
## 몬스터 라운드 난이도: 봇 8명 게임 여러 판에서 라운드별 몬스터 전투 승률·남은 몬스터 수
##   godot --headless --path . res://tests/monster_check.tscn
func _ready():
	App.start(get_tree().root)
	await get_tree().process_frame
	var stat := {}
	for g in 6:
		var players := []
		for i in 8:
			players.append({"id": "p%d" % i, "name": "봇%d" % i, "bot": true})
		var m := Match.new(players, 1000 + g)
		m.start()
		var last := 0
		while m.state["phase"] != "over" and int(m.state["round"]) <= 17:
			m.advance(0.25)
			if m.state["phase"] == "battle" and int(m.state["round"]) != last:
				last = int(m.state["round"])
				for bt in m.state["battles"]:
					if bt.get("monster", false):
						var s: Dictionary = stat.get(last, {"n": 0, "win": 0, "time": 0.0, "names": {}})
						s["n"] += 1
						s["win"] += 1 if int(bt["winner"]) == 0 else 0
						s["time"] += float(bt["end_time"])
						for u in bt["army_b"]:
							s["names"][GameData.apostle(u["aid"]).get("name", u["aid"])] = 1
						stat[last] = s
	for r in stat:
		var s: Dictionary = stat[r]
		print("라운드 %d: 승률 %d%% (%d전), 평균 %.1f초, 몬스터 %s" % [r, int(100.0 * s["win"] / s["n"]), s["n"], s["time"] / s["n"], ", ".join(s["names"].keys().slice(0, 8))])
	get_tree().quit()
