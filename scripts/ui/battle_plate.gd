class_name BattlePlate
extends Control
## 전투 중 사도 발밑 이름표: [★ 이름] + 체력(보호막) 막대 + 상태 표시. 모든 사도가 같은 모양·같은 위치.
## 사도 그림 위 레이어에 그려서 다른 사도에 가려지지 않는다.

const W := 128.0
const H := 36.0

var uname := ""
var star := 1
var mine := true
var hp := 1.0
var shield := 0.0
var status := ""          # 짧은 상태 이름 (기절·빙결 등), "" 이면 없음
var dead := false
var _name: Label
var _status: Label
var _status_bg: PanelContainer


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(W, H)


func _ready() -> void:
	var bg := Panel.new()
	bg.add_theme_stylebox_override("panel", UI.box(Color(0.04, 0.05, 0.09, 0.85), 8, Color(UI.GOOD if mine else UI.BAD, 0.9), 2))
	bg.position = Vector2.ZERO
	bg.size = Vector2(W, 22)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_name = UI.outlined(("★".repeat(star) + " " + uname) if star > 1 else uname, 16, UI.ACCENT if star >= 3 else Color.WHITE, 4)
	_name.position = Vector2(2, -1)
	_name.size = Vector2(W - 4, 24)
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name)
	_status_bg = PanelContainer.new()
	_status_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_bg.visible = false
	add_child(_status_bg)
	_status = UI.outlined("", 14, Color.WHITE, 4)
	_status_bg.add_child(_status)


func set_hp(ratio: float, shield_ratio: float) -> void:
	if absf(ratio - hp) < 0.001 and absf(shield_ratio - shield) < 0.001:
		return
	hp = clampf(ratio, 0.0, 1.0)
	shield = clampf(shield_ratio, 0.0, 1.0)
	queue_redraw()


func set_dead(on: bool) -> void:
	dead = on
	modulate.a = 0.4 if on else 1.0
	if on:
		set_status("")
	queue_redraw()


func set_status(text: String, color: Color = Color.WHITE) -> void:
	if text == status or _status_bg == null:
		return
	status = text
	_status_bg.visible = text != ""
	if text != "":
		_status.text = text
		var sb := UI.box(Color(color.darkened(0.35), 0.92), 6, color, 1)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		_status_bg.add_theme_stylebox_override("panel", sb)
		_status_bg.reset_size()
		_status_bg.position = Vector2(W / 2.0 - _status_bg.size.x / 2.0, -_status_bg.size.y - 2.0)


func _draw() -> void:
	# 체력 막대 (이름 띠 아래)
	var bar := Rect2(4, 25, W - 8, 9)
	draw_rect(bar.grow(1.5), Color(0, 0, 0, 0.9))
	draw_rect(bar, Color(0.2, 0.2, 0.24))
	var hc := (Color("57d68d") if mine else Color("ff6b6b")) if hp > 0.3 else Color("ffcc33")
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * hp, bar.size.y)), hc)
	if shield > 0.0:
		var sw := minf(bar.size.x * (1.0 - hp), bar.size.x * shield)
		var sx := bar.position.x + bar.size.x * hp
		if sw < 2.0:
			sx = bar.end.x - bar.size.x * shield
			sw = bar.size.x * shield
		draw_rect(Rect2(sx, bar.position.y, sw, bar.size.y), Color(0.85, 0.93, 1.0, 0.9))
