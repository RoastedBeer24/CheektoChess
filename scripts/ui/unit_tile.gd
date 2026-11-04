class_name UnitTile
extends Button
## 사도 한 칸(보드/대기석/상점/전투). 누르기와 끌어다 놓기(드래그 앤 드롭) 모두 지원.

signal held(tile: UnitTile)   # 누르기 시작 (끌기 후보)

var aid := ""
var loc: Dictionary = {}           # 이 칸의 위치 ({"bench": i} / {"board": "r,s"}), 비어 있으면 끌기 불가
var draggable := false
var _drop_state := ""
var _drop_shade: ColorRect
var _drop_lbl: Label
var _ghost: TextureRect
var selected := false
var highlight := false
var dim := false
var _border := Color.GRAY
var _bg := Color.GRAY

var _tex: TextureRect
var _shade: ColorRect
var _stars: Label
var _badge: Label
var _strip: PanelContainer
var _name: Label
var _sub: Label
var _arts: HBoxContainer
var _hp_bg: ColorRect
var _hp: ColorRect
var _shield: ColorRect
var _hint: Label
var _lock: PanelContainer
var locked := false
var _icons: VBoxContainer
var _corner: Label
var _inner: Panel
var _stripe: ColorRect
var _cost := 0
var _clock := 0.0


func _init(size: Vector2 = Vector2(140, 140)) -> void:
	custom_minimum_size = size
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	_tex = UI.tex_rect(null, Vector2.ZERO, true)
	_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_tex)
	_shade = ColorRect.new()
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.color = Color(0, 0, 0, 0.0)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
	_hint = UI.label("", 18, Color(1, 1, 1, 0.25), HORIZONTAL_ALIGNMENT_CENTER)
	_hint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 5
	v.offset_right = -5
	v.offset_top = 3
	v.offset_bottom = -5
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 2)
	v.add_child(top)
	# 성격·종족(·엘다인) 아이콘
	_icons = VBoxContainer.new()
	_icons.add_theme_constant_override("separation", 1)
	_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icons.position = Vector2(5, 4)
	add_child(_icons)   # 흐름 밖에 둬서 이름 띠를 아래로 밀어내지 않게
	# 가운데 위 알림 (합성 가능·보유 수): 어두운 바탕을 깔아 초상화 위에서도 잘 읽히게
	var cwrap := CenterContainer.new()
	cwrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cwrap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cwrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(cwrap)
	_corner = UI.outlined("", 15, UI.ACCENT, 4, HORIZONTAL_ALIGNMENT_CENTER)
	var cs := UI.box(Color(0.06, 0.07, 0.12, 0.85), 7)
	cs.content_margin_left = 6
	cs.content_margin_right = 6
	cs.content_margin_top = 0
	cs.content_margin_bottom = 1
	_corner.add_theme_stylebox_override("normal", cs)
	_corner.visible = false
	cwrap.add_child(_corner)
	var right := VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_theme_constant_override("separation", -4)
	top.add_child(right)
	_stars = UI.outlined("", 18, UI.ACCENT, 5, HORIZONTAL_ALIGNMENT_RIGHT)
	right.add_child(_stars)
	_badge = UI.outlined("", 18, Color.WHITE, 5, HORIZONTAL_ALIGNMENT_RIGHT)
	right.add_child(_badge)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spacer)
	_arts = HBoxContainer.new()
	_arts.alignment = BoxContainer.ALIGNMENT_END
	_arts.add_theme_constant_override("separation", 2)
	_arts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_arts)
	_strip = PanelContainer.new()
	var sb := UI.box(Color(0.05, 0.05, 0.1, 0.72), 7)
	sb.set_content_margin_all(2)
	_strip.add_theme_stylebox_override("panel", sb)
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_strip)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", -3)
	sv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(sv)
	_name = UI.label("", 19, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_name.clip_text = true
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sv.add_child(_name)
	_sub = UI.label("", 14, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER)
	_sub.add_theme_font_size_override("font_size", 16)   # 칸 안의 보조 글자는 공간이 좁아 조금 작게
	_sub.clip_text = true
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sv.add_child(_sub)
	_hp_bg = ColorRect.new()
	_hp_bg.color = Color(0, 0, 0, 0.7)
	_hp_bg.custom_minimum_size = Vector2(0, 15)
	_hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_hp_bg)
	_hp = ColorRect.new()
	_hp.color = UI.GOOD
	_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bg.add_child(_hp)
	_shield = ColorRect.new()
	_shield.color = Color(0.85, 0.92, 1.0, 0.9)
	_shield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bg.add_child(_shield)
	_hp_bg.visible = false
	# 코스트 등급 띠(아래)와 안쪽 테두리
	_stripe = ColorRect.new()
	_stripe.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_stripe.offset_top = -6
	_stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stripe.visible = false
	add_child(_stripe)
	_inner = Panel.new()
	_inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inner.offset_left = 4
	_inner.offset_top = 4
	_inner.offset_right = -4
	_inner.offset_bottom = -4
	_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inner.visible = false
	add_child(_inner)
	# 끌어다 놓기 표시용
	_ghost = UI.tex_rect(null, Vector2.ZERO, true)
	_ghost.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ghost.modulate = Color(1, 1, 1, 0.55)
	add_child(_ghost)
	_drop_shade = ColorRect.new()
	_drop_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drop_shade.color = Color(0, 0, 0, 0)
	_drop_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_drop_shade)
	_drop_lbl = UI.outlined("", 22, Color.WHITE, 7)
	_drop_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drop_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_drop_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drop_lbl.visible = false
	add_child(_drop_lbl)
	# 잠금 표시 (상점)
	_lock = UI.chip("잠금", Color("8fd0ff"), 16)
	_lock.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_lock.position = Vector2(-30, 36)
	_lock.visible = false
	add_child(_lock)
	button_down.connect(func():
		_press_fx(true)
		held.emit(self))
	button_up.connect(func(): _press_fx(false))
	set_empty("")


