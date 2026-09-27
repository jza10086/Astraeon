extends RefCounted
## Current character catalog. Selection is read once when a player enters the tree.
const MODELS: Array[Dictionary] = [
	{"id": &"basic_voxel", "name": "标准素体", "path": "res://game/entities/player/assets/basic_voxel.glb"},
	{"id": &"klukai", "name": "Klukai", "path": "res://game/entities/player/assets/klukai_voxel.glb"},
]

static func definition(id: StringName) -> Dictionary:
	for entry: Dictionary in MODELS:
		if entry.id == id:
			return entry
	return {}

static func load_id(path: String = "user://settings.cfg") -> StringName:
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(path)
	if error == ERR_FILE_NOT_FOUND:
		return &"basic_voxel"
	if error != OK:
		return &""
	var id: StringName = StringName(str(config.get_value("character", "model", "basic_voxel")))
	return id if _contains(available(path), id) else &""

static func save_id(id: StringName, path: String = "user://settings.cfg") -> Error:
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
	var entry: Dictionary = definition(id)
	if entry.is_empty():
		return null
	var scene: PackedScene = load(entry.path) as PackedScene
	return scene.instantiate() as Node3D if scene != null else null

## Local catalog removal preserves packaged assets and authoring sources.
static func available(path: String = "user://settings.cfg") -> Array[Dictionary]:
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
	return result

static func _contains(entries: Array[Dictionary], id: StringName) -> bool:
	for entry: Dictionary in entries:
		if entry.id == id:
			return true
	return false

static func remove_id(id: StringName, path: String = "user://settings.cfg") -> Error:
	var entries: Array[Dictionary] = available(path)
	if load_id(path).is_empty():
		return ERR_INVALID_DATA
	if entries.size() <= 1 or not _contains(entries, id):
		return ERR_INVALID_PARAMETER
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
