extends SceneTree
var failures: Array[String] = []
var checks: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)

func make_buffer(size: int) -> VoxelBuffer:
	var result: VoxelBuffer = VoxelBuffer.new()
	result.create(size, size, size)
	return result

func same_buffer(a: VoxelBuffer, b: VoxelBuffer) -> bool:
	var size: Vector3i = a.get_size()
	if size != b.get_size():
		return false
	for z: int in range(size.z):
		for x: int in range(size.x):
			for y: int in range(size.y):
				if a.get_voxel(x, y, z) != b.get_voxel(x, y, z):
					return false
	return true

func _initialize() -> void:
	var content: AstraeonWorldContent = AstraeonWorldContent.new()
	check(content.build(PackedStringArray(["res://game/data/content/packages/astraeon.aebpack"])), "Content builds")
	var previous_material: Material
	for axis: String in ["x", "y", "z"]:
		var model: VoxelBlockyModelCube = content.library.models[content.state_keys.find("astraeon:log/axis_" + axis)] as VoxelBlockyModelCube
		var material: Material = model.get_material_override(0)
		check(previous_material == null or previous_material == material, "Log orientations share compiled material " + axis)
		previous_material = material
	var water_model: VoxelBlockyModelCube = content.library.models[content.water_id] as VoxelBlockyModelCube
	check(water_model.collision_aabbs.is_empty() and not water_model.is_mesh_collision_enabled(0), "Water has no solid collision")
	var generator: AstraeonNativeGenerator = AstraeonNativeGenerator.new()
	check(generator.configure_content(content.state_keys), "Content IDs configured")
	check(not generator.configure_content(content.state_keys), "Registry frozen")
	generator.biome_layout = 1
	for pair: Vector2i in [Vector2i(0, 0), Vector2i(320, 1), Vector2i(640, 2), Vector2i(850, 3)]:
		check(int(generator.sample_column(pair.x, 0)["biome"]) == pair.y, "Expected biome at " + str(pair.x))
	var origin: Vector3i = Vector3i(-768, 32, -16)
	var large: VoxelBuffer = make_buffer(32)
	generator.generate_block(large, Vector3(origin), 0)
	var trunks: int = 0
	var leaves: int = 0
	var log_id: int = content.state_keys.find("astraeon:log/axis_y")
	var leaf_id: int = content.state_keys.find("astraeon:leaves/default")
	for z: int in range(32):
		for x: int in range(32):
			for y: int in range(32):
				var value: int = large.get_voxel(x, y, z)
				trunks += int(value == log_id)
				leaves += int(value == leaf_id)
	check(trunks > 0 and leaves > 0, "Forest creates trunks and leaves")
	var seams_match: bool = true
	for index: int in range(7, -1, -1):
		var offset: Vector3i = Vector3i((index & 1) * 16, ((index >> 1) & 1) * 16, ((index >> 2) & 1) * 16)
		var section: VoxelBuffer = make_buffer(16)
		generator.generate_block(section, Vector3(origin + offset), 0)
		for z: int in range(16):
			for x: int in range(16):
				for y: int in range(16):
					seams_match = seams_match and section.get_voxel(x, y, z) == large.get_voxel(x + offset.x, y + offset.y, z + offset.z)
	check(seams_match, "Negative XYZ sections equal whole region, including tree canopies")
	var repeat: VoxelBuffer = make_buffer(32)
	generator.generate_block(repeat, Vector3(origin), 0)
	check(same_buffer(repeat, large), "Repeated generation deterministic")
	generator.seed += 1
	generator.generate_block(repeat, Vector3(origin), 0)
	check(not same_buffer(repeat, large), "Seed changes forest")
	generator.biome_layout = 0
	var biomes: Dictionary[int, bool] = {}
	for z: int in range(-2048, 2049, 64):
		for x: int in range(-2048, 2049, 64):
			biomes[int(generator.sample_column(x, z)["biome"])] = true
	check(biomes.size() == 4, "Natural layout contains all four biomes")
	var directory: String = "res://tmp/landscape-tests/" + str(Time.get_ticks_usec())
	var registry: RefCounted = ClassDB.instantiate("AstraeonContentRegistry")
	var registered: Dictionary = registry.call("resolve", directory, content.bundle.contracts, PackedStringArray(["astraeon"]))
	var stream: AstraeonNativeStream = AstraeonNativeStream.new()
	check(stream.open_world(directory, generator.seed, 0, content.state_keys, String(registered.world_id)), "Open format 3")
	var section: VoxelBuffer = make_buffer(16)
	section.fill(content.water_id)
	section.set_voxel(content.state_keys.find("astraeon:log/axis_z"), 15, 15, 15)
	stream.save_voxel_block(section, Vector3i(-1, 2, -1), 0)
	var loaded: VoxelBuffer = make_buffer(16)
	check(stream.load_voxel_block(loaded, Vector3i(-1, 2, -1), 0) == VoxelStream.RESULT_BLOCK_FOUND and same_buffer(loaded, section), "Water and oriented log round trip")
	var reordered: PackedStringArray = content.state_keys.duplicate()
	var temp: String = reordered[1]
	reordered[1] = reordered[2]
	reordered[2] = temp
	var wrong: AstraeonNativeStream = AstraeonNativeStream.new()
	check(not wrong.open_world(directory, generator.seed, 0, reordered, String(registered.world_id)), "Reject reordered state table")
	var file: FileAccess = FileAccess.open(directory + "/-1_0_-1.avr", FileAccess.READ_WRITE)
	file.seek(12)
	file.store_32(1)
	file.close()
	var old: AstraeonNativeStream = AstraeonNativeStream.new()
	check(old.open_world(directory, generator.seed, 0, content.state_keys, String(registered.world_id)), "Open obsolete generation")
	check(old.load_voxel_block(loaded, Vector3i(-1, 2, -1), 0) == VoxelStream.RESULT_ERROR, "Reject obsolete generator")
	print(JSON.stringify({"checks": checks, "failures": failures, "trunks": trunks, "leaves": leaves}))
	quit(0 if failures.is_empty() else 1)
