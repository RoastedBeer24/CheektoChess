class_name GameScreen
extends Control
## 게임 화면: 상단 정보 / 플레이어·시너지 / 보드·전투 / 상세·보관함 / 대기석·상점.
## 조작: 누르기→누르기, 또는 끌어다 놓기. 터치와 마우스 모두 같은 방식.

signal toast_requested(msg: String)

const STAT_NAME := {
	"hp": "최대 HP", "atk": "공격력", "patk": "물리 공격력", "matk": "마법 공격력", "def": "방어력",
	"pdef": "물리 방어력", "mdef": "마법 방어력", "aspd": "공격 속도", "crit": "치명타", "critdmg": "치명 피해",
	"critres": "치명타 저항", "critdmgres": "치명 피해 저항", "heal_out": "치유량", "heal_in": "HP 회복량",
}
const PHASE_NAME := {"prep": "준비", "battle": "전투", "result": "결과", "over": "게임 종료"}
const PHASE_COLOR := {"prep": Color("2f6b4a"), "battle": Color("8a3a3a"), "result": Color("4a4f6b"), "over": Color("4a4f6b")}

## 유닛을 끌어다 놓아 팔 수 있는 버튼
class SellZone extends Button:
	signal unit_dropped(from_loc: Dictionary)
	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return typeof(data) == TYPE_DICTIONARY and data.has("unit_from")
	func _drop_data(_at: Vector2, data: Variant) -> void:
		unit_dropped.emit(data["unit_from"])

var sel := {}                 # {"unit": loc} 또는 {"art": uid}
var merge_mode := false
var _last_phase := ""
var _last_round := -1
var _phase_total := 1.0
var _offer_hidden := false
var _overlay_kind := ""

var _round_lbl: Label
var _phase_pill: PanelContainer
var _phase_lbl: Label
var _time_bar: ProgressBar
var _hp_lbl: Label
var _hp_bar: ProgressBar
var _gold_lbl: Label
var _lvl_lbl: Label
var _xp_bar: ProgressBar
var _ready_btn: Button
var _offer_btn: Button
var _players_box: VBoxContainer
var _syn_box: VBoxContainer
var _board_root: Control
var _board_info: Label
var _board_tiles := {}
var _battle_view: BattleView
var _banner: Label
var _detail_box: VBoxContainer
var _inv_grid: GridContainer
var _inv_title: Label
var _bench_tiles: Array = []
var _bench_lbl: Label
var _shop_tiles: Array = []
var _reroll_btn: Button
var _xp_btn: Button
var _sell_btn: SellZone
var _merge_btn: Button
var _overlay: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	App.session.state_changed.connect(refresh)
	refresh()


func me() -> Dictionary:
	return App.session.state.get("players", {}).get(App.session.my_pid, {})


func B() -> Dictionary:
	return GameData.balance


func _toast(msg: String) -> void:
	toast_requested.emit(msg)


# ─────────────────────────────── 화면 구성 ───────────────────────────────

func _build() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 12
	root.offset_right = -12
	root.offset_top = 10
	root.offset_bottom = -10
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	root.add_child(_build_top())

	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 10)
	root.add_child(mid)
	mid.add_child(_build_left())
	var center := UI.panel(Color("1c1f2e"), 16, UI.LINE, 2)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(center)
	var cstack := Control.new()
	center.add_child(cstack)
	_board_root = _build_board()
	_board_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	cstack.add_child(_board_root)
	_battle_view = BattleView.new()
	_battle_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_battle_view.visible = false
	cstack.add_child(_battle_view)
	_banner = UI.outlined("", 64, UI.ACCENT, 14)
	_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0.0
	cstack.add_child(_banner)
	mid.add_child(_build_right())

	root.add_child(_build_bench())
	root.add_child(_build_shop())

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)


