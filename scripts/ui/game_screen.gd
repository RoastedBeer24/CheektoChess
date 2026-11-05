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
var _income_lbl: Label
var _star_seen := {}
var _star_init := false          # 합성 알림용: "사도id:성급" -> 개수
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
var _banner_sub: Label
var _banner_box: PanelContainer
var _detail_box: VBoxContainer
var _inv_grid: GridContainer
var _inv_title: Label
var _bench_tiles: Array = []
var _bench_lbl: Label
var _shop_tiles: Array = []
var _reroll_btn: Button
var _xp_btn: Button
var _sell_btn: Button
var _root: VBoxContainer
var _row_heads: Array = []
var _fit_k := 1.0
var _right_panel: Control
var _left_panel: Control
var _drag_layer: Control
var _drag := {}               # 끌기 중 정보 {src, aid, star, unit, start, active, ghost, hover}
var _suppress_click := false  # 끌기 직후 버튼 클릭 무시
const DRAG_START := 14.0      # 이만큼 움직이면 끌기 시작 (화면 좌표)
var _merge_btn: Button
var _overlay: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	get_viewport().size_changed.connect(_fit_layout)
	_fit_layout.call_deferred()
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
	_root = root
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
	# 라운드·결과 배너: 가운데 가로 띠 + 큰 글자 + 작은 설명
	_banner_box = PanelContainer.new()
	_banner_box.set_anchors_preset(Control.PRESET_HCENTER_WIDE)
	_banner_box.offset_top = -70
	_banner_box.offset_bottom = 70
	_banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_box.modulate.a = 0.0
	cstack.add_child(_banner_box)
	var bv := VBoxContainer.new()
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	bv.add_theme_constant_override("separation", 0)
	_banner_box.add_child(bv)
	_banner = UI.outlined("", 60, UI.ACCENT, 12)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bv.add_child(_banner)
	_banner_sub = UI.outlined("", 24, UI.TEXT, 6)
	_banner_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bv.add_child(_banner_sub)
	mid.add_child(_build_right())

	root.add_child(_build_bench())
	root.add_child(_build_shop())

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_drag_layer = Control.new()
	_drag_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_drag_layer)


## 화면 높이에 맞춰 보드·대기석·상점 칸 크기를 줄인다 (긴 화면·작은 화면에서 아래가 잘리지 않게)
const BOARD_TILE := 170.0
const BENCH_TILE := 124.0
const SHOP_H := 124.0


func _fit_layout() -> void:
	var avail := get_viewport_rect().size.y
	if avail <= 0 or _root == null:
		return
	# 가로로 긴 화면: 남는 너비를 정보 패널과 왼쪽 목록에 나눠 준다
	var extra := maxf(0.0, get_viewport_rect().size.x - 1920.0)
	_right_panel.custom_minimum_size.x = 450.0 + minf(extra * 0.55, 240.0)
	_left_panel.custom_minimum_size.x = 340.0 + minf(extra * 0.25, 80.0)
	_apply_fit(1.0)
	var need := _root.get_combined_minimum_size().y + 20.0
	var over := need - avail
	var k := 1.0
	if over > 0.0:
		k = clampf(1.0 - over / (BOARD_TILE * 3.0 + BENCH_TILE + SHOP_H), 0.55, 1.0)
	if not is_equal_approx(k, 1.0):
		_apply_fit(k)
	_fit_k = k


