extends Control
## 시작 화면 겸 자동 업데이트. APK 에 들어가는 유일한 게임 스크립트이므로 게임 코드(class_name)를 직접 참조하지 않는다.
##
## 1. APK 에 들어 있는 기본 묶음(res://packs)을 user://packs 로 복사 (처음 실행 또는 APK 가 더 새것일 때)
## 2. GitHub 릴리스의 manifest.json 을 확인해 바뀐 묶음만 받기
## 3. 묶음을 불러온 뒤 게임 시작
##
## PC(Windows/Linux): 시작 화면(실행 파일) 자체가 바뀐 경우 새 실행 파일을 받아 바꿔 끼우고 다시 실행한다.
##
## 명령줄 옵션(테스트용): -- --manifest=<주소>  /  -- --offline  /  -- --no-self-update

const BASE_VERSION := 4   # 이 시작 화면(APK/실행 파일) 버전. 묶음이 더 높은 값을 요구하면 새로 설치 안내.
const RELEASES_PAGE := "https://github.com/RoastedBeer24/CheektoChess/releases/latest"
const MANIFEST_URL := "https://github.com/RoastedBeer24/CheektoChess/releases/latest/download/manifest.json"
const PACK_DIR := "user://packs/"
const INSTALLED := "user://packs/installed.json"
const EMBEDDED := "res://packs/index.json"
const REQUIRED := ["core", "art"]   # 게임에 꼭 필요한 묶음. 나머지(모션·보이스)는 못 받아도 게임은 시작
const PACK_LABEL := {"core": "게임 코드", "art": "그림", "motion": "전투 모션", "voice": "보이스"}
const CHUNK := 4 * 1048576           # 큰 묶음은 4MB 조각으로 받는다 (이어받기)
const STALL := 20.0                  # 이 시간(초) 동안 받은 양이 늘지 않으면 실패

var _status: Label
var _detail: Label
var _bar: ProgressBar
var _http: HTTPRequest
var _restarting := false
var _skip_extras := false
var _skip_btn: Button
const SELF_UPDATE_LOG := "user://self_update.json"


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
	_skip_btn = Button.new()
	_skip_btn.text = "  지금은 건너뛰기 (다음 실행 때 이어서)  "
	_skip_btn.add_theme_font_size_override("font_size", 24)
	_skip_btn.visible = false
	_skip_btn.pressed.connect(func(): _skip_extras = true)
	v.add_child(_skip_btn)
	_http = HTTPRequest.new()
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
	_cleanup_old_exe()
	var embedded := _read_json(EMBEDDED)
	# 에디터/개발 실행: 묶음 없이 프로젝트 파일을 그대로 사용
	if OS.has_feature("editor") or (embedded.is_empty() and not FileAccess.file_exists(INSTALLED)):
		_launch()
		return
	DirAccess.make_dir_recursive_absolute(PACK_DIR)
	var inst := _read_json(INSTALLED)
	if inst.is_empty():
		inst = {"build": 0, "packs": {}}
	# 1) APK 에 든 묶음이 더 새것이면 복사 (이미 받아 둔 모션·보이스 묶음은 그대로 둔다)
	if int(embedded.get("build", 0)) > int(inst.get("build", 0)):
		await _say("게임 파일 준비 중...")
		var ok := true
		for name in embedded["packs"]:
			var meta: Dictionary = embedded["packs"][name]
			ok = ok and _copy("res://packs/" + meta["file"], PACK_DIR + meta["file"])
		if ok:
			var packs: Dictionary = inst.get("packs", {}).duplicate()
			for name in embedded["packs"]:
				packs[name] = embedded["packs"][name]
			inst = {"build": int(embedded["build"]), "version": embedded.get("version", ""), "packs": packs}
			_write_json(INSTALLED, inst)
	# 2) 온라인 업데이트
	if _arg("offline") == "":
		inst = await _update_online(inst)
		if _restarting:
			return
	# 3) 묶음 불러오기
	await _say("불러오는 중...")
	for name in REQUIRED:
		var meta: Dictionary = inst.get("packs", {}).get(name, {})
		if meta.is_empty():
			continue
		if not ProjectSettings.load_resource_pack(PACK_DIR + meta["file"], true):
			await _say("게임 파일을 불러오지 못했습니다", "%s 묶음이 손상되었을 수 있습니다. 앱 데이터를 지우고 다시 실행해 주세요." % name)
			return
	_launch()


