extends Node
## 공유 선택·몬스터 전투 캡처: xvfb-run godot --path . --resolution 1920x1080 res://tests/rounds_shot.tscn -- <출력 폴더>

func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(5)
	App.session.start_offline(5)
	await _wait(10)
	var m: Match = App.session.game
	m.state["round"] = 4
	m._start_carousel(4)
	# 내 차례가 오도록 순서 맨 앞에
	var order: Array = m.state["carousel"]["order"]
	order.erase(App.session.my_pid)
	order.push_front(App.session.my_pid)
	App.session._flush()
	await _wait(10)
	await _shot(out, "r1_carousel")
	App.session.submit({"t": "carousel_pick", "i": 2})
	await _wait(30)
	await _shot(out, "r2_carousel_after")
	# 몬스터 라운드 전투
	while m.state["phase"] != "prep":
		m.advance(0.5)
		await get_tree().process_frame
	var p = m.player(App.session.my_pid)
	p["gold"] = 50
	p["shop"] = ["rohne", "aya", "butter", "selene", "kommy"]
	for i in 5:
		App.session.submit({"t": "buy", "i": i})
	App.session.submit({"t": "move", "from": {"bench": 0}, "to": {"board": "0,1"}})
	App.session.submit({"t": "move", "from": {"bench": 1}, "to": {"board": "1,1"}})
	App.session.submit({"t": "move", "from": {"bench": 2}, "to": {"board": "2,1"}})
	m.state["round_kind"] = "monster"
	m.state["round"] = 6
	m._start_battle()
	App.session._flush()
	await get_tree().create_timer(2.5).timeout
	await _shot(out, "r3_monster")
	get_tree().quit()


func _shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
