class_name AstraeonWorldContent
extends RefCounted
## Startup snapshot: the ordered state table drives generation, meshing and persistence together.
var state_keys: PackedStringArray = []
var library: VoxelBlockyLibrary
var water_id: int = -1
var grass_id: int = -1
var dirt_id: int = -1

func build(catalog: AstraeonBlockCatalog, water: AstraeonFluidDefinition) -> bool:
	if library != null or catalog == null or water == null:
		return false
	var models: Array[VoxelBlockyModel] = [VoxelBlockyModelEmpty.new()]
	state_keys = PackedStringArray(["astraeon_air/default"])
	var by_key: Dictionary[String, AstraeonBlockDefinition] = {}
	for definition: AstraeonBlockDefinition in catalog.definitions:
		if definition == null or not _valid_key(String(definition.key)) or by_key.has(String(definition.key)) or definition.key == &"astraeon_air":
			return false
		by_key[String(definition.key)] = definition
	var keys: Array[String] = by_key.keys()
	keys.sort()
	for key: String in keys:
		var definition: AstraeonBlockDefinition = by_key[key]
		var states: Dictionary[String, Basis] = {}
		if definition.states.is_empty():
			states["default"] = Basis.IDENTITY
		for state: AstraeonBlockStateDefinition in definition.states:
			if state == null or String(state.key).is_empty() or String(state.key).contains("/") or String(state.key).contains("\n") or states.has(String(state.key)):
				return false
			states[String(state.key)] = state.orientation
		if not states.has(String(definition.default_state)):
			return false
		var names: Array[String] = states.keys()
		names.sort()
		for state: String in names:
			var model: VoxelBlockyModelCube = AstraeonBlockLibraryBuilder.build_block(definition, states[state])
			if model == null:
				return false
			state_keys.append(key + "/" + state)
			models.append(model)
	if not _valid_key(String(water.key)) or by_key.has(String(water.key)) or water.key == &"astraeon_air":
		return false
	var water_model: VoxelBlockyModelCube = AstraeonBlockLibraryBuilder.build_water(water)
	if water_model == null:
		return false
	water_id = models.size()
	state_keys.append(String(water.key) + "/default")
	models.append(water_model)
	grass_id = state_keys.find("astraeon_grass/default")
	dirt_id = state_keys.find("astraeon_dirt/default")
	if models.size() > 65536 or grass_id < 0 or dirt_id < 0:
		return false
	library = VoxelBlockyLibrary.new()
	library.models = models
	library.bake()
	return true

static func _valid_key(key: String) -> bool:
	if not key.begins_with("astraeon_") or key.length() <= 8:
		return false
	for character: String in key:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789_":
			return false
	return true
