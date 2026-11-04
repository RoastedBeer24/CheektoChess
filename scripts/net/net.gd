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
