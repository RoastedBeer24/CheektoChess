extends Control
## 첫 화면 / 대기실 / 게임 화면 전환.

var _screen: Control
var _toast: Label
var _toast_t := 0.0
var _rooms_box: VBoxContainer
var _lobby_list: VBoxContainer
var _bots_spin: SpinBox


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_toast = UI.label("", 24, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position.y = 90
	_toast.z_index = 100
	Session.toast.connect(show_toast)
	Session.lobby_changed.connect(_on_lobby_changed)
	Session.game_started.connect(_show_game)
	Session.left.connect(func(reason):
		_show_title()
		if reason != "":
			show_toast(reason))
	Net.rooms_changed.connect(_on_rooms)
	add_child(_toast)
	_show_title()


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0, 1)


func show_toast(msg: String) -> void:
	_toast.text = msg
	_toast_t = 2.5
	_toast.modulate.a = 1.0
	_toast.size.x = get_viewport_rect().size.x
	_toast.position.x = 0
	move_child(_toast, get_child_count() - 1)


func _set_screen(c: Control) -> void:
	if _screen:
		_screen.queue_free()
	_screen = c
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	move_child(_toast, get_child_count() - 1)


# ─────────────────────────────── 첫 화면 ───────────────────────────────

func _show_title() -> void:
	Net.start_discovery()
	var root := MarginContainer.new()
	for m in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + m, 40)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 40)
	root.add_child(h)
	# 왼쪽: 제목/이름/혼자하기/방 만들기
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 18)
	h.add_child(left)
	left.add_child(UI.label("CheektoChess", 72, UI.ACCENT))
	left.add_child(UI.label("트릭컬 팬게임 · 오토체스 (비공식)", 26, UI.SUB))
	left.add_child(UI.label("내 이름", 22))
	var name_edit := LineEdit.new()
	name_edit.text = Session.my_name
	name_edit.max_length = 12
	name_edit.custom_minimum_size = Vector2(420, 60)
	name_edit.add_theme_font_size_override("font_size", 26)
	name_edit.text_changed.connect(func(t):
		Session.my_name = t.strip_edges() if t.strip_edges() != "" else "플레이어"
		Session.save_profile())
	left.add_child(name_edit)
	var solo := HBoxContainer.new()
	solo.add_theme_constant_override("separation", 12)
	left.add_child(solo)
	var b_solo := UI.button("혼자 하기 (봇 상대)", 26, Vector2(360, 72), Color("3d6b4f"))
	solo.add_child(b_solo)
	solo.add_child(UI.label("봇 수", 22))
	_bots_spin = SpinBox.new()
	_bots_spin.min_value = 3
	_bots_spin.max_value = 7
	_bots_spin.value = 7
	_bots_spin.custom_minimum_size = Vector2(120, 60)
	solo.add_child(_bots_spin)
	b_solo.pressed.connect(func():
		Net.stop()
		Session.start_offline(int(_bots_spin.value)))
	var b_host := UI.button("방 만들기 (LAN)", 26, Vector2(360, 72), Color("3b5b8f"))
	b_host.pressed.connect(func():
		var err := Session.host_room()
		if err != OK:
			show_toast("방을 만들 수 없습니다 (오류 %d)" % err)
		else:
			_show_lobby())
	left.add_child(b_host)
	# 오른쪽: 방 찾기
	var right := UI.panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 14)
	right.add_child(rv)
	rv.add_child(UI.label("같은 와이파이의 방", 30, UI.ACCENT))
	_rooms_box = VBoxContainer.new()
	_rooms_box.add_theme_constant_override("separation", 10)
	_rooms_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(_rooms_box)
	_on_rooms(Net.rooms.values())
	rv.add_child(UI.label("방이 안 보이면 방장 화면에 표시된 IP로 직접 참가", 18, UI.SUB))
	var ipbox := HBoxContainer.new()
	rv.add_child(ipbox)
	var ip_edit := LineEdit.new()
	ip_edit.placeholder_text = "예: 192.168.0.10"
	ip_edit.custom_minimum_size = Vector2(320, 60)
	ip_edit.add_theme_font_size_override("font_size", 24)
	ipbox.add_child(ip_edit)
	var b_ip := UI.button("IP로 참가", 24, Vector2(200, 60))
	b_ip.pressed.connect(func(): _join(ip_edit.text.strip_edges()))
	ipbox.add_child(b_ip)
	_set_screen(root)


func _on_rooms(rooms: Array) -> void:
	if _rooms_box == null or not is_instance_valid(_rooms_box):
		return
	UI.clear(_rooms_box)
	if rooms.is_empty():
		_rooms_box.add_child(UI.label("찾는 중...", 22, UI.SUB))
		return
	for r in rooms:
		var b := UI.button("%s   (%d/%d)%s" % [r.get("name", "방"), int(r.get("players", 0)), int(r.get("max", 8)),
			"  · 진행 중" if r.get("started", false) else ""], 24, Vector2(0, 64))
		var ip: String = r["ip"]
		b.pressed.connect(func(): _join(ip))
		_rooms_box.add_child(b)


func _join(ip: String) -> void:
	if ip == "":
		show_toast("IP를 입력하세요")
		return
	var err := Session.join_room(ip)
	if err != OK:
		show_toast("참가할 수 없습니다 (오류 %d)" % err)
		return
	_show_lobby()


# ─────────────────────────────── 대기실 ───────────────────────────────

func _show_lobby() -> void:
	Net.stop_discovery()
	var root := MarginContainer.new()
	for m in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + m, 40)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	root.add_child(v)
	v.add_child(UI.label("대기실", 48, UI.ACCENT))
	if Session.mode == "host":
		v.add_child(UI.label("내 IP: %s   (같은 와이파이에서 참가 가능)" % ", ".join(Net.local_ips()), 22, UI.SUB))
	else:
		v.add_child(UI.label("방장이 게임을 시작할 때까지 기다리는 중...", 22, UI.SUB))
	_lobby_list = VBoxContainer.new()
	_lobby_list.add_theme_constant_override("separation", 8)
	_lobby_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_lobby_list)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	v.add_child(bar)
	if Session.mode == "host":
		var add := UI.button("봇 추가", 24, Vector2(180, 64))
		add.pressed.connect(Session.add_bot)
		bar.add_child(add)
		var rem := UI.button("봇 제거", 24, Vector2(180, 64))
		rem.pressed.connect(Session.remove_bot)
		bar.add_child(rem)
		var start := UI.button("게임 시작", 26, Vector2(240, 64), Color("3d6b4f"))
		start.pressed.connect(Session.start_game)
		bar.add_child(start)
	var quit := UI.button("나가기", 24, Vector2(160, 64), Color("6b3d3d"))
	quit.pressed.connect(Session.leave)
	bar.add_child(quit)
	_set_screen(root)
	_on_lobby_changed()


func _on_lobby_changed() -> void:
	if _lobby_list == null or not is_instance_valid(_lobby_list):
		return
	UI.clear(_lobby_list)
	_lobby_list.add_child(UI.label("참가자 %d / %d  (최소 %d명, 부족하면 봇으로 채우세요)" % [Session.lobby.size(), Session.MAX_PLAYERS, Session.MIN_PLAYERS], 24))
	for p in Session.lobby:
		var tag := " (봇)" if p["bot"] else (" (나)" if p["id"] == Session.my_pid else "")
		_lobby_list.add_child(UI.label("• " + p["name"] + tag, 26))


# ─────────────────────────────── 게임 ───────────────────────────────

func _show_game() -> void:
	var g := GameScreen.new()
	_set_screen(g)
