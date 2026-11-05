class_name BattleView
extends Control
## 전투 재생 화면. 방장과 같은 입력(군대 + seed)으로 이 기기에서 전투를 다시 계산해 보여준다.
## 결과(승패/피해)는 방장의 계산이 기준이다.

const TILE := Vector2(150, 150)
const GAP := 12.0

var _tiles := {}          # 유닛 index -> UnitTile (모션이 없거나 모션을 끈 경우의 카드)
var _sprites := {}        # 유닛 index -> MotionSprite (모션 파일이 있는 사도만)
var _plates := {}         # 유닛 index -> BattlePlate (발밑 이름표·체력, 맨 위 레이어)
var _plate_layer: Control
var _box := 200.0         # 모션 그림 크기(px)
var _card_k := 1.0        # 카드 크기 배율
var _ppu_v := Vector2(60, 80)   # 전장 1칸 → 화면 px
var _origin := Vector2.ZERO     # 전장 (0, 첫 줄 발 위치) 의 화면 위치
var _float_n := {}        # 유닛 index -> 떠오르는 글자 개수 (겹치지 않게 비켜 놓기)
var _status_until := {}   # 유닛 index -> 상태 표시가 끝나는 전투 시간
var _units: Array = []
var _hp := {}
var _sh := {}
var _events: Array = []
var _ev_i := 0
var _t := 0.0
var _speed := 1.0
var _my_side := 0
var _title: Label
var _banner: Label
var _field: Control
var _speed_btn: Button
var _playing := false
var _divider: ColorRect
var _left_tag: Label
var _right_tag: Label
var _dtype := {}          # 유닛 index -> "physical"/"magic"
var _anim := {}           # 유닛 index -> {lunge, dir, flash, pulse, dead} (임시 모션)
var _clock := 0.0
var _stats := {}          # 유닛 index -> {dealt, taken, heal}
var _stats_panel: Control
var _fx: BattleFx
var _udata := {}          # 유닛 index -> 스냅샷 (열·진영)
var _shake := 0.0
var _skill_banner: Label
var _full_btn: Button
signal full_toggled
var _pos := {}            # 유닛 index -> 전투 계산 좌표 (목표)
var _disp := {}           # 유닛 index -> 화면에 보이는 좌표 (목표로 부드럽게 이동)


func _ready() -> void:
	_title = UI.outlined("", 30, UI.TEXT, 8)
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 6
	add_child(_title)
	_divider = ColorRect.new()
	_divider.color = Color(1, 1, 1, 0.08)
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_divider)
	_left_tag = UI.label("우리 편", 22, UI.GOOD, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_left_tag)
	_right_tag = UI.label("상대", 22, UI.BAD, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_right_tag)
	_field = Control.new()
	_field.set_anchors_preset(Control.PRESET_FULL_RECT)
	_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_field)
	_fx = BattleFx.new()
	add_child(_fx)
	_plate_layer = Control.new()
	_plate_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_plate_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plate_layer)
	_skill_banner = UI.outlined("", 34, UI.ACCENT, 9)
	_skill_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_skill_banner.offset_top = 64
	_skill_banner.offset_bottom = 120
	_skill_banner.modulate.a = 0.0
	_skill_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_skill_banner)
	_banner = UI.label("", 64, UI.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 12)
	add_child(_banner)
	_speed_btn = UI.button("속도 x1", 20, Vector2(120, 48))
	_speed_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_speed_btn.offset_left = -130
	_speed_btn.offset_top = -56
	_speed_btn.offset_right = -8
	_speed_btn.offset_bottom = -8
	_speed_btn.pressed.connect(func():
		# 1 → 1.25 → 1.5 → 2 → 1 …
		var steps := [1.0, 1.25, 1.5, 2.0]
		var at := 0
		for k in steps.size():
			if absf(steps[k] - _speed) < 0.01:
				at = k
		_speed = steps[(at + 1) % steps.size()]
		_speed_btn.text = speed_text(_speed))
	add_child(_speed_btn)
	_full_btn = UI.button("", 20, Vector2(150, 48))
	_full_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_full_btn.offset_left = -290
	_full_btn.offset_top = -56
	_full_btn.offset_right = -138
	_full_btn.offset_bottom = -8
	_full_btn.text = "기본 보기" if UI.battle_full() else "크게 보기"
	_full_btn.pressed.connect(func():
		Settings.set_value("battle_full", 2 if UI.battle_full() else 1)
		_full_btn.text = "기본 보기" if UI.battle_full() else "크게 보기"
		full_toggled.emit())
	add_child(_full_btn)
	resized.connect(_layout)


