class_name UI
extends RefCounted
## 화면 구성 도우미: 색상, 테마, 패널, 버튼, 라벨, 막대.

const BG := Color("161824")
const BG2 := Color("1f2233")
const PANEL := Color("262a3d")
const PANEL_LIGHT := Color("33384f")
const LINE := Color("3d4360")
const ACCENT := Color("ffc857")
const TEXT := Color("f2f2f7")
const SUB := Color("a3a8bf")
const GOOD := Color("5ee39b")
const BAD := Color("ff6b6b")
const BLUE := Color("4fa3ff")

const PERS_COLOR := {
	"순수": Color("5fcf7a"), "냉정": Color("4fa3ff"), "광기": Color("ff5d5d"),
	"활발": Color("ffcc33"), "우울": Color("a77bff"), "공명": Color("e8e8f0"), "이면": Color("7fd6d0"),
}
const GRADE_COLOR := {
	"common": Color("b8bcc8"), "advanced": Color("5fcf7a"), "rare": Color("4fa3ff"), "legend": Color("ffb13b"),
}
const COST_COLOR := [Color("9aa0b4"), Color("4fc77a"), Color("3f9cff"), Color("b072ff"), Color("ffb13b")]


## 전체 화면에 쓰는 기본 테마 (모바일에서 누르기 쉽게 크게)
static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("normal", "Button", box(PANEL_LIGHT, 10))
	t.set_stylebox("hover", "Button", box(PANEL_LIGHT.lightened(0.1), 10))
	t.set_stylebox("pressed", "Button", box(PANEL_LIGHT.darkened(0.2), 10))
	t.set_stylebox("disabled", "Button", box(PANEL_LIGHT.darkened(0.35), 10))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	var le := box(BG2, 10, LINE, 2)
	le.content_margin_left = 14
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", box(BG2, 10, ACCENT, 2))
	t.set_font_size("font_size", "LineEdit", 26)
	# 스크롤바를 손가락으로 잡기 좋게
	var grab := box(Color(1, 1, 1, 0.25), 6)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(1, 1, 1, 0.4), 6))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(ACCENT, 6))
	var track := box(Color(0, 0, 0, 0.2), 6)
	track.content_margin_left = 6
	track.content_margin_right = 6
	t.set_stylebox("scroll", "VScrollBar", track)
	var tip := box(Color("101220"), 8, LINE, 2)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_font_size("font_size", "TooltipLabel", 20)
	return t


static func box(color: Color, radius: int = 10, border: Color = Color.TRANSPARENT, border_w: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	s.anti_aliasing = true
	return s


static func panel(color: Color = PANEL, radius: int = 14, border: Color = Color.TRANSPARENT, border_w: int = 0) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(color, radius, border, border_w)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	p.add_theme_stylebox_override("panel", s)
	return p


static func label(text: String, size: int = 22, color: Color = TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


static func outlined(text: String, size: int, color: Color, outline: int = 6, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := label(text, size, color, align)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", outline)
	return l


static func wrap_label(text: String, size: int = 18, color: Color = SUB) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 100
	return l


static func button(text: String, size: int = 22, min_size: Vector2 = Vector2(0, 56), color: Color = PANEL_LIGHT) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = min_size
	b.add_theme_stylebox_override("normal", box(color, 12, color.lightened(0.18), 2))
	b.add_theme_stylebox_override("hover", box(color.lightened(0.1), 12, color.lightened(0.3), 2))
	b.add_theme_stylebox_override("pressed", box(color.darkened(0.2), 12, color.lightened(0.1), 2))
	b.add_theme_stylebox_override("disabled", box(color.darkened(0.45), 12))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	b.focus_mode = Control.FOCUS_NONE
	return b


## 작은 색깔 꼬리표 (성격/종족/등급 등)
static func chip(text: String, color: Color, size: int = 16) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(color.darkened(0.55), 8, color, 2)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", s)
	p.add_child(label(text, size, color.lightened(0.25)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## 막대 (HP/경험치/시간)
static func bar(color: Color, height: int = 14, bg: Color = Color(0, 0, 0, 0.45)) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_stylebox_override("background", box(bg, height / 2))
	var fill := box(color, height / 2)
	fill.content_margin_left = 0
	fill.content_margin_right = 0
	b.add_theme_stylebox_override("fill", fill)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func hsep(color: Color = LINE) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0, 2)
	return r


static func stars(n: int) -> String:
	return "★".repeat(n)


static func pers_color(aid: String, pers: String = "") -> Color:
	var p: String = GameData.apostle(aid).get("personality", "")
	if pers != "":
		return PERS_COLOR.get(pers, Color.GRAY)
	return PERS_COLOR.get(p, Color.GRAY)


static func cost_color(aid: String) -> Color:
	return COST_COLOR[clampi(GameData.cost_of.get(aid, 1), 1, 5) - 1]


static var _tex_cache := {}


static func _find_tex(dir: String, id: String) -> Texture2D:
	var key := dir + id
	if _tex_cache.has(key):
		return _tex_cache[key]
	var tex: Texture2D = null
	for ext in ["webp", "png", "jpg"]:
		var path := "res://assets/%s/%s.%s" % [dir, id, ext]
		if ResourceLoader.exists(path):
			tex = load(path)
			break
	_tex_cache[key] = tex
	return tex


## 사도 초상화 (assets/portraits/<id>.webp|png)
static func portrait(aid: String) -> Texture2D:
	return _find_tex("portraits", aid)


## 아티팩트 아이콘 (assets/artifacts/<id>.png|webp)
static func artifact_icon(id: String) -> Texture2D:
	return _find_tex("artifacts", id)


static func tex_rect(tex: Texture2D, size: Vector2, cover: bool = false) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if cover else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = size
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## 아티팩트 버튼 (아이콘 + 이름, 등급 색 테두리)
static func artifact_button(id: String, size: Vector2 = Vector2(130, 64), font: int = 15, selected: bool = false) -> Button:
	var art := GameData.artifact(id)
	var g: String = art.get("grade", "common")
	var col: Color = GRADE_COLOR[g]
	var b := button(art.get("name", "?"), font, size, col.darkened(0.62))
	b.add_theme_stylebox_override("normal", box(col.darkened(0.62 if not selected else 0.35), 10, ACCENT if selected else col.darkened(0.1), 4 if selected else 2))
	b.icon = artifact_icon(id)
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", int(size.y) - 14)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.tooltip_text = "%s [%s]\n%s" % [art.get("name", ""), GameData.grade_name(g), art.get("text", "")]
	return b


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
