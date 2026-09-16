extends SceneTree
## Run with --headless --path <project> --script res://tests/blocks/test_block_data.gd.
const DEFINITION: Script = preload("res://game/world/blocks/block_definition.gd")
const STATE: Script = preload("res://game/world/blocks/block_state_definition.gd")
const REGISTRY: Script = preload("res://game/world/blocks/block_registry.gd")
const SECTION: Script = preload("res://game/world/blocks/block_section.gd")
const FACTORY: Script = preload("res://game/world/blocks/storage/block_storage_factory.gd")
const STORAGE: Script = preload("res://game/world/blocks/storage/block_storage.gd")
var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0

func _initialize() -> void:
	_test_registry()
	_test_catalog()
	_test_coordinates()
	for backend: FACTORY.Backend in [FACTORY.Backend.DIRECT32, FACTORY.Backend.DIRECT16, FACTORY.Backend.PALETTE]:
		_test_storage(backend)
		_test_section(backend)
	_test_palette_boundaries()
	if _failures.is_empty():
		print("BLOCK_DATA PASS: ", _checks, " checks; 3 backends.")
		quit(0)
	else:
		for failure: String in _failures:
			printerr(failure)
		print("BLOCK_DATA FAIL: ", _failures.size(), " failures.")
		quit(1)

func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)

func _test_registry() -> void:
	var air: AstraeonBlockDefinition = DEFINITION.new()
	air.key = &"astraeon:air"
	air.collision_enabled = false
	air.light_opacity = 0
	var log_block: AstraeonBlockDefinition = DEFINITION.new()
	log_block.key = &"astraeon:log"
	var axis_z: AstraeonBlockStateDefinition = STATE.new()
	axis_z.key = &"axis_z"
	axis_z.properties[&"axis"] = &"z"
	var axis_x: AstraeonBlockStateDefinition = STATE.new()
	axis_x.key = &"axis_x"
	axis_x.properties[&"axis"] = &"x"
	log_block.states = [axis_z, axis_x]
	var registry: AstraeonBlockRegistry = REGISTRY.new()
	_expect(not registry.build([log_block]).is_empty() and registry.state_count() == 0, "Missing air is atomic")
	_expect(registry.build([log_block, air]).is_empty(), "REGISTRY build")
	_expect(registry.find_state(&"astraeon:air") == 0, "Air zero")
	_expect(registry.state_count() == 3 and registry.find_state(&"astraeon:log", &"axis_x") == 1, "Sorted state IDs")
	_expect(registry.find_state(&"missing:block") == -1, "Unknown key")
	var second: AstraeonBlockRegistry = REGISTRY.new()
	log_block.states.reverse()
	_expect(second.build([air, log_block]).is_empty() and second.stable_key(1) == registry.stable_key(1), "Input order independent")
	log_block.hardness = 99.0
	axis_x.properties[&"axis"] = &"changed"
	var copied: Dictionary = registry.properties_for(1)
	copied[&"axis"] = &"external"
	_expect(registry.hardness_for(1) == 1.0 and registry.properties_for(1)[&"axis"] == &"x", "Resource snapshot isolation")
	_expect(not registry.build([air]).is_empty() and registry.state_count() == 3, "REGISTRY immutable")
	var bad: AstraeonBlockRegistry = REGISTRY.new()
	_expect(not bad.build([air, air]).is_empty() and bad.state_count() == 0, "Duplicate block rejected")
	log_block.states = [axis_x, axis_x]
	_expect(not bad.build([air, log_block]).is_empty(), "Duplicate state rejected")
	log_block.states = []
	log_block.light_emission = 16
	_expect(not bad.build([air, log_block]).is_empty(), "Light range checked")
	log_block.light_emission = 0
	log_block.key = &"bad/key"
	_expect(not bad.build([air, log_block]).is_empty(), "Stable key validation")
	_expect(not bad.build([null, air]).is_empty(), "Null resource rejected")

func _test_coordinates() -> void:
	for value: int in [-33, -32, -17, -16, -1, 0, 15, 16, 17, 32]:
		var world: Vector3i = Vector3i(value, value - 1, -value)
		var coordinate: Vector3i = SECTION.section_of(world)
		var local: Vector3i = SECTION.world_to_local(world)
		_expect(SECTION.contains_local(local) and coordinate * 16 + local == world, "Negative coordinate round trip")
	_expect(SECTION.section_of(Vector3i(-1, -16, -17)) == Vector3i(-1, -1, -2), "Floor at negative boundaries")
	for index: int in range(STORAGE.CELL_COUNT):
		_expect(SECTION.index_of(SECTION.local_of(index)) == index, "Index bijection")
	_expect(not SECTION.contains_local(Vector3i(16, 0, 0)), "Upper bound exclusive")

