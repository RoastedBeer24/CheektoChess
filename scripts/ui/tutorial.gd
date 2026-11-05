class_name Tutorial
extends Control
## 튜토리얼 안내 (게임 화면 위에 덮음). 단계마다 설명 + 강조 칸, 직접 해 보면 다음 단계로.
## App.session.start_tutorial() 로 시작한 연습 판에서만 뜬다.

var gs: GameScreen
var _step := 0
var _box: PanelContainer
var _title: Label
var _text: RichTextLabel
var _next: Button
var _count: Label
var _hl: Rect2 = Rect2()
var _t := 0.0

## [제목, 설명, 강조 대상 키, 완료 조건 키("" = 다음 버튼)]
const STEPS := [
	["볼토체스에 오신 것을 환영합니다", "사도를 모아 보드에 세우면 자동으로 싸우는 게임입니다. 8명까지 마지막 1명이 남을 때까지 겨룹니다.\n이 연습 판은 준비 시간이 멈춰 있으니 천천히 따라 해 보세요.", "", ""],
	["1. 사도 사기", "아래 상점의 사도 카드를 눌러 사거나, 대기석·보드의 원하는 칸으로 끌어다 놓아 사 보세요. 카드 테두리 색은 코스트(가격)입니다.\n상점 왼쪽 표는 지금 레벨에서 코스트별로 나올 확률입니다.", "shop", "bought"],
	["2. 보드에 세우기", "대기석의 사도를 위쪽 보드로 끌어다 놓으세요. 모든 이동은 끌어다 놓기로 합니다 (사도를 누르면 정보만 봅니다).\n사도마다 설 수 있는 열(전열·중열·후열)이 정해져 있고, 보드 인원 = 레벨입니다. 끄는 동안 왼쪽 시너지에 바뀌는 수치가 미리 보입니다.", "board", "placed"],
	["3. 합성", "같은 사도 3명을 모으면 ★2 로 합성되어 훨씬 강해집니다. 상점에 같은 사도가 여러 장 있습니다 — 모두 사 보세요.\n★3 을 완성한 사도는 그 게임에서 더는 나오지 않습니다.", "shop", "merged"],
	["4. 시너지", "왼쪽 아래 '시너지'는 보드의 사도가 함께 켜는 효과입니다. 필요 인원(예: 2/4/6)을 채우면 단계가 오릅니다.\nPC는 마우스를 올리고, 모바일은 꾹 눌러 자세히 볼 수 있습니다.", "synergy", ""],
	["5. 아티팩트 장착", "오른쪽 아래 보관함의 아티팩트를 보드의 사도 위로 끌어다 놓아 장착하세요. 한 사도에 3개까지, 장착하면 뺄 수 없습니다.", "inv", "equipped"],
	["6. 골드와 레벨", "골드는 라운드마다 들어오고, 10골드마다 이자 1골드가 붙습니다(최대 5).\n'새로고침'은 상점을 다시 뽑고, '경험치'로 레벨을 올리면 보드 인원이 늘고 비싼 사도가 자주 나옵니다.", "economy", ""],
	["7. 전투", "'준비 완료'를 누르면 전투가 시작됩니다. 전투는 자동이고, 지면 살아남은 적 수만큼 체력이 줄어듭니다.\n이름표 아래 파란 막대는 SP — 가득 차면 곧 스킬을 씁니다. 전투 중 사도를 꾹 누르면 노리는 대상이 선으로 보입니다.", "ready", "battle"],
	["8. 특별한 라운드", "몬스터 라운드(1·2·9·16)는 몬스터와 싸워 골드·아티팩트를 얻습니다. 연승·연패와 체력에는 영향이 없습니다.\n공유 선택 라운드(4·9·13·17)에서는 체력이 낮은 사람부터 한 명당 15초 안에 사도+아티팩트 묶음을 고릅니다.\n게임이 끝나면 1위의 MVP 사도 3명이 발표됩니다.", "", ""],
	["튜토리얼 끝!", "기본은 모두 익혔습니다. 이 판을 계속해도 되고, 첫 화면으로 돌아가 봇전·LAN 방을 시작해도 됩니다.\n도감의 '용어' 탭과 밑줄 친 단어에서 규칙을 더 볼 수 있습니다.", "", "end"],
]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 40
	_box = UI.panel(Color("101828"), 16, UI.ACCENT, 3)
	_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_box.custom_minimum_size = Vector2(760, 0)
	add_child(_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_box.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	_title = UI.label("", 28, UI.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_title)
	_count = UI.label("", 18, UI.SUB)
	h.add_child(_count)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("normal_font_size", UI.fs(21))
	_text.add_theme_color_override("default_color", UI.TEXT)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_text)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 10)
	bh.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(bh)
	var skip := UI.button("튜토리얼 끝내기", 18, Vector2(170, 46), Color("4a3a3a"))
	skip.pressed.connect(_finish)
	bh.add_child(skip)
	_next = UI.button("다음", 20, Vector2(140, 46), Color("2f6b4a"))
	_next.pressed.connect(func(): _go(_step + 1))
	bh.add_child(_next)
	_go(0)


