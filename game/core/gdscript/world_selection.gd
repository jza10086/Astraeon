extends RefCounted
## World directories are separate slots. No region conversion or secondary voxel state.
static func valid_slot(slot: String) -> bool:
	if slot.is_empty() or slot.length() > 64 or slot != slot.strip_edges() or slot.ends_with(".") or slot.begins_with("."):
		return false
	for character: String in ['/', '\\', ':', '*', '?', '"', '<', '>', '|']:
		if character in slot:
			return false
	for index: int in slot.length():
		if slot.unicode_at(index) < 32:
			return false
	var stem: String = slot.get_slice(".", 0).to_upper()
	return stem not in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]

static func selected(fallback: String, settings_path: String) -> Dictionary:
	var config: ConfigFile = ConfigFile.new()
	var code: Error = config.load(settings_path)
	if code not in [OK, ERR_FILE_NOT_FOUND]:
		return {"error": "无法读取世界选择设置：" + error_string(code)}
	if not config.has_section("world"):
		return {"directory": fallback}
	if config.get_value("world", "format", 0) != 1:
		return {"error": "不支持的世界选择设置版本"}
	var slot: Variant = config.get_value("world", "active_slot", "")
	if not slot is String or not valid_slot(slot):
		return {"error": "无效的世界目录名称"}
	var root: String = fallback.get_base_dir()
	var directory: DirAccess = DirAccess.open(root)
	if directory == null or directory.is_link(slot) or not directory.dir_exists(slot):
		return {"error": "所选世界不存在或是链接，请重新选择存档"}
	return {"directory": root.path_join(slot)}

static func list_worlds(root: String) -> Dictionary:
	if not DirAccess.dir_exists_absolute(root):
		return {"slots": PackedStringArray()}
	var directory: DirAccess = DirAccess.open(root)
	if directory == null:
		return {"error": "无法读取存档目录"}
	var slots: PackedStringArray = []
	for slot: String in directory.get_directories():
		if valid_slot(slot) and not directory.is_link(slot):
			slots.append(slot)
	slots.sort()
	return {"slots": slots}

## Selection is persisted with recoverable replacement; unrelated settings remain intact.
static func choose(root: String, slot: String, settings_path: String) -> Dictionary:
	var directory: DirAccess = DirAccess.open(root)
	if not valid_slot(slot) or directory == null or directory.is_link(slot) or not directory.dir_exists(slot):
		return {"error": "存档不存在或目录无效"}
	var config: ConfigFile = ConfigFile.new()
	var code: Error = config.load(settings_path)
	if code not in [OK, ERR_FILE_NOT_FOUND]:
		return {"error": "设置无法读取：" + error_string(code)}
	if config.has_section("world") and config.get_value("world", "format", 0) != 1:
		return {"error": "不支持的世界选择设置版本"}
	config.set_value("world", "format", 1)
	config.set_value("world", "active_slot", slot)
	var temporary: String = settings_path + ".tmp"
	code = config.save(temporary)
	if code == OK:
		code = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(settings_path))
	if code != OK:
		return {"error": "无法保存世界选择：" + error_string(code)}
	return {"directory": root.path_join(slot)}

## Called only by an explicit create action. An empty name produces a unique recovery slot.
static func create_new(current: String, settings_path: String, name: String = "", seed: int = 20260916, layout: int = 0, mode: int = AstraeonPlayerState.Mode.SURVIVAL) -> Dictionary:
	if mode not in [AstraeonPlayerState.Mode.SURVIVAL, AstraeonPlayerState.Mode.CREATIVE]:
		return {"error": "无效的游戏模式"}
	if seed < -2147483648 or seed > 2147483647 or layout not in [0, 1]:
		return {"error": "种子必须是 -2147483648 到 2147483647 之间的整数"}
	var slot: String = name if not name.is_empty() else "world_%d_%08x" % [int(Time.get_unix_time_from_system()), randi()]
	if not valid_slot(slot):
		return {"error": "名称须为 1–64 字，不能包含路径符号、首尾空格或系统保留名称"}
	var root: String = current.get_base_dir()
	var directory: String = root.path_join(slot)
	if DirAccess.dir_exists_absolute(directory) or FileAccess.file_exists(directory):
		return {"error": "同名存档已存在，请换一个名称"}
	# Validate settings before creating anything.
	var config: ConfigFile = ConfigFile.new()
	var code: Error = config.load(settings_path)
	if code not in [OK, ERR_FILE_NOT_FOUND] or (config.has_section("world") and config.get_value("world", "format", 0) != 1):
		return {"error": "设置文件无法读取或版本不支持，未创建世界"}
	code = DirAccess.make_dir_recursive_absolute(directory)
	if code != OK:
		return {"error": "无法创建世界目录：" + error_string(code)}
	var parameters: ConfigFile = ConfigFile.new()
	parameters.set_value("world", "format", 2)
	parameters.set_value("world", "initial_mode", mode)
	parameters.set_value("world", "seed", seed)
	parameters.set_value("world", "biome_layout", layout)
	code = parameters.save(directory.path_join("world.cfg.tmp"))
	if code == OK:
		code = DirAccess.rename_absolute(ProjectSettings.globalize_path(directory.path_join("world.cfg.tmp")), ProjectSettings.globalize_path(directory.path_join("world.cfg")))
	if code != OK:
		DirAccess.remove_absolute(directory.path_join("world.cfg.tmp"))
		DirAccess.remove_absolute(directory)
		return {"error": "无法保存世界种子，未进入世界：" + error_string(code)}
	var result: Dictionary = choose(root, slot, settings_path)
	if result.has("error"):
		# Only the files just created here; never remove pre-existing world contents.
		DirAccess.remove_absolute(directory.path_join("world.cfg"))
		DirAccess.remove_absolute(directory)
	return result

