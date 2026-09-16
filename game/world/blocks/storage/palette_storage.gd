class_name AstraeonPaletteStorage
extends "res://game/world/blocks/storage/block_storage.gd"
## Uniform sections use one palette entry and zero words. Otherwise use 1..16 bits/index.
## Indices never cross signed 64-bit word boundaries; shifts are masked on read.
## Removed entries remain until explicit compact(); no hidden full scan on ordinary writes.
var _palette: PackedInt32Array = PackedInt32Array([0])
var _indices: Dictionary[int, int] = {0: 0}
var _words: PackedInt64Array = PackedInt64Array()
var _bits: int = 0

func get_state(index: int) -> int:
	assert(valid_index(index))
	if _bits == 0:
		return _palette[0]
	@warning_ignore("integer_division")
	var slots: int = 64 / _bits
	@warning_ignore("integer_division")
	var word_index: int = index / slots
	var palette_index: int = (_words[word_index] >> ((index % slots) * _bits)) & ((1 << _bits) - 1)
	return _palette[palette_index]

func set_state(index: int, state_id: int) -> bool:
	if not valid_index(index) or not valid_state(state_id):
		return false
	var palette_index: int = _indices.get(state_id, -1)
	if palette_index < 0:
		palette_index = _palette.size()
		_indices[state_id] = palette_index
		_palette.append(state_id)
		var needed: int = _bits
		while (1 << needed) < _palette.size():
			needed += 1
		if needed != _bits:
			_repack(needed)
	if _bits != 0:
		_write_index(index, palette_index)
	return true

func fill(state_id: int) -> bool:
	if not valid_state(state_id):
		return false
	_palette = PackedInt32Array([state_id])
	_indices = {state_id: 0}
	_words = PackedInt64Array()
	_bits = 0
	return true

func _write_index(index: int, palette_index: int) -> void:
	@warning_ignore("integer_division")
	var slots: int = 64 / _bits
	@warning_ignore("integer_division")
	var word_index: int = index / slots
	var shift: int = (index % slots) * _bits
	var mask: int = ((1 << _bits) - 1) << shift
	_words[word_index] = (_words[word_index] & ~mask) | (palette_index << shift)

func _repack(new_bits: int) -> void:
	var previous: PackedInt64Array = _words
	var previous_bits: int = _bits
	_bits = new_bits
	@warning_ignore("integer_division")
	var slots: int = 64 / _bits
	_words = PackedInt64Array()
	@warning_ignore("integer_division")
	var word_count: int = (CELL_COUNT + slots - 1) / slots
	_words.resize(word_count)
	_words.fill(0)
	if previous_bits == 0:
		return
	@warning_ignore("integer_division")
	var previous_slots: int = 64 / previous_bits
	var previous_mask: int = (1 << previous_bits) - 1
	for index: int in range(CELL_COUNT):
		@warning_ignore("integer_division")
		var word_index: int = index / previous_slots
		var palette_index: int = (previous[word_index] >> ((index % previous_slots) * previous_bits)) & previous_mask
		_write_index(index, palette_index)

## Explicit maintenance operation. Preserve all cells while removing dead palette entries.
func compact() -> void:
	var values: PackedInt32Array = export_states()
	fill(values[0])
	for index: int in range(CELL_COUNT):
		set_state(index, values[index])

func bits_per_index() -> int:
	return _bits

func palette_size() -> int:
	return _palette.size()

func payload_bytes() -> int:
	return _words.size() * 8 + _palette.size() * 4
