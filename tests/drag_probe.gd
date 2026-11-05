extends Node
## 끌기 재현: 창 좌표로 터치(또는 마우스) 입력을 넣어 대기석 → 보드 이동이 되는지
##   CHEEKTO_UI_SCALE=1.3 godot --path . --resolution 2340x1080 res://tests/drag_probe.tscn -- [touch|mouse] [hold]

var mode := "touch"
var hold := false


func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]
	hold = args.size() > 1 and args[1] == "hold"
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(10)
	App.session.start_offline(3)
	await _wait(20)
	var g = App.session.game
	var p = g.player(App.session.my_pid)
	p["bench"][0] = {"uid": 900, "aid": "rohne", "star": 1, "arts": [], "pers": ""}
	g.state_changed.emit()
	await _wait(10)
	var gs = main.find_children("*", "GameScreen", true, false)[0]
	var src: Control = gs._bench_tiles[0]
	var dst: Control = gs._board_tiles["0,1"]
	var sc: float = get_tree().root.content_scale_factor
	# 캔버스 좌표 → 창(물리) 좌표
	var xf: Transform2D = get_viewport().get_final_transform()
	var a: Vector2 = xf * src.get_global_rect().get_center()
	var b: Vector2 = xf * dst.get_global_rect().get_center()
	print("scale=", sc, " final=", xf, " from=", a, " to=", b)
	await _press(a)
	if hold:
		await get_tree().create_timer(0.6).timeout
	for i in 20:
		await _move(a.lerp(b, (i + 1) / 20.0))
		await _wait(1)
	await _release(b)
	await _wait(10)
	var on_board: bool = p["board"].has("0,1")
	print("RESULT mode=%s hold=%s moved_to_board=%s bench0=%s" % [mode, hold, on_board, p["bench"][0]])
	get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _press(pos: Vector2) -> void:
	if mode == "touch":
		var e := InputEventScreenTouch.new()
		e.index = 0
		e.position = pos
		e.pressed = true
		Input.parse_input_event(e)
	else:
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_LEFT
		m.pressed = true
		m.position = pos
		m.global_position = pos
		Input.parse_input_event(m)
	await _wait(2)


func _move(pos: Vector2) -> void:
	if mode == "touch":
		var e := InputEventScreenDrag.new()
		e.index = 0
		e.position = pos
		Input.parse_input_event(e)
	else:
		var m := InputEventMouseMotion.new()
		m.position = pos
		m.global_position = pos
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(m)


func _release(pos: Vector2) -> void:
	if mode == "touch":
		var e := InputEventScreenTouch.new()
		e.index = 0
		e.position = pos
		e.pressed = false
		Input.parse_input_event(e)
	else:
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_LEFT
		m.pressed = false
		m.position = pos
		m.global_position = pos
		Input.parse_input_event(m)
	await _wait(2)
