extends Node
## 방장 넘기기 시험: 같은 기기에서 방장 1 + 참가자 2 프로세스.
##   godot --headless --path . res://tests/lan_migrate.tscn -- host [crash]
##   godot --headless --path . res://tests/lan_migrate.tscn -- c1
##   godot --headless --path . res://tests/lan_migrate.tscn -- c2
## 방장이 나가면(crash: 알리지 않고 종료) 참가자 중 id 가 앞선 c1 이 새 방장이 되고 c2 가 다시 연결돼야 한다.

var role := ""


func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	role = args[0]
	if role == "host":
		await _host(args.size() > 1 and args[1] == "crash")
	else:
		await _client()
	get_tree().quit()


func _log(msg: String) -> void:
	print("[%s] %s" % [role, msg])


func _host(crash: bool) -> void:
	App.session.my_name = "방장"
	App.session.token = "a-host"
	App.session.host_room()
	App.session.add_bot()
	var t := 0
	while App.session.lobby.size() < 4 and t < 400:
		await get_tree().create_timer(0.05).timeout
		t += 1
	App.session.start_game()
	_log("started, players=%d" % App.session.state["players"].size())
	await get_tree().create_timer(3.0).timeout
	if crash:
		_log("crash (알리지 않고 종료)")
		App.net.stop()
	else:
		_log("leave")
		await App.session.leave()


func _client() -> void:
	App.session.my_name = "참가자 " + role
	App.session.token = "b-" + role   # c1 이 c2 보다 앞 → 새 방장
	await get_tree().create_timer(0.6 if role == "c1" else 1.0).timeout
	App.session.join_room("127.0.0.1")
	var t := 0
	while App.session.state.is_empty() and t < 400:
		await get_tree().create_timer(0.05).timeout
		t += 1
	_log("in game: round=%s" % App.session.state.get("round"))
	App.session.reconnecting.connect(func(txt): if txt != "": _log("안내: " + txt))
	# 방장이 사라질 때까지 + 넘기기 끝날 때까지
	t = 0
	while t < 1200:
		await get_tree().create_timer(0.05).timeout
		t += 1
		if App.session.state.get("_host_pid", "") != "a-host" and not App.session._recovering and App.session.mode != "none":
			break
	_log("after: mode=%s host_pid=%s round=%s phase=%s" % [App.session.mode, App.session.state.get("_host_pid", ""), App.session.state.get("round"), App.session.state.get("phase")])
	# 넘긴 뒤에도 명령이 반영되는지 (새로고침 → 골드 감소)
	await get_tree().create_timer(1.5).timeout
	var g0: int = App.session.state["players"][App.session.my_pid]["gold"]
	App.session.submit({"t": "reroll"})
	await get_tree().create_timer(1.0).timeout
	var g1: int = App.session.state["players"][App.session.my_pid]["gold"]
	var others := []
	for pid in App.session.state["players"]:
		var p: Dictionary = App.session.state["players"][pid]
		others.append("%s:%s" % [p["name"], "연결" if p["connected"] else "끊김"])
	_log("reroll gold %d -> %d, players=%s" % [g0, g1, others])
	await get_tree().create_timer(2.0).timeout
	if App.session.mode == "host":
		await get_tree().create_timer(2.0).timeout
	App.session.leave()
