class_name Info
extends RefCounted
## 사도·아티팩트 정보 화면 구성 (게임 화면 오른쪽 패널, 도감에서 함께 사용)

const STAT_NAME := {
	"hp": "최대 HP", "atk": "공격력", "patk": "물리 공격력", "matk": "마법 공격력", "def": "방어력",
	"pdef": "물리 방어력", "mdef": "마법 방어력", "aspd": "공격 속도", "crit": "치명타", "critdmg": "치명 피해",
	"critres": "치명타 저항", "critdmgres": "치명 피해 저항", "heal_out": "치유량", "heal_in": "HP 회복량",
}


const TABS := {"skill": "스킬", "aside": "어사이드", "art": "아티팩트"}
## 마지막으로 본 사도 정보 탭 (다른 사도를 눌러도 유지)
static var apostle_tab := "skill"


## 제목: 위 간격 + 강조색 글자 + 짧은 색 밑줄
static func section(box: Control, title: String, color: Color = UI.ACCENT) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	box.add_child(gap)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.add_child(UI.label(title, 22, color))
	var bar := ColorRect.new()
	bar.color = Color(color, 0.8)
	bar.custom_minimum_size = Vector2(56, 3)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(bar)
	box.add_child(v)


## 사도 정보. on_art: 장착 아티팩트를 눌렀을 때 (uid) 호출, sel_art: 선택된 아티팩트 uid
static func apostle(box: Control, u: Dictionary, on_art: Callable = Callable(), sel_art: int = -1, show_sell: bool = true) -> void:
	var aid: String = u["aid"]
	var a := GameData.apostle(aid)
	var star := int(u.get("star", 1))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	var pf := UI.panel(UI.pers_color(aid, u.get("pers", "")).darkened(0.55), 12, UI.pers_color(aid, u.get("pers", "")), 3)
	pf.add_child(UI.tex_rect(UI.portrait(aid), Vector2(96, 96), true))
	head.add_child(pf)
	# 전투 모션 미리보기 (누르면 공격 → 스킬 → 궁극기 순서로)
	if MotionSprite.available(aid):
		var mb := Button.new()
		mb.custom_minimum_size = Vector2(110, 120)
		mb.focus_mode = Control.FOCUS_NONE
		mb.add_theme_stylebox_override("normal", UI.box(Color(0, 0, 0, 0.18), 12))
		mb.add_theme_stylebox_override("hover", UI.box(Color(1, 1, 1, 0.06), 12))
		mb.add_theme_stylebox_override("pressed", UI.box(Color(0, 0, 0, 0.3), 12))
		var sp := MotionSprite.new(aid)
		sp.face_right = true
		sp.box = 150.0
		sp.size = Vector2(110, 112)
		sp.position = Vector2(0, 0)
		mb.add_child(sp)
		Tips.set_tip(mb, "전투 모션 — 누르면 공격·스킬·궁극기 동작")
		var seq := ["Attack1_1", "Skill1_1", "Ultimate1_1"]
		var state := {"i": 0}
		mb.pressed.connect(func():
			sp.play(seq[state["i"] % seq.size()], false, "Idle")
			state["i"] += 1)
		head.add_child(mb)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	var nh := HBoxContainer.new()
	nh.add_theme_constant_override("separation", 12)
	hv.add_child(nh)
	nh.add_child(UI.label(a["name"], 28, UI.TEXT))
	nh.add_child(UI.label(UI.stars(star) + "  %d골드" % GameData.cost_of.get(aid, 1), 21, UI.ACCENT))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	hv.add_child(chips)   # 초상화 오른쪽에 (세로 공간 절약)
	var pers: String = a["personality"] + (" → " + u["pers"] if u.get("pers", "") != "" else "")
	var picon: String = u["pers"] if u.get("pers", "") != "" else a["personality"]
	for t in GameData.traits_of(aid):
		chips.add_child(UI.chip(t, UI.syn_color(t), 16))
	chips.add_child(UI.chip(pers, UI.pers_color(aid, u.get("pers", "")), 16, UI.trait_icon(picon)))
	chips.add_child(UI.chip(a["race"], Color("8fb7ff"), 16, UI.trait_icon(a["race"])))
	if a.get("eldyne", false):
		chips.add_child(UI.chip("엘다인", Color("e0b84f"), 16, UI.trait_icon("엘다인")))
	chips.add_child(UI.chip(GameData.ROW_NAME[a["row"]], Color("c0c4d6"), 16, UI.trait_icon(a["row"])))
	chips.add_child(UI.chip(GameData.ROLE_NAME[a["role"]], Color("c0c4d6"), 16, UI.trait_icon(a["role"])))
	chips.add_child(UI.chip(GameData.DAMAGE_NAME[a["damage"]], Color("ff9f6b") if a["damage"] == "physical" else Color("7fb8ff"), 16, UI.trait_icon(a["damage"])))
	var bs := Rules.base_stats(aid, star)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	box.add_child(grid)
	for pair in [["HP", "%d" % bs["hp"]], ["공격력", "%d" % bs["atk"]], ["방어력", "%d" % bs["def"]], ["공속", "%.2f" % bs["aspd"]]]:
		grid.add_child(UI.label(pair[0], 18, UI.SUB))
		grid.add_child(UI.label(pair[1], 21, UI.TEXT))
	if show_sell:
		box.add_child(UI.label("판매 가격  %d골드" % (GameData.cost_of.get(u["aid"], 1) * int(pow(3, int(u.get("star", 1)) - 1))), 19, UI.SUB))
	# 탭: 스킬 / 어사이드 / 아티팩트 (한 번에 보이는 양을 줄여 스크롤을 덜 하게)
	var arts: Array = u.get("arts", [])
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	box.add_child(tabs)
	var pages := {}
	var btns := {}
	for key in TABS:
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 8)
		box.add_child(page)
		pages[key] = page
		var title: String = TABS[key]
		if key == "art":
			title = "아티팩트 %d/%d" % [arts.size(), int(GameData.balance["artifact_slots"])]
		var b := UI.button(title, 19, Vector2(0, 52))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btns[key] = b
		tabs.add_child(b)
	var show := func(k: String) -> void:
		apostle_tab = k
		for key in pages:
			pages[key].visible = key == k
			var on: bool = key == k
			btns[key].add_theme_stylebox_override("normal", UI.box(UI.ACCENT.darkened(0.6) if on else UI.PANEL_LIGHT.darkened(0.15), 10, UI.ACCENT if on else UI.LINE, 3 if on else 2))
			btns[key].add_theme_color_override("font_color", UI.ACCENT if on else UI.SUB)
	for key in btns:
		var kk: String = key
		btns[key].pressed.connect(func(): show.call(kk))

	# ── 스킬
	var sp: VBoxContainer = pages["skill"]
	sp.add_child(UI.wrap_label("현재는 역할별 공통 스킬로 동작합니다 (원작 스킬 구현 예정).", 18, UI.DIM))
	for k in ["fresh", "senior", "passive"]:
		var sk: Dictionary = a.get("skills", {}).get(k, {})
		if sk.is_empty():
			continue
		var kn: String = {"fresh": "저학년 · SP", "senior": "고학년 · 재사용 대기", "passive": "패시브"}[k]
		var card := UI.panel(UI.BG2, 10)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 6)
		card.add_child(cv)
		var h := HFlowContainer.new()
		h.add_theme_constant_override("h_separation", 8)
		h.add_theme_constant_override("v_separation", 4)
		h.add_child(UI.chip(kn, Color("9fd3ff") if k == "fresh" else (UI.ACCENT if k == "senior" else Color("c0c4d6")), 18))
		if sk.get("tr", "") == "translated" and (k == "fresh" or k == "senior"):
			h.add_child(UI.chip("임시 번역", Color("9aa0b4"), 18))
		cv.add_child(h)
		var nl := UI.label(sk["name"], 22, UI.TEXT)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(nl)
		cv.add_child(UI.rich_desc(sk["desc"], 19))
		sp.add_child(card)

	# ── 어사이드
	var ap: VBoxContainer = pages["aside"]
	for n in ["1", "2", "3"]:
		var asd: Dictionary = a.get("aside", {}).get(n, {})
		if asd.is_empty():
			continue
		var on := star >= int(n)
		var card := UI.panel(UI.BG2 if on else UI.BG2.darkened(0.25), 10, UI.GOOD.darkened(0.3) if on else Color.TRANSPARENT, 2 if on else 0)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 6)
		card.add_child(cv)
		var h := HFlowContainer.new()
		h.add_theme_constant_override("h_separation", 8)
		h.add_child(UI.chip("%s성 %s" % [n, "적용 중" if on else "★%s에서 적용" % n], UI.GOOD if on else Color("8a8fa6"), 18))
		if asd.get("tr", "") == "translated":
			h.add_child(UI.chip("임시 번역", Color("9aa0b4"), 18))
		cv.add_child(h)
		var nl := UI.label(asd["name"], 21, UI.TEXT if on else UI.SUB)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(nl)
		cv.add_child(UI.rich_desc(asd["desc"], 19, UI.SUB if on else UI.DIM, Color("ffd98a") if on else UI.DIM))
		ap.add_child(card)
	if a.get("aside", {}).is_empty():
		ap.add_child(UI.label("어사이드 정보 없음", 18, UI.SUB))

	# ── 아티팩트
	var tp: VBoxContainer = pages["art"]
	for art in arts:
		var info := GameData.artifact(art["id"])
		var fav := "  ♥애착" if info.get("owner", "") == a["name"] else ""
		var b := UI.artifact_button(art["id"], Vector2(0, 64), 20, sel_art == int(art["uid"]))
		b.text = "%s%s" % [info["name"], fav]
		var uid := int(art["uid"])
		b.set_meta("art_uid", uid)   # 게임 화면에서 끌어다 놓기(합성) 대상으로 찾을 수 있게
		if on_art.is_valid():
			b.pressed.connect(func(): on_art.call(uid))
		tp.add_child(b)
	if arts.is_empty():
		tp.add_child(UI.wrap_label("보관함의 아티팩트를 이 사도 위로 끌어다 놓거나, 아티팩트를 누른 뒤 이 사도를 누르면 장착합니다.", 18, UI.SUB))
	show.call(apostle_tab if pages.has(apostle_tab) else "skill")


