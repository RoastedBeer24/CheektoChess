extends Node
## 전투 모션 확인용 캡처: xvfb-run godot --path . --resolution 1920x1080 res://tests/motion_shot.tscn -- <출력 폴더>

func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var bv := BattleView.new()
	bv.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bv)
	await get_tree().process_frame
	var a := [
		{"aid": "canna", "star": 2, "row": 2, "slot": 0, "arts": [], "pers": ""},
		{"aid": "meluna", "star": 2, "row": 2, "slot": 1, "arts": [], "pers": ""},
		{"aid": "jubee", "star": 2, "row": 1, "slot": 0, "arts": [], "pers": ""},
		{"aid": "joanne", "star": 2, "row": 1, "slot": 2, "arts": [], "pers": "순수"},
		{"aid": "rohne", "star": 2, "row": 0, "slot": 1, "arts": [], "pers": ""},
		{"aid": "allet", "star": 1, "row": 0, "slot": 2, "arts": [], "pers": ""},
	]
	var b := [
		{"aid": "amelia", "star": 1, "row": 2, "slot": 0, "arts": [], "pers": ""},
		{"aid": "daya", "star": 1, "row": 2, "slot": 2, "arts": [], "pers": ""},
		{"aid": "mayo", "star": 1, "row": 2, "slot": 1, "arts": [], "pers": ""},
		{"aid": "raika", "star": 2, "row": 0, "slot": 1, "arts": [], "pers": ""},
		{"aid": "kommy", "star": 1, "row": 0, "slot": 0, "arts": [], "pers": ""},
		{"aid": "guin", "star": 1, "row": 0, "slot": 2, "arts": [], "pers": ""},
	]
	bv.setup({"army_a": a, "army_b": b, "seed": 5}, 0, "우리 편", "상대")
	for t in [0.3, 1.6, 3.2, 6.0]:
		while bv._t < t and bv._playing:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("m_%04.1f.png" % t))
	get_tree().quit()
