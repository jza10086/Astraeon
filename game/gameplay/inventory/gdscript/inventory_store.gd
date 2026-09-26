class_name AstraeonInventoryStore
extends RefCounted
## Write-ahead snapshots pair the player's inventory with unreconciled terrain edits.
## Two checked files protect interrupted writes. FileAccess.flush is not a hardware power-loss guarantee.
var error: String = ""
var pending: Dictionary[String, Dictionary] = {}
var _directory: String
var _identity: Dictionary
var _sequence: int = 0
var _inventory: AstraeonInventoryState

func open(directory: String, identity: Dictionary, inventory: AstraeonInventoryState) -> bool:
	_directory = directory
	_identity = identity
	_inventory = inventory
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return _fail("无法创建物品栏存档目录")
	var best: Dictionary = {}
	var found: bool = false
	for suffix: String in ["a", "b"]:
		var path: String = directory.path_join("inventory_" + suffix + ".json")
		if not FileAccess.file_exists(path):
			continue
		found = true
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			return _fail("无法读取物品栏存档")
		var parser: JSON = JSON.new()
		if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
			continue
		var envelope: Dictionary = parser.data
		var body: String = str(envelope.get("body", ""))
		if body.sha256_text() != envelope.get("sha256", "") or parser.parse(body) != OK or not parser.data is Dictionary:
			continue
		var data: Dictionary = parser.data
		if not AstraeonInventoryState._integer(data.get("version")) or int(data.get("version", -1)) != 1 or not _same_world(data.get("world")):
			return _fail("物品栏版本或世界标识不匹配")
		if not AstraeonInventoryState._integer(data.get("sequence")) or int(data.sequence) < 1:
			continue
		if best.is_empty() or int(data.sequence) > int(best.sequence):
			best = data
	if found and best.is_empty():
		return _fail("物品栏存档损坏，无法恢复")
	if not best.is_empty():
		if not best.get("inventory") is Dictionary or not inventory.restore(best.inventory) or not best.get("edits") is Dictionary:
			return _fail("物品栏包含未知物品或非法数量")
		for key: String in best.edits:
			var edit: Variant = best.edits[key]
			if not edit is Dictionary or not edit.get("position") is Array or edit.position.size() != 3 or not edit.get("state") is String:
				return _fail("地形恢复记录无效")
			for coordinate: Variant in edit.position:
				if not AstraeonInventoryState._integer(coordinate) or absf(float(coordinate)) > 1048576.0:
					return _fail("地形恢复坐标无效")
			pending[key] = edit
		_sequence = int(best.sequence)
	inventory.before_commit = commit
	return true

func commit(snapshot: Dictionary, context: Dictionary = {}) -> bool:
	if not error.is_empty():
		return false
	var next: Dictionary[String, Dictionary] = pending.duplicate(true)
	if not context.is_empty():
		var position: Vector3i = context.position
		next[str(position)] = {"position": [position.x, position.y, position.z], "state": context.state}
	if not _write(snapshot, next):
		return false
	pending = next
	return true

func checkpoint() -> bool:
	var empty: Dictionary[String, Dictionary] = {}
	if not error.is_empty() or not _write(_inventory.snapshot(), empty):
		return false
	pending.clear()
	return true

func _write(snapshot: Dictionary, edits: Dictionary[String, Dictionary]) -> bool:
	var body: String = JSON.stringify({"version": 1, "sequence": _sequence + 1, "world": _identity, "inventory": snapshot, "edits": edits})
	var path: String = _directory.path_join("inventory_" + ("a" if (_sequence + 1) % 2 == 0 else "b") + ".json")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _fail("无法写入物品栏存档")
	file.store_string(JSON.stringify({"body": body, "sha256": body.sha256_text()}))
	file.flush()
	if file.get_error() != OK:
		return _fail("物品栏存档写入失败")
	file.close()
	_sequence += 1
	return true

## Replay before terrain workers start; group by section and use native durable region writes.
func recover(stream: AstraeonNativeStream, generator: AstraeonNativeGenerator, state_keys: PackedStringArray) -> bool:
	var sections: Dictionary[Vector3i, VoxelBuffer] = {}
	for edit: Dictionary in pending.values():
		var values: Array = edit.position
		var position: Vector3i = Vector3i(int(values[0]), int(values[1]), int(values[2]))
		var state: int = state_keys.find(edit.state)
		if state < 0 or position.y < -64 or position.y >= 192:
			return _fail("恢复记录包含未知方块或越界坐标")
		var section: Vector3i = Vector3i(floori(position.x / 16.0), floori(position.y / 16.0), floori(position.z / 16.0))
		if not sections.has(section):
			var buffer: VoxelBuffer = VoxelBuffer.new()
			buffer.create(16, 16, 16)
			var result: int = stream.load_voxel_block(buffer, section, 0)
			if result == VoxelStream.RESULT_ERROR:
				return _fail(stream.get_last_error())
			if result == VoxelStream.RESULT_BLOCK_NOT_FOUND:
				generator.generate_block(buffer, Vector3(section * 16), 0)
			sections[section] = buffer
		sections[section].set_voxel_v(state, position - section * 16)
	for section: Vector3i in sections:
		stream.save_voxel_block(sections[section], section, 0)
		if not stream.get_last_error().is_empty():
			return _fail(stream.get_last_error())
	return true

func _fail(message: String) -> bool:
	error = message
	return false

func _same_world(value: Variant) -> bool:
	return value is Dictionary and AstraeonInventoryState._integer(value.get("generation")) and int(value.generation) == int(_identity.generation) and AstraeonInventoryState._integer(value.get("seed")) and AstraeonInventoryState._integer(value.get("layout")) and int(value.seed) == int(_identity.seed) and int(value.layout) == int(_identity.layout) and value.get("states") == _identity.states