static func speed_text(v: float) -> String:
	return "속도 x" + (str(int(v)) if is_equal_approx(v, roundf(v)) else str(snappedf(v, 0.01)))


func setup(bt: Dictionary, my_side: int, name_a: String, name_b: String) -> void:
	_my_side = my_side
	UI.clear(_field)
	UI.clear(_plate_layer)
	_tiles.clear()
	_sprites.clear()
	_plates.clear()
	_float_n.clear()
	_status_until.clear()
	_anim.clear()
	_stats.clear()
	if _stats_panel and is_instance_valid(_stats_panel):
		_stats_panel.queue_free()
	_stats_panel = null
	_hp.clear()
	_sh.clear()
	_udata.clear()
	_pos.clear()
	_disp.clear()
	_fx.clear_all()
	_speed = Settings.num("battle_speed")
	_speed_btn.text = speed_text(_speed)
	_banner.text = ""
	var sim := BattleSim.new(bt["army_a"], bt["army_b"], int(bt["seed"]))
	var res := sim.run()
	# 결과 검증: 같은 입력이면 방장 계산과 같아야 한다 (다르면 알림 — 점수는 방장 결과)
	if bt.has("winner") and (int(res["winner"]) != int(bt["winner"]) or int(res["survivors"]) != int(bt["survivors"])):
		App.session.report_mismatch({"round": App.session.state.get("round", 0), "a": bt.get("a", ""), "b": bt.get("b", ""),
			"host": [bt["winner"], bt["survivors"]], "mine": [res["winner"], res["survivors"]]})
	_events = res["events"]
	_units = sim.unit_snapshots()
	_ev_i = 0
	_t = 0.0
	_playing = true
	var left := name_a if my_side == 0 else name_b
	var right := name_b if my_side == 0 else name_a
	_title.text = "%s   VS   %s" % [left, right]
	_left_tag.text = left
	_right_tag.text = right
	for u in _units:
		_add_unit(u)
	_layout()
	_update_bars()
	_say_spawn.call_deferred()


## 유닛 하나의 그림·이름표 만들기 (처음 + 전투 중 소환)
func _add_unit(u: Dictionary) -> void:
	var my_side := _my_side
	var i: int = u["i"]
	_udata[i] = u
	if not u.get("summon", false):   # 소환물 위치는 바로 뒤의 "pos" 이벤트로
		_pos[i] = _start_pos(u)
		_disp[i] = _pos[i]
	if Settings.flag("battle_motion") and MotionSprite.available(u["aid"]):
		MotionSprite.preload_anims(u["aid"], ["Idle", "Move", "Attack1_1"])
		var sp := MotionSprite.new(u["aid"])
		sp.face_right = u["side"] == my_side   # 왼쪽(우리 편)은 오른쪽을 봄
		sp.shadow = true
		if u.get("monster", false):
			sp.modulate = Color(0.45, 0.32, 0.62)   # 그림자 몬스터
		if u.get("summon", false):
			sp.modulate = Color(0.8, 0.9, 1.0, 0.85)
		_field.add_child(sp)
		_sprites[i] = sp
	else:
		var tile := UnitTile.new(TILE)
		tile.set_unit({"aid": u["aid"], "star": u["star"], "pers": u["pers"]})
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_field.add_child(tile)
		_tiles[i] = tile
	var pl := BattlePlate.new()
	pl.uname = u["name"]
	pl.star = int(u["star"]) if not u.get("summon", false) else 1
	pl.mine = int(u["side"]) == my_side
	_plate_layer.add_child(pl)
	_plates[i] = pl
	_dtype[i] = GameData.apostle(u["aid"]).get("damage", "physical")
	_anim[i] = {"lunge": 0.0, "dir": Vector2.ZERO, "flash": 0.0, "pulse": 0.0, "dead": false}
	_hp[i] = float(u["max_hp"])
	_sh[i] = 0.0


# ─────────────────────────────── 위치 (이동하며 싸우기) ───────────────────────────────
## 전투 계산의 좌표(x: 진영 사이 거리, y: 칸) → 전장 안 좌표. 내가 오른쪽 진영이면 좌우를 뒤집는다.

func _mv() -> Dictionary:
	return GameData.balance["move"]


func _span() -> Vector2:
	return BattleSim.field_size()


## 처음 위치 (전투 계산과 같은 식)
func _start_pos(u: Dictionary) -> Vector2:
	return BattleSim.start_xy(int(u["side"]), int(u["row"]), int(u["slot"]))


