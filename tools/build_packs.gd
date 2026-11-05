extends SceneTree
## 업데이트 묶음(.pck) 만들기.
##   godot --headless --path . -s res://tools/build_packs.gd -- <출력 폴더> <빌드 번호> [min_base]
## 결과: <출력 폴더>/core.pck, art.pck, manifest.json
##   core: 코드·장면·데이터 (res://version.json 포함)
##   art : 초상화·아티팩트 아이콘
##   voice: 전투 보이스 (assets/voices, 원본 파일 그대로 — 있을 때만)
##   motion: 전투 모션 시트 (assets/motions, 가져오기 없이 원본 파일 그대로 — 있을 때만)
##   motion2: 의상 그룹 유닛 모션 (id 에 "__"), mobs: 몬스터·펫 모션 (m_ / pet_)
## 먼저 `godot --headless --path . --import` 로 가져오기를 끝내 두어야 한다.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("사용법: -- <출력 폴더> <빌드 번호> [min_base]")
		quit(1)
		return
	var out: String = args[0]
	var build := int(args[1])
	var min_base := int(args[2]) if args.size() > 2 else 1
	DirAccess.make_dir_recursive_absolute(out)
	var version := "%s-b%d" % [Time.get_date_string_from_system().replace("-", "."), build]
	# 묶음 안에 들어갈 버전 정보
	var vf := FileAccess.open("res://version.json", FileAccess.WRITE)
	vf.store_string(JSON.stringify({"build": build, "version": version}))
	vf.close()

	var core := []
	for dir in ["res://scripts", "res://scenes"]:
		_collect(dir, ["gd", "uid", "tscn", "tres"], core)
	for f in DirAccess.get_files_at("res://data"):
		if f.ends_with(".json"):
			core.append("res://data/" + f)
	core.append("res://version.json")
	core.append("res://.godot/global_script_class_cache.cfg")

	var art := []
	for dir in ["res://assets/portraits", "res://assets/artifacts", "res://assets/icons"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".import"):
				art.append(dir + "/" + f)
				var imported := _imported_path(dir + "/" + f)
				if imported != "":
					art.append(imported)

	# 효과음: 가져오기 없이 원본 ogg 그대로 (assets/sfx/.gdignore)
	if DirAccess.dir_exists_absolute("res://assets/sfx"):
		_collect("res://assets/sfx", ["ogg"], art)

	# 모션: 사도(motion) · 의상 그룹 유닛(motion2, id 에 "__") · 몬스터·펫(mobs, m_/pet_) 로 나눠 각각 받게
	var motion := []
	var motion2 := []
	var mobs := []
	if DirAccess.dir_exists_absolute("res://assets/motions"):
		for f in DirAccess.get_files_at("res://assets/motions"):
			if f.ends_with(".json"):
				motion.append("res://assets/motions/" + f)
		for d in DirAccess.get_directories_at("res://assets/motions"):
			var dst := motion
			if d.begins_with("m_") or d.begins_with("pet_"):
				dst = mobs
			elif d.contains("__"):
				dst = motion2
			_collect("res://assets/motions/" + d, ["json", "webp"], dst)
	var voice := []
	if DirAccess.dir_exists_absolute("res://assets/voices"):
		_collect("res://assets/voices", ["json", "ogg"], voice)

	var manifest := {"build": build, "version": version, "min_base": min_base, "packs": {}}
	var packs := [["core", core], ["art", art]]
	if not motion.is_empty():
		packs.append(["motion", motion])
	if not motion2.is_empty():
		packs.append(["motion2", motion2])
	if not mobs.is_empty():
		packs.append(["mobs", mobs])
	if not voice.is_empty():
		packs.append(["voice", voice])
	for pack in packs:
		var path: String = out.path_join(pack[0] + ".pck")
		var p := PCKPacker.new()
		p.pck_start(path)
		for res_path in pack[1]:
			p.add_file(res_path, ProjectSettings.globalize_path(res_path))
		p.flush()
		manifest["packs"][pack[0]] = {
			"file": pack[0] + ".pck",
			"sha256": FileAccess.get_sha256(path),
			"size": FileAccess.get_file_as_bytes(path).size(),
			"files": pack[1].size(),
		}
		print("%s: 파일 %d개, %.2f MB" % [pack[0], pack[1].size(), manifest["packs"][pack[0]]["size"] / 1048576.0])
	var mf := FileAccess.open(out.path_join("manifest.json"), FileAccess.WRITE)
	mf.store_string(JSON.stringify(manifest, " "))
	mf.close()
	print("build %d (%s) -> %s" % [build, version, out])
	quit(0)


func _collect(dir: String, exts: Array, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if exts.has(f.get_extension()):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_collect(dir + "/" + d, exts, out)


## .import 파일에서 실제 가져온 리소스 경로(.ctex 등)를 읽는다
func _imported_path(import_file: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(import_file) != OK:
		return ""
	return str(cfg.get_value("remap", "path", ""))
