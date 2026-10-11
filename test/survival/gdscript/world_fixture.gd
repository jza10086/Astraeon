extends RefCounted
## Explicit current-format creation for test-owned worlds; never upgrades an existing config.
static func prepare(world: Node) -> void:
	var directory: String = world.get("world_directory")
	assert(directory.begins_with("res://tmp/"))
	if FileAccess.file_exists(directory.path_join("world.cfg")):
		return
	assert(DirAccess.make_dir_recursive_absolute(directory) == OK)
	var config: ConfigFile = ConfigFile.new()
	config.set_value("world", "format", 2)
	config.set_value("world", "seed", int(world.get("seed")))
	config.set_value("world", "biome_layout", int(world.get("biome_layout")))
	config.set_value("world", "initial_mode", AstraeonPlayerState.Mode.SURVIVAL)
	assert(config.save(directory.path_join("world.cfg")) == OK)
