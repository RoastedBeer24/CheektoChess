extends Node
## 끌기 조합 시험 (터치 입력, 바로 끌기 / 누르고 있다가 끌기 둘 다)
##   CHEEKTO_UI_SCALE=1.3 godot --path . --resolution 2340x1080 res://tests/drag_suite.tscn
## 상점→보드, 대기석→보드, 보드→대기석, 보드 안 교체, 보드→판매, 아티팩트→사도 장착, 아티팩트→아티팩트 합성

var main
var gs
var g
var fails := 0


func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(10)
	App.session.start_offline(3)
	await _wait(20)
	g = App.session.game
	gs = main.find_children("*", "GameScreen", true, false)[0]
	App.session.toast.connect(func(m): print("  알림: ", m))
	gs.toast_requested.connect(func(m): print("  알림: ", m))
	for hold in [false, true]:
		await _case("상점→보드", hold, func(p):
			p["gold"] = 30
			p["shop"] = ["rohne", "bana", "festa", "mayo", "levi"]
			p["board"] = {}
			, func(): return _shop(0), func(): return _board("0,1"),
			func(p): return p["board"].has("0,1") and p["board"]["0,1"]["aid"] == "rohne")
		await _case("대기석→보드", hold, func(p):
			p["board"] = {}
			_clear_bench(p)
			p["bench"][0] = _u(901, "rohne")
			, func(): return _bench(0), func(): return _board("0,0"),
			func(p): return p["board"].has("0,0") and p["bench"][0] == null)
		await _case("보드→대기석", hold, func(p):
			_clear_bench(p)
			p["board"] = {"0,1": _u(902, "rohne")}
			, func(): return _board("0,1"), func(): return _bench(3),
			func(p): return p["board"].is_empty() and p["bench"][3] != null)
		await _case("보드 안 교체", hold, func(p):
			_clear_bench(p)
			p["board"] = {"0,0": _u(903, "rohne"), "0,2": _u(904, "allet")}
			, func(): return _board("0,0"), func(): return _board("0,2"),
			func(p): return p["board"]["0,2"]["aid"] == "rohne" and p["board"]["0,0"]["aid"] == "allet")
		await _case("보드→판매", hold, func(p):
			_clear_bench(p)
			p["gold"] = 0
			p["board"] = {"0,1": _u(905, "rohne")}
			, func(): return _board("0,1"), func(): return gs._sell_btn,
			func(p): return p["board"].is_empty() and p["gold"] > 0)
		await _case("아티팩트→사도", hold, func(p):
			_clear_bench(p)
			p["board"] = {"0,1": _u(906, "rohne")}
			p["inv"] = [{"uid": 7001, "id": "wooden_sword"}]
			, func(): return _art(7001), func(): return _board("0,1"),
			func(p): return p["board"]["0,1"]["arts"].size() == 1 and p["inv"].is_empty())
		await _case("아티팩트 합성", hold, func(p):
			p["inv"] = [{"uid": 7002, "id": "wooden_sword"}, {"uid": 7003, "id": "rusty_awl"}]
			, func(): return _art(7002), func(): return _art(7003),
			func(p): return p["inv"].size() == 1)
	print("DRAG SUITE DONE fails=%d" % fails)
	get_tree().quit()


func _u(uid: int, aid: String) -> Dictionary:
	return {"uid": uid, "aid": aid, "star": 1, "arts": [], "pers": ""}


func _clear_bench(p: Dictionary) -> void:
	for i in p["bench"].size():
		p["bench"][i] = null


func _shop(i: int) -> Control:
	return gs._shop_tiles[i]


func _bench(i: int) -> Control:
	return gs._bench_tiles[i]


func _board(k: String) -> Control:
	return gs._board_tiles[k]


func _art(uid: int) -> Control:
	return gs._art_buttons().get(uid)


func _case(name: String, hold: bool, setup: Callable, from_c: Callable, to_c: Callable, check: Callable) -> void:
	var p = g.player(App.session.my_pid)
	g.state["phase"] = "prep"
	g.phase_left = 999.0
	setup.call(p)
	g.state_changed.emit()
	gs.sel = {}
	await _wait(8)
	var a_ctrl: Control = from_c.call()
	var b_ctrl: Control = to_c.call()
	if a_ctrl == null or b_ctrl == null:
		print("FAIL %s%s: 칸을 찾지 못함" % [name, " (누르고 있다가)" if hold else ""])
		fails += 1
		return
	var xf: Transform2D = get_viewport().get_final_transform()
	var a: Vector2 = xf * a_ctrl.get_global_rect().get_center()
	var b: Vector2 = xf * b_ctrl.get_global_rect().get_center()
	_touch(a, true)
	await _wait(2)
	if hold:
		await get_tree().create_timer(0.6).timeout
	for i in 16:
		_drag(a.lerp(b, (i + 1) / 16.0))
		await _wait(1)
		if i == 8 and OS.get_environment("DRAG_DEBUG") != "":
			print("  mid drag: active=%s src=%s aid=%s" % [gs._drag.get("active"), gs._drag.get("src"), gs._drag.get("aid")])
	_touch(b, false)
	await _wait(10)
	var ok: bool = check.call(p)
	if not ok:
		print("  board=%s bench=%s gold=%d hover=%s" % [p["board"].keys(), p["bench"].map(func(x): return x["aid"] if x != null else "-"), p["gold"], gs._target_at(b / xf.x.x)])
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, " (누르고 있다가)" if hold else ""])
	if not ok:
		fails += 1


func _touch(pos: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = pos
	e.pressed = down
	Input.parse_input_event(e)


func _drag(pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = pos
	Input.parse_input_event(e)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
