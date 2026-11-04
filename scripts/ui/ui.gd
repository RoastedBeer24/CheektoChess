class_name UI
extends RefCounted
## 화면 구성 도우미: 색상, 패널, 버튼, 라벨.

const BG := Color("1b1d29")
const PANEL := Color("272a3a")
const PANEL_LIGHT := Color("33374b")
const ACCENT := Color("ffc857")
const TEXT := Color("f2f2f7")
const SUB := Color("a9adc1")
const GOOD := Color("6ee7a0")
const BAD := Color("ff6b6b")

const PERS_COLOR := {
	"순수": Color("5fcf7a"), "냉정": Color("4fa3ff"), "광기": Color("ff5d5d"),
	"활발": Color("ffcc33"), "우울": Color("a77bff"), "공명": Color("e8e8f0"), "이면": Color("7fd6d0"),
}
const GRADE_COLOR := {
	"common": Color("b8bcc8"), "advanced": Color("5fcf7a"), "rare": Color("4fa3ff"), "legend": Color("ffb13b"),
}


static func box(color: Color, radius: int = 10, border: Color = Color.TRANSPARENT, border_w: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func panel(color: Color = PANEL, radius: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, radius))
	return p


static func label(text: String, size: int = 22, color: Color = TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
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
	b.add_theme_stylebox_override("normal", box(color, 10))
	b.add_theme_stylebox_override("hover", box(color.lightened(0.12), 10))
	b.add_theme_stylebox_override("pressed", box(color.darkened(0.2), 10))
	b.add_theme_stylebox_override("disabled", box(color.darkened(0.4), 10))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.focus_mode = Control.FOCUS_NONE
	return b


static func stars(n: int) -> String:
	return "★".repeat(n)


static func pers_color(aid: String, pers: String = "") -> Color:
	var p: String = GameData.apostle(aid).get("personality", "")
	if pers != "":
		return PERS_COLOR.get(pers, Color.GRAY)
	return PERS_COLOR.get(p, Color.GRAY)


## 사도 초상화 (assets/portraits/<id>.png 가 있으면 사용)
static func portrait(aid: String) -> Texture2D:
	for ext in ["png", "webp", "jpg"]:
		var path := "res://assets/portraits/%s.%s" % [aid, ext]
		if ResourceLoader.exists(path):
			return load(path)
	return null


## 아티팩트 아이콘 (assets/artifacts/<id>.png 가 있으면 사용)
static func artifact_icon(id: String) -> Texture2D:
	for ext in ["png", "webp", "jpg"]:
		var path := "res://assets/artifacts/%s.%s" % [id, ext]
		if ResourceLoader.exists(path):
			return load(path)
	return null


## 아티팩트 버튼 (아이콘 + 이름, 등급 색 테두리)
static func artifact_button(id: String, size: Vector2 = Vector2(130, 64), font: int = 15, selected: bool = false) -> Button:
	var art := GameData.artifact(id)
	var g: String = art.get("grade", "common")
	var col: Color = GRADE_COLOR[g]
	var b := button(art.get("name", "?"), font, size, col.darkened(0.6))
	b.add_theme_stylebox_override("normal", box(col.darkened(0.6 if not selected else 0.3), 10, ACCENT if selected else col.darkened(0.1), 4 if selected else 2))
	b.icon = artifact_icon(id)
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", int(size.y) - 14)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.tooltip_text = art.get("name", "")
	return b


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
