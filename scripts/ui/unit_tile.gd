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
	v.add_child(top)
	_stars = UI.outlined("", 20, UI.ACCENT, 5, HORIZONTAL_ALIGNMENT_LEFT)
	_stars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_stars)
	_badge = UI.outlined("", 18, Color.WHITE, 5, HORIZONTAL_ALIGNMENT_RIGHT)
	top.add_child(_badge)
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
	_sub.clip_text = true
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sv.add_child(_sub)
	_hp_bg = ColorRect.new()
	_hp_bg.color = Color(0, 0, 0, 0.7)
	_hp_bg.custom_minimum_size = Vector2(0, 12)
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
	button_down.connect(func(): held.emit(self))
	set_empty("")


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
	UI.clear(_arts)
	_hp_bg.visible = false
	_refresh_style()


## unit: {aid, star, arts:[{id}], pers} 또는 상점용 {aid}
func set_unit(unit: Dictionary, sub_text: String = "", border: Color = Color.TRANSPARENT) -> void:
	aid = unit["aid"]
	var a := GameData.apostle(aid)
	var pc := UI.pers_color(aid, unit.get("pers", ""))
	_bg = pc.darkened(0.6)
	_border = border if border.a > 0 else pc.darkened(0.15)
	_tex.texture = UI.portrait(aid)
	_hint.text = ""
	_strip.visible = true
	_name.text = a.get("name", aid)
	_sub.text = sub_text
	_sub.visible = sub_text != ""
	_stars.text = UI.stars(int(unit.get("star", 0)))
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


func set_badge(text: String, color: Color = Color.WHITE) -> void:
	_badge.text = text
	_badge.add_theme_color_override("font_color", color)


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
	var bw := 5 if selected or highlight else 3
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
	for st in ["normal", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(st, UI.box(_bg, 14, border, bw))
	add_theme_stylebox_override("hover", UI.box(_bg.lightened(0.08), 14, border.lightened(0.2), bw))


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
