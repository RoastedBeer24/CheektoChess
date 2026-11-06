extends Node
## 화면 너비 넘침 확인: 위 막대·가운데 줄·아래 줄의 최소 너비를 화면 너비와 비교
func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _w(10)
	App.session.start_offline(7)
	await _w(60)
	var gs = main.find_children("*", "GameScreen", true, false)[0]
	var vw: float = gs.get_viewport_rect().size.x
	print("PROBE viewport=", gs.get_viewport_rect().size)
	for i in gs._root.get_child_count():
		var c: Control = gs._root.get_child(i)
		print("PROBE row ", i, " ", c.get_class(), " min=", c.get_combined_minimum_size(), " over=", c.get_combined_minimum_size().x > vw)
		if c is BoxContainer:
			for cc in c.get_children():
				if cc is Control:
					print("PROBE    ", cc.name, " min=", (cc as Control).get_combined_minimum_size())
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	if out != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()


func _w(n: int) -> void:
	for i in n:
		await get_tree().process_frame
