class_name Glossary
extends RefCounted
## 게임 용어 사전: 설명 글에서 색을 입히고 밑줄(누르면/올리면 설명)을 다는 데 사용. 도감 '용어' 탭에도 표시.

## 색 규칙 (화면 전체 공통)
const C_GOLD := "ffd25e"      # 골드·숫자
const C_GOOD := "5ee39b"      # 좋음·회복·보호막·적용 중
const C_BAD := "ff7070"       # 위험·약화·상태이상
const C_INFO := "8cc4ff"      # 정보·마법
const C_PHYS := "ffad70"      # 물리
const C_STAT := "f0d8a8"      # 능력치 이름
const C_SKILL := "c9a7ff"     # 스킬·SP

## 용어: 색 + 설명 (같은 뜻의 다른 표기는 ALIAS)
const TERMS := {
	"SP": {"c": C_SKILL, "cat": "전투", "d": "저학년 스킬에 쓰는 힘. 시간이 지나거나 공격하거나 맞으면 차오르고, 가득(100) 차면 저학년 스킬을 씁니다."},
	"저학년 스킬": {"c": C_SKILL, "cat": "전투", "d": "SP가 가득 차면 쓰는 스킬."},
	"고학년 스킬": {"c": C_SKILL, "cat": "전투", "d": "재사용 대기시간마다 자동으로 쓰는 강한 스킬."},
	"재사용 대기": {"c": C_SKILL, "cat": "전투", "d": "스킬을 한 번 쓴 뒤 다시 쓰기까지 기다리는 시간."},
	"일반 공격": {"c": C_STAT, "cat": "전투", "d": "기본 공격. 4번째 공격마다 강화 공격이 나갑니다."},
	"강화 공격": {"c": C_STAT, "cat": "전투", "d": "일반 공격 4번마다 한 번 나가는 더 강한 공격 (피해 180%)."},
	"보호막": {"c": C_GOOD, "cat": "전투", "d": "HP보다 먼저 피해를 대신 받아 주는 막. 다 깎이면 사라집니다."},
	"회복": {"c": C_GOOD, "cat": "전투", "d": "잃은 HP를 되찾습니다. 최대 HP를 넘지 않습니다."},
	"치명타": {"c": C_GOLD, "cat": "능력치", "d": "확률로 피해가 크게 늘어나는 공격. 늘어나는 정도는 치명 피해."},
	"치명 피해": {"c": C_GOLD, "cat": "능력치", "d": "치명타가 났을 때 피해가 늘어나는 비율."},
	"물리 피해": {"c": C_PHYS, "cat": "전투", "d": "물리 공격력으로 주는 피해. 상대의 (물리) 방어력으로 줄어듭니다."},
	"마법 피해": {"c": C_INFO, "cat": "전투", "d": "마법 공격력으로 주는 피해. 상대의 (마법) 방어력으로 줄어듭니다."},
	"방어력": {"c": C_STAT, "cat": "능력치", "d": "받는 피해를 줄입니다. 높을수록 덜 아픕니다."},
	"공격력": {"c": C_STAT, "cat": "능력치", "d": "주는 피해의 기본값."},
	"공격 속도": {"c": C_STAT, "cat": "능력치", "d": "1초에 몇 번 공격하는지. 높을수록 자주 공격합니다."},
	"기절": {"c": C_BAD, "cat": "상태이상", "d": "잠시 공격도 스킬도 못 합니다."},
	"화상": {"c": C_BAD, "cat": "상태이상", "d": "1초마다 건 사도 공격력의 20%만큼 피해를 받습니다."},
	"쓰라림": {"c": C_BAD, "cat": "상태이상", "d": "1초마다 건 사도 공격력의 10%만큼 피해를 받고, 받는 회복이 50% 줄어듭니다."},
	"감전": {"c": C_BAD, "cat": "상태이상", "d": "공격 속도가 20% 줄어듭니다."},
	"눈가림": {"c": C_BAD, "cat": "상태이상", "d": "일반 공격이 50% 확률로 빗나갑니다."},
	"상태이상": {"c": C_BAD, "cat": "상태이상", "d": "기절·화상·쓰라림·감전·눈가림 같은 나쁜 효과."},
	"도발": {"c": C_INFO, "cat": "전투", "d": "적이 이 사도를 먼저 공격하게 만듭니다."},
	"무적": {"c": C_GOOD, "cat": "전투", "d": "잠시 피해와 기절을 받지 않습니다."},
	"처형": {"c": C_BAD, "cat": "전투", "d": "HP가 일정 비율보다 낮은 적을 바로 쓰러뜨립니다."},
	"어사이드": {"c": C_GOLD, "cat": "사도", "d": "사도의 추가 능력. ★1은 1성, ★2는 2성, ★3은 3성 어사이드까지 적용됩니다."},
	"애착": {"c": "ff9ec7", "cat": "사도", "d": "아티팩트마다 정해진 주인 사도가 끼면 추가로 생기는 효과 (아직 동작하지 않음)."},
	"공명": {"c": "e8e8f0", "cat": "시너지", "d": "보드에 올릴 때마다 성격 5가지 중 하나를 골라 그 성격으로 계산됩니다."},
	"이면": {"c": "7fd6d0", "cat": "시너지", "d": "보드에 올릴 때마다 순수/우울 중 하나를 골라 그 성격으로 계산됩니다."},
	"엘다인": {"c": "e0b84f", "cat": "시너지", "d": "특별한 사도 묶음. 보드에 많을수록 시너지 효과가 커집니다."},
	"전열": {"c": "ff9a8a", "cat": "배치", "d": "적과 가장 가까운 열. 전열 사도는 전열에만 놓을 수 있습니다."},
	"중열": {"c": "ffd28a", "cat": "배치", "d": "가운데 열."},
	"후열": {"c": "9ad0ff", "cat": "배치", "d": "적과 가장 먼 열."},
	"모든열": {"c": "c9f0c9", "cat": "배치", "d": "어느 열에나 놓을 수 있습니다."},
	"이자": {"c": C_GOLD, "cat": "경제", "d": "라운드가 끝날 때 가진 골드 10마다 1골드 (최대 5)."},
	"연승": {"c": C_GOLD, "cat": "경제", "d": "연속으로 이기면 라운드마다 추가 골드 (2연속 +1, 4연속 +2, 5연속 이상 +3)."},
	"연패": {"c": C_GOLD, "cat": "경제", "d": "연속으로 지면 라운드마다 추가 골드 (연승과 같은 규칙)."},
	"합성": {"c": C_GOLD, "cat": "경제", "d": "같은 사도 3명 → ★ 한 단계 위. 같은 등급 아티팩트 2개 → 한 등급 위 아티팩트 1개 (보관함으로)."},
}
const ALIAS := {
	"쿨타임": "재사용 대기", "재사용 대기시간": "재사용 대기", "강화공격": "강화 공격", "일반공격": "일반 공격",
	"공속": "공격 속도", "치명타 피해": "치명 피해", "물리 공격력": "공격력", "마법 공격력": "공격력",
	"물리 방어력": "방어력", "마법 방어력": "방어력", "물리피해": "물리 피해", "마법피해": "마법 피해",
	"피해량": "", "HP": "", "스킬 피해": "",
}
## 색만 입히는 단어 (설명 없음)
const COLOR_ONLY := {
	"최대 HP": C_GOOD, "HP": C_GOOD, "피해량": C_STAT, "스킬 피해": C_SKILL, "받는 피해": C_BAD,
	"물리": C_PHYS, "마법": C_INFO, "아군": C_GOOD,
}
## 글 속에서 찾지 않는 단어 ('~이면' 같은 흔한 어미와 겹침). 도감 용어 탭에는 그대로 나온다.
const NO_MATCH := ["이면"]