func _test_storage(backend: FACTORY.Backend) -> void:
	var data: AstraeonBlockStorage = FACTORY.create(backend)
	var expected: PackedInt32Array = PackedInt32Array()
	expected.resize(STORAGE.CELL_COUNT)
	expected.fill(0)
	_expect(data.export_states() == expected, "Initial air")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 73517
	for operation: int in range(12000):
		var index: int = rng.randi_range(0, STORAGE.CELL_COUNT - 1)
		var state_id: int = rng.randi_range(0, STORAGE.MAX_STATE_ID)
		_expect(data.set_state(index, state_id), "Random write accepted")
		expected[index] = state_id
	_expect(data.export_states() == expected, "Random edits match independent oracle")
	_expect(not data.set_state(-1, 1) and not data.set_state(4096, 1) and not data.set_state(0, -1) and not data.set_state(0, 65536), "Invalid writes rejected")
	var invalid: PackedInt32Array = expected.duplicate()
	invalid[4095] = 65536
	_expect(not data.import_states(invalid) and data.export_states() == expected, "Invalid import atomic")
	_expect(not data.import_states(PackedInt32Array([0])) and not data.fill(-1), "Invalid size and fill")
	var exported: PackedInt32Array = data.export_states()
	exported[0] = (expected[0] + 1) % 65536
	_expect(data.get_state(0) == expected[0], "Export owns its data")
	for target: FACTORY.Backend in [FACTORY.Backend.DIRECT32, FACTORY.Backend.DIRECT16, FACTORY.Backend.PALETTE]:
		var converted: AstraeonBlockStorage = FACTORY.convert(data, target)
		_expect(converted.export_states() == expected, "Cross-backend round trip")
		converted.fill(7)
		_expect(data.export_states() == expected, "Converted storage independent")
	_expect(data.fill(65535), "Maximum state fill")
	for index: int in range(STORAGE.CELL_COUNT):
		_expect(data.get_state(index) == 65535, "Maximum state reads")
	_expect(data.fill(0) and data.get_state(4095) == 0, "Reset to air")

func _test_section(backend: FACTORY.Backend) -> void:
	var section: AstraeonBlockSection = SECTION.new()
	_expect(section.configure(Vector3i(-2, -1, 3), 8, backend), "SECTION configure")
	_expect(not section.configure(Vector3i.ZERO, 8, backend), "No reconfigure")
	_expect(section.set_state(Vector3i(15, 15, 15), 7) and section.revision() == 1, "SECTION mutation")
	_expect(section.set_state(Vector3i(15, 15, 15), 7) and section.revision() == 1, "No-op revision")
	_expect(not section.set_state(Vector3i.ZERO, 8) and not section.set_state(Vector3i(-1, 0, 0), 1), "SECTION validation")
	_expect(section.get_state(Vector3i(16, 0, 0)) == -1, "Invalid local read")
	var before: PackedInt32Array = section.export_states()
	var invalid: PackedInt32Array = before.duplicate()
	invalid[4095] = 8
	_expect(not section.import_states(invalid) and section.export_states() == before and section.revision() == 1, "SECTION import atomic")
	_expect(section.import_states(before) and section.revision() == 1, "No-op import")
	for target: FACTORY.Backend in [FACTORY.Backend.DIRECT32, FACTORY.Backend.DIRECT16, FACTORY.Backend.PALETTE]:
		_expect(section.change_backend(target) and section.export_states() == before and section.revision() == 1, "SECTION conversion preserves revision")
	before[0] = 3
	_expect(section.import_states(before) and section.revision() == 2, "SECTION transaction revision")

func _test_palette_boundaries() -> void:
	var palette: AstraeonPaletteStorage = FACTORY.create(FACTORY.Backend.PALETTE) as AstraeonPaletteStorage
	_expect(palette.bits_per_index() == 0 and palette.payload_bytes() == 4, "Uniform encoding")
	var uniform: PackedInt32Array = PackedInt32Array()
	uniform.resize(STORAGE.CELL_COUNT)
	uniform.fill(12)
	_expect(palette.import_states(uniform) and palette.bits_per_index() == 0 and palette.get_state(4095) == 12, "Uniform import uses zero bits")
	palette.fill(0)
	var expected: PackedInt32Array = palette.export_states()
	for state_id: int in range(1, 4097):
		var index: int = state_id % 4096
		palette.set_state(index, state_id)
		expected[index] = state_id
		if state_id in [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096]:
			_expect(palette.export_states() == expected, "Palette resize preserves all words")
	for state_id: int in range(4097, 32769):
		palette.set_state(0, state_id)
	expected[0] = 32768
	palette.set_state(3, 32768)
	expected[3] = 32768
	_expect(palette.bits_per_index() == 16 and palette.export_states() == expected, "16-bit indices and signed highest bit")
	palette.compact()
	_expect(palette.export_states() == expected and palette.palette_size() <= 4096, "Compaction preserves cells")
	for index: int in range(STORAGE.CELL_COUNT):
		palette.set_state(index, 65535)
	palette.compact()
	_expect(palette.bits_per_index() == 0 and palette.palette_size() == 1 and palette.get_state(4095) == 65535, "Compaction restores uniform representation")

func _test_catalog() -> void:
	var catalog: AstraeonBlockCatalog = load("res://game/world/blocks/default_block_catalog.tres") as AstraeonBlockCatalog
	_expect(catalog != null, "Catalog resource loads")
	if catalog == null:
		return
	var registry: AstraeonBlockRegistry = REGISTRY.new()
	_expect(registry.build(catalog.definitions).is_empty() and registry.state_count() == 6, "Catalog has six states")
	var lamp: int = registry.find_state(&"astraeon:lamp")
	_expect(lamp >= 0 and registry.emission_for(lamp) == 15, "Lamp emission")
	_expect(not registry.has_collision(0) and registry.opacity_for(0) == 0, "Air flags")
	var opacity: PackedByteArray = registry.opacity_table()
	opacity[0] = 15
	_expect(registry.opacity_for(0) == 0, "Lookup table isolated")
	_expect(registry.find_state(&"astraeon:log", &"axis_y") >= 0, "Directional log")