func _build_top() -> Control:
	var top := UI.panel(UI.PANEL, 14)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	top.add_child(h)
	_round_lbl = UI.label("", 30, UI.ACCENT)
	h.add_child(_round_lbl)
	var pv := VBoxContainer.new()
	pv.custom_minimum_size.x = 300
	pv.add_theme_constant_override("separation", 4)
	h.add_child(pv)
	_phase_pill = UI.panel(PHASE_COLOR["prep"], 10)
	_phase_lbl = UI.label("", 22, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_phase_pill.add_child(_phase_lbl)
	pv.add_child(_phase_pill)
	_time_bar = UI.bar(UI.ACCENT, 8)
	pv.add_child(_time_bar)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	var hpv := VBoxContainer.new()
	hpv.custom_minimum_size.x = 200
	hpv.add_theme_constant_override("separation", 2)
	h.add_child(hpv)
	_hp_lbl = UI.label("", 22, UI.GOOD)
	hpv.add_child(_hp_lbl)
	_hp_bar = UI.bar(UI.GOOD, 10)
	hpv.add_child(_hp_bar)
	var gold := UI.panel(Color("4a3a12"), 10, UI.ACCENT, 2)
	_gold_lbl = UI.label("", 26, UI.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_gold_lbl.custom_minimum_size.x = 120
	gold.add_child(_gold_lbl)
	h.add_child(gold)
	var lv := VBoxContainer.new()
	lv.custom_minimum_size.x = 200
	lv.add_theme_constant_override("separation", 2)
	h.add_child(lv)
	_lvl_lbl = UI.label("", 22)
	lv.add_child(_lvl_lbl)
	_xp_bar = UI.bar(UI.BLUE, 10)
	lv.add_child(_xp_bar)
	_offer_btn = UI.button("아티팩트 선택", 22, Vector2(190, 58), Color("8a5a1f"))
	_offer_btn.pressed.connect(func():
		_offer_hidden = false
		refresh())
	h.add_child(_offer_btn)
	_ready_btn = UI.button("준비 완료", 22, Vector2(160, 58), Color("2f6b4a"))
	_ready_btn.pressed.connect(func(): App.session.submit({"t": "ready", "on": not me().get("ready", false)}))
	h.add_child(_ready_btn)
	var quit := UI.button("나가기", 22, Vector2(110, 58), Color("6b3535"))
	quit.pressed.connect(_confirm_quit)
	h.add_child(quit)
	return top


func _build_left() -> Control:
	var left := UI.panel()
	left.custom_minimum_size.x = 340
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var lv := VBoxContainer.new()
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_theme_constant_override("separation", 8)
	scroll.add_child(lv)
	lv.add_child(UI.label("플레이어", 24, UI.ACCENT))
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 6)
	lv.add_child(_players_box)
	lv.add_child(UI.hsep())
	lv.add_child(UI.label("시너지", 24, UI.ACCENT))
	_syn_box = VBoxContainer.new()
	_syn_box.add_theme_constant_override("separation", 6)
	lv.add_child(_syn_box)
	return left


func _build_right() -> Control:
	var right := UI.panel()
	right.custom_minimum_size.x = 450
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right.add_child(rv)
	var dscroll := ScrollContainer.new()
	dscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(dscroll)
	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_theme_constant_override("separation", 6)
	dscroll.add_child(_detail_box)
	rv.add_child(UI.hsep())
	var invh := HBoxContainer.new()
	rv.add_child(invh)
	_inv_title = UI.label("보관함", 24, UI.ACCENT)
	_inv_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	invh.add_child(_inv_title)
	_merge_btn = UI.button("합성", 20, Vector2(120, 48), Color("5a3f86"))
	_merge_btn.pressed.connect(_on_merge_pressed)
	invh.add_child(_merge_btn)
	var iscroll := ScrollContainer.new()
	iscroll.custom_minimum_size.y = 210
	iscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(iscroll)
	_inv_grid = GridContainer.new()
	_inv_grid.columns = 2
	_inv_grid.add_theme_constant_override("h_separation", 6)
	_inv_grid.add_theme_constant_override("v_separation", 6)
	_inv_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	iscroll.add_child(_inv_grid)
	return right


func _build_board() -> Control:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 10)
	_board_info = UI.label("", 22, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_board_info)
	var heads := HBoxContainer.new()
	heads.alignment = BoxContainer.ALIGNMENT_CENTER
	heads.add_theme_constant_override("separation", 14)
	v.add_child(heads)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	var cc := CenterContainer.new()
	cc.add_child(grid)
	v.add_child(cc)
	# 화면 왼쪽부터 후열 · 중열 · 전열 (오른쪽이 적 방향)
	for r in [2, 1, 0]:
		var chip := UI.panel(UI.PANEL_LIGHT, 10)
		chip.custom_minimum_size.x = 170
		chip.add_child(UI.label(GameData.ROW_NAME[GameData.ROWS[r]], 22, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
		heads.add_child(chip)
	for s in int(B()["board_slots"]):
		for r in [2, 1, 0]:
			var t := UnitTile.new(Vector2(170, 170))
			var key := Match.key_of(r, s)
			t.loc = {"board": key}
			var loc: Dictionary = t.loc
			t.pressed.connect(func(): _on_tile(loc))
			t.dropped.connect(_on_drop)
			grid.add_child(t)
			_board_tiles[key] = t
	v.add_child(UI.label("적 방향  ▶▶", 20, UI.SUB, HORIZONTAL_ALIGNMENT_RIGHT))
	return v


func _build_bench() -> Control:
	var bench := HBoxContainer.new()
	bench.add_theme_constant_override("separation", 8)
	bench.alignment = BoxContainer.ALIGNMENT_CENTER
	_bench_lbl = UI.label("대기석", 22, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER)
	_bench_lbl.custom_minimum_size.x = 110
	bench.add_child(_bench_lbl)
	for i in int(B()["bench_size"]):
		var t := UnitTile.new(Vector2(124, 124))
		t.loc = {"bench": i}
		var loc: Dictionary = t.loc
		t.pressed.connect(func(): _on_tile(loc))
		t.dropped.connect(_on_drop)
		bench.add_child(t)
		_bench_tiles.append(t)
	_sell_btn = SellZone.new()
	_sell_btn.text = "판매"
	_sell_btn.custom_minimum_size = Vector2(170, 124)
	_sell_btn.add_theme_font_size_override("font_size", 22)
	for st in ["normal", "hover", "pressed", "disabled"]:
		_sell_btn.add_theme_stylebox_override(st, UI.box(Color("5a2b2b") if st != "disabled" else Color("3a2525"), 14, Color("b55a5a"), 2))
	_sell_btn.focus_mode = Control.FOCUS_NONE
	_sell_btn.pressed.connect(_on_sell)
	_sell_btn.unit_dropped.connect(func(from):
		App.session.submit({"t": "sell", "loc": from})
		sel = {}
		refresh())
	bench.add_child(_sell_btn)
	return bench


func _build_shop() -> Control:
	var shop := HBoxContainer.new()
	shop.add_theme_constant_override("separation", 8)
	shop.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in int(B()["shop_size"]):
		var t := UnitTile.new(Vector2(226, 124))
		var idx := i
		t.pressed.connect(func(): App.session.submit({"t": "buy", "i": idx}))
		shop.add_child(t)
		_shop_tiles.append(t)
	_reroll_btn = UI.button("새로고침\n%d골드" % int(B()["reroll_cost"]), 22, Vector2(170, 124), Color("2f4f86"))
	_reroll_btn.pressed.connect(func(): App.session.submit({"t": "reroll"}))
	shop.add_child(_reroll_btn)
	_xp_btn = UI.button("경험치 +%d\n%d골드" % [int(B()["xp_amount"]), int(B()["xp_cost"])], 22, Vector2(170, 124), Color("4f3586"))
	_xp_btn.pressed.connect(func(): App.session.submit({"t": "buy_xp"}))
	shop.add_child(_xp_btn)
	return shop


# ─────────────────────────────── 갱신 ───────────────────────────────

func _process(_delta: float) -> void:
	var st := App.session.state
	if st.is_empty():
		return
	var phase: String = st.get("phase", "")
	var left := float(st.get("phase_end", 0.0))
	_phase_lbl.text = "%s  %d초" % [PHASE_NAME.get(phase, phase), ceili(left)] if phase != "over" else "게임 종료"
	_time_bar.value = 100.0 * left / maxf(1.0, _phase_total)


func refresh() -> void:
	var st := App.session.state
	if st.is_empty():
		return
	var p := me()
	var phase: String = st["phase"]
	if phase != _last_phase or int(st["round"]) != _last_round:
		_on_phase_changed(phase, int(st["round"]))
	_round_lbl.text = "라운드 %d" % int(st["round"])
	_phase_pill.add_theme_stylebox_override("panel", UI.box(PHASE_COLOR.get(phase, UI.PANEL_LIGHT), 10))
	if not p.is_empty():
		_hp_lbl.text = "♥ %d" % maxi(0, int(p["hp"]))
		_hp_bar.value = 100.0 * maxi(0, int(p["hp"])) / float(B()["player_hp"])
		_gold_lbl.text = "%d G" % int(p["gold"])
		var maxed := int(p["level"]) >= int(B()["max_level"])
		var need := 0 if maxed else int(B()["xp_to_next"][int(p["level"]) - 1])
		_lvl_lbl.text = "Lv %d  %s" % [int(p["level"]), "MAX" if maxed else "%d/%d" % [int(p["xp"]), need]]
		_xp_bar.value = 100.0 if maxed else 100.0 * int(p["xp"]) / maxf(1.0, need)
		_ready_btn.text = "준비 취소" if p.get("ready", false) else "준비 완료"
	var prep: bool = phase == "prep" and p.get("alive", false)
	var gold := int(p.get("gold", 0))
	_ready_btn.disabled = not prep
	_reroll_btn.disabled = not prep or gold < int(B()["reroll_cost"])
	_xp_btn.disabled = not prep or gold < int(B()["xp_cost"]) or int(p.get("level", 1)) >= int(B()["max_level"])
	_sell_btn.disabled = not prep
	_merge_btn.disabled = not prep
	_offer_btn.visible = prep and not p.get("art_offer", {}).is_empty() and _offer_hidden
	_board_root.visible = phase != "battle"
	_battle_view.visible = phase == "battle"
	_refresh_players()
	_refresh_synergy()
	_refresh_board()
	_refresh_bench_shop()
	_refresh_inventory()
	_refresh_detail()
	_refresh_overlay()


func _on_phase_changed(phase: String, rnd: int) -> void:
	var st := App.session.state
	if phase == "prep":
		_offer_hidden = false
	sel = {}
	merge_mode = false
	_last_phase = phase
	_last_round = rnd
	_phase_total = maxf(1.0, float(st.get("phase_end", 1.0)))
	match phase:
		"prep":
			var art := " · 아티팩트 획득!" if not me().get("art_offer", {}).is_empty() else ""
			_show_banner("라운드 %d%s" % [rnd, art], UI.ACCENT)
		"battle":
			_start_battle_view()
		"result":
			_show_result_banner()


func _show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	var tw := create_tween()
	_banner.modulate.a = 0.0
	tw.tween_property(_banner, "modulate:a", 1.0, 0.2)
	tw.tween_interval(1.1)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.5)


func _show_result_banner() -> void:
	var st := App.session.state
	for bt in st.get("battles", []):
		var side := -1
		if bt["a"] == App.session.my_pid:
			side = 0
		elif bt["b"] == App.session.my_pid:
			side = 1
		if side < 0:
			continue
		var w := int(bt["winner"])
		var base := int(B()["damage_base"]) + int(st["round"]) / int(B()["damage_per_round_div"])
		if w == side:
			_show_banner("승리!  +1 골드", UI.GOOD)
		elif w == -1:
			_show_banner("무승부  ♥ -%d" % base, UI.SUB)
		else:
			_show_banner("패배  ♥ -%d" % (base + int(bt["survivors"])), UI.BAD)
		return


func _refresh_players() -> void:
	UI.clear(_players_box)
	var list: Array = App.session.state["players"].values()
	list.sort_custom(func(a, b):
		if a["alive"] != b["alive"]:
			return a["alive"]
		return a["hp"] > b["hp"] if a["alive"] else a["place"] < b["place"])
	var rank := 0
	for p in list:
		rank += 1
		var mine: bool = p["id"] == App.session.my_pid
		var row := UI.panel(Color(UI.ACCENT, 0.12) if mine else UI.BG2, 8, UI.ACCENT if mine else Color.TRANSPARENT, 2 if mine else 0)
		var sb: StyleBoxFlat = row.get_theme_stylebox("panel")
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		row.add_child(h)
		var name_l := UI.label("%d %s" % [rank, p["name"]], 19, UI.ACCENT if mine else (UI.TEXT if p["alive"] else UI.SUB))
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.clip_text = true
		h.add_child(name_l)
		if not p["alive"]:
			h.add_child(UI.label("%d위" % int(p["place"]), 17, UI.SUB))
			row.modulate.a = 0.55
		else:
			if not p["connected"]:
				h.add_child(UI.label("끊김", 15, UI.BAD))
			elif p.get("ready", false) and App.session.state["phase"] == "prep" and not p["bot"]:
				h.add_child(UI.label("준비", 15, UI.GOOD))
			h.add_child(UI.label("Lv%d" % int(p["level"]), 16, UI.SUB))
			var hb := UI.bar(UI.GOOD if int(p["hp"]) > 30 else UI.BAD, 8)
			hb.value = 100.0 * maxi(0, int(p["hp"])) / float(B()["player_hp"])
			hb.custom_minimum_size.x = 60
			hb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(hb)
			var hl := UI.label("%d" % maxi(0, int(p["hp"])), 17, UI.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
			hl.custom_minimum_size.x = 34
			h.add_child(hl)
		_players_box.add_child(row)


func _refresh_synergy() -> void:
	UI.clear(_syn_box)
	var p := me()
	if p.is_empty():
		return
	var specs := []
	for k in p["board"]:
		specs.append(p["board"][k])
	var counts := Rules.count_traits(specs)
	var tiers := Rules.active_tiers(counts)
	var names := counts.keys()
	names.sort_custom(func(a, b): return tiers.get(a, 0) * 100 + counts[a] > tiers.get(b, 0) * 100 + counts[b])
	for n in names:
		var syn: Dictionary = GameData.synergies.get(n, {})
		if syn.is_empty():
			continue
		var active: int = tiers.get(n, 0)
		var col: Color = UI.PERS_COLOR.get(n, Color("e0b84f") if n == "엘다인" else Color("8fb7ff"))
		var row := UI.panel(col.darkened(0.7) if active > 0 else UI.BG2, 10, col if active > 0 else UI.LINE, 2)
		row.tooltip_text = syn.get("desc", "")
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		row.add_child(v)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		v.add_child(h)
		var cnt := UI.label(str(counts[n]), 22, col if active > 0 else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER)
		cnt.custom_minimum_size.x = 28
		h.add_child(cnt)
		var nl := UI.label(n, 21, UI.TEXT if active > 0 else UI.SUB)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nl)
		var tl: Array = syn["tiers"]
		for i in tl.size():
			h.add_child(UI.label(str(int(tl[i])), 18, col if i < active else Color(1, 1, 1, 0.3)))
		if active > 0:
			v.add_child(UI.wrap_label(syn.get("desc", ""), 15, UI.SUB))
		_syn_box.add_child(row)
	if names.is_empty():
		_syn_box.add_child(UI.wrap_label("보드에 사도를 올리면 시너지가 표시됩니다.", 18))


func _refresh_board() -> void:
	var p := me()
	var prep: bool = App.session.state.get("phase", "") == "prep" and p.get("alive", false)
	var su = _unit_at(sel["unit"]) if sel.has("unit") else null
	for key in _board_tiles:
		var t: UnitTile = _board_tiles[key]
		var row: int = Match._parse_key(key)[0]
		var u = p.get("board", {}).get(key)
		if u == null:
			t.set_empty(GameData.ROW_NAME[GameData.ROWS[row]])
			t.set_highlight(su != null and GameData.can_place(su["aid"], row))
		else:
			t.set_unit(u, _pers_tag(u))
			t.set_highlight(false)
			t.draggable = prep
		t.set_selected(sel.get("unit", {}) == {"board": key})
	_board_info.text = "보드 %d / %d   (레벨만큼 올릴 수 있음)" % [p.get("board", {}).size(), int(p.get("level", 1))]


func _pers_tag(u: Dictionary) -> String:
	var a := GameData.apostle(u["aid"])
	var p: String = a.get("personality", "")
	if p == "공명" or p == "이면":
		return "%s→%s" % [p, u["pers"]] if u["pers"] != "" else p
	return "%s · %s" % [p, a.get("race", "")]


func _owned_count(p: Dictionary, aid: String) -> int:
	var n := 0
	for u in p.get("bench", []):
		if u != null and u["aid"] == aid and int(u["star"]) == 1:
			n += 1
	for k in p.get("board", {}):
		if p["board"][k]["aid"] == aid and int(p["board"][k]["star"]) == 1:
			n += 1
	return n


func _refresh_bench_shop() -> void:
	var p := me()
	var prep: bool = App.session.state.get("phase", "") == "prep" and p.get("alive", false)
	var bench: Array = p.get("bench", [])
	var used := 0
	for i in _bench_tiles.size():
		var t: UnitTile = _bench_tiles[i]
		var u = bench[i] if i < bench.size() else null
		if u == null:
			t.set_empty("")
		else:
			used += 1
			t.set_unit(u, _pers_tag(u))
			t.draggable = prep
		t.set_selected(sel.get("unit", {}) == {"bench": i})
	_bench_lbl.text = "대기석\n%d/%d" % [used, bench.size()]
	var su = _unit_at(sel["unit"]) if sel.has("unit") else null
	_sell_btn.text = "판매\n+%d골드" % _sell_value(su) if su != null else "판매\n(끌어다 놓기)"
	var shop: Array = p.get("shop", [])
	var gold := int(p.get("gold", 0))
	for i in _shop_tiles.size():
		var t: UnitTile = _shop_tiles[i]
		var aid: String = shop[i] if i < shop.size() else ""
		if aid == "":
			t.set_empty("")
			t.disabled = true
			continue
		var a := GameData.apostle(aid)
		var cost: int = GameData.cost_of[aid]
		var traits: String = "%s · %s · %s%s" % [a["personality"], a["race"], GameData.ROW_NAME[a["row"]], " · 엘다인" if a.get("eldyne", false) else ""]
		t.set_unit({"aid": aid}, traits, UI.cost_color(aid))
		t.set_badge("%dG" % cost, UI.cost_color(aid).lightened(0.3))
		var owned := _owned_count(p, aid)
		if owned > 0:
			t._stars.text = "보유 %d/3" % owned
		t.set_dim(gold < cost)
		t.disabled = not prep


func _sell_value(u: Dictionary) -> int:
	return GameData.cost_of.get(u["aid"], 1) * int(pow(3, int(u["star"]) - 1))


func _refresh_inventory() -> void:
	UI.clear(_inv_grid)
	var p := me()
	var inv: Array = p.get("inv", [])
	for a in inv:
		var b := UI.artifact_button(a["id"], Vector2(205, 62), 16, sel.get("art", -1) == int(a["uid"]))
		var uid := int(a["uid"])
		b.pressed.connect(func(): _on_art(uid))
		_inv_grid.add_child(b)
	if inv.is_empty():
		_inv_grid.add_child(UI.label("비어 있음", 18, UI.SUB))
	_inv_title.text = "보관함  %d" % inv.size()
	_merge_btn.text = "합성 취소" if merge_mode else "합성"


# ─────────────────────────────── 상세 정보 ───────────────────────────────

func _refresh_detail() -> void:
	UI.clear(_detail_box)
	if sel.has("unit"):
		var u = _unit_at(sel["unit"])
		if u != null:
			_detail_unit(u)
			return
	if sel.has("art"):
		var where := _find_art(int(sel["art"]))
		if not where.is_empty():
			_detail_art(where["art"]["id"], where.has("inv"))
			return
	_detail_box.add_child(UI.label("도움말", 26, UI.ACCENT))
	for line in [
		"상점 카드를 누르면 구매합니다. 테두리 색은 코스트(회색 1 → 금색 5).",
		"사도를 누른 뒤 빈칸을 누르거나, 끌어다 놓아 이동합니다.",
		"사도는 자기 열에만 놓을 수 있습니다. 놓을 수 있는 칸이 빛납니다.",
		"같은 사도 3명이 모이면 자동으로 ★ 합성. 합성·판매 시 아티팩트는 보관함으로.",
		"보관함 아티팩트를 누르고 사도를 누르면 장착 (최대 3개, 임의 해제 불가).",
		"아티팩트를 고르고 [합성] → 같은 등급 다른 아티팩트를 누르면 다음 등급 무작위 1개.",
		"공명·이면 사도는 보드에 올릴 때 성격을 고릅니다.",
		"판매: 사도를 고르고 [판매], 또는 판매 칸으로 끌어다 놓기.",
	]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(UI.label("•", 18, UI.ACCENT))
		var l := UI.wrap_label(line, 18, UI.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		_detail_box.add_child(row)


func _section(title: String) -> void:
	var l := UI.label(title, 20, UI.ACCENT)
	_detail_box.add_child(UI.hsep())
	_detail_box.add_child(l)


func _detail_unit(u: Dictionary) -> void:
	var aid: String = u["aid"]
	var a := GameData.apostle(aid)
	var star := int(u.get("star", 1))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_detail_box.add_child(head)
	var pf := UI.panel(UI.pers_color(aid, u.get("pers", "")).darkened(0.55), 12, UI.pers_color(aid, u.get("pers", "")), 3)
	pf.add_child(UI.tex_rect(UI.portrait(aid), Vector2(112, 112), true))
	head.add_child(pf)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	hv.add_child(UI.label(a["name"], 30, UI.TEXT))
	hv.add_child(UI.label(UI.stars(star) + "  ·  %d골드" % GameData.cost_of.get(aid, 1), 22, UI.ACCENT))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	_detail_box.add_child(chips)
	var pers: String = a["personality"] + (" → " + u["pers"] if u.get("pers", "") != "" else "")
	chips.add_child(UI.chip(pers, UI.pers_color(aid, u.get("pers", ""))))
	chips.add_child(UI.chip(a["race"], Color("8fb7ff")))
	if a.get("eldyne", false):
		chips.add_child(UI.chip("엘다인", Color("e0b84f")))
	chips.add_child(UI.chip(GameData.ROW_NAME[a["row"]], Color("c0c4d6")))
	chips.add_child(UI.chip(GameData.ROLE_NAME[a["role"]], Color("c0c4d6")))
	chips.add_child(UI.chip(GameData.DAMAGE_NAME[a["damage"]], Color("ff9f6b") if a["damage"] == "physical" else Color("7fb8ff")))
	var bs := Rules.base_stats(aid, star)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	_detail_box.add_child(grid)
	for pair in [["HP", "%d" % bs["hp"]], ["공격력", "%d" % bs["atk"]], ["방어력", "%d" % bs["def"]], ["공속", "%.2f" % bs["aspd"]]]:
		grid.add_child(UI.label(pair[0], 17, UI.SUB))
		grid.add_child(UI.label(pair[1], 19, UI.TEXT))
	_section("스킬")
	_detail_box.add_child(UI.wrap_label("현재는 역할별 공통 스킬로 동작합니다 (원작 스킬 구현 예정).", 15, UI.SUB))
	for k in ["fresh", "senior", "passive"]:
		var sk: Dictionary = a.get("skills", {}).get(k, {})
		if sk.is_empty():
			continue
		var kn: String = {"fresh": "저학년 · SP", "senior": "고학년 · 재사용 대기", "passive": "패시브"}[k]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		h.add_child(UI.chip(kn, Color("9fd3ff") if k == "fresh" else (UI.ACCENT if k == "senior" else Color("c0c4d6")), 15))
		var nl := UI.label(sk["name"], 19, UI.TEXT)
		nl.clip_text = true
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nl)
		_detail_box.add_child(h)
		_detail_box.add_child(UI.wrap_label(sk["desc"], 15))
	_section("어사이드")
	for n in ["1", "2", "3"]:
		var asd: Dictionary = a.get("aside", {}).get(n, {})
		if asd.is_empty():
			continue
		var on := star >= int(n)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		h.add_child(UI.chip("%s성 %s" % [n, "적용" if on else "잠김"], UI.GOOD if on else Color("777b8f"), 15))
		var nl := UI.label(asd["name"], 19, UI.TEXT if on else UI.SUB)
		nl.clip_text = true
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nl)
		_detail_box.add_child(h)
		_detail_box.add_child(UI.wrap_label(asd["desc"], 15, UI.SUB if on else Color(1, 1, 1, 0.35)))
	if a.get("aside", {}).is_empty():
		_detail_box.add_child(UI.label("어사이드 정보 없음", 16, UI.SUB))
	_section("아티팩트  %d / %d" % [u.get("arts", []).size(), int(B()["artifact_slots"])])
	for art in u.get("arts", []):
		var info := GameData.artifact(art["id"])
		var fav := "  ♥애착" if info.get("owner", "") == a["name"] else ""
		var b := UI.artifact_button(art["id"], Vector2(0, 58), 18, sel.get("art", -1) == int(art["uid"]))
		b.text = "%s%s" % [info["name"], fav]
		var uid := int(art["uid"])
		b.pressed.connect(func(): _on_art(uid))
		_detail_box.add_child(b)
	if u.get("arts", []).is_empty():
		_detail_box.add_child(UI.label("보관함의 아티팩트를 누른 뒤 이 사도를 누르면 장착", 16, UI.SUB))
	_detail_box.add_child(UI.label("판매 가격  %d골드" % _sell_value(u), 18, UI.SUB))


