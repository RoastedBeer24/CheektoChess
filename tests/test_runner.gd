extends Node
## 헤드리스 테스트: godot --headless --path . res://tests/tests.tscn

func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var fails := 0
	fails += _test_battle()
	fails += _test_match()
	fails += _test_group_synergies()
	fails += _test_special_rounds()
	fails += _test_rules_augments()
	fails += _test_assets()
	fails += await _test_ui()
	print("TESTS DONE, failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _test_battle() -> int:
	var a := [
		{"aid":"mayo","star":2,"row":0,"slot":1,"arts":["soft_vest","emergency_belt"],"pers":""},
		{"aid":"aya","star":1,"row":1,"slot":0,"arts":["belita_staff"],"pers":""},
		{"aid":"sylla","star":1,"row":2,"slot":2,"arts":["sylla_arrow","toy_telescope","rim_scythe"],"pers":""},
		{"aid":"hilde","star":1,"row":1,"slot":2,"arts":["hilde_uniform"],"pers":""},
	]
	var b := [
		{"aid":"rohne","star":2,"row":0,"slot":0,"arts":["levi_dagger","dokkaebi_hat"],"pers":""},
		{"aid":"joanne","star":1,"row":0,"slot":2,"arts":["madness_mask"],"pers":"우울"},
		{"aid":"vela","star":3,"row":2,"slot":1,"arts":["fire_bow","greed_ring"],"pers":"광기"},
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
## 그룹 시너지: 6명 단계 효과가 실제로 동작하는지 (이벤트로 확인)
func _army(ids: Array, arts: Dictionary = {}) -> Array:
	var out := []
	var slots := {}
	for aid in ids:
		var a := GameData.apostle(aid)
		var row: int = {"front": 0, "mid": 1, "back": 2}.get(a.get("row", "mid"), 1)
		var sl: int = slots.get(row, 0)
		if sl >= 3:
			row = (row + 1) % 3
			sl = slots.get(row, 0)
		slots[row] = sl + 1
		out.append({"aid": aid, "star": 1, "row": row, "slot": sl, "arts": arts.get(aid, []), "pers": "순수" if aid == "joanne" else ""})
	return out


func _count_ev(res: Dictionary, kind: String, extra: String = "") -> int:
	var n := 0
	for e in res["events"]:
		if e[1] == kind and (extra == "" or String(e[5]) == extra):
			n += 1
	return n


func _test_group_synergies() -> int:
	var fails := 0
	var enemy := _army(["mayo", "bana", "rohne", "festa", "bigwood", "speaki", "opal", "levi", "marie"])
	# 유령 늪 6: 부활
	var swamp := _army(["speaki", "kishya", "barong", "selene", "alice", "shaydi"])
	var counts := Rules.active_tiers(Rules.count_traits(swamp))
	if counts.get("유령 늪", 0) != 3:
		print("FAIL: 유령 늪 6단계가 아님 %s" % counts); fails += 1
	var found_revive := false
	for seed in range(1, 8):
		var r := BattleSim.new(swamp, enemy, seed).run()
		if _count_ev(r, "revive") > 0:
			found_revive = true
			break
	print("유령 늪 부활 이벤트: %s" % found_revive)
	if not found_revive:
		print("FAIL: 유령 늪 부활 없음"); fails += 1
	# 세계수 교단 6: 가호 (버티기)
	var tree := _army(["picora", "kyarot", "ner", "skea", "polan", "joanne"])
	var guard := false
	var strong := []
	for x in enemy:
		var y: Dictionary = x.duplicate()
		y["star"] = 2
		strong.append(y)
	for seed in range(1, 31):
		var r := BattleSim.new(tree, strong, seed).run()
		if _count_ev(r, "buff", "세계수의 가호") > 0:
			guard = true
			break
	print("세계수의 가호 발동: %s" % guard)
	if not guard:
		print("FAIL: 세계수의 가호 없음"); fails += 1
	# 결정론: 같은 seed 같은 결과
	var r1 := BattleSim.new(tree, swamp, 42).run()
	var r2 := BattleSim.new(tree, swamp, 42).run()
	if r1["events"].size() != r2["events"].size() or r1["winner"] != r2["winner"]:
		print("FAIL: 그룹 시너지 전투가 결정론적이지 않음"); fails += 1
	# 폐쇄적인 수집가: 아티팩트 수에 비례한 HP
	var col := _army(["opal", "sist"], {"opal": ["life_gem", "life_gem"]})
	var sim := BattleSim.new(col, enemy, 1)
	var opal_hp: float = sim.max_hp(sim.units[0])
	var plain := BattleSim.new(_army(["opal"], {"opal": ["life_gem", "life_gem"]}), enemy, 1)
	print("수집가 HP %.0f vs 시너지 없음 %.0f" % [opal_hp, plain.max_hp(plain.units[0])])
	if opal_hp <= plain.max_hp(plain.units[0]):
		print("FAIL: 수집가 아티팩트 비례 효과 없음"); fails += 1
	return fails


## 몬스터 라운드(연승·연패·체력 변화 없음, 보상)와 공유 선택 라운드
func _test_special_rounds() -> int:
	var fails := 0
	var players := []
	for i in 4:
		players.append({"id": "b%d" % i, "name": "봇%d" % i, "bot": true})
	var m := Match.new(players, 77)
	m.start()
	var saw_carousel := false
	var monster_ok := true
	var rewards := 0
	var guard := 0
	while int(m.state["round"]) < 7 and m.state["phase"] != "over" and guard < 200000:
		guard += 1
		var before := {}
		if m.state["phase"] == "battle" and m.state.get("round_kind", "") == "monster":
			for pid in m.state["players"]:
				before[pid] = [int(m.player(pid)["hp"]), int(m.player(pid)["streak"])]
		m.advance(0.25)
		if m.state["phase"] == "carousel":
			saw_carousel = true
		if not before.is_empty() and m.state["phase"] != "battle":
			for pid in before:
				if before[pid][0] != int(m.player(pid)["hp"]) or before[pid][1] != int(m.player(pid)["streak"]):
					monster_ok = false
			for bt in m.state["battles"]:
				if bt.has("reward"):
					rewards += 1
	print("특수 라운드: 공유 선택=%s, 몬스터 라운드 체력·연승 그대로=%s, 보상 %d건, 라운드 %d" % [saw_carousel, monster_ok, rewards, int(m.state["round"])])
	if not saw_carousel:
		print("FAIL: 공유 선택 라운드 없음"); fails += 1
	if not monster_ok:
		print("FAIL: 몬스터 라운드가 체력·연승을 바꿈"); fails += 1
	if rewards == 0:
		print("FAIL: 몬스터 보상 없음"); fails += 1
	return fails


## 모션·보이스 파일을 실제로 읽을 수 있는지
## 방 규칙(빠른 모드·증강) + 봇 성향으로 한 판 끝까지
func _test_rules_augments() -> int:
	var players := []
	for i in 8:
		players.append({"id": "p%d" % i, "name": "봇%d" % i, "bot": true, "style": Bot.STYLES[i % 4]})
	var m := Match.new(players, 4242, {"fast": true, "augments": true})
	if int(m.B["player_hp"]) != 60 or int(m.state["bal"]["player_hp"]) != 60:
		print("FAIL: 빠른 모드 체력"); return 1
	m.start()
	var g := 0
	var picked := {}
	while m.state["phase"] != "over" and g < 200000:
		g += 1
		m.advance(0.25)
		for pid in m.state["players"]:
			for a in m.player(pid)["augs"]:
				picked[a["id"]] = true
	var rounds: int = m.state["round"]
	var n_augs := 0
	for pid in m.state["players"]:
		n_augs = maxi(n_augs, m.player(pid)["augs"].size())
	print("규칙·증강 판: 라운드 %d에 끝, 증강 최대 %d개, 나온 증강 %d종: %s" % [rounds, n_augs, picked.size(), picked.keys()])
	# MVP: 1위의 사도별 기록이 쌓였는지
	var champ: Dictionary = m.player(m.state["winner"]) if m.state["winner"] != "" else {}
	var tops := Match.mvp_top(champ, 3)
	print("1위 MVP: %s" % [tops.map(func(t): return "%s %d점" % [t[0], int(Match.mvp_score(t[1]))])])
	if tops.size() < 3:
		print("FAIL: MVP 3인 집계"); return 1
	# ★3 이 나온 사도는 그 게임에서 더는 안 나옴
	var m3 := Match.new([{"id": "a", "name": "a", "bot": false}, {"id": "b", "name": "b", "bot": true}], 11)
	m3.start()
	var p3 := m3.player("a")
	for k in 9:
		p3["bench"][k % 8] = null
	p3["board"] = {}
	p3["bench"][0] = {"uid": 1, "aid": "rohne", "star": 2, "arts": [], "pers": ""}
	p3["bench"][1] = {"uid": 2, "aid": "rohne", "star": 2, "arts": [], "pers": ""}
	m3._try_merge(p3, "rohne", 2, {"uid": 3, "aid": "rohne", "star": 2, "arts": [], "pers": ""})
	if not m3.is_banned("rohne"):
		print("FAIL: ★3 금지 표시"); return 1
	var seen_rohne := false
	for k in 400:
		if m3._roll_unit([100, 0, 0, 0, 0]) == "rohne":
			seen_rohne = true
	if seen_rohne:
		print("FAIL: ★3 사도가 상점에 나옴"); return 1
	print("★3 금지 OK")
	if m.state["phase"] != "over" or n_augs < 2:
		print("FAIL: 증강 판"); return 1
	# 증강 효과 단위 확인
	var m2 := Match.new([{"id": "a", "name": "a", "bot": false}, {"id": "b", "name": "b", "bot": true}], 7, {"augments": true})
	m2.start()
	var pa := m2.player("a")
	pa["augs"] = [{"id": "board_plus"}, {"id": "free_row"}, {"id": "interest_cap"}]
	if Match.board_cap(pa) != int(pa["level"]) + 1 or not Match.can_place_p(pa, "rohne", 2):
		print("FAIL: 확장 보드·자유 배치"); return 1
	pa["gold"] = 80
	if m2.income(pa) < int(m2.B["base_income"]) + 8:
		print("FAIL: 복리 이자"); return 1
	pa["augs"].append({"id": "b_shield"})
	pa["board"] = {"0,1": {"uid": 1, "aid": "rohne", "star": 1, "arts": [], "pers": ""}}
	var army := m2.army_of("a")
	if army.is_empty() or army[0].get("augs", []).is_empty():
		print("FAIL: 전투 증강 전달"); return 1
	var sim := BattleSim.new(army, [{"aid": "bana", "star": 1, "row": 0, "slot": 1, "arts": [], "pers": ""}], 3)
	if float(sim.units[0].get("start_shield", 0.0)) < 18.0:
		print("FAIL: 보호막 전개 적용 안 됨"); return 1
	# 2차 증강: 사도 변형·모험·퀘스트
	var hp0 := int(pa["hp"])
	m2._apply_aug_now(pa, {"id": "r_glass"})
	if int(pa["hp"]) != hp0 - 15:
		print("FAIL: 유리 대포 체력"); return 1
	m2._apply_aug_now(pa, {"id": "u_upgrade"})
	if int(pa["board"]["0,1"]["star"]) != 2:
		print("FAIL: 승급 시험"); return 1
	pa["gold"] = 20
	m2._apply_aug_now(pa, {"id": "r_allin"})
	pa["augs"].append({"id": "r_allin"})
	m2._aug_after_battle(pa, {"winner": 0, "deaths": [0, 3]}, 0)
	if int(pa["gold"]) != 40:
		print("FAIL: 올인 정산 %d" % pa["gold"]); return 1
	pa["augs"].append({"id": "u_twin"})
	m2._apply_aug_now(pa, {"id": "u_twin"})
	var twins := 0
	for u in pa["bench"]:
		if u != null and u["aid"] == "rohne":
			twins += 1
	if twins != 1:
		print("FAIL: 쌍둥이"); return 1
	pa["augs"].append({"id": "r_hunger"})
	pa["gold"] = 50
	if Match.board_cap(pa) != int(pa["level"]) + 2 or m2.income(pa) > int(m2.B["base_income"]) + 4:
		print("FAIL: 욕심쟁이 군단"); return 1
	# 대기석이 가득 찼을 때 받은 사도: 임시 칸 → 빈칸이 생기면 대기석으로
	var pb := m2.player("b")
	var ids_ok: Array = GameData.roster.slice(0, 12)
	for k in int(m2.B["bench_size"]):
		pb["bench"][k] = {"uid": 9000 + k, "aid": ids_ok[k], "star": 1, "arts": [], "pers": ""}
	m2._receive_unit(pb, {"uid": 9100, "aid": ids_ok[9], "star": 1, "arts": [], "pers": ""})
	m2._receive_unit(pb, {"uid": 9101, "aid": ids_ok[10], "star": 1, "arts": [], "pers": ""})
	if pb["bench"].size() != int(m2.B["bench_size"]) + 2:
		print("FAIL: 임시 칸 %d" % pb["bench"].size()); return 1
	var g_before := int(pb["gold"])
	m2._receive_unit(pb, {"uid": 9102, "aid": ids_ok[11], "star": 1, "arts": [], "pers": ""})
	if int(pb["gold"]) <= g_before:
		print("FAIL: 임시 칸도 가득 → 골드"); return 1
	pb["bench"][0] = null
	m2._compact_bench(pb)
	if pb["bench"].size() != int(m2.B["bench_size"]) + 1 or pb["bench"][0] == null:
		print("FAIL: 임시 칸 정리"); return 1
	# 방 코드
	for ip in ["192.168.0.10", "192.168.255.254", "172.20.3.4", "10.1.2.3"]:
		if NetNode.code_to_ip(NetNode.pretty_code(NetNode.room_code(ip))) != ip:
			print("FAIL: 방 코드 %s" % ip); return 1
	print("증강 단위 확인 OK")
	return 0


func _test_assets() -> int:
	var fails := 0
	var m := MotionSprite.meta_of("aya")
	var tex = MotionSprite._sheet("aya", "Idle") if not m.is_empty() else null
	var vm := Voice.meta_of("aya")
	var snd = Voice._stream("res://assets/voices/aya/SPSkill_1.ogg") if not vm.is_empty() else null
	print("자원: 모션 %s (%s), 보이스 %s (%.1f초)" % [not m.is_empty(), tex != null, not vm.is_empty(), snd.get_length() if snd != null else 0.0])
	if m.is_empty() or tex == null:
		print("FAIL: 모션을 읽지 못함"); fails += 1
	if not vm.is_empty() and (snd == null or snd.get_length() <= 0.0):
		print("FAIL: 보이스를 읽지 못함"); fails += 1
	return fails


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
	pa["shop"] = ["mayo","mayo","mayo","joanne","rohne"]
	for i in 3:
		var e = t.command("a", {"t":"buy","i":i})
		if e != "":
			print("FAIL buy: ", e); return 1
	var two := 0
	for u in pa["bench"]:
		if u != null and u["aid"] == "mayo" and u["star"] == 2:
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
	# 연결 끊김: 탈락하지 않고 봇이 대신 플레이, 라운드가 지나도 재접속 가능
	t.set_connected("b", false)
	if not t.can_rejoin("b"):
		print("FAIL: 재접속 불가"); return 1
	var r0: int = t.state["round"]
	var g := 0
	while int(t.state["round"]) <= r0 + 1 and g < 20000:
		g += 1
		t.advance(0.25)
	if not t.player("b")["alive"] or not t.can_rejoin("b"):
		print("FAIL: 끊긴 사람이 탈락했거나 재접속 불가"); return 1
	# 방장 넘기기: state 로 Match 를 다시 만들어도 같은 난수 흐름
	t.pack_host_meta()
	var t2 := Match.from_state(t.state)
	if t2.rng.randi() != t.rng.randi() or t2.state["round"] != t.state["round"]:
		print("FAIL: 방장 넘기기 상태 복원"); return 1
	print("끊김 → 봇 대신 플레이 OK, 방장 넘기기 복원 OK")
	return 0 if m.state["phase"] == "over" else 1


## 실제 화면을 띄우고 오프라인 게임을 빠르게 진행시켜 본다 (스크립트 오류 확인용)
func _test_ui() -> int:
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	App.session.start_offline(7)
	Engine.time_scale = 30.0
	var frames := 0
	var seen_battle := false
	var me := ""
	while frames < 3000 and App.session.state.get("phase", "") != "over":
		await get_tree().process_frame
		frames += 1
		if App.session.state.get("phase", "") == "battle":
			seen_battle = true
		# 사람 플레이어 대신 간단히 행동: 첫 칸 구매 후 보드에 올리기
		if App.session.state.get("phase", "") == "prep" and frames % 30 == 0:
			var p = App.session.state["players"][App.session.my_pid]
			if not p["art_offer"].is_empty():
				App.session.submit({"t": "art_reroll", "i": 1})
				App.session.submit({"t": "art_pick", "i": 0})
			App.session.submit({"t": "buy", "i": 0})
			for i in p["bench"].size():
				if p["bench"][i] != null:
					var aid = p["bench"][i]["aid"]
					for r in 3:
						if GameData.can_place(aid, r):
							App.session.submit({"t": "move", "from": {"bench": i}, "to": {"board": Match.key_of(r, i % 3)}, "pers": ""})
							break
			if not p["inv"].is_empty() and not p["board"].is_empty():
				App.session.submit({"t": "equip", "art": p["inv"][0]["uid"], "loc": {"board": p["board"].keys()[0]}})
	Engine.time_scale = 1.0
	var st = App.session.state
	var p = st["players"][App.session.my_pid]
	print("ui: frames=%d round=%d phase=%s my_hp=%d board=%d inv=%d battle_seen=%s" % [frames, st["round"], st["phase"], p["hp"], p["board"].size(), p["inv"].size(), seen_battle])
	App.session.leave()
	await get_tree().process_frame
	main.queue_free()
	return 0 if seen_battle else 1
