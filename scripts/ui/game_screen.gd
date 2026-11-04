class_name GameScreen
extends Control
## 게임 화면: 상단 정보 / 플레이어·시너지 / 보드·전투 / 상세·보관함 / 대기석·상점.
## 조작: 누르고(선택) → 누르기(이동/장착). 터치와 마우스 모두 같은 방식.

const STAT_NAME := {
	"hp": "최대 HP", "atk": "공격력", "patk": "물리 공격력", "matk": "마법 공격력", "def": "방어력",
	"pdef": "물리 방어력", "mdef": "마법 방어력", "aspd": "공격 속도", "crit": "치명타", "critdmg": "치명 피해",
	"critres": "치명타 저항", "critdmgres": "치명 피해 저항", "heal_out": "치유량", "heal_in": "HP 회복량",
}

var sel := {}                 # {"unit": loc} 또는 {"art": uid}
var merge_mode := false
var _last_phase := ""
var _last_round := -1
var _offer_hidden := false

# 위젯
var _round_lbl: Label
var _phase_lbl: Label
var _gold_lbl: Label
var _lvl_lbl: Label
var _hp_lbl: Label
var _ready_btn: Button
var _offer_btn: Button
var _players_box: VBoxContainer
var _syn_box: VBoxContainer
var _center: Control
var _board_root: Control
var _board_tiles := {}        # "r,s" -> UnitTile
var _battle_view: BattleView
var _detail_box: VBoxContainer
var _inv_grid: GridContainer
var _bench_tiles: Array = []
var _shop_tiles: Array = []
var _reroll_btn: Button
var _xp_btn: Button
var _sell_btn: Button
var _merge_btn: Button
var _overlay: Control
var _overlay_kind := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	Session.state_changed.connect(refresh)
	refresh()


func me() -> Dictionary:
	return Session.state.get("players", {}).get(Session.my_pid, {})


