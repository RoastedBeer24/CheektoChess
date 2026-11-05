class_name Sfx
extends Node
## 효과음 재생 (assets/sfx/<이름>.ogg, tools/make_sfx.py 로 만든 소리). 음량 = 전체 × 효과음.
## 같은 소리는 짧은 간격 안에 겹쳐 울리지 않게 하고(전투 타격 등), 동시에 최대 8개.

const DIR := "res://assets/sfx/"
const MIN_GAP := {"hit": 0.06, "hit_magic": 0.06, "crit": 0.1, "death": 0.12, "tick": 0.5, "click": 0.05}

static var inst: Sfx
static var _cache := {}
var _players: Array = []
var _last := {}


func _init() -> void:
	inst = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


static func _stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var path := DIR + name + ".ogg"
	var s: AudioStream = AudioStreamOggVorbis.load_from_file(path) if FileAccess.file_exists(path) else null
	_cache[name] = s
	return s


## vol: 이 소리의 상대 음량(0~1), pitch_var: 음 높이를 조금씩 바꿔 반복이 덜 거슬리게
static func play(name: String, vol: float = 1.0, pitch_var: float = 0.04) -> void:
	if inst == null:
		return
	var v := Settings.num("vol_master") * Settings.num("vol_sfx") * vol
	if v <= 0.01:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(inst._last.get(name, -9.0)) < float(MIN_GAP.get(name, 0.03)):
		return
	var s := _stream(name)
	if s == null:
		return
	inst._last[name] = now
	var target: AudioStreamPlayer = null
	for p in inst._players:
		if not p.playing:
			target = p
			break
	if target == null:
		target = inst._players[0]
		inst._players.push_back(inst._players.pop_front())
	target.stream = s
	target.volume_db = linear_to_db(clampf(v, 0.0, 1.0))
	target.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	target.play()
