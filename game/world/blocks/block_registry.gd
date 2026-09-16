class_name AstraeonBlockRegistry
extends RefCounted
## Build once from Resources, then query an immutable snapshot. Air/default is always state 0.
## Runtime IDs are not a save format: persist the stable block/state keys instead.
const DEFINITION: Script = preload("res://game/world/blocks/block_definition.gd")
const AIR_KEY: StringName = &"astraeon:air"
const MAX_STATES: int = 65536
var _built: bool = false
var _ids: Dictionary[String, int] = {}
var _keys: PackedStringArray = PackedStringArray()
var _names: PackedStringArray = PackedStringArray()
var _hardness: PackedFloat64Array = PackedFloat64Array()
var _collision: PackedByteArray = PackedByteArray()
var _opacity: PackedByteArray = PackedByteArray()
var _emission: PackedByteArray = PackedByteArray()
var _properties: Array[Dictionary] = []

## Atomic validation. Returns problems without publishing a partial registry.
func build(definitions: Array[AstraeonBlockDefinition]) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if _built:
		return PackedStringArray(["Registry is already built; create a new registry to change content."])
	var by_key: Dictionary[String, AstraeonBlockDefinition] = {}
	var total: int = 0
	for definition: AstraeonBlockDefinition in definitions:
		if definition == null:
			errors.append("Null block definition.")
			continue
		var block_key: String = String(definition.key)
		if not _valid_key(block_key, true) or by_key.has(block_key):
			errors.append("Invalid or duplicate block key: " + block_key)
		by_key[block_key] = definition
		if not is_finite(definition.hardness) or definition.hardness < 0.0:
			errors.append("Invalid hardness: " + block_key)
		if definition.light_opacity < 0 or definition.light_opacity > 15 or definition.light_emission < 0 or definition.light_emission > 15:
			errors.append("Light values must be in 0..15: " + block_key)
		var seen: Dictionary[StringName, bool] = {}
		for state: AstraeonBlockStateDefinition in definition.states:
			if state == null:
				errors.append("Null state: " + block_key)
				continue
			if not _valid_key(String(state.key), false) or seen.has(state.key):
				errors.append("Invalid or duplicate state key: " + block_key)
			seen[state.key] = true
		total += maxi(1, definition.states.size())
	if total > MAX_STATES:
		errors.append("More than 65536 block states.")
	var air: AstraeonBlockDefinition = by_key.get(String(AIR_KEY))
	if air == null:
		errors.append("Missing astraeon:air.")
	elif air.collision_enabled or air.light_opacity != 0 or air.light_emission != 0 or (not air.states.is_empty() and (air.states.size() != 1 or air.states[0] == null or air.states[0].key != &"default")):
		errors.append("Air must have only default state, no collision, opacity or emission.")
	if not errors.is_empty():
		return errors
	var block_keys: Array[String] = by_key.keys()
	block_keys.sort()
	block_keys.erase(String(AIR_KEY))
	block_keys.push_front(String(AIR_KEY))
	for block_key: String in block_keys:
		var definition: AstraeonBlockDefinition = by_key[block_key]
		if definition.states.is_empty():
			_append(definition, "default", {})
			continue
		var state_map: Dictionary[String, AstraeonBlockStateDefinition] = {}
		for state: AstraeonBlockStateDefinition in definition.states:
			state_map[String(state.key)] = state
		var state_keys: Array[String] = state_map.keys()
		state_keys.sort()
		for state_key: String in state_keys:
			_append(definition, state_key, state_map[state_key].properties)
	_built = true
	return errors

func _append(definition: AstraeonBlockDefinition, state_key: String, properties: Dictionary[StringName, StringName]) -> void:
	var combined_key: String = String(definition.key) + "/" + state_key
	_ids[combined_key] = _keys.size()
	_keys.append(combined_key)
	_names.append(definition.display_name)
	_hardness.append(definition.hardness)
	_collision.append(int(definition.collision_enabled))
	_opacity.append(definition.light_opacity)
	_emission.append(definition.light_emission)
	_properties.append(properties.duplicate(true))

static func _valid_key(value: String, namespaced: bool) -> bool:
	if value.is_empty():
		return false
	var parts: PackedStringArray = value.split(":")
	if parts.size() != (2 if namespaced else 1):
		return false
	for part: String in parts:
		if part.is_empty():
			return false
		for index: int in range(part.length()):
			var code: int = part.unicode_at(index)
			if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95 or code == 45 or code == 46):
				return false
	return true

func state_count() -> int:
	return _keys.size()

func find_state(block_key: StringName, state_key: StringName = &"default") -> int:
	return _ids.get(String(block_key) + "/" + String(state_key), -1)

func stable_key(state_id: int) -> String:
	assert(state_id >= 0 and state_id < state_count())
	return _keys[state_id]

func properties_for(state_id: int) -> Dictionary[StringName, StringName]:
	assert(state_id >= 0 and state_id < state_count())
	return _properties[state_id].duplicate(true)

func hardness_for(state_id: int) -> float:
	assert(state_id >= 0 and state_id < state_count())
	return _hardness[state_id]

func has_collision(state_id: int) -> bool:
	assert(state_id >= 0 and state_id < state_count())
	return _collision[state_id] != 0

func opacity_for(state_id: int) -> int:
	assert(state_id >= 0 and state_id < state_count())
	return _opacity[state_id]

func emission_for(state_id: int) -> int:
	assert(state_id >= 0 and state_id < state_count())
	return _emission[state_id]

func display_name_for(state_id: int) -> String:
	assert(state_id >= 0 and state_id < state_count())
	return _names[state_id]

## Owned dense lookup tables for future batch lighting; callers cannot mutate this registry.
func opacity_table() -> PackedByteArray:
	return _opacity.duplicate()

func emission_table() -> PackedByteArray:
	return _emission.duplicate()
