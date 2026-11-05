extends Node
## 증강·규칙 화면 캡처: xvfb-run godot --path . --resolution 1920x1080 res://tests/aug_shot.tscn -- <출력 폴더>

func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 10:
		await get_tree().process_frame
	main._show_rules_with({"fast": true, "augments": true, "gold": 1})
	for i in 5:
		await get_tree().process_frame
	await _shot(out, "a1_rules")
	main._close_modal()
	Settings._data["rules"] = {"augments": true}
	App.session.start_offline(7)
	for i in 10:
		await get_tree().process_frame
	var g = App.session.game
	var p = g.player(App.session.my_pid)
	p["augs"] = [{"id": "b_shield"}, {"id": "emblem", "trait": "정령산"}]
	p["aug_offer"] = {"options": [{"id": "fated"}, {"id": "b_revive"}, {"id": "emblem", "trait": "벨리티엔"}], "rerolled": false}
	g.state_changed.emit()
	for i in 10:
		await get_tree().process_frame
	await _shot(out, "a2_aug_offer")
	App.session.submit({"t": "aug_pick", "i": 1})
	for i in 10:
		await get_tree().process_frame
	await _shot(out, "a3_aug_chips")
	get_tree().quit()


func _shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
