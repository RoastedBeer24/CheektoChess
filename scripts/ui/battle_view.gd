class_name BattleView
extends Control
## 전투 재생 화면. 방장과 같은 입력(군대 + seed)으로 이 기기에서 전투를 다시 계산해 보여준다.
## 결과(승패/피해)는 방장의 계산이 기준이다.

const TILE := Vector2(150, 150)
const GAP := 12.0

var _tiles := {}          # 유닛 index -> UnitTile
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
	_anim.clear()
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
		var tile := UnitTile.new(TILE)
		tile.set_unit({"aid": u["aid"], "star": u["star"], "pers": u["pers"]})
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
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


func _update_bars() -> void:
	for u in _units:
		var mh: float = maxf(1.0, u["max_hp"])
		_tiles[u["i"]].set_hp(_hp[u["i"]] / mh, _sh[u["i"]] / mh)


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
			_float(dst, str(int(e[4])) + ("!" if crit else ""), col, 34 if crit else (26 if dkind == "fresh" or dkind == "senior" else 22))
		"heal":
			_hp[dst] = float(e[6])
			_float(dst, "+" + str(int(e[4])), UI.GOOD, 22)
		"shield":
			_sh[dst] = float(e[7])
			_float(dst, "보호막", Color("cfe8ff"), 18)
		"attack":
			_lunge(src, dst)
		"skill":
			_anim[src]["pulse"] = 0.35
			_float(src, String(e[5]), UI.ACCENT if int(e[4]) == 1 else Color("9fd3ff"), 24, -50)
		"death":
			_hp[dst] = 0.0
			_anim[dst]["dead"] = true
		"status":
			var names := {"stun": "기절", "burn": "화상", "bitter": "쓰라림", "shock": "감전", "blind": "눈가림"}
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
			_banner.position = Vector2(0, size.y / 2.0 - 40)


func _float(i: int, text: String, color: Color, fsize: int, dy: float = 0.0) -> void:
	if not _tiles.has(i):
		return
	var t: UnitTile = _tiles[i]
	var l := UI.label(text, fsize, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.size = Vector2(TILE.x + 60, 40)
	l.position = t.position + Vector2(-30, 30 + dy + randf_range(-10, 10))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 50, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


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
		if a["dead"]:
			t.position = pos + Vector2(0, 6)
			t.modulate = t.modulate.lerp(Color(0.5, 0.5, 0.5, 0.25), minf(1.0, delta * 6.0))
			t.scale = Vector2.ONE
			continue
		pos.y += sin(_clock * 3.0 + i * 0.9) * 3.0
		if a["lunge"] > 0.0:
			a["lunge"] = maxf(0.0, a["lunge"] - delta)
			var k: float = sin((1.0 - a["lunge"] / 0.18) * PI)
			pos += a["dir"] * 18.0 * k
		t.position = pos
		if a["flash"] > 0.0:
			a["flash"] = maxf(0.0, a["flash"] - delta)
			t.modulate = Color(1.0, 0.55, 0.55)
		else:
			t.modulate = Color.WHITE
		if a["pulse"] > 0.0:
			a["pulse"] = maxf(0.0, a["pulse"] - delta)
			t.scale = Vector2.ONE * (1.0 + 0.12 * sin((1.0 - a["pulse"] / 0.35) * PI))
		else:
			t.scale = Vector2.ONE
