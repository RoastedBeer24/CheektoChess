class_name SettingsPanel
extends Control
## 설정·기록 화면 (전체 화면 덮개). 첫 화면과 게임 화면에서 연다.

var _tab := "settings"
var _body: VBoxContainer
var _tab_btns := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 60
	mouse_filter = Control.MOUSE_FILTER_STOP
	if Tips.inst:
		Tips.inst.dismiss()
	var bg := ColorRect.new()
	bg.color = Color(UI.BG, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_right = -24
	root.offset_top = 16
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	root.add_child(top)
	top.add_child(UI.outlined("설정", 40, UI.ACCENT, 8, HORIZONTAL_ALIGNMENT_LEFT))
	for t in [["settings", "설정"], ["history", "기록"]]:
		var b := UI.button(t[1], 24, Vector2(150, 60))
		var key: String = t[0]
		b.pressed.connect(func(): _set_tab(key))
		top.add_child(b)
		_tab_btns[key] = b
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(UI.label("빌드 %d · %s" % [App.build, App.version], 18, UI.DIM))
	var close := UI.button("닫기", 22, Vector2(120, 60), Color("6b3535"))
	close.pressed.connect(queue_free)
	top.add_child(close)
	var panel := UI.panel()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(panel)
	var scroll := DragScroll.new(UI.PANEL)
	panel.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 14)
	scroll.add_child(_body)
	_set_tab("settings")


func _set_tab(t: String) -> void:
	_tab = t
	for k in _tab_btns:
		var on: bool = k == t
		_tab_btns[k].add_theme_stylebox_override("normal", UI.box(UI.ACCENT.darkened(0.55) if on else UI.PANEL_LIGHT, 12, UI.ACCENT if on else UI.PANEL_LIGHT.lightened(0.18), 2))
	UI.clear(_body)
	if t == "settings":
		_build_settings()
	else:
		_build_history()


# ─────────────────────────────── 설정 ───────────────────────────────

func _build_settings() -> void:
	Info.section(_body, "소리")
	_slider("전체 음량", "vol_master")
	_slider("보이스 (사도 대사)", "vol_voice")
	_slider("효과음", "vol_sfx")
	Info.section(_body, "전투")
	_choice("전투 기본 속도", "battle_speed", [["x1", 1.0], ["x1.25", 1.25], ["x1.5", 1.5], ["x2", 2.0]])
	_toggle("전투 모션 (끄면 초상화 카드로 싸움 — 저사양 기기용)", "battle_motion")
	_toggle("준비 단계 보드에서 사도 모션", "board_motion")
	_choice("모션 화질 (낮음: 메모리 1/4 — 저사양 기기용, 다음 전투부터)", "motion_quality", [["높음", 1], ["낮음", 0]])
	_toggle("화면 흔들림 (치명타·궁극기)", "screen_shake")
	_choice("피해·회복 숫자", "dmg_numbers", [["전부", 0], ["치명타·스킬만", 1], ["끄기", 2]])
	_toggle("이름표 아래 SP 막대 (가득 차면 곧 스킬)", "sp_bar")
	Info.section(_body, "화면·조작")
	_choice("화면 크기 (버튼·칸·글자 전체 — 휴대폰은 자동으로 크게)", "ui_scale", [["자동 (%.2f배)" % UI.auto_ui_scale(), 0.0], ["1배", 1.0], ["1.15배", 1.15], ["1.3배", 1.3]])
	_choice("글자 크기 (다음에 여는 화면부터)", "text_scale", [["보통", 1.0], ["크게", 1.15], ["아주 크게", 1.3]])
	_toggle("색약 모드 (좋음=파랑, 위험=주황)", "colorblind")
	_toggle("상점 구매 추천 (보드에 올리면 시너지 단계가 오르는 사도에 ▲ 표시)", "shop_hint")
	if OS.has_feature("android"):
		_toggle("진동", "vibrate")
	Info.section(_body, "튜토리얼")
	var tb := UI.button("튜토리얼 시작", 22, Vector2(260, 58), Color("2f4f86"))
	tb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tb.pressed.connect(func():
		queue_free()
		App.session.start_tutorial())
	_body.add_child(tb)