static var _re: RegEx
static var _lookup := {}


## 단어 → {"c": 색, "term": 설명 키 또는 ""}
static func _build() -> void:
	if _re != null:
		return
	for k in TERMS:
		_lookup[k] = {"c": TERMS[k]["c"], "term": k}
	for k in ALIAS:
		var t: String = ALIAS[k]
		if t != "":
			_lookup[k] = {"c": TERMS[t]["c"], "term": t}
	for k in COLOR_ONLY:
		if not _lookup.has(k):
			_lookup[k] = {"c": COLOR_ONLY[k], "term": ""}
	# 성격·종족 이름은 시너지 색
	for k in UI.PERS_COLOR:
		if not _lookup.has(k):
			_lookup[k] = {"c": UI.PERS_COLOR[k].to_html(false), "term": ""}
	for k in NO_MATCH:
		_lookup.erase(k)
	var words: Array = _lookup.keys()
	words.sort_custom(func(a, b): return a.length() > b.length())   # 긴 단어 먼저
	var alts := []
	for w in words:
		alts.append(_escape(w))
	# 1: 단어, 2: 숫자(+단위)
	_re = RegEx.create_from_string("(" + "|".join(alts) + ")|([+\\-]?\\d+(?:[.,]\\d+)?\\s?(?:%|초|s\\b|회|명|칸|골드|G\\b)?)")


static func _escape(s: String) -> String:
	var out := ""
	for ch in s:
		out += ("\\" + ch) if "\\^$.|?*+()[]{}".contains(ch) else ch
	return out


## 평범한 글 → BBCode (용어는 색 + 밑줄 링크, 숫자는 강조). 대괄호는 전각으로 바꿔 BBCode 충돌 방지.
static func markup(text: String, num_color: String = C_GOLD, links: bool = true) -> String:
	_build()
	text = text.replace("[", "［").replace("]", "］")
	var out := ""
	var last := 0
	for m in _re.search_all(text):
		out += text.substr(last, m.get_start() - last)
		var word := m.get_string(1)
		if word != "":
			var info: Dictionary = _lookup[word]
			if links and info["term"] != "":
				out += "[url=%s][color=#%s]%s[/color][/url]" % [info["term"], info["c"], word]
			else:
				out += "[color=#%s]%s[/color]" % [info["c"], word]
		else:
			out += "[color=#%s]%s[/color]" % [num_color, m.get_string(2)]
		last = m.get_end()
	out += text.substr(last)
	return out


static func describe(term: String) -> String:
	var t: Dictionary = TERMS.get(term, {})
	if t.is_empty():
		return ""
	return "[b][color=#%s]%s[/color][/b]\n%s" % [t["c"], term, markup(t["d"], C_GOLD, false)]
