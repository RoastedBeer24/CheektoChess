class_name Codex
extends Control
## 도감: 사도 / 아티팩트 / 시너지. 검색(초성 검색 포함), 여러 필터, 정렬, 상세 정보.

const CHO := ["ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]

const FILTERS := [
	["cost", "코스트", ["1", "2", "3", "4", "5"]],
	["pers", "성격", ["순수", "냉정", "광기", "활발", "우울", "공명", "이면"]],
	["race", "종족", ["수인", "엘프", "정령", "요정", "유령", "용족", "마녀", "미스틱"]],
	["eldyne", "특수", ["엘다인"]],
	["row", "열", ["전열", "중열", "후열", "모든열"]],
	["role", "역할", ["딜러", "탱커", "서포터"]],
	["dmg", "공격", ["물리", "마법"]],
]
const ART_FILTERS := [
	["grade", "등급", ["일반", "고급", "희귀", "전설"]],
	["kind", "종류", ["애착", "글로벌 전용", "부가 효과 있음"]],
]

var tab := "apostle"
var query := ""
var picked := {}          # 필터 키 -> {값: true}
var sort_mode := "cost"
var _search: LineEdit
var _filters_box: VBoxContainer
var _grid: GridContainer
var _count: Label
var _detail: VBoxContainer
var _tab_btns := {}
var _sort_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 50
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(UI.BG, 0.98)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_right = -16
	root.offset_top = 12
	root.offset_bottom = -12
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	root.add_child(top)
	top.add_child(UI.outlined("도감", 40, UI.ACCENT, 8, HORIZONTAL_ALIGNMENT_LEFT))
	for t in [["apostle", "사도"], ["artifact", "아티팩트"], ["synergy", "시너지"]]:
		var b := UI.button(t[1], 24, Vector2(150, 60))
		var key: String = t[0]
		b.pressed.connect(func(): _set_tab(key))
		top.add_child(b)
		_tab_btns[key] = b
	_search = LineEdit.new()
	_search.placeholder_text = "이름 검색 (초성 가능: ㅇㄹㅍ)"
	_search.custom_minimum_size = Vector2(0, 60)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(t):
		query = t.strip_edges()
		_rebuild())
	top.add_child(_search)
	_sort_btn = UI.button("", 20, Vector2(150, 60))
	_sort_btn.pressed.connect(func():
		sort_mode = "name" if sort_mode == "cost" else "cost"
		_rebuild())
	top.add_child(_sort_btn)
	var close := UI.button("닫기", 22, Vector2(120, 60), Color("6b3535"))
	close.pressed.connect(queue_free)
	top.add_child(close)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	root.add_child(body)
	var fpanel := UI.panel()
	fpanel.custom_minimum_size.x = 330
	body.add_child(fpanel)
	var fscroll := ScrollContainer.new()
	fscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	fpanel.add_child(fscroll)
	_filters_box = VBoxContainer.new()
	_filters_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filters_box.add_theme_constant_override("separation", 8)
	fscroll.add_child(_filters_box)

	var center := UI.panel(Color("1c1f2e"))
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	var cv := VBoxContainer.new()
	center.add_child(cv)
	_count = UI.label("", 18, UI.SUB)
	cv.add_child(_count)
	var gscroll := ScrollContainer.new()
	gscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cv.add_child(gscroll)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	gscroll.add_child(_grid)

	var dpanel := UI.panel()
	dpanel.custom_minimum_size.x = 470
	body.add_child(dpanel)
	var dscroll := ScrollContainer.new()
	dscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dpanel.add_child(dscroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 6)
	dscroll.add_child(_detail)
	_set_tab("apostle")


func _set_tab(t: String) -> void:
	tab = t
	picked.clear()
	for k in _tab_btns:
		var on: bool = k == t
		_tab_btns[k].add_theme_stylebox_override("normal", UI.box(UI.ACCENT.darkened(0.55) if on else UI.PANEL_LIGHT, 12, UI.ACCENT if on else UI.PANEL_LIGHT.lightened(0.18), 2))
	_search.visible = t != "synergy"
	_sort_btn.visible = t != "synergy"
	_build_filters()
	_rebuild()
	UI.clear(_detail)
	_detail.add_child(UI.wrap_label("항목을 누르면 자세한 정보가 여기에 나옵니다.", 18))


