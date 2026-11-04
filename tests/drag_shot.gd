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
	# 6) 아티팩트: 보관함 → 사도에 장착 (끄는 중), 같은 등급끼리 합성 대상 표시
	p["inv"] = [{"uid": 8001, "id": "wooden_sword"}, {"uid": 8002, "id": "rusty_awl"}, {"uid": 8003, "id": "life_gem"}]
	var rim_key := ""
	for k in p["board"]:
		rim_key = k
	p["board"][rim_key]["arts"] = [{"uid": 8004, "id": "towel_headband"}, {"uid": 8005, "id": "patched_staff"}]
	App.session.state_changed.emit()
	await _wait(5)
	var art_btn: Button = gs._art_buttons()[8001]
	var a_from: Vector2 = art_btn.get_global_rect().get_center()
	var a_to: Vector2 = gs._board_tiles[rim_key].get_global_rect().get_center()
	await _press(a_from)
	await _move_to(a_from, a_to)
	await _shot("d6_art_to_unit")
	var a_to2: Vector2 = gs._art_buttons()[8002].get_global_rect().get_center()
	await _move_to(a_to, a_to2)
	await _shot("d7_art_to_art")
	await _release(a_to2)
	await _wait(5)
	# 7) 장착 중인 같은 등급 2개 → 합성 버튼
	gs.sel = {"unit": {"board": rim_key}}
	gs.refresh()
	await _wait(5)
	await _shot("d8_equipped_merge")
	var before: int = p["inv"].size()
	var mb: Button = null
	for c in gs._detail_box.get_children():
		if c is Button and String(c.text).contains("보관함으로"):
			mb = c
			break
	if mb == null:
		push_error("장착 합성 버튼 없음")
	else:
		mb.pressed.emit()
		await _wait(5)
		var after: int = gs.me()["inv"].size()
		print("장착 합성: 보관함 %d → %d, 장착 %d개" % [before, after, gs.me()["board"][rim_key]["arts"].size()])
	await _shot("d9_after_equipped_merge")
	# 8) 보관함을 손가락으로 끌어 스크롤: 스크롤만 되고 아티팩트가 선택·장착되지 않아야 한다
	var inv := []
	for i in 12:
		inv.append({"uid": 8100 + i, "id": ["life_gem", "wooden_sword", "rusty_awl"][i % 3]})
	p["inv"] = inv
	gs.sel = {}
	App.session.state_changed.emit()
	await _wait(5)
	var ib: Button = gs._art_buttons()[8102]
	var iscroll: ScrollContainer = gs._inv_grid.get_parent()
	var s0 := iscroll.scroll_vertical
	var f: Vector2 = ib.get_global_rect().get_center()
	await _press(f)
	await _move_to(f, f + Vector2(0, -110))
	await _release(f + Vector2(0, -110))
	await _wait(20)
	print("손가락 스크롤: %d → %d, 선택=%s, 보관함 %d개" % [s0, iscroll.scroll_vertical, str(gs.sel), gs.me()["inv"].size()])
	if iscroll.scroll_vertical <= s0 or gs.sel.has("art") or gs.me()["inv"].size() != 12:
		push_error("손가락 스크롤 실패")
	# 짧게 누르기는 그대로 선택
	var ib2: Button = gs._art_buttons()[8105]
	var f2: Vector2 = ib2.get_global_rect().get_center()
	await _press(f2)
	await _release(f2)
	await _wait(3)
	print("짧게 누르기 선택=%s" % str(gs.sel))
	await _shot("d10_inv_scrolled")
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
