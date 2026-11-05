class_name Voice
extends Node
## 사도 보이스 재생 (assets/voices/<id>/<동작>_<n>.ogg). 동작과 확실히 연결된 대사만.
## 겹침 방지: 동시에 2개까지, 같은 사도는 1.5초 안에 다시 말하지 않음, 우선순위 높은 대사가 낮은 것을 끊음.

const DIR := "res://assets/voices/"
## 동작 → 우선순위 (높을수록 중요)
const PRIORITY := {"Ultimate": 5, "Victory": 4, "Defeat": 4, "Die": 3, "SPSkill": 2, "Spawn": 1, "PowerAttack": 0, "Hit": 0}

static var inst: Voice
static var _meta_cache := {}
static var _stream_cache := {}

var _players: Array = []
var _last_by_unit := {}


func _init() -> void:
	inst = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.set_meta("prio", -1)
		add_child(p)
		_players.append(p)


static func meta_of(aid: String) -> Dictionary:
	if _meta_cache.has(aid):
		return _meta_cache[aid]
	var m := {}
	var path := DIR + aid + "/meta.json"
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(d) == TYPE_DICTIONARY:
			m = d
	_meta_cache[aid] = m
	return m


static func _stream(path: String) -> AudioStream:
	if _stream_cache.has(path):
		return _stream_cache[path]
	var s: AudioStream = null
	if FileAccess.file_exists(path):
		s = AudioStreamOggVorbis.load_from_file(path)
	_stream_cache[path] = s
	return s


## 사도 aid 의 cat 동작 대사 하나 (무작위). unit_key: 같은 유닛이 연달아 말하지 않게
static func say(aid: String, cat: String, unit_key = null) -> void:
	if inst == null:
		return
	var vol := Settings.num("vol_master") * Settings.num("vol_voice")
	if vol <= 0.01:
		return
	var n := int(meta_of(aid).get(cat, 0))
	if n <= 0:
		return
	inst._play(aid, cat, n, unit_key if unit_key != null else aid, vol)


func _play(aid: String, cat: String, n: int, key, vol: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_by_unit.get(key, -9.0)) < 1.5:
		return
	var prio: int = PRIORITY.get(cat, 0)
	var target: AudioStreamPlayer = null
	for p in _players:
		if not p.playing:
			target = p
			break
	if target == null:
		# 모두 재생 중이면 우선순위가 가장 낮은 것을 끊는다 (더 낮을 때만)
		var low: AudioStreamPlayer = _players[0]
		for p in _players:
			if int(p.get_meta("prio")) < int(low.get_meta("prio")):
				low = p
		if int(low.get_meta("prio")) >= prio:
			return
		target = low
	var s := _stream(DIR + "%s/%s_%d.ogg" % [aid, cat, randi() % n + 1])
	if s == null:
		return
	_last_by_unit[key] = now
	target.stream = s
	target.volume_db = linear_to_db(clampf(vol, 0.0, 1.0))
	target.set_meta("prio", prio)
	target.play()