## 받아야 할 묶음 이름 (게임 필수 묶음 먼저)
func _needed(remote: Dictionary, inst: Dictionary) -> Array:
	var out: Array = []
	var names: Array = remote["packs"].keys()
	names.sort_custom(func(x, y): return (REQUIRED.find(x) if x in REQUIRED else 99) < (REQUIRED.find(y) if y in REQUIRED else 99))
	for name in names:
		var meta: Dictionary = remote["packs"][name]
		var old: Dictionary = inst.get("packs", {}).get(name, {})
		var have := not old.is_empty() and FileAccess.file_exists(PACK_DIR + String(old.get("file", "")))
		if have and old.get("sha256", "") == meta["sha256"]:
			continue
		# 서버가 설치된 것보다 옛 빌드면(새 APK 를 먼저 설치한 경우) 없는 묶음만 받는다 — 되돌리지 않음
		if have and int(remote.get("build", 0)) < int(inst.get("build", 0)):
			continue
		out.append(name)
	return out


func _update_online(inst: Dictionary) -> Dictionary:
	await _say("업데이트 확인 중...")
	print("[boot] 설치된 build=%d, 업데이트 확인" % int(inst.get("build", 0)))
	var url := _arg("manifest")
	if url == "":
		url = MANIFEST_URL
	var res := await _http_get(url, "", 10.0)
	if res.is_empty():
		await _say("업데이트 서버에 연결하지 못했습니다", "설치된 버전으로 시작합니다.")
		await get_tree().create_timer(0.6).timeout
		return inst
	var remote = JSON.parse_string(res["body"].get_string_from_utf8())
	if typeof(remote) != TYPE_DICTIONARY or not remote.has("packs"):
		return inst
	var base_url := url.get_base_dir() + "/"
	# PC: 실행 파일이 더 새것이면 먼저 바꿔 끼운다 (성공하면 새 실행 파일로 다시 시작)
	var desk: Dictionary = remote.get("desktop", {}).get(_desktop_key(), {})
	# 같은 버전으로 이미 한 번 바꿨는데도 여전히 낮으면(잘못된 배포) 다시 시도하지 않는다 — 무한 재시작 방지
	var tried := int(_read_json(SELF_UPDATE_LOG).get("base", 0))
	if not desk.is_empty() and int(desk.get("base", 0)) > BASE_VERSION and int(desk["base"]) != tried and _arg("no-self-update") == "":
		if await _self_update(base_url, desk):
			_restarting = true
			return inst
	# 안드로이드: 새 APK 가 나왔으면 알림 (받을지는 사용자가 고름)
	var apk: Dictionary = remote.get("android", {})
	if OS.get_name() == "Android" and int(apk.get("base", 0)) > BASE_VERSION:
		await _ask_apk(base_url + String(apk.get("file", "")), float(apk.get("size", 0)), int(remote.get("min_base", 1)) > BASE_VERSION)
	if int(remote.get("min_base", 1)) > BASE_VERSION:
		if int(remote.get("build", 0)) > int(inst.get("build", 0)):
			if OS.has_feature("pc"):
				await _say("새 버전을 받아야 합니다", "자동으로 바꾸지 못했습니다. 열리는 페이지에서 새 버전을 받아 주세요. 설치된 버전으로 시작합니다.")
				OS.shell_open(RELEASES_PAGE)
			else:
				await _say("새 APK가 필요합니다", "이번 업데이트는 앱을 새로 설치해야 합니다. 설치된 버전으로 시작합니다.")
			await get_tree().create_timer(2.5).timeout
		return inst
	var needed := _needed(remote, inst)
	var newer := int(remote.get("build", 0)) >= int(inst.get("build", 0))
	if needed.is_empty():
		if int(remote.get("build", 0)) > int(inst.get("build", 0)):
			inst["build"] = int(remote["build"])
			inst["version"] = remote.get("version", "")
			_write_json(INSTALLED, inst)
		return inst
	var total := 0.0
	for name in needed:
		total += float(remote["packs"][name].get("size", 0))
	# 필수 묶음(core·art): 모두 받은 뒤에 한꺼번에 바꾼다 (반만 바뀐 상태 방지). 실패하면 이번에는 설치된 버전으로.
	var req_new: Array = []
	for name in needed:
		if not name in REQUIRED:
			continue
		var meta: Dictionary = remote["packs"][name]
		if not await _fetch_pack(base_url, name, meta, needed.find(name) + 1, needed.size(), total):
			await _say("업데이트를 받지 못했습니다", "인터넷 연결을 확인해 주세요. 설치된 버전으로 시작하고, 다음 실행 때 이어서 받습니다.")
			await get_tree().create_timer(1.5).timeout
			return inst
		req_new.append(name)
	var packs: Dictionary = inst.get("packs", {}).duplicate()
	for name in req_new:
		var meta: Dictionary = remote["packs"][name]
		DirAccess.rename_absolute(_part_path(meta), PACK_DIR + String(meta["file"]))
		packs[name] = meta
		print("[boot] %s 받음 (%d bytes)" % [name, int(meta.get("size", 0))])
	if newer:
		inst = {"build": int(remote["build"]), "version": remote.get("version", ""), "packs": packs}
	else:
		inst["packs"] = packs
	_write_json(INSTALLED, inst)
	# 추가 묶음(모션·보이스): 하나씩 받아 바로 반영. 실패하거나 건너뛰면 게임은 시작하고 다음 실행 때 이어서 받는다.
	_skip_extras = false
	for name in needed:
		if name in REQUIRED:
			continue
		var meta: Dictionary = remote["packs"][name]
		_skip_btn.visible = true
		var ok := await _fetch_pack(base_url, name, meta, needed.find(name) + 1, needed.size(), total)
		_skip_btn.visible = false
		if not ok:
			if not _skip_extras:
				await _say("%s 묶음을 다 받지 못했습니다" % PACK_LABEL.get(name, name), "게임은 그대로 시작합니다. 다음 실행 때 받은 곳부터 이어서 받습니다.")
				await get_tree().create_timer(1.5).timeout
			break
		DirAccess.rename_absolute(_part_path(meta), PACK_DIR + String(meta["file"]))
		inst["packs"][name] = meta
		_write_json(INSTALLED, inst)
		print("[boot] %s 받음 (%d bytes)" % [name, int(meta.get("size", 0))])
	return inst


