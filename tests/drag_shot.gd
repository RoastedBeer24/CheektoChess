extends Node
## 끌어다 놓기 화면 확인용 캡처
##   xvfb-run godot --path . --resolution 2000x923 res://tests/drag_shot.tscn -- <출력 폴더>

var out := "user://shots"


func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(5)
	await _shot("d0_title")
	App.session.start_offline(7)
	await _wait(10)
	var p = App.session.state["players"][App.session.my_pid]
	p["gold"] = 30
	p["shop"] = ["picora", "rim", "ed", "naia", "sylla"]
	App.session.submit({"t": "buy", "i": 0})
	App.session.submit({"t": "move", "from": {"bench": 0}, "to": {"board": "2,1"}})
	p["level"] = 3
	App.session.state_changed.emit()
	await _wait(5)
	var gs = _find(main)
	# 1) 상점의 림(전열)을 끌어 후열 칸 위에 올린 상태 → 불가 표시
	var shop_tile = gs._shop_tiles[1]
	var src: Vector2 = shop_tile.get_global_rect().get_center()
	var bad: Vector2 = gs._board_tiles["2,0"].get_global_rect().get_center()
	await _press(src)
	print("after press drag=", gs._drag.keys(), " prep=", gs._is_prep(), " mouse=", gs.get_global_mouse_position(), " src=", src)
	await _move_to(src, bad)
	print("after move active=", gs._drag.get("active"), " hover=", gs._drag.get("hover"))
	await _shot("d1_drag_bad")
	# 2) 전열 칸 위로 → 가능 + 미리보기
	var good: Vector2 = gs._board_tiles["0,0"].get_global_rect().get_center()
	await _move_to(bad, good)
	await _shot("d2_drag_good")
	await _release(good)
	await _wait(5)
	await _shot("d3_dropped")
	# 4) 보드의 피코라(후열)를 끌어 대기석 위로
	var from: Vector2 = gs._board_tiles["2,1"].get_global_rect().get_center()
	var to: Vector2 = gs._bench_tiles[2].get_global_rect().get_center()
	await _press(from)
	await _move_to(from, to)
	await _shot("d4_board_to_bench")
	await _release(to)
	await _wait(5)
	await _shot("d5_after")
	get_tree().quit()


func _find(n: Node):
	for c in n.get_children():
		if c is GameScreen:
			return c
		var r = _find(c)
		if r != null:
			return r
	return null


## 화면 배율(stretch)을 반영해 캔버스 좌표 → 창 좌표
func _win(pos: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * pos


func _ev_button(pos: Vector2, pressed: bool) -> void:
	get_viewport().warp_mouse(pos)
	pos = _win(pos)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)


func _press(pos: Vector2) -> void:
	_ev_button(pos, true)
	await _wait(3)


func _release(pos: Vector2) -> void:
	_ev_button(pos, false)
	await _wait(3)


func _move_to(a: Vector2, b: Vector2) -> void:
	for i in range(1, 13):
		var cpos := a.lerp(b, i / 12.0)
		get_viewport().warp_mouse(cpos)
		var pos := _win(cpos)
		var e := InputEventMouseMotion.new()
		e.position = pos
		e.global_position = pos
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(e)
		await get_tree().process_frame
	await _wait(3)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)
