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
	return id if not definition(id).is_empty() else &""

static func save_id(id: StringName, path: String = "user://settings.cfg") -> Error:
	if definition(id).is_empty():
		return ERR_INVALID_PARAMETER
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(path)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		return error
	config.set_value("character", "model", String(id))
	var temporary: String = path + ".character.tmp"
	error = config.save(temporary)
	if error != OK:
		return error
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))

static func instantiate(id: StringName) -> Node3D:
	var entry: Dictionary = definition(id)
	if entry.is_empty():
		return null
	var scene: PackedScene = load(entry.path) as PackedScene
	return scene.instantiate() as Node3D if scene != null else null
