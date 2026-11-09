extends Node
## 그룹 바꾸기 검사: 타이틀에서 그룹을 고르고 혼자 하기 → 나가기 → 다른 그룹으로 혼자 하기를 이어서 해도
## 상점·봇 이름이 그 판 그룹을 따르는지.  godot --headless --path . res://tests/group_switch.tscn

var fails := 0


func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var order := []
	for g in GameData.groups:
		order.append(g["id"])
	order.append(order[0])
	for gid in order:
		# 타이틀의 그룹 버튼과 같은 처리
		Settings.set_value("group", gid)
		GameData.set_group(gid)
		App.session.start_offline(3)
		await get_tree().process_frame
		var st: Dictionary = App.session.state
		var ids := {}
		for g in GameData.groups:
			if g["id"] == gid:
				for u in g["units"]:
					ids[u["id"]] = true
		if String(st.get("group", "")) != gid:
			print("GROUP FAIL 판 그룹 %s, 고른 그룹 %s" % [st.get("group", ""), gid])
			fails += 1
		for pid in st["players"]:
			for aid in st["players"][pid].get("shop", []):
				if aid != "" and not ids.has(aid):
					print("GROUP FAIL %s 판 상점에 다른 그룹 사도 %s" % [gid, aid])
					fails += 1
		var bots := []
		for pl in App.session.lobby:
			if pl["bot"]:
				bots.append(pl["name"])
		if bots != ["봇 1", "봇 2", "봇 3"]:
			print("GROUP FAIL 봇 이름 %s" % [bots])
			fails += 1
		print("GROUP %s OK? 상점 검사, 봇 %s" % [gid, bots])
		App.session.leave()
		await get_tree().process_frame
	print("GROUP SWITCH DONE fails=%d" % fails)
	get_tree().quit()
