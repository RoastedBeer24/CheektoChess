class_name DesktopWindow
extends Node
## PC 전용: F11·Alt+Enter 전체 화면 전환, 창 크기·위치·전체 화면 기억, 최소 창 크기.

const SAVE := "user://window.json"
const MIN_SIZE := Vector2i(1024, 576)

var _save_t := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var w := get_window()
	w.min_size = MIN_SIZE
	_restore()
	w.size_changed.connect(func(): _save_t = 0.6)


func _restore() -> void:
	if not FileAccess.file_exists(SAVE):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	if typeof(d) != TYPE_DICTIONARY:
		return
	var w := get_window()
	if d.get("fullscreen", false):
		w.mode = Window.MODE_FULLSCREEN
		return
	var size := Vector2i(int(d.get("w", 0)), int(d.get("h", 0)))
	var pos := Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))
	if size.x < MIN_SIZE.x or size.y < MIN_SIZE.y:
		return
	# 저장된 위치가 지금 연결된 화면 안에 있을 때만 (모니터를 뗀 경우 대비)
	var on_screen := false
	for i in DisplayServer.get_screen_count():
		var r := Rect2i(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i))
		if r.has_point(pos + Vector2i(40, 40)):
			on_screen = true
	w.size = size
	if on_screen:
		w.position = pos
	if d.get("maximized", false):
		w.mode = Window.MODE_MAXIMIZED


func _process(delta: float) -> void:
	if _save_t > 0.0:
		_save_t -= delta
		if _save_t <= 0.0:
			_store()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_store()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


func toggle_fullscreen() -> void:
	var w := get_window()
	w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN or w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN else Window.MODE_FULLSCREEN
	_save_t = 0.3


func _store() -> void:
	var w := get_window()
	var d := {"fullscreen": w.mode == Window.MODE_FULLSCREEN or w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN, "maximized": w.mode == Window.MODE_MAXIMIZED}
	if w.mode == Window.MODE_WINDOWED:
		d.merge({"w": w.size.x, "h": w.size.y, "x": w.position.x, "y": w.position.y})
	else:
		var old = JSON.parse_string(FileAccess.get_file_as_string(SAVE)) if FileAccess.file_exists(SAVE) else {}
		if typeof(old) == TYPE_DICTIONARY:
			for k in ["w", "h", "x", "y"]:
				if old.has(k):
					d[k] = old[k]
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
