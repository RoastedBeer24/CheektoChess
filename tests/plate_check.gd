extends Node
## 전투 이름표 검사: 이름표가 사도 그림 뒤 레이어에 있는지, 쓰러진 사도 이름표가 사라지는지, SP 막대가 차오르는지.
##   godot --path . --resolution 1920x1080 res://tests/plate_check.tscn -- <출력 폴더>

var fails := 0


func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(10)
	App.session.start_offline(7)
	await _wait(10)
	var g = App.session.game
	g.player(App.session.my_pid)["connected"] = false
	var checked := 0
	var t := 0
	while checked < 3 and g.state["phase"] != "over" and t < 60000:
		t += 1
		g.advance(0.5)
		App.session._flush()
		if g.state["round"] >= 3 + checked * 2 and g.state["phase"] == "battle":
			var bvs = main.find_children("*", "BattleView", true, false)
			if not bvs.is_empty() and bvs[0].visible:
				var keep = App.session.game
				App.session.game = null
				await _check(bvs[0], out, checked)
				App.session.game = keep
				checked += 1
		if t % 50 == 0:
			await get_tree().process_frame
	if checked == 0:
		print("PLATE FAIL 전투를 못 봄")
		fails += 1
	print("PLATE CHECK DONE fails=%d" % fails)
	get_tree().quit()


func _check(bv, out: String, k: int) -> void:
	var died_at := {}
	var sp_seen := false
	var layer_ok: bool = bv._bar_layer.get_index() < bv._field.get_index()
	if not layer_ok:
		print("PLATE FAIL 이름표 레이어가 사도 그림보다 위")
		fails += 1
	var shot := false
	var end_f := -1
	for f in 900:
		await get_tree().process_frame
		if not bv._playing and bv._end_stage == 0 and f > 30:
			break
		for i in bv._plates:
			var pl = bv._plates[i]
			if pl.get_parent() != bv._bar_layer:
				print("PLATE FAIL 이름표 %d 가 이름표 레이어 밖" % i)
				fails += 1
				return
			if bv._anim.get(i, {}).get("dead", false):
				if not died_at.has(i):
					died_at[i] = f
				elif f - int(died_at[i]) > 40 and pl.visible:
					print("PLATE FAIL 쓰러진 사도 %d 이름표가 남아 있음" % i)
					fails += 1
					died_at[i] = 1 << 30
			else:
				died_at.erase(i)
				if pl.show_sp and pl.sp > 0.05:
					sp_seen = true
		if bv._end_stage == 3 and end_f < 0:
			end_f = f
		if end_f >= 0 and f == end_f + 20:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("plate_end_%d.png" % k))
			if bv._mvp_panel == null or not is_instance_valid(bv._mvp_panel):
				print("PLATE 참고: 전투 %d MVP 카드 없음 (우리 편 활약 0?)" % k)
			break
		if not shot and f == 150:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("plate_%d.png" % k))
			shot = true
	if not sp_seen:
		print("PLATE FAIL SP 막대가 한 번도 차오르지 않음")
		fails += 1
	print("PLATE 전투 %d: 쓰러짐 %d, SP 표시 %s" % [k, died_at.size(), sp_seen])


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
