class_name UnitTile
extends Button
## 사도 한 칸(보드/대기석/상점/전투)을 그리는 버튼.

var aid := ""
var _name: Label
var _sub: Label
var _stars: Label
var _tex: TextureRect
var _hp_bg: ColorRect
var _hp: ColorRect
var _shield: ColorRect
var _arts: HBoxContainer
var _color := Color.GRAY
var selected := false
var highlight := false


func _init(size: Vector2 = Vector2(140, 140)) -> void:
	custom_minimum_size = size
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	_tex = TextureRect.new()
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tex.modulate = Color(1, 1, 1, 0.85)
	add_child(_tex)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 6
	v.offset_right = -6
	v.offset_top = 4
	v.offset_bottom = -4
	v.add_theme_constant_override("separation", 0)
	add_child(v)
	_stars = UI.label("", 18, UI.ACCENT)
	v.add_child(_stars)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	_name = UI.label("", 20, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.add_theme_color_override("font_outline_color", Color.BLACK)
	_name.add_theme_constant_override("outline_size", 6)
	v.add_child(_name)
	_sub = UI.label("", 15, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER)
	_sub.add_theme_color_override("font_outline_color", Color.BLACK)
	_sub.add_theme_constant_override("outline_size", 2)
	v.add_child(_sub)
	_arts = HBoxContainer.new()
	_arts.alignment = BoxContainer.ALIGNMENT_CENTER
	_arts.add_theme_constant_override("separation", 3)
	v.add_child(_arts)
	_hp_bg = ColorRect.new()
	_hp_bg.color = Color(0, 0, 0, 0.6)
	_hp_bg.custom_minimum_size = Vector2(0, 10)
	v.add_child(_hp_bg)
	_hp = ColorRect.new()
	_hp.color = UI.GOOD
	_hp_bg.add_child(_hp)
	_shield = ColorRect.new()
	_shield.color = Color(1, 1, 1, 0.8)
	_hp_bg.add_child(_shield)
	_hp_bg.visible = false
	for c in [_tex, v, _stars, _name, _sub, _arts, _hp_bg, _hp, _shield, spacer]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_empty("")


func set_empty(hint: String = "") -> void:
	aid = ""
	_color = UI.PANEL_LIGHT.darkened(0.25)
	_tex.texture = null
	_name.text = hint
	_name.add_theme_color_override("font_color", UI.SUB)
	_sub.text = ""
	_stars.text = ""
	UI.clear(_arts)
	_hp_bg.visible = false
	_refresh_style()


## unit: {aid, star, arts:[{id}], pers} 또는 상점용 {aid}
func set_unit(unit: Dictionary, sub_text: String = "") -> void:
	aid = unit["aid"]
	var a := GameData.apostle(aid)
	_color = UI.pers_color(aid, unit.get("pers", ""))
	_tex.texture = UI.portrait(aid)
	_name.text = a.get("name", aid)
	_name.add_theme_color_override("font_color", UI.TEXT)
	_stars.text = UI.stars(int(unit.get("star", 0)))
	_sub.text = sub_text
	UI.clear(_arts)
	for art in unit.get("arts", []):
		var g: String = GameData.artifact(art["id"] if art is Dictionary else art).get("grade", "common")
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.color = UI.GRADE_COLOR[g]
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_arts.add_child(dot)
	_refresh_style()


func set_hp(ratio: float, shield_ratio: float = 0.0) -> void:
	_hp_bg.visible = true
	var w := _hp_bg.size.x if _hp_bg.size.x > 0 else size.x - 12
	_hp.size = Vector2(w * clampf(ratio, 0, 1), 10)
	_hp.color = UI.GOOD if ratio > 0.35 else UI.BAD
	_shield.position = Vector2(_hp.size.x, 0)
	_shield.size = Vector2(minf(w - _hp.size.x, w * shield_ratio), 10)


func set_selected(on: bool) -> void:
	selected = on
	_refresh_style()


func set_highlight(on: bool) -> void:
	highlight = on
	_refresh_style()


func _refresh_style() -> void:
	var border := UI.ACCENT if selected else (Color("7fffd4") if highlight else _color.darkened(0.3))
	var bw := 5 if selected or highlight else 3
	var bg := _color.darkened(0.55) if aid != "" else _color
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var s := UI.box(bg if st != "hover" else bg.lightened(0.08), 12, border, bw)
		add_theme_stylebox_override(st, s)
