class_name BurstFx
extends Control
## 합성 연출: 칸 위에서 퍼지는 빛 고리 + 빛살 + ★ 글자. ★3 은 더 크고 금빛.

var star := 2
var t := 0.0
var dur := 0.9
var col := Color("ffe066")


func _init(s: int = 2) -> void:
	star = s
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	dur = 1.3 if star >= 3 else 0.9
	col = Color("ffd23f") if star >= 3 else Color("bfe8ff")


func _ready() -> void:
	var l := UI.outlined("★".repeat(star) + (" 완성!" if star >= 3 else ""), 40 if star >= 3 else 30, col.lightened(0.2), 8)
	l.size = Vector2(300, 60)
	l.position = size / 2.0 - Vector2(150, 30)
	l.pivot_offset = Vector2(150, 30)
	l.scale = Vector2(0.4, 0.4)
	add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector2(1.15, 1.15), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 60.0, dur)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(dur - 0.35)
	tw.chain().tween_callback(queue_free)


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	var k := clampf(t / dur, 0.0, 1.0)
	var c := size / 2.0
	var r0 := minf(size.x, size.y) * 0.5
	var a := 1.0 - k
	# 바닥 빛
	draw_circle(c, r0 * (0.6 + 0.6 * k), Color(col, 0.22 * a))
	# 퍼지는 고리 2개
	for i in 2:
		var kk := clampf(k * 1.3 - i * 0.25, 0.0, 1.0)
		if kk > 0.0:
			draw_arc(c, r0 * (0.3 + 1.2 * kk), 0, TAU, 48, Color(col, (1.0 - kk) * 0.9), 6.0 * (1.0 - kk) + 1.0)
	# 빛살
	var n := 12 if star >= 3 else 8
	for i in n:
		var ang := TAU * i / n + k * 0.6
		var d := Vector2(cos(ang), sin(ang))
		draw_line(c + d * r0 * (0.35 + 0.5 * k), c + d * r0 * (0.6 + 0.9 * k), Color(col.lightened(0.3), a * 0.9), 3.0)