func _detail_art(art_id: String, in_inv: bool) -> void:
	var a := GameData.artifact(art_id)
	var col: Color = UI.GRADE_COLOR[a["grade"]]
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	_detail_box.add_child(hb)
	var frame := UI.panel(col.darkened(0.6), 12, col, 3)
	var ic := UI.artifact_icon(art_id)
	if ic != null:
		frame.add_child(UI.tex_rect(ic, Vector2(96, 96)))
	else:
		frame.add_child(UI.label("?", 48, col, HORIZONTAL_ALIGNMENT_CENTER))
		frame.custom_minimum_size = Vector2(120, 120)
	hb.add_child(frame)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(hv)
	var nl := UI.label(a["name"], 26, col)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(nl)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	hv.add_child(chips)
	chips.add_child(UI.chip(GameData.grade_name(a["grade"]), col))
	if a.get("region", "") == "global":
		chips.add_child(UI.chip("글로벌 전용", Color("c0c4d6")))
	chips.add_child(UI.chip("보관함" if in_inv else "장착 중", UI.GOOD if in_inv else Color("c0c4d6")))
	_section("능력치")
	for k in a.get("stats", {}):
		_detail_box.add_child(UI.label("%s  +%s%%" % [STAT_NAME.get(k, k), str(a["stats"][k])], 20, UI.TEXT))
	_section("효과")
	_detail_box.add_child(UI.wrap_label(a.get("text", ""), 18, UI.TEXT))
	if a.get("nostack", false):
		_detail_box.add_child(UI.label("※ 부가 효과는 한 사도에 중첩되지 않음", 15, UI.SUB))
	if a.get("owner", "") != "":
		_section("애착: %s" % a["owner"])
		_detail_box.add_child(UI.wrap_label(a.get("fav", ""), 16))
		_detail_box.add_child(UI.label("※ 애착 효과는 다음 단계에서 구현 예정", 15, UI.SUB))
	_detail_box.add_child(UI.hsep())
	if in_inv:
		_detail_box.add_child(UI.wrap_label("사도를 누르면 장착합니다. [합성]을 누르면 같은 등급 아티팩트와 합칠 수 있습니다.", 16))
	else:
		_detail_box.add_child(UI.wrap_label("장착 중인 아티팩트는 뺄 수 없지만 [합성] 재료로는 쓸 수 있습니다.", 16))


