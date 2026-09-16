class_name AstraeonWorldStore
extends RefCounted
## Single I/O owner via mutex. Alternating validated snapshots retain the previous commit.
## flush is not a promise of physical power-loss durability on every filesystem.
const CODEC: Script = preload("res://game/world/persistence/section_codec.gd")
var root: String
var organization: int = 1
var encoding: int = 0
var disk_to_runtime: PackedInt32Array = PackedInt32Array()
var runtime_to_disk: PackedInt32Array = PackedInt32Array()
var _identity: String
var _read_bytes: int = 0
var _mutex: Mutex = Mutex.new()
var _indexes: Dictionary[String, Dictionary] = {}
var _index_order: Array[String] = []
var _files: Dictionary[String, FileAccess] = {}
var _file_order: Array[String] = []

func configure(path: String, config: Dictionary, registry: AstraeonBlockRegistry, file_mode: int, codec_mode: int) -> String:
	if file_mode not in [0, 1] or codec_mode < 0 or codec_mode > 4:
		return "Unsupported storage mode"
	root = path
	organization = file_mode
	encoding = codec_mode
	var error: Error = DirAccess.make_dir_recursive_absolute(root)
	if error != OK:
		return "Cannot create world directory: " + str(error)
	var manifest: Dictionary = _latest(root.path_join("world"))
	if manifest.has("error"):
		return manifest.error
	var keys: PackedStringArray = PackedStringArray()
	var sequence: int = 0
	if not manifest.is_empty():
		if manifest.get("format") != 1 or manifest.get("config") != config or manifest.get("organization") != organization or not manifest.get("states") is PackedStringArray:
			return "World format/configuration mismatch; use a new world or explicit migration"
		keys = manifest.states
		sequence = int(manifest.sequence)
	for key: String in keys:
		var parts: PackedStringArray = key.split("/")
		if parts.size() != 2:
			return "Invalid stable state key"
		var runtime_id: int = registry.find_state(StringName(parts[0]), StringName(parts[1]))
		if runtime_id < 0:
			return "Missing block state: " + key
		disk_to_runtime.append(runtime_id)
	runtime_to_disk.resize(registry.state_count())
	for runtime_id: int in range(registry.state_count()):
		var key: String = registry.stable_key(runtime_id)
		var disk_id: int = keys.find(key)
		if disk_id == -1:
			disk_id = keys.size()
			keys.append(key)
			disk_to_runtime.append(runtime_id)
		runtime_to_disk[runtime_id] = disk_id
	if keys.size() > 65536:
		return "Persistent state table exhausted"
	_identity = str(manifest.get("world_id", str(Time.get_unix_time_from_system()) + "-" + str(Time.get_ticks_usec())))
	var updated: Dictionary = {"format": 1, "sequence": sequence + 1, "world_id": _identity, "config": config, "organization": organization, "states": keys}
	return _write_snapshot(root.path_join("world"), updated)

func _write_snapshot(base: String, value: Dictionary, metrics: Dictionary = {}) -> String:
	var path: String = base + "." + str(int(value.sequence) % 2)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Open for write failed: " + path
	var encode_started: int = Time.get_ticks_usec()
	var bytes: PackedByteArray = CODEC.envelope(value)
	metrics["envelope_us"] = Time.get_ticks_usec() - encode_started
	var write_started: int = Time.get_ticks_usec()
	file.store_buffer(bytes)
	metrics["write_us"] = Time.get_ticks_usec() - write_started
	var flush_started: int = Time.get_ticks_usec()
	file.flush()
	metrics["flush_us"] = Time.get_ticks_usec() - flush_started
	metrics["committed_bytes"] = bytes.size()
	var error: Error = file.get_error()
	file.close()
	var verify_started: int = Time.get_ticks_usec()
	var verified: Dictionary = _read_snapshot(path)
	metrics["commit_verify_us"] = Time.get_ticks_usec() - verify_started
	if error != OK or verified.is_empty():
		return "Commit verification failed: " + path
	return ""

