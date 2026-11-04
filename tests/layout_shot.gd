extends Node
## 여러 화면 비율에서 게임 화면이 잘리거나 겹치지 않는지 확인 (창 크기는 --resolution 으로)
##   xvfb-run godot --path . --resolution 2000x923 res://tests/layout_shot.tscn -- <출력 폴더> <이름>

func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://shots"
	var name: String = args[1] if args.size() > 1 else "layout"
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(5)
	App.session.start_offline(7)
	await _wait(10)
	var p = App.session.state["players"][App.session.my_pid]
	p["gold"] = 80
	p["shop"] = ["ed", "aya", "sylla", "joanne", "uros"]
	for i in 3:
		App.session.submit({"t": "buy", "i": i})
	App.session.submit({"t": "move", "from": {"bench": 0}, "to": {"board": "0,1"}})
	p["inv"] = []
	for i in 9:
		p["inv"].append({"uid": 70000 + i, "id": ["life_gem", "wooden_sword", "rusty_awl", "towel_headband", "patched_staff", "kettlebell"][i % 6]})
	App.session.state_changed.emit()
	await _wait(5)
	var gs = _find(main)
	gs._on_tile({"board": "0,1"})
	await _wait(8)
	var vr := get_viewport().get_visible_rect()
	var root_min: float = gs._root.get_combined_minimum_size().y
	var shop_bottom: float = gs._shop_tiles[0].get_global_rect().end.y
	print("LAYOUT %s canvas=%s root_min=%.0f fit=%.2f shop_bottom=%.0f %s" % [name, vr.size, root_min, gs._fit_k, shop_bottom, "OK" if shop_bottom <= vr.size.y + 1 else "CUT"])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	get_tree().quit()


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
