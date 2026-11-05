class_name Settings
extends RefCounted
## 사용자 설정 (user://settings.json). 기기마다 따로 저장된다.

const PATH := "user://settings.json"
const DEFAULTS := {
	"vol_master": 0.8,      # 0~1
	"vol_voice": 0.9,
	"vol_sfx": 0.8,
	"battle_speed": 1.0,    # 전투 기본 배속 (1, 2)
	"vibrate": true,
	"board_motion": true,   # 준비 단계 보드에서 사도 모션
	"battle_motion": true,  # 전투 모션 (끄면 초상화 카드)
	"effects": true,        # 전투 이펙트 (탄환·타격·화면 흔들림)
	"screen_shake": true,
	"text_scale": 1.0,      # 1.0 / 1.15 / 1.3
	"colorblind": false,    # 색약 모드: 좋음/위험 색을 파랑/주황으로
	"tutorial_done": false,
	"rules": {},            # 방 규칙 (방장·혼자 하기): {fast, augments, hp, gold, prep}
}

static var _data: Dictionary = {}
static var _loaded := false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_data = DEFAULTS.duplicate(true)
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if typeof(d) == TYPE_DICTIONARY:
			for k in d:
				if DEFAULTS.has(k):
					_data[k] = d[k]


static func get_value(key: String):
	_ensure()
	return _data.get(key, DEFAULTS.get(key))


static func set_value(key: String, value) -> void:
	_ensure()
	_data[key] = value
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_data, " "))


static func flag(key: String) -> bool:
	return bool(get_value(key))


static func num(key: String) -> float:
	return float(get_value(key))