func _part_path(meta: Dictionary) -> String:
	return PACK_DIR + String(meta["file"]) + "." + String(meta["sha256"]).substr(0, 12) + ".part"


## 묶음 하나를 조각(CHUNK)으로 나눠 받는다. 받은 만큼은 .part 파일로 남아 다음에 이어서 받는다.
func _fetch_pack(base_url: String, name: String, meta: Dictionary, idx: int, count: int, total: float) -> bool:
	var size := int(meta.get("size", 0))
	var part := _part_path(meta)
	# 다른 버전의 받다 만 파일은 지운다
	for f in DirAccess.get_files_at(PACK_DIR):
		if f.begins_with(String(meta["file"]) + ".") and f.ends_with(".part") and PACK_DIR + f != part:
			DirAccess.remove_absolute(PACK_DIR + f)
	var have := 0
	if FileAccess.file_exists(part):
		var pf := FileAccess.open(part, FileAccess.READ)
		have = pf.get_length() if pf else 0
		pf = null
		if have > size:
			DirAccess.remove_absolute(part)
			have = 0
	var label: String = PACK_LABEL.get(name, name)
	var big := size > 15 * 1048576
	var started := Time.get_ticks_msec()
	var start_have := have
	while have < size:
		if _skip_extras and not name in REQUIRED:
			return false
		var end: int = mini(size, have + CHUNK) - 1
		var res := await _http_get(base_url + String(meta["file"]), "", 0.0, ["Range: bytes=%d-%d" % [have, end]],
			func(got: int):
				var done: int = have + got
				_bar.value = 100.0 * done / maxf(1.0, size)
				var secs: float = (Time.get_ticks_msec() - started) / 1000.0
				var speed: float = (done - start_have) / maxf(0.5, secs)
				var detail := "%s  %.1f / %.1f MB" % [label, done / 1048576.0, size / 1048576.0]
				if speed > 1024 and secs > 1.5:
					detail += "  ·  %.1f MB/s, 약 %d초 남음" % [speed / 1048576.0, int((size - done) / speed)]
				if big:
					detail += "\n용량이 큽니다 — 와이파이에서 받는 것을 권장합니다"
				_status.text = "업데이트 받는 중... (%d/%d)" % [idx, count]
				_detail.text = detail)
		if res.is_empty():
			return false
		var body: PackedByteArray = res["body"]
		var f: FileAccess
		if int(res["code"]) == 206 and have > 0:
			f = FileAccess.open(part, FileAccess.READ_WRITE)
			if f:
				f.seek_end()
		else:
			# 서버가 범위 요청을 무시하고 전체를 보냈거나 처음 조각
			f = FileAccess.open(part, FileAccess.WRITE)
			if int(res["code"]) == 200:
				have = 0
		if f == null:
			return false
		f.store_buffer(body)
		f = null
		have += body.size()
	if FileAccess.get_sha256(part) != meta["sha256"]:
		print("[boot] %s 확인값이 다름 — 처음부터 다시" % name)
		DirAccess.remove_absolute(part)
		return false
	return true