# ─────────────────────────────── 조작 ───────────────────────────────

func _unit_at(loc: Dictionary):
	var p := me()
	if loc.has("bench"):
		var b: Array = p.get("bench", [])
		var i := int(loc["bench"])
		return b[i] if i < b.size() else null
	return p.get("board", {}).get(loc.get("board", ""))


func _find_art(uid: int) -> Dictionary:
	var p := me()
	for a in p.get("inv", []):
		if int(a["uid"]) == uid:
			return {"art": a, "inv": true}
	var units := []
	for u in p.get("bench", []):
		if u != null:
			units.append(u)
	for k in p.get("board", {}):
		units.append(p["board"][k])
	for u in units:
		for a in u["arts"]:
			if int(a["uid"]) == uid:
				return {"art": a, "unit": u}
	return {}


func _is_prep() -> bool:
	return App.session.state.get("phase", "") == "prep" and me().get("alive", false)


func _do_move(from: Dictionary, to: Dictionary) -> void:
	var mover = _unit_at(from)
	if mover == null:
		return
	if to.has("board") and from.has("bench") and not GameData.personality_options(mover["aid"]).is_empty():
		_ask_personality(mover["aid"], func(pers): App.session.submit({"t": "move", "from": from, "to": to, "pers": pers}))
	else:
		App.session.submit({"t": "move", "from": from, "to": to})


