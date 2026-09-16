class_name AstraeonDirect16Storage
extends "res://game/world/blocks/storage/block_storage.gd"
## Two little-endian bytes per cell. No PackedUInt16Array is assumed.
var _values: PackedByteArray = PackedByteArray()

func _init() -> void:
	_values.resize(CELL_COUNT * 2)
	_values.fill(0)

func get_state(index: int) -> int:
	assert(valid_index(index))
	return _values.decode_u16(index * 2)

func set_state(index: int, state_id: int) -> bool:
	if not valid_index(index) or not valid_state(state_id):
		return false
	_values.encode_u16(index * 2, state_id)
	return true

func fill(state_id: int) -> bool:
	if not valid_state(state_id):
		return false
	if state_id == 0:
		_values.fill(0)
	else:
		for index: int in range(CELL_COUNT):
			_values.encode_u16(index * 2, state_id)
	return true

func payload_bytes() -> int:
	return _values.size()
