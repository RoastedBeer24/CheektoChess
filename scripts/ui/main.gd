extends Control
## 첫 화면 / 대기실 / 게임 화면 전환, 알림(토스트), 방장 기기에서 업데이트 받기 안내.

var _screen: Control
var _toast: VBoxContainer          # 알림 여러 개를 위에서부터 차례로 쌓는다 (최대 3개)
const TOAST_MAX := 3
var _rooms_box: VBoxContainer
var _group_box: HBoxContainer
var _lobby_list: GridContainer
var _lobby_count: Label
var _start_btn: Button
var _bots_spin: SpinBox
var _modal: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UI.apply_settings()
	theme = UI.make_theme()
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_toast = VBoxContainer.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.z_index = 100
	_toast.add_theme_constant_override("separation", 8)
	add_child(_toast)
	App.session.toast.connect(show_toast)
	App.session.lobby_changed.connect(_on_lobby_changed)
	App.session.game_started.connect(_show_game)
	App.session.left.connect(func(reason):
		_show_title()
		if reason != "":
			show_toast(reason, 4.0))
	App.session.reconnecting.connect(_on_reconnecting)
	App.session.update_progress.connect(_on_update_progress)
	App.session.update_done.connect(_on_update_done)
	App.net.rooms_changed.connect(_on_rooms)
	_show_title()


func _process(delta: float) -> void:
	for t in _toast.get_children():
		var left: float = t.get_meta("t") - delta
		t.set_meta("t", left)
		t.modulate.a = clampf(left * 2.5, 0, 1)
		if left <= 0.0:
			_toast.remove_child(t)
			t.queue_free()
			_place_toast()


func show_toast(msg: String, secs: float = 2.5) -> void:
	# 같은 알림이 이미 떠 있으면 시간만 늘린다
	for t in _toast.get_children():
		if t.get_meta("msg") == msg:
			t.set_meta("t", secs)
			return
	while _toast.get_child_count() >= TOAST_MAX:
		var old := _toast.get_child(0)
		_toast.remove_child(old)
		old.queue_free()
	var item := UI.panel(Color("101220").lerp(UI.ACCENT, 0.08), 14, UI.ACCENT, 2)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.label(msg, 24, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = minf(900.0, 24.0 * msg.length() + 20.0)
	item.add_child(l)
	item.set_meta("msg", msg)
	item.set_meta("t", secs)
	item.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_toast.add_child(item)
	move_child(_toast, get_child_count() - 1)
	_place_toast()


func _place_toast() -> void:
	_toast.reset_size()
	var vp := get_viewport_rect().size
	_toast.position = Vector2((vp.x - _toast.size.x) / 2.0, 96)


func _set_screen(c: Control) -> void:
	if _screen:
		_screen.queue_free()
	_close_modal()
	_screen = c
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	move_child(_toast, get_child_count() - 1)


func _margin(m: int = 40) -> MarginContainer:
	var root := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, m)
	return root