## 새 APK 알림: [받기] 를 누르면 브라우저로 APK 를 받는다. 필수가 아니면 [나중에] 로 계속.
func _ask_apk(apk_url: String, size: float, required: bool) -> void:
	await _say("새 버전의 앱(APK)이 있습니다", ("이번 업데이트는 새 앱이 필요합니다." if required else "시작 화면·업데이트 기능이 좋아졌습니다.") + " 받은 파일을 열어 덮어 설치하세요 (%.0f MB)." % (size / 1048576.0))
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 24)
	_detail.get_parent().add_child(h)
	var get_btn := Button.new()
	get_btn.text = "  받기  "
	get_btn.add_theme_font_size_override("font_size", 30)
	h.add_child(get_btn)
	var later := Button.new()
	later.text = "  나중에  "
	later.add_theme_font_size_override("font_size", 30)
	h.add_child(later)
	var chosen: Array = []
	get_btn.pressed.connect(func(): chosen.append(true))
	later.pressed.connect(func(): chosen.append(false))
	while chosen.is_empty():
		await get_tree().process_frame
	h.queue_free()
	if chosen[0]:
		OS.shell_open(apk_url)


# ─────────────── PC 실행 파일 자체 업데이트 ───────────────

func _desktop_key() -> String:
	if OS.get_name() == "Windows":
		return "windows"
	if OS.get_name() == "Linux":
		return "linux"
	return ""


