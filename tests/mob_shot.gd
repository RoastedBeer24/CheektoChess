extends Node
## 몬스터 전투(9·16라운드), 볼스패닉 의상 전투, 보드 옆 펫 캡처
##   godot --path . --resolution 2340x1080 res://tests/mob_shot.tscn -- <출력 폴더>
func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	var m := Match.new([{"id": "a", "name": "나", "bot": false}, {"id": "b", "name": "봇", "bot": true}], 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var mine := []
	var ids: Array = GameData.roster.duplicate()
	for i in 7:
		var aid: String = ids[(i * 9) % ids.size()]
		var r: int = {"front": 0, "mid": 1, "back": 2}.get(GameData.apostle(aid).get("row", "mid"), 1)
		mine.append({"aid": aid, "star": 2, "row": r, "slot": i % 3, "arts": [], "pers": ""})
	for r in [9, 16]:
		await _battle(out, "m%d" % r, mine, m.monster_army(r, rng))
	# 볼스패닉
	GameData.set_group("g2")
	var g2: Array = GameData.roster.duplicate()
	var a := []
	var b := []
	for i in 7:
		for side in 2:
			var aid: String = g2[(i * 7 + side * 31) % g2.size()]
			var row: int = {"front": 0, "mid": 1, "back": 2}.get(GameData.apostle(aid).get("row", "mid"), 1)
			(a if side == 0 else b).append({"aid": aid, "star": 1 + i % 2, "row": row, "slot": i % 3, "arts": [], "pers": ""})
	await _battle(out, "g2", a, b)
	# 펫 (보드 옆)
	GameData.set_group("g1")
	Settings._data["pet"] = GameData.pets[3]["id"] if not GameData.pets.is_empty() else ""
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(10)
	App.session.start_offline(7)
	await _wait(90)
	await _shot(out, "pet")
	get_tree().quit()


func _battle(out: String, name: String, a: Array, b: Array) -> void:
	var bv := BattleView.new()
	bv.set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	layer.add_child(bv)
	await _wait(2)
	bv.setup({"army_a": a, "army_b": b, "seed": 7}, 0, "나", name)
	await _wait(200)
	await _shot(out, name)
	layer.queue_free()


func _shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