func _build_filters() -> void:
	UI.clear(_filters_box)
	var defs: Array = FILTERS if tab == "apostle" else (ART_FILTERS if tab == "artifact" else [])
	if defs.is_empty():
		_filters_box.add_child(UI.wrap_label("시너지를 누르면 단계별 효과와 해당 사도가 표시됩니다.", 18))
		return
	var head := HBoxContainer.new()
	_filters_box.add_child(head)
	var t := UI.label("필터", 24, UI.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var reset := UI.button("초기화", 18, Vector2(100, 44))
	reset.pressed.connect(func():
		picked.clear()
		_build_filters()
		_rebuild())
	head.add_child(reset)
	_filters_box.add_child(UI.wrap_label("같은 줄은 '또는', 다른 줄끼리는 '그리고'", 15))
	for f in defs:
		_filters_box.add_child(UI.label(f[1], 19, UI.SUB))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		_filters_box.add_child(flow)
		for val in f[2]:
			var on: bool = picked.get(f[0], {}).has(val)
			var col := _filter_color(f[0], val)
			var b := UI.button(val, 18, Vector2(0, 46), col.darkened(0.45) if on else UI.BG2)
			b.add_theme_stylebox_override("normal", UI.box(col.darkened(0.45) if on else UI.BG2, 10, col if on else UI.LINE, 2))
			var key: String = f[0]
			var value: String = val
			b.pressed.connect(func():
				var d: Dictionary = picked.get(key, {})
				if d.has(value):
					d.erase(value)
				else:
					d[value] = true
				picked[key] = d
				_build_filters()
				_rebuild())
			flow.add_child(b)


func _filter_color(key: String, val: String) -> Color:
	match key:
		"pers":
			return UI.PERS_COLOR.get(val, Color.GRAY)
		"cost":
			return UI.COST_COLOR[int(val) - 1]
		"grade":
			return UI.GRADE_COLOR[{"일반": "common", "고급": "advanced", "희귀": "rare", "전설": "legend"}[val]]
		"eldyne":
			return Color("e0b84f")
	return Color("8fb7ff")


# ─────────────────────────────── 검색 ───────────────────────────────

static func chosung(s: String) -> String:
	var out := ""
	for i in s.length():
		var c := s.unicode_at(i)
		if c >= 0xAC00 and c <= 0xD7A3:
			out += CHO[(c - 0xAC00) / 588]
		else:
			out += s[i]
	return out


static func _is_jamo_only(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if not (c >= 0x3131 and c <= 0x314E) and s[i] != " ":
			return false
	return s != ""


static func matches(name: String, q: String) -> bool:
	if q == "":
		return true
	var n := name.replace(" ", "").to_lower()
	var qq := q.replace(" ", "").to_lower()
	if n.find(qq) >= 0:
		return true
	if _is_jamo_only(qq):
		return chosung(n).find(qq) >= 0
	return false


func _pick_ok(key: String, values: Array) -> bool:
	var d: Dictionary = picked.get(key, {})
	if d.is_empty():
		return true
	for v in values:
		if d.has(v):
			return true
	return false


# ─────────────────────────────── 목록 ───────────────────────────────

func _rebuild() -> void:
	UI.clear(_grid)
	_sort_btn.text = "정렬: 코스트" if sort_mode == "cost" else "정렬: 이름"
	match tab:
		"apostle":
			_list_apostles()
		"artifact":
			_list_artifacts()
		_:
			_list_synergies()


func _list_apostles() -> void:
	_grid.columns = 6
	var ids := []
	for aid in GameData.roster:
		var a := GameData.apostle(aid)
		if not matches(a["name"], query) and not matches(a.get("name_en", ""), query):
			continue
		if not _pick_ok("cost", [str(GameData.cost_of[aid])]):
			continue
		if not _pick_ok("pers", [a["personality"]] + a.get("personality_options", [])):
			continue
		if not _pick_ok("race", [a["race"]]):
			continue
		if not _pick_ok("eldyne", ["엘다인"] if a.get("eldyne", false) else []):
			continue
		if not _pick_ok("row", [GameData.ROW_NAME[a["row"]]]):
			continue
		if not _pick_ok("role", [GameData.ROLE_NAME[a["role"]]]):
			continue
		if not _pick_ok("dmg", [GameData.DAMAGE_NAME[a["damage"]]]):
			continue
		ids.append(aid)
	if sort_mode == "cost":
		ids.sort_custom(func(x, y):
			if GameData.cost_of[x] != GameData.cost_of[y]:
				return GameData.cost_of[x] < GameData.cost_of[y]
			return GameData.apostle(x)["name"] < GameData.apostle(y)["name"])
	else:
		ids.sort_custom(func(x, y): return GameData.apostle(x)["name"] < GameData.apostle(y)["name"])
	_count.text = "사도 %d / %d명" % [ids.size(), GameData.roster.size()]
	for aid in ids:
		var a := GameData.apostle(aid)
		var t := UnitTile.new(Vector2(150, 150))
		t.set_unit({"aid": aid}, "%s · %s" % [a["personality"], a["race"]], UI.cost_color(aid))
		t.set_badge("%dG" % GameData.cost_of[aid], UI.cost_color(aid).lightened(0.3))
		if a.get("eldyne", false):
			t.set_corner("엘다인", Color("e0b84f"))
		var id: String = aid
		t.pressed.connect(func(): _show_apostle(id))
		_grid.add_child(t)
	if ids.is_empty():
		_grid.add_child(UI.label("조건에 맞는 사도가 없습니다", 20, UI.SUB))


func _show_apostle(aid: String) -> void:
	UI.clear(_detail)
	Info.apostle(_detail, {"aid": aid, "star": 3, "arts": [], "pers": ""}, Callable(), -1, false)
	var name: String = GameData.apostle(aid)["name"]
	var favs := []
	for id in GameData.artifacts:
		if GameData.artifact(id).get("owner", "") == name:
			favs.append(id)
	Info.section(_detail, "애착 아티팩트")
	if favs.is_empty():
		_detail.add_child(UI.label("없음", 17, UI.SUB))
	for id in favs:
		var b := UI.artifact_button(id, Vector2(0, 58), 18)
		var art_id: String = id
		b.pressed.connect(func(): _show_artifact(art_id))
		_detail.add_child(b)
	_detail.add_child(UI.label("※ 도감에서는 3성 기준(어사이드 전부 표시)", 15, UI.SUB))


func _list_artifacts() -> void:
	_grid.columns = 3
	var order: Array = GameData.balance["grade_order"]
	var ids := []
	for id in GameData.artifacts:
		var a := GameData.artifact(id)
		if not matches(a["name"], query):
			continue
		if not _pick_ok("grade", [GameData.grade_name(a["grade"])]):
			continue
		var kinds := []
		if a.get("owner", "") != "":
			kinds.append("애착")
		if a.get("region", "") == "global":
			kinds.append("글로벌 전용")
		if not a.get("fx", []).is_empty():
			kinds.append("부가 효과 있음")
		if not _pick_ok("kind", kinds):
			continue
		ids.append(id)
	if sort_mode == "cost":
		ids.sort_custom(func(x, y):
			var gx := order.find(GameData.artifact(x)["grade"])
			var gy := order.find(GameData.artifact(y)["grade"])
			if gx != gy:
				return gx > gy
			return GameData.artifact(x)["name"] < GameData.artifact(y)["name"])
	else:
		ids.sort_custom(func(x, y): return GameData.artifact(x)["name"] < GameData.artifact(y)["name"])
	_count.text = "아티팩트 %d / %d종" % [ids.size(), GameData.artifacts.size()]
	for id in ids:
		var b := UI.artifact_button(id, Vector2(300, 72), 18)
		var art_id: String = id
		b.pressed.connect(func(): _show_artifact(art_id))
		_grid.add_child(b)


func _show_artifact(id: String) -> void:
	UI.clear(_detail)
	Info.artifact(_detail, id, "")


func _list_synergies() -> void:
	_grid.columns = 3
	_count.text = "시너지 %d종" % GameData.synergies.size()
	for name in GameData.synergies:
		var syn: Dictionary = GameData.synergies[name]
		var col: Color = UI.PERS_COLOR.get(name, Color("e0b84f") if name == "엘다인" else Color("8fb7ff"))
		var tiers := []
		for t in syn["tiers"]:
			tiers.append(str(int(t)))
		var b := UI.button("%s\n%s  (%s)" % [name, syn.get("desc", ""), "/".join(tiers)], 18, Vector2(300, 96), col.darkened(0.6))
		b.add_theme_stylebox_override("normal", UI.box(col.darkened(0.65), 12, col, 2))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var n: String = name
		b.pressed.connect(func():
			UI.clear(_detail)
			Info.synergy(_detail, n, 0, []))
		_grid.add_child(b)
