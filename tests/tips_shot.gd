extends Node
## 툴팁·용어·색 규칙 확인용 캡처
##   xvfb-run godot --path . --resolution 1920x1080 res://tests/tips_shot.tscn -- <출력 폴더>

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
	App.session.start_offline(7)
	await _wait(10)
	var p = App.session.state["players"][App.session.my_pid]
	p["gold"] = 13
	p["shop"] = ["mayo", "aya", "sylla", "erpin", "vela"]
	App.session.submit({"t": "buy", "i": 0})
	App.session.submit({"t": "buy", "i": 1})
	App.session.submit({"t": "move", "from": {"bench": 0}, "to": {"board": "0,1"}})
	p["inv"] = [{"uid": 9001, "id": "tig_sword"}, {"uid": 9002, "id": "life_gem"}]
	App.session.state_changed.emit()
	await _wait(5)
	var gs = _find(main)
	gs._on_tile({"board": "0,1"})
	await _wait(5)
	await _hover(gs._gold_lbl, "t1_gold")
	await _hover(gs._shop_tiles[2], "t2_shop")
	await _hover(gs._xp_btn, "t3_xp_lack")
	var ab: Button = gs._art_buttons()[9001]
	await _hover(ab, "t4_artifact")
	Tips.inst.dismiss()
	Tips.inst.show_term("강화 공격", Vector2(1500, 600))
	await _wait(4)
	await _shot("t5_term")
	Tips.inst.hide_tip()
	var cx := Codex.new()
	gs.add_child(cx)
	await _wait(3)
	cx._set_tab("terms")
	await _wait(5)
	await _shot("t6_terms_tab")
	get_tree().quit()


func _hover(c: Control, name: String) -> void:
	var pos: Vector2 = c.get_global_rect().get_center()
	var w := get_viewport().get_final_transform() * pos
	get_viewport().warp_mouse(pos)
	var e := InputEventMouseMotion.new()
	e.position = w
	e.global_position = w
	Input.parse_input_event(e)
	await get_tree().create_timer(0.6).timeout
	await _shot(name)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))


func _find(n: Node):
	for c in n.get_children():
		if c is GameScreen:
			return c
		var r = _find(c)
		if r != null:
			return r
	return null


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