func B() -> Dictionary:
	return GameData.balance


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

	# 상단 바
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	root.add_child(top)
	_round_lbl = UI.label("", 28, UI.ACCENT)
	top.add_child(_round_lbl)
	_phase_lbl = UI.label("", 26)
	_phase_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_phase_lbl)
	_hp_lbl = UI.label("", 26, UI.GOOD)
	top.add_child(_hp_lbl)
	_gold_lbl = UI.label("", 26, UI.ACCENT)
	top.add_child(_gold_lbl)
	_lvl_lbl = UI.label("", 26)
	top.add_child(_lvl_lbl)
	_offer_btn = UI.button("아티팩트 선택", 22, Vector2(200, 52), Color("8a5a1f"))
	_offer_btn.pressed.connect(func():
		_offer_hidden = false
		refresh())
	top.add_child(_offer_btn)
	_ready_btn = UI.button("준비 완료", 22, Vector2(170, 52), Color("3d6b4f"))
	_ready_btn.pressed.connect(func(): Session.submit({"t": "ready", "on": not me().get("ready", false)}))
	top.add_child(_ready_btn)
	var quit := UI.button("나가기", 22, Vector2(120, 52), Color("6b3d3d"))
	quit.pressed.connect(_confirm_quit)
	top.add_child(quit)

	# 가운데
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 10)
	root.add_child(mid)

	var left := UI.panel()
	left.custom_minimum_size.x = 330
	mid.add_child(left)
	var lscroll := ScrollContainer.new()
	lscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(lscroll)
	var lv := VBoxContainer.new()
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_theme_constant_override("separation", 6)
	lscroll.add_child(lv)
	lv.add_child(UI.label("플레이어", 22, UI.ACCENT))
	_players_box = VBoxContainer.new()
	lv.add_child(_players_box)
	lv.add_child(UI.label("시너지", 22, UI.ACCENT))
	_syn_box = VBoxContainer.new()
	lv.add_child(_syn_box)

	_center = UI.panel(Color("202333"))
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(_center)
	var cstack := Control.new()
	_center.add_child(cstack)
	_board_root = _build_board()
	_board_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	cstack.add_child(_board_root)
	_battle_view = BattleView.new()
	_battle_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_battle_view.visible = false
	cstack.add_child(_battle_view)

	var right := UI.panel()
	right.custom_minimum_size.x = 430
	mid.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right.add_child(rv)
	var dscroll := ScrollContainer.new()
	dscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(dscroll)
	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_theme_constant_override("separation", 4)
	dscroll.add_child(_detail_box)
	var invh := HBoxContainer.new()
	rv.add_child(invh)
	var inv_lbl := UI.label("보관함", 22, UI.ACCENT)
	inv_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	invh.add_child(inv_lbl)
	_merge_btn = UI.button("합성", 20, Vector2(100, 46))
	_merge_btn.pressed.connect(_on_merge_pressed)
	invh.add_child(_merge_btn)
	var iscroll := ScrollContainer.new()
	iscroll.custom_minimum_size.y = 150
	iscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(iscroll)
	_inv_grid = GridContainer.new()
	_inv_grid.columns = 3
	_inv_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	iscroll.add_child(_inv_grid)

	# 하단: 대기석 + 상점
	var bench := HBoxContainer.new()
	bench.add_theme_constant_override("separation", 8)
	bench.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(bench)
	bench.add_child(UI.label("대기석", 22, UI.SUB))
	for i in int(B()["bench_size"]):
		var t := UnitTile.new(Vector2(122, 122))
		var loc := {"bench": i}
		t.pressed.connect(func(): _on_tile(loc))
		bench.add_child(t)
		_bench_tiles.append(t)
	_sell_btn = UI.button("판매", 22, Vector2(140, 122), Color("6b3d3d"))
	_sell_btn.pressed.connect(_on_sell)
	bench.add_child(_sell_btn)

	var shop := HBoxContainer.new()
	shop.add_theme_constant_override("separation", 8)
	shop.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(shop)
	for i in int(B()["shop_size"]):
		var t := UnitTile.new(Vector2(210, 112))
		var idx: int = i
		t.pressed.connect(func(): Session.submit({"t": "buy", "i": idx}))
		shop.add_child(t)
		_shop_tiles.append(t)
	_reroll_btn = UI.button("새로고침 (%d)" % int(B()["reroll_cost"]), 22, Vector2(190, 112), Color("3b5b8f"))
	_reroll_btn.pressed.connect(func(): Session.submit({"t": "reroll"}))
	shop.add_child(_reroll_btn)
	_xp_btn = UI.button("경험치 +%d (%d)" % [int(B()["xp_amount"]), int(B()["xp_cost"])], 22, Vector2(190, 112), Color("5b3b8f"))
	_xp_btn.pressed.connect(func(): Session.submit({"t": "buy_xp"}))
	shop.add_child(_xp_btn)

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)


func _build_board() -> Control:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 8)
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
		var l := UI.label(GameData.ROW_NAME[GameData.ROWS[r]], 24, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER)
		l.custom_minimum_size.x = 160
		heads.add_child(l)
	for s in int(B()["board_slots"]):
		for r in [2, 1, 0]:
			var t := UnitTile.new(Vector2(160, 160))
			var key := Match.key_of(r, s)
			var loc := {"board": key}
			t.pressed.connect(func(): _on_tile(loc))
			grid.add_child(t)
			_board_tiles[key] = t
	v.add_child(UI.label("적 방향 ▶", 20, UI.SUB, HORIZONTAL_ALIGNMENT_RIGHT))
	return v


# ─────────────────────────────── 갱신 ───────────────────────────────

func _process(_delta: float) -> void:
	var st := Session.state
	if st.is_empty():
		return
	var phase: String = st.get("phase", "")
	var names := {"prep": "준비", "battle": "전투", "result": "결과", "over": "게임 종료"}
	_phase_lbl.text = "%s  %d초" % [names.get(phase, phase), ceili(float(st.get("phase_end", 0.0)))] if phase != "over" else "게임 종료"


