class_name BattleView
extends Control
## 전투 재생 화면. 방장과 같은 입력(군대 + seed)으로 이 기기에서 전투를 다시 계산해 보여준다.
## 결과(승패/피해)는 방장의 계산이 기준이다.

const TILE := Vector2(150, 150)
const GAP := 12.0

var _tiles := {}          # 유닛 index -> UnitTile
var _sprites := {}        # 유닛 index -> MotionSprite (모션 파일이 있는 사도만)
const SPRITE_BOX := 215.0
const SPRITE_LIFT := 30.0 # 이름·HP 띠 위에 발이 오도록
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
		_speed = 2.0 if _speed < 1.5 else 1.0
		_speed_btn.text = "속도 x%d" % int(_speed))
	add_child(_speed_btn)
	resized.connect(_layout)


func setup(bt: Dictionary, my_side: int, name_a: String, name_b: String) -> void:
	_my_side = my_side
	UI.clear(_field)
	_tiles.clear()
	_sprites.clear()
	_anim.clear()
	_stats.clear()
	if _stats_panel and is_instance_valid(_stats_panel):
		_stats_panel.queue_free()
	_stats_panel = null
	_hp.clear()
	_sh.clear()
	_banner.text = ""
	var sim := BattleSim.new(bt["army_a"], bt["army_b"], int(bt["seed"]))
	var res := sim.run()
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
		if MotionSprite.available(u["aid"]):
			var sp := MotionSprite.new(u["aid"])
			sp.face_right = u["side"] == my_side   # 왼쪽(우리 편)은 오른쪽을 봄
			sp.size = TILE
			sp.box = SPRITE_BOX
			sp.pivot_offset = Vector2(TILE.x / 2.0, TILE.y)
			_field.add_child(sp)
			_sprites[u["i"]] = sp
		var tile := UnitTile.new(TILE)
		tile.set_unit({"aid": u["aid"], "star": u["star"], "pers": u["pers"]})
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _sprites.has(u["i"]):
			tile.set_motion_mode(true)
		_field.add_child(tile)
		_tiles[u["i"]] = tile
		_dtype[u["i"]] = GameData.apostle(u["aid"]).get("damage", "physical")
		_anim[u["i"]] = {"lunge": 0.0, "dir": Vector2.ZERO, "flash": 0.0, "pulse": 0.0, "dead": false}
		tile.pivot_offset = TILE / 2.0
		_hp[u["i"]] = float(u["max_hp"])
		_sh[u["i"]] = 0.0
	_layout()
	_update_bars()


func _cell_pos(u: Dictionary) -> Vector2:
	var on_left: bool = u["side"] == _my_side
	# 왼쪽 진영: 후열·중열·전열 / 오른쪽 진영: 전열·중열·후열
	var col: int = (2 - int(u["row"])) if on_left else (3 + int(u["row"]))
	var total_w := 6 * TILE.x + 5 * GAP + 60.0
	var x0 := (size.x - total_w) / 2.0
	var x := x0 + col * (TILE.x + GAP) + (60.0 if col >= 3 else 0.0)
	var total_h := 3 * TILE.y + 2 * GAP
	var y0 := (size.y - total_h) / 2.0 + 20.0
	return Vector2(x, y0 + int(u["slot"]) * (TILE.y + GAP))


func _layout() -> void:
	var total_w := 6 * TILE.x + 5 * GAP + 60.0
	var x0 := (size.x - total_w) / 2.0
	var total_h := 3 * TILE.y + 2 * GAP
	var y0 := (size.y - total_h) / 2.0 + 20.0
	_divider.position = Vector2(x0 + 3 * TILE.x + 2.5 * GAP + 30.0 - 1.0, y0 - 10)
	_divider.size = Vector2(2, total_h + 20)
	_left_tag.position = Vector2(x0, y0 - 46)
	_left_tag.size = Vector2(3 * TILE.x + 2 * GAP, 32)
	_right_tag.position = Vector2(x0 + 3 * TILE.x + 3 * GAP + 60.0, y0 - 46)
	_right_tag.size = Vector2(3 * TILE.x + 2 * GAP, 32)
	for u in _units:
		if _tiles.has(u["i"]):
			_tiles[u["i"]].position = _cell_pos(u)
			_tiles[u["i"]].size = TILE
		if _sprites.has(u["i"]):
			_sprites[u["i"]].position = _cell_pos(u) - Vector2(0, SPRITE_LIFT)


func _update_bars() -> void:
	for u in _units:
		var mh: float = maxf(1.0, u["max_hp"])
		_tiles[u["i"]].set_hp(_hp[u["i"]] / mh, _sh[u["i"]] / mh)


## 남은 이벤트를 모두 바로 적용 (건너뛰기)
func skip_to_end() -> void:
	while _ev_i < _events.size():
		_apply(_events[_ev_i])
		_ev_i += 1
	_t = float(_events[-1][0]) if not _events.is_empty() else _t
	_update_bars()
	_playing = false


