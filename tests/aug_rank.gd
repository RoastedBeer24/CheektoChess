extends Node
## 증강별 평균 순위: 증강을 켠 봇 8명 게임 여러 판 (낮을수록 강함, 4.5가 평균)
##   godot --headless --path . res://tests/aug_rank.tscn -- [판 수] [그룹 id]
func _ready():
	App.start(get_tree().root)
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 20
	if args.size() > 1:
		GameData.set_group(args[1])
	var sum := {}
	var n := {}
	for g in games:
		var players := []
		for i in 8:
			players.append({"id": "p%d" % i, "name": "봇%d" % i, "bot": true})
		var m := Match.new(players, 9000 + g, {"augments": true})
		m.start()
		var guard := 0
		while m.state["phase"] != "over" and guard < 300000:
			guard += 1
			m.advance(0.25)
		for pid in m.state["players"]:
			var p: Dictionary = m.state["players"][pid]
			for a in p.get("augs", []):
				var id: String = a["id"]
				sum[id] = float(sum.get(id, 0.0)) + float(p["place"])
				n[id] = int(n.get(id, 0)) + 1
	var ids := sum.keys()
	ids.sort_custom(func(a, b): return sum[a] / n[a] < sum[b] / n[b])
	for id in ids:
		print("AUG %-14s 평균 %.2f위 (%d번)" % [id, sum[id] / n[id], n[id]])
	print("AUG RANK DONE")
	get_tree().quit()
