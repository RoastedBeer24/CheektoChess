extends Node
## LAN 테스트: 같은 기기에서 방장/참가자 두 프로세스를 띄운다.
##   godot --headless --path . res://tests/lan_test.tscn -- host
##   godot --headless --path . res://tests/lan_test.tscn -- client

var role := ""


func _ready() -> void:
	role = OS.get_cmdline_user_args()[0]
	if role == "host":
		await _host()
	else:
		await _client()
	get_tree().quit()


func _log(msg: String) -> void:
	print("[%s] %s" % [role, msg])


func _host() -> void:
	Session.my_name = "방장"
	Session.token = "host-token"
	var err := Session.host_room()
	_log("host_room -> %d, ips=%s" % [err, Net.local_ips()])
	for i in 2:
		Session.add_bot()
	# 참가자 대기
	var t := 0
	while Session.lobby.size() < 4 and t < 600:
		await get_tree().create_timer(0.05).timeout
		t += 1
	_log("lobby: %s" % [Session.lobby.map(func(p): return p["name"])])
	Session.start_game()
	# 참가자가 구매했는지 확인
	t = 0
	var client_pid := ""
	for p in Session.lobby:
		if p["name"] == "참가자":
			client_pid = p["id"]
	while t < 400:
		await get_tree().create_timer(0.05).timeout
		t += 1
		var cp = Session.state["players"][client_pid]
		if cp["gold"] < 6:
			break
	var cp = Session.state["players"][client_pid]
	_log("client gold after buy = %d, bench0=%s" % [cp["gold"], cp["bench"][0]])
	# 끊김 → 재접속 확인
	t = 0
	var saw_dc := false
	while t < 400:
		await get_tree().create_timer(0.05).timeout
		t += 1
		cp = Session.state["players"][client_pid]
		if not cp["connected"]:
			saw_dc = true
		if saw_dc and cp["connected"]:
			break
	_log("disconnect seen=%s, reconnected=%s, alive=%s round=%d" % [saw_dc, cp["connected"], cp["alive"], Session.state["round"]])
	await get_tree().create_timer(1.0).timeout
	Session.leave()


func _client() -> void:
	Session.my_name = "참가자"
	Session.token = "client-token"
	await get_tree().create_timer(0.5).timeout
	var err := Session.join_room("127.0.0.1")
	_log("join -> %d" % err)
	var t := 0
	while Session.state.is_empty() and t < 600:
		await get_tree().create_timer(0.05).timeout
		t += 1
	_log("got state: round=%s phase=%s my_pid=%s players=%d" % [Session.state.get("round"), Session.state.get("phase"), Session.my_pid, Session.state.get("players", {}).size()])
	Session.submit({"t": "buy", "i": 0})
	await get_tree().create_timer(1.0).timeout
	var me = Session.state["players"][Session.my_pid]
	_log("after buy: gold=%d bench0=%s" % [me["gold"], me["bench"][0]])
	# 연결 끊기 후 같은 라운드 안에 재접속
	Net.stop()
	_log("disconnected")
	await get_tree().create_timer(1.0).timeout
	err = Session.join_room("127.0.0.1")
	t = 0
	while Session.state.is_empty() and t < 200:
		await get_tree().create_timer(0.05).timeout
		t += 1
	_log("rejoin -> err=%d state_round=%s mode=%s" % [err, Session.state.get("round"), Session.mode])
	await get_tree().create_timer(2.0).timeout
