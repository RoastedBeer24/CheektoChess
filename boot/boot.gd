extends Control
## 시작 화면 겸 자동 업데이트. APK 에 들어가는 유일한 게임 스크립트이므로 게임 코드(class_name)를 직접 참조하지 않는다.
##
## 1. APK 에 들어 있는 기본 묶음(res://packs)을 user://packs 로 복사 (처음 실행 또는 APK 가 더 새것일 때)
## 2. GitHub 릴리스의 manifest.json 을 확인해 바뀐 묶음만 받기
## 3. 묶음을 불러온 뒤 게임 시작
##
## 명령줄 옵션(테스트용): -- --manifest=<주소>  /  -- --offline

const BASE_VERSION := 1   # 이 시작 화면(APK) 버전. 묶음이 더 높은 값을 요구하면 APK 재설치 안내.
const MANIFEST_URL := "https://github.com/RoastedBeer24/CheektoChess/releases/latest/download/manifest.json"
const PACK_DIR := "user://packs/"
const INSTALLED := "user://packs/installed.json"
const EMBEDDED := "res://packs/index.json"

var _status: Label
var _detail: Label
var _bar: ProgressBar
var _http: HTTPRequest


func _ready() -> void:
	_build_ui()
	_run()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("1b1d29")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.custom_minimum_size = Vector2(900, 0)
	v.position = Vector2(-450, -120)
	v.add_theme_constant_override("separation", 18)
	add_child(v)
	var title := Label.new()
	title.text = "볼토체스"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 80)
	title.add_theme_color_override("font_color", Color("ffc857"))
	v.add_child(title)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 30)
	v.add_child(_status)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 26)
	_bar.show_percentage = false
	v.add_child(_bar)
	_detail = Label.new()
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_theme_font_size_override("font_size", 22)
	_detail.add_theme_color_override("font_color", Color("a9adc1"))
	v.add_child(_detail)
	_http = HTTPRequest.new()
	_http.timeout = 8.0
	_http.use_threads = true
	add_child(_http)


func _say(text: String, detail: String = "") -> void:
	_status.text = text
	_detail.text = detail
	await get_tree().process_frame


