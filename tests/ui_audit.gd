extends Node
## 화면 검사: 여러 화면 상태에서 (1) 화면 밖으로 나간 버튼·글자 (2) 서로 겹친 버튼 (3) 가로로 잘린 글자
##   CHEEKTO_UI_SCALE=1.35 godot --path . --resolution 2220x1080 res://tests/ui_audit.tscn [-- 캡처 폴더]
## 스크롤 목록 안의 것은 화면 밖 검사에서 뺀다 (스크롤하면 보이므로).

var fails := 0
var shot_dir := ""


func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	shot_dir = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(10)
	await _check(main, "첫화면")
	App.session.start_offline(7)
	await _wait(30)
	var g = App.session.game
	var me: String = App.session.my_pid
	var p = g.player(me)
	p["board"] = {"0,1": {"uid": 8101, "aid": "rohne", "star": 2, "arts": [], "pers": ""}, "2,0": {"uid": 8103, "aid": "amelia_r41", "star": 1, "arts": [], "pers": ""}}
	p["bench"][0] = {"uid": 8102, "aid": "shoupan", "star": 1, "arts": [], "pers": ""}
	p["shop"] = ["amelia_r41", "heidi", "blanchet", "shoupan", "kishya"]
	g.state_changed.emit()
	await get_tree().create_timer(2.0).timeout
	var gs = main.find_children("*", "GameScreen", true, false)[0]
	await _check(gs, "준비")
	# 대기석 가득 + 임시 칸 2개
	var keep_bench: Array = p["bench"].duplicate()
	for k in int(g.B["bench_size"]):
		p["bench"][k] = {"uid": 8200 + k, "aid": GameData.roster[k], "star": 1, "arts": [], "pers": ""}
	g._receive_unit(p, {"uid": 8300, "aid": GameData.roster[9], "star": 1, "arts": [], "pers": ""})
	g._receive_unit(p, {"uid": 8301, "aid": GameData.roster[10], "star": 1, "arts": [], "pers": ""})
	g.state_changed.emit()
	await _wait(10)
	await _check(gs, "대기석넘침")
	p["bench"] = keep_bench
	g.state_changed.emit()
	await _wait(5)
	gs.sel = {"unit": {"board": "0,1"}}
	gs.refresh()
	await _wait(5)
	await _check(gs, "사도정보")
	gs.sel = {}
	# 증강·아티팩트 선택
	p["aug_offer"] = {"options": g._roll_augments(p, 3), "rerolled": false}
	g.state_changed.emit()
	await _wait(10)
	await _check(gs, "증강선택")
	p["aug_offer"] = {}
	p["art_offer"] = {"options": g._roll_artifacts(5, 3), "rerolled": [false, false, false]}
	g.state_changed.emit()
	await _wait(10)
	await _check(gs, "아티팩트선택")
	p["art_offer"] = {}
	g.state_changed.emit()
	await _wait(5)
	# 정찰
	gs._show_player(g.state["players"].keys()[1])
	await _wait(5)
	await _check(gs, "정찰")
	gs._close_modal()
	# 공유 선택 (8명 → 10장)
	g._start_carousel(4)
	var car: Dictionary = g.state.get("carousel", {})
	if not car.is_empty():
		car["order"].erase(me)
		car["order"].insert(0, me)
		car["turn"] = 0
	g.state_changed.emit()
	await _wait(10)
	await _check(gs, "공유선택")
	# 전투
	App.session.game = null
	gs._close_modal()
	g.state["carousel"] = {}
	App.session.game = g
	g.state["phase"] = "prep"
	g.phase_left = 0.1
	var guard := 0
	while g.state["phase"] != "battle" and guard < 400:
		guard += 1
		g.advance(0.1)
		App.session._flush()
		await _wait(1)
	App.session.game = null    # 전투 화면 그대로 두고 진행 멈춤
	await _wait(120)
	await _check(gs, "전투")
	gs._battle_view.skip_to_end()
	await _wait(10)
	await _check(gs, "전투끝")
	gs._battle_view._show_stats()
	await _wait(5)
	await _check(gs, "전투통계")
	App.session.game = g
	# 설정·도감
	var sp := SettingsPanel.new()
	gs.add_child(sp)
	await _wait(5)
	await _check(sp, "설정")
	sp.queue_free()
	var cx := Codex.new()
	gs.add_child(cx)
	await _wait(5)
	await _check(cx, "도감")
	cx.queue_free()
	# 게임 종료
	App.session.game = null
	for pid in g.state["players"]:
		g.state["players"][pid]["place"] = 1 if pid == me else 2
	g.state["phase"] = "over"
	g.state["winner"] = me
	App.session.state = g.state
	gs._overlay_kind = ""
	gs._show_game_over()
	await _wait(10)
	await _check(gs, "게임종료")
	print("UI AUDIT DONE fails=%d" % fails)
	get_tree().quit()


func _check(root: Node, label: String) -> void:
	await RenderingServer.frame_post_draw
	if shot_dir != "":
		DirAccess.make_dir_recursive_absolute(shot_dir)
		get_viewport().get_texture().get_image().save_png(shot_dir.path_join(label + ".png"))
	var vp: Rect2 = get_viewport().get_visible_rect()
	var bad := 0
	var btns := []
	for c in root.find_children("*", "Control", true, false):
		if not c.is_visible_in_tree() or c.modulate.a < 0.05 or _in_scroll(c):
			continue
		if not (c is Button or c is Label or c is LineEdit):
			continue
		if c is Label and c.text == "":
			continue
		var r: Rect2 = c.get_global_rect()
		if r.size.x < 4 or r.size.y < 4:
			continue
		var why := ""
		if not vp.grow(1.0).encloses(r):
			why = "화면 밖"
		elif c is Label and c.autowrap_mode == TextServer.AUTOWRAP_OFF and c.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING and not c.clip_text:
			var font: Font = c.get_theme_font("font")
			var fsz: int = c.get_theme_font_size("font_size")
			var w := 0.0
			for line in c.text.split("\n"):
				w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x)
			if w * c.get_global_transform().get_scale().x > r.size.x + 3.0:
				why = "가로 잘림"
		if why != "":
			bad += 1
			if bad <= 12:
				print("AUDIT [%s] %s '%s' %s @%s %s" % [label, c.get_class(), _txt(c), why, r.position.round(), r.size.round()])
		if c is Button and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			btns.append(c)
	# 겹친 버튼 (서로 조상이 아니고, 작은 쪽 넓이의 30% 이상 겹침)
	for i in btns.size():
		for j in range(i + 1, btns.size()):
			var a: Control = btns[i]
			var b: Control = btns[j]
			if a.is_ancestor_of(b) or b.is_ancestor_of(a):
				continue
			var ra := a.get_global_rect()
			var rb := b.get_global_rect()
			var x := ra.intersection(rb)
			if x.has_area() and x.get_area() > 0.3 * minf(ra.get_area(), rb.get_area()):
				bad += 1
				if bad <= 12:
					print("AUDIT [%s] 겹침 '%s' / '%s' @%s" % [label, _txt(a), _txt(b), x.position.round()])
	if bad > 0:
		print("AUDIT [%s] 문제 %d" % [label, bad])
	fails += bad


func _txt(c: Control) -> String:
	var t: String = c.text if "text" in c else c.name
	return t.replace("\n", " / ").left(24)


func _in_scroll(n: Node) -> bool:
	var q := n.get_parent()
	while q != null:
		if q is ScrollContainer:
			return true
		q = q.get_parent()
	return false


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
