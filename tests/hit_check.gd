extends Node
## 누를 수 있는지 검사: 게임 화면의 모든 칸·버튼 가운데를 가리켰을 때 그 칸(또는 그 안의 것)이 잡히는지.
## 보이지 않는 막(투명 배너·패널 등)이 가로채면 FAIL.
##   CHEEKTO_UI_SCALE=1.3 godot --path . --resolution 2340x1080 res://tests/hit_check.tscn

var fails := 0


func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(10)
	await _check_tree(main, "첫 화면")
	App.session.start_offline(7)
	await _wait(30)
	var gs = main.find_children("*", "GameScreen", true, false)[0]
	var g = App.session.game
	var p = g.player(App.session.my_pid)
	p["inv"] = [{"uid": 8001, "id": "wooden_sword"}]
	p["board"] = {"0,1": {"uid": 8101, "aid": "rohne", "star": 1, "arts": [], "pers": ""}}
	p["bench"][0] = {"uid": 8102, "aid": "bana", "star": 1, "arts": [], "pers": ""}
	g.state_changed.emit()
	# 라운드 배너가 떠 있는 동안과 사라진 뒤 모두
	await _wait(5)
	await _check_tree(gs, "준비 (배너 표시 중)")
	await get_tree().create_timer(3.0).timeout
	await _check_tree(gs, "준비")
	gs.sel = {"art": 8001}
	gs.refresh()
	await _wait(5)
	await _check_tree(gs, "아티팩트 선택 중")
	await RenderingServer.frame_post_draw
	var out := OS.get_environment("HIT_SHOT")
	if out != "":
		get_viewport().get_texture().get_image().save_png(out)
	print("HIT CHECK DONE fails=%d" % fails)
	get_tree().quit()


func _check_tree(root: Node, label: String) -> void:
	var targets := []
	_collect(root, targets)
	var xf: Transform2D = get_viewport().get_final_transform()
	var bad := 0
	for c in targets:
		var pos: Vector2 = xf * c.get_global_rect().get_center()
		var m := InputEventMouseMotion.new()
		m.position = pos
		m.global_position = pos
		Input.parse_input_event(m)
		await get_tree().process_frame
		var hov: Control = get_viewport().gui_get_hovered_control()
		if hov == null or not (hov == c or c.is_ancestor_of(hov)):
			bad += 1
			if bad <= 12:
				print("FAIL [%s] %s(%s) 가 %s 에 가려짐" % [label, c.get_class(), _name(c), (hov.get_path() if hov else "없음")])
	print("[%s] 검사 %d개, 가려짐 %d개" % [label, targets.size(), bad])
	fails += bad


func _name(c: Control) -> String:
	if c is Button and c.text != "":
		return c.text.replace("\n", " ")
	return c.name


## 눌러야 하는 것: 보이는 버튼(칸 포함)
func _collect(n: Node, out: Array) -> void:
	for ch in n.get_children():
		if ch is BaseButton and ch.is_visible_in_tree() and not ch.disabled and ch.get_global_rect().size.x > 4:
			if get_viewport().get_visible_rect().has_point(ch.get_global_rect().get_center()):
				out.append(ch)
		_collect(ch, out)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