## 유닛 index → 발 위치 (화면 px, 전장 레이어 기준). 내가 오른쪽 진영이면 좌우를 뒤집는다.
func _foot(i: int) -> Vector2:
	var p: Vector2 = _disp.get(i, Vector2.ZERO)
	if _my_side == 1:
		p.x = _span().x - p.x
	return _origin + Vector2(p.x * _ppu_v.x, (p.y - 0.7) * _ppu_v.y)


## 캐릭터 키(px): 머리 위 글자·몸 가운데 이펙트 위치에 쓴다
func _char_h(i: int) -> float:
	if _sprites.has(i):
		return _box * 0.66 * MotionSprite.body_scale(_udata[i]["aid"]) * float(_udata[i].get("scale", 1.0))
	return TILE.y * _card_k


func _layout() -> void:
	var mv := _mv()
	var span := _span()
	var top := 64.0
	var bottom := 74.0
	# 세로: 3줄 발 간격 + 맨 윗줄 머리 높이(≈ 1.3줄) + 이름표
	var lane := maxf(50.0, (size.y - top - bottom - 40.0) / 3.3)
	_ppu_v = Vector2((size.x - 70.0) / span.x, lane / float(mv["slot_h"]))
	_box = clampf(minf(lane * 1.75, _ppu_v.x * float(mv["col_w"]) * 1.9), 90.0, 250.0)
	_card_k = clampf(lane * 0.9 / TILE.y, 0.4, 1.0)
	# 세로 가운데 정렬: 맨 윗줄 머리 ~ 맨 아랫줄 이름표
	var content := _box * 0.72 + 2.0 * lane + 46.0
	var free := maxf(0.0, size.y - top - bottom - content)
	_origin = Vector2(35.0, top + free * 0.5 + _box * 0.72)
	var mid_x := _origin.x + span.x * _ppu_v.x / 2.0
	_divider.position = Vector2(mid_x - 1.0, top)
	_divider.size = Vector2(2, size.y - top - bottom)
	_left_tag.visible = false    # 제목에 이름이 있고, 이름표 테두리 색(초록/빨강)으로 진영 구분
	_right_tag.visible = false
	var pk := clampf(_ppu_v.x * float(mv["spacing"]) / (BattlePlate.W + 4.0), 0.72, 1.0)
	for i in _plates:
		_plates[i].scale = Vector2(pk, pk)
	for i in _sprites:
		_sprites[i].size = Vector2(_box, _box)
		_sprites[i].box = _box * float(_udata[i].get("scale", 1.0))
		_sprites[i].pivot_offset = Vector2(_box / 2.0, _box)
	for i in _tiles:
		_tiles[i].size = TILE
		_tiles[i].scale = Vector2.ONE * _card_k
	_place_all()


func _place_all() -> void:
	for u in _units:
		_place(u["i"], Vector2.ZERO)


## 유닛 i 를 발 위치(+ off)에 그린다. 아래 줄일수록 앞에 (겹칠 때 자연스럽게)
func _place(i: int, off: Vector2) -> void:
	var f := _foot(i) + off
	if _sprites.has(i):
		_sprites[i].position = f - Vector2(_box / 2.0, _box)
	if _tiles.has(i):
		_tiles[i].position = f - Vector2(TILE.x * _card_k / 2.0, TILE.y * _card_k)
	if _plates.has(i):
		_plates[i].position = _foot(i) + Vector2(-BattlePlate.W * _plates[i].scale.x / 2.0, 6.0)


func _update_bars() -> void:
	for u in _units:
		var i: int = u["i"]
		var mh: float = maxf(1.0, u["max_hp"])
		if _plates.has(i):
			_plates[i].set_hp(_hp[i] / mh, _sh[i] / mh)


## 남은 이벤트를 모두 바로 적용 (건너뛰기)
var _skipping := false


func skip_to_end() -> void:
	_skipping = true
	while _ev_i < _events.size():
		_apply(_events[_ev_i])
		_ev_i += 1
	_skipping = false
	_t = float(_events[-1][0]) if not _events.is_empty() else _t
	_update_bars()
	_playing = false


func _stat(i: int, key: String, v: float) -> void:
	if i < 0:
		return
	if not _stats.has(i):
		_stats[i] = {"dealt": 0.0, "taken": 0.0, "heal": 0.0, "blocked": 0.0}
	_stats[i][key] += v


## 전투가 끝나면 사도별 통계 (준 피해·받은 피해·막은 피해·회복, MVP). 우리 편/상대 편 전환.
var _stats_side := -1


