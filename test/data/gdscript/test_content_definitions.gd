extends SceneTree

var failures: int = 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var catalog: AstraeonBlockCatalog = load("res://game/data/block/resources/block_catalog.tres")
	var keys: Array[StringName] = []
	for definition: AstraeonBlockDefinition in catalog.definitions:
		check(not keys.has(definition.key), "Duplicate content key")
		keys.append(definition.key)
		check(String(definition.key).begins_with("astraeon_"), "Invalid key prefix")
		check(definition.appearance.validate().is_empty(), "Invalid block appearance")
	var wood: AstraeonBlockDefinition = load("res://game/data/block/resources/astraeon_log.tres")
	check(wood.default_state == &"axis_y", "Log default must be vertical")
	for state: AstraeonBlockStateDefinition in wood.states:
		var axis: StringName = state.properties[&"axis"]
		var direction: Vector3 = {&"x": Vector3.RIGHT, &"y": Vector3.UP, &"z": Vector3.BACK}[axis]
		check(AstraeonBlockAppearance.is_cube_rotation(state.orientation), "Invalid state rotation")
		check((state.orientation * Vector3.UP).is_equal_approx(direction), "Log end points along wrong axis")
		var world_face: int = {&"x": AstraeonBlockAppearance.Face.RIGHT, &"y": AstraeonBlockAppearance.Face.TOP, &"z": AstraeonBlockAppearance.Face.BACK}[axis]
		check(wood.appearance.authored_face_for_world(world_face, state.orientation) == AstraeonBlockAppearance.Face.TOP, "Wrong authored end face")
	check(wood.appearance.authoring_orientation == Basis.IDENTITY, "Shared appearance was mutated")
	var grass: AstraeonBlockDefinition = load("res://game/data/block/resources/astraeon_grass.tres")
	check(grass.appearance.surface_for_face(AstraeonBlockAppearance.Face.TOP) != grass.appearance.surface_for_face(AstraeonBlockAppearance.Face.BOTTOM), "Grass top and bottom must differ")
	var water: AstraeonFluidDefinition = load("res://game/data/fluid/resources/astraeon_water.tres")
	check(water.key == &"astraeon_water" and not water.collision_enabled, "Invalid water logic")
	check(water.appearance.validate().is_empty(), "Invalid water appearance")
	check(water.appearance == load("res://game/shading/water/resources/default_water.tres"), "Water must share shading appearance")
	print("CONTENT_DEFINITIONS failures=", failures)
	quit(0 if failures == 0 else 1)
