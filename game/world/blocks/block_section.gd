class_name AstraeonBlockSection
extends RefCounted
## One 16^3 section, independent of rendering/lighting. X varies fastest, then Y, then Z.
## Single-owner mutable data; background jobs must receive independent snapshots.
const FACTORY: Script = preload("res://game/world/blocks/storage/block_storage_factory.gd")
const STORAGE: Script = preload("res://game/world/blocks/storage/block_storage.gd")
var _coordinate: Vector3i
var _storage: AstraeonBlockStorage
var _state_count: int = 0
var _revision: int = 0

## Registry count restricts writes to registered IDs. Configure only once.
func configure(section_coordinate: Vector3i, state_count: int, backend: FACTORY.Backend) -> bool:
	if _storage != null or state_count < 1 or state_count > STORAGE.MAX_STATE_ID + 1:
		return false
	var candidate: AstraeonBlockStorage = FACTORY.create(backend)
	if candidate == null:
		return false
	_coordinate = section_coordinate
	_state_count = state_count
	_storage = candidate
	return true

func coordinate() -> Vector3i:
	return _coordinate

func revision() -> int:
	return _revision

func get_state(local: Vector3i) -> int:
	if _storage == null or not contains_local(local):
		return -1
	return _storage.get_state(index_of(local))

## Returns success, including unchanged writes. Revision only changes with content.
func set_state(local: Vector3i, state_id: int) -> bool:
	if _storage == null or not contains_local(local) or state_id < 0 or state_id >= _state_count:
		return false
	var index: int = index_of(local)
	if _storage.get_state(index) != state_id:
		_storage.set_state(index, state_id)
		_revision += 1
	return true

## Transactional whole-section replacement: invalid input leaves data/revision unchanged.
func import_states(values: PackedInt32Array) -> bool:
	if _storage == null or values.size() != STORAGE.CELL_COUNT:
		return false
	for value: int in values:
		if value < 0 or value >= _state_count:
			return false
	if values != _storage.export_states():
		_storage.import_states(values)
		_revision += 1
	return true

func export_states() -> PackedInt32Array:
	if _storage == null:
		return PackedInt32Array()
	return _storage.export_states()

## Conversion does not change content revision.
func change_backend(backend: FACTORY.Backend) -> bool:
	var candidate: AstraeonBlockStorage = FACTORY.convert(_storage, backend)
	if candidate == null:
		return false
	_storage = candidate
	return true

func payload_bytes() -> int:
	return 0 if _storage == null else _storage.payload_bytes()

static func contains_local(local: Vector3i) -> bool:
	return local.x >= 0 and local.y >= 0 and local.z >= 0 and local.x < 16 and local.y < 16 and local.z < 16

static func index_of(local: Vector3i) -> int:
	assert(contains_local(local))
	return local.x + 16 * (local.y + 16 * local.z)

static func local_of(index: int) -> Vector3i:
	assert(STORAGE.valid_index(index))
	return Vector3i(index & 15, (index >> 4) & 15, index >> 8)

## Arithmetic right shift is floor division by 16, including negative coordinates.
static func section_of(world: Vector3i) -> Vector3i:
	return Vector3i(world.x >> 4, world.y >> 4, world.z >> 4)

static func world_to_local(world: Vector3i) -> Vector3i:
	return world - section_of(world) * 16
