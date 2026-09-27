extends RefCounted
const Paths: Script = preload("res://game/core/gdscript/project_paths.gd")
## Content selection is frozen before entering a world; gameplay never installs packages.
static func selected(base: PackedStringArray, settings_path: String) -> Dictionary:
	var config: ConfigFile = ConfigFile.new()
	var code: Error = config.load(settings_path)
	if code not in [OK, ERR_FILE_NOT_FOUND]:
		return {"error": "Cannot read content settings"}
	var result: PackedStringArray = base.duplicate()
	if not config.has_section("content"):
		return {"paths": result}
	if config.get_value("content", "format", 0) != 1:
		return {"error": "Unsupported content settings version"}
	var enabled: Variant = config.get_value("content", "enabled", PackedStringArray())
	if not enabled is PackedStringArray:
		return {"error": "Invalid enabled package list"}
	for file: String in enabled:
		if file != file.get_file() or file.get_extension() != "aebpack":
			return {"error": "Invalid package filename"}
		result.append(Paths.blocks_directory().path_join(file))
	return {"paths": result}
