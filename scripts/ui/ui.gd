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
const SUB := Color("b9bed3")
const DIM := Color("8a8fa6")
## 화면 어디서나 이보다 작은 글자는 쓰지 않는다 (모바일 가독성)
const MIN_FONT := 18
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
	var grab := box(Color(1, 1, 1, 0.38), 7)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(1, 1, 1, 0.55), 7))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(ACCENT, 7))
	var track := box(Color(0, 0, 0, 0.28), 7)
	track.content_margin_left = 7
	track.content_margin_right = 7
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_constant("line_spacing", "Label", 3)
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
	l.add_theme_font_size_override("font_size", maxi(size, MIN_FONT))
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
	b.add_theme_font_size_override("font_size", maxi(size, MIN_FONT))
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
static func chip(text: String, color: Color, size: int = 16, icon: Texture2D = null) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(color.darkened(0.55), 8, color, 2)
	s.content_margin_left = 8 if icon == null else 4
	s.content_margin_right = 8
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", s)
	var l := label(text, size, color.lightened(0.25))
	if icon != null:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 4)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(tex_rect(icon, Vector2(size + 6, size + 6)))
		h.add_child(l)
		p.add_child(h)
	else:
		p.add_child(l)
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


## 설명 글: 용어는 색 + 밑줄(올리거나 누르면 설명), 숫자는 강조, '■' 줄은 들여쓰기
static func rich_desc(text: String, size: int = 19, color: Color = SUB, num_color: Color = Color("ffd98a"), links: bool = true) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size.x = 100
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.mouse_filter = Control.MOUSE_FILTER_PASS if links else Control.MOUSE_FILTER_IGNORE
	r.meta_underlined = true
	r.add_theme_font_size_override("normal_font_size", maxi(size, MIN_FONT))
	r.add_theme_font_size_override("bold_font_size", maxi(size, MIN_FONT))
	r.add_theme_color_override("default_color", color)
	r.add_theme_constant_override("line_separation", 4)
	var lines := []
	for line in text.split("\n"):
		var t := String(line).strip_edges()
		if t == "":
			continue
		var bullet := t.begins_with("■")
		if bullet:
			t = t.substr(1).strip_edges()
		t = Glossary.markup(t, num_color.to_html(false), links)
		if bullet:
			t = "[indent]• " + t + "[/indent]"
		lines.append(t)
	r.text = "\n".join(lines)
	if links:
		r.meta_hover_started.connect(func(meta):
			if Tips.inst and not OS.has_feature("mobile"):
				Tips.inst.show_term(String(meta), r.get_global_mouse_position()))
		r.meta_hover_ended.connect(func(_meta):
			if Tips.inst and not OS.has_feature("mobile"):
				Tips.inst.hide_tip())
		r.meta_clicked.connect(func(meta):
			if Tips.inst:
				Tips.inst.show_term(String(meta), r.get_global_mouse_position()))
	return r


## 짧은 글에 색 규칙만 입힌 BBCode (툴팁 등)
static func mark(text: String) -> String:
	return Glossary.markup(text, Glossary.C_GOLD, false)


## 주어진 너비에 맞게 글자 크기를 줄인다 (min_size 까지)
static func fit_font(l: Label, width: float, size: int, min_size: int = 15) -> void:
	var f := l.get_theme_font("font")
	var s := size
	while s > min_size and f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > width:
		s -= 1
	l.add_theme_font_size_override("font_size", s)


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


const TRAIT_ICON := {
	"순수": "pers_innocence", "냉정": "pers_composed", "광기": "pers_madness", "활발": "pers_vivacious",
	"우울": "pers_depressed", "공명": "pers_resonance", "이면": "pers_resonance",
	"수인": "race_werebeasts", "엘프": "race_elves", "정령": "race_elementals", "요정": "race_sprites",
	"유령": "race_phantoms", "용족": "race_dragons", "마녀": "race_witches", "미스틱": "race_mystic",
	"엘다인": "eldyne",
	"front": "row_front", "mid": "row_mid", "back": "row_back", "all": "row_all",
	"dealer": "role_dealer", "tank": "role_tank", "support": "role_support",
	"physical": "dmg_physical", "magic": "dmg_magic",
}


## 성격·종족·엘다인·열·역할·공격 타입 아이콘 (assets/icons)
static func trait_icon(key: String) -> Texture2D:
	if not TRAIT_ICON.has(key):
		return null
	return _find_tex("icons", TRAIT_ICON[key])


## 그룹 시너지 짧은 이름 (좁은 곳)
static func syn_short(name: String) -> String:
	return String(GameData.synergies.get(name, {}).get("short", name))


## 그룹 시너지 색
static func syn_color(name: String) -> Color:
	var syn: Dictionary = GameData.synergies.get(name, {})
	return Color(syn.get("color", "c0c4d6"))


