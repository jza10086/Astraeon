extends RefCounted
const Paths: Script = preload("res://game/core/gdscript/project_paths.gd")
const Library: Script = preload("res://game/entities/common/gdscript/character_library.gd")
## All characters, including the default, are external paired folders.
static func definition(id: StringName) -> Dictionary:
	return Library.definition(id)

static func load_id(path: String = "") -> StringName:
	if path.is_empty():
		path = Paths.settings_file()
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(path)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		return &""
	if config.has_section_key("character", "removed"):
		return &""
	var id: StringName = StringName(str(config.get_value("character", "model", "basic_voxel")))
	return id if not definition(id).is_empty() else &""

static func save_id(id: StringName, path: String = "") -> Error:
	if path.is_empty():
		path = Paths.settings_file()
	if not _contains(available(path), id):
		return ERR_INVALID_PARAMETER
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(path)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		return error
	config.set_value("character", "model", String(id))
	return _save(config, path)

static func _save(config: ConfigFile, path: String) -> Error:
	var temporary: String = path + ".character.tmp"
	var error: Error = config.save(temporary)
	if error != OK:
		return error
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))

static func instantiate(id: StringName, first_person: bool = false) -> Node3D:
	return Library.instantiate(id, first_person)

static func available(path: String = "") -> Array[Dictionary]:
	if path.is_empty():
		path = Paths.settings_file()
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(path)
	if error != OK and error != ERR_FILE_NOT_FOUND or config.has_section_key("character", "removed"):
		return []
	Library.ensure_scanned()
	return Library.entries.duplicate()

static func _contains(entries: Array[Dictionary], id: StringName) -> bool:
	for entry: Dictionary in entries:
		if entry.id == id:
			return true
	return false

static func remove_id(id: StringName, path: String = "") -> Error:
	if path.is_empty():
		path = Paths.settings_file()
	var entries: Array[Dictionary] = available(path)
	var current: StringName = load_id(path)
	if current.is_empty():
		return ERR_INVALID_DATA
	if entries.size() <= 1 or not _contains(entries, id):
		return ERR_INVALID_PARAMETER
	if current == id:
		for entry: Dictionary in entries:
			if entry.id != id:
				var saved: Error = save_id(entry.id, path)
				if saved != OK:
					return saved
				break
	return Library.delete_folder(id)
