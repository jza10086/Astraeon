extends SceneTree
## Functional title -> production Main startup. User saves/settings are never touched.
var failures: int = 0
var checks: int = 0
var directory: String
var settings: String
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	directory = "res://tmp/content/main_entry_" + str(Time.get_ticks_usec())
	settings = directory + "/settings.cfg"
	DirAccess.make_dir_recursive_absolute(directory)
	var config: ConfigFile = ConfigFile.new()
	config.set_value("content", "format", 1)
	config.set_value("content", "enabled", PackedStringArray())
	check(config.save(settings) == OK, "isolated settings")
	var menu: Control = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	menu.set("settings_path", settings)
	menu.set("worlds_root", directory + "/worlds")
	root.add_child(menu)
	current_scene = menu
	check(menu.get("content_button") != null, "title content package entry")
	menu.get_node("%Play").emit_signal("pressed")
	check(menu.world_page.visible and not menu.loading, "single player opens slot selection")
	menu.world_page._show_create()
	menu.world_page.name_input.text = "Main entry"
	menu.world_page.create_world()
	check(menu.get("content_button").disabled, "package selection frozen while loading")
	var deadline: int = Time.get_ticks_msec() + 90000
	while (current_scene == menu or current_scene == null) and Time.get_ticks_msec() < deadline:
		await process_frame
	var world: Node = current_scene
	check(world != null and world.scene_file_path == "res://game/core/main.tscn", "title opens production Main")
	if world != null and world.scene_file_path == "res://game/core/main.tscn":
		while not world.get("ready_to_play") and Time.get_ticks_msec() < deadline:
			await process_frame
		check(world.get("ready_to_play"), "Main playable: " + str(world.get("_status").text))
		check(world.get("shading_settings_path") == settings, "title settings reach Main")
		var content: AstraeonWorldContent = world.get("content")
		check(content != null and content.error.is_empty(), "compiled content builds")
		if content != null and content.bundle != null:
			check(content.state_keys.has("astraeon:grass/default") and content.state_keys.has("astraeon:glowstone/default"), "base namespaced content registered")
			check(world.get("item_catalog") == content.item_catalog, "compiled items feed inventory")
			check(world.get("water_definition") == content.water_definition, "compiled water feeds world")
			check(world.get("cache_coordinator") != null, "visual cache coordinator active")
			check(content.bundle.visuals.call("get_metrics").failures.is_empty(), "visual cache has no failures")
		if world.get("ready_to_play"):
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/content/main_entry.png")
		world.queue_free()
		await process_frame
	print("CONTENT_MAIN_ENTRY_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
