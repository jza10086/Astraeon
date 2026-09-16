extends SceneTree
## One backend/fixture per process. Driven by tools/run_block_storage_suite.py.
## All checks are outside timed regions. Memory markers are sampled by the parent process.
const FACTORY: Script = preload("res://game/world/blocks/storage/block_storage_factory.gd")
const STORAGE: Script = preload("res://game/world/blocks/storage/block_storage.gd")
const SECTION: Script = preload("res://game/world/blocks/block_section.gd")
const RESIDENT_COUNT: int = 1024
const READ_SECTIONS: int = 64
const EDIT_BATCH: int = 128
const EDIT_BATCHES: int = 512
var _backend: FACTORY.Backend = FACTORY.Backend.DIRECT32
var _fixture: String = "terrain"
var _seed: int = 73517
var _checksum: int = 0
var _failed: bool = false
var _values: PackedInt32Array = PackedInt32Array()
var _edit_indices: PackedInt32Array = PackedInt32Array()
var _edit_states: PackedInt32Array = PackedInt32Array()
var _locals: Array[Vector3i] = []
var _sections: Array[AstraeonBlockStorage] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--backend="):
			_backend = int(argument.trim_prefix("--backend=")) as FACTORY.Backend
		elif argument.begins_with("--fixture="):
			_fixture = argument.trim_prefix("--fixture=")
		elif argument.begins_with("--seed="):
			_seed = int(argument.trim_prefix("--seed="))
	if not _fixture in ["uniform", "terrain", "building"] or int(_backend) < 0 or int(_backend) > 2:
		printerr("Invalid benchmark arguments")
		quit(1)
		return
	_build_inputs()
	_warmup()
	print("BLOCK_MEMORY baseline " + str(OS.get_process_id()))
	OS.delay_msec(250)
	var start: int = Time.get_ticks_usec()
	for index: int in range(RESIDENT_COUNT):
		var section: AstraeonBlockStorage = FACTORY.create(_backend)
		section.import_states(_values)
		_sections.append(section)
	var load_usec: int = Time.get_ticks_usec() - start
	var payload: int = 0
	for section: AstraeonBlockStorage in _sections:
		payload += section.payload_bytes()
	print("BLOCK_MEMORY resident " + str(OS.get_process_id()))
	OS.delay_msec(250)
	_check(_sections[0].export_states() == _values and _sections[-1].export_states() == _values, "Resident data")
	var rows: Array[Dictionary] = []
	# Round 0 warms the operation paths; one measured round per process; the driver repeats each case in three processes.
	for round_index: int in range(2):
		var row: Dictionary[String, Variant] = _measure()
		if round_index > 0:
			row["round"] = round_index
			rows.append(row)
	_sections.clear()
	print("BLOCK_MEMORY released " + str(OS.get_process_id()))
	OS.delay_msec(250)
	print("BLOCK_RESULT " + JSON.stringify({
		"schema": 1, "backend": FACTORY.Backend.keys()[_backend], "fixture": _fixture,
		"seed": _seed, "resident_sections": RESIDENT_COUNT, "read_sections": READ_SECTIONS,
		"cell_count": STORAGE.CELL_COUNT, "load_1024_us": load_usec,
		"payload_bytes": payload, "rows": rows, "checksum": _checksum, "valid": not _failed,
		"engine": Engine.get_version_info()["string"], "debug_build": OS.is_debug_build()
	}))
	quit(1 if _failed else 0)

func _build_inputs() -> void:
	_values.resize(STORAGE.CELL_COUNT)
	var types: int = 1 if _fixture == "uniform" else (8 if _fixture == "terrain" else 64)
	for index: int in range(STORAGE.CELL_COUNT):
		# Spatial clusters, same fixture for every backend and repeat.
		var x: int = index & 15
		var y: int = (index >> 4) & 15
		var z: int = index >> 8
		_values[index] = 1 if types == 1 else ((y >> 1) if types == 8 else ((x >> 2) + 4 * (y >> 2) + 16 * (z >> 2)))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed
	for index: int in range(EDIT_BATCH * EDIT_BATCHES):
		var cell: int = rng.randi_range(0, 4095)
		_edit_indices.append(cell)
		_locals.append(SECTION.local_of(cell))
		_edit_states.append(rng.randi_range(0, maxi(1, types - 1)))

