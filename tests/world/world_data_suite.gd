extends SceneTree
## Explicit correctness and data-layer entry. Nothing runs without --run.
const CONFIG: Script = preload("res://game/world/generation/world_config.gd")
const GENERATOR: Script = preload("res://game/world/generation/terrain_generator.gd")
const CATALOG: Script = preload("res://game/world/generation/terrain_catalog.gd")
const CODEC: Script = preload("res://game/world/persistence/section_codec.gd")
const STORE: Script = preload("res://game/world/persistence/world_store.gd")
const SECTION: Script = preload("res://game/world/blocks/block_section.gd")
var _options: Dictionary[String, String] = {}
var _checks: int = 0
var _failures: PackedStringArray = PackedStringArray()
var _rows: Array[Dictionary] = []
var _output: String
var _registry: AstraeonBlockRegistry
var _ids: PackedInt32Array

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--"):
			var parts: PackedStringArray = argument.substr(2).split("=", true, 1)
			_options[parts[0]] = parts[1] if parts.size() == 2 else "true"
	if not _options.has("run"):
		print("World tests are armed only by --run; no tests executed.")
		quit()
		return
	_output = _options.get("output", "res://tmp/world_data/" + str(Time.get_ticks_usec()))
	if DirAccess.make_dir_recursive_absolute(_output) != OK:
		quit(2)
		return
	_registry = CATALOG.build_registry()
	_ids = CATALOG.ids(_registry)
	if _options.get("mode", "correctness") == "correctness":
		_correctness()
	else:
		_benchmark()
	var result: Dictionary = {"checks": _checks, "failures": _failures, "rows": _rows, "engine": Engine.get_version_info(), "options": _options, "status": "passed" if _failures.is_empty() else "failed"}
	var file: FileAccess = FileAccess.open(_output.path_join("data.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
	print("WORLD_DATA_RESULT " + JSON.stringify({"checks": _checks, "failures": _failures, "rows": _rows.size()}))
	quit(0 if _failures.is_empty() else 2)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)

func _generator(mode: int) -> AstraeonTerrainGenerator:
	var settings: AstraeonWorldConfig = CONFIG.new()
	settings.generation_mode = mode
	settings.layout = int(_options.get("layout", "1"))
	var generator: AstraeonTerrainGenerator = GENERATOR.new()
	_check(generator.configure(settings, _ids), "generator configuration")
	return generator

func _correctness() -> void:
	var g1: AstraeonTerrainGenerator = _generator(0)
	var g2: AstraeonTerrainGenerator = _generator(1)
	var g3: AstraeonTerrainGenerator = _generator(2)
	var coordinates: Array[Vector3i] = [Vector3i(-17, 0, -1), Vector3i(-1, 2, 0), Vector3i(0, -4, 0), Vector3i(4, 2, 4), Vector3i(20, 2, 4), Vector3i(36, 6, 4), Vector3i(52, 0, 4), Vector3i(0, 12, 0)]
	for coordinate: Vector3i in coordinates:
		var reference: PackedInt32Array = g1.generate(coordinate, _registry.state_count(), 1).section.export_states()
		for backend: int in range(3):
			_check(g1.generate(coordinate, _registry.state_count(), backend).section.export_states() == reference, "backend equality " + str(coordinate))
			_check(g2.generate(coordinate, _registry.state_count(), backend).section.export_states() == reference, "G1/G2 equality " + str(coordinate))
		var interpolated: PackedInt32Array = g3.generate(coordinate, _registry.state_count(), 1).section.export_states()
		_check(interpolated == g3.generate(coordinate, _registry.state_count(), 1).section.export_states(), "G3 deterministic")
	coordinates.reverse()
	for coordinate: Vector3i in coordinates:
		_check(g1.generate(coordinate, _registry.state_count(), 1).section.export_states() == g2.generate(coordinate, _registry.state_count(), 1).section.export_states(), "request order invariant")
	var values: PackedInt32Array = PackedInt32Array()
	values.resize(4096)
	var identity: PackedInt32Array = PackedInt32Array()
	identity.resize(65536)
	for index: int in range(identity.size()):
		identity[index] = index
	for mode: int in range(5):
		for diversity: int in [1, 2, 6, 17, 256, 4096]:
			for index: int in range(values.size()):
				values[index] = 65535 if diversity == 1 else index % diversity
			var encoded: Dictionary = CODEC.encode(values, mode)
			var decoded: Dictionary = CODEC.decode(encoded.record, identity)
			_check(decoded.get("states") == values, "codec round trip %d/%d" % [mode, diversity])
			var corrupt: Dictionary = encoded.record.duplicate(true)
			corrupt.sha256 = PackedByteArray([0])
			_check(CODEC.decode(corrupt, identity).has("error"), "checksum rejection")
		var swapped: PackedInt32Array = identity.duplicate()
		swapped[0] = 1
		swapped[1] = 0
		values.fill(0)
		var remapped: Dictionary = CODEC.decode(CODEC.encode(values, mode).record, swapped)
		_check(remapped.states[0] == 1 and remapped.states[4095] == 1, "persistent ID remapping")
	for organization: int in range(2):
		for mode: int in range(5):
			var path: String = _output.path_join("world_%d_%d" % [organization, mode])
			var store: AstraeonWorldStore = STORE.new()
			_check(store.configure(path, g1.config.snapshot(), _registry, organization, mode).is_empty(), "world configure")
			var coordinate: Vector3i = Vector3i(-1, 2, -17)
			_check(store.load_section(coordinate).get("missing", false), "missing distinct from corrupt")
			var generated: AstraeonBlockSection = g1.generate(coordinate, _registry.state_count(), 1).section
			var original: PackedInt32Array = generated.export_states()
			_check(not store.save_section(coordinate, 1, original).has("error"), "initial save")
			_check(store.load_section(coordinate).get("states") == original, "saved terrain equality")
			var snapshot: PackedInt32Array = generated.export_states()
			generated.set_state(Vector3i.ZERO, _ids[4])
			_check(snapshot == original, "snapshot isolated from subsequent edit")
			var air: PackedInt32Array = PackedInt32Array()
			air.resize(4096)
			air.fill(_ids[0])
			_check(not store.save_section(coordinate, 2, air).has("error"), "save all-air")
			var reopened: AstraeonWorldStore = STORE.new()
			_check(reopened.configure(path, g1.config.snapshot(), _registry, organization, mode).is_empty(), "reopen manifest")
			_check(reopened.load_section(coordinate).get("states") == air, "excavated section survives reopen")
			# Damage only the latest record. The previous successful snapshot must recover.
			var damaged_path: String = path.path_join("s_-1_-2/-1_2_-17.0") if organization == 0 else path.path_join("r_-1_-2.bin")
			var file: FileAccess = FileAccess.open(damaged_path, FileAccess.READ_WRITE)
			_check(file != null, "fault injection target exists")
			if file != null:
				file.seek(file.get_length() - 1)
				var byte: int = file.get_8()
				file.seek(file.get_length() - 1)
				file.store_8(byte ^ 255)
				file.close()
				_check(reopened.load_section(coordinate).get("states") == original, "previous record recovery")
	_registry_migration(g1)
	_quality(g1, g3)

func _quality(reference: AstraeonTerrainGenerator, approximate: AstraeonTerrainGenerator) -> void:
	var differences: Array[float] = []
	var sea_changes: int = 0
	var total: float = 0.0
	for cz: int in [-2, 0, 4]:
		for cx: int in range(-4, 68):
			var a: PackedInt32Array = reference.column(Vector2i(cx, cz))
			var b: PackedInt32Array = approximate.column(Vector2i(cx, cz))
			for index: int in range(256):
				var difference: float = absf(float(a[index * 2] - b[index * 2]))
				differences.append(difference)
				total += difference
				if (a[index * 2] < reference.config.sea_level) != (b[index * 2] < reference.config.sea_level):
					sea_changes += 1
	differences.sort()
	_rows.append({"kind": "quality", "samples": differences.size(), "mean_height_error": total / differences.size(), "p95_height_error": differences[int(0.95 * (differences.size() - 1))], "max_height_error": differences[-1], "sea_classification_changes": sea_changes})

func _benchmark() -> void:
	var backend: int = int(_options.get("backend", "1"))
	var mode: int = int(_options.get("generator", "0"))
	var codec: int = int(_options.get("codec", "0"))
	var organization: int = int(_options.get("files", "1"))
	var count: int = clampi(int(_options.get("count", "64")), 1, 2048)
	var generator: AstraeonTerrainGenerator = _generator(mode)
	var store: AstraeonWorldStore = STORE.new()
	_check(store.configure(_output.path_join("world"), generator.config.snapshot(), _registry, organization, codec).is_empty(), "benchmark store")
	if not _failures.is_empty():
		return
	for index: int in range(count):
		var cx: int = 4 + (int(index / 4) % 4) * 16
		var cz: int = 4 + int(index / 16)
		var surface_y: int = int(floor(generator.sample_exact(cx * 16, cz * 16).x)) >> 4
		var coordinate: Vector3i = Vector3i(cx, surface_y - 1 + index % 4, cz)
		var started: int = Time.get_ticks_usec()
		var generated: Dictionary = generator.generate(coordinate, _registry.state_count(), backend)
		var section: AstraeonBlockSection = generated.section
		generated.erase("section")
		generated["kind"] = "generation"
		generated["warmup"] = index < 8
		generated["coordinate"] = str(coordinate)
		generated["total_us"] = Time.get_ticks_usec() - started
		generated["payload_bytes"] = section.payload_bytes()
		_rows.append(generated)
		if _options.get("mode") == "generation":
			continue
		var edit_started: int = Time.get_ticks_usec()
		for edit_index: int in range(128):
			var local: Vector3i = SECTION.local_of((edit_index * 977 + index * 31) % 4096)
			section.set_state(local, _ids[0] if edit_index % 2 == 0 else _ids[1])
		_rows.append({"kind": "edit", "edit_us": Time.get_ticks_usec() - edit_started, "operations": 128, "warmup": index < 8})
		var snapshot_started: int = Time.get_ticks_usec()
		var snapshot: PackedInt32Array = section.export_states()
		var snapshot_us: int = Time.get_ticks_usec() - snapshot_started
		var saved: Dictionary = store.save_section(coordinate, section.revision(), snapshot)
		saved["kind"] = "save"
		saved["warmup"] = index < 8
		saved["snapshot_us"] = snapshot_us
		_rows.append(saved)
		_check(not saved.has("error"), "benchmark save")
		var loaded: Dictionary = store.load_section(coordinate)
		_check(loaded.get("states") == snapshot, "benchmark load equality")
		if loaded.has("states"):
			var import_started: int = Time.get_ticks_usec()
			var restored: AstraeonBlockSection = SECTION.new()
			_check(restored.configure(coordinate, _registry.state_count(), backend) and restored.import_states(loaded.states), "benchmark backend import")
			loaded["backend_import_us"] = Time.get_ticks_usec() - import_started
		loaded.erase("states")
		loaded["kind"] = "load_os_cache_warm"
		loaded["warmup"] = index < 8
		_rows.append(loaded)


func _registry_migration(generator: AstraeonTerrainGenerator) -> void:
	var path: String = _output.path_join("registry_migration")
	var store: AstraeonWorldStore = STORE.new()
	_check(store.configure(path, generator.config.snapshot(), _registry, 0, 0).is_empty(), "registry original configure")
	var values: PackedInt32Array = PackedInt32Array()
	values.resize(4096)
	values.fill(_registry.find_state(&"astraeon:stone"))
	_check(not store.save_section(Vector3i.ZERO, 1, values).has("error"), "registry original save")
	var definitions: Array[AstraeonBlockDefinition] = []
	var names: Array[String] = CATALOG.KEYS.duplicate()
	names.append("aaa")
	for name: String in names:
		var definition: AstraeonBlockDefinition = CATALOG.DEFINITION.new()
		definition.key = StringName("astraeon:" + name)
		definition.collision_enabled = name != "air"
		definition.light_opacity = 0 if name == "air" else 15
		definitions.append(definition)
	var extended: AstraeonBlockRegistry = CATALOG.REGISTRY.new()
	_check(extended.build(definitions).is_empty(), "extended registry")
	var reopened: AstraeonWorldStore = STORE.new()
	_check(reopened.configure(path, generator.config.snapshot(), extended, 0, 0).is_empty(), "append persistent registry")
	var loaded: Dictionary = reopened.load_section(Vector3i.ZERO)
	values.fill(extended.find_state(&"astraeon:stone"))
	_check(loaded.get("states") == values, "registry reorder remapping")
	var missing: AstraeonWorldStore = STORE.new()
	_check(not missing.configure(path, generator.config.snapshot(), _registry, 0, 0).is_empty(), "missing persistent state blocks overwrite")

