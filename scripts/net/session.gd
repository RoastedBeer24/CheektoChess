class_name SessionNode
extends Node
## 한 판의 세션. 방장(또는 오프라인)일 때 Match 를 직접 돌리고,
## 참가자일 때는 방장에게 명령을 보내고 상태를 받아 화면에 넘긴다.

signal lobby_changed
signal state_changed
signal toast(msg: String)
signal game_started
signal left(reason: String)
signal update_progress(text: String, ratio: float)   # 방장에게서 업데이트 받는 중
signal update_done

const MAX_PLAYERS := 8
const MIN_PLAYERS := 4
const PROFILE := "user://profile.cfg"

var mode := "none"          # none / offline / host / client
var my_name := "플레이어"
var token := ""             # 기기별 고유 id (재접속 확인용)
var my_pid := ""
var lobby: Array = []       # [{id, name, bot, connected}]
var group_id := ""          # 이번 판 그룹 (방장이 고름, 참가자에게 전달)
var state: Dictionary = {}  # 최신 게임 상태
var game: Match = null      # 방장만 가짐
var peer_to_pid := {}
var _dirty := false
var _timer_send := 0.0
var _bot_seq := 0
var _incoming := {}   # 방장에게서 받는 중인 묶음: 이름 -> {meta, data: PackedByteArray}
var _host_meta := {}
const CHUNK := 48 * 1024


func _ready() -> void:
	_load_profile()
	App.net.connected_to_host.connect(_on_connected)
	App.net.connection_failed.connect(func(): _leave_with("방에 연결하지 못했습니다."))
	App.net.host_lost.connect(func(): _leave_with("방장과의 연결이 끊어졌습니다."))
	App.net.peer_left.connect(_on_peer_left)


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


## 튜토리얼: 봇 3명과 혼자 하는 연습 판 (화면 안내는 Tutorial 이 맡음)
var tutorial := false


func start_tutorial() -> void:
	start_offline(3)
	tutorial = true
	if game == null:
		return
	# 연습 판: 준비 시간 멈춤, 합성 연습용 상점(같은 사도 3장), 장착 연습용 아티팩트
	game.tutorial = true
	game.phase_left = 99999.0
	var p: Dictionary = game.player(my_pid)
	p["gold"] = 12
	p["shop"] = ["rohne", "rohne", "rohne", "bana", "festa"]
	p["inv"].append({"uid": game._uid(), "id": "wooden_sword"})
	_flush()


func host_room() -> Error:
	_reset()
	var err := App.net.host("%s의 방" % my_name)
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
	return App.net.join(ip)


func leave() -> void:
	_leave_with("")


func _leave_with(reason: String) -> void:
	App.net.stop()
	_reset()
	left.emit(reason)


func _reset() -> void:
	tutorial = false
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


## (방장) 이번 판 그룹 고르기
func set_group(id: String) -> void:
	if not is_host() or in_game():
		return
	group_id = id
	GameData.set_group(id)
	_lobby_updated()


func _lobby_updated() -> void:
	if group_id == "":
		group_id = GameData.group_id
	App.net.room_info = {"players": lobby.size(), "max": MAX_PLAYERS, "started": in_game(), "group": GameData.group_name(group_id)}
	if mode == "host":
		_rpc_lobby.rpc(lobby, group_id)
	lobby_changed.emit()


func start_game() -> void:
	if not is_host():
		return
	if lobby.size() < MIN_PLAYERS:
		toast.emit("최소 %d명이 필요합니다. 봇을 추가하세요." % MIN_PLAYERS)
		return
	GameData.set_group(group_id if group_id != "" else GameData.group_id)
	game = Match.new(lobby, randi())
	game.state_changed.connect(func(): _dirty = true)
	game.start()
	state = game.state
	App.net.room_info["started"] = true
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
	_rpc_hello.rpc_id(1, token, my_name, App.build)


# ─────────────────────────────── 버전 맞추기 ───────────────────────────────
# LAN 대전은 모두 같은 콘텐츠여야 전투 결과가 일치한다.
# 참가자가 방장보다 낮은 빌드면 방장 기기의 묶음 파일을 직접 받는다.