func _show_stats(side: int = -1) -> void:
	if side < 0:
		side = _my_side
	_stats_side = side
	if _stats_panel and is_instance_valid(_stats_panel):
		_stats_panel.queue_free()
	var mine := []
	for u in _units:
		if u["side"] == side:
			mine.append(u)
	if mine.is_empty():
		return
	mine.sort_custom(func(a, b): return _stats.get(a["i"], {}).get("dealt", 0.0) > _stats.get(b["i"], {}).get("dealt", 0.0))
	var top := 1.0
	for u in mine:
		var st: Dictionary = _stats.get(u["i"], {})
		for k in ["dealt", "taken", "heal", "blocked"]:
			top = maxf(top, st.get(k, 0.0))
	# MVP: 준 피해 + 회복 + 막은 피해의 합이 가장 큰 사도
	var mvp := -1
	var mvp_v := -1.0
	for u in mine:
		var st: Dictionary = _stats.get(u["i"], {})
		var v: float = st.get("dealt", 0.0) + st.get("heal", 0.0) + st.get("blocked", 0.0) * 0.8 + st.get("taken", 0.0) * 0.3
		if v > mvp_v:
			mvp_v = v
			mvp = u["i"]
	var panel := UI.panel(Color(0.06, 0.07, 0.11, 0.95), 14, UI.LINE, 2)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	panel.add_child(outer)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var t := UI.label("전투 통계", 24, UI.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	for sd in [_my_side, 1 - _my_side]:
		var b := UI.button("우리 편" if sd == _my_side else "상대 편", 18, Vector2(110, 40), UI.ACCENT.darkened(0.55) if sd == side else UI.PANEL_LIGHT)
		var sdk: int = sd
		b.pressed.connect(func(): _show_stats(sdk))
		head.add_child(b)
	outer.add_child(head)
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 14)
	outer.add_child(legend)
	# 사도 목록은 스크롤 (전투 화면 안에 들어오게 — 아래 대기석·상점에 가리지 않음)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(sc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	sc.add_child(v)
	for pair in STAT_KINDS:
		legend.add_child(UI.label("■ " + pair[1], 16, pair[2]))
	for u in mine:
		var st: Dictionary = _stats.get(u["i"], {})
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		v.add_child(row)
		row.add_child(UI.tex_rect(UI.portrait(u["aid"]), Vector2(44, 44), true))
		var nl := UI.label(u["name"] + " " + UI.stars(int(u["star"])), 18, UI.ACCENT if u["i"] == mvp else UI.TEXT)
		nl.custom_minimum_size.x = 170
		nl.clip_text = true
		row.add_child(nl)
		var badge := UI.label("MVP" if u["i"] == mvp else "", 16, UI.ACCENT)
		badge.add_theme_font_override("font", UI.bold())
		badge.custom_minimum_size.x = 40
		row.add_child(badge)
		var bars := VBoxContainer.new()
		bars.add_theme_constant_override("separation", 1)
		bars.custom_minimum_size.x = 400
		row.add_child(bars)
		for pair in STAT_KINDS:
			var val: float = st.get(pair[0], 0.0)
			if pair[0] != "dealt" and pair[0] != "taken" and val <= 0.0:
				continue
			var bh := HBoxContainer.new()
			var b := UI.bar(pair[2], 10)
			b.value = 100.0 * val / top
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bh.add_child(b)
			var vl := UI.label(str(int(val)), 15, UI.SUB, HORIZONTAL_ALIGNMENT_RIGHT)
			vl.custom_minimum_size.x = 64
			bh.add_child(vl)
			bars.add_child(bh)
	add_child(panel)
	var list_min := v.get_combined_minimum_size()
	var room := maxf(120.0, size.y - 90.0 - 70.0 - outer.get_combined_minimum_size().y + sc.get_combined_minimum_size().y)
	sc.custom_minimum_size = Vector2(list_min.x, minf(list_min.y, room))
	panel.reset_size()
	panel.position = Vector2((size.x - panel.size.x) / 2.0, clampf((size.y - panel.size.y) / 2.0, 60.0, maxf(60.0, size.y - panel.size.y - 64.0)))
	panel.modulate.a = 0.0
	create_tween().tween_property(panel, "modulate:a", 1.0, 0.2)
	_stats_panel = panel


const STAT_KINDS := [["dealt", "준 피해", Color("ffb27a")], ["taken", "받은 피해", Color("ff7b7b")], ["blocked", "막은 피해", Color("bfe3ff")], ["heal", "회복", Color("5ee39b")]]