func _warmup() -> void:
	var data: AstraeonBlockStorage = FACTORY.create(_backend)
	data.import_states(_values)
	for index: int in range(4096):
		_checksum += data.get_state(index)
	data.fill(0)

func _measure() -> Dictionary[String, Variant]:
	var row: Dictionary[String, Variant] = {}
	var start: int = Time.get_ticks_usec()
	for pass_index: int in range(4):
		for section_index: int in range(READ_SECTIONS):
			var data: AstraeonBlockStorage = _sections[section_index * 16]
			for index: int in range(4096):
				_checksum += data.get_state(index)
	row["scan_1048576_us"] = Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	# Periodic local wrap resolves boundary neighbors from a different resident section.
	# This is a data-access workload, not a physical world topology or a mesher.
	for section_index: int in range(READ_SECTIONS):
		var data: AstraeonBlockStorage = _sections[section_index * 16]
		var neighbor: AstraeonBlockStorage = _sections[(section_index * 16 + 1) % RESIDENT_COUNT]
		for index: int in range(4096):
			var x: int = index & 15
			var y: int = (index >> 4) & 15
			var z: int = index >> 8
			_checksum += data.get_state(index - 1) if x > 0 else neighbor.get_state(index + 15)
			_checksum += data.get_state(index + 1) if x < 15 else neighbor.get_state(index - 15)
			_checksum += data.get_state(index - 16) if y > 0 else neighbor.get_state(index + 240)
			_checksum += data.get_state(index + 16) if y < 15 else neighbor.get_state(index - 240)
			_checksum += data.get_state(index - 256) if z > 0 else neighbor.get_state(index + 3840)
			_checksum += data.get_state(index + 256) if z < 15 else neighbor.get_state(index - 3840)
	row["neighbors_1572864_us"] = Time.get_ticks_usec() - start
	var bulk_data: AstraeonBlockStorage = FACTORY.create(_backend)
	start = Time.get_ticks_usec()
	for index: int in range(128):
		bulk_data.import_states(_values)
	row["import_128_us"] = Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	for index: int in range(128):
		var snapshot: PackedInt32Array = bulk_data.export_states()
		_checksum += snapshot[0]
	row["export_128_us"] = Time.get_ticks_usec() - start
	var section: AstraeonBlockSection = SECTION.new()
	section.configure(Vector3i.ZERO, 65536, _backend)
	section.import_states(_values)
	# Prime all ordinary edit states outside the timed region, including air in uniform data.
	for state_id: int in range(2 if _fixture == "uniform" else (8 if _fixture == "terrain" else 64)):
		section.set_state(Vector3i.ZERO, state_id)
	section.set_state(Vector3i.ZERO, _values[0])
	var expected: PackedInt32Array = _values.duplicate()
	var edits: PackedInt64Array = PackedInt64Array()
	for batch: int in range(EDIT_BATCHES):
		start = Time.get_ticks_usec()
		for offset: int in range(EDIT_BATCH):
			var operation: int = batch * EDIT_BATCH + offset
			section.set_state(_locals[operation], _edit_states[operation])
		edits.append(Time.get_ticks_usec() - start)
	for operation: int in range(_edit_indices.size()):
		expected[_edit_indices[operation]] = _edit_states[operation]
	_check(section.export_states() == expected, "Edit replay")
	row["edit_batch_128_us"] = edits
	var growth: PackedInt64Array = PackedInt64Array()
	# Each event begins from a fresh fixture; one new state may grow the palette width.
	for trial: int in range(32):
		var fresh: AstraeonBlockStorage = FACTORY.create(_backend)
		fresh.import_states(_values)
		start = Time.get_ticks_usec()
		fresh.set_state(4095, 65000)
		growth.append(Time.get_ticks_usec() - start)
		_check(fresh.get_state(4095) == 65000 and fresh.get_state(0) == _values[0], "New state preserves neighbors")
	row["new_state_us"] = growth
	return row

func _check(condition: bool, label: String) -> void:
	if not condition:
		_failed = true
		printerr("BENCHMARK CHECK FAILED: ", label)