func _arg(name: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a == "--" + name:
			return "1"
		if a.begins_with("--" + name + "="):
			return a.split("=", true, 1)[1]
	return ""


func _run() -> void:
	var embedded := _read_json(EMBEDDED)
	# 에디터/개발 실행: 묶음 없이 프로젝트 파일을 그대로 사용
	if OS.has_feature("editor") or (embedded.is_empty() and not FileAccess.file_exists(INSTALLED)):
		_launch()
		return
	DirAccess.make_dir_recursive_absolute(PACK_DIR)
	var inst := _read_json(INSTALLED)
	if inst.is_empty():
		inst = {"build": 0, "packs": {}}
	# 1) APK 에 든 묶음이 더 새것이면 복사
	if int(embedded.get("build", 0)) > int(inst.get("build", 0)):
		await _say("게임 파일 준비 중...")
		var ok := true
		for name in embedded["packs"]:
			var meta: Dictionary = embedded["packs"][name]
			ok = ok and _copy("res://packs/" + meta["file"], PACK_DIR + meta["file"])
		if ok:
			inst = {"build": int(embedded["build"]), "version": embedded.get("version", ""), "packs": embedded["packs"]}
			_write_json(INSTALLED, inst)
	# 2) 온라인 업데이트
	if _arg("offline") == "":
		inst = await _update_online(inst)
	# 3) 묶음 불러오기
	await _say("불러오는 중...")
	for name in ["core", "art"]:
		var meta: Dictionary = inst.get("packs", {}).get(name, {})
		if meta.is_empty():
			continue
		if not ProjectSettings.load_resource_pack(PACK_DIR + meta["file"], true):
			await _say("게임 파일을 불러오지 못했습니다", "%s 묶음이 손상되었을 수 있습니다. 앱 데이터를 지우고 다시 실행해 주세요." % name)
			return
	_launch()


func _update_online(inst: Dictionary) -> Dictionary:
	await _say("업데이트 확인 중...")
	print("[boot] 설치된 build=%d, 업데이트 확인" % int(inst.get("build", 0)))
	var url := _arg("manifest")
	if url == "":
		url = MANIFEST_URL
	var res := await _http_get(url, "")
	if res.is_empty():
		await _say("업데이트 서버에 연결하지 못했습니다", "설치된 버전으로 시작합니다.")
		await get_tree().create_timer(0.6).timeout
		return inst
	var remote = JSON.parse_string(res["body"].get_string_from_utf8())
	if typeof(remote) != TYPE_DICTIONARY or not remote.has("packs"):
		return inst
	if int(remote.get("build", 0)) <= int(inst.get("build", 0)):
		return inst
	if int(remote.get("min_base", 1)) > BASE_VERSION:
		await _say("새 APK가 필요합니다", "이번 업데이트는 앱을 새로 설치해야 합니다. 설치된 버전으로 시작합니다.")
		await get_tree().create_timer(2.5).timeout
		return inst
	var base_url := url.get_base_dir() + "/"
	var new_packs: Dictionary = {}
	var names: Array = remote["packs"].keys()
	for i in names.size():
		var name: String = names[i]
		var meta: Dictionary = remote["packs"][name]
		var old: Dictionary = inst.get("packs", {}).get(name, {})
		if old.get("sha256", "") == meta["sha256"] and FileAccess.file_exists(PACK_DIR + old.get("file", "")):
			new_packs[name] = old
			continue
		await _say("업데이트 받는 중... (%d/%d)" % [i + 1, names.size()], "%s  %.1f MB" % [name, float(meta.get("size", 0)) / 1048576.0])
		var tmp: String = PACK_DIR + meta["file"] + ".download"
		var got := await _http_get(base_url + meta["file"], tmp)
		if got.is_empty() or FileAccess.get_sha256(tmp) != meta["sha256"]:
			await _say("업데이트를 받지 못했습니다", "설치된 버전으로 시작합니다.")
			await get_tree().create_timer(1.0).timeout
			return inst
		DirAccess.rename_absolute(tmp, PACK_DIR + meta["file"])
		print("[boot] %s 받음 (%d bytes)" % [name, int(meta.get("size", 0))])
		new_packs[name] = meta
	inst = {"build": int(remote["build"]), "version": remote.get("version", ""), "packs": new_packs}
	_write_json(INSTALLED, inst)
	return inst


## GET 요청. download_to 가 있으면 파일로 저장. 실패하면 {}.
func _http_get(url: String, download_to: String) -> Dictionary:
	_http.download_file = download_to
	_bar.value = 0
	if _http.request(url) != OK:
		return {}
	var result: Array = []
	_http.request_completed.connect(func(r, code, _h, body): result.append([r, code, body]), CONNECT_ONE_SHOT)
	while result.is_empty():
		var total := _http.get_body_size()
		if total > 0:
			_bar.value = 100.0 * _http.get_downloaded_bytes() / total
		await get_tree().process_frame
	_bar.value = 100
	if result[0][0] != HTTPRequest.RESULT_SUCCESS or result[0][1] != 200:
		return {}
	return {"body": result[0][2]}


func _copy(src: String, dst: String) -> bool:
	var data := FileAccess.get_file_as_bytes(src)
	if data.is_empty():
		return false
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(data)
	return true


func _launch() -> void:
	var app = load("res://scripts/app.gd")
	if app == null:
		await _say("게임 파일이 없습니다", "앱을 다시 설치해 주세요.")
		return
	app.start(get_tree().root)
	await get_tree().process_frame
	print("[boot] 게임 시작: build=%d version=%s" % [app.build, app.version])
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if typeof(d) == TYPE_DICTIONARY else {}


func _write_json(path: String, d: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, " "))