func _read_snapshot(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > CODEC.LIMIT * 16:
		return {}
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	_read_bytes += bytes.size()
	return CODEC.unwrap(bytes)

func _latest(base: String) -> Dictionary:
	var a: Dictionary = _read_snapshot(base + ".0")
	var b: Dictionary = _read_snapshot(base + ".1")
	if a.is_empty() and b.is_empty():
		return {"error": "Both snapshots unreadable: " + base} if FileAccess.file_exists(base + ".0") or FileAccess.file_exists(base + ".1") else {}
	var selected: Dictionary = a if int(a.get("sequence", -1)) >= int(b.get("sequence", -1)) else b
	if (a.is_empty() and FileAccess.file_exists(base + ".0")) or (b.is_empty() and FileAccess.file_exists(base + ".1")):
		selected["_recovered"] = true
	return selected

func _key(coordinate: Vector3i) -> String:
	return "%d_%d_%d" % [coordinate.x, coordinate.y, coordinate.z]

func _region(coordinate: Vector3i) -> String:
	return "%d_%d" % [coordinate.x >> 4, coordinate.z >> 4]

func _index(region: String) -> Dictionary:
	if not _indexes.has(region):
		var value: Dictionary = _latest(root.path_join("r_" + region + "_index"))
		if value.is_empty():
			if FileAccess.file_exists(root.path_join("r_" + region + ".bin")):
				return {"error": "Region exists without recoverable index"}
			value = {"sequence": 0, "entries": {}}
		if not value.has("error") and (not value.get("entries") is Dictionary or not value.get("sequence") is int):
			return {"error": "Malformed region index"}
		while _index_order.size() >= 64:
			_indexes.erase(_index_order.pop_front())
		_indexes[region] = value
		_index_order.append(region)
	return _indexes[region]

func save_section(coordinate: Vector3i, revision: int, states: PackedInt32Array) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var persistent: PackedInt32Array = states.duplicate()
	for index: int in range(persistent.size()):
		if persistent[index] < 0 or persistent[index] >= runtime_to_disk.size():
			return {"error": "Invalid runtime state"}
		persistent[index] = runtime_to_disk[persistent[index]]
	var mapped: int = Time.get_ticks_usec()
	var encoded: Dictionary = CODEC.encode(persistent, encoding)
	if encoded.has("error"):
		return encoded
	encoded["save_map_us"] = mapped - started
	var record: Dictionary = {"world_id": _identity, "coordinate": coordinate, "revision": revision, "record": encoded.record}
	var lock_requested: int = Time.get_ticks_usec()
	_mutex.lock()
	var locked: int = Time.get_ticks_usec()
	_read_bytes = 0
	var error: String = ""
	var io_metrics: Dictionary = {}
	if organization == 0:
		var directory: String = root.path_join("s_" + _region(coordinate))
		var dir_error: Error = DirAccess.make_dir_recursive_absolute(directory)
		var base: String = directory.path_join(_key(coordinate))
		var old: Dictionary = _latest(base)
		if dir_error != OK or old.has("error"):
			error = "Section directory or previous snapshot unavailable"
		else:
			record["sequence"] = int(old.get("sequence", 0)) + 1
			error = _write_snapshot(base, record, io_metrics)
	else:
		var region: String = _region(coordinate)
		var index: Dictionary = _index(region)
		if index.has("error"):
			error = index.error
		else:
			var path: String = root.path_join("r_" + region + ".bin")
			var file: FileAccess = _region_file(path, true)
			if file == null:
				error = "Region open failed"
			else:
				file.seek_end()
				var offset: int = file.get_position()
				var bytes: PackedByteArray = CODEC.envelope(record)
				var write_started: int = Time.get_ticks_usec()
				file.store_buffer(bytes)
				io_metrics["region_write_us"] = Time.get_ticks_usec() - write_started
				var flush_started: int = Time.get_ticks_usec()
				file.flush()
				io_metrics["region_flush_us"] = Time.get_ticks_usec() - flush_started
				io_metrics["region_bytes"] = bytes.size()
				var io_error: Error = file.get_error()
				if io_error != OK:
					error = "Region write failed"
				else:
					var next: Dictionary = index.duplicate(true)
					next.sequence = int(index.sequence) + 1
					# Keep previous extent for recovery even after unrelated index commits.
					var previous: Dictionary = index.entries.get(_key(coordinate), {})
					next.entries[_key(coordinate)] = {"offset": offset, "length": bytes.size(), "previous": {"offset": previous.get("offset", -1), "length": previous.get("length", 0)}}
					error = _write_snapshot(root.path_join("r_" + region + "_index"), next, io_metrics)
					if error.is_empty():
						_indexes[region] = next
	var finished: int = Time.get_ticks_usec()
	io_metrics["readback_bytes"] = _read_bytes
	_mutex.unlock()
	encoded.erase("record")
	encoded.merge(io_metrics)
	encoded["io_lock_wait_us"] = locked - lock_requested
	encoded["write_commit_us"] = finished - locked
	encoded["save_total_us"] = finished - started
	if not error.is_empty():
		encoded["error"] = error
	return encoded

func _region_file(path: String, create: bool) -> FileAccess:
	if _files.has(path):
		_file_order.erase(path)
		_file_order.append(path)
		return _files[path]
	if not create and not FileAccess.file_exists(path):
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE_READ)
	if file == null:
		return null
	while _file_order.size() >= 16:
		var oldest: String = _file_order.pop_front()
		_files[oldest].close()
		_files.erase(oldest)
	_files[path] = file
	_file_order.append(path)
	return file