## 그룹 시너지 표시: 색 원 + 첫 글자 (그림 아이콘이 없으므로)
static func syn_badge(name: String, size: float = 30.0, dim: bool = false) -> PanelContainer:
	var col := syn_color(name)
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = col.darkened(0.45) if not dim else col.darkened(0.75)
	s.border_color = col if not dim else col.darkened(0.4)
	s.set_border_width_all(2)
	s.set_corner_radius_all(int(size / 2.0))
	if GameData.synergies.get(name, {}).get("kind", "") == "unique":
		s.set_corner_radius_all(int(size / 5.0))   # 고유 시너지는 네모
	s.anti_aliasing = true
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = Vector2(size, size)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = name.substr(0, 1)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", int(size * 0.55))
	l.add_theme_color_override("font_color", Color.WHITE if not dim else Color(1, 1, 1, 0.5))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


static var _TIER_RE := RegEx.create_from_string("^(\\d+)명\\s*:\\s*(.*)$")


## 시너지 효과 글 → [컨셉 줄, {필요 인원: 그 단계 효과 글}]
static func syn_lines(name: String) -> Array:
	var syn: Dictionary = GameData.synergies.get(name, {})
	var head := ""
	var tiers := {}
	for line in String(syn.get("effect", "")).split("\n"):
		var t := String(line).strip_edges()
		if t == "":
			continue
		var m := _TIER_RE.search(t)
		if m:
			tiers[int(m.get_string(1))] = m.get_string(2)
		else:
			head = (head + " " + t).strip_edges()
	return [head, tiers]


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
	Tips.set_tip(b, art_tip(id))
	# 이름이 길면 버튼 너비에 맞게 글자를 줄인다 (잘림 방지)
	if size.x > 0:
		var room := size.x - (size.y - 14) - 34
		var f := b.get_theme_font("font")
		var fs := maxi(font, MIN_FONT)
		while fs > 15 and f.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
			fs -= 1
		b.add_theme_font_size_override("font_size", fs)
	return b


## 툴팁 글: 아티팩트 (이름·등급·능력치·효과)
static func art_tip(id: String) -> String:
	var art := GameData.artifact(id)
	if art.is_empty():
		return ""
	var g: String = art.get("grade", "common")
	var col: String = GRADE_COLOR[g].to_html(false)
	var out := "[b][color=#%s]%s[/color][/b]  [color=#%s]%s[/color]" % [col, art.get("name", ""), col, GameData.grade_name(g)]
	var st := []
	for k in art.get("stats", {}):
		st.append("%s +%s%%" % [Info.STAT_NAME.get(k, k), str(art["stats"][k])])
	if not st.is_empty():
		out += "\n" + mark(" · ".join(st))
	if art.get("text", "") != "":
		out += "\n" + mark(art["text"])
	if art.get("owner", "") != "":
		out += "\n[color=#ff9ec7]♥ 애착: %s[/color]" % art["owner"]
	return out


## 툴팁 글: 사도 (이름·★·코스트·특성·장착 아티팩트)
static func unit_tip(u: Dictionary, extra: String = "") -> String:
	var aid: String = u.get("aid", "")
	if aid == "":
		return ""
	var a := GameData.apostle(aid)
	var cost: int = GameData.cost_of.get(aid, 1)
	var pers: String = u.get("pers", "") if u.get("pers", "") != "" else a.get("personality", "")
	var out := "[b]%s[/b] [color=#ffc857]%s[/color]  [color=#%s]%d코스트[/color]" % [a.get("name", aid), stars(int(u.get("star", 1))), cost_color(aid).lightened(0.25).to_html(false), cost]
	var tr := ["[color=#%s]%s[/color]" % [PERS_COLOR.get(pers, Color.GRAY).to_html(false), pers], a.get("race", "")]
	if a.get("eldyne", false):
		tr.append("[color=#e0b84f]엘다인[/color]")
	out += "\n" + " · ".join(tr)
	var syns := []
	for t in GameData.traits_of(aid):
		syns.append("[color=#%s]%s[/color]" % [syn_color(t).to_html(false), t])
	if not syns.is_empty():
		out += "\n시너지: " + ", ".join(syns)
	out += "\n" + mark("%s · %s · %s" % [GameData.ROW_NAME[a["row"]], GameData.ROLE_NAME[a["role"]], GameData.DAMAGE_NAME[a["damage"]]])
	var arts: Array = u.get("arts", [])
	if not arts.is_empty():
		var names := []
		for art in arts:
			var ai := GameData.artifact(art["id"])
			names.append("[color=#%s]%s[/color]" % [GRADE_COLOR[ai.get("grade", "common")].to_html(false), ai.get("name", "")])
		out += "\n아티팩트: " + ", ".join(names)
	if extra != "":
		out += "\n" + extra
	return out


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
