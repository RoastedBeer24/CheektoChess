class_name MotionSprite
extends Control
## 사도 전투 모션 재생 (assets/motions/<사도 id>/<Anim>.webp 시트 + meta.json).
## 모션 파일이 없으면 has_motion() 이 false — 화면은 기존 초상화 카드로 대신한다.
## 원본은 왼쪽을 봄: face_right = true 이면 좌우를 뒤집어 그린다.
## 발 위치(feet)가 이 컨트롤의 아래쪽 가운데에 오도록 그린다.

const DIR := "res://assets/motions/"

static var _meta_cache := {}     # aid -> meta (없으면 {})
static var _tex_cache := {}      # "aid/Anim" -> Texture2D

var aid := ""
var face_right := false
var box := 200.0                 # 시트 한 칸(512 원본 기준)을 화면에 그릴 크기
var speed := 1.0
var tint := Color.WHITE
var shadow := false              # 발밑 그림자
var _meta: Dictionary = {}
var _anim := ""
var _loop := true
var _then := "Idle"              # 한 번 재생 후 넘어갈 애니메이션
var _hold_last := false          # 끝 프레임에서 멈춤 (쓰러짐)
var _t := 0.0
var _frame := 0
var _loop_until := -1.0          # 반복 재생을 이 시간까지만 (기절 등)


static func meta_of(id: String) -> Dictionary:
	if _meta_cache.has(id):
		return _meta_cache[id]
	var m := {}
	var path := DIR + id + "/meta.json"
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(d) == TYPE_DICTIONARY:
			m = d
	_meta_cache[id] = m
	return m


static func available(id: String) -> bool:
	return not meta_of(id).is_empty()


static func _sheet(id: String, anim: String) -> Texture2D:
	var key := id + "/" + anim
	if _tex_cache.has(key):
		return _tex_cache[key]
	var tex: Texture2D = null
	var path := DIR + id + "/" + anim + ".webp"
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load_webp_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
			tex = ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


func _init(apostle_id: String = "") -> void:
	aid = apostle_id
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meta = meta_of(aid)
	if has_motion():
		play("Idle")


func has_motion() -> bool:
	return not _meta.is_empty() and _meta.get("anims", {}).has("Idle")


func has_anim(anim: String) -> bool:
	return _meta.get("anims", {}).has(anim)


## anim 재생. loop=false 면 끝나면 then 으로 (hold_last 면 마지막 프레임 유지)
const FALLBACK := {"Ultimate1_1": "Skill1_1", "Skill1_1": "Attack1_1", "Groggy": "Idle", "Move": "Idle"}


func play(anim: String, loop: bool = true, then: String = "Idle", hold_last: bool = false, loop_for: float = -1.0) -> void:
	# 없는 동작은 비슷한 동작으로 (예: 궁극기 없음 → 저학년 스킬)
	while not has_anim(anim) and FALLBACK.has(anim):
		anim = FALLBACK[anim]
	if not has_anim(anim):
		if anim != "Idle" and has_anim("Idle") and not hold_last:
			anim = "Idle"
			loop = true
		else:
			return
	_anim = anim
	_loop = loop
	_then = then
	_hold_last = hold_last
	_t = 0.0
	_frame = 0
	_loop_until = loop_for
	queue_redraw()


func current() -> String:
	return _anim


func _process(delta: float) -> void:
	if _anim == "":
		return
	var info: Dictionary = _meta["anims"][_anim]
	var n := int(info["n"])
	var fps := float(_meta.get("fps", 8.0)) * speed
	_t += delta
	if _loop_until > 0.0:
		_loop_until -= delta * speed
		if _loop_until <= 0.0:
			play(_then)
			return
	var f := int(_t * fps)
	if f >= n:
		if _loop:
			_t = fmod(_t, n / fps)
			f = int(_t * fps) % n
		elif _hold_last:
			f = n - 1
		else:
			play(_then)
			return
	if f != _frame:
		_frame = f
		queue_redraw()


func _draw() -> void:
	if _anim == "":
		return
	var tex := _sheet(aid, _anim)
	if tex == null:
		return
	var info: Dictionary = _meta["anims"][_anim]
	var cols := int(info["cols"])
	var cell := float(_meta.get("size", 192))
	var src := Rect2((_frame % cols) * cell, (_frame / cols) * cell, cell, cell)
	var feet := float(_meta.get("feet", 0.9))
	# 발이 컨트롤 아래쪽 가운데에 오도록
	var dst := Rect2(size.x / 2.0 - box / 2.0, size.y - box * feet, box, box)
	var flip := face_right != (String(_meta.get("facing", "left")) == "right")
	if flip:
		# 컨트롤 가운데를 기준으로 좌우 뒤집기
		draw_set_transform(Vector2(size.x, 0), 0.0, Vector2(-1, 1))
	if shadow:
		var c := Vector2(size.x / 2.0, size.y - 2.0)
		draw_set_transform(c, 0.0, Vector2(1.0, 0.28))
		draw_circle(Vector2.ZERO, box * 0.22, Color(0, 0, 0, 0.35 * tint.a))
		draw_set_transform(Vector2(size.x, 0) if flip else Vector2.ZERO, 0.0, Vector2(-1, 1) if flip else Vector2.ONE)
	draw_texture_rect_region(tex, dst, src, tint)
	if flip:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
