class_name AstraeonBlockStorage
extends RefCounted
## Common fixed 16^3 storage contract. State IDs are 0..65535; 0 is air.
## No registry lookups, lighting, rendering, scene nodes or thread synchronization here.
const EDGE: int = 16
const CELL_COUNT: int = 4096
const MAX_STATE_ID: int = 65535

func get_state(_index: int) -> int:
	assert(false, "Use a concrete storage backend.")
	return -1

## Invalid inputs return false and do not mutate storage.
func set_state(_index: int, _state_id: int) -> bool:
	return false

func fill(_state_id: int) -> bool:
	return false

## Owned copy, suitable for backend conversion. Not a durable save format.
func export_states() -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	result.resize(CELL_COUNT)
	for index: int in range(CELL_COUNT):
		result[index] = get_state(index)
	return result

## Validate the entire input before any mutation.
func import_states(values: PackedInt32Array) -> bool:
	if values.size() != CELL_COUNT:
		return false
	for value: int in values:
		if not valid_state(value):
			return false
	fill(values[0])
	for index: int in range(1, CELL_COUNT):
		set_state(index, values[index])
	return true

## Raw packed payload only; excludes objects, dictionaries, allocator overhead and capacity.
func payload_bytes() -> int:
	return 0

static func valid_state(state_id: int) -> bool:
	return state_id >= 0 and state_id <= MAX_STATE_ID

static func valid_index(index: int) -> bool:
	return index >= 0 and index < CELL_COUNT
