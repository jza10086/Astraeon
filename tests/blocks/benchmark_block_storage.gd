extends SceneTree
## Opt-in microbenchmark, not a terrain FPS benchmark. No backend is selected automatically.
const FACTORY: Script = preload("res://game/world/blocks/storage/block_storage_factory.gd")
const STORAGE: Script = preload("res://game/world/blocks/storage/block_storage.gd")
var _checksum: int = 0

func _initialize() -> void:
	var rounds: int = 5
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--rounds="):
			rounds = clampi(int(argument.trim_prefix("--rounds=")), 1, 100)
	var rows: Array[Dictionary] = []
	# Fixture generation is outside the measured region and identical for all backends.
	for fixture: String in ["uniform", "layered", "diverse"]:
		var values: PackedInt32Array = PackedInt32Array()
		values.resize(STORAGE.CELL_COUNT)
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 73517
		for index: int in range(STORAGE.CELL_COUNT):
			match fixture:
				"uniform":
					values[index] = 1
				"layered":
					values[index] = (index >> 8) % 8
				"diverse":
					values[index] = rng.randi_range(0, 65535)
		var edit_indices: PackedInt32Array = PackedInt32Array()
		var edit_values: PackedInt32Array = PackedInt32Array()
		for operation: int in range(8192):
			edit_indices.append(rng.randi_range(0, 4095))
			edit_values.append(rng.randi_range(0, 65535))
		for round_index: int in range(rounds + 1):
			# Rotate order; round zero is an unreported warmup for each fixture.
			for offset: int in range(3):
				var backend: FACTORY.Backend = ((offset + round_index) % 3) as FACTORY.Backend
				var data: AstraeonBlockStorage = FACTORY.create(backend)
				var start: int = Time.get_ticks_usec()
				data.import_states(values)
				var import_usec: int = Time.get_ticks_usec() - start
				var initial_payload: int = data.payload_bytes()
				start = Time.get_ticks_usec()
				for pass_index: int in range(8):
					for index: int in range(STORAGE.CELL_COUNT):
						_checksum += data.get_state(index)
				var scan_usec: int = Time.get_ticks_usec() - start
				start = Time.get_ticks_usec()
				for index: int in edit_indices:
					_checksum += data.get_state(index)
				var random_read_usec: int = Time.get_ticks_usec() - start
				start = Time.get_ticks_usec()
				for operation: int in range(edit_indices.size()):
					data.set_state(edit_indices[operation], edit_values[operation])
				var edit_usec: int = Time.get_ticks_usec() - start
				var edited_payload: int = data.payload_bytes()
				start = Time.get_ticks_usec()
				var snapshot: PackedInt32Array = data.export_states()
				var export_usec: int = Time.get_ticks_usec() - start
				_checksum += snapshot[0]
				start = Time.get_ticks_usec()
				data.fill(1)
				var fill_usec: int = Time.get_ticks_usec() - start
				if round_index > 0:
					rows.append({
						"fixture": fixture, "backend": FACTORY.Backend.keys()[backend],
						"round": round_index, "import_us": import_usec,
						"scan_32768_reads_us": scan_usec, "random_8192_reads_us": random_read_usec,
						"random_8192_edits_us": edit_usec, "export_us": export_usec,
						"fill_us": fill_usec, "initial_payload_bytes": initial_payload,
						"edited_payload_bytes": edited_payload
					})
	print(JSON.stringify({
		"schema": 1, "engine": Engine.get_version_info()["string"],
		"debug_build": OS.is_debug_build(), "rounds": rounds, "checksum": _checksum,
		"scope": "GDScript data microbenchmark; packed payload is not total memory; no FPS, mesh, collision or light work.",
		"rows": rows
	}))
	quit(0)
