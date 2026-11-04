class_name DragScroll
extends ScrollContainer
## 손가락으로 끌어서 스크롤하는 목록 (버튼·카드 위에서 끌어도 스크롤, 놓으면 관성).
## 짧게 누르면 그대로 누르기, 일정 거리 이상 끌면 스크롤로 바뀌고 그 누르기는 취소된다.
## 아래(위)에 내용이 더 있으면 가장자리를 흐리게 표시한다.

const START_DIST := 12.0        # 이만큼 움직이면 스크롤 시작 (캔버스 좌표)
const FRICTION := 5.0           # 관성 감속 (클수록 빨리 멈춤)

## 다른 끌기(사도·아티팩트 끌어다 놓기)가 이미 시작되었으면 스크롤하지 않는다
static var external_drag := false
## 지금 어느 목록이든 손가락 스크롤 중인지 (게임 화면이 끌어다 놓기를 취소하는 데 사용)
static var scrolling := false
static var _injecting := false

## true 이면 세로로 확실히 끌 때만 스크롤 (가로로 끌면 끌어다 놓기에 양보)
var vertical_only := false

var _pressing := false
var _dragging := false
var _start := Vector2.ZERO
var _start_scroll := 0.0
var _last := Vector2.ZERO
var _last_t := 0
var _vel := 0.0
var _fade_bottom: TextureRect
var _fade_top: TextureRect


func _init(fade_color: Color = UI.PANEL) -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_fade_bottom = _make_fade(fade_color, false)
	_fade_top = _make_fade(fade_color, true)


func _ready() -> void:
	get_v_scroll_bar().custom_step = 90.0
	# 흐림 표시는 목록 내용과 겹치지 않게 부모 쪽에 둔다 (ScrollContainer 는 자식을 모두 배치하므로)
	(func():
		var p := get_parent()
		if p != null:
			p.add_child(_fade_top)
			p.add_child(_fade_bottom)).call_deferred()


func _exit_tree() -> void:
	if _dragging:
		scrolling = false


func _make_fade(col: Color, top: bool) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(col, 0.0) if not top else Color(col, 0.95))
	g.set_color(1, Color(col, 0.95) if not top else Color(col, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.top_level = true
	tr.visible = false
	return tr


func _input(event: InputEvent) -> void:
	if _injecting or not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var pos := _canvas_pos(event.position)
			if _max_scroll() > 0.0 and get_global_rect().has_point(pos) and not _covered(pos):
				_pressing = true
				_dragging = false
				_start = event.position
				_start_scroll = scroll_vertical
				_last = event.position
				_last_t = Time.get_ticks_msec()
				_vel = 0.0
		else:
			if _dragging:
				_dragging = false
				scrolling = false
				get_viewport().set_input_as_handled()
			_pressing = false
	elif event is InputEventMouseMotion and _pressing:
		var d: Vector2 = event.position - _start
		if not _dragging:
			if d.length() < START_DIST or external_drag:
				return
			if absf(d.y) < absf(d.x) * (1.4 if vertical_only else 0.8):
				_pressing = false     # 가로로 끌기 → 스크롤이 아님
				return
			_dragging = true
			scrolling = true
			_cancel_press()
		var now := Time.get_ticks_msec()
		var dt := maxf(1.0, float(now - _last_t))
		var dy: float = event.position.y - _last.y
		_vel = lerpf(_vel, -dy / dt * 1000.0, 0.5)
		_last = event.position
		_last_t = now
		scroll_vertical = int(_start_scroll - d.y / _scale())
		get_viewport().set_input_as_handled()


## 이미 눌린 버튼이 손을 뗄 때 눌리지 않도록, 화면 밖에서 놓은 것으로 처리한다
func _cancel_press() -> void:
	cancel_press(get_viewport())


## 지금 눌린 버튼이 눌리지 않도록 취소 (화면 밖에서 놓은 것으로 처리). 툴팁 꾹 누르기에서도 사용.
static func cancel_press(vp: Viewport) -> void:
	_injecting = true
	var far := Vector2(-100000, -100000)
	var mv := InputEventMouseMotion.new()
	mv.position = far
	mv.global_position = far
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT
	vp.push_input(mv)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = far
	up.global_position = far
	vp.push_input(up)
	_injecting = false


func _process(delta: float) -> void:
	if not _dragging and absf(_vel) > 5.0:
		scroll_vertical = int(scroll_vertical + _vel * delta / _scale())
		_vel *= maxf(0.0, 1.0 - FRICTION * delta)
		if scroll_vertical <= 0 or scroll_vertical >= int(_max_scroll()):
			_vel = 0.0
	_update_fades()


var _cover_t := 0.0
var _is_covered := false


func _update_fades() -> void:
	var r := get_global_rect()
	var mx := _max_scroll()
	# 위에 다른 창이 덮이면 흐림 표시를 숨긴다 (top_level 이라 창보다 위에 그려지므로). 가끔만 검사
	_cover_t -= get_process_delta_time()
	if _cover_t <= 0.0:
		_cover_t = 0.15
		_is_covered = mx > 1.0 and is_visible_in_tree() and _covered(r.get_center())
	if _is_covered:
		_fade_bottom.visible = false
		_fade_top.visible = false
		return
	var h := minf(56.0, r.size.y * 0.25)
	var bar_w := get_v_scroll_bar().size.x if get_v_scroll_bar().visible else 0.0
	_fade_bottom.visible = is_visible_in_tree() and mx > 1.0 and scroll_vertical < mx - 2.0
	_fade_top.visible = is_visible_in_tree() and mx > 1.0 and scroll_vertical > 2
	if _fade_bottom.visible:
		_fade_bottom.global_position = Vector2(r.position.x, r.end.y - h)
		_fade_bottom.size = Vector2(r.size.x - bar_w, h)
	if _fade_top.visible:
		_fade_top.global_position = r.position
		_fade_top.size = Vector2(r.size.x - bar_w, h * 0.6)


## 이 목록 위에 다른 창(도감·팝업 등)이 덮여 있는지: 조상들의 '뒤에 그려지는' 형제를 살펴본다
func _covered(pos: Vector2) -> bool:
	var n: Node = self
	while n.get_parent() != null:
		var par := n.get_parent()
		var after := false
		for c in par.get_children():
			if c == n:
				after = true
				continue
			if after and c is Control and c != _fade_top and c != _fade_bottom and _hits(c, pos):
				return true
		n = par
	return false


static func _hits(c: Control, pos: Vector2) -> bool:
	if not c.visible:
		return false
	if c.mouse_filter == Control.MOUSE_FILTER_STOP and c.get_global_rect().has_point(pos):
		return true
	for k in c.get_children():
		if k is Control and _hits(k, pos):
			return true
	return false


func _max_scroll() -> float:
	var sb := get_v_scroll_bar()
	return maxf(0.0, sb.max_value - sb.page)


## _input 좌표(캔버스) 와 이 목록의 배율이 다를 때 보정 (보통 1)
func _scale() -> float:
	return get_global_transform().get_scale().y


func _canvas_pos(p: Vector2) -> Vector2:
	return p
