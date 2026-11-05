class_name NetNode
extends Node
## LAN 네트워크: 방 만들기(ENet 서버), 참가, 같은 와이파이 안의 방 자동 찾기(UDP 브로드캐스트).

signal rooms_changed(rooms: Array)
signal connected_to_host
signal connection_failed
signal host_lost
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

const GAME_PORT := 24680
const DISCOVERY_PORT := 24681
const MAGIC := "cheektochess-v1"
const MAX_CLIENTS := 7

var room_name := ""
var room_info := {}               # 브로드캐스트에 실을 정보 (인원 등)
var rooms := {}                   # "ip:port" -> {ip, port, name, players, started, seen}
var _bcast: PacketPeerUDP
var _listen: PacketPeerUDP
var _bcast_timer := 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(func(id): peer_joined.emit(id))
	multiplayer.peer_disconnected.connect(func(id): peer_left.emit(id))
	multiplayer.connected_to_server.connect(func(): connected_to_host.emit())
	multiplayer.connection_failed.connect(func():
		_reset_peer()
		connection_failed.emit())
	multiplayer.server_disconnected.connect(func():
		_reset_peer()
		host_lost.emit())


func is_online() -> bool:
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


func is_host() -> bool:
	return not is_online() or multiplayer.is_server()


func host(name: String) -> Error:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT, MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	room_name = name
	_bcast = PacketPeerUDP.new()
	_bcast.set_broadcast_enabled(true)
	_bcast.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	return OK


func join(ip: String, port: int = GAME_PORT) -> Error:
	stop_discovery()
	_reset_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func stop() -> void:
	_reset_peer()
	if _bcast:
		_bcast.close()
		_bcast = null
	stop_discovery()


func _reset_peer() -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func start_discovery() -> void:
	stop_discovery()
	rooms.clear()
	_listen = PacketPeerUDP.new()
	var err := _listen.bind(DISCOVERY_PORT)
	if err != OK:
		push_warning("방 찾기 포트를 열 수 없음: %d" % err)
		_listen = null


func stop_discovery() -> void:
	if _listen:
		_listen.close()
		_listen = null


## 이 기기의 LAN IP 목록 (방장 화면에 표시)
func local_ips() -> Array:
	var out := []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			out.append(ip)
	return out


func _process(delta: float) -> void:
	if _bcast and is_online() and multiplayer.is_server():
		_bcast_timer -= delta
		if _bcast_timer <= 0.0:
			_bcast_timer = 1.0
			var msg := room_info.duplicate()
			msg["magic"] = MAGIC
			msg["name"] = room_name
			msg["port"] = GAME_PORT
			_bcast.put_packet(JSON.stringify(msg).to_utf8_buffer())
	if _listen:
		var changed := false
		while _listen.get_available_packet_count() > 0:
			var pkt := _listen.get_packet()
			var ip := _listen.get_packet_ip()
			var data = JSON.parse_string(pkt.get_string_from_utf8())
			if typeof(data) != TYPE_DICTIONARY or data.get("magic", "") != MAGIC:
				continue
			var key := "%s:%d" % [ip, int(data.get("port", GAME_PORT))]
			data["ip"] = ip
			data["seen"] = Time.get_ticks_msec()
			rooms[key] = data
			changed = true
		# 3초 넘게 신호가 없는 방은 목록에서 뺀다
		for key in rooms.keys():
			if Time.get_ticks_msec() - int(rooms[key]["seen"]) > 3000:
				rooms.erase(key)
				changed = true
		if changed:
			rooms_changed.emit(rooms.values())


# ─────────────────────────────── 방 코드 (IP 를 숫자로) ───────────────────────────────
## 사설 IP 를 짧은 숫자로: 192.168.a.b → 1xxxxx (6자리), 172.16~31.a.b → 2xxxxxxx, 10.a.b.c → 3xxxxxxxx
static func room_code(ip: String) -> String:
	var o := ip.split(".")
	if o.size() != 4:
		return ""
	var n := [int(o[0]), int(o[1]), int(o[2]), int(o[3])]
	if n[0] == 192 and n[1] == 168:
		return "1%05d" % (n[2] * 256 + n[3])
	if n[0] == 172 and n[1] >= 16 and n[1] <= 31:
		return "2%07d" % ((n[1] - 16) * 65536 + n[2] * 256 + n[3])
	if n[0] == 10:
		return "3%08d" % (n[1] * 65536 + n[2] * 256 + n[3])
	return ""


## 방 코드 또는 IP → IP ("" 이면 알 수 없음). 띄어쓰기·하이픈은 무시
static func code_to_ip(text: String) -> String:
	var t := text.strip_edges().replace(" ", "").replace("-", "")
	if t.count(".") == 3:
		return t
	if not t.is_valid_int() or t.length() < 6:
		return ""
	var kind := t.substr(0, 1)
	var v := int(t.substr(1))
	if kind == "1" and t.length() == 6 and v < 65536:
		return "192.168.%d.%d" % [v / 256, v % 256]
	if kind == "2" and t.length() == 8 and v < 16 * 65536:
		return "172.%d.%d.%d" % [16 + v / 65536, (v / 256) % 256, v % 256]
	if kind == "3" and t.length() == 9 and v < 16777216:
		return "10.%d.%d.%d" % [v / 65536, (v / 256) % 256, v % 256]
	return ""


## 보기 좋게: 1-23456 / 2-1234-567 ...
static func pretty_code(c: String) -> String:
	if c.length() <= 6:
		return c.substr(0, 1) + "-" + c.substr(1)
	return c.substr(0, 1) + "-" + c.substr(1, 4) + "-" + c.substr(5)