func _stat(i: int, key: String, v: float) -> void:
	if i < 0:
		return
	if not _stats.has(i):
		_stats[i] = {"dealt": 0.0, "taken": 0.0, "heal": 0.0}
	_stats[i][key] += v


## 전투가 끝나면 우리 편 사도별 피해 통계
func _show_stats() -> void:
	if _stats_panel and is_instance_valid(_stats_panel):
		return
	var mine := []
	for u in _units:
		if u["side"] == _my_side:
			mine.append(u)
	if mine.is_empty():
		return
	mine.sort_custom(func(a, b): return _stats.get(a["i"], {}).get("dealt", 0.0) > _stats.get(b["i"], {}).get("dealt", 0.0))
	var top := 1.0
	for u in mine:
		var st: Dictionary = _stats.get(u["i"], {})
		top = maxf(top, maxf(st.get("dealt", 0.0), maxf(st.get("taken", 0.0), st.get("heal", 0.0))))
	var panel := UI.panel(Color(0.06, 0.07, 0.11, 0.94), 14, UI.LINE, 2)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UI.label("전투 통계", 24, UI.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UI.label("■ 준 피해  ", 16, Color("ffb27a")))
	head.add_child(UI.label("■ 받은 피해  ", 16, Color("ff7b7b")))
	head.add_child(UI.label("■ 회복", 16, UI.GOOD))
	for u in mine:
		var st: Dictionary = _stats.get(u["i"], {"dealt": 0.0, "taken": 0.0, "heal": 0.0})
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		v.add_child(row)
		row.add_child(UI.tex_rect(UI.portrait(u["aid"]), Vector2(44, 44), true))
		var nl := UI.label(u["name"] + " " + UI.stars(int(u["star"])), 18, UI.TEXT)
		nl.custom_minimum_size.x = 170
		nl.clip_text = true
		row.add_child(nl)
		var bars := VBoxContainer.new()
		bars.add_theme_constant_override("separation", 1)
		bars.custom_minimum_size.x = 420
		row.add_child(bars)
		for pair in [["dealt", Color("ffb27a")], ["taken", Color("ff7b7b")], ["heal", UI.GOOD]]:
			var val: float = st.get(pair[0], 0.0)
			if pair[0] == "heal" and val <= 0.0:
				continue
			var bh := HBoxContainer.new()
			var b := UI.bar(pair[1], 10)
			b.value = 100.0 * val / top
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bh.add_child(b)
			var vl := UI.label(str(int(val)), 15, UI.SUB, HORIZONTAL_ALIGNMENT_RIGHT)
			vl.custom_minimum_size.x = 64
			bh.add_child(vl)
			bars.add_child(bh)
	add_child(panel)
	panel.reset_size()
	panel.position = Vector2((size.x - panel.size.x) / 2.0, maxf(110.0, (size.y - panel.size.y) / 2.0 + 30.0))
	panel.modulate.a = 0.0
	create_tween().tween_property(panel, "modulate:a", 1.0, 0.3)
	_stats_panel = panel


func elapsed() -> float:
	return _t


func finished() -> bool:
	return not _playing


func _process(delta: float) -> void:
	if not visible:
		return
	_clock += delta
	_animate(delta)
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
			_hp[dst] = float(e[6])
			_anim[dst]["flash"] = 0.18
			_sh[dst] = float(e[7])
			var crit := String(e[5]).ends_with("!")
			var dkind := String(e[5]).trim_suffix("!")
			var col := Color("ffb27a") if _dtype.get(src, "physical") == "physical" else Color("8cc4ff")
			if dkind == "status" or dkind == "reflect":
				col = Color("d9a6ff")
			if crit:
				col = UI.ACCENT
			if crit:
				_float(dst, "치명 " + str(int(e[4])) + "!", col, 36, 0.0, true)
			else:
				_float(dst, str(int(e[4])), col, 28 if dkind == "fresh" or dkind == "senior" else 23)
		"heal":
			_stat(src, "heal", float(e[4]))
			_hp[dst] = float(e[6])
			_float(dst, "+" + str(int(e[4])), UI.GOOD, 22)
		"shield":
			_sh[dst] = float(e[7])
			_float(dst, "보호막", Color("cfe8ff"), 18)
		"attack":
			_lunge(src, dst)
			_motion(src, "Attack1_1")
		"skill":
			_anim[src]["pulse"] = 0.35
			_motion(src, "Ultimate1_1" if int(e[4]) == 1 else "Skill1_1")
			_float(src, "✦ " + String(e[5]), UI.ACCENT if int(e[4]) == 1 else Color("c9a7ff"), 26, -56, true)
		"death":
			_hp[dst] = 0.0
			_anim[dst]["dead"] = true
			if _sprites.has(dst):
				_sprites[dst].play("Die", false, "", true)
		"revive":
			_hp[dst] = float(e[6])
			_sh[dst] = 0.0
			_anim[dst]["dead"] = false
			if _sprites.has(dst):
				_sprites[dst].play("Idle")
				_sprites[dst].modulate = Color.WHITE
			if _tiles.has(dst):
				_tiles[dst].modulate = Color.WHITE
			_float(dst, "부활!", Color("d9b3ff"), 30, -30, true)
		"status":
			var names := {"stun": "기절", "burn": "화상", "bitter": "쓰라림", "shock": "감전", "blind": "눈가림", "freeze": "빙결"}
			if (String(e[5]) == "stun" or String(e[5]) == "freeze") and _sprites.has(dst) and not _anim[dst]["dead"]:
				_sprites[dst].play("Groggy", true, "Idle", false, float(e[4]))
				if String(e[5]) == "freeze":
					_sprites[dst].tint = Color(0.7, 0.85, 1.0)
			_float(dst, names.get(String(e[5]), String(e[5])), Color("ffb3e6"), 18)
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
			if w == -1:
				_banner.text = "무승부"
			elif w == _my_side:
				_banner.text = "승리!"
			else:
				_banner.text = "패배"
			_banner.size.x = size.x
			_banner.position = Vector2(0, 40)
			_show_stats()


