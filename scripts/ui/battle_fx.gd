class_name BattleFx
extends Control
## 전투 이펙트 (그리기만 함 — 전투 결과와 무관). 효과 목록을 매 프레임 그린다.
##   proj  : 원거리 탄환 (from → to, 꼬리)
##   ring  : 퍼지는 고리 (타격·회복·보호막·스킬)
##   slash : 근접 베기 (호 두 개)
##   spark : 사방으로 튀는 선 (치명타·처치)
##   glow  : 바닥에 깔리는 원 (스킬 시전)

var _list: Array = []
var speed := 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func add(kind: String, from: Vector2, to: Vector2, color: Color, dur: float = 0.3, r: float = 40.0) -> void:
	_list.append({"k": kind, "a": from, "b": to, "c": color, "d": dur, "t": 0.0, "r": r, "rot": randf() * TAU})
	queue_redraw()


func clear_all() -> void:
	_list.clear()
	queue_redraw()


func _process(delta: float) -> void:
	if _list.is_empty():
		return
	var keep := []
	for e in _list:
		e["t"] += delta * speed
		if e["t"] < e["d"]:
			keep.append(e)
	_list = keep
	queue_redraw()


func _draw() -> void:
	for e in _list:
		var p: float = e["t"] / e["d"]
		var c: Color = e["c"]
		match e["k"]:
			"proj":
				var pos: Vector2 = (e["a"] as Vector2).lerp(e["b"], p)
				var tail: Vector2 = (e["a"] as Vector2).lerp(e["b"], maxf(0.0, p - 0.25))
				draw_line(tail, pos, Color(c, 0.55), 6.0, true)
				draw_circle(pos, 9.0, Color(c, 0.9))
				draw_circle(pos, 4.5, Color(1, 1, 1, 0.95))
			"ring":
				var rad: float = e["r"] * (0.35 + 0.65 * p)
				draw_arc(e["a"], rad, 0, TAU, 40, Color(c, 1.0 - p), 5.0 * (1.0 - p) + 1.5, true)
			"slash":
				var rot: float = e["rot"]
				var rad: float = e["r"]
				var span := PI * 0.9
				var start := rot - span / 2.0 + span * p * 0.4
				draw_arc(e["a"], rad, start, start + span * minf(1.0, p * 2.5), 18, Color(c, 1.0 - p), 6.0, true)
				draw_arc(e["a"], rad * 0.7, start + 0.2, start + 0.2 + span * minf(1.0, p * 2.5), 18, Color(1, 1, 1, 0.8 * (1.0 - p)), 3.0, true)
			"spark":
				for i in 8:
					var ang: float = e["rot"] + i * TAU / 8.0
					var d := Vector2.from_angle(ang)
					var r0: float = e["r"] * (0.2 + 0.6 * p)
					var r1: float = r0 + e["r"] * 0.35 * (1.0 - p)
					draw_line(e["a"] + d * r0, e["a"] + d * r1, Color(c, 1.0 - p), 3.0, true)
			"glow":
				var rad: float = e["r"] * (0.8 + 0.3 * sin(p * PI))
				draw_set_transform(e["a"], 0.0, Vector2(1.0, 0.35))
				draw_circle(Vector2.ZERO, rad, Color(c, 0.35 * sin(p * PI)))
				draw_arc(Vector2.ZERO, rad, 0, TAU, 40, Color(c, 0.8 * sin(p * PI)), 3.0, true)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
