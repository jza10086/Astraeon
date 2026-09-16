class_name AstraeonDirect32Storage
extends "res://game/world/blocks/storage/block_storage.gd"
## Baseline: one native packed 32-bit integer per cell.
var _values: PackedInt32Array = PackedInt32Array()

func _init() -> void:
	_values.resize(CELL_COUNT)
	_values.fill(0)

func get_state(index: int) -> int:
	assert(valid_index(index))
	return _values[index]

func set_state(index: int, state_id: int) -> bool:
	if not valid_index(index) or not valid_state(state_id):
		return false
	_values[index] = state_id
	return true

func fill(state_id: int) -> bool:
	if not valid_state(state_id):
		return false
	_values.fill(state_id)
	return true

func payload_bytes() -> int:
	return _values.size() * 4