func _apply_fit(k: float) -> void:
	var b := roundf(BOARD_TILE * k)
	for key in _board_tiles:
		_board_tiles[key].custom_minimum_size = Vector2(b, b)
	for c in _row_heads:
		c.custom_minimum_size.x = b
	var be := roundf(BENCH_TILE * k)
	for t in _bench_tiles:
		t.custom_minimum_size = Vector2(be, be)
	_sell_btn.custom_minimum_size.y = be
	var sh := roundf(SHOP_H * k)
	for t in _shop_tiles:
		t.custom_minimum_size.y = sh
	_reroll_btn.custom_minimum_size.y = sh
	_xp_btn.custom_minimum_size.y = sh


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
	hpv.mouse_filter = Control.MOUSE_FILTER_STOP
	Tips.set_tip(hpv, _hp_tip)
	var gold := UI.panel(Color("4a3a12"), 10, UI.ACCENT, 2)
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", -4)
	gold.add_child(gv)
	_gold_lbl = UI.label("", 26, UI.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_gold_lbl.custom_minimum_size.x = 150
	gv.add_child(_gold_lbl)
	_income_lbl = UI.label("", 15, Color("e8d9a8"), HORIZONTAL_ALIGNMENT_CENTER)
	gv.add_child(_income_lbl)
	h.add_child(gold)
	Tips.set_tip(gold, _gold_tip)
	var lv := VBoxContainer.new()
	lv.custom_minimum_size.x = 200
	lv.add_theme_constant_override("separation", 2)
	h.add_child(lv)
	_lvl_lbl = UI.label("", 22)
	lv.add_child(_lvl_lbl)
	_xp_bar = UI.bar(UI.BLUE, 10)
	lv.add_child(_xp_bar)
	lv.mouse_filter = Control.MOUSE_FILTER_STOP
	Tips.set_tip(lv, _level_tip)
	_offer_btn = UI.button("아티팩트 선택", 22, Vector2(190, 58), Color("8a5a1f"))
	_offer_btn.pressed.connect(func():
		_offer_hidden = false
		refresh())
	h.add_child(_offer_btn)
	var codex := UI.button("도감", 22, Vector2(100, 58), Color("4f3586"))
	codex.pressed.connect(func(): add_child(Codex.new()))
	h.add_child(codex)
	Tips.set_tip(codex, "[b]도감[/b]\n모든 사도·아티팩트·시너지·용어를 찾아볼 수 있습니다.")
	_ready_btn = UI.button("준비 완료", 22, Vector2(160, 58), Color("2f6b4a"))
	_ready_btn.pressed.connect(_on_ready_btn)
	Tips.set_tip(_ready_btn, "[b]준비 완료[/b]  [color=#8a8fa6]［스페이스］[/color]\n사람 플레이어가 모두 준비하면 시간이 남아도 바로 전투합니다.\n전투 중에는 [b]건너뛰기[/b] — 모두 누르면 바로 다음 라운드.")
	h.add_child(_ready_btn)
	var quit := UI.button("나가기", 22, Vector2(110, 58), Color("6b3535"))
	quit.pressed.connect(_confirm_quit)
	h.add_child(quit)
	return top


func _build_left() -> Control:
	var left := UI.panel()
	left.custom_minimum_size.x = 340
	_left_panel = left
	var scroll := DragScroll.new(UI.PANEL)
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
	_right_panel = right
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right.add_child(rv)
	var dscroll := DragScroll.new(UI.PANEL)
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
	Tips.set_tip(_merge_btn, "[b]아티팩트 합성[/b]\n" + UI.mark("같은 등급 아티팩트 2개 → 한 등급 위 아티팩트 1개 (보관함으로). 전설은 합성할 수 없습니다.\n아티팩트를 다른 아티팩트 위로 끌어다 놓아도 됩니다."))
	invh.add_child(_merge_btn)
	var iscroll := DragScroll.new(UI.PANEL)
	iscroll.vertical_only = true   # 가로로 끌면 아티팩트 끌어다 놓기
	iscroll.custom_minimum_size.y = 146
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
		_row_heads.append(chip)
		chip.add_child(UI.label(GameData.ROW_NAME[GameData.ROWS[r]], 22, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
		heads.add_child(chip)
	for s in int(B()["board_slots"]):
		for r in [2, 1, 0]:
			var t := UnitTile.new(Vector2(170, 170))
			t.show_motion = Settings.flag("board_motion")
			var key := Match.key_of(r, s)
			t.loc = {"board": key}
			var loc: Dictionary = t.loc
			t.pressed.connect(func(): _on_tile(loc))
			t.held.connect(func(_t): _on_held(loc))
			Tips.set_tip(t, func(): return _tile_tip(loc))
			grid.add_child(t)
			_board_tiles[key] = t
	# 적 방향 표시는 열 이름 줄 오른쪽에 (아래에 두면 좁은 화면에서 대기석과 겹침)
	heads.add_child(UI.label("적 ▶▶", 20, UI.BAD.lightened(0.2), HORIZONTAL_ALIGNMENT_LEFT))
	var pad := Control.new()
	pad.custom_minimum_size.x = 40
	heads.add_child(pad)
	heads.move_child(pad, 0)
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
		t.held.connect(func(_t): _on_held(loc))
		Tips.set_tip(t, func(): return _tile_tip(loc))
		bench.add_child(t)
		_bench_tiles.append(t)
	_sell_btn = Button.new()
	_sell_btn.text = "판매"
	_sell_btn.custom_minimum_size = Vector2(170, 124)
	_sell_btn.add_theme_font_size_override("font_size", 22)
	for st in ["normal", "hover", "pressed", "disabled"]:
		_sell_btn.add_theme_stylebox_override(st, UI.box(Color("5a2b2b") if st != "disabled" else Color("3a2525"), 14, Color("b55a5a"), 2))
	_sell_btn.focus_mode = Control.FOCUS_NONE
	_sell_btn.pressed.connect(_on_sell)
	Tips.set_tip(_sell_btn, "[b]판매[/b]  [color=#8a8fa6]［E］[/color]\n사도를 여기로 끌어다 놓거나, 사도를 고른 뒤 누르면 판매합니다.\n판매 가격 = 코스트 × (★1: 1, ★2: 3, ★3: 9). 장착한 아티팩트는 보관함으로 돌아옵니다.")
	bench.add_child(_sell_btn)
	return bench


func _build_shop() -> Control:
	var shop := HBoxContainer.new()
	shop.add_theme_constant_override("separation", 8)
	shop.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in int(B()["shop_size"]):
		var t := UnitTile.new(Vector2(226, 124))
		var idx := i
		t.pressed.connect(func():
			if _take_suppress():
				return
			App.session.submit({"t": "buy", "i": idx}))
		t.held.connect(func(_t): _on_held({"shop": idx}))
		Tips.set_tip(t, func(): return _shop_tip(idx))
		shop.add_child(t)
		_shop_tiles.append(t)
	_reroll_btn = UI.button("새로고침\n%d골드" % int(B()["reroll_cost"]), 22, Vector2(170, 124), Color("2f4f86"))
	_reroll_btn.pressed.connect(func(): App.session.submit({"t": "reroll"}))
	Tips.set_tip(_reroll_btn, func(): return "[b]새로고침[/b]  [color=#8a8fa6]［D］[/color]\n상점의 사도 5명을 새로 뽑습니다 ([color=#ffd25e]%d골드[/color]).\n잠근 칸은 그대로 남습니다 (상점 카드 꾹 누르기)." % int(B()["reroll_cost"]) + _lack_text(int(B()["reroll_cost"])))
	shop.add_child(_reroll_btn)
	_xp_btn = UI.button("경험치 +%d\n%d골드" % [int(B()["xp_amount"]), int(B()["xp_cost"])], 22, Vector2(170, 124), Color("4f3586"))
	_xp_btn.pressed.connect(func(): App.session.submit({"t": "buy_xp"}))
	Tips.set_tip(_xp_btn, func(): return "[b]경험치 구매[/b]  [color=#8a8fa6]［F］[/color]\n[color=#ffd25e]%d골드[/color]로 경험치 +%d.\n" % [int(B()["xp_cost"]), int(B()["xp_amount"])] + _level_tip() + _lack_text(int(B()["xp_cost"])))
	shop.add_child(_xp_btn)
	return shop


# ─────────────────────────────── 갱신 ───────────────────────────────

func _process(_delta: float) -> void:
	if DragScroll.scrolling and _syn_popup:
		_hide_syn_popup()
	_check_long_press()
	var st := App.session.state
	if st.is_empty():
		return
	var phase: String = st.get("phase", "")
	var left := float(st.get("phase_end", 0.0))
	if phase == "battle" and _battle_view.visible:
		# 내 전투 경과 시간 / 최대 시간 (전투마다 같은 기준)
		var limit := float(B()["battle_time_limit"])
		var el := minf(_battle_view.elapsed(), limit)
		_phase_lbl.text = "전투  %d / %d초" % [int(el), int(limit)]
		_time_bar.value = 100.0 * (1.0 - el / limit)
		if _battle_view.finished() and not me().get("skip", false) and _ready_btn.text != "결과 보기 ▶":
			_ready_btn.text = "결과 보기 ▶"
	else:
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
		var inc := _income_parts(p)
		_income_lbl.text = "다음 +%d  (이자 %d%s)" % [inc[0], inc[1], ("· %s %d" % ["연승" if int(p["streak"]) > 0 else "연패", absi(int(p["streak"]))]) if absi(int(p["streak"])) >= 2 else ""]
		_check_merge_fx(p)
		var maxed := int(p["level"]) >= int(B()["max_level"])
		var need := 0 if maxed else int(B()["xp_to_next"][int(p["level"]) - 1])
		_lvl_lbl.text = "Lv %d  %s" % [int(p["level"]), "MAX" if maxed else "%d/%d" % [int(p["xp"]), need]]
		_xp_bar.value = 100.0 if maxed else 100.0 * int(p["xp"]) / maxf(1.0, need)
		if phase == "battle":
			_ready_btn.text = "기다리는 중" if p.get("skip", false) else ("결과 보기 ▶" if _battle_view.finished() else "건너뛰기 ▶")
		else:
			_ready_btn.text = "준비 취소" if p.get("ready", false) else "준비 완료"
	var prep: bool = phase == "prep" and p.get("alive", false)
	var gold := int(p.get("gold", 0))
	_ready_btn.disabled = not (prep or (phase == "battle" and p.get("alive", false) and not p.get("skip", false)))
	_reroll_btn.disabled = not prep or gold < int(B()["reroll_cost"])
	var lv_max := int(p.get("level", 1)) >= int(B()["max_level"])
	_xp_btn.disabled = not prep or gold < int(B()["xp_cost"]) or lv_max
	# 누를 수 없을 때는 이유를 버튼에 적는다 (골드 부족은 빨간 글씨)
	_reroll_btn.text = "새로고침\n%d골드%s" % [int(B()["reroll_cost"]), "  부족" if gold < int(B()["reroll_cost"]) else ""]
	_xp_btn.text = "경험치 +%d\n%s" % [int(B()["xp_amount"]), "최대 레벨" if lv_max else ("%d골드%s" % [int(B()["xp_cost"]), "  부족" if gold < int(B()["xp_cost"]) else ""])]
	for b in [_reroll_btn, _xp_btn]:
		b.add_theme_color_override("font_disabled_color", Color("ff9a9a", 0.85) if prep and b.text.ends_with("부족") else Color(1, 1, 1, 0.35))
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
	if not _drag.is_empty() and _drag.get("active", false):
		_paint_drag()


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
			var subs := []
			if not me().get("art_offer", {}).is_empty():
				subs.append("아티팩트 선택")
			var stk := int(me().get("streak", 0))
			if absi(stk) >= 2:
				subs.append("%d%s 중" % [absi(stk), "연승" if stk > 0 else "연패"])
			_show_banner("라운드 %d" % rnd, UI.ACCENT, " · ".join(subs))
		"battle":
			_start_battle_view()
		"result":
			_show_result_banner()


func _show_banner(text: String, color: Color, sub: String = "") -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner_sub.text = sub
	_banner_sub.visible = sub != ""
	var band := StyleBoxFlat.new()
	band.bg_color = Color(color.darkened(0.75), 0.82)
	band.border_color = Color(color, 0.8)
	band.border_width_top = 3
	band.border_width_bottom = 3
	band.content_margin_top = 8
	band.content_margin_bottom = 8
	_banner_box.add_theme_stylebox_override("panel", band)
	var tw := create_tween()
	_banner_box.modulate.a = 0.0
	_banner_box.scale = Vector2(1, 0.4)
	_banner_box.pivot_offset = Vector2(_banner_box.size.x / 2.0, _banner_box.size.y / 2.0)
	tw.set_parallel(true)
	tw.tween_property(_banner_box, "modulate:a", 1.0, 0.18)
	tw.tween_property(_banner_box, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(1.2)
	tw.chain().tween_property(_banner_box, "modulate:a", 0.0, 0.45)


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
		var opp: String = bt["b"] if side == 0 else bt["a"]
		var opp_name: String = "유령 상대" if opp == "" else String(st["players"].get(opp, {}).get("name", ""))
		if w == side:
			_show_banner("승리!", UI.GOOD, "vs %s · +1 골드 · 살아남은 사도 %d명" % [opp_name, int(bt["survivors"])])
		elif w == -1:
			_show_banner("무승부", UI.SUB, "vs %s · ♥ -%d" % [opp_name, base])
		else:
			_show_banner("패배", UI.BAD, "vs %s · ♥ -%d (기본 %d + 살아남은 적 %d)" % [opp_name, base + int(bt["survivors"]), base, int(bt["survivors"])])
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
		var pid: String = p["id"]
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var pp: Dictionary = p
		Tips.set_tip(row, func(): return _player_tip(pp))
		row.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed \
					and Rect2(Vector2.ZERO, row.size).has_point(ev.position) and not DragScroll.scrolling:
				_show_player(pid))
		var sb: StyleBoxFlat = row.get_theme_stylebox("panel")
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		row.custom_minimum_size.y = 46
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
		var col: Color = UI.syn_color(n)
		var row := UI.panel(col.darkened(0.7) if active > 0 else UI.BG2, 10, col if active > 0 else UI.LINE, 2)
		# 꾹 누르면(PC는 마우스를 올리면) 시너지 상세 팝업
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var syn_name: String = n
		var syn_count: int = counts[n]
		row.mouse_entered.connect(func(): _show_syn_popup(row, syn_name, syn_count))
		row.mouse_exited.connect(_hide_syn_popup)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		row.add_child(v)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		v.add_child(h)
		h.add_child(UI.syn_badge(n, 30, active == 0))
		var cnt := UI.label(str(counts[n]), 22, col if active > 0 else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER)
		cnt.custom_minimum_size.x = 22
		h.add_child(cnt)
		var nl := UI.label(UI.syn_short(n), 20, UI.TEXT if active > 0 else UI.SUB)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.custom_minimum_size.x = 60
		h.add_child(nl)
		var tl: Array = syn["tiers"]
		for i in tl.size():
			var tlab := UI.label(str(int(tl[i])), 18, col if i < active else Color(1, 1, 1, 0.3))
			if i == active:
				tlab.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
			h.add_child(tlab)
		# 다음 단계까지 1명 남았으면 강조
		if active < tl.size() and int(tl[active]) - int(counts[n]) == 1 and int(counts[n]) >= 2:
			var more := UI.chip("1명 더!", Color("ffe066"), 18)
			more.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			h.add_child(more)
			h.move_child(more, 3)
			row.add_theme_stylebox_override("panel", UI.box(col.darkened(0.75), 10, Color("ffe066").darkened(0.15), 2))
		if active > 0:
			# 지금 적용 중인 단계의 효과 (고유 시너지는 효과 전체)
			var lines: Array = UI.syn_lines(n)
			var now_text: String = lines[1].get(int(tl[active - 1]), lines[0])
			v.add_child(UI.wrap_label(now_text, 18, UI.SUB))
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
			if not _merge_pairs(u).is_empty():
				t.set_corner("◆ 합성", Color("c9a7ff"))
		t.set_selected(sel.get("unit", {}) == {"board": key})
	_board_info.text = "보드 %d / %d   (레벨만큼 올릴 수 있음)" % [p.get("board", {}).size(), int(p.get("level", 1))]


## 사도 칸 아래 작은 글씨 (성격·종족은 아이콘으로 표시하므로 공명/이면 선택만)
func _pers_tag(u: Dictionary) -> String:
	var a := GameData.apostle(u["aid"])
	var p: String = a.get("personality", "")
	if p == "공명" or p == "이면":
		return "%s→%s" % [p, u["pers"]] if u["pers"] != "" else p
	return ""


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
			if not _merge_pairs(u).is_empty():
				t.set_corner("◆ 합성", Color("c9a7ff"))
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
		var sn := []
		for tr in GameData.traits_of(aid):
			if GameData.synergies.get(tr, {}).get("kind", "") != "unique":
				sn.append(UI.syn_short(tr))
		var traits: String = "%s · %s" % [" ".join(sn), GameData.ROW_NAME[a["row"]]]
		t.set_unit({"aid": aid}, traits, UI.cost_color(aid))
		t.set_badge("%dG" % cost, UI.cost_color(aid).lightened(0.35), 24)
		t.set_name_color(UI.cost_color(aid).lightened(0.45))
		var owned := _owned_count(p, aid)
		if owned >= 2:
			t.set_corner("★ 합성!", Color("ffe066"))
		elif owned > 0:
			t.set_corner("보유 %d/3" % owned, UI.ACCENT)
		var locks: Array = p.get("locks", [])
		t.set_locked(i < locks.size() and locks[i] == true)
		t.set_dim(gold < cost)
		t.disabled = not prep


# ─────────────────────────────── 툴팁 글 ───────────────────────────────

func _lack_text(cost: int) -> String:
	var g := int(me().get("gold", 0))
	if App.session.state.get("phase", "") != "prep":
		return "\n[color=#ff7070]준비 시간에만 할 수 있습니다[/color]"
	if g < cost:
		return "\n[color=#ff7070]골드 %d 부족[/color]" % (cost - g)
	return ""


func _gold_tip() -> String:
	var p := me()
	if p.is_empty():
		return ""
	var inc := _income_parts(p)
	var stk := int(p.get("streak", 0))
	var out := "[b][color=#ffd25e]골드 %d[/color][/b]\n다음 라운드 수입 [color=#ffd25e]+%d[/color]\n" % [int(p["gold"]), inc[0]]
	out += "• 기본 [color=#ffd25e]%d[/color]\n" % int(B()["base_income"])
	out += "• 이자 [color=#ffd25e]%d[/color]  (가진 골드 10마다 1, 최대 %d)\n" % [inc[1], int(B()["interest_max"])]
	out += "• %s [color=#ffd25e]%d[/color]  (지금 %s)" % ["연승" if stk >= 0 else "연패", inc[2], ("%d연승" % stk) if stk > 0 else (("%d연패" % -stk) if stk < 0 else "없음")]
	var nxt := (int(p["gold"]) / 10 + 1) * 10
	if inc[1] < int(B()["interest_max"]):
		out += "\n[color=#8a8fa6]%d골드까지 모으면 이자 +1[/color]" % nxt
	return out


func _hp_tip() -> String:
	var p := me()
	if p.is_empty():
		return ""
	var r := int(App.session.state.get("round", 1))
	var base_dmg := int(B()["damage_base"]) + r / int(B()["damage_per_round_div"])
	return "[b][color=#5ee39b]체력 %d[/color][/b] / %d\n전투에서 지면 [color=#ff7070]%d + 살아남은 적 사도 수[/color]만큼 줄어듭니다 (라운드가 갈수록 커짐).\n0이 되면 탈락." % [maxi(0, int(p["hp"])), int(B()["player_hp"]), base_dmg]


func _level_tip() -> String:
	var p := me()
	if p.is_empty():
		return ""
	var lv := int(p["level"])
	var out := "[b]레벨 %d[/b] — 보드에 [color=#ffd25e]%d명[/color]까지 올릴 수 있습니다." % [lv, lv]
	if lv < int(B()["max_level"]):
		var need := int(B()["xp_to_next"][lv - 1])
		out += "\n다음 레벨까지 경험치 [color=#8cc4ff]%d[/color] (라운드마다 +%d)" % [need - int(p["xp"]), int(B().get("xp_per_round", 2))]
	var odds: Array = B()["shop_odds"][clampi(lv - 1, 0, B()["shop_odds"].size() - 1)]
	var parts := []
	for i in odds.size():
		if int(odds[i]) > 0:
			parts.append("[color=#%s]%d코 %d%%[/color]" % [UI.COST_COLOR[i].lightened(0.2).to_html(false), i + 1, int(odds[i])])
	out += "\n상점 확률: " + "  ".join(parts)
	return out


func _player_tip(p: Dictionary) -> String:
	var cur: Dictionary = App.session.state.get("players", {}).get(p["id"], p)
	var out := "[b]%s[/b]  Lv %d\n" % [cur["name"], int(cur["level"])]
	if not cur["alive"]:
		return out + "[color=#8a8fa6]탈락 (%d위)[/color]" % int(cur["place"])
	out += "체력 [color=#5ee39b]%d[/color]" % maxi(0, int(cur["hp"]))
	var stk := int(cur.get("streak", 0))
	if absi(stk) >= 2:
		out += " · [color=#ffd25e]%d%s[/color]" % [absi(stk), "연승" if stk > 0 else "연패"]
	out += " · 보드 %d명" % cur.get("board", {}).size()
	if cur.get("bot", false):
		out += " · 봇"
	return out + "\n[color=#8a8fa6]눌러서 보드 보기[/color]"


func _tile_tip(loc: Dictionary) -> String:
	if not _drag.is_empty() and _drag.get("active", false):
		return ""
	var u = _unit_at(loc)
	if u == null:
		if loc.has("board"):
			var r := int(String(loc["board"]).split(",")[0])
			return UI.mark("빈 칸 — %s 사도를 놓을 수 있습니다 (모든열 사도는 어디든)." % GameData.ROW_NAME[GameData.ROWS[r]])
		return ""
	var extra := "[color=#8a8fa6]판매 %d골드 · 끌어서 이동 · 꾹 눌러 정보[/color]" % _sell_value(u)
	return UI.unit_tip(u, extra)


func _shop_tip(i: int) -> String:
	var p := me()
	var shop: Array = p.get("shop", [])
	if i >= shop.size() or shop[i] == "":
		return ""
	var aid: String = shop[i]
	var cost: int = GameData.cost_of[aid]
	var owned := _owned_count(p, aid)
	var extra := "보유 [color=#ffd25e]%d/3[/color]%s" % [owned, "  [color=#ffe066]→ 사면 ★ 합성![/color]" if owned >= 2 else ""]
	if int(p.get("gold", 0)) < cost:
		extra += "\n[color=#ff7070]골드 %d 부족[/color]" % (cost - int(p.get("gold", 0)))
	extra += "\n[color=#8a8fa6]누르면 구매 · 끌어서 원하는 칸에 구매 · 꾹 눌러 잠금[/color]"
	return UI.unit_tip({"aid": aid, "star": 1}, extra)


func _sell_value(u: Dictionary) -> int:
	return GameData.cost_of.get(u["aid"], 1) * int(pow(3, int(u["star"]) - 1))


func _refresh_inventory() -> void:
	UI.clear(_inv_grid)
	var p := me()
	var inv: Array = p.get("inv", [])
	for a in inv:
		var bw := floorf((_right_panel.custom_minimum_size.x - 28.0 - 6.0 - 18.0) / 2.0)
		var b := UI.artifact_button(a["id"], Vector2(bw, 64), 19, sel.get("art", -1) == int(a["uid"]))
		var uid := int(a["uid"])
		b.set_meta("art_uid", uid)
		b.pressed.connect(func(): _on_art(uid))
		b.button_down.connect(func(): _on_held({"art": uid}))
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
	if sel.has("shop_aid"):
		_detail_box.add_child(UI.label("상점 사도", 18, UI.SUB))
		Info.apostle(_detail_box, {"aid": sel["shop_aid"], "star": 1, "arts": [], "pers": ""}, Callable(), -1, false)
		return
	if sel.has("art"):
		var where := _find_art(int(sel["art"]))
		if not where.is_empty():
			_detail_art(where["art"]["id"], where.has("inv"))
			return
	_detail_box.add_child(UI.label("도움말", 26, UI.ACCENT))
	for line in [
		"상점 카드를 누르면 구매, 끌어다 놓으면 그 칸에 구매. 테두리 색은 코스트(회색 1 → 금색 5).",
		"상점 카드를 꾹 누르면 잠금 — 새로고침·다음 라운드에도 남습니다. 다시 꾹 누르면 해제.",
		"사도를 끌어다 놓아 이동. 놓을 수 있는 칸은 초록, 손가락 옆에 결과가 보입니다.",
		"사도는 자기 열(전열/중열/후열)에만 놓을 수 있습니다. 모든열은 어디든.",
		"같은 사도 3명이 모이면 자동 ★ 합성. '★ 합성!' 표시된 상점 카드를 사면 바로 합성됩니다.",
		"보관함 아티팩트를 누르고 사도를 누르면 장착 (최대 3개, 임의 해제 불가).",
		"시너지를 꾹 누르면 단계별 효과와 해당 사도 목록을 볼 수 있습니다.",
		"왼쪽 플레이어 이름을 누르면 그 플레이어의 보드를 볼 수 있습니다.",
		"PC 단축키: D 새로고침 · F 경험치 · E 마우스 아래 사도 판매 · 스페이스 준비/건너뛰기 · F11 전체 화면",
	]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var dot := UI.label("•", 18, UI.ACCENT)
		dot.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		row.add_child(dot)
		var l := UI.rich_desc(line, 18, UI.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		_detail_box.add_child(row)


func _detail_unit(u: Dictionary) -> void:
	# 같은 등급 아티팩트를 2개 이상 장착했으면 바로 합성 (결과는 보관함으로) — 스크롤 없이 보이게 맨 위에
	var pairs := _merge_pairs(u)
	if not pairs.is_empty() and _is_prep():
		for pr in pairs:
			var a1 := GameData.artifact(pr[0]["id"])
			var a2 := GameData.artifact(pr[1]["id"])
			var ng := GameData.next_grade(a1["grade"])
			var b := UI.button("%s + %s\n→ %s 무작위 1개 (보관함으로)" % [a1["name"], a2["name"], GameData.grade_name(ng)], 17, Vector2(0, 72), Color("5a3f86"))
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var ua := int(pr[0]["uid"])
			var ub := int(pr[1]["uid"])
			b.pressed.connect(func():
				App.session.submit({"t": "art_merge", "a": ua, "b": ub})
				_vibrate(40))
			_detail_box.add_child(b)
	Info.apostle(_detail_box, u, _on_art, int(sel.get("art", -1)), sel.has("unit"))


## 사도가 장착한 아티팩트 중 합성할 수 있는 쌍 (등급마다 앞의 두 개)
func _merge_pairs(u: Dictionary) -> Array:
	var by_grade := {}
	for art in u.get("arts", []):
		var g: String = GameData.artifact(art["id"]).get("grade", "")
		if GameData.next_grade(g) == "":
			continue
		if not by_grade.has(g):
			by_grade[g] = []
		by_grade[g].append(art)
	var out := []
	for g in by_grade:
		if by_grade[g].size() >= 2:
			out.append([by_grade[g][0], by_grade[g][1]])
	return out


func _detail_art(art_id: String, in_inv: bool) -> void:
	Info.artifact(_detail_box, art_id, "inv" if in_inv else "equipped")


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
		_ask_personality(mover["aid"], func(pers): _send_move(from, to, pers))
	else:
		_send_move(from, to, "")


## 이동 명령. LAN 참가자는 방장 응답을 기다리지 않고 화면에 먼저 반영한다 (거절되면 방장이 상태를 다시 보냄).
func _send_move(from: Dictionary, to: Dictionary, pers: String) -> void:
	if App.session.mode == "client":
		_local_move(from, to, pers)
	App.session.submit({"t": "move", "from": from, "to": to, "pers": pers})


func _local_move(from: Dictionary, to: Dictionary, pers: String) -> void:
	var p := me()
	var a = _unit_at(from)
	var b = _unit_at(to)
	if a == null:
		return
	for pair in [[from, b], [to, a]]:
		var loc: Dictionary = pair[0]
		if loc.has("bench"):
			p["bench"][int(loc["bench"])] = pair[1]
		elif pair[1] == null:
			p["board"].erase(loc["board"])
		else:
			p["board"][loc["board"]] = pair[1]
	if to.has("board") and pers != "":
		a["pers"] = pers
	refresh()


## PC 단축키: D 새로고침, F 경험치, E 마우스 아래 사도 판매, 스페이스 준비/건너뛰기
func _hotkey(e: InputEventKey) -> void:
	if _overlay_kind != "":
		return
	match e.keycode:
		KEY_D:
			if _is_prep():
				App.session.submit({"t": "reroll"})
		KEY_F:
			if _is_prep():
				App.session.submit({"t": "buy_xp"})
		KEY_E:
			if _is_prep():
				var tgt = _target_at(get_global_mouse_position())
				if tgt != null and not tgt.has("sell") and _unit_at(tgt) != null:
					App.session.submit({"t": "sell", "loc": tgt})
		KEY_SPACE:
			if not _ready_btn.disabled:
				_on_ready_btn()


## [합계, 이자, 연승·연패 보너스]
func _income_parts(p: Dictionary) -> Array:
	var interest := mini(int(p["gold"]) / int(B()["interest_per"]), int(B()["interest_max"]))
	var s := absi(int(p["streak"]))
	var bonus := 0
	for pair in B()["streak_bonus"]:
		if s >= int(pair[0]):
			bonus = int(pair[1])
	return [int(B()["base_income"]) + interest + bonus, interest, bonus]


## 새로 ★합성된 사도가 생기면 알림 + 진동
func _check_merge_fx(p: Dictionary) -> void:
	var now := {}
	var units := []
	for u in p.get("bench", []):
		if u != null:
			units.append(u)
	for k in p.get("board", {}):
		units.append(p["board"][k])
	for u in units:
		if int(u["star"]) >= 2:
			var key := "%s:%d" % [u["aid"], int(u["star"])]
			now[key] = now.get(key, 0) + 1
	if _star_init:
		for key in now:
			if now[key] > _star_seen.get(key, 0):
				var parts: PackedStringArray = key.split(":")
				_show_banner("%s  %s 합성!" % [UI.stars(int(parts[1])), GameData.apostle(parts[0])["name"]], Color("ffe066"))
				_vibrate(60)
				break
	_star_seen = now
	_star_init = true


## 다른 플레이어 보드 보기 (정찰)
func _show_player(pid: String) -> void:
	var p: Dictionary = App.session.state["players"].get(pid, {})
	if p.is_empty():
		return
	var v := _modal("%s" % p["name"], "scout")
	var info := "Lv %d  ·  ♥ %d  ·  %d골드" % [int(p["level"]), maxi(0, int(p["hp"])), int(p["gold"])]
	if absi(int(p["streak"])) >= 2:
		info += "  ·  %s %d" % ["연승" if int(p["streak"]) > 0 else "연패", absi(int(p["streak"]))]
	if not p["alive"]:
		info += "  ·  %d위 탈락" % int(p["place"])
	v.add_child(UI.label(info, 22, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	v.add_child(h)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	h.add_child(grid)
	for sl in int(B()["board_slots"]):
		for r in [2, 1, 0]:
			var t := UnitTile.new(Vector2(120, 120))
			t.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var u = p["board"].get(Match.key_of(r, sl))
			if u == null:
				t.set_empty(GameData.ROW_NAME[GameData.ROWS[r]])
			else:
				t.set_unit(u)
			grid.add_child(t)
	var syn := VBoxContainer.new()
	syn.custom_minimum_size.x = 260
	h.add_child(syn)
	syn.add_child(UI.label("시너지", 22, UI.ACCENT))
	var specs := []
	for k in p["board"]:
		specs.append(p["board"][k])
	var counts := Rules.count_traits(specs)
	var tiers := Rules.active_tiers(counts)
	for n in counts:
		if tiers.get(n, 0) > 0:
			syn.add_child(UI.label("%s %d" % [n, counts[n]], 20, UI.GOOD))
	if syn.get_child_count() == 1:
		syn.add_child(UI.label("발동 없음", 18, UI.SUB))
	var bench := HBoxContainer.new()
	bench.add_theme_constant_override("separation", 6)
	v.add_child(UI.label("대기석", 18, UI.SUB))
	v.add_child(bench)
	for u in p["bench"]:
		var t := UnitTile.new(Vector2(84, 84))
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if u == null:
			t.set_empty("")
		else:
			t.set_unit(u)
		bench.add_child(t)
	var close := UI.button("닫기", 22, Vector2(0, 60))
	close.pressed.connect(_close_modal)
	v.add_child(close)


func _on_ready_btn() -> void:
	var phase: String = App.session.state.get("phase", "")
	if phase == "battle":
		_battle_view.skip_to_end()
		App.session.submit({"t": "skip"})
	else:
		App.session.submit({"t": "ready", "on": not me().get("ready", false)})


func _take_suppress() -> bool:
	if _suppress_click:
		_suppress_click = false
		return true
	return false


func _on_tile(loc: Dictionary) -> void:
	if _take_suppress():
		return
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
	if _take_suppress():
		return
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
	if _take_suppress():
		return
	if sel.has("unit") and _unit_at(sel["unit"]) != null:
		App.session.submit({"t": "sell", "loc": sel["unit"]})
		sel = {}
		refresh()
	else:
		_toast("팔 사도를 고르거나, 판매 칸으로 끌어다 놓으세요")


# ─────────────────────────────── 끌어다 놓기 ───────────────────────────────
# 누른 채 움직이면 사도가 손가락을 따라오고, 모든 칸이 놓을 수 있는지(초록)/없는지(어둡게) 표시된다.
# 손가락 아래 칸에는 놓일 모습과 결과(놓기/교체/구매/판매 또는 불가 사유)가 보인다.

func _vibrate(ms: int = 20) -> void:
	if OS.has_feature("android") and Settings.flag("vibrate"):
		Input.vibrate_handheld(ms)


func _on_held(src: Dictionary) -> void:
	if not _is_prep():
		return
	if src.has("art"):
		var where := _find_art(int(src["art"]))
		if where.is_empty():
			return
		_drag = {"src": src, "art_id": where["art"]["id"], "in_inv": where.has("inv"), "aid": "", "star": 1, "unit": null,
			"start": get_global_mouse_position(), "active": false, "hover": null, "t0": Time.get_ticks_msec()}
		return
	var p := me()
	var aid := ""
	var star := 1
	var unit = null
	if src.has("shop"):
		var shop: Array = p.get("shop", [])
		aid = shop[src["shop"]] if src["shop"] < shop.size() else ""
	else:
		unit = _unit_at(src)
		if unit != null:
			aid = unit["aid"]
			star = int(unit["star"])
	if aid == "":
		return
	_drag = {"src": src, "aid": aid, "star": star, "unit": unit, "start": get_global_mouse_position(), "active": false, "hover": null, "t0": Time.get_ticks_msec()}


const LONG_PRESS_MS := 450
var _long_fired := false
var _syn_popup: Control


func _show_syn_popup(row: Control, name: String, count: int) -> void:
	_hide_syn_popup()
	var p := me()
	var aids := []
	for k in p.get("board", {}):
		aids.append(p["board"][k]["aid"])
	var panel := UI.panel(Color("161824"), 14, UI.LINE, 2)
	panel.custom_minimum_size = Vector2(700, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	Info.synergy(v, name, count, aids)
	_drag_layer.add_child(panel)
	_syn_popup = panel
	panel.modulate.a = 0.0
	_place_syn_popup(panel, row)
	# 글 줄바꿈 높이는 너비가 정해진 뒤에 확정되므로 한 프레임 뒤 다시 맞춘다
	await get_tree().process_frame
	if is_instance_valid(panel) and _syn_popup == panel:
		_place_syn_popup(panel, row)
		panel.modulate.a = 1.0


func _place_syn_popup(panel: Control, row: Control) -> void:
	panel.reset_size()
	var r := row.get_global_rect()
	var vp := get_viewport_rect().size
	# 화면보다 크면 줄이고, 항상 화면 안에 들어오게
	var k := minf(1.0, (vp.y - 20.0) / maxf(1.0, panel.size.y))
	panel.scale = Vector2(k, k)
	var ps := panel.size * k
	panel.position = Vector2(clampf(r.end.x + 12, 10, maxf(10.0, vp.x - ps.x - 10)), clampf(r.position.y - 20, 10, maxf(10.0, vp.y - ps.y - 10)))


func _hide_syn_popup() -> void:
	if _syn_popup and is_instance_valid(_syn_popup):
		_syn_popup.queue_free()
	_syn_popup = null


## 꾹 누르기: 움직이지 않고 일정 시간 누르고 있으면 발동
func _check_long_press() -> void:
	if _drag.is_empty() or _drag.get("active", false):
		return
	if DragScroll.scrolling:
		_drag = {}
		return
	if Time.get_ticks_msec() - int(_drag["t0"]) < LONG_PRESS_MS:
		return
	var src: Dictionary = _drag["src"]
	_drag = {}
	_long_fired = true
	_vibrate(30)
	if src.has("art"):
		sel = {"art": src["art"]}
		refresh()
		return
	if src.has("shop"):
		var locks: Array = me().get("locks", [])
		var on: bool = not (src["shop"] < locks.size() and locks[src["shop"]] == true)
		App.session.submit({"t": "lock", "i": src["shop"], "on": on})
		_toast("상점 칸 잠금 — 새로고침·다음 라운드에도 유지" if on else "잠금 해제")
		sel = {"shop_aid": me().get("shop", [])[src["shop"]]}
		refresh()
	else:
		sel = {"unit": src}
		refresh()


func _input(event: InputEvent) -> void:
	# 시너지 팝업: 손을 떼면 닫힘 (모바일 '꾹 누르는 동안 보기')
	if _syn_popup and event is InputEventMouseButton and not event.pressed:
		_hide_syn_popup()
	# 꾹 누르기 후 손을 떼면 버튼 클릭(구매 등)이 일어나지 않게 막는다
	if _long_fired and event is InputEventMouseButton and not event.pressed:
		_long_fired = false
		_suppress_click = true
		(func(): _suppress_click = false).call_deferred()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_hotkey(event)
	if _drag.is_empty():
		return
	if event is InputEventMouseMotion:
		# 목록을 손가락으로 스크롤하기 시작했으면 끌어다 놓기 후보는 취소
		if DragScroll.scrolling and not _drag.get("active", false):
			_drag = {}
			return
		# _input 의 좌표는 화면 배율이 반영된 캔버스 좌표 (GameScreen 은 화면 전체를 덮음)
		var pos: Vector2 = event.position
		if not _drag["active"]:
			if pos.distance_to(_drag["start"]) >= DRAG_START:
				_begin_drag()
		if _drag.get("active", false):
			_move_drag(pos)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		DragScroll.external_drag = false
		if _drag.get("active", false):
			_suppress_click = true
			_finish_drag()
			# 다른 칸 위에서 손을 떼면 클릭이 오지 않으므로 다음 프레임에 풀어 준다
			(func(): _suppress_click = false).call_deferred()
		_drag = {}


func _begin_drag() -> void:
	_drag["active"] = true
	DragScroll.external_drag = true
	sel = {}
	_vibrate(15)
	var ghost: Control
	if _drag.has("art_id"):
		ghost = _art_ghost(_drag["art_id"])
	else:
		var ut := UnitTile.new(Vector2(150, 150))
		ut.set_unit({"aid": _drag["aid"], "star": _drag["star"], "arts": _drag["unit"]["arts"] if _drag["unit"] != null else [], "pers": _drag["unit"]["pers"] if _drag["unit"] != null else ""})
		ghost = ut
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.modulate = Color(1, 1, 1, 0.92)
	ghost.pivot_offset = Vector2(75, 75)
	ghost.scale = Vector2(1.08, 1.08)
	_drag_layer.add_child(ghost)
	_drag["ghost"] = ghost
	var tag := UI.panel(Color(0, 0, 0, 0.8), 10)
	var tag_lbl := UI.label("", 22, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	tag.add_child(tag_lbl)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.visible = false
	_drag_layer.add_child(tag)
	_drag["tag"] = tag
	_drag["tag_lbl"] = tag_lbl
	if _drag["src"].has("shop"):
		_shop_tiles[_drag["src"]["shop"]].set_dim(true)
	refresh()


func _move_drag(pos: Vector2) -> void:
	var ghost: Control = _drag["ghost"]
	# 손가락과 아래 칸이 가리지 않도록 위쪽에 띄운다
	ghost.position = pos - Vector2(75, 75) + Vector2(0, -140)
	var tag: Control = _drag["tag"]
	tag.reset_size()
	tag.position = pos + Vector2(-tag.size.x / 2.0, -58)
	var hover = _target_at(pos)
	if hover != _drag["hover"]:
		_drag["hover"] = hover
		_paint_drag()


## 화면 좌표 아래에 있는 놓을 곳 ({"board": key} / {"bench": i} / {"sell": true} / null)
## 화면의 아티팩트 버튼들 (보관함 + 사도 정보의 장착 아티팩트): uid -> 버튼
func _art_buttons() -> Dictionary:
	var out := {}
	for root in [_inv_grid, _detail_box]:
		_collect_art_buttons(root, out)
	return out


func _collect_art_buttons(n: Node, out: Dictionary) -> void:
	for c in n.get_children():
		if c is Button and c.has_meta("art_uid") and c.is_visible_in_tree():
			out[int(c.get_meta("art_uid"))] = c
		_collect_art_buttons(c, out)


func _art_ghost(art_id: String) -> Control:
	var art := GameData.artifact(art_id)
	var col: Color = UI.GRADE_COLOR[art.get("grade", "common")]
	var p := UI.panel(col.darkened(0.6), 16, col, 4)
	p.custom_minimum_size = Vector2(150, 150)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var ic := UI.artifact_icon(art_id)
	if ic != null:
		v.add_child(UI.tex_rect(ic, Vector2(96, 96)))
	else:
		v.add_child(UI.label("?", 56, col, HORIZONTAL_ALIGNMENT_CENTER))
	var l := UI.label(art.get("name", ""), 16, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	l.clip_text = true
	v.add_child(l)
	p.modulate = Color(1, 1, 1, 0.92)
	return p


func _target_at(pos: Vector2):
	if _drag.has("art_id"):
		var btns := _art_buttons()
		for uid in btns:
			if btns[uid].get_global_rect().has_point(pos):
				return {"art": uid}
	for key in _board_tiles:
		if _board_tiles[key].get_global_rect().has_point(pos):
			return {"board": key}
	for i in _bench_tiles.size():
		if _bench_tiles[i].get_global_rect().has_point(pos):
			return {"bench": i}
	if _sell_btn.get_global_rect().has_point(pos):
		return {"sell": true}
	return null


## 놓을 수 있는지 검사: {ok, text}
func _check_drop(target: Dictionary) -> Dictionary:
	if _drag.has("art_id"):
		return _check_art_drop(target)
	var p := me()
	var src: Dictionary = _drag["src"]
	var aid: String = _drag["aid"]
	var a := GameData.apostle(aid)
	if target == src:
		return {"ok": false, "text": "", "same": true}
	if target.has("sell"):
		if src.has("shop"):
			return {"ok": false, "text": ""}
		return {"ok": true, "text": "판매\n+%d골드" % _sell_value(_drag["unit"])}
	var occupant = _unit_at(target)
	if src.has("shop"):
		var cost: int = GameData.cost_of.get(aid, 1)
		if int(p.get("gold", 0)) < cost:
			return {"ok": false, "text": "골드 부족"}
		if occupant != null:
			return {"ok": false, "text": "빈칸에\n놓으세요"}
		if target.has("board"):
			var row: int = Match._parse_key(target["board"])[0]
			if not GameData.can_place(aid, row):
				return {"ok": false, "text": "%s\n전용" % GameData.ROW_NAME[a["row"]]}
			if p.get("board", {}).size() >= int(p.get("level", 1)):
				return {"ok": false, "text": "보드 가득\n(Lv %d)" % int(p["level"])}
			return {"ok": true, "text": "구매 후\n배치"}
		return {"ok": true, "text": "구매"}
	if target.has("board"):
		var row: int = Match._parse_key(target["board"])[0]
		if not GameData.can_place(aid, row):
			return {"ok": false, "text": "%s\n전용" % GameData.ROW_NAME[a["row"]]}
		if occupant == null and src.has("bench") and p.get("board", {}).size() >= int(p.get("level", 1)):
			return {"ok": false, "text": "보드 가득\n(Lv %d)" % int(p["level"])}
		if occupant != null and src.has("board") and not GameData.can_place(occupant["aid"], Match._parse_key(src["board"])[0]):
			return {"ok": false, "text": "교체 불가\n(%s)" % GameData.ROW_NAME[GameData.apostle(occupant["aid"])["row"]]}
		return {"ok": true, "text": "교체" if occupant != null else ""}
	# 대기석
	if occupant != null and src.has("board") and not GameData.can_place(occupant["aid"], Match._parse_key(src["board"])[0]):
		return {"ok": false, "text": "교체 불가"}
	return {"ok": true, "text": "교체" if occupant != null else ""}


## 아티팩트 끌기: 사도에 놓으면 장착, 같은 등급 아티팩트에 놓으면 합성
func _check_art_drop(target: Dictionary) -> Dictionary:
	var art := GameData.artifact(_drag["art_id"])
	if target.has("art"):
		if int(target["art"]) == int(_drag["src"]["art"]):
			return {"ok": false, "text": "", "same": true}
		var other := _find_art(int(target["art"]))
		if other.is_empty():
			return {"ok": false, "text": ""}
		var og: String = GameData.artifact(other["art"]["id"]).get("grade", "")
		if og != art["grade"]:
			return {"ok": false, "text": "등급이 다름\n(%s/%s)" % [GameData.grade_name(art["grade"]), GameData.grade_name(og)]}
		var ng := GameData.next_grade(og)
		if ng == "":
			return {"ok": false, "text": "전설은 합성 불가"}
		return {"ok": true, "text": "합성 → %s\n(보관함으로)" % GameData.grade_name(ng)}
	if target.has("sell"):
		return {"ok": false, "text": ""}
	var u = _unit_at(target)
	if u == null:
		return {"ok": false, "text": ""}
	if not _drag["in_inv"]:
		return {"ok": false, "text": "장착 중인 것은\n옮길 수 없음"}
	if u["arts"].size() >= int(B()["artifact_slots"]):
		return {"ok": false, "text": "장착 칸 가득\n(%d/%d)" % [u["arts"].size(), int(B()["artifact_slots"])]}
	return {"ok": true, "text": "장착 (%d/%d)" % [u["arts"].size() + 1, int(B()["artifact_slots"])]}


func _paint_drag() -> void:
	var hover = _drag.get("hover")
	# 아티팩트 버튼 칠하기
	if _drag.has("art_id"):
		var btns := _art_buttons()
		for uid in btns:
			var b: Button = btns[uid]
			var r := _check_drop({"art": uid})
			var base: Color = UI.GRADE_COLOR[GameData.artifact(_find_art(uid).get("art", {}).get("id", "")).get("grade", "common")]
			var col := Color("5ee39b") if r["ok"] else Color("6b3535")
			if r.get("same", false):
				col = UI.ACCENT
			var on_it: bool = hover != null and hover.has("art") and int(hover["art"]) == uid
			b.add_theme_stylebox_override("normal", UI.box(base.darkened(0.45 if on_it else 0.62), 10, col.lightened(0.3) if on_it else col, 6 if on_it else 3))
			b.modulate.a = 1.0 if r["ok"] or r.get("same", false) else 0.5
	var all := []
	for key in _board_tiles:
		all.append([_board_tiles[key], {"board": key}])
	for i in _bench_tiles.size():
		all.append([_bench_tiles[i], {"bench": i}])
	for pair in all:
		var t: UnitTile = pair[0]
		var target: Dictionary = pair[1]
		var r := _check_drop(target)
		if r.get("same", false):
			t.set_drop("bad")
			t.set_dim(true)
			continue
		if hover != null and hover == target:
			# 결과 글자는 손가락 옆 표시로 보여 주고, 칸에는 놓일 모습만 그린다
			t.set_drop("hover" if r["ok"] else "hover_bad", "", _drag["aid"] if r["ok"] and _unit_at(target) == null else "")
		else:
			t.set_drop("ok" if r["ok"] else "bad")
	# 손가락 옆 결과 표시
	var tag_text := ""
	var tag_ok := true
	if hover != null:
		var hr := _check_drop(hover)
		if not hr.get("same", false):
			tag_ok = hr["ok"]
			tag_text = String(hr["text"]).replace("\n", " ")
			if tag_text == "":
				tag_text = "놓기"
	if _drag.has("tag"):
		_drag["tag"].visible = tag_text != ""
		_drag["tag_lbl"].text = tag_text
		_drag["tag_lbl"].add_theme_color_override("font_color", UI.GOOD if tag_ok else UI.BAD)
	# 판매 칸
	var sell_ok: bool = not _drag["src"].has("shop") and not _drag.has("art_id")
	var on_sell: bool = hover != null and hover.has("sell")
	var col := Color("b55a5a") if sell_ok else Color("3a2525")
	_sell_btn.add_theme_stylebox_override("normal", UI.box(Color("8a3030") if on_sell and sell_ok else Color("5a2b2b"), 14, Color("ffb0b0") if on_sell and sell_ok else col, 6 if on_sell else 2))
	if sell_ok:
		_sell_btn.text = "판매\n+%d골드" % _sell_value(_drag["unit"])
		_sell_btn.add_theme_font_size_override("font_size", 28 if on_sell else 26)
		_sell_btn.add_theme_color_override("font_color", Color("fff3b0"))
		if not on_sell:
			_sell_btn.add_theme_stylebox_override("normal", UI.box(Color("6a2f2f"), 14, UI.ACCENT, 4))


func _clear_drag_paint() -> void:
	for key in _board_tiles:
		_board_tiles[key].set_drop("")
		_board_tiles[key].set_dim(false)
	for t in _bench_tiles:
		t.set_drop("")
		t.set_dim(false)
	_sell_btn.add_theme_stylebox_override("normal", UI.box(Color("5a2b2b"), 14, Color("b55a5a"), 2))
	_sell_btn.add_theme_font_size_override("font_size", 22)
	_sell_btn.remove_theme_color_override("font_color")


func _finish_drag() -> void:
	var target = _drag.get("hover")
	var src: Dictionary = _drag["src"]
	var aid: String = _drag["aid"]
	if _drag.has("ghost"):
		_drag["ghost"].queue_free()
	if _drag.has("tag"):
		_drag["tag"].queue_free()
	for t in _shop_tiles:
		t.set_dim(false)
	var info := {}
	if target != null:
		info = _check_drop(target)
	_drag["active"] = false   # 이후 refresh 에서 다시 칠하지 않도록
	_clear_drag_paint()
	if target == null or info.get("same", false):
		refresh()
		return
	if not info["ok"]:
		if info["text"] != "":
			_toast(String(info["text"]).replace("\n", " "))
		refresh()
		return
	_vibrate(25)
	if src.has("art"):
		if target.has("art"):
			App.session.submit({"t": "art_merge", "a": int(src["art"]), "b": int(target["art"])})
			_vibrate(40)
		else:
			App.session.submit({"t": "equip", "art": int(src["art"]), "loc": target})
			sel = {"unit": target}
	elif target.has("sell"):
		App.session.submit({"t": "sell", "loc": src})
	elif src.has("shop"):
		var i: int = src["shop"]
		if target.has("board") and not GameData.personality_options(aid).is_empty():
			_ask_personality(aid, func(pers): App.session.submit({"t": "buy", "i": i, "to": target, "pers": pers}))
		else:
			App.session.submit({"t": "buy", "i": i, "to": target})
	else:
		_do_move(src, target)
	refresh()


# ─────────────────────────────── 팝업 ───────────────────────────────

func _modal(title: String, kind: String = "") -> VBoxContainer:
	UI.clear(_overlay)
	if Tips.inst:
		Tips.inst.dismiss()
	_overlay_kind = kind
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 바깥(어두운 곳)을 누르면 닫기 — 게임 종료 화면은 제외
	if kind != "over":
		dim.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed \
					and Rect2(Vector2.ZERO, dim.size).has_point(ev.position):
				if _overlay_kind == "offer":
					_offer_hidden = true
				_close_modal()
				refresh())
	_overlay.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(cc)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		var txt := UI.rich_desc(art.get("text", ""), 18, UI.TEXT.darkened(0.08))
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
	# 시상대: 1~3위의 대표 사도(별·코스트 높은 순 3명)가 모션으로
	var podium := HBoxContainer.new()
	podium.alignment = BoxContainer.ALIGNMENT_CENTER
	podium.add_theme_constant_override("separation", 30)
	v.add_child(podium)
	for idx in mini(3, list.size()):
		var p: Dictionary = list[idx]
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_END
		podium.add_child(col)
		var units := []
		for k in p.get("board", {}):
			units.append(p["board"][k])
		units.sort_custom(func(a, b): return int(a["star"]) * 10 + GameData.cost_of.get(a["aid"], 1) > int(b["star"]) * 10 + GameData.cost_of.get(b["aid"], 1))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", -20)
		col.add_child(row)
		for u in units.slice(0, 3):
			if MotionSprite.available(u["aid"]) and Settings.flag("battle_motion"):
				var sp := MotionSprite.new(u["aid"])
				sp.face_right = true
				sp.shadow = true
				var h := 150.0 if idx == 0 else 120.0
				sp.custom_minimum_size = Vector2(h * 0.75, h)
				sp.box = h / 0.82
				sp.play("Victory" if sp.has_anim("Victory") else "Idle")
				row.add_child(sp)
			else:
				row.add_child(UI.tex_rect(UI.portrait(u["aid"]), Vector2(90, 90), true))
		var medal_col: Color = [UI.ACCENT, Color("d8dde8"), Color("e0a070")][idx]
		col.add_child(UI.label("%d위  %s" % [idx + 1, p["name"]], 30 if idx == 0 else 24, medal_col, HORIZONTAL_ALIGNMENT_CENTER))
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