func refresh() -> void:
	var st := Session.state
	if st.is_empty():
		return
	var p := me()
	var phase: String = st["phase"]
	if phase != _last_phase or int(st["round"]) != _last_round:
		if phase == "prep":
			_offer_hidden = false
		sel = {}
		merge_mode = false
		_last_phase = phase
		_last_round = int(st["round"])
		if phase == "battle":
			_start_battle_view()
	_round_lbl.text = "라운드 %d" % int(st["round"])
	if not p.is_empty():
		_hp_lbl.text = "♥ %d" % int(p["hp"])
		_gold_lbl.text = "골드 %d" % int(p["gold"])
		var need := int(B()["xp_to_next"][mini(int(p["level"]), 8) - 1]) if int(p["level"]) < int(B()["max_level"]) else 0
		_lvl_lbl.text = "Lv %d  (%d/%d)" % [int(p["level"]), int(p["xp"]), need]
		_ready_btn.text = "준비 취소" if p.get("ready", false) else "준비 완료"
	var prep: bool = phase == "prep" and p.get("alive", false)
	_ready_btn.disabled = not prep
	_reroll_btn.disabled = not prep
	_xp_btn.disabled = not prep
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


func _refresh_players() -> void:
	UI.clear(_players_box)
	var list: Array = Session.state["players"].values()
	list.sort_custom(func(a, b):
		if a["alive"] != b["alive"]:
			return a["alive"]
		return a["hp"] > b["hp"] if a["alive"] else a["place"] < b["place"])
	for p in list:
		var txt := "%s  ♥%d  Lv%d" % [p["name"], maxi(0, int(p["hp"])), int(p["level"])]
		if not p["alive"]:
			txt = "%s  %d위" % [p["name"], int(p["place"])]
		elif not p["connected"]:
			txt += "  (끊김)"
		var col := UI.ACCENT if p["id"] == Session.my_pid else (UI.TEXT if p["alive"] else UI.SUB)
		_players_box.add_child(UI.label(txt, 20, col))


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
		var tl: Array = syn["tiers"]
		var steps := []
		for t in tl:
			steps.append(str(int(t)))
		var active: int = tiers.get(n, 0)
		var l := UI.label("%s %d  (%s)" % [n, counts[n], "/".join(steps)], 20, UI.GOOD if active > 0 else UI.SUB)
		l.tooltip_text = syn.get("desc", "")
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		_syn_box.add_child(l)
		if active > 0:
			_syn_box.add_child(UI.wrap_label("  " + syn.get("desc", ""), 15))
	if names.is_empty():
		_syn_box.add_child(UI.label("보드에 사도를 배치하세요", 18, UI.SUB))


func _refresh_board() -> void:
	var p := me()
	for key in _board_tiles:
		var t: UnitTile = _board_tiles[key]
		var u = p.get("board", {}).get(key)
		if u == null:
			var row: int = Match._parse_key(key)[0]
			t.set_empty("")
			var hl := false
			if sel.has("unit"):
				var su = _unit_at(sel["unit"])
				hl = su != null and GameData.can_place(su["aid"], row)
			t.set_highlight(hl)
		else:
			t.set_unit(u, _pers_tag(u))
			t.set_highlight(false)
		t.set_selected(sel.get("unit", {}) == {"board": key})


func _pers_tag(u: Dictionary) -> String:
	var a := GameData.apostle(u["aid"])
	var p: String = a.get("personality", "")
	if p == "공명" or p == "이면":
		return "%s→%s" % [p, u["pers"]] if u["pers"] != "" else p
	return p


func _refresh_bench_shop() -> void:
	var p := me()
	var bench: Array = p.get("bench", [])
	for i in _bench_tiles.size():
		var t: UnitTile = _bench_tiles[i]
		var u = bench[i] if i < bench.size() else null
		if u == null:
			t.set_empty("")
		else:
			t.set_unit(u, _pers_tag(u))
		t.set_selected(sel.get("unit", {}) == {"bench": i})
	var shop: Array = p.get("shop", [])
	for i in _shop_tiles.size():
		var t: UnitTile = _shop_tiles[i]
		var aid: String = shop[i] if i < shop.size() else ""
		if aid == "":
			t.set_empty("")
		else:
			var a := GameData.apostle(aid)
			t.set_unit({"aid": aid}, "%d골드 · %s %s · %s" % [GameData.cost_of[aid], a["personality"], a["race"], GameData.ROW_NAME[a["row"]]])
		t.disabled = aid == ""


