extends Node
## 도감·시너지 팝업·정찰·잠금 화면 캡처
var out := "user://shots"

func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(5)
	await _shot("c0_title")
	var cx := Codex.new()
	main.add_child(cx)
	await _wait(3)
	cx._search.text = "ㅇㄹ"
	cx.query = "ㅇㄹ"
	cx.picked = {"cost": {"4": true, "5": true}}
	cx._build_filters()
	cx._rebuild()
	cx._show_apostle("erpin")
	await _wait(5)
	await _shot("c1_codex_apostle")
	cx._set_tab("artifact")
	cx.picked = {"grade": {"전설": true}, "kind": {"애착": true}}
	cx._build_filters()
	cx._rebuild()
	cx._show_artifact("tig_sword")
	await _wait(5)
	await _shot("c2_codex_artifact")
	cx.queue_free()
	App.session.start_offline(7)
	await _wait(10)
	var gs = _find(main)
	var p = App.session.state["players"][App.session.my_pid]
	p["gold"] = 40
	p["level"] = 4
	p["shop"] = ["aya", "picora", "aya", "jade", "belita"]
	App.session.submit({"t": "buy", "i": 0})
	App.session.submit({"t": "buy", "i": 1})
	App.session.submit({"t": "move", "from": {"bench": 0}, "to": {"board": "1,1"}})
	App.session.submit({"t": "move", "from": {"bench": 1}, "to": {"board": "2,1"}})
	App.session.submit({"t": "lock", "i": 3, "on": true})
	App.session.state_changed.emit()
	await _wait(5)
	var row = gs._syn_box.get_child(0)
	gs._show_syn_popup(row, "냉정", 2)
	await _wait(3)
	await _shot("c3_synergy_popup")
	gs._hide_syn_popup()
	var other: String = ""
	for pid in App.session.state["players"]:
		if pid != App.session.my_pid:
			other = pid
			break
	gs._show_player(other)
	await _wait(3)
	await _shot("c4_scout")
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


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)