## 아티팩트 정보. where: "inv"(보관함) / "equipped"(장착 중) / ""(도감)
static func artifact(box: Control, art_id: String, where: String = "") -> void:
	var a := GameData.artifact(art_id)
	var col: Color = UI.GRADE_COLOR[a["grade"]]
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	box.add_child(hb)
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
	if where != "":
		chips.add_child(UI.chip("보관함" if where == "inv" else "장착 중", UI.GOOD if where == "inv" else Color("c0c4d6")))
	section(box, "능력치")
	for k in a.get("stats", {}):
		box.add_child(UI.label("%s  +%s%%" % [STAT_NAME.get(k, k), str(a["stats"][k])], 20, UI.TEXT))
	section(box, "효과")
	box.add_child(UI.rich_desc(a.get("text", ""), 20, UI.TEXT))
	if a.get("nostack", false):
		box.add_child(UI.wrap_label("※ 부가 효과는 한 사도에 중첩되지 않음", 18, UI.DIM))
	if a.get("owner", "") != "":
		section(box, "애착: %s" % a["owner"])
		box.add_child(UI.rich_desc(a.get("fav", ""), 19))
		box.add_child(UI.wrap_label("※ 애착 효과는 다음 단계에서 구현 예정", 18, UI.DIM))
	if where != "":
		box.add_child(UI.hsep())
	if where == "inv":
		box.add_child(UI.wrap_label("사도 위로 끌어다 놓거나 사도를 누르면 장착합니다. 같은 등급 아티팩트 위로 끌어다 놓거나 [합성]을 누르면 합칠 수 있습니다.", 18))
	elif where == "equipped":
		box.add_child(UI.wrap_label("장착 중인 아티팩트는 뺄 수 없지만 [합성] 재료로는 쓸 수 있습니다.", 18))