func _on_drop(from: Dictionary, to: Dictionary) -> void:
	if not _is_prep():
		return
	sel = {}
	_do_move(from, to)
	refresh()


func _on_tile(loc: Dictionary) -> void:
	var u = _unit_at(loc)
	if not _is_prep():
		# 준비 단계가 아니어도 정보는 볼 수 있다
		sel = {"unit": loc} if u != null else {}
		refresh()
		return
	if sel.has("art"):
		if u != null:
			var where := _find_art(int(sel["art"]))
			if not where.is_empty() and where.has("inv"):
				App.session.submit({"t": "equip", "art": int(sel["art"]), "loc": loc})
				sel = {"unit": loc}
				refresh()
				return
		sel = {"unit": loc} if u != null else {}
		refresh()
		return
	if sel.has("unit"):
		var from: Dictionary = sel["unit"]
		sel = {}
		if from != loc:
			_do_move(from, loc)
		refresh()
		return
	if u != null:
		sel = {"unit": loc}
	refresh()


func _on_art(uid: int) -> void:
	if merge_mode and sel.has("art") and int(sel["art"]) != uid:
		App.session.submit({"t": "art_merge", "a": int(sel["art"]), "b": uid})
		merge_mode = false
		sel = {}
		refresh()
		return
	sel = {"art": uid}
	refresh()


