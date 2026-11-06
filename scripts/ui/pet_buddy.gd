class_name PetBuddy
extends Control
## 내 펫: 보드 옆에 서서 이따금 돌아다니고, 승리·패배·★3·레벨업에 반응한다. 누르면 논다.
## 모션이 없으면(펫 묶음을 아직 안 받음) 초상화로.

var pet_id := ""
var _sp: MotionSprite
var _tex: TextureRect
var _idle_t := 6.0
var _walk_to := -1.0
var _x := 0.0


func _init(id: String = "", sz: Vector2 = Vector2(120, 120)) -> void:
	pet_id = id
	custom_minimum_size = sz
	size = sz
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = GameData.pet(id).get("name", "")


func _ready() -> void:
	if MotionSprite.available(pet_id):
		_sp = MotionSprite.new(pet_id)
		_sp.shadow = true
		_sp.face_right = true
		add_child(_sp)
	else:
		_tex = UI.tex_rect(UI.portrait(pet_id), size * 0.8, true)
		_tex.position = size * 0.1
		add_child(_tex)
	resized.connect(_fit)
	_fit()


func _fit() -> void:
	if _sp:
		_sp.size = size
		_sp.box = size.y / 0.82
		_sp.position.x = _x


## 반응: win / lose / star3 / levelup / buy / tap
func react(kind: String) -> void:
	if _sp == null:
		_bounce()
		return
	var anim: String = {"win": "Play", "lose": "Angry", "star3": "Play", "levelup": "Play", "buy": "Play", "tap": "Play"}.get(kind, "Play")
	if not _sp.has_anim(anim):
		anim = "Play" if _sp.has_anim("Play") else "Idle"
	_sp.play(anim, false, "Idle")
	_walk_to = -1.0
	_idle_t = 7.0
	_bounce()


func _bounce() -> void:
	pivot_offset = Vector2(size.x / 2.0, size.y)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.1, 0.92), 0.08)
	tw.tween_property(self, "scale", Vector2(0.95, 1.08), 0.1)
	tw.tween_property(self, "scale", Vector2.ONE, 0.12)


func _gui_input(ev: InputEvent) -> void:
	if (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and ev.pressed):
		react("tap")
		accept_event()


func _process(delta: float) -> void:
	if _sp == null or not is_visible_in_tree():
		return
	# 가끔 좌우로 조금 걷거나, 먹거나, 졸기
	if _walk_to >= 0.0:
		var d := _walk_to - _x
		if absf(d) < 1.5:
			_walk_to = -1.0
			_sp.play("Idle")
		else:
			_x += signf(d) * minf(absf(d), 38.0 * delta)
			_sp.face_right = d > 0.0
			_sp.position.x = _x
		return
	_idle_t -= delta
	if _idle_t > 0.0:
		return
	_idle_t = randf_range(6.0, 14.0)
	var r := randf()
	if r < 0.5 and _sp.has_anim("Move"):
		_walk_to = clampf(_x + randf_range(-40.0, 40.0), -30.0, 30.0)
		_sp.play("Move")
	elif r < 0.7 and _sp.has_anim("Eat"):
		_sp.play("Eat", false, "Idle")
	elif r < 0.85 and _sp.has_anim("Sleep"):
		_sp.play("Sleep", true, "Idle", false, 4.0)
	elif _sp.has_anim("Act"):
		_sp.play("Act", false, "Idle")