func _refresh_inventory() -> void:
	UI.clear(_inv_grid)
	var p := me()
	for a in p.get("inv", []):
		var art := GameData.artifact(a["id"])
		var b := UI.button(art.get("name", "?"), 16, Vector2(130, 56), UI.GRADE_COLOR[art["grade"]].darkened(0.55))
		b.clip_text = true
		b.tooltip_text = art.get("name", "")
		if sel.get("art", -1) == int(a["uid"]):
			b.add_theme_stylebox_override("normal", UI.box(UI.GRADE_COLOR[art["grade"]].darkened(0.3), 10, UI.ACCENT, 4))
		var uid := int(a["uid"])
		b.pressed.connect(func(): _on_art(uid))
		_inv_grid.add_child(b)
	if p.get("inv", []).is_empty():
		_inv_grid.add_child(UI.label("비어 있음", 18, UI.SUB))
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
			_detail_art(where["art"]["id"])
			return
	_detail_box.add_child(UI.label("도움말", 24, UI.ACCENT))
	for line in [
		"· 상점의 사도를 눌러 구매합니다.",
		"· 사도를 누른 뒤 빈칸(또는 다른 사도)을 누르면 이동합니다.",
		"· 사도는 자기 열(전열/중열/후열)에만 놓을 수 있습니다. 모든열은 어디든 가능.",
		"· 같은 사도 3명이 모이면 자동 합성(★ 증가). 합성·판매 시 아티팩트는 보관함으로.",
		"· 보관함의 아티팩트를 누른 뒤 사도를 누르면 장착 (최대 3개, 임의 해제 불가).",
		"· 아티팩트를 고르고 [합성] → 같은 등급 다른 아티팩트를 누르면 다음 등급 무작위 1개.",
		"· 공명·이면 사도는 보드에 올릴 때 성격을 고릅니다.",
	]:
		_detail_box.add_child(UI.wrap_label(line, 18))


func _detail_unit(u: Dictionary) -> void:
	var aid: String = u["aid"]
	var a := GameData.apostle(aid)
	var star := int(u.get("star", 1))
	_detail_box.add_child(UI.label("%s  %s" % [a["name"], UI.stars(star)], 28, UI.ACCENT))
	var pers: String = a["personality"]
	if u.get("pers", "") != "":
		pers += " → " + u["pers"]
	_detail_box.add_child(UI.label("%s · %s%s" % [pers, a["race"], " · 엘다인" if a.get("eldyne", false) else ""], 20, UI.pers_color(aid, u.get("pers", ""))))
	_detail_box.add_child(UI.label("%s · %s · %s · %d골드" % [GameData.ROW_NAME[a["row"]], GameData.ROLE_NAME[a["role"]], GameData.DAMAGE_NAME[a["damage"]], GameData.cost_of.get(aid, 1)], 18, UI.SUB))
	var bs := Rules.base_stats(aid, star)
	_detail_box.add_child(UI.label("HP %d · 공격력 %d · 방어력 %d · 공속 %.2f" % [bs["hp"], bs["atk"], bs["def"], bs["aspd"]], 18))
	_detail_box.add_child(UI.label("※ 스킬 효과는 현재 역할별 공통 효과로 동작 (원작 스킬 구현 예정)", 14, UI.SUB))
	for k in ["fresh", "senior", "passive"]:
		var sk: Dictionary = a.get("skills", {}).get(k, {})
		if sk.is_empty():
			continue
		var kn: String = {"fresh": "저학년", "senior": "고학년", "passive": "패시브"}[k]
		_detail_box.add_child(UI.label("[%s] %s" % [kn, sk["name"]], 19, UI.TEXT))
		_detail_box.add_child(UI.wrap_label(sk["desc"], 15))
	for n in ["1", "2", "3"]:
		var asd: Dictionary = a.get("aside", {}).get(n, {})
		if asd.is_empty():
			continue
		var on := star >= int(n)
		_detail_box.add_child(UI.label("어사이드 %s성 %s: %s" % [n, "✔" if on else "🔒", asd["name"]], 19, UI.GOOD if on else UI.SUB))
		_detail_box.add_child(UI.wrap_label(asd["desc"], 15))
	if a.get("aside", {}).is_empty():
		_detail_box.add_child(UI.label("어사이드 정보 없음", 16, UI.SUB))
	_detail_box.add_child(UI.label("아티팩트 %d/%d" % [u.get("arts", []).size(), int(B()["artifact_slots"])], 20, UI.ACCENT))
	for art in u.get("arts", []):
		var info := GameData.artifact(art["id"])
		var fav := " ♥애착" if info.get("owner", "") == a["name"] else ""
		var b := UI.button("%s [%s]%s" % [info["name"], GameData.grade_name(info["grade"]), fav], 17, Vector2(0, 48), UI.GRADE_COLOR[info["grade"]].darkened(0.55))
		var uid := int(art["uid"])
		b.pressed.connect(func(): _on_art(uid))
		_detail_box.add_child(b)
	if sel.has("unit"):
		_detail_box.add_child(UI.label("판매 가격: %d골드" % (GameData.cost_of.get(aid, 1) * int(pow(3, star - 1))), 18, UI.SUB))