## 누를 때 살짝 작아졌다가 돌아오는 느낌 (눌렸는지 손가락으로도 알 수 있게)
var _press_tw: Tween


func _press_fx(down: bool) -> void:
	if aid == "" and not down:
		scale = Vector2.ONE
		return
	pivot_offset = size / 2.0
	if _press_tw:
		_press_tw.kill()
	_press_tw = create_tween()
	_press_tw.tween_property(self, "scale", Vector2(0.95, 0.95) if down else Vector2.ONE, 0.07)


func set_empty(hint: String = "") -> void:
	aid = ""
	draggable = false
	_bg = UI.BG2
	_border = UI.LINE
	_tex.texture = null
	_shade.color.a = 0.0
	_hint.text = hint
	_strip.visible = false
	_stars.text = ""
	_badge.text = ""
	_corner.text = ""
	_corner.visible = false
	UI.clear(_arts)
	UI.clear(_icons)
	_cost = 0
	_stripe.visible = false
	_inner.visible = false
	set_process(false)
	_hp_bg.visible = false
	locked = false
	_lock.visible = false
	_refresh_style()


## unit: {aid, star, arts:[{id}], pers} 또는 상점용 {aid}
func set_unit(unit: Dictionary, sub_text: String = "", border: Color = Color.TRANSPARENT) -> void:
	aid = unit["aid"]
	var a := GameData.apostle(aid)
	# 코스트 등급 색으로 테두리·배경 (성격은 아이콘으로 구분)
	_cost = int(GameData.cost_of.get(aid, 1))
	var cc: Color = UI.COST_COLOR[clampi(_cost, 1, 5) - 1]
	_bg = cc.darkened(0.7)
	_border = border if border.a > 0 else cc
	_stripe.color = cc
	_stripe.visible = true
	var ib := StyleBoxFlat.new()
	ib.draw_center = false
	ib.set_corner_radius_all(10)
	ib.set_border_width_all(2)
	ib.border_color = cc.lightened(0.45) if _cost >= 4 else Color(cc, 0.55)
	_inner.add_theme_stylebox_override("panel", ib)
	_inner.visible = true
	_inner.self_modulate.a = 1.0
	set_process(_cost >= 5)
	_set_icons(unit)
	_corner.text = ""
	_corner.visible = false
	_tex.texture = UI.portrait(aid)
	_hint.text = ""
	_strip.visible = true
	_name.text = a.get("name", aid)
	_name.add_theme_color_override("font_color", UI.TEXT)
	_sub.text = sub_text
	_sub.visible = sub_text != ""
	_stars.text = UI.stars(int(unit.get("star", 0)))
	_stars.add_theme_color_override("font_color", UI.ACCENT)
	_badge.text = ""
	UI.clear(_arts)
	for art in unit.get("arts", []):
		var art_id: String = art["id"] if art is Dictionary else art
		var g: String = GameData.artifact(art_id).get("grade", "common")
		var frame := PanelContainer.new()
		var st := UI.box(Color(0, 0, 0, 0.7), 5, UI.GRADE_COLOR[g], 2)
		st.set_content_margin_all(1)
		frame.add_theme_stylebox_override("panel", st)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tex := UI.artifact_icon(art_id)
		if tex != null:
			frame.add_child(UI.tex_rect(tex, Vector2(24, 24)))
		else:
			var dot := ColorRect.new()
			dot.custom_minimum_size = Vector2(20, 20)
			dot.color = UI.GRADE_COLOR[g]
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			frame.add_child(dot)
		_arts.add_child(frame)
	_refresh_style()