const MOD_NAME := {
	"heal_in": "받는 회복", "shield_in": "받는 보호막", "hp": "최대 HP", "skill_dmg": "스킬 피해",
	"dmg": "피해량", "aspd": "공격 속도", "crit": "치명타", "critdmg": "치명 피해", "normal_dmg": "일반 공격 피해",
	"enh_dmg": "강화 공격 피해", "sp_regen": "SP 회복", "dmg_taken": "받는 피해", "start_shield": "전투 시작 보호막(최대 HP)",
	"def": "방어력", "atk": "공격력", "heal_out": "치유량",
}
const SCOPE_NAME := {"trait": "해당 사도", "team": "아군 전체", "enemy": "적 전체"}


static func mods_text(mods: Dictionary) -> String:
	var parts := []
	for k in mods:
		var v := float(mods[k])
		parts.append("%s %s%s%%" % [MOD_NAME.get(k, k), "+" if v > 0 else "", str(snappedf(v, 0.1)).trim_suffix(".0")])
	return ", ".join(parts)


## 시너지 정보: 컨셉, 단계별 효과, 보드의 해당 사도, 그룹의 해당 사도(코스트)
static func synergy(box: Control, name: String, count: int, board_aids: Array) -> void:
	var syn: Dictionary = GameData.synergies.get(name, {})
	if syn.is_empty():
		return
	var tiers: Array = syn["tiers"]
	var active := 0
	for i in tiers.size():
		if count >= int(tiers[i]):
			active = i + 1
	var col := UI.syn_color(name)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 10)
	th.add_child(UI.syn_badge(name, 44))
	var tl := UI.label("%s  %d명" % [name, count], 26, col)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(tl)
	box.add_child(th)
	var kind_name: String = {"origin": "계열", "cls": "직업", "unique": "고유"}.get(syn.get("kind", ""), "")
	var lines: Array = UI.syn_lines(name)
	if lines[0] != "":
		box.add_child(UI.rich_desc(("[%s] " % kind_name if kind_name != "" else "") + String(lines[0]), 18, UI.SUB, Color("ffd98a"), false))
	for i in tiers.size():
		var on := i < active
		var txt: String = lines[1].get(int(tiers[i]), "")
		if txt == "":
			continue
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		h.add_child(UI.chip("%d명" % int(tiers[i]), col if on else Color("777b8f"), 16))
		var l := UI.rich_desc(txt, 18, UI.TEXT if on else UI.DIM, Color("ffd98a") if on else UI.DIM, false)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		box.add_child(h)
	# 해당 사도 목록
	var members := []
	for aid in GameData.roster:
		if GameData.traits_of(aid).has(name):
			members.append(aid)
	members.sort_custom(func(x, y): return GameData.cost_of[x] * 1000 + (0 if board_aids.has(x) else 1) < GameData.cost_of[y] * 1000 + (0 if board_aids.has(y) else 1))
	section(box, "해당 사도 %d명  (초록 = 내 보드)" % members.size())
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	box.add_child(flow)
	for aid in members:
		var on_board: bool = board_aids.has(aid)
		var chip := UI.chip("%s %dG" % [GameData.apostle(aid)["name"], GameData.cost_of[aid]], UI.GOOD if on_board else UI.cost_color(aid), 15)
		flow.add_child(chip)
