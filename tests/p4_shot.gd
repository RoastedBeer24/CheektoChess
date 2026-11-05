extends Node
## 합성 연출·전투 통계·라운드 기록·다시보기 캡처

func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(10)
	Settings._data["rules"] = {}
	App.session.start_offline(7)
	await _wait(10)
	var g = App.session.game
	var p = g.player(App.session.my_pid)
	p["gold"] = 20
	p["shop"] = ["rohne", "rohne", "rohne", "bana", "festa"]
	g.state_changed.emit()
	await _wait(5)
	App.session.submit({"t": "buy", "i": 0})
	App.session.submit({"t": "move", "from": {"bench": 0}, "to": {"board": "0,1"}})
	await _wait(5)
	App.session.submit({"t": "buy", "i": 1})
	await _wait(3)
	App.session.submit({"t": "buy", "i": 2})
	await _wait(8)
	await _shot(out, "p1_merge")
	App.session.submit({"t": "buy", "i": 3})
	App.session.submit({"t": "move", "from": {"bench": 0}, "to": {"board": "2,1"}})
	g.phase_left = 0.1
	var gs = main.get_node_or_null("GameScreen")
	var t := 0
	while App.session.state["phase"] != "result" and t < 4000:
		await get_tree().process_frame
		t += 1
		if App.session.state["phase"] == "battle":
			for c in main.find_children("*", "BattleView", true, false):
				if c.visible and c.finished():
					await _wait(30)
					await _shot(out, "p2_stats")
					g.phase_left = 0.1
					break
	await _wait(20)
	var screens = main.find_children("*", "GameScreen", true, false)
	if not screens.is_empty():
		screens[0]._show_round_log(false)
		await _wait(10)
		await _shot(out, "p3_log")
		screens[0]._show_replay(screens[0]._round_log[0], false)
		await get_tree().create_timer(3.0).timeout
		await _shot(out, "p4_replay")
	get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
