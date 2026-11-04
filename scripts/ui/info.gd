class_name Info
extends RefCounted
## 사도·아티팩트 정보 화면 구성 (게임 화면 오른쪽 패널, 도감에서 함께 사용)

const STAT_NAME := {
	"hp": "최대 HP", "atk": "공격력", "patk": "물리 공격력", "matk": "마법 공격력", "def": "방어력",
	"pdef": "물리 방어력", "mdef": "마법 방어력", "aspd": "공격 속도", "crit": "치명타", "critdmg": "치명 피해",
	"critres": "치명타 저항", "critdmgres": "치명 피해 저항", "heal_out": "치유량", "heal_in": "HP 회복량",
}


static func section(box: Control, title: String) -> void:
	box.add_child(UI.hsep())
	box.add_child(UI.label(title, 20, UI.ACCENT))


## 사도 정보. on_art: 장착 아티팩트를 눌렀을 때 (uid) 호출, sel_art: 선택된 아티팩트 uid
static func apostle(box: Control, u: Dictionary, on_art: Callable = Callable(), sel_art: int = -1, show_sell: bool = true) -> void:
	var aid: String = u["aid"]
	var a := GameData.apostle(aid)
	var star := int(u.get("star", 1))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	var pf := UI.panel(UI.pers_color(aid, u.get("pers", "")).darkened(0.55), 12, UI.pers_color(aid, u.get("pers", "")), 3)
	pf.add_child(UI.tex_rect(UI.portrait(aid), Vector2(112, 112), true))
	head.add_child(pf)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	hv.add_child(UI.label(a["name"], 30, UI.TEXT))
	hv.add_child(UI.label(UI.stars(star) + "  ·  %d골드" % GameData.cost_of.get(aid, 1), 22, UI.ACCENT))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	box.add_child(chips)
	var pers: String = a["personality"] + (" → " + u["pers"] if u.get("pers", "") != "" else "")
	chips.add_child(UI.chip(pers, UI.pers_color(aid, u.get("pers", ""))))
	chips.add_child(UI.chip(a["race"], Color("8fb7ff")))
	if a.get("eldyne", false):
		chips.add_child(UI.chip("엘다인", Color("e0b84f")))
	chips.add_child(UI.chip(GameData.ROW_NAME[a["row"]], Color("c0c4d6")))
	chips.add_child(UI.chip(GameData.ROLE_NAME[a["role"]], Color("c0c4d6")))
	chips.add_child(UI.chip(GameData.DAMAGE_NAME[a["damage"]], Color("ff9f6b") if a["damage"] == "physical" else Color("7fb8ff")))
	var bs := Rules.base_stats(aid, star)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	box.add_child(grid)
	for pair in [["HP", "%d" % bs["hp"]], ["공격력", "%d" % bs["atk"]], ["방어력", "%d" % bs["def"]], ["공속", "%.2f" % bs["aspd"]]]:
		grid.add_child(UI.label(pair[0], 17, UI.SUB))
		grid.add_child(UI.label(pair[1], 19, UI.TEXT))
	section(box, "스킬")
	box.add_child(UI.wrap_label("현재는 역할별 공통 스킬로 동작합니다 (원작 스킬 구현 예정).", 15, UI.SUB))
	for k in ["fresh", "senior", "passive"]:
		var sk: Dictionary = a.get("skills", {}).get(k, {})
		if sk.is_empty():
			continue
		var kn: String = {"fresh": "저학년 · SP", "senior": "고학년 · 재사용 대기", "passive": "패시브"}[k]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		h.add_child(UI.chip(kn, Color("9fd3ff") if k == "fresh" else (UI.ACCENT if k == "senior" else Color("c0c4d6")), 15))
		var nl := UI.label(sk["name"], 19, UI.TEXT)
		nl.clip_text = true
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nl)
		box.add_child(h)
		box.add_child(UI.wrap_label(sk["desc"], 15))
	section(box, "어사이드")
	for n in ["1", "2", "3"]:
		var asd: Dictionary = a.get("aside", {}).get(n, {})
		if asd.is_empty():
			continue
		var on := star >= int(n)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		h.add_child(UI.chip("%s성 %s" % [n, "적용" if on else "잠김"], UI.GOOD if on else Color("777b8f"), 15))
		var nl := UI.label(asd["name"], 19, UI.TEXT if on else UI.SUB)
		nl.clip_text = true
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nl)
		box.add_child(h)
		box.add_child(UI.wrap_label(asd["desc"], 15, UI.SUB if on else Color(1, 1, 1, 0.35)))
	if a.get("aside", {}).is_empty():
		box.add_child(UI.label("어사이드 정보 없음", 16, UI.SUB))
	section(box, "아티팩트  %d / %d" % [u.get("arts", []).size(), int(GameData.balance["artifact_slots"])])
	for art in u.get("arts", []):
		var info := GameData.artifact(art["id"])
		var fav := "  ♥애착" if info.get("owner", "") == a["name"] else ""
		var b := UI.artifact_button(art["id"], Vector2(0, 58), 18, sel_art == int(art["uid"]))
		b.text = "%s%s" % [info["name"], fav]
		var uid := int(art["uid"])
		if on_art.is_valid():
			b.pressed.connect(func(): on_art.call(uid))
		box.add_child(b)
	if u.get("arts", []).is_empty():
		box.add_child(UI.label("보관함의 아티팩트를 누른 뒤 이 사도를 누르면 장착", 16, UI.SUB))
	if show_sell:
		box.add_child(UI.label("판매 가격  %d골드" % (GameData.cost_of.get(u["aid"], 1) * int(pow(3, int(u.get("star", 1)) - 1))), 18, UI.SUB))


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
	box.add_child(UI.wrap_label(a.get("text", ""), 18, UI.TEXT))
	if a.get("nostack", false):
		box.add_child(UI.label("※ 부가 효과는 한 사도에 중첩되지 않음", 15, UI.SUB))
	if a.get("owner", "") != "":
		section(box, "애착: %s" % a["owner"])
		box.add_child(UI.wrap_label(a.get("fav", ""), 16))
		box.add_child(UI.label("※ 애착 효과는 다음 단계에서 구현 예정", 15, UI.SUB))
	if where != "":
		box.add_child(UI.hsep())
	if where == "inv":
		box.add_child(UI.wrap_label("사도를 누르면 장착합니다. [합성]을 누르면 같은 등급 아티팩트와 합칠 수 있습니다.", 16))
	elif where == "equipped":
		box.add_child(UI.wrap_label("장착 중인 아티팩트는 뺄 수 없지만 [합성] 재료로는 쓸 수 있습니다.", 16))


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


