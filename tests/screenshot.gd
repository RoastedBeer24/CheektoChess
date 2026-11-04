extends Node
## 화면 캡처용: xvfb-run godot --path . --resolution 1920x1080 res://tests/screenshot.tscn -- <출력 폴더>

var out := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(10)
	_shot("01_title")
	Session.start_offline(7)
	await _wait(10)
	var p = Session.state["players"][Session.my_pid]
	p["gold"] = 60
	p["shop"] = ["ed", "aya", "sylla", "joanne", "uros"]
	for i in 5:
		Session.submit({"t": "buy", "i": i})
	Session.submit({"t": "buy_xp"})
	Session.submit({"t": "buy_xp"})
	Session.submit({"t": "move", "from": {"bench": 0}, "to": {"board": "0,1"}})
	Session.submit({"t": "move", "from": {"bench": 1}, "to": {"board": "1,0"}})
	Session.submit({"t": "move", "from": {"bench": 2}, "to": {"board": "2,2"}})
	Session.submit({"t": "move", "from": {"bench": 3}, "to": {"board": "1,2"}, "pers": "우울"})
	p["inv"] = [{"uid": 90001, "id": "belita_staff"}, {"uid": 90002, "id": "kettlebell"}, {"uid": 90003, "id": "life_gem"}, {"uid": 90004, "id": "emergency_belt"}, {"uid": 90005, "id": "jade_codex"}]
	Session.submit({"t": "equip", "art": 90002, "loc": {"board": "2,2"}})
	Session.state_changed.emit()
	await _wait(10)
	var gs = _find_game_screen(main)
	gs._on_tile({"board": "2,2"})
	await _wait(5)
	_shot("02_prep")
	gs._on_tile({"bench": 4})
	gs._on_tile({"board": "0,0"})
	await _wait(5)
	_shot("03_personality")
	gs._close_modal()
	p["art_offer"] = {"options": ["tig_sword", "prickle_seal", "healing_pendant"], "rerolled": [false, true, false]}
	Session.state_changed.emit()
	await _wait(5)
	_shot("04_artifact_offer")
	Session.submit({"t": "art_pick", "i": 0})
	gs._close_modal()
	Session.submit({"t": "ready", "on": true})
	# 전투가 시작될 때까지
	var guard := 0
	Engine.time_scale = 20.0
	while not (Session.state["phase"] == "battle" and int(Session.state["round"]) >= 4) and guard < 20000:
		guard += 1
		if Session.state["phase"] == "prep" and not Session.state["players"][Session.my_pid]["ready"]:
			Session.submit({"t": "ready", "on": true})
		await get_tree().process_frame
	Engine.time_scale = 1.0
	await get_tree().create_timer(2.5).timeout
	_shot("05_battle")
	get_tree().quit()


func _find_game_screen(n: Node):
	for c in n.get_children():
		if c is GameScreen:
			return c
		var r = _find_game_screen(c)
		if r != null:
			return r
	return null


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("saved ", name)