func _detail_art(art_id: String) -> void:
	var a := GameData.artifact(art_id)
	_detail_box.add_child(UI.label(a["name"], 26, UI.GRADE_COLOR[a["grade"]]))
	_detail_box.add_child(UI.label("%s 등급%s" % [GameData.grade_name(a["grade"]), " · 글로벌 전용" if a.get("region", "") == "global" else ""], 18, UI.SUB))
	for k in a.get("stats", {}):
		_detail_box.add_child(UI.label("%s +%s%%" % [STAT_NAME.get(k, k), str(a["stats"][k])], 19))
	_detail_box.add_child(UI.wrap_label(a.get("text", ""), 17, UI.TEXT))
	if a.get("nostack", false):
		_detail_box.add_child(UI.label("부가 효과는 한 사도에 중첩되지 않음", 15, UI.SUB))
	if a.get("owner", "") != "":
		_detail_box.add_child(UI.label("애착 사도: %s" % a["owner"], 19, UI.ACCENT))
		_detail_box.add_child(UI.wrap_label(a.get("fav", ""), 15))
		_detail_box.add_child(UI.label("※ 애착 효과는 다음 단계에서 구현 예정", 14, UI.SUB))


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


func _on_tile(loc: Dictionary) -> void:
	if Session.state.get("phase", "") != "prep":
		# 전투 중에도 정보는 볼 수 있다
		if _unit_at(loc) != null:
			sel = {"unit": loc}
			refresh()
		return
	var u = _unit_at(loc)
	if sel.has("art"):
		if u != null:
			var where := _find_art(int(sel["art"]))
			if not where.is_empty() and where.has("inv"):
				Session.submit({"t": "equip", "art": int(sel["art"]), "loc": loc})
				sel = {}
				refresh()
				return
		sel = {"unit": loc} if u != null else {}
		refresh()
		return
	if sel.has("unit"):
		var from: Dictionary = sel["unit"]
		if from == loc:
			sel = {}
			refresh()
			return
		var mover = _unit_at(from)
		sel = {}
		if mover != null and loc.has("board") and from.has("bench") and not GameData.personality_options(mover["aid"]).is_empty():
			_ask_personality(mover["aid"], func(pers): Session.submit({"t": "move", "from": from, "to": loc, "pers": pers}))
		elif mover != null:
			Session.submit({"t": "move", "from": from, "to": loc})
		refresh()
		return
	if u != null:
		sel = {"unit": loc}
	refresh()


func _on_art(uid: int) -> void:
	if merge_mode and sel.has("art") and int(sel["art"]) != uid:
		Session.submit({"t": "art_merge", "a": int(sel["art"]), "b": uid})
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
		Session.toast.emit("같은 등급의 다른 아티팩트를 누르세요 (장착 중인 것도 가능)")
	else:
		Session.toast.emit("먼저 합성할 아티팩트를 고르세요")
	refresh()


func _on_sell() -> void:
	if sel.has("unit") and _unit_at(sel["unit"]) != null:
		Session.submit({"t": "sell", "loc": sel["unit"]})
		sel = {}
		refresh()
	else:
		Session.toast.emit("팔 사도를 먼저 고르세요")


# ─────────────────────────────── 팝업 ───────────────────────────────