## 배경: 초상화를 흐리게 깔아 둔 콜라주
func _collage() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grid := GridContainer.new()
	grid.columns = 10
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	grid.modulate = Color(1, 1, 1, 0.12)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(grid)
	var ids: Array = GameData.roster.duplicate()
	for i in 40:
		var tex := UI.portrait(ids[i % ids.size()]) if not ids.is_empty() else null
		var tr := UI.tex_rect(tex, Vector2(192, 192), true)
		tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_child(tr)
	var fade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(UI.BG, 0.55))
	g.set_color(1, Color(UI.BG, 1.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	fade.texture = gt
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(fade)
	return c


# ─────────────────────────────── 첫 화면 ───────────────────────────────

func _show_title() -> void:
	App.net.start_discovery()
	var screen := Control.new()
	screen.add_child(_collage())
	var root := _margin(48)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(root)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 48)
	root.add_child(h)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 18)
	h.add_child(left)
	var logo := UI.outlined("볼토체스", 104, UI.ACCENT, 14, HORIZONTAL_ALIGNMENT_LEFT)
	left.add_child(logo)
	left.add_child(UI.label("트릭컬 팬게임 · 오토체스  (비공식)", 28, UI.TEXT))
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 16)
	left.add_child(vrow)
	vrow.add_child(UI.label("버전 %s" % App.version, 18, UI.SUB))
	var codex := UI.button("도감", 24, Vector2(160, 56), Color("4f3586"))
	codex.pressed.connect(func(): add_child(Codex.new()))
	vrow.add_child(codex)
	var tut := UI.button("튜토리얼", 24, Vector2(160, 56), Color("2f6b4a"))
	tut.pressed.connect(func(): App.session.start_tutorial())
	vrow.add_child(tut)
	var setb := UI.button("설정·기록", 24, Vector2(170, 56), Color("3a4058"))
	setb.pressed.connect(func(): add_child(SettingsPanel.new()))
	vrow.add_child(setb)
	var sp := Control.new()
	sp.custom_minimum_size.y = 20
	left.add_child(sp)

	var card := UI.panel(Color(UI.PANEL, 0.92))
	left.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 14)
	card.add_child(cv)
	cv.add_child(UI.label("내 이름", 22, UI.SUB))
	var name_edit := LineEdit.new()
	name_edit.text = App.session.my_name
	name_edit.max_length = 12
	name_edit.custom_minimum_size = Vector2(0, 64)
	name_edit.text_changed.connect(func(t):
		App.session.my_name = t.strip_edges() if t.strip_edges() != "" else "플레이어"
		App.session.save_profile())
	cv.add_child(name_edit)
	cv.add_child(UI.hsep())
	var solo := HBoxContainer.new()
	solo.add_theme_constant_override("separation", 14)
	cv.add_child(solo)
	var b_solo := UI.button("혼자 하기", 30, Vector2(0, 84), Color("2f6b4a"))
	b_solo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	solo.add_child(b_solo)
	var bots := VBoxContainer.new()
	solo.add_child(bots)
	bots.add_child(UI.label("봇 수", 18, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER))
	_bots_spin = SpinBox.new()
	_bots_spin.min_value = 3
	_bots_spin.max_value = 7
	_bots_spin.value = 7
	_bots_spin.custom_minimum_size = Vector2(130, 56)
	_bots_spin.get_line_edit().add_theme_font_size_override("font_size", 26)
	bots.add_child(_bots_spin)
	b_solo.pressed.connect(func():
		App.net.stop()
		App.session.start_offline(int(_bots_spin.value)))
	var b_host := UI.button("방 만들기 (LAN)", 30, Vector2(0, 84), Color("2f4f86"))
	b_host.pressed.connect(func():
		var err := App.session.host_room()
		if err != OK:
			show_toast("방을 만들 수 없습니다 (오류 %d)" % err)
		else:
			_show_lobby())
	cv.add_child(b_host)

	var right := UI.panel(Color(UI.PANEL, 0.92))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 14)
	right.add_child(rv)
	rv.add_child(UI.label("같은 와이파이의 방", 32, UI.ACCENT))
	rv.add_child(UI.label("방장이 '방 만들기'를 누르면 여기에 나타납니다", 18, UI.SUB))
	var scroll := DragScroll.new(UI.PANEL)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(scroll)
	_rooms_box = VBoxContainer.new()
	_rooms_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rooms_box.add_theme_constant_override("separation", 10)
	scroll.add_child(_rooms_box)
	_on_rooms(App.net.rooms.values())
	rv.add_child(UI.hsep())
	rv.add_child(UI.label("방이 안 보이면 방장 화면의 IP로 직접 참가", 18, UI.SUB))
	var ipbox := HBoxContainer.new()
	ipbox.add_theme_constant_override("separation", 10)
	rv.add_child(ipbox)
	var ip_edit := LineEdit.new()
	ip_edit.placeholder_text = "예: 192.168.0.10"
	ip_edit.custom_minimum_size = Vector2(0, 64)
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ipbox.add_child(ip_edit)
	var b_ip := UI.button("참가", 26, Vector2(150, 64), Color("2f4f86"))
	b_ip.pressed.connect(func(): _join(ip_edit.text.strip_edges()))
	ipbox.add_child(b_ip)
	_set_screen(screen)


