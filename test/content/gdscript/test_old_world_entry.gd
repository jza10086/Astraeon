extends SceneTree
## Explicit new-world recovery must preserve old data and settings.
const Selection: Script = preload("res://game/core/gdscript/world_selection.gd")
var checks: int = 0
var failures: int = 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var base: String = "res://tmp/content/old_entry_" + str(Time.get_ticks_usec())
	var old: String = base + "/legacy"
	var settings: String = base + "/settings.cfg"
	DirAccess.make_dir_recursive_absolute(old)
	var region_path: String = old + "/r.0.0.0.avr"
	var region: FileAccess = FileAccess.open(region_path, FileAccess.WRITE)
	region.store_string("retained prototype bytes: never reinterpret or migrate")
	region.close()
	var digest: String = FileAccess.get_sha256(region_path)
	var config: ConfigFile = ConfigFile.new()
	config.set_value("content", "format", 1)
	config.set_value("content", "enabled", PackedStringArray())
	config.set_value("unrelated", "sentinel", 42)
	check(config.save(settings) == OK, "prepare isolated settings")
	var world: Node = load("res://game/core/main.tscn").instantiate()
	world.set("world_directory", old)
	world.set("shading_settings_path", settings)
	root.add_child(world)
	current_scene = world
	await process_frame
	var panel: Node = world.get_node_or_null("Overlay/Layout/Content/WorldStartError")
	check(panel != null, "old world shows explicit recovery choices")
	check(not world.get("ready_to_play"), "old world never runs")
	check(not FileAccess.file_exists(old + "/content_registry.0"), "no registry fabricated for old data")
	if panel != null:
		panel.get_node("CreateNewWorld").emit_signal("pressed")
		await process_frame
		var deadline: int = Time.get_ticks_msec() + 90000
		while (current_scene == null or not current_scene.get("ready_to_play")) and Time.get_ticks_msec() < deadline:
			await process_frame
		var fresh: Node = current_scene
		check(fresh != null and fresh.get("ready_to_play"), "new world playable")
		if fresh != null:
			var directory: String = fresh.get("world_directory")
			check(directory != old and directory.get_base_dir() == old.get_base_dir(), "new sibling save directory")
			check(FileAccess.file_exists(directory + "/content_registry.0"), "new stable ID registry created")
			check(Selection.selected(old, settings).get("directory", "") == directory, "next launch remembers selected world")
			check(config.load(settings) == OK and config.get_value("unrelated", "sentinel") == 42, "other settings retained")
			fresh.queue_free()
			await process_frame
	check(FileAccess.get_sha256(region_path) == digest, "old region bytes unchanged")
	check(not FileAccess.file_exists(old + "/content_registry.0"), "old directory still unmodified")
	config.set_value("world", "active_slot", "../escape")
	config.save(settings)
	check(Selection.selected(old, settings).has("error"), "reject traversal")
	config.set_value("world", "format", 99)
	config.save(settings)
	check(Selection.create_new(old, settings).has("error"), "reject unsupported config without overwriting")
	print("CONTENT_OLD_WORLD_ENTRY_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