func set_locked(on: bool) -> void:
	locked = on
	_lock.visible = on
	_lock.position = Vector2((size.x if size.x > 0 else custom_minimum_size.x) / 2.0 - 30, 4)
	_refresh_style()


func set_corner(text: String, color: Color = UI.ACCENT) -> void:
	_corner.text = text
	_corner.visible = text != ""
	_corner.add_theme_color_override("font_color", color)


func _set_icons(unit: Dictionary) -> void:
	UI.clear(_icons)
	var a := GameData.apostle(aid)
	var p: String = unit.get("pers", "")
	if p == "":
		p = a.get("personality", "")
	var s := clampf(minf(custom_minimum_size.x, custom_minimum_size.y) * 0.19, 16.0, 30.0)
	for key in [p, a.get("race", ""), "엘다인" if a.get("eldyne", false) else ""]:
		var tex := UI.trait_icon(key)
		if tex != null:
			_icons.add_child(UI.tex_rect(tex, Vector2(s, s)))


func _process(delta: float) -> void:
	# 5코스트: 안쪽 테두리가 은은하게 반짝인다
	_clock += delta
	_inner.self_modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_clock * 3.2))


func set_badge(text: String, color: Color = Color.WHITE, fsize: int = 18) -> void:
	_badge.text = text
	_badge.add_theme_color_override("font_color", color)
	_badge.add_theme_font_size_override("font_size", fsize)


func set_name_color(color: Color) -> void:
	_name.add_theme_color_override("font_color", color)


func set_hp(ratio: float, shield_ratio: float = 0.0) -> void:
	_hp_bg.visible = true
	var w := _hp_bg.size.x if _hp_bg.size.x > 0 else size.x - 10
	_hp.size = Vector2(w * clampf(ratio, 0, 1), 12)
	_hp.color = UI.GOOD if ratio > 0.5 else (Color("ffcc33") if ratio > 0.25 else UI.BAD)
	_shield.position = Vector2(_hp.size.x, 0)
	_shield.size = Vector2(minf(w - _hp.size.x, w * shield_ratio), 12)


func set_selected(on: bool) -> void:
	selected = on
	_refresh_style()


func set_highlight(on: bool) -> void:
	highlight = on
	_refresh_style()


func set_dim(on: bool) -> void:
	dim = on
	_shade.color.a = 0.55 if on else 0.0


func _refresh_style() -> void:
	var border := UI.ACCENT if selected else (Color("7fffd4") if highlight else _border)
	var bw := 5 if selected or highlight else (4 if aid != "" else 3)
	if locked and _drop_state == "":
		border = Color("8fd0ff")
		bw = 5
	match _drop_state:
		"ok":
			border = Color("5ee39b")
			bw = 4
		"bad":
			border = Color("6b3535")
		"hover":
			border = Color("9dffc8")
			bw = 7
		"hover_bad":
			border = Color("ff6b6b")
			bw = 7
	for st in ["normal", "pressed", "disabled", "focus", "hover"]:
		var sb := UI.box(_bg.lightened(0.08) if st == "hover" else _bg, 14, border.lightened(0.2) if st == "hover" else border, bw)
		if _cost >= 4 and _drop_state == "":
			sb.shadow_color = Color(UI.COST_COLOR[_cost - 1], 0.55 if _cost == 5 else 0.4)
			sb.shadow_size = 9 if _cost == 5 else 6
		add_theme_stylebox_override(st, sb)


# ─────────────────────────────── 끌어다 놓기 표시 ───────────────────────────────
# 끌기 자체는 GameScreen 이 처리하고, 칸은 상태만 그린다.
#   state: "" (보통) / "ok" (놓을 수 있음) / "bad" (불가) / "hover" (손가락 아래, 가능) / "hover_bad" (손가락 아래, 불가)

func set_drop(state: String, text: String = "", ghost_aid: String = "") -> void:
	_drop_state = state
	match state:
		"ok":
			_drop_shade.color = Color(0.3, 1.0, 0.6, 0.10)
		"bad":
			_drop_shade.color = Color(0.0, 0.0, 0.0, 0.55)
		"hover":
			_drop_shade.color = Color(0.3, 1.0, 0.6, 0.22)
		"hover_bad":
			_drop_shade.color = Color(1.0, 0.25, 0.25, 0.35)
		_:
			_drop_shade.color = Color(0, 0, 0, 0)
	_drop_lbl.text = text
	_drop_lbl.visible = text != ""
	_ghost.texture = UI.portrait(ghost_aid) if ghost_aid != "" and state == "hover" else null
	_refresh_style()