func _on_rooms(rooms: Array) -> void:
	if _rooms_box == null or not is_instance_valid(_rooms_box):
		return
	UI.clear(_rooms_box)
	if rooms.is_empty():
		_rooms_box.add_child(UI.label("찾는 중...", 22, UI.SUB))
		return
	for r in rooms:
		var started: bool = r.get("started", false)
		var b := UI.button("%s\n%d / %d명%s" % [r.get("name", "방"), int(r.get("players", 0)), int(r.get("max", 8)),
			"  · 진행 중 (재접속만 가능)" if started else ""], 24, Vector2(0, 96), Color("2c3350"))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var ip: String = r["ip"]
		b.pressed.connect(func(): _join(ip))
		_rooms_box.add_child(b)


func _join(ip: String) -> void:
	if ip == "":
		show_toast("IP를 입력하세요")
		return
	var err := App.session.join_room(ip)
	if err != OK:
		show_toast("참가할 수 없습니다 (오류 %d)" % err)
		return
	_show_lobby()


# ─────────────────────────────── 대기실 ───────────────────────────────

func _show_lobby() -> void:
	App.net.stop_discovery()
	var screen := Control.new()
	screen.add_child(_collage())
	var root := _margin(48)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(root)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	root.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UI.outlined("대기실", 56, UI.ACCENT, 10, HORIZONTAL_ALIGNMENT_LEFT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_lobby_count = UI.label("", 28, UI.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	head.add_child(_lobby_count)
	var info := UI.panel(Color(UI.PANEL, 0.92))
	v.add_child(info)
	if App.session.mode == "host":
		var ips := App.net.local_ips()
		info.add_child(UI.label("내 IP  %s     같은 와이파이에서 이 IP로 참가할 수 있습니다" % (", ".join(ips) if not ips.is_empty() else "확인 불가"), 26, UI.TEXT))
	else:
		info.add_child(UI.label("방장이 게임을 시작할 때까지 기다리는 중...", 26, UI.TEXT))
	# 그룹 (판에 쓰는 사도·시너지 묶음)
	_group_box = HBoxContainer.new()
	_group_box.add_theme_constant_override("separation", 10)
	v.add_child(_group_box)
	_lobby_list = GridContainer.new()
	_lobby_list.columns = 4
	_lobby_list.add_theme_constant_override("h_separation", 14)
	_lobby_list.add_theme_constant_override("v_separation", 14)
	_lobby_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_lobby_list)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	v.add_child(bar)
	if App.session.mode == "host":
		var add := UI.button("봇 추가", 26, Vector2(200, 76))
		add.pressed.connect(App.session.add_bot)
		bar.add_child(add)
		var rem := UI.button("봇 제거", 26, Vector2(200, 76))
		rem.pressed.connect(App.session.remove_bot)
		bar.add_child(rem)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	var quit := UI.button("나가기", 26, Vector2(180, 76), Color("6b3535"))
	quit.pressed.connect(App.session.leave)
	bar.add_child(quit)
	if App.session.mode == "host":
		_start_btn = UI.button("게임 시작", 30, Vector2(280, 76), Color("2f6b4a"))
		_start_btn.pressed.connect(App.session.start_game)
		bar.add_child(_start_btn)
	_set_screen(screen)
	_on_lobby_changed()


func _refresh_group_box() -> void:
	if _group_box == null or not is_instance_valid(_group_box):
		return
	UI.clear(_group_box)
	_group_box.add_child(UI.label("그룹", 26, UI.ACCENT))
	var host := App.session.mode == "host"
	for gv in GameData.groups:
		var g: Dictionary = gv
		var on: bool = g["id"] == GameData.group_id
		var txt := "%s  (사도 %d명 · 시너지 %d개)" % [g.get("name", g["id"]), g.get("units", []).size(), g.get("synergies", []).size()]
		if host and GameData.groups.size() > 1:
			var b := UI.button(txt, 22, Vector2(0, 60), UI.ACCENT.darkened(0.6) if on else UI.PANEL_LIGHT)
			var gid: String = g["id"]
			b.pressed.connect(func(): App.session.set_group(gid))
			_group_box.add_child(b)
		elif on:
			_group_box.add_child(UI.chip(txt, UI.ACCENT, 22))


func _on_lobby_changed() -> void:
	if _lobby_list == null or not is_instance_valid(_lobby_list):
		return
	_refresh_group_box()
	UI.clear(_lobby_list)
	var n := App.session.lobby.size()
	_lobby_count.text = "%d / %d명  (최소 %d명)" % [n, App.session.MAX_PLAYERS, App.session.MIN_PLAYERS]
	if _start_btn and is_instance_valid(_start_btn):
		_start_btn.disabled = n < App.session.MIN_PLAYERS
	for i in App.session.MAX_PLAYERS:
		var card := UI.panel(Color(UI.PANEL, 0.92), 14, UI.LINE, 2)
		card.custom_minimum_size = Vector2(0, 110)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i < n:
			var p: Dictionary = App.session.lobby[i]
			var me: bool = p["id"] == App.session.my_pid
			var tag := "방장" if i == 0 else ("봇" if p["bot"] else "참가자")
			if me:
				tag += " · 나"
			var cv := VBoxContainer.new()
			cv.add_child(UI.label(p["name"], 30, UI.ACCENT if me else UI.TEXT))
			cv.add_child(UI.label(tag, 20, UI.SUB))
			card.add_child(cv)
			card.add_theme_stylebox_override("panel", UI.box(Color(UI.PANEL, 0.95), 14, UI.ACCENT if me else UI.LINE, 2))
		else:
			card.add_child(UI.label("빈 자리", 24, Color(1, 1, 1, 0.25), HORIZONTAL_ALIGNMENT_CENTER))
		_lobby_list.add_child(card)


# ─────────────────────────────── 업데이트 (방장 기기에서 받기) ───────────────────────────────

func _modal_box(title: String) -> VBoxContainer:
	_close_modal()
	_modal = Control.new()
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(cc)
	var p := UI.panel(UI.PANEL, 18, UI.ACCENT, 2)
	p.custom_minimum_size = Vector2(820, 0)
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	p.add_child(v)
	v.add_child(UI.label(title, 34, UI.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	move_child(_toast, get_child_count() - 1)
	return v


func _close_modal() -> void:
	if _modal and is_instance_valid(_modal):
		_modal.queue_free()
	_modal = null


var _upd_label: Label
var _upd_bar: ProgressBar


func _on_update_progress(text: String, ratio: float) -> void:
	if _upd_bar == null or not is_instance_valid(_upd_bar):
		var v := _modal_box("게임 버전 맞추는 중")
		v.add_child(UI.wrap_label("방장과 게임 버전이 달라, 방장 기기에서 바뀐 파일만 받고 있습니다.", 22, UI.TEXT))
		_upd_label = UI.label(text, 22, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(_upd_label)
		_upd_bar = UI.bar(UI.ACCENT, 22)
		v.add_child(_upd_bar)
	_upd_label.text = text
	_upd_bar.value = ratio * 100.0


func _on_update_done() -> void:
	var v := _modal_box("업데이트 완료")
	var android := OS.has_feature("android")
	v.add_child(UI.wrap_label("새 버전을 적용하려면 게임을 다시 시작해야 합니다." + ("\n앱을 닫은 뒤 다시 실행하고, 방에 다시 참가해 주세요." if android else ""), 24, UI.TEXT))
	var b := UI.button("앱 닫기" if android else "다시 시작", 28, Vector2(0, 76), Color("2f6b4a"))
	b.pressed.connect(func(): App.restart(get_tree()))
	v.add_child(b)


# ─────────────────────────────── 게임 ───────────────────────────────

func _show_game() -> void:
	var g := GameScreen.new()
	g.toast_requested.connect(show_toast)
	_set_screen(g)


## 재접속·방장 넘기기 중 안내 (화면 맨 위, 게임 조작은 막지 않음)
var _reconn: PanelContainer


func _on_reconnecting(text: String) -> void:
	if _reconn == null:
		_reconn = UI.panel(Color(0.08, 0.06, 0.02, 0.95), 14, UI.ACCENT, 3)
		_reconn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_reconn.z_index = 120
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		_reconn.add_child(h)
		var spin := UI.outlined("⟳", 30, UI.ACCENT, 4)
		spin.name = "Spin"
		h.add_child(spin)
		var l := UI.label("", 24, UI.TEXT)
		l.name = "Text"
		h.add_child(l)
		add_child(_reconn)
	_reconn.visible = text != ""
	if text == "":
		return
	(_reconn.get_child(0).get_node("Text") as Label).text = text
	_reconn.reset_size()
	_reconn.position = Vector2((get_viewport_rect().size.x - _reconn.size.x) / 2.0, 120.0)
	move_child(_reconn, get_child_count() - 1)
