extends Node
## 헤드리스 테스트: godot --headless --path . res://tests/tests.tscn

func _ready() -> void:
	var fails := 0
	fails += _test_battle()
	fails += _test_match()
	fails += await _test_ui()
	print("TESTS DONE, failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _test_battle() -> int:
	var a := [
		{"aid":"ed","star":2,"row":0,"slot":1,"arts":["soft_vest","emergency_belt"],"pers":""},
		{"aid":"aya","star":1,"row":1,"slot":0,"arts":["belita_staff"],"pers":""},
		{"aid":"sylla","star":1,"row":2,"slot":2,"arts":["sylla_arrow","toy_telescope","rim_scythe"],"pers":""},
		{"aid":"hilde","star":1,"row":1,"slot":2,"arts":["hilde_uniform"],"pers":""},
	]
	var b := [
		{"aid":"rudd","star":2,"row":0,"slot":0,"arts":["levi_dagger","dokkaebi_hat"],"pers":""},
		{"aid":"joanne","star":1,"row":0,"slot":2,"arts":["madness_mask"],"pers":"우울"},
		{"aid":"uros","star":3,"row":2,"slot":1,"arts":["fire_bow","greed_ring"],"pers":"광기"},
		{"aid":"belita","star":1,"row":2,"slot":0,"arts":["kettlebell","dragonlight_sword"],"pers":""},
	]
	var r1 = BattleSim.new(a, b, 12345).run()
	var r2 = BattleSim.new(a, b, 12345).run()
	print("winner=%s survivors=%s time=%.1f events=%d" % [r1["winner"], r1["survivors"], r1["end_time"], r1["events"].size()])
	var kinds := {}
	for e in r1["events"]:
		kinds[e[1]] = kinds.get(e[1], 0) + 1
	print(kinds)
	if JSON.stringify(r1["events"]) != JSON.stringify(r2["events"]):
		print("FAIL: 전투 결과가 결정론적이지 않음")
		return 1
	return 0


## 봇 8명으로 한 판을 끝까지 돌려본다
func _test_match() -> int:
	var players := []
	for i in 8:
		players.append({"id": "p%d" % i, "name": "봇%d" % i, "bot": true})
	var m := Match.new(players, 777)
	m.start()
	var guard := 0
	while m.state["phase"] != "over" and guard < 200000:
		guard += 1
		m.advance(0.25)
		if guard % 2000 == 0: print("round ", m.state["round"], " phase ", m.state["phase"], " alive ", m.alive_players().size(), " t=", Time.get_ticks_msec())
	var places := []
	for pid in m.state["players"]:
		var p = m.state["players"][pid]
		places.append("%s:%d위(Lv%d)" % [p["name"], p["place"], p["level"]])
	print("match: rounds=%d winner=%s %s" % [m.state["round"], m.state["winner"], " ".join(places)])
	# 합성/아티팩트 테스트
	var t := Match.new([{"id":"a","name":"A"},{"id":"b","name":"B"},{"id":"c","name":"C"},{"id":"d","name":"D"}], 1)
	t.start()
	var pa = t.player("a")
	pa["gold"] = 100
	pa["shop"] = ["ed","ed","ed","joanne","rudd"]
	for i in 3:
		var e = t.command("a", {"t":"buy","i":i})
		if e != "":
			print("FAIL buy: ", e); return 1
	var two := 0
	for u in pa["bench"]:
		if u != null and u["aid"] == "ed" and u["star"] == 2:
			two += 1
	if two != 1:
		print("FAIL: 3명 합성 실패"); return 1
	t.command("a", {"t":"buy","i":3})
	var err = t.command("a", {"t":"move","from":{"bench":1},"to":{"board":"2,1"},"pers":"우울"})
	print("move joanne: '%s' board=%s" % [err, pa["board"]])
	if not pa["board"].has("2,1") or pa["board"]["2,1"]["pers"] != "우울":
		print("FAIL: 이면 성격 선택"); return 1
	var err2 = t.command("a", {"t":"move","from":{"bench":0},"to":{"board":"2,0"}})
	if err2 == "":
		print("FAIL: 이드(전열)를 후열에 배치함"); return 1
	print("열 제한 OK: ", err2)
	pa["inv"] = [{"uid":9001,"id":"wooden_sword"},{"uid":9002,"id":"rusty_awl"}]
	var err3 = t.command("a", {"t":"art_merge","a":9001,"b":9002})
	if err3 != "" or pa["inv"].size() != 1 or GameData.artifact(pa["inv"][0]["id"])["grade"] != "advanced":
		print("FAIL art_merge: ", err3, pa["inv"]); return 1
	print("아티팩트 합성 OK → ", GameData.artifact(pa["inv"][0]["id"])["name"])
	# 연결 끊김: 같은 라운드면 재접속 가능, 다음 라운드가 시작되면 탈락
	t.set_connected("b", false)
	if not t.can_rejoin("b"):
		print("FAIL: 같은 라운드 재접속 불가"); return 1
	var r0: int = t.state["round"]
	var g := 0
	while int(t.state["round"]) == r0 and g < 10000:
		g += 1
		t.advance(0.25)
	if t.player("b")["alive"] or t.can_rejoin("b"):
		print("FAIL: 라운드가 넘어갔는데 탈락하지 않음"); return 1
	print("끊김 탈락 OK: ", t.state["log"][-2] if t.state["log"].size() > 1 else "")
	return 0 if m.state["phase"] == "over" else 1


## 실제 화면을 띄우고 오프라인 게임을 빠르게 진행시켜 본다 (스크립트 오류 확인용)
func _test_ui() -> int:
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	Session.start_offline(7)
	Engine.time_scale = 30.0
	var frames := 0
	var seen_battle := false
	var me := ""
	while frames < 3000 and Session.state.get("phase", "") != "over":
		await get_tree().process_frame
		frames += 1
		if Session.state.get("phase", "") == "battle":
			seen_battle = true
		# 사람 플레이어 대신 간단히 행동: 첫 칸 구매 후 보드에 올리기
		if Session.state.get("phase", "") == "prep" and frames % 30 == 0:
			var p = Session.state["players"][Session.my_pid]
			if not p["art_offer"].is_empty():
				Session.submit({"t": "art_reroll", "i": 1})
				Session.submit({"t": "art_pick", "i": 0})
			Session.submit({"t": "buy", "i": 0})
			for i in p["bench"].size():
				if p["bench"][i] != null:
					var aid = p["bench"][i]["aid"]
					for r in 3:
						if GameData.can_place(aid, r):
							Session.submit({"t": "move", "from": {"bench": i}, "to": {"board": Match.key_of(r, i % 3)}, "pers": ""})
							break
			if not p["inv"].is_empty() and not p["board"].is_empty():
				Session.submit({"t": "equip", "art": p["inv"][0]["uid"], "loc": {"board": p["board"].keys()[0]}})
	Engine.time_scale = 1.0
	var st = Session.state
	var p = st["players"][Session.my_pid]
	print("ui: frames=%d round=%d phase=%s my_hp=%d board=%d inv=%d battle_seen=%s" % [frames, st["round"], st["phase"], p["hp"], p["board"].size(), p["inv"].size(), seen_battle])
	Session.leave()
	await get_tree().process_frame
	main.queue_free()
	return 0 if seen_battle else 1
