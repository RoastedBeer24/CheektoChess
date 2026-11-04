extends Node
## 한 판의 세션. 방장(또는 오프라인)일 때 Match 를 직접 돌리고,
## 참가자일 때는 방장에게 명령을 보내고 상태를 받아 화면에 넘긴다.

signal lobby_changed
signal state_changed
signal toast(msg: String)
signal game_started
signal left(reason: String)

const MAX_PLAYERS := 8
const MIN_PLAYERS := 4
const PROFILE := "user://profile.cfg"

var mode := "none"          # none / offline / host / client
var my_name := "플레이어"
var token := ""             # 기기별 고유 id (재접속 확인용)
var my_pid := ""
var lobby: Array = []       # [{id, name, bot, connected}]
var state: Dictionary = {}  # 최신 게임 상태
var game: Match = null      # 방장만 가짐
var peer_to_pid := {}
var _dirty := false
var _timer_send := 0.0
var _bot_seq := 0


func _ready() -> void:
	_load_profile()
	Net.connected_to_host.connect(_on_connected)
	Net.connection_failed.connect(func(): _leave_with("방에 연결하지 못했습니다."))
	Net.host_lost.connect(func(): _leave_with("방장과의 연결이 끊어졌습니다."))
	Net.peer_left.connect(_on_peer_left)


func _load_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PROFILE)
	my_name = cfg.get_value("player", "name", "플레이어%d" % (randi() % 1000))
	token = cfg.get_value("player", "token", "")
	if token == "":
		token = "%x%x" % [randi(), Time.get_ticks_usec()]
	save_profile()


func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", my_name)
	cfg.set_value("player", "token", token)
	cfg.save(PROFILE)


func is_host() -> bool:
	return mode == "offline" or mode == "host"


func in_game() -> bool:
	return not state.is_empty()


# ─────────────────────────────── 시작 / 종료 ───────────────────────────────

func start_offline(bots: int) -> void:
	_reset()
	mode = "offline"
	my_pid = token
	lobby = [{"id": my_pid, "name": my_name, "bot": false, "connected": true}]
	for i in bots:
		add_bot()
	start_game()


func host_room() -> Error:
	_reset()
	var err := Net.host("%s의 방" % my_name)
	if err != OK:
		return err
	mode = "host"
	my_pid = token
	lobby = [{"id": my_pid, "name": my_name, "bot": false, "connected": true}]
	_lobby_updated()
	return OK


func join_room(ip: String) -> Error:
	_reset()
	mode = "client"
	my_pid = token
	return Net.join(ip)


func leave() -> void:
	_leave_with("")


func _leave_with(reason: String) -> void:
	Net.stop()
	_reset()
	left.emit(reason)


func _reset() -> void:
	mode = "none"
	lobby = []
	state = {}
	game = null
	peer_to_pid.clear()


# ─────────────────────────────── 대기실 ───────────────────────────────

func add_bot() -> void:
	if not is_host() or lobby.size() >= MAX_PLAYERS or in_game():
		return
	_bot_seq += 1
	lobby.append({"id": "bot%d" % _bot_seq, "name": "봇 %d" % _bot_seq, "bot": true, "connected": true})
	_lobby_updated()


func remove_bot() -> void:
	if not is_host() or in_game():
		return
	for i in range(lobby.size() - 1, -1, -1):
		if lobby[i]["bot"]:
			lobby.remove_at(i)
			break
	_lobby_updated()


func can_start() -> bool:
	return is_host() and lobby.size() >= MIN_PLAYERS and lobby.size() <= MAX_PLAYERS


func _lobby_updated() -> void:
	Net.room_info = {"players": lobby.size(), "max": MAX_PLAYERS, "started": in_game()}
	if mode == "host":
		_rpc_lobby.rpc(lobby)
	lobby_changed.emit()


