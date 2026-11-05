class_name App
extends RefCounted
## 게임 시작점. boot 화면이 업데이트 묶음을 불러온 뒤 App.start() 를 호출한다.
## 네트워크(App.net)와 세션(App.session)은 모든 기기에서 같은 경로(/root/Net, /root/Session)에 둔다 (RPC 경로 일치).

## 묶음 폴더 (테스트에서는 환경 변수 CHEEKTO_PACK_DIR 로 바꿀 수 있음)
static var PACK_DIR: String = OS.get_environment("CHEEKTO_PACK_DIR") if OS.get_environment("CHEEKTO_PACK_DIR") != "" else "user://packs/"
static var INSTALLED: String = PACK_DIR + "installed.json"

static var net: NetNode
static var session: SessionNode
static var build := 0              # 콘텐츠 빌드 번호 (0 = 개발 실행)
static var version := "dev"
static var started := false


static func start(root: Node) -> void:
	if started:
		return
	started = true
	_load_extra_packs()
	GameData.load_all()
	var v := _read_json("res://version.json")
	build = int(v.get("build", 0))
	if OS.get_environment("CHEEKTO_BUILD") != "":
		build = int(OS.get_environment("CHEEKTO_BUILD"))   # 테스트용
	version = str(v.get("version", "dev"))
	net = NetNode.new()
	net.name = "Net"
	session = SessionNode.new()
	session.name = "Session"
	# 다른 노드가 준비 중일 수 있으므로 지연 추가 (호출한 쪽은 한 프레임 기다린 뒤 사용)
	root.add_child.call_deferred(net)
	root.add_child.call_deferred(session)
	var tips := Tips.new()
	tips.name = "Tips"
	root.add_child.call_deferred(tips)
	var voice := Voice.new()
	voice.name = "Voice"
	root.add_child.call_deferred(voice)
	# PC: 전체 화면 전환(F11), 창 크기·위치 기억
	if OS.has_feature("pc") and DisplayServer.get_name() != "headless" and not OS.has_feature("editor"):
		var dw := DesktopWindow.new()
		dw.name = "DesktopWindow"
		root.add_child.call_deferred(dw)


## 시작 화면(boot)이 불러오지 않는 추가 묶음(motion 등)을 불러온다.
## 옛 APK·실행 파일의 시작 화면은 core/art 만 불러오므로 여기서 처리한다.
static func _load_extra_packs() -> void:
	var inst := _read_json(INSTALLED)
	for name in inst.get("packs", {}):
		if name == "core" or name == "art":
			continue
		var path: String = PACK_DIR + String(inst["packs"][name].get("file", ""))
		if FileAccess.file_exists(path):
			if ProjectSettings.load_resource_pack(path, true):
				print("[app] 추가 묶음 불러옴: %s (모션 사도 %d명)" % [name, DirAccess.get_directories_at("res://assets/motions").size()])


## 설치된 묶음 정보 {build, packs: {이름: {file, sha256, size}}}
static func installed() -> Dictionary:
	return _read_json(INSTALLED)


static func save_installed(d: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(PACK_DIR)
	var f := FileAccess.open(INSTALLED, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, " "))


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if typeof(d) == TYPE_DICTIONARY else {}


## 앱 재시작 (데스크톱은 자동, 안드로이드는 사용자가 다시 실행)
static func restart(tree: SceneTree) -> void:
	if not OS.has_feature("android"):
		OS.set_restart_on_exit(true)
	tree.quit()
