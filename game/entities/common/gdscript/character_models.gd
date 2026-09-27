extends RefCounted
const Paths: Script = preload("res://game/core/gdscript/project_paths.gd")
## Current character catalog. Selection is read once when a player enters the tree.
const Library: Script = preload("res://game/entities/common/gdscript/character_library.gd")
const MODELS: Array[Dictionary] = [
	{"id": &"basic_voxel", "name": "标准素体", "path": "res://game/entities/player/assets/basic_voxel.glb"},
	{"id": &"klukai", "name": "Klukai", "path": "res://game/entities/player/assets/klukai_voxel.glb"},
]

static func definition(id: StringName) -> Dictionary:
	for entry: Dictionary in MODELS:
		if entry.id == id:
			return entry
	return Library.definition(id)

static func load_id(path: String = "") -> StringName:
	if path.is_empty():
		path = Paths.settings_file()
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(path)
	if error == ERR_FILE_NOT_FOUND:
		return &"basic_voxel"
	if error != OK:
		return &""
	var id: StringName = StringName(str(config.get_value("character", "model", "basic_voxel")))
	var choices: Array[Dictionary] = available(path)
	if _contains(choices, id):
		return id
	if String(id).begins_with("user/") and not choices.is_empty():
		return choices[0].id
	return &""

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

static func instantiate(id: StringName) -> Node3D:
	if String(id).begins_with("user/"):
		return Library.instantiate(id)
	var entry: Dictionary = definition(id)
	if entry.is_empty():
		return null
	var scene: PackedScene = load(entry.path) as PackedScene
	return scene.instantiate() as Node3D if scene != null else null

## Local catalog removal preserves packaged assets and authoring sources.
static func available(path: String = "") -> Array[Dictionary]:
	if path.is_empty():
		path = Paths.settings_file()
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(path)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		return []
	var removed: Variant = config.get_value("character", "removed", PackedStringArray())
	if not removed is PackedStringArray:
		return []
	for id: String in removed:
		if definition(StringName(id)).is_empty():
			return []
	var result: Array[Dictionary] = []
	for entry: Dictionary in MODELS:
		if not String(entry.id) in removed:
			result.append(entry)
	# Populate external entries lazily when entering a world directly.
	Library.ensure_scanned()
	result.append_array(Library.entries)
	# External files can disappear outside the game; retain a usable built-in fallback.
	if result.is_empty():
		result.append(MODELS[0])
	return result

static func _contains(entries: Array[Dictionary], id: StringName) -> bool:
	for entry: Dictionary in entries:
		if entry.id == id:
			return true
	return false

static func remove_id(id: StringName, path: String = "") -> Error:
	if path.is_empty():
		path = Paths.settings_file()
	var entries: Array[Dictionary] = available(path)
	if load_id(path).is_empty():
		return ERR_INVALID_DATA
	if entries.size() <= 1 or not _contains(entries, id):
		return ERR_INVALID_PARAMETER
	if String(id).begins_with("user/"):
		var current: StringName = load_id(path)
		if current == id:
			for entry: Dictionary in entries:
				if entry.id != id:
					var saved: Error = save_id(entry.id, path)
					if saved != OK:
						return saved
					break
		return Library.delete_file(id)
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(path)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		return error
	var removed: PackedStringArray = config.get_value("character", "removed", PackedStringArray())
	removed.append(String(id))
	config.set_value("character", "removed", removed)
	if load_id(path) == id:
		for entry: Dictionary in entries:
			if entry.id != id:
				config.set_value("character", "model", String(entry.id))
				break
	return _save(config, path)
