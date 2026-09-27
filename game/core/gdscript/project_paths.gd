extends RefCounted
## Writable application data stays beside the project (or exported executable).
static func root_directory() -> String:
	return ProjectSettings.globalize_path("res://").trim_suffix("/") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir()

static func directory(relative: String) -> String:
	var path: String = root_directory().path_join(relative)
	var error: Error = DirAccess.make_dir_recursive_absolute(path)
	if error != OK:
		push_error("Cannot create project data directory %s: %s" % [path, error_string(error)])
	return path

static func settings_file() -> String:
	var parent: String = directory("runtime_data")
	return parent.path_join("settings.cfg") if not parent.is_empty() else ""

static func worlds_directory() -> String:
	return directory("runtime_data/worlds")

static func characters_directory() -> String:
	return directory("external_data/characters")

static func blocks_directory() -> String:
	return directory("external_data/blocks")
