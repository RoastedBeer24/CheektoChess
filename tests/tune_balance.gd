extends Node
## 밸런스 자동 조정: 무작위 팀 전투로 사도별 '팀 승률'을 재고, 50%에서 벗어난 만큼 체력·공격력 배율을 조금씩 고친다.
##   godot --headless --path . res://tests/tune_balance.tscn -- [반복=4] [반복마다 전투 수=2500]
## 결과: data/unit_tuning.json (게임이 바로 씀), docs/TUNING.md (전·후 표)
## 1:1 이 아니라 팀(5명, 코스트 섞어서)으로 재므로 서포터의 팀 기여도 반영된다.

const MIN_M := 0.85
const MAX_M := 1.3
const STEP := 0.6        # 승률 차이(0~0.5) → 배율 변화 비율


func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var iters := int(args[0]) if args.size() > 0 else 4
	var n := int(args[1]) if args.size() > 1 else 2500
	var ids: Array = GameData.roster.duplicate()
	ids.sort()
	GameData.unit_tuning = {}
	var first := _measure(ids, n, 1)
	var tuning := {}
	for it in iters:
		var wr := first if it == 0 else _measure(ids, n, 100 + it)
		var mean := _cost_means(ids, wr)
		for aid in ids:
			var m := float(tuning.get(aid, 1.0))
			# 같은 코스트 평균과 비교 (비싼 사도가 더 강한 것은 정상)
			var d := float(wr[aid]) - float(mean[GameData.cost_of[aid]])
			m = clampf(m * (1.0 - STEP * d), MIN_M, MAX_M)
			tuning[aid] = snappedf(m, 0.01)
		GameData.unit_tuning = tuning
		print("반복 %d 끝" % (it + 1))
	var last := _measure(ids, n, 999)
	var out := {"_doc": "tests/tune_balance 가 만든 사도별 체력·공격력 배율 (1 = 기본). 팀 전투 승률을 50%에 맞춤"}
	for aid in ids:
		if absf(float(tuning[aid]) - 1.0) >= 0.01:
			out[aid] = tuning[aid]
	var f := FileAccess.open("res://data/unit_tuning.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " ", true))
	f.close()
	var lines := ["# 밸런스 자동 조정 결과", "", "`godot --headless --path . res://tests/tune_balance.tscn -- %d %d` (그룹: %s)" % [iters, n, GameData.group_name(GameData.group_id)], "",
		"무작위 5명 팀(코스트 섞음, ★1~2) 전투에서 그 사도가 든 팀의 승률. 같은 코스트 평균에 맞춤(비싼 사도가 강한 것은 그대로). 배율은 체력·공격력에 곱함.", "",
		"| 사도 | 코스트 | 역할 | 조정 전 팀 승률 | 배율 | 조정 후 팀 승률 |", "|---|---|---|---|---|---|"]
	var rows := ids.duplicate()
	rows.sort_custom(func(a, b): return float(first[a]) < float(first[b]))
	for aid in rows:
		var a := GameData.apostle(aid)
		lines.append("| %s | %d | %s | %d%% | x%.2f | %d%% |" % [a.get("name", aid), GameData.cost_of.get(aid, 1), GameData.ROLE_NAME.get(a.get("role", "dealer"), ""), int(100 * first[aid]), float(tuning[aid]), int(100 * last[aid])])
	var spread0 := _spread(first)
	var spread1 := _spread(last)
	lines.insert(5, "같은 코스트 안 승률 차이(표준편차): 조정 전 %.1f%%p → 조정 후 %.1f%%p" % [spread0 * 100, spread1 * 100])
	lines.insert(6, "")
	var g := FileAccess.open("res://docs/TUNING.md", FileAccess.WRITE)
	g.store_string("\n".join(lines) + "\n")
	g.close()
	print("TUNE DONE spread %.3f -> %.3f" % [spread0, spread1])
	get_tree().quit()


## 같은 코스트 안에서의 퍼짐 (코스트 평균과의 차이)
func _spread(wr: Dictionary) -> float:
	var mean := _cost_means(wr.keys(), wr)
	var s := 0.0
	for k in wr:
		s += pow(float(wr[k]) - float(mean[GameData.cost_of[k]]), 2)
	return sqrt(s / maxf(1.0, wr.size()))


func _cost_means(ids: Array, wr: Dictionary) -> Dictionary:
	var sum := {}
	var cnt := {}
	for aid in ids:
		var c: int = GameData.cost_of[aid]
		sum[c] = float(sum.get(c, 0.0)) + float(wr[aid])
		cnt[c] = int(cnt.get(c, 0)) + 1
	var out := {}
	for c in sum:
		out[c] = sum[c] / cnt[c]
	return out


## 무작위 팀 전투 n번 → 사도별 (든 팀이 이긴 수 / 나온 수)
func _measure(ids: Array, n: int, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var by_cost := {}
	for aid in ids:
		if not by_cost.has(GameData.cost_of[aid]):
			by_cost[GameData.cost_of[aid]] = []
		by_cost[GameData.cost_of[aid]].append(aid)
	var win := {}
	var seen := {}
	for aid in ids:
		win[aid] = 0.0
		seen[aid] = 0.0
	for k in n:
		var level := rng.randi_range(4, 8)
		var teams := [_team(rng, by_cost, level), _team(rng, by_cost, level)]
		var res := BattleSim.new(teams[0]["army"], teams[1]["army"], rng.randi()).run()
		var w := int(res["winner"])
		for side in [0, 1]:
			for aid in teams[side]["aids"]:
				seen[aid] += 1.0
				if w == side:
					win[aid] += 1.0
				elif w == -1:
					win[aid] += 0.5
	var out := {}
	for aid in ids:
		out[aid] = win[aid] / maxf(1.0, seen[aid])
	return out


## 레벨에 맞는 코스트 분포로 5명 (같은 사도 없이), 열에 맞게 배치
func _team(rng: RandomNumberGenerator, by_cost: Dictionary, level: int) -> Dictionary:
	var odds: Array = GameData.balance["shop_odds"][clampi(level, 1, 9) - 1]
	var aids := []
	var guard := 0
	while aids.size() < 5 and guard < 100:
		guard += 1
		var r := rng.randf() * 100.0
		var c := 1
		var acc := 0.0
		for i in odds.size():
			acc += float(odds[i])
			if r < acc:
				c = i + 1
				break
		var pool: Array = by_cost.get(c, [])
		if pool.is_empty():
			continue
		var aid: String = pool[rng.randi_range(0, pool.size() - 1)]
		if not aids.has(aid):
			aids.append(aid)
	var army := []
	var used := {}
	for aid in aids:
		var rk: String = GameData.apostle(aid).get("row", "mid")
		var row: int = {"front": 0, "mid": 1, "back": 2}.get(rk, rng.randi_range(0, 2))
		for slot in [1, 0, 2]:
			if not used.has("%d,%d" % [row, slot]):
				used["%d,%d" % [row, slot]] = true
				var opts := GameData.personality_options(aid)
				army.append({"aid": aid, "star": 1 if rng.randf() < 0.6 else 2, "row": row, "slot": slot, "arts": [], "pers": opts[0] if not opts.is_empty() else ""})
				break
	return {"aids": aids, "army": army}