## 전투 결과 요약 (라운드 기록용): 우리 편 준 피해 합계, MVP 이름
func summary() -> Dictionary:
	var dealt := 0.0
	var best := ""
	var best_v := -1.0
	for u in _units:
		if u["side"] != _my_side:
			continue
		var d: float = _stats.get(u["i"], {}).get("dealt", 0.0)
		dealt += d
		if d > best_v:
			best_v = d
			best = u["name"]
	return {"dealt": int(dealt), "mvp": best}


func elapsed() -> float:
	return _t


func finished() -> bool:
	return not _playing


func _process(delta: float) -> void:
	if not visible:
		return
	_clock += delta
	_animate(delta)
	_fx.speed = _speed
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta)
		var amp := 10.0 * _shake / 0.35
		_field.position = Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
		_fx.position = _field.position
		_plate_layer.position = _field.position
	elif _field.position != Vector2.ZERO:
		_field.position = Vector2.ZERO
		_fx.position = Vector2.ZERO
		_plate_layer.position = Vector2.ZERO
	if not _playing:
		return
	_t += delta * _speed
	var changed := false
	while _ev_i < _events.size() and float(_events[_ev_i][0]) <= _t:
		_apply(_events[_ev_i])
		_ev_i += 1
		changed = true
	if changed:
		_update_bars()
	if _ev_i >= _events.size():
		_playing = false


func _apply(e: Array) -> void:
	var kind: String = e[1]
	var src: int = e[2]
	var dst: int = e[3]
	match kind:
		"dmg":
			_stat(src, "dealt", float(e[4]))
			_stat(dst, "taken", float(e[4]))
			# 보호막이 줄어든 만큼 = 막은 피해
			var sh_before: float = _sh.get(dst, 0.0)
			if float(e[7]) < sh_before:
				_stat(dst, "blocked", sh_before - float(e[7]))
			_hp[dst] = float(e[6])
			_sh[dst] = float(e[7])
			var crit := String(e[5]).ends_with("!")
			var dkind := String(e[5]).trim_suffix("!")
			if dkind != "status":
				_anim[dst]["flash"] = 0.18   # 지속 피해(화상 등)는 깜빡이지 않음
			var col := Color("ffb27a") if _dtype.get(src, "physical") == "physical" else Color("8cc4ff")
			if dkind == "status" or dkind == "reflect":
				col = Color("d9a6ff")
			if crit:
				col = UI.ACCENT
			if dkind != "status":
				_fx_at(dst, "ring", col, 0.25, 30.0 if not crit else 44.0)
				_sfx("crit" if crit else ("hit_magic" if _dtype.get(src, "physical") == "magic" else "hit"), 0.55)
			if crit:
				_fx_at(dst, "spark", UI.ACCENT, 0.35, 60.0)
				_shake_cam(0.12)
				_float(dst, "치명 " + str(int(e[4])) + "!", col, 36, 0.0, true)
			else:
				_float(dst, str(int(e[4])), col, 30 if dkind == "fresh" or dkind == "senior" else 25)
		"heal":
			_fx_at(dst, "ring", UI.GOOD, 0.45, 46.0)
			_stat(src, "heal", float(e[4]))
			_hp[dst] = float(e[6])
			_float(dst, "+" + str(int(e[4])), UI.GOOD, 22)
		"shield":
			_fx_at(dst, "ring", Color("bfe3ff"), 0.5, 54.0)
			_sh[dst] = float(e[7])
			_float(dst, "보호막", Color("cfe8ff"), 18)
		"pos":
			_pos[src] = Vector2(float(e[4][0]), float(e[4][1]))
			if not _disp.has(src):
				_disp[src] = _pos[src]
		"summon":
			var snap: Dictionary = e[4]
			if not _udata.has(dst):
				_units.append(snap)
				_add_unit(snap)
				_layout()
				_fx_at(dst, "ring", Color("bfe8ff"), 0.5, 50.0)
				_float(dst, "소환!", Color("bfe8ff"), 20)
		"resist":
			_float(dst, "면역", Color("dddddd"), 18)
		"attack":
			_lunge(src, dst)
			_motion(src, "Attack1_1")
			_fx_attack(src, dst)
		"skill":
			_anim[src]["pulse"] = 0.35
			_fx_skill(src, int(e[4]) == 1, String(e[5]))
			_say(src, "Ultimate" if int(e[4]) == 1 else "SPSkill")
			_sfx("ultimate" if int(e[4]) == 1 else "skill", 0.8)
			_motion(src, "Ultimate1_1" if int(e[4]) == 1 else "Skill1_1")
			_bubble(src, String(e[5]), UI.ACCENT if int(e[4]) == 1 else Color("c9a7ff"))
		"death":
			_fx_at(dst, "spark", Color(0.8, 0.8, 0.85), 0.5, 70.0)
			_say(dst, "Die")
			_sfx("death", 0.7)
			_hp[dst] = 0.0
			_anim[dst]["dead"] = true
			if _plates.has(dst):
				_plates[dst].set_dead(true)
			if _sprites.has(dst):
				_sprites[dst].play("Die", false, "", true)
		"revive":
			_hp[dst] = float(e[6])
			_sh[dst] = 0.0
			_anim[dst]["dead"] = false
			if _plates.has(dst):
				_plates[dst].set_dead(false)
			if _sprites.has(dst):
				_sprites[dst].play("Idle")
				_sprites[dst].modulate = Color.WHITE
			if _tiles.has(dst):
				_tiles[dst].modulate = Color.WHITE
			_float(dst, "부활!", Color("d9b3ff"), 30, -30, true)
		"status":
			var names := {"stun": "기절", "burn": "화상", "bitter": "쓰라림", "shock": "감전", "blind": "눈가림", "freeze": "빙결", "poison": "중독", "silence": "침묵"}
			if (String(e[5]) == "stun" or String(e[5]) == "freeze") and _sprites.has(dst) and not _anim[dst]["dead"]:
				_sprites[dst].play("Groggy", true, "Idle", false, float(e[4]))
				if String(e[5]) == "freeze":
					_sprites[dst].tint = Color(0.7, 0.85, 1.0)
			var st := String(e[5])
			var scol := {"stun": Color("ffd166"), "freeze": Color("9fd8ff"), "burn": Color("ff9a6b"), "shock": Color("e6e07a"), "bitter": Color("c9a7ff"), "blind": Color("b8b8c8"), "poison": Color("9be564"), "silence": Color("8f9bb3")}
			if _plates.has(dst) and typeof(e[4]) in [TYPE_FLOAT, TYPE_INT] and float(e[4]) > 0.0:
				_plates[dst].set_status(names.get(st, st), scol.get(st, Color("ffb3e6")))
				_status_until[dst] = _t + float(e[4])
			else:
				_float(dst, names.get(st, st), scol.get(st, Color("ffb3e6")), 18)
		"buff":
			if String(e[5]) != "":
				_float(dst, String(e[5]), Color("b3ffcc"), 16, -20)
		"immune":
			_float(dst, "무적", Color("dddddd"), 16)
		"miss":
			_float(dst, "빗나감", Color("dddddd"), 16)
		"execute":
			_float(dst, "처형!", UI.BAD, 30)
		"end":
			var w := int(e[4])
			_say_end(w)
			if w == -1:
				_banner.text = "무승부"
			elif w == _my_side:
				_banner.text = "승리!"
			else:
				_banner.text = "패배"
			_banner.size.x = size.x
			_banner.position = Vector2(0, 40)
			_show_stats()


