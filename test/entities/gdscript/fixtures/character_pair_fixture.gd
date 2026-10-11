extends RefCounted
## Copy installed delivery assets into isolated test-owned character directories.
static func install(directory: String, name: String) -> void:
	assert(directory.begins_with("res://tmp/"))
	var folder: String = directory.path_join(name)
	assert(DirAccess.make_dir_recursive_absolute(folder) == OK)
	var source: String = preload("res://game/core/gdscript/project_paths.gd").characters_directory().path_join("basic_voxel")
	for suffix: String in ["_tp.glb", "_fp.glb"]:
		assert(DirAccess.copy_absolute(source.path_join("basic_voxel" + suffix), ProjectSettings.globalize_path(folder.path_join(name + suffix))) == OK)
