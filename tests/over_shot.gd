extends Node
## 게임 종료(MVP 3인) 화면과 전투 통계 창 캡처
##   CHEEKTO_UI_SCALE=1.3 godot --path . --resolution 2340x1080 res://tests/over_shot.tscn -- <출력 폴더>

func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	Settings._data["battle_full"] = 2
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(10)
	App.session.start_offline(7)
	await _wait(10)
	var g = App.session.game
	# 내 자리는 봇이 대신 → 빠르게 진행
	g.player(App.session.my_pid)["connected"] = false
	var shot_stats := false
	var t := 0
	while g.state["phase"] != "over" and t < 60000:
		t += 1
		g.advance(0.5)
		App.session._flush()
		if not shot_stats and g.state["round"] >= 3 and g.state["phase"] == "battle":
			var bvs = main.find_children("*", "BattleView", true, false)
			if not bvs.is_empty() and bvs[0].visible:
				bvs[0].skip_to_end()
				await _wait(20)
				await _shot(out, "o1_stats")
				shot_stats = true
		if t % 50 == 0:
			await get_tree().process_frame
	await _wait(30)
	await _shot(out, "o2_over")
	get_tree().quit()


func _shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