## 시너지 정보: 단계별 효과, 보드의 해당 사도, 전체 해당 사도(코스트)
static func synergy(box: Control, name: String, count: int, board_aids: Array) -> void:
	var syn: Dictionary = GameData.synergies.get(name, {})
	if syn.is_empty():
		return
	var tiers: Array = syn["tiers"]
	var active := 0
	for i in tiers.size():
		if count >= int(tiers[i]):
			active = i + 1
	var col: Color = UI.PERS_COLOR.get(name, Color("e0b84f") if name == "엘다인" else Color("8fb7ff"))
	box.add_child(UI.label("%s  %d명" % [name, count], 28, col))
	box.add_child(UI.wrap_label("%s · 적용: %s" % [syn.get("desc", ""), SCOPE_NAME.get(syn.get("scope", ""), "")], 17, UI.SUB))
	for i in tiers.size():
		var on := i < active
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		h.add_child(UI.chip("%d명" % int(tiers[i]), col if on else Color("777b8f"), 16))
		var l := UI.wrap_label(mods_text(syn["mods"][i]), 17, UI.TEXT if on else UI.SUB)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		box.add_child(h)
	# 해당 사도 목록
	var members := []
	for aid in GameData.roster:
		var a := GameData.apostle(aid)
		var opts: Array = a.get("personality_options", [])
		if GameData.traits_of(aid, "").has(name) or opts.has(name):
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
