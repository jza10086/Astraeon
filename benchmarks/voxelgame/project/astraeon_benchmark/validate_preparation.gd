extends SceneTree
## Loads scripts/resources only. Never instantiates scenes, terrain, viewers or generators.

func _initialize() -> void:
	if not ClassDB.class_exists("VoxelTerrain") or not ClassDB.class_exists("VoxelMesherBlocky"):
		push_error("Missing voxel extension classes")
		quit(1)
		return
	var version: Vector3i = VoxelEngine.get_version_v()
	if version.x != 1 or version.y != 7 or not VoxelEngine.get_version_edition().to_lower().contains("extension"):
		push_error("Unexpected voxel dependency version: " + str(version))
		quit(1)
		return
	var paths: PackedStringArray = PackedStringArray([
		"res://astraeon_benchmark/benchmark.gd",
		"res://astraeon_benchmark/benchmark.tscn",
		"res://astraeon_benchmark/initial_load.tscn",
		"res://astraeon_benchmark/stationary.tscn",
		"res://astraeon_benchmark/streaming.tscn",
		"res://astraeon_benchmark/editing.tscn",
		"res://blocky_game/main.tscn",
		"res://blocky_game/blocks/mesher.tres",
		"res://blocky_game/generator/generator.gd"
	])
	for path: String in paths:
		var resource: Resource = load(path)
		if resource == null:
			push_error("Cannot load resource: " + path)
			quit(1)
			return
	print("PREPARATION_VALID: Voxel Tools ", version, " (", VoxelEngine.get_version_edition(), ")")
	print("Resources loaded without scene instantiation. No benchmark workload executed.")
	quit()