func _on_merge_pressed() -> void:
	if merge_mode:
		merge_mode = false
	elif sel.has("art"):
		merge_mode = true
		_toast("같은 등급의 다른 아티팩트를 누르세요 (장착 중인 것도 가능)")
	else:
		_toast("먼저 합성할 아티팩트를 고르세요")
	refresh()


func _on_sell() -> void:
	if sel.has("unit") and _unit_at(sel["unit"]) != null:
		App.session.submit({"t": "sell", "loc": sel["unit"]})
		sel = {}
		refresh()
	else:
		_toast("팔 사도를 고르거나, 판매 칸으로 끌어다 놓으세요")


# ─────────────────────────────── 팝업 ───────────────────────────────

func _modal(title: String, kind: String = "") -> VBoxContainer:
	UI.clear(_overlay)
	_overlay_kind = kind
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(cc)
	var p := UI.panel(UI.PANEL, 18, UI.LINE, 2)
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	p.add_child(v)
	v.add_child(UI.label(title, 34, UI.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	return v


func _close_modal() -> void:
	UI.clear(_overlay)
	_overlay_kind = ""


func _ask_personality(aid: String, cb: Callable) -> void:
	var v := _modal("%s의 성격을 고르세요" % GameData.apostle(aid)["name"], "pers")
	v.add_child(UI.label("시너지에 이 성격으로 계산됩니다. 바꾸려면 대기석으로 내렸다가 다시 올리세요.", 18, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER))
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 14)
	v.add_child(h)
	for pers in GameData.personality_options(aid):
		var col: Color = UI.PERS_COLOR.get(pers, Color.GRAY)
		var b := UI.button(pers, 30, Vector2(170, 110), col.darkened(0.45))
		var chosen: String = pers
		b.pressed.connect(func():
			_close_modal()
			cb.call(chosen))
		h.add_child(b)
	var cancel := UI.button("취소", 22, Vector2(0, 60))
	cancel.pressed.connect(func():
		_close_modal()
		refresh())
	v.add_child(cancel)


func _refresh_overlay() -> void:
	var st := App.session.state
	var p := me()
	if st["phase"] == "over":
		if _overlay_kind != "over":
			_show_game_over()
		return
	var offer: Dictionary = p.get("art_offer", {})
	if st["phase"] == "prep" and not offer.is_empty() and not _offer_hidden:
		_show_offer(offer)
		return
	if _overlay_kind == "offer" or (_overlay_kind == "pers" and st["phase"] != "prep"):
		_close_modal()


func _show_offer(offer: Dictionary) -> void:
	var v := _modal("아티팩트 선택", "offer")
	v.add_child(UI.label("하나를 고르세요. 칸마다 한 번씩 다시 뽑을 수 있습니다.", 20, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	v.add_child(h)
	for i in offer["options"].size():
		var art := GameData.artifact(offer["options"][i])
		var col: Color = UI.GRADE_COLOR[art["grade"]]
		var card := UI.panel(col.darkened(0.7), 16, col, 3)
		card.custom_minimum_size = Vector2(400, 560)
		h.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		card.add_child(cv)
		var ic := UI.artifact_icon(offer["options"][i])
		var icon_box := UI.panel(Color(0, 0, 0, 0.35), 12)
		icon_box.custom_minimum_size = Vector2(0, 130)
		cv.add_child(icon_box)
		if ic != null:
			icon_box.add_child(UI.tex_rect(ic, Vector2(0, 110)))
		else:
			icon_box.add_child(UI.label("?", 64, col, HORIZONTAL_ALIGNMENT_CENTER))
		var nl := UI.label(art["name"], 26, col.lightened(0.15))
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(nl)
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 6)
		cv.add_child(chips)
		chips.add_child(UI.chip(GameData.grade_name(art["grade"]), col))
		if art.get("owner", "") != "":
			chips.add_child(UI.chip("애착: " + art["owner"], Color("ff8fb8")))
		for k in art.get("stats", {}):
			cv.add_child(UI.label("%s  +%s%%" % [STAT_NAME.get(k, k), str(art["stats"][k])], 19, UI.TEXT))
		var txt := UI.wrap_label(art.get("text", ""), 17, UI.SUB)
		txt.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cv.add_child(txt)
		var idx: int = i
		var used: bool = offer["rerolled"][i]
		var rr := UI.button("다시 뽑기 사용함" if used else "다시 뽑기", 20, Vector2(0, 56), Color("2f4f86"))
		rr.disabled = used
		rr.pressed.connect(func(): App.session.submit({"t": "art_reroll", "i": idx}))
		cv.add_child(rr)
		var pick := UI.button("선택", 24, Vector2(0, 64), Color("2f6b4a"))
		pick.pressed.connect(func():
			App.session.submit({"t": "art_pick", "i": idx})
			_close_modal())
		cv.add_child(pick)
	var hide := UI.button("잠시 접기 (보드 보기)", 20, Vector2(0, 56))
	hide.pressed.connect(func():
		_offer_hidden = true
		_close_modal()
		refresh())
	v.add_child(hide)


func _show_game_over() -> void:
	var st := App.session.state
	var v := _modal("게임 종료", "over")
	var list: Array = st["players"].values()
	list.sort_custom(func(a, b): return int(a["place"]) < int(b["place"]))
	for p in list:
		var mine: bool = p["id"] == App.session.my_pid
		var row := UI.panel(Color(UI.ACCENT, 0.15) if mine else UI.BG2, 10, UI.ACCENT if mine else Color.TRANSPARENT, 2 if mine else 0)
		row.custom_minimum_size.x = 520
		var h := HBoxContainer.new()
		row.add_child(h)
		var place := int(p["place"])
		h.add_child(UI.label("%d위" % place, 30, UI.ACCENT if place == 1 else UI.TEXT))
		var n := UI.label("   " + p["name"], 28, UI.TEXT)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		v.add_child(row)
	var b := UI.button("처음 화면으로", 26, Vector2(0, 70), Color("2f4f86"))
	b.pressed.connect(App.session.leave)
	v.add_child(b)


func _confirm_quit() -> void:
	var v := _modal("게임에서 나갈까요?", "quit")
	v.add_child(UI.wrap_label("방장이 나가면 게임이 끝납니다. 참가자는 같은 라운드 안에 다시 들어오면 이어서 할 수 있습니다.", 20, UI.TEXT))
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 14)
	v.add_child(h)
	var yes := UI.button("나가기", 24, Vector2(200, 66), Color("6b3535"))
	yes.pressed.connect(App.session.leave)
	h.add_child(yes)
	var no := UI.button("계속하기", 24, Vector2(200, 66), Color("2f6b4a"))
	no.pressed.connect(_close_modal)
	h.add_child(no)


# ─────────────────────────────── 전투 화면 ───────────────────────────────

func _start_battle_view() -> void:
	var st := App.session.state
	var mine := {}
	var side := 0
	for bt in st.get("battles", []):
		if bt["a"] == App.session.my_pid:
			mine = bt
			side = 0
		elif bt["b"] == App.session.my_pid:
			mine = bt
			side = 1
	if mine.is_empty() and not st.get("battles", []).is_empty():
		mine = st["battles"][0]   # 탈락했으면 첫 번째 전투 관전
	if mine.is_empty():
		return
	var pa: Dictionary = st["players"].get(mine["a"], {})
	var name_a: String = pa.get("name", "?")
	var name_b := ""
	if mine["ghost"] != "":
		name_b = "유령 (%s)" % st["players"].get(mine["ghost"], {}).get("name", "?")
	else:
		name_b = st["players"].get(mine["b"], {}).get("name", "?")
	_battle_view.setup(mine, side, name_a, name_b)
