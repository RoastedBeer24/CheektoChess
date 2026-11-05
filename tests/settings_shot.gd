extends Node
## 설정·기록 화면 캡처: xvfb-run godot --path . --resolution 1920x1080 res://tests/settings_shot.tscn -- <출력 폴더>

func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	# 가짜 기록 하나
	var st := {"seed": 999001, "round": 14, "group": GameData.group_id, "players": {"me": {"id": "me", "place": 2, "board": {
		"0,0": {"aid": "rohne", "star": 2}, "1,0": {"aid": "aya", "star": 2}, "2,0": {"aid": "butter", "star": 1}}}, "b1": {}, "b2": {}, "b3": {}}}
	History.record(st, "me", "offline")
	var sp := SettingsPanel.new()
	main.add_child(sp)
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("s1_settings.png"))
	sp._set_tab("history")
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("s2_history.png"))
	get_tree().quit()
