extends Node
## LAN 버전 맞추기 테스트 (같은 기기, 서로 다른 묶음 폴더)
##   CHEEKTO_BUILD=5 CHEEKTO_PACK_DIR=<방장 폴더> godot --headless --path . res://tests/lan_update_test.tscn -- host
##   CHEEKTO_BUILD=3 CHEEKTO_PACK_DIR=<참가자 폴더> godot --headless --path . res://tests/lan_update_test.tscn -- client

func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var role: String = OS.get_cmdline_user_args()[0]
	if role == "host":
		App.session.my_name = "방장"
		App.session.token = "host-t"
		App.session.host_room()
		print("[host] build=%d hosting" % App.build)
		await get_tree().create_timer(12.0).timeout
	else:
		App.session.my_name = "참가자"
		App.session.token = "client-t"
		await get_tree().create_timer(0.8).timeout
		var done := [false]
		App.session.update_progress.connect(func(t, r): print("[client] ", t, " ", snappedf(r, 0.01)))
		App.session.update_done.connect(func(): done[0] = true)
		App.session.join_room("127.0.0.1")
		var t := 0
		while not done[0] and t < 200:
			await get_tree().create_timer(0.05).timeout
			t += 1
		var inst := App.installed()
		print("[client] done=%s installed_build=%s core_sha=%s" % [done[0], inst.get("build"), str(inst.get("packs", {}).get("core", {}).get("sha256", "")).left(12)])
	get_tree().quit()