## Optional creation parameters supplement the scene defaults; existing native headers still validate them.
static func parameters(directory: String) -> Dictionary:
	var config: ConfigFile = ConfigFile.new()
	var code: Error = config.load(directory.path_join("world.cfg"))
	if code == ERR_FILE_NOT_FOUND:
		return {"error": "缺少当前世界创建参数，请创建新世界"}
	if code != OK or config.get_value("world", "format", 0) != 2:
		return {"error": "世界生成参数不可读取或版本不支持"}
	var seed: Variant = config.get_value("world", "seed", null)
	var layout: Variant = config.get_value("world", "biome_layout", null)
	if not seed is int or seed < -2147483648 or seed > 2147483647 or not layout is int or layout not in [0, 1]:
		return {"error": "世界生成参数无效，未进入世界"}
	var mode: Variant = config.get_value("world", "initial_mode", null)
	if not mode is int or mode not in [AstraeonPlayerState.Mode.SURVIVAL, AstraeonPlayerState.Mode.CREATIVE]:
		return {"error": "世界初始模式无效"}
	return {"seed": seed, "biome_layout": layout, "initial_mode": mode}

static func valid_seed_text(text: String) -> bool:
	var value: String = text.strip_edges()
	return value.is_empty() or (value.length() <= 11 and value.is_valid_int() and value.to_int() >= -2147483648 and value.to_int() <= 2147483647)

## Preflight the entire subtree before removal. Never follow links or escape the chosen slot.
static func delete_world(root: String, slot: String, settings_path: String) -> Dictionary:
	var listing: Dictionary = list_worlds(root)
	if listing.has("error") or not valid_slot(slot) or slot not in listing.get("slots", PackedStringArray()):
		return {"error": "存档不存在或目录无效"}
	var absolute_root: String = ProjectSettings.globalize_path(root).simplify_path().trim_suffix("/")
	var cursor: String = absolute_root
	while cursor != cursor.get_base_dir():
		var parent: DirAccess = DirAccess.open(cursor.get_base_dir())
		if parent == null or parent.is_link(cursor.get_file()):
			return {"error": "拒绝通过链接目录删除存档"}
		cursor = cursor.get_base_dir()
	var target: String = absolute_root.path_join(slot).simplify_path()
	if target.get_base_dir() != absolute_root:
		return {"error": "拒绝删除存档目录以外的路径"}
	var files: Array[String] = []
	var directories: Array[String] = []
	var code: Error = _collect(target, files, directories)
	if code != OK:
		return {"error": "无法安全删除存档（目录包含链接或不可读取）"}
	# Clear a matching selection before deletion so a missing slot can never be recreated by startup.
	var config: ConfigFile = ConfigFile.new()
	code = config.load(settings_path)
	if code not in [OK, ERR_FILE_NOT_FOUND]:
		return {"error": "设置不可读取，未删除存档"}
	if config.has_section("world"):
		if config.get_value("world", "format", 0) != 1:
			return {"error": "世界选择设置版本不支持，未删除存档"}
		if config.get_value("world", "active_slot", "") == slot:
			config.erase_section("world")
			code = config.save(settings_path + ".tmp")
			if code == OK:
				code = DirAccess.rename_absolute(ProjectSettings.globalize_path(settings_path + ".tmp"), ProjectSettings.globalize_path(settings_path))
			if code != OK:
				return {"error": "无法更新世界选择，未删除存档"}
	for path: String in files:
		code = DirAccess.remove_absolute(path)
		if code != OK:
			return {"error": "删除未完成：" + error_string(code)}
	for path: String in directories:
		code = DirAccess.remove_absolute(path)
		if code != OK:
			return {"error": "删除未完成：" + error_string(code)}
	return {"deleted": slot}

static func _collect(path: String, files: Array[String], directories: Array[String]) -> Error:
	var parent: DirAccess = DirAccess.open(path.get_base_dir())
	if parent == null or parent.is_link(path.get_file()):
		return ERR_INVALID_PARAMETER
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return ERR_CANT_OPEN
	directory.include_hidden = true
	for file: String in directory.get_files():
		if directory.is_link(file):
			return ERR_INVALID_PARAMETER
		files.append(path.path_join(file))
	for child: String in directory.get_directories():
		if directory.is_link(child):
			return ERR_INVALID_PARAMETER
		var code: Error = _collect(path.path_join(child), files, directories)
		if code != OK:
			return code
	directories.append(path)
	return OK
