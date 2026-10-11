extends SceneTree
var failures: int = 0
var checked: int = 0
func _initialize() -> void:
	for directory: String in ["res://game", "res://test", "res://tools/content", "res://addons/astraeon_content"]:
		visit(directory)
	print("CONTENT_SCRIPTS_DONE checks=%d failures=%d" % [checked, failures])
	quit(1 if failures else 0)
func visit(directory: String) -> void:
	if FileAccess.file_exists(directory.path_join(".gdignore")): return
	for file: String in DirAccess.get_files_at(directory):
		if file.get_extension() != "gd": continue
		var path: String = directory.path_join(file)
		var script: GDScript = load(path) as GDScript
		checked += 1
		if script == null or not script.can_instantiate():
			failures += 1
			printerr("SCRIPT_LOAD_FAIL ", path)
	for child: String in DirAccess.get_directories_at(directory):
		if child in ["reports", "native"]: continue
		visit(directory.path_join(child))