func _row(title: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var l := UI.label(title, 22, UI.TEXT)
	l.custom_minimum_size.x = 520
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(l)
	_body.add_child(h)
	return h


func _toggle(title: String, key: String) -> void:
	var h := _row(title)
	var on := Settings.flag(key)
	var b := UI.button("켜짐" if on else "꺼짐", 22, Vector2(140, 54), Color("2f6b4a") if on else UI.PANEL_LIGHT)
	b.pressed.connect(func():
		Settings.set_value(key, not Settings.flag(key))
		UI.apply_settings()
		_set_tab("settings"))
	h.add_child(b)


func _choice(title: String, key: String, opts: Array) -> void:
	var h := _row(title)
	var cur := Settings.num(key)
	for o in opts:
		var on: bool = is_equal_approx(cur, float(o[1]))
		var b := UI.button(o[0], 22, Vector2(130, 54), UI.ACCENT.darkened(0.55) if on else UI.PANEL_LIGHT)
		var v: float = o[1]
		b.pressed.connect(func():
			Settings.set_value(key, v)
			UI.apply_settings()
			if key == "ui_scale":
				UI.apply_ui_scale(get_tree().root)
			_set_tab("settings"))
		h.add_child(b)


func _slider(title: String, key: String) -> void:
	var h := _row(title)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 5
	s.value = Settings.num(key) * 100.0
	s.custom_minimum_size = Vector2(320, 44)
	h.add_child(s)
	var v := UI.label("%d%%" % int(s.value), 22, UI.SUB)
	v.custom_minimum_size.x = 70
	h.add_child(v)
	s.value_changed.connect(func(x):
		v.text = "%d%%" % int(x)
		Settings.set_value(key, x / 100.0))


# ─────────────────────────────── 기록 ───────────────────────────────

func _build_history() -> void:
	var st := History.stats()
	if st["games"] == 0:
		_body.add_child(UI.wrap_label("아직 끝까지 마친 게임이 없습니다. 게임을 마치면 순위와 쓴 사도·시너지가 여기에 쌓입니다.", 22, UI.SUB))
		return
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 14)
	_body.add_child(grid)
	for pair in [["게임", str(st["games"])], ["1위", "%d번" % st["wins"]], ["4위 이내", "%d%%" % int(100.0 * st["top4"] / st["games"])], ["평균 순위", "%.1f위" % st["avg_place"]]]:
		var card := UI.panel(UI.BG2, 12)
		card.custom_minimum_size = Vector2(200, 0)
		var v := VBoxContainer.new()
		card.add_child(v)
		v.add_child(UI.label(pair[0], 18, UI.SUB))
		v.add_child(UI.label(pair[1], 32, UI.ACCENT))
		grid.add_child(card)
	# 도감 수집: 이번 그룹 사도 중 써 본 사도·★3 을 만든 사도
	var recs := History.apostle_records()
	var used := 0
	var s3 := 0
	for aid in GameData.roster:
		if recs.has(aid) and int(recs[aid]["used"]) > 0:
			used += 1
		if recs.get(aid, {}).get("star3", "") != "":
			s3 += 1
	Info.section(_body, "도감 수집 (%s)" % GameData.group_name(GameData.group_id))
	var cl := HBoxContainer.new()
	cl.add_theme_constant_override("separation", 14)
	_body.add_child(cl)
	for pair in [["써 본 사도", "%d / %d" % [used, GameData.roster.size()]], ["★3 을 만든 사도", "%d / %d" % [s3, GameData.roster.size()]]]:
		var card := UI.panel(UI.BG2, 12)
		card.custom_minimum_size = Vector2(240, 0)
		var cv := VBoxContainer.new()
		card.add_child(cv)
		cv.add_child(UI.label(pair[0], 18, UI.SUB))
		cv.add_child(UI.label(pair[1], 30, UI.ACCENT))
		cl.add_child(card)
	_body.add_child(UI.wrap_label("사도별 기록(쓴 판·1위·★3)은 도감에서 사도를 누르면 볼 수 있습니다.", 18, UI.SUB))
	Info.section(_body, "많이 켠 시너지")
	var sflow := HFlowContainer.new()
	sflow.add_theme_constant_override("h_separation", 8)
	sflow.add_theme_constant_override("v_separation", 8)
	_body.add_child(sflow)
	for pair in st["synergies"].slice(0, 12):
		sflow.add_child(UI.chip("%s ×%d" % [pair[0], pair[1]], UI.syn_color(pair[0]) if GameData.synergies.has(pair[0]) else UI.SUB, 20))
	Info.section(_body, "최근 게임")
	var games := History.load_all()
	games.reverse()
	for g in games.slice(0, 20):
		var row := UI.panel(UI.BG2, 10)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		row.add_child(h)
		var pl := int(g.get("place", 0))
		h.add_child(UI.label("%d위" % pl, 26, UI.ACCENT if pl == 1 else (UI.GOOD if pl <= 4 else UI.SUB)))
		h.add_child(UI.label("%s · %d명 · 라운드 %d · %s" % [String(g.get("date", "")).substr(0, 16), int(g.get("players", 0)), int(g.get("round", 0)), g.get("group", "")], 18, UI.SUB))
		var pics := HBoxContainer.new()
		pics.add_theme_constant_override("separation", 2)
		for u in g.get("board", []).slice(0, 9):
			pics.add_child(UI.tex_rect(UI.portrait(u["aid"]), Vector2(40, 40), true))
		h.add_child(pics)
		_body.add_child(row)
