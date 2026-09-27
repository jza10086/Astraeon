extends SceneTree
const Paths: Script = preload("res://game/core/gdscript/project_paths.gd")
const Models: Script = preload("res://game/entities/common/gdscript/character_models.gd")
const Library: Script = preload("res://game/entities/common/gdscript/character_library.gd")
const Content: Script = preload("res://game/core/gdscript/content_selection.gd")
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
const Menu: PackedScene = preload("res://game/ui/main_menu/scenes/main_menu.tscn")
var failures: int = 0
var checks: int = 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func run() -> void:
	root.get_node("MCPRuntimeServer").call("_stop_server")
	var project: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	check(Paths.root_directory() == project, "Storage root is project, independent of shell cwd")
	check(Paths.settings_file() == project.path_join("runtime_data/settings.cfg"), "Settings are local")
	check(Paths.worlds_directory() == project.path_join("runtime_data/worlds"), "Worlds are local")
	check(Library.directory == project.path_join("external_data/characters"), "Character import uses external data")
	check(Paths.blocks_directory() == project.path_join("external_data/blocks"), "Block imports use external data")
	var menu: Control = Menu.instantiate() as Control
	root.add_child(menu)
	check(menu.get("settings_path") == Paths.settings_file(), "Menu defaults use project storage")
	var worlds: DirAccess = DirAccess.open(Paths.worlds_directory())
	check(worlds != null, "Local world list readable")
	var config: ConfigFile = ConfigFile.new()
	check(config.load(Paths.settings_file()) in [OK, ERR_FILE_NOT_FOUND], "Local settings readable")
	var temporary: String = "res://tmp/local_storage_%d.cfg" % Time.get_ticks_usec()
	config = ConfigFile.new()
	config.set_value("content", "format", 1)
	config.set_value("content", "enabled", PackedStringArray(["example.aebpack"]))
	config.save(temporary)
	var selected: Dictionary = Content.selected(PackedStringArray(), temporary)
	check(selected.get("paths", PackedStringArray()) == PackedStringArray([Paths.blocks_directory().path_join("example.aebpack")]), "Content paths use project blocks directory")
	check(Models.save_id(&"basic_voxel", temporary) == OK and Models.load_id(temporary) == &"basic_voxel", "Character selection roundtrip")
	var profile: Profile = Profile.new()
	check(profile.save_settings(temporary) == OK and Profile.new().load_settings(temporary) == OK and Models.load_id(temporary) == &"basic_voxel", "Shared settings preserve character selection")
	menu.queue_free()
	await process_frame
	print("LOCAL_STORAGE_TEST checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
