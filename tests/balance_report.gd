extends Node
## 밸런스 리포트: docs/BALANCE.md 를 만든다.
##   godot --headless --path . res://tests/balance_report.tscn -- [게임 수=30]
## 1) 같은 코스트끼리 1:1 (★2, 아티팩트 없음) 승률 — 사도 스킬 이상치 찾기
## 2) 봇 8명 게임을 여러 판: 사도·시너지·코스트별 '마지막 보드에 있던 판'의 평균 순위·1위 비율

func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var n_games := int(args[0]) if args.size() > 0 else 30
	var lines := ["# 밸런스 리포트", "", "`godot --headless --path . res://tests/balance_report.tscn -- %d` 로 생성 (그룹: %s)" % [n_games, GameData.group_name(GameData.group_id)], ""]
	lines.append_array(_duels())
	await get_tree().process_frame
	lines.append_array(_games(n_games))
	var f := FileAccess.open("res://docs/BALANCE.md", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	print("BALANCE DONE")
	get_tree().quit()


func _unit(aid: String, row_override: int = -1) -> Dictionary:
	var row: int = {"front": 0, "mid": 1, "back": 2}.get(GameData.apostle(aid).get("row", "mid"), 1)
	return {"aid": aid, "star": 2, "row": row if row_override < 0 else row_override, "slot": 1, "arts": [], "pers": "순수" if aid == "joanne" else ""}


func _duels() -> Array:
	var out := ["## 1. 같은 코스트 1:1 승률 (★2, 아티팩트·시너지 영향 최소)", "", "| 코스트 | 사도 | 승률 | 역할 |", "|---|---|---|---|"]
	for c in range(1, 6):
		var ids := []
		for aid in GameData.roster:
			if GameData.cost_of[aid] == c:
				ids.append(aid)
		var rate := {}
		for a in ids:
			var w := 0
			var g := 0
			for b in ids:
				if a == b:
					continue
				for seed in [3, 11]:
					var r := BattleSim.new([_unit(a)], [_unit(b)], seed).run()
					g += 1
					if r["winner"] == 0:
						w += 1
					elif r["winner"] == -1:
						w += 0
			rate[a] = 100.0 * w / maxf(1.0, g)
		ids.sort_custom(func(x, y): return rate[x] > rate[y])
		for a in ids:
			var flag := ""
			if rate[a] >= 80.0:
				flag = " ⚠ 강함"
			elif rate[a] <= 20.0:
				flag = " ⚠ 약함"
			out.append("| %d | %s | %.0f%%%s | %s |" % [c, GameData.apostle(a)["name"], rate[a], flag, GameData.ROLE_NAME.get(GameData.apostle(a).get("role", ""), "")])
	out.append("")
	out.append("※ 1:1 은 탱커·서포터에게 불리하다 (혼자서는 때릴 상대만 남음). 같은 역할끼리 비교해서 볼 것.")
	out.append("")
	return out


func _games(n: int) -> Array:
	var ap := {}    # aid -> [순위 합, 판 수, 1위 수]
	var sy := {}
	var co := {}
	var rounds := 0
	for gi in n:
		var players := []
		for i in 8:
			players.append({"id": "b%d" % i, "name": "봇%d" % i, "bot": true})
		var m := Match.new(players, 1000 + gi)
		m.start()
		var guard := 0
		while m.state["phase"] != "over" and guard < 400000:
			guard += 1
			m.advance(0.5)
		rounds += int(m.state["round"])
		for pid in m.state["players"]:
			var p: Dictionary = m.player(pid)
			var place := int(p["place"]) if int(p["place"]) > 0 else 1
			# 탈락한 봇의 마지막 보드는 비어 있으므로 기록해 둔 보드를 쓴다
			var board: Dictionary = p.get("last_board", p["board"])
			var specs := []
			for k in board:
				specs.append(board[k])
				_acc(ap, board[k]["aid"], place)
				_acc(co, str(GameData.cost_of.get(board[k]["aid"], 1)), place)
			var tiers := Rules.active_tiers(Rules.count_traits(specs))
			for s in tiers:
				if int(tiers[s]) > 0:
					_acc(sy, s, place)
	var out := ["## 2. 봇 8명 게임 %d판 (평균 %.1f라운드)" % [n, float(rounds) / maxf(1, n)], "", "평균 순위가 낮을수록(1에 가까울수록) 강함. 4.5 가 평균.", ""]
	out.append_array(_table("시너지 (마지막 보드에서 켜져 있던 판)", sy, 3))
	out.append_array(_table("코스트", co, 1))
	out.append_array(_table("사도 (마지막 보드에 있던 판)", ap, 5, true))
	return out


func _acc(d: Dictionary, k: String, place: int) -> void:
	var v: Array = d.get(k, [0, 0, 0])
	v[0] += place
	v[1] += 1
	if place == 1:
		v[2] += 1
	d[k] = v


func _table(title: String, d: Dictionary, min_n: int, names: bool = false) -> Array:
	var keys := []
	for k in d:
		if int(d[k][1]) >= min_n:
			keys.append(k)
	keys.sort_custom(func(a, b): return float(d[a][0]) / d[a][1] < float(d[b][0]) / d[b][1])
	var out := ["### " + title, "", "| 이름 | 평균 순위 | 판 수 | 1위 |", "|---|---|---|---|"]
	for k in keys:
		var nm: String = GameData.apostle(k).get("name", k) if names else String(k)
		out.append("| %s | %.2f | %d | %d |" % [nm, float(d[k][0]) / d[k][1], int(d[k][1]), int(d[k][2])])
	out.append("")
	return out
