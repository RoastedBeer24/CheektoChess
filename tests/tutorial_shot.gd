extends Node
## 튜토리얼 진행 확인: xvfb-run godot --path . --resolution 1920x1080 res://tests/tutorial_shot.tscn -- <출력 폴더>

func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(5)
	App.session.start_tutorial()
	await _wait(10)
	var tut: Tutorial = _find(main)
	await _shot(out, "t0")
	tut._next.pressed.emit()
	await _wait(5)
	await _shot(out, "t1_shop")
	App.session.submit({"t": "buy", "i": 0})
	await _wait(5)
	print("단계 %d (2=보드에 세우기 기대)" % (tut._step + 1))
	await _shot(out, "t2_board")
	App.session.submit({"t": "move", "from": {"bench": 0}, "to": {"board": "0,1"}})
	await _wait(5)
	App.session.submit({"t": "buy", "i": 1})
	App.session.submit({"t": "buy", "i": 2})
	await _wait(5)
	print("단계 %d (5=시너지 기대)" % (tut._step + 1))
	await _shot(out, "t3_synergy")
	get_tree().quit()


func _find(n: Node):
	for c in n.get_children():
		if c is Tutorial:
			return c
		var r = _find(c)
		if r != null:
			return r
	return null


func _shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
