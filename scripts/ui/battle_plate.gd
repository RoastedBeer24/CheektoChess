class_name BattlePlate
extends Control
## 전투 중 사도 발밑 이름표: [★ 이름] + 체력(보호막) 막대 + SP 막대 + 상태 표시. 모든 사도가 같은 모양·같은 위치.
## 사도 그림 '뒤' 레이어에 그려서 사도를 가리지 않는다 (앞줄 사도가 뒷줄 이름표를 덮는 건 괜찮다).
## 쓰러지면 잠깐 흐려진 뒤 사라진다.

const W := 116.0
const H := 32.0
const BAND := 19.0

var uname := ""
var star := 1
var mine := true
var hp := 1.0
var shield := 0.0
var sp := 0.0            # 0~1 (저학년 스킬 게이지)
var show_sp := true
var status := ""          # 짧은 상태 이름 (기절·빙결 등), "" 이면 없음
var dead := false
var _name: Label
var _status: Label
var _status_bg: PanelContainer
var _skill_bg: PanelContainer
var _skill_lbl: Label
var _skill_tw: Tween
var _dead_tw: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(W, H)


func _ready() -> void:
	var bg := Panel.new()
	bg.add_theme_stylebox_override("panel", UI.box(Color(0.04, 0.05, 0.09, 0.7), 7, Color(UI.GOOD if mine else UI.BAD, 0.85), 2))
	bg.position = Vector2.ZERO
	bg.size = Vector2(W, BAND)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_name = UI.outlined(("★".repeat(star) + " " + uname) if star > 1 else uname, 14, UI.ACCENT if star >= 3 else Color.WHITE, 4)
	_name.position = Vector2(2, -1)
	_name.size = Vector2(W - 4, BAND + 2)
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name)
	_status_bg = PanelContainer.new()
	_status_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_bg.visible = false
	add_child(_status_bg)
	_status = UI.outlined("", 13, Color.WHITE, 4)
	_status_bg.add_child(_status)
	_skill_bg = PanelContainer.new()
	_skill_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_bg.visible = false
	add_child(_skill_bg)
	_skill_lbl = UI.outlined("", 14, Color.WHITE, 4)
	_skill_bg.add_child(_skill_lbl)


func set_hp(ratio: float, shield_ratio: float) -> void:
	if absf(ratio - hp) < 0.001 and absf(shield_ratio - shield) < 0.001:
		return
	hp = clampf(ratio, 0.0, 1.0)
	shield = clampf(shield_ratio, 0.0, 1.0)
	queue_redraw()


func set_sp(ratio: float) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	if absf(ratio - sp) < 0.001:
		return
	sp = ratio
	queue_redraw()


func set_dead(on: bool) -> void:
	dead = on
	if _dead_tw:
		_dead_tw.kill()
		_dead_tw = null
	if on:
		set_status("")
		if _skill_bg:
			_skill_bg.visible = false
		if is_inside_tree():
			_dead_tw = create_tween()
			_dead_tw.tween_property(self, "modulate:a", 0.0, 0.3)
			_dead_tw.tween_callback(func(): visible = false)
		else:
			visible = false
	else:
		visible = true
		modulate.a = 1.0
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
		_status_bg.position = Vector2(W / 2.0 - _status_bg.size.x / 2.0, H + 1.0)


## 스킬 이름 표시: 이름표 바로 아래 작은 띠로 잠깐 (머리 위 말풍선 대신 — 사도 그림을 가리지 않게)
func flash_skill(text: String, color: Color, dur: float) -> void:
	if _skill_bg == null or dead:
		return
	_skill_lbl.text = text
	_skill_lbl.add_theme_color_override("font_color", color.lightened(0.35))
	var sb := UI.box(Color(0.05, 0.06, 0.1, 0.9), 6, color, 1)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	_skill_bg.add_theme_stylebox_override("panel", sb)
	_skill_bg.visible = true
	_skill_bg.reset_size()
	var y := H + 1.0
	if _status_bg.visible:
		y += _status_bg.size.y + 1.0
	_skill_bg.position = Vector2(W / 2.0 - _skill_bg.size.x / 2.0, y)
	if _skill_tw:
		_skill_tw.kill()
	_skill_bg.modulate.a = 1.0
	_skill_tw = create_tween()
	_skill_tw.tween_interval(dur)
	_skill_tw.tween_property(_skill_bg, "modulate:a", 0.0, 0.25)
	_skill_tw.tween_callback(func(): _skill_bg.visible = false)


func _process(_d: float) -> void:
	if sp >= 0.999 and not dead:
		queue_redraw()


func _draw() -> void:
	if dead:
		return
	# 체력 막대 (이름 띠 아래)
	var bar := Rect2(4, BAND + 2.0, W - 8, 6)
	draw_rect(bar.grow(1.5), Color(0, 0, 0, 0.85))
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
	# SP 막대 (체력 막대 바로 아래): 가득 차면 반짝임 = 곧 스킬
	if show_sp:
		var sb := Rect2(4, bar.end.y + 1.5, W - 8, 3.5)
		draw_rect(sb.grow(1.0), Color(0, 0, 0, 0.85))
		draw_rect(sb, Color(0.14, 0.15, 0.22))
		var c := Color("5ec8ff")
		if sp >= 0.999:
			var k := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 90.0)
			c = Color("5ec8ff").lerp(Color.WHITE, k)
		draw_rect(Rect2(sb.position, Vector2(sb.size.x * sp, sb.size.y)), c)