## 방장이 보낼 수 있는 묶음 정보 (설치된 묶음 파일이 있을 때만)
func _host_packs() -> Dictionary:
	var inst := App.installed()
	if int(inst.get("build", 0)) != App.build:
		return {}
	for name in inst.get("packs", {}):
		if not FileAccess.file_exists(App.PACK_DIR + inst["packs"][name]["file"]):
			return {}
	return inst


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
func _rpc_hello(their_token: String, their_name: String, their_build: int = 0) -> void:
	if mode != "host":
		return
	var peer := multiplayer.get_remote_sender_id()
	# 버전 확인 (개발 실행(빌드 0)끼리는 검사하지 않음)
	if App.build != their_build and App.build > 0 and their_build > 0:
		if their_build > App.build:
			_rpc_reject.rpc_id(peer, "방장의 게임 버전이 더 낮습니다 (방장 %d, 나 %d). 방장이 인터넷에 연결해 업데이트하면 참가할 수 있습니다." % [App.build, their_build])
			return
		var packs := _host_packs()
		if packs.is_empty():
			_rpc_reject.rpc_id(peer, "게임 버전이 다릅니다 (방장 %d, 나 %d). 인터넷에 연결해 업데이트해 주세요." % [App.build, their_build])
			return
		_rpc_offer_update.rpc_id(peer, packs)
		return
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
		# 참가자 화면이 미리 바뀌었을 수 있으므로 올바른 상태를 다시 보낸다
		_rpc_state.rpc_id(peer, game.state)


@rpc("authority", "reliable")
func _rpc_welcome(pid: String) -> void:
	my_pid = pid


@rpc("authority", "reliable")
func _rpc_lobby(l: Array, gid: String = "") -> void:
	lobby = l
	if gid != "" and gid != GameData.group_id:
		GameData.set_group(gid)
	group_id = gid
	lobby_changed.emit()


@rpc("authority", "reliable")
func _rpc_game_started() -> void:
	game_started.emit()


@rpc("authority", "reliable")
func _rpc_state(s: Dictionary) -> void:
	if s.get("group", "") != "" and s["group"] != GameData.group_id:
		GameData.set_group(s["group"])
	state = s
	state_changed.emit()


@rpc("authority", "unreliable_ordered")
func _rpc_timer(t: float) -> void:
	if not state.is_empty():
		state["phase_end"] = t


@rpc("authority", "reliable")
func _rpc_toast(msg: String) -> void:
	toast.emit(msg)


## (참가자) 방장이 업데이트를 제안함 → 다른 묶음만 요청
@rpc("authority", "reliable")
func _rpc_offer_update(host_inst: Dictionary) -> void:
	_host_meta = host_inst
	_incoming.clear()
	var mine: Dictionary = App.installed().get("packs", {})
	var need := []
	for name in host_inst["packs"]:
		if mine.get(name, {}).get("sha256", "") != host_inst["packs"][name]["sha256"]:
			need.append(name)
			_incoming[name] = {"meta": host_inst["packs"][name], "data": PackedByteArray()}
	update_progress.emit("방장 기기에서 업데이트 받는 중...", 0.0)
	if need.is_empty():
		_finish_update()
		return
	_rpc_request_packs.rpc_id(1, need)


## (방장) 요청한 묶음 파일을 나눠서 보낸다
@rpc("any_peer", "reliable")
func _rpc_request_packs(names: Array) -> void:
	if mode != "host":
		return
	var peer := multiplayer.get_remote_sender_id()
	var inst := _host_packs()
	for name in names:
		if not inst.get("packs", {}).has(name):
			continue
		var bytes := FileAccess.get_file_as_bytes(App.PACK_DIR + inst["packs"][name]["file"])
		var off := 0
		while off < bytes.size():
			_rpc_pack_chunk.rpc_id(peer, name, off, bytes.slice(off, off + CHUNK), bytes.size())
			off += CHUNK
			await get_tree().process_frame


## (참가자) 조각 받기
@rpc("authority", "reliable")
func _rpc_pack_chunk(name: String, _offset: int, chunk: PackedByteArray, total: int) -> void:
	if not _incoming.has(name):
		return
	_incoming[name]["data"].append_array(chunk)
	var got := 0
	var all := 0
	for n in _incoming:
		got += _incoming[n]["data"].size()
		all += int(_incoming[n]["meta"]["size"])
	update_progress.emit("방장 기기에서 업데이트 받는 중... %.1f / %.1f MB" % [got / 1048576.0, all / 1048576.0], float(got) / maxf(1.0, all))
	if got >= all:
		_finish_update()


func _finish_update() -> void:
	DirAccess.make_dir_recursive_absolute(App.PACK_DIR)
	var packs: Dictionary = App.installed().get("packs", {}).duplicate(true)
	for name in _incoming:
		var meta: Dictionary = _incoming[name]["meta"]
		var path: String = App.PACK_DIR + meta["file"]
		var f := FileAccess.open(path + ".download", FileAccess.WRITE)
		f.store_buffer(_incoming[name]["data"])
		f.close()
		if FileAccess.get_sha256(path + ".download") != meta["sha256"]:
			_leave_with("업데이트 파일이 손상되었습니다. 다시 참가해 주세요.")
			return
		DirAccess.rename_absolute(path + ".download", path)
		packs[name] = meta
	App.save_installed({"build": int(_host_meta["build"]), "version": _host_meta.get("version", ""), "packs": packs})
	App.net.stop()
	update_done.emit()


@rpc("authority", "reliable")
func _rpc_reject(msg: String) -> void:
	_leave_with(msg)