## 떠오르는 글자 (머리 위). 같은 사도에 연달아 뜨면 좌우·위아래로 비켜 놓아 겹치지 않게.
## pop: 크게 튀어나왔다 줄어듦 (치명타)
func _float(i: int, text: String, color: Color, fsize: int, dy: float = 0.0, pop: bool = false) -> void:
	if not _udata.has(i):
		return
	var n: int = _float_n.get(i, 0)
	_float_n[i] = n + 1
	var l := UI.label(text, fsize, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_override("font", UI.bold())
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", 10 if pop else 8)
	l.size = Vector2(200, fsize + 16)
	var head := _foot(i) - Vector2(0, _char_h(i) + 8.0)
	var off := Vector2(((n % 3) - 1) * 26.0, -(n % 2) * 20.0 + dy * 0.5)
	l.position = head + off - Vector2(100, l.size.y)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.z_index = 5
	_plate_layer.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 34, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.65)
	if pop:
		l.pivot_offset = l.size / 2.0
		l.scale = Vector2(1.45, 1.45)
		tw.tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(l.queue_free)


## 스킬 이름 말풍선 (머리 위, 어두운 바탕)
func _bubble(i: int, text: String, color: Color) -> void:
	if not _udata.has(i):
		return
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.box(Color(0.06, 0.07, 0.12, 0.92), 10, color, 2))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.label("✦ " + text, 18, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_override("font", UI.bold())
	pc.add_child(l)
	pc.z_index = 6
	_plate_layer.add_child(pc)
	pc.reset_size()
	var head := _foot(i) - Vector2(0, _char_h(i) + 30.0)
	pc.position = head - Vector2(pc.size.x / 2.0, pc.size.y)
	pc.position.x = clampf(pc.position.x, 4.0, size.x - pc.size.x - 4.0)
	pc.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(pc, "modulate:a", 1.0, 0.1)
	tw.tween_interval(0.9 / maxf(0.5, _speed))
	tw.tween_property(pc, "modulate:a", 0.0, 0.25)
	tw.tween_callback(pc.queue_free)


# ─────────────────────────────── 이펙트 ───────────────────────────────

## 유닛 몸 가운데
func _center(i: int) -> Vector2:
	if not _udata.has(i):
		return Vector2.ZERO
	return _foot(i) - Vector2(0, _char_h(i) * 0.5)


## 직접 그린 전투 이펙트(고리·베기·탄환·바닥 빛)는 뺐다 — 모션·피해 숫자·이름표·스킬 이름만
func _fx_on() -> bool:
	return false


func _fx_at(i: int, kind: String, color: Color, dur: float, r: float) -> void:
	if _fx_on() and _udata.has(i):
		var c := _center(i)
		_fx.add(kind, c, c, color, dur, r)


## 공격: 앞 열 물리 공격은 베기, 그 외(원거리·마법)는 탄환
func _fx_attack(src: int, dst: int) -> void:
	if not _fx_on() or not _udata.has(src) or not _udata.has(dst):
		return
	var magic: bool = _dtype.get(src, "physical") == "magic"
	var col := Color("8cc4ff") if magic else Color("ffcf8a")
	var u: Dictionary = _udata.get(src, {})
	if int(u.get("row", 0)) == 0 and not magic:
		_fx.add("slash", _center(dst), _center(dst), col, 0.25, 46.0)
	else:
		_fx.add("proj", _center(src), _center(dst), col, 0.18, 10.0)


## 스킬: 시전자 바닥 빛, 고학년(궁극기)은 화면 흔들림 + 이름 배너
func _fx_skill(src: int, senior: bool, sname: String) -> void:
	if not _udata.has(src):
		return
	var col := UI.ACCENT if senior else Color("c9a7ff")
	if _fx_on():
		var foot: Vector2 = _foot(src)
		_fx.add("glow", foot, foot, col, 0.7 if senior else 0.5, 70.0 if senior else 52.0)
		_fx.add("ring", _center(src), _center(src), col, 0.5, 80.0 if senior else 56.0)
	if senior:
		_shake_cam(0.3)
		var u: Dictionary = _udata.get(src, {})
		var mine: bool = int(u.get("side", 0)) == _my_side
		_skill_banner.text = "✦ %s — %s ✦" % [u.get("name", ""), sname]
		_skill_banner.add_theme_color_override("font_color", UI.ACCENT if mine else Color("ff9a9a"))
		var tw := create_tween()
		_skill_banner.modulate.a = 0.0
		tw.tween_property(_skill_banner, "modulate:a", 1.0, 0.12)
		tw.tween_interval(0.9 / maxf(0.5, _speed))
		tw.tween_property(_skill_banner, "modulate:a", 0.0, 0.3)


func _shake_cam(t: float) -> void:
	if Settings.flag("screen_shake"):
		_shake = maxf(_shake, t)


# ─────────────────────────────── 보이스 ───────────────────────────────

## 효과음 (이 전투 화면이 보일 때만, 건너뛰기로 한꺼번에 적용할 때는 울리지 않음)
func _sfx(name: String, vol: float) -> void:
	if is_visible_in_tree() and _playing and not _skipping:
		Sfx.play(name, vol)


## 이 전투 화면이 보일 때만, 그림자 몬스터는 말하지 않음
func _say(i: int, cat: String) -> void:
	if not is_visible_in_tree() or not _udata.has(i):
		return
	var u: Dictionary = _udata[i]
	if u.get("monster", false):
		return
	Voice.say(u["aid"], cat, i)


## 전투 시작: 우리 편 사도 한 명이 등장 대사
func _say_spawn() -> void:
	var mine := []
	for u in _units:
		if int(u["side"]) == _my_side and not u.get("monster", false):
			mine.append(u)
	if not mine.is_empty():
		var u: Dictionary = mine[randi() % mine.size()]
		Voice.say(u["aid"], "Spawn", u["i"])


## 전투 끝: 이기면 살아 있는 우리 사도의 승리 대사, 지면 패배 대사
func _say_end(winner: int) -> void:
	if winner == -1 or not is_visible_in_tree():
		return
	var cands := []
	for u in _units:
		if int(u["side"]) == _my_side and not u.get("monster", false) and (winner != _my_side or not _anim[u["i"]]["dead"]):
			cands.append(u)
	if not cands.is_empty():
		var u: Dictionary = cands[randi() % cands.size()]
		Voice.say(u["aid"], "Victory" if winner == _my_side else "Defeat", u["i"])
		if winner == _my_side and _sprites.has(u["i"]):
			_sprites[u["i"]].play("Victory", true)


## 모션 재생 (모션이 있는 사도만). 쓰러진 사도는 무시.
func _motion(i: int, anim: String) -> void:
	if not _sprites.has(i) or _anim[i]["dead"]:
		return
	_sprites[i].play(anim, false, "Idle")


func _lunge(src: int, dst: int) -> void:
	if not _udata.has(src) or not _udata.has(dst):
		return
	_anim[src]["lunge"] = 0.18
	_anim[src]["dir"] = (_foot(dst) - _foot(src)).normalized()


## 걷기·대기 전환, 공격 돌진, 피격 깜빡임, 스킬 때 커짐, 쓰러지면 흐려짐
func _animate(delta: float) -> void:
	for u in _units:
		var i: int = u["i"]
		var a: Dictionary = _anim[i]
		# 목표 좌표로 걸어간다 (전투 계산 속도보다 약간 빠르게 따라감)
		var walking := false
		if _pos.has(i) and _disp[i] != _pos[i] and not a["dead"]:
			_disp[i] = (_disp[i] as Vector2).move_toward(_pos[i], float(_mv()["speed"]) * 1.15 * _speed * delta)
			walking = true
		if _status_until.has(i) and _t >= float(_status_until[i]):
			_status_until.erase(i)
			if _plates.has(i):
				_plates[i].set_status("")
		var sp: MotionSprite = _sprites.get(i)
		var t: UnitTile = _tiles.get(i)
		if sp != null:
			sp.speed = _speed
			if walking and (sp.current() == "Idle" or sp.current() == ""):
				sp.play("Move", true)
			elif not walking and sp.current() == "Move":
				sp.play("Idle")
		if a["dead"]:
			_place(i, Vector2(0, 4))
			if t != null:
				t.modulate = t.modulate.lerp(Color(0.5, 0.5, 0.5, 0.25), minf(1.0, delta * 6.0))
			if sp != null:
				sp.tint = Color.WHITE
				# 쓰러짐 동작이 끝난 뒤 서서히 흐려짐
				sp.modulate = sp.modulate.lerp(Color(1, 1, 1, 0.35), minf(1.0, delta * 1.2))
			continue
		var off := Vector2.ZERO
		if sp == null:
			off.y += sin(_clock * 3.0 + i * 0.9) * 3.0
		if a["lunge"] > 0.0:
			a["lunge"] = maxf(0.0, a["lunge"] - delta)
			var k: float = sin((1.0 - a["lunge"] / 0.18) * PI)
			off += a["dir"] * 18.0 * k
		_place(i, off)
		if a["flash"] > 0.0:
			a["flash"] = maxf(0.0, a["flash"] - delta)
			if sp != null:
				sp.tint = Color(1.0, 0.5, 0.5)
			if t != null:
				t.modulate = Color(1.0, 0.55, 0.55)
		else:
			if t != null:
				t.modulate = Color.WHITE
			if sp != null and sp.current() != "Groggy":
				sp.tint = Color.WHITE
		var pk := 0.0
		if a["pulse"] > 0.0:
			a["pulse"] = maxf(0.0, a["pulse"] - delta)
			pk = sin((1.0 - a["pulse"] / 0.35) * PI)
		if sp != null:
			sp.scale = Vector2.ONE * (1.0 + 0.06 * pk)
		if t != null:
			t.scale = Vector2.ONE * _card_k * (1.0 + 0.12 * pk)
	_sort_depth()


## 아래 줄(발이 아래)에 있는 사도가 앞에 보이도록 그리는 순서 정렬 (z_index 대신: 다른 레이어를 덮지 않게)
func _sort_depth() -> void:
	var kids: Array = _field.get_children()
	var sorted := kids.duplicate()
	sorted.sort_custom(func(a, b): return (a.position.y + a.size.y * a.scale.y) < (b.position.y + b.size.y * b.scale.y))
	for k in sorted.size():
		if kids[k] != sorted[k]:
			for j in sorted.size():
				_field.move_child(sorted[j], j)
			return
