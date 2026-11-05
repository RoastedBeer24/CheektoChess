extends Node
## 글자 잘림 검사: 보이는 라벨 중 글자가 칸보다 넓어 잘리는 것, 화면 밖으로 나간 것
##   CHEEKTO_UI_SCALE=1.3 godot --path . --resolution 2340x1080 res://tests/text_check.tscn

func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(10)
	_check(main, "첫 화면")
	App.session.start_offline(7)
	await _wait(30)
	var g = App.session.game
	var p = g.player(App.session.my_pid)
	p["board"] = {"0,1": {"uid": 8101, "aid": "rohne", "star": 2, "arts": [], "pers": ""}, "2,0": {"uid": 8103, "aid": "amelia_r41", "star": 1, "arts": [], "pers": ""}}
	p["bench"][0] = {"uid": 8102, "aid": "shoupan", "star": 1, "arts": [], "pers": ""}
	p["shop"] = ["amelia_r41", "heidi", "blanchet", "shoupan", "kishya"]
	g.state_changed.emit()
	await get_tree().create_timer(2.5).timeout
	var gs = main.find_children("*", "GameScreen", true, false)[0]
	_check(gs, "준비")
	gs.sel = {"unit": {"board": "0,1"}}
	gs.refresh()
	await _wait(5)
	_check(gs, "사도 정보")
	print("TEXT CHECK DONE")
	get_tree().quit()


func _check(root: Node, label: String) -> void:
	var bad := 0
	var vp: Rect2 = get_viewport().get_visible_rect()
	for l in root.find_children("*", "Label", true, false):
		if not l.is_visible_in_tree() or l.text == "" or _in_scroll(l):
			continue
		var r: Rect2 = l.get_global_rect()
		var font: Font = l.get_theme_font("font")
		var fsz: int = l.get_theme_font_size("font_size")
		var why := ""
		if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
			var w := 0.0
			for line in l.text.split("\\n"):
				w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x)
			if w > r.size.x * l.get_global_transform().get_scale().x + 3.0 and l.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
				why = "가로 잘림(%d>%d)" % [w, r.size.x]
		if why == "" and not vp.encloses(r.grow(-2)):
			why = "화면 밖"
		if why != "":
			bad += 1
			if bad <= 25:
				print("TEXT [%s] '%s' %s @%s" % [label, l.text.replace("\\n", " / ").left(30), why, r.position.round()])
	print("[%s] 잘림 %d" % [label, bad])


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
