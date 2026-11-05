class_name Tips
extends CanvasLayer
## 게임 전체 공통 툴팁 (색 글씨·굵게 지원).
##   PC: 마우스를 잠시 올리면 표시.  모바일: 꾹 누르면 표시(손을 떼면 잠시 뒤 사라짐, 버튼은 눌리지 않음).
## 사용: Tips.set_tip(컨트롤, "BBCode 글" 또는 Callable) — 기본 tooltip_text 대신.
## 설명 글 속 밑줄 용어(Glossary)는 올리거나 누르면 용어 설명.

const HOVER_DELAY := 0.35
const HOLD_MS := 350
const MOVE_CANCEL := 14.0

static var inst: Tips
static var _TAG_RE := RegEx.create_from_string("\\[[^\\]]*\\]")

var _panel: PanelContainer
var _text: RichTextLabel
var _touch := false
var _hover_ctrl: Control
var _hover_t := 0.0
var _shown_for: Object
var _hide_t := -1.0
var _press_pos := Vector2.ZERO
var _press_ms := -1
var _press_ctrl: Control
var _held_shown := false
var _need_move := false   # 창이 열린 직후 등: 마우스가 움직일 때까지 마우스 올리기 툴팁을 띄우지 않음


static func set_tip(c: Control, tip) -> void:
	c.set_meta("tip", tip)
	c.tooltip_text = ""


func _init() -> void:
	inst = self
	layer = 120
	_touch = OS.has_feature("mobile")
	_panel = PanelContainer.new()
	var sb := UI.box(Color("0e1020", 0.97), 10, UI.ACCENT.darkened(0.25), 2)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 8
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_size_override("normal_font_size", 20)
	_text.add_theme_font_size_override("bold_font_size", 22)
	_text.add_theme_color_override("default_color", UI.TEXT)
	_text.add_theme_constant_override("line_separation", 4)
	_panel.add_child(_text)


## 지정한 글을 위치 근처에 표시 (owner: 같은 대상이면 다시 그리지 않음)
func show_tip(bb: String, at: Vector2, owner: Object = null) -> void:
	if bb == "":
		hide_tip()
		return
	_shown_for = owner
	_text.text = bb
	# 태그를 뺀 가장 긴 줄 길이로 너비 결정 (한글 한 글자 ≈ 20px)
	var plain := _TAG_RE.sub(bb, "", true)
	var longest := 0
	for line in plain.split("\n"):
		longest = maxi(longest, line.length())
	var w := clampf(float(longest) * 19.0 + 8.0, 200.0, 560.0)
	_text.custom_minimum_size = Vector2(w, 0)
	_panel.reset_size()
	_panel.visible = true
	(func(): _place(at)).call_deferred()
	_hide_t = -1.0


func _place(at: Vector2) -> void:
	_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	var sz := _panel.size
	var pos := at + Vector2(18, 22)
	if _touch:
		pos = at + Vector2(-sz.x / 2.0, -sz.y - 70)   # 손가락에 가리지 않게 위쪽
		if pos.y < 8:
			pos.y = at.y + 60
	if pos.x + sz.x > vp.x - 8:
		pos.x = at.x - sz.x - 18 if not _touch else vp.x - sz.x - 8
	if pos.y + sz.y > vp.y - 8:
		pos.y = vp.y - sz.y - 8
	_panel.position = Vector2(maxf(8, pos.x), maxf(8, pos.y))


func hide_tip() -> void:
	_panel.visible = false
	_shown_for = null


## 창(도감·팝업)을 열 때: 지금 툴팁을 닫고, 마우스가 움직이기 전까지 다시 띄우지 않음
func dismiss() -> void:
	hide_tip()
	_need_move = true


## 용어 설명 (설명 글의 밑줄 단어)
func show_term(term: String, at: Vector2) -> void:
	show_tip(Glossary.describe(term), at, null)
	if _touch:
		_hide_t = 3.0


static func _tip_of(c: Control) -> Variant:
	var n: Node = c
	var depth := 0
	while n != null and depth < 6:
		if n is Control and n.has_meta("tip"):
			return n
		n = n.get_parent()
		depth += 1
	return null


static func _resolve(holder: Control) -> String:
	var t = holder.get_meta("tip")
	if t is Callable:
		return String(t.call()) if t.is_valid() else ""
	return String(t)


func _process(delta: float) -> void:
	if _hide_t > 0.0:
		_hide_t -= delta
		if _hide_t <= 0.0:
			hide_tip()
	if _touch:
		_process_touch()
		return
	# PC: 마우스 올리기
	var vp := get_viewport()
	var hov := vp.gui_get_hovered_control()
	var holder = _tip_of(hov) if hov != null else null
	if holder != _hover_ctrl:
		_hover_ctrl = holder
		_hover_t = 0.0
		if _shown_for != null and _shown_for != holder:
			hide_tip()
	if holder == null or not holder.is_visible_in_tree() or _need_move:
		return
	_hover_t += delta
	if _hover_t >= HOVER_DELAY and _shown_for != holder:
		show_tip(_resolve(holder), vp.get_mouse_position(), holder)
	elif _panel.visible and _shown_for == holder:
		_place(vp.get_mouse_position())


func _process_touch() -> void:
	if _press_ms < 0 or _held_shown or _press_ctrl == null:
		return
	if Time.get_ticks_msec() - _press_ms >= HOLD_MS and is_instance_valid(_press_ctrl):
		_held_shown = true
		show_tip(_resolve(_press_ctrl), _press_pos, _press_ctrl)
		DragScroll.cancel_press(get_viewport())   # 손을 떼도 버튼이 눌리지 않게


func _input(event: InputEvent) -> void:
	if DragScroll._injecting:
		return
	if event is InputEventMouseMotion:
		_need_move = false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not _touch:
				hide_tip()
				_hover_t = -9999.0   # 누른 뒤에는 다시 올릴 때까지 표시 안 함
				return
			hide_tip()
			_press_pos = event.position
			_press_ms = Time.get_ticks_msec()
			_held_shown = false
			_press_ctrl = null
			var hit := _hit(event.position)
			if hit != null and not _is_unit_tile(hit):
				_press_ctrl = _tip_of(hit)
		else:
			if _held_shown:
				_hide_t = 1.2
			_press_ms = -1
			_press_ctrl = null
	elif event is InputEventMouseMotion and _press_ms >= 0 and not _held_shown:
		if event.position.distance_to(_press_pos) > MOVE_CANCEL or DragScroll.scrolling:
			_press_ms = -1


## 화면 좌표 아래의 컨트롤 (모바일은 누르는 순간 hover 가 갱신되지 않을 수 있어 직접 찾음)
func _hit(pos: Vector2) -> Control:
	var hov := get_viewport().gui_get_hovered_control()
	if hov != null and hov.get_global_rect().has_point(pos):
		return hov
	return _find_at(get_tree().root, pos)


func _find_at(n: Node, pos: Vector2) -> Control:
	var kids := n.get_children()
	for i in range(kids.size() - 1, -1, -1):
		var k = kids[i]
		if k is CanvasLayer:
			continue
		if k is Control and not k.visible:
			continue
		var r := _find_at(k, pos)
		if r != null:
			return r
	if n is Control and n.mouse_filter != Control.MOUSE_FILTER_IGNORE and n.get_global_rect().has_point(pos):
		return n
	return null


static func _is_unit_tile(c: Node) -> bool:
	var n := c
	for i in 4:
		if n == null:
			return false
		if n is UnitTile:
			return true
		n = n.get_parent()
	return false
