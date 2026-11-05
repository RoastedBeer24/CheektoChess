extends Node
## 무작위 입력 시험: 게임 중 화면 아무 곳이나 누르고·끌고·꾹 누르기를 오래 반복해 스크립트 오류를 찾는다.
##   CHEEKTO_UI_SCALE=1.3 godot --path . --resolution 2340x1080 res://tests/monkey.tscn -- [초=120] [seed=1]
## 끝나면 MONKEY DONE. 오류는 Godot 로그의 SCRIPT ERROR 로 확인.

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	App.start(get_tree().root)
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var secs := float(args[0]) if args.size() > 0 else 120.0
	rng.seed = int(args[1]) if args.size() > 1 else 1
	Settings._data["vibrate"] = false
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(10)
	var t0 := Time.get_ticks_msec()
	var actions := 0
	var restarts := 0
	while (Time.get_ticks_msec() - t0) / 1000.0 < secs:
		if not App.session.in_game():
			Settings._data["rules"] = {"augments": rng.randf() < 0.5}
			App.session.start_offline(7)
			restarts += 1
			await _wait(10)
		# 게임을 빨리 진행 (준비 시간 줄이기)
		if App.session.game and App.session.game.phase_left > 6.0 and rng.randf() < 0.02:
			App.session.game.phase_left = 2.0
		var vp: Vector2 = get_viewport().get_visible_rect().size
		var xf: Transform2D = get_viewport().get_final_transform()
		var a: Vector2 = xf * Vector2(rng.randf() * vp.x, rng.randf() * vp.y)
		var r := rng.randf()
		if r < 0.45:
			await _tap(a, 0.0)
		elif r < 0.6:
			await _tap(a, rng.randf_range(0.4, 0.8))
		else:
			var b: Vector2 = xf * Vector2(rng.randf() * vp.x, rng.randf() * vp.y)
			await _drag(a, b, rng.randf() < 0.4)
		actions += 1
		# 나가기 확인창이 떠 있으면 가끔만 나간다 (대부분 계속하기)
		await _wait(rng.randi_range(1, 6))
	print("MONKEY DONE actions=%d restarts=%d" % [actions, restarts])
	get_tree().quit()


func _tap(pos: Vector2, hold: float) -> void:
	_touch(pos, true)
	if hold > 0.0:
		await get_tree().create_timer(hold).timeout
	else:
		await _wait(2)
	_touch(pos, false)


func _drag(a: Vector2, b: Vector2, hold: bool) -> void:
	_touch(a, true)
	await _wait(2)
	if hold:
		await get_tree().create_timer(0.5).timeout
	for i in 8:
		var e := InputEventScreenDrag.new()
		e.index = 0
		e.position = a.lerp(b, (i + 1) / 8.0)
		Input.parse_input_event(e)
		await _wait(1)
	_touch(b, false)


func _touch(pos: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = pos
	e.pressed = down
	Input.parse_input_event(e)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
