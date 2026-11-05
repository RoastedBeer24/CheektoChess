class_name GameData
extends RefCounted
## 게임 데이터(JSON) 로더. 정적 클래스 — 시작 시 GameData.load_all() 한 번 호출.

const PERSONALITIES := ["순수", "냉정", "광기", "활발", "우울"]
const ROWS := ["front", "mid", "back"]
const ROW_NAME := {"front": "전열", "mid": "중열", "back": "후열", "all": "모든열"}
const ROLE_NAME := {"dealer": "딜러", "tank": "탱커", "support": "서포터"}
const DAMAGE_NAME := {"physical": "물리", "magic": "마법"}

static var apostles: Dictionary = {}      # id -> 사도 정의
static var roster: Array = []             # 지금 그룹에서 상점에 나오는 사도 id 목록
static var cost_of: Dictionary = {}       # id -> 코스트 (지금 그룹)
static var groups: Array = []             # 그룹 정의 (data/groups.json)
static var group_id := ""                 # 지금 쓰는 그룹
static var group_traits: Dictionary = {}  # 사도 id -> [시너지 이름] (지금 그룹)
static var _base_balance: Dictionary = {}
static var artifacts: Dictionary = {}     # id -> 아티팩트 정의
static var artifacts_by_grade: Dictionary = {}  # grade -> [id]
static var synergies: Dictionary = {}     # 시너지 이름 -> 정의 (지금 그룹: id, kind, tiers, color, effect, levels)
static var balance: Dictionary = {}
static var skill_specs: Dictionary = {}  # 사도별 원작 스킬·어사이드·애착 동작 (data/skill_specs.json)
static var unit_tuning: Dictionary = {}  # 사도별 체력·공격력 보정 배율 (data/unit_tuning.json)
static var augments: Dictionary = {}     # 증강 (data/augments.json): {rounds, list}
static var _aug_by_id: Dictionary = {}


static var loaded := false


static func load_all() -> void:
	loaded = true
	balance = _load("res://data/balance.json")
	apostles = _load("res://data/apostles.json")
	var a: Dictionary = _load("res://data/artifacts.json")
	artifacts.clear()
	artifacts_by_grade.clear()
	for g in balance.get("grade_order", []):
		artifacts_by_grade[g] = []
	for item in a.get("list", []):
		artifacts[item["id"]] = item
		artifacts_by_grade[item["grade"]].append(item["id"])
	skill_specs = _load("res://data/skill_specs.json") if FileAccess.file_exists("res://data/skill_specs.json") else {}
	unit_tuning = _load("res://data/unit_tuning.json") if FileAccess.file_exists("res://data/unit_tuning.json") else {}
	unit_tuning.erase("_doc")
	augments = _load("res://data/augments.json") if FileAccess.file_exists("res://data/augments.json") else {"rounds": [], "list": []}
	_aug_by_id.clear()
	for ag in augments.get("list", []):
		_aug_by_id[ag["id"]] = ag
	_base_balance = balance.duplicate(true)
	groups = _load("res://data/groups.json").get("groups", [])
	set_group(groups[0]["id"] if not groups.is_empty() else "")


## 그룹 이름 (id 로)
static func group_name(id: String) -> String:
	for g in groups:
		if g["id"] == id:
			return g.get("name", id)
	return id


## 판에 쓸 그룹을 정한다: 상점 사도·코스트·시너지·풀 크기·상점 확률이 바뀐다.
static func set_group(id: String) -> void:
	var g: Dictionary = {}
	for x in groups:
		if x["id"] == id:
			g = x
	if g.is_empty() and not groups.is_empty():
		g = groups[0]
	group_id = g.get("id", "")
	roster.clear()
	cost_of.clear()
	group_traits.clear()
	synergies.clear()
	balance = _base_balance.duplicate(true)
	if g.has("pool_size"):
		balance["pool_size"] = g["pool_size"]
	if g.has("shop_odds"):
		balance["shop_odds"] = g["shop_odds"]
	for u in g.get("units", []):
		if not apostles.has(u["id"]):
			push_warning("그룹 %s: 알 수 없는 사도 id %s" % [group_id, u["id"]])
			continue
		roster.append(u["id"])
		cost_of[u["id"]] = int(u["cost"])
		group_traits[u["id"]] = u.get("traits", [])
	for syn in g.get("synergies", []):
		synergies[syn["name"]] = syn


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


## 사도가 가진 시너지 이름 목록 (지금 그룹 기준. 성격·종족은 분류로만 쓰고 시너지가 아님)
static func traits_of(apostle_id: String, _chosen_personality: String = "") -> Array:
	return group_traits.get(apostle_id, [])


## 사도가 지금 그룹에 들어 있는지
static func in_group(apostle_id: String) -> bool:
	return cost_of.has(apostle_id)


## 공명/이면 사도가 고를 수 있는 성격 목록 (일반 사도는 빈 배열)
static func personality_options(apostle_id: String) -> Array:
	return apostle(apostle_id).get("personality_options", [])


static func augment(id: String) -> Dictionary:
	return _aug_by_id.get(id, {})


## 증강 이름 (상징은 시너지 이름 포함)
static func augment_name(a: Dictionary) -> String:
	var d := augment(String(a.get("id", "")))
	if a.get("id", "") == "emblem":
		return "상징: " + String(a.get("trait", ""))
	return String(d.get("name", a.get("id", "")))


static func augment_desc(a: Dictionary) -> String:
	var d := augment(String(a.get("id", "")))
	return String(d.get("desc", "")).replace("{trait}", String(a.get("trait", "")))