func _modal(title: String, kind: String = "") -> VBoxContainer:
	UI.clear(_overlay)
	_overlay_kind = kind
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(cc)
	var p := UI.panel(UI.PANEL, 16)
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	v.add_child(UI.label(title, 32, UI.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	return v


func _close_modal() -> void:
	UI.clear(_overlay)
	_overlay_kind = ""


func _ask_personality(aid: String, cb: Callable) -> void:
	var v := _modal("%s의 성격을 고르세요" % GameData.apostle(aid)["name"], "pers")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)
	for pers in GameData.personality_options(aid):
		var b := UI.button(pers, 28, Vector2(150, 90), UI.PERS_COLOR.get(pers, Color.GRAY).darkened(0.4))
		var chosen: String = pers
		b.pressed.connect(func():
			_close_modal()
			cb.call(chosen))
		h.add_child(b)
	var cancel := UI.button("취소", 22, Vector2(0, 56))
	cancel.pressed.connect(func():
		_close_modal()
		refresh())
	v.add_child(cancel)


func _refresh_overlay() -> void:
	var st := Session.state
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
	var v := _modal("아티팩트 선택 — 하나를 고르세요 (칸마다 다시 뽑기 1회)", "offer")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	v.add_child(h)
	for i in offer["options"].size():
		var art := GameData.artifact(offer["options"][i])
		var card := UI.panel(UI.GRADE_COLOR[art["grade"]].darkened(0.6), 14)
		card.custom_minimum_size = Vector2(380, 420)
		h.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 6)
		card.add_child(cv)
		cv.add_child(UI.label(art["name"], 26, UI.GRADE_COLOR[art["grade"]]))
		cv.add_child(UI.label(GameData.grade_name(art["grade"]) + (" · 애착: " + art["owner"] if art.get("owner", "") != "" else ""), 18, UI.SUB))
		for k in art.get("stats", {}):
			cv.add_child(UI.label("%s +%s%%" % [STAT_NAME.get(k, k), str(art["stats"][k])], 18))
		var txt := UI.wrap_label(art.get("text", ""), 16, UI.TEXT)
		txt.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cv.add_child(txt)
		var idx: int = i
		var rr := UI.button("다시 뽑기" if not offer["rerolled"][i] else "다시 뽑기 사용함", 20, Vector2(0, 54))
		rr.disabled = offer["rerolled"][i]
		rr.pressed.connect(func(): Session.submit({"t": "art_reroll", "i": idx}))
		cv.add_child(rr)
		var pick := UI.button("선택", 22, Vector2(0, 60), Color("3d6b4f"))
		pick.pressed.connect(func():
			Session.submit({"t": "art_pick", "i": idx})
			_close_modal())
		cv.add_child(pick)
	var hide := UI.button("잠시 접기 (보드 보기)", 20, Vector2(0, 54))
	hide.pressed.connect(func():
		_offer_hidden = true
		_close_modal()
		refresh())
	v.add_child(hide)


func _show_game_over() -> void:
	var st := Session.state
	var v := _modal("게임 종료", "over")
	var list: Array = st["players"].values()
	list.sort_custom(func(a, b): return int(a["place"]) < int(b["place"]))
	for p in list:
		var col := UI.ACCENT if p["id"] == Session.my_pid else UI.TEXT
		v.add_child(UI.label("%d위  %s" % [int(p["place"]), p["name"]], 28, col))
	var b := UI.button("처음 화면으로", 24, Vector2(0, 64))
	b.pressed.connect(Session.leave)
	v.add_child(b)


func _confirm_quit() -> void:
	var v := _modal("게임에서 나갈까요?", "quit")
	v.add_child(UI.wrap_label("방장이 나가면 게임이 끝납니다. 참가자는 같은 라운드 안에 다시 들어오면 이어서 할 수 있습니다.", 18))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)
	var yes := UI.button("나가기", 22, Vector2(180, 60), Color("6b3d3d"))
	yes.pressed.connect(Session.leave)
	h.add_child(yes)
	var no := UI.button("계속하기", 22, Vector2(180, 60))
	no.pressed.connect(_close_modal)
	h.add_child(no)


# ─────────────────────────────── 전투 화면 ───────────────────────────────

func _start_battle_view() -> void:
	var st := Session.state
	var mine := {}
	var side := 0
	for bt in st.get("battles", []):
		if bt["a"] == Session.my_pid:
			mine = bt
			side = 0
		elif bt["b"] == Session.my_pid:
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