func _read_extent(path: String, extent: Dictionary) -> Dictionary:
	var file: FileAccess = _region_file(path, false)
	var offset: int = int(extent.get("offset", -1))
	var length: int = int(extent.get("length", 0))
	if file == null or offset < 0 or length <= 0 or length > CODEC.LIMIT or offset + length > file.get_length():
		return {}
	file.seek(offset)
	var bytes: PackedByteArray = file.get_buffer(length)
	_read_bytes += bytes.size()
	return CODEC.unwrap(bytes)

func load_section(coordinate: Vector3i) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	_mutex.lock()
	var locked: int = Time.get_ticks_usec()
	_read_bytes = 0
	var record: Dictionary = {}
	var recovered: bool = false
	if organization == 0:
		record = _latest(root.path_join("s_" + _region(coordinate)).path_join(_key(coordinate)))
		recovered = bool(record.get("_recovered", false))
	else:
		var region: String = _region(coordinate)
		var index: Dictionary = _index(region)
		if index.has("error"):
			record = index
		elif index.get("_recovered", false) and not index.entries.has(_key(coordinate)):
			record = {"error": "Recovered index cannot prove section was never saved"}
		elif index.entries.has(_key(coordinate)):
			recovered = bool(index.get("_recovered", false))
			var extent: Dictionary = index.entries[_key(coordinate)]
			var path: String = root.path_join("r_" + region + ".bin")
			record = _read_extent(path, extent)
			if record.is_empty():
				record = _read_extent(path, extent.get("previous", {}))
				recovered = not record.is_empty()
			if record.is_empty():
				record = {"error": "Region record and backup unreadable"}
	var read_at: int = Time.get_ticks_usec()
	var bytes_read: int = _read_bytes
	_mutex.unlock()
	if record.has("error"):
		return record
	if record.is_empty():
		return {"missing": true, "read_bytes": bytes_read, "read_us": read_at - locked, "io_lock_wait_us": locked - started}
	if record.get("world_id") != _identity or record.get("coordinate") != coordinate or not record.get("record") is Dictionary:
		return {"error": "Section identity mismatch"}
	var decoded: Dictionary = CODEC.decode(record.record, disk_to_runtime)
	decoded["read_us"] = read_at - locked
	decoded["read_bytes"] = bytes_read
	decoded["io_lock_wait_us"] = locked - started
	decoded["load_total_us"] = Time.get_ticks_usec() - started
	decoded["recovered"] = recovered
	return decoded