func _go(i: int) -> void:
	if i >= STEPS.size():
		_finish()
		return
	_step = i
	var s: Array = STEPS[i]
	_title.text = s[0]
	_text.text = s[1]
	_count.text = "%d / %d" % [i + 1, STEPS.size()]
	var cond: String = s[3]
	_next.visible = cond == "" or cond == "end"
	_next.text = "마치기" if cond == "end" else "다음"
	if cond == "end":
		Settings.set_value("tutorial_done", true)
	_box.reset_size()


func _finish() -> void:
	Settings.set_value("tutorial_done", true)
	queue_free()


func _target_rect(key: String) -> Rect2:
	var c: Control = null
	match key:
		"shop":
			c = gs._shop_tiles[0].get_parent()
		"board":
			c = gs._board_root
		"synergy":
			c = gs._syn_box
		"inv":
			c = gs._inv_grid.get_parent()
		"economy":
			c = gs._reroll_btn.get_parent()
		"ready":
			c = gs._ready_btn
	return c.get_global_rect() if c != null and c.is_visible_in_tree() else Rect2()


func _done(cond: String) -> bool:
	var p: Dictionary = gs.me()
	if p.is_empty():
		return false
	match cond:
		"bought":
			for u in p.get("bench", []):
				if u != null:
					return true
			return not p.get("board", {}).is_empty()
		"placed":
			return not p.get("board", {}).is_empty()
		"merged":
			for u in gs._all_my_units():
				if int(u["star"]) >= 2:
					return true
		"equipped":
			for k in p.get("board", {}):
				if not p["board"][k].get("arts", []).is_empty():
					return true
		"battle":
			return App.session.state.get("phase", "") == "battle"
	return false


func _process(delta: float) -> void:
	_t += delta
	var cond: String = STEPS[_step][3]
	if cond != "" and cond != "end" and _done(cond):
		_go(_step + 1)
		return
	_hl = _target_rect(STEPS[_step][2])
	# 안내 상자: 강조 칸과 겹치지 않게 위쪽 또는 아래쪽
	var vp := get_viewport_rect().size
	_box.reset_size()
	var y := 130.0
	if _hl.size != Vector2.ZERO and _hl.position.y < vp.y * 0.45:
		y = vp.y - _box.size.y - 20.0
	_box.position = Vector2((vp.x - _box.size.x) / 2.0, y)
	queue_redraw()


func _draw() -> void:
	if _hl.size == Vector2.ZERO:
		return
	var a := 0.55 + 0.45 * sin(_t * 5.0)
	draw_rect(_hl.grow(6), Color(UI.ACCENT, a), false, 5.0)