## 받은 zip 에서 실행 파일을 꺼내 지금 실행 파일과 바꾼 뒤 다시 실행. 성공하면 true (곧 종료됨).
## 실행 중인 파일은 덮어쓸 수 없지만 이름은 바꿀 수 있으므로: 지금 것 → .old, 새 것 → 원래 이름.
func _self_update(base_url: String, desk: Dictionary) -> bool:
	var exe := OS.get_executable_path()
	var dir := exe.get_base_dir()
	var tmp_zip := dir.path_join("update.zip.download")
	print("[boot] 실행 파일 업데이트: base %d → %d" % [BASE_VERSION, int(desk["base"])])
	await _say("새 버전 받는 중...", "%.1f MB" % (float(desk.get("size", 0)) / 1048576.0))
	var got := await _http_get(base_url + String(desk["file"]), tmp_zip)
	if got.is_empty() or FileAccess.get_sha256(tmp_zip) != desk.get("sha256", ""):
		DirAccess.remove_absolute(tmp_zip)
		return await _self_update_failed("새 버전을 받지 못했습니다")
	var zr := ZIPReader.new()
	if zr.open(tmp_zip) != OK:
		return await _self_update_failed("받은 파일을 열 수 없습니다")
	var inner: String = desk.get("exe", "")
	var data := zr.read_file(inner)
	zr.close()
	DirAccess.remove_absolute(tmp_zip)
	if data.is_empty():
		return await _self_update_failed("받은 파일에 실행 파일이 없습니다")
	var new_path := exe + ".new"
	var f := FileAccess.open(new_path, FileAccess.WRITE)
	if f == null:
		# 쓰기 권한이 없는 폴더(예: Program Files)
		return await _self_update_failed("이 폴더에는 새 버전을 저장할 수 없습니다")
	f.store_buffer(data)
	f.close()
	var old_path := exe + ".old"
	if FileAccess.file_exists(old_path):
		DirAccess.remove_absolute(old_path)
	if DirAccess.rename_absolute(exe, old_path) != OK:
		DirAccess.remove_absolute(new_path)
		return await _self_update_failed("실행 파일을 바꾸지 못했습니다")
	if DirAccess.rename_absolute(new_path, exe) != OK:
		DirAccess.rename_absolute(old_path, exe)
		return await _self_update_failed("실행 파일을 바꾸지 못했습니다")
	if OS.get_name() != "Windows":
		OS.execute("chmod", ["+x", exe])
	_write_json(SELF_UPDATE_LOG, {"base": int(desk["base"]), "from": BASE_VERSION})
	await _say("새 버전으로 다시 시작합니다...")
	await get_tree().create_timer(0.4).timeout
	var args := Array(OS.get_cmdline_args())
	var user_args := OS.get_cmdline_user_args()
	if not user_args.is_empty():
		args.append("--")
		args.append_array(user_args)
	OS.create_process(exe, PackedStringArray(args))
	get_tree().quit()
	return true


func _self_update_failed(why: String) -> bool:
	print("[boot] 실행 파일 업데이트 실패: " + why)
	await _say(why, "열리는 페이지에서 새 버전을 직접 받아 주세요. 지금 버전으로 계속합니다.")
	OS.shell_open(RELEASES_PAGE)
	await get_tree().create_timer(2.5).timeout
	return false


## 지난번 업데이트에서 남은 이전 실행 파일 지우기
func _cleanup_old_exe() -> void:
	if not OS.has_feature("pc") or OS.has_feature("editor"):
		return
	var old := OS.get_executable_path() + ".old"
	if FileAccess.file_exists(old):
		DirAccess.remove_absolute(old)


## GET 요청. download_to 가 있으면 파일로 저장. 실패하면 {}.
## limit > 0: 전체 시간 제한(초). 그 밖에는 STALL 초 동안 받은 양이 늘지 않을 때만 실패로 본다 (느린 연결에서도 큰 파일 OK).
## on_progress(받은 바이트) 가 있으면 진행 중에 불린다.
func _http_get(url: String, download_to: String, limit: float = 0.0, headers: Array = [], on_progress = null) -> Dictionary:
	_http.download_file = download_to
	_http.timeout = limit
	if on_progress == null:
		_bar.value = 0
	if _http.request(url, PackedStringArray(headers)) != OK:
		return {}
	var result: Array = []
	_http.request_completed.connect(func(r, code, _h, body): result.append([r, code, body]), CONNECT_ONE_SHOT)
	var last := -1
	var last_t := Time.get_ticks_msec()
	while result.is_empty():
		var got := _http.get_downloaded_bytes()
		if got != last:
			last = got
			last_t = Time.get_ticks_msec()
			if on_progress != null:
				on_progress.call(got)
			else:
				var total := _http.get_body_size()
				if total > 0:
					_bar.value = 100.0 * got / total
		elif Time.get_ticks_msec() - last_t > STALL * 1000.0:
			_http.cancel_request()
			print("[boot] 받기 멈춤 (%d초 동안 진행 없음): %s" % [int(STALL), url])
			return {}
		if _skip_extras and on_progress != null:
			_http.cancel_request()
			return {}
		await get_tree().process_frame
	if on_progress == null:
		_bar.value = 100
	var code := int(result[0][1])
	if result[0][0] != HTTPRequest.RESULT_SUCCESS or (code != 200 and code != 206):
		print("[boot] 받기 실패 (result=%d, code=%d): %s" % [result[0][0], code, url])
		return {}
	return {"body": result[0][2], "code": code}


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
