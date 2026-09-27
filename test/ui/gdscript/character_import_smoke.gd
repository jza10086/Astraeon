extends SceneTree
const Models: Script = preload("res://game/entities/common/gdscript/character_models.gd")
const Library: Script = preload("res://game/entities/common/gdscript/character_library.gd")
const Page: Script = preload("res://game/ui/main_menu/gdscript/character_select.gd")
const Player: PackedScene = preload("res://game/entities/player/scenes/player.tscn")
var failures: int = 0
var checks: int = 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	root.get_node("MCPRuntimeServer").call("_stop_server")
	create_timer(60).timeout.connect(func() -> void: quit(2))
	check(Library.ensure_directory() == OK, "Create project character directory")
	print("CHARACTERS_DIRECTORY=" + ProjectSettings.globalize_path(Library.directory))
	Library.set_directory("res://tmp/character_import_%d" % Time.get_ticks_usec())
	Library.ensure_directory()
	var settings: String = Library.directory.path_join("settings.cfg")
	# Simulate a file placed into the folder, then opening the menu.
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://game/entities/player/assets/basic_voxel.glb"), ProjectSettings.globalize_path(Library.directory.path_join("dropped.glb")))
	var page: Control = Page.new()
	page.theme = preload("res://game/ui/resources/menu_theme.tres")
	root.add_child(page)
	page.call("open", settings)
	check((page.get("model_buttons") as Dictionary).has(&"user/dropped.glb"), "Dropped model discovered on open: " + str(Library.errors))
	# Same handler used by the import dialog, preserving the original source.
	await page.call("import_character", "res://game/entities/player/assets/klukai_voxel.glb")
	var id: StringName = &"user/klukai_voxel.glb"
	check(page.get("selected_id") == id, "Imported Klukai preview: " + (page.get("message") as Label).text)
	if page.get("selected_id") == id:
		var animator: AnimationPlayer = (page.get("preview_model") as Node3D).get_node("AnimationPlayer") as AnimationPlayer
		check(animator.is_playing() and animator.current_animation == "Idle", "Runtime GLB plays Idle")
		check(animator.get_animation("Run").loop_mode == Animation.LOOP_LINEAR and animator.get_animation("JumpStart").loop_mode == Animation.LOOP_NONE, "Runtime loops assigned")
		page.call("confirm")
		check(Models.load_id(settings) == id, "Imported selection saved")
		var player: CharacterMotor = Player.instantiate() as CharacterMotor
		player.get_node("Visual").set("settings_path", settings)
		player.get_node("Controller").set("input_enabled", false)
		root.add_child(player)
		check(player.get_node("Visual").get("model_id") == id and player.find_child("Skeleton3D", true, false).get_bone_count() == 67, "Player instantiates external character")
		player.queue_free()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/character_import.png")
		page.call("delete_selected")
		check(not FileAccess.file_exists(Library.directory.path_join("klukai_voxel.glb")) and FileAccess.file_exists("res://game/entities/player/assets/klukai_voxel.glb"), "Delete only imported copy")
	var bad: String = Library.directory.path_join("invalid.glb")
	var file: FileAccess = FileAccess.open(bad, FileAccess.WRITE)
	file.store_string("not a model")
	file.close()
	page.call("cancel")
	page.call("open", settings)
	check(not Library.errors.is_empty() and not (page.get("model_buttons") as Dictionary).has(&"user/invalid.glb"), "Invalid file reported without breaking available characters")
	page.queue_free()
	await process_frame
	print("CHARACTER_IMPORT_SMOKE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