func start_game() -> void:
	if not is_host():
		return
	if lobby.size() < MIN_PLAYERS:
		toast.emit("최소 %d명이 필요합니다. 봇을 추가하세요." % MIN_PLAYERS)
		return
	game = Match.new(lobby, randi())
	game.state_changed.connect(func(): _dirty = true)
	game.start()
	state = game.state
	Net.room_info["started"] = true
	if mode == "host":
		_rpc_game_started.rpc()
	game_started.emit()
	_flush()


# ─────────────────────────────── 명령 / 동기화 ───────────────────────────────

func submit(cmd: Dictionary) -> void:
	if is_host():
		if game == null:
			return
		var err := game.command(my_pid, cmd)
		if err != "":
			toast.emit(err)
	elif mode == "client":
		_rpc_cmd.rpc_id(1, cmd)


func _process(delta: float) -> void:
	if not is_host() or game == null:
		return
	game.advance(delta)
	if _dirty:
		_flush()
	elif mode == "host":
		_timer_send -= delta
		if _timer_send <= 0.0:
			_timer_send = 0.5
			_rpc_timer.rpc(game.state["phase_end"])


func _flush() -> void:
	_dirty = false
	state = game.state
	if mode == "host":
		_rpc_state.rpc(state)
	state_changed.emit()


func _on_connected() -> void:
	_rpc_hello.rpc_id(1, token, my_name)


func _on_peer_left(peer_id: int) -> void:
	if mode != "host" or not peer_to_pid.has(peer_id):
		return
	var pid: String = peer_to_pid[peer_id]
	peer_to_pid.erase(peer_id)
	if game != null:
		game.set_connected(pid, false)
	else:
		for i in lobby.size():
			if lobby[i]["id"] == pid:
				lobby.remove_at(i)
				break
		_lobby_updated()


# ─────────────────────────────── RPC ───────────────────────────────

@rpc("any_peer", "reliable")
func _rpc_hello(their_token: String, their_name: String) -> void:
	if mode != "host":
		return
	var peer := multiplayer.get_remote_sender_id()
	if game != null:
		if game.can_rejoin(their_token):
			peer_to_pid[peer] = their_token
			game.set_connected(their_token, true)
			_rpc_welcome.rpc_id(peer, their_token)
			_rpc_game_started.rpc_id(peer)
			_rpc_state.rpc_id(peer, game.state)
		else:
			_rpc_reject.rpc_id(peer, "이미 게임이 진행 중이거나, 재접속 가능한 라운드가 지났습니다.")
		return
	if lobby.size() >= MAX_PLAYERS:
		_rpc_reject.rpc_id(peer, "방이 가득 찼습니다.")
		return
	for p in lobby:
		if p["id"] == their_token:
			_rpc_reject.rpc_id(peer, "같은 기기가 이미 참가 중입니다.")
			return
	peer_to_pid[peer] = their_token
	lobby.append({"id": their_token, "name": their_name, "bot": false, "connected": true})
	_rpc_welcome.rpc_id(peer, their_token)
	_lobby_updated()


@rpc("any_peer", "reliable")
func _rpc_cmd(cmd: Dictionary) -> void:
	if mode != "host" or game == null:
		return
	var peer := multiplayer.get_remote_sender_id()
	if not peer_to_pid.has(peer):
		return
	var err := game.command(peer_to_pid[peer], cmd)
	if err != "":
		_rpc_toast.rpc_id(peer, err)


@rpc("authority", "reliable")
func _rpc_welcome(pid: String) -> void:
	my_pid = pid


@rpc("authority", "reliable")
func _rpc_lobby(l: Array) -> void:
	lobby = l
	lobby_changed.emit()


@rpc("authority", "reliable")
func _rpc_game_started() -> void:
	game_started.emit()


@rpc("authority", "reliable")
func _rpc_state(s: Dictionary) -> void:
	state = s
	state_changed.emit()


@rpc("authority", "unreliable_ordered")
func _rpc_timer(t: float) -> void:
	if not state.is_empty():
		state["phase_end"] = t


@rpc("authority", "reliable")
func _rpc_toast(msg: String) -> void:
	toast.emit(msg)


@rpc("authority", "reliable")
func _rpc_reject(msg: String) -> void:
	_leave_with(msg)
