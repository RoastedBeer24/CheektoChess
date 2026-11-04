class_name GameData
extends RefCounted
## 게임 데이터(JSON) 로더. 정적 클래스 — 시작 시 GameData.load_all() 한 번 호출.

const PERSONALITIES := ["순수", "냉정", "광기", "활발", "우울"]
const ROWS := ["front", "mid", "back"]
const ROW_NAME := {"front": "전열", "mid": "중열", "back": "후열", "all": "모든열"}
const ROLE_NAME := {"dealer": "딜러", "tank": "탱커", "support": "서포터"}
const DAMAGE_NAME := {"physical": "물리", "magic": "마법"}

static var apostles: Dictionary = {}      # id -> 사도 정의
static var roster: Array = []             # 상점에 나오는 사도 id 목록
static var cost_of: Dictionary = {}       # id -> 코스트
static var artifacts: Dictionary = {}     # id -> 아티팩트 정의
static var artifacts_by_grade: Dictionary = {}  # grade -> [id]
static var synergies: Dictionary = {}     # 시너지 이름 -> 정의 (+ "group")
static var balance: Dictionary = {}


static var loaded := false


static func load_all() -> void:
	loaded = true
	balance = _load("res://data/balance.json")
	apostles = _load("res://data/apostles.json")
	var r: Dictionary = _load("res://data/roster.json")
	roster.clear()
	cost_of.clear()
	for e in r.get("pool", []):
		if apostles.has(e["id"]):
			roster.append(e["id"])
			cost_of[e["id"]] = int(e["cost"])
		else:
			push_warning("roster: 알 수 없는 사도 id %s" % e["id"])
	var a: Dictionary = _load("res://data/artifacts.json")
	artifacts.clear()
	artifacts_by_grade.clear()
	for g in balance.get("grade_order", []):
		artifacts_by_grade[g] = []
	for item in a.get("list", []):
		artifacts[item["id"]] = item
		artifacts_by_grade[item["grade"]].append(item["id"])
	var s: Dictionary = _load("res://data/synergies.json")
	synergies.clear()
	for group in ["personality", "race", "special"]:
		for name in s.get(group, {}):
			var d: Dictionary = s[group][name].duplicate(true)
			d["group"] = group
			synergies[name] = d


static func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("데이터 파일을 열 수 없음: %s" % path)
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("JSON 형식 오류: %s" % path)
		return {}
	return data


static func apostle(id: String) -> Dictionary:
	return apostles.get(id, {})


static func artifact(id: String) -> Dictionary:
	return artifacts.get(id, {})


static func grade_name(g: String) -> String:
	return balance["grade_name"].get(g, g)


static func next_grade(g: String) -> String:
	var order: Array = balance["grade_order"]
	var i := order.find(g)
	if i < 0 or i >= order.size() - 1:
		return ""
	return order[i + 1]


## 사도가 놓일 수 있는 열인지
static func can_place(apostle_id: String, row: int) -> bool:
	var r: String = apostle(apostle_id).get("row", "all")
	return r == "all" or ROWS[row] == r


## 사도가 가진 시너지 이름 목록 (공명/이면은 선택한 성격 사용)
static func traits_of(apostle_id: String, chosen_personality: String = "") -> Array:
	var a := apostle(apostle_id)
	var out := []
	var p: String = a.get("personality", "")
	if p == "공명" or p == "이면":
		if chosen_personality != "":
			out.append(chosen_personality)
	else:
		out.append(p)
	out.append(a.get("race", ""))
	if a.get("eldyne", false):
		out.append("엘다인")
	return out


## 공명/이면 사도가 고를 수 있는 성격 목록 (일반 사도는 빈 배열)
static func personality_options(apostle_id: String) -> Array:
	return apostle(apostle_id).get("personality_options", [])
