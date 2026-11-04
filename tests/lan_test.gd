extends Node
## LAN 테스트: 같은 기기에서 방장/참가자 두 프로세스를 띄운다.
##   godot --headless --path . res://tests/lan_test.tscn -- host
##   godot --headless --path . res://tests/lan_test.tscn -- client

var role := ""


func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	role = OS.get_cmdline_user_args()[0]
	if role == "host":
		await _host()
	else:
		await _client()
	get_tree().quit()


func _log(msg: String) -> void:
	print("[%s] %s" % [role, msg])


func _host() -> void:
	App.session.my_name = "방장"
	App.session.token = "host-token"
	var err := App.session.host_room()
	_log("host_room -> %d, ips=%s" % [err, App.net.local_ips()])
	for i in 2:
		App.session.add_bot()
	# 참가자 대기
	var t := 0
	while App.session.lobby.size() < 4 and t < 600:
		await get_tree().create_timer(0.05).timeout
		t += 1
	_log("lobby: %s" % [App.session.lobby.map(func(p): return p["name"])])
	App.session.start_game()
	# 참가자가 구매했는지 확인
	t = 0
	var client_pid := ""
	for p in App.session.lobby:
		if p["name"] == "참가자":
			client_pid = p["id"]
	while t < 400:
		await get_tree().create_timer(0.05).timeout
		t += 1
		var cp = App.session.state["players"][client_pid]
		if cp["gold"] < 6:
			break
	var cp = App.session.state["players"][client_pid]
	_log("client gold after buy = %d, bench0=%s" % [cp["gold"], cp["bench"][0]])
	# 끊김 → 재접속 확인
	t = 0
	var saw_dc := false
	while t < 400:
		await get_tree().create_timer(0.05).timeout
		t += 1
		cp = App.session.state["players"][client_pid]
		if not cp["connected"]:
			saw_dc = true
		if saw_dc and cp["connected"]:
			break
	_log("disconnect seen=%s, reconnected=%s, alive=%s round=%d" % [saw_dc, cp["connected"], cp["alive"], App.session.state["round"]])
	await get_tree().create_timer(1.0).timeout
	App.session.leave()


func _client() -> void:
	App.session.my_name = "참가자"
	App.session.token = "client-token"
	await get_tree().create_timer(0.5).timeout
	var err := App.session.join_room("127.0.0.1")
	_log("join -> %d" % err)
	var t := 0
	while App.session.state.is_empty() and t < 600:
		await get_tree().create_timer(0.05).timeout
		t += 1
	_log("got state: round=%s phase=%s my_pid=%s players=%d" % [App.session.state.get("round"), App.session.state.get("phase"), App.session.my_pid, App.session.state.get("players", {}).size()])
	App.session.submit({"t": "buy", "i": 0})
	await get_tree().create_timer(1.0).timeout
	var me = App.session.state["players"][App.session.my_pid]
	_log("after buy: gold=%d bench0=%s" % [me["gold"], me["bench"][0]])
	# 연결 끊기 후 같은 라운드 안에 재접속
	App.net.stop()
	_log("disconnected")
	await get_tree().create_timer(1.0).timeout
	err = App.session.join_room("127.0.0.1")
	t = 0
	while App.session.state.is_empty() and t < 200:
		await get_tree().create_timer(0.05).timeout
		t += 1
	_log("rejoin -> err=%d state_round=%s mode=%s" % [err, App.session.state.get("round"), App.session.mode])
	await get_tree().create_timer(2.0).timeout