## 떠오르는 글자. pop: 크게 튀어나왔다 줄어듦 (치명타·스킬)
func _float(i: int, text: String, color: Color, fsize: int, dy: float = 0.0, pop: bool = false) -> void:
	if not _tiles.has(i):
		return
	var t: UnitTile = _tiles[i]
	var l := UI.label(text, fsize, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 9 if pop else 7)
	l.size = Vector2(TILE.x + 60, 40)
	l.position = t.position + Vector2(-30, 30 + dy + randf_range(-10, 10))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 50, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	if pop:
		l.pivot_offset = l.size / 2.0
		l.scale = Vector2(1.45, 1.45)
		tw.tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(l.queue_free)


## 모션 재생 (모션이 있는 사도만). 쓰러진 사도는 무시.
func _motion(i: int, anim: String) -> void:
	if not _sprites.has(i) or _anim[i]["dead"]:
		return
	_sprites[i].play(anim, false, "Idle")


func _lunge(src: int, dst: int) -> void:
	if not _tiles.has(src) or not _tiles.has(dst):
		return
	_anim[src]["lunge"] = 0.18
	_anim[src]["dir"] = (_tiles[dst].position - _tiles[src].position).normalized()


## 임시 모션: 대기 중 흔들림, 공격 시 돌진, 피격 시 붉게 깜빡임, 스킬 시 커짐, 쓰러지면 흐려짐.
## 사도별 모션 에셋을 받으면 이 부분을 교체한다.
func _animate(delta: float) -> void:
	for u in _units:
		var i: int = u["i"]
		if not _tiles.has(i):
			continue
		var t: UnitTile = _tiles[i]
		var a: Dictionary = _anim[i]
		var pos := _cell_pos(u)
		var sp: MotionSprite = _sprites.get(i)
		if sp != null:
			sp.speed = _speed
		if a["dead"]:
			t.position = pos + Vector2(0, 6)
			t.modulate = t.modulate.lerp(Color(0.5, 0.5, 0.5, 0.25), minf(1.0, delta * 6.0))
			t.scale = Vector2.ONE
			if sp != null:
				sp.position = pos - Vector2(0, SPRITE_LIFT)
				sp.tint = Color.WHITE
				# 쓰러짐 동작이 끝난 뒤 서서히 흐려짐
				sp.modulate = sp.modulate.lerp(Color(1, 1, 1, 0.35), minf(1.0, delta * 1.2))
			continue
		if sp == null:
			pos.y += sin(_clock * 3.0 + i * 0.9) * 3.0
		if a["lunge"] > 0.0:
			a["lunge"] = maxf(0.0, a["lunge"] - delta)
			var k: float = sin((1.0 - a["lunge"] / 0.18) * PI)
			pos += a["dir"] * 18.0 * k
		t.position = pos
		if sp != null:
			sp.position = pos - Vector2(0, SPRITE_LIFT)
		if a["flash"] > 0.0:
			a["flash"] = maxf(0.0, a["flash"] - delta)
			if sp != null:
				sp.tint = Color(1.0, 0.5, 0.5)
				t.modulate = Color.WHITE
			else:
				t.modulate = Color(1.0, 0.55, 0.55)
		else:
			t.modulate = Color.WHITE
			if sp != null and sp.current() != "Groggy":
				sp.tint = Color.WHITE
		if a["pulse"] > 0.0:
			a["pulse"] = maxf(0.0, a["pulse"] - delta)
			var sc := Vector2.ONE * (1.0 + 0.12 * sin((1.0 - a["pulse"] / 0.35) * PI))
			if sp != null:
				sp.scale = Vector2.ONE * (1.0 + 0.06 * sin((1.0 - a["pulse"] / 0.35) * PI))
				t.scale = Vector2.ONE
			else:
				t.scale = sc
		else:
			t.scale = Vector2.ONE
			if sp != null:
				sp.scale = Vector2.ONE
