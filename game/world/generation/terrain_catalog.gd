class_name AstraeonTerrainCatalog
extends RefCounted
## Dedicated six-block fixture; does not change the existing gameplay catalog.
const DEFINITION: Script = preload("res://game/world/blocks/block_definition.gd")
const REGISTRY: Script = preload("res://game/world/blocks/block_registry.gd")
const KEYS: Array[String] = ["air", "stone", "dirt", "grass", "sand", "water"]

static func build_registry() -> AstraeonBlockRegistry:
	var definitions: Array[AstraeonBlockDefinition] = []
	for key: String in KEYS:
		var definition: AstraeonBlockDefinition = DEFINITION.new()
		definition.key = StringName("astraeon:" + key)
		definition.display_name = key
		definition.collision_enabled = key != "air" and key != "water"
		definition.light_opacity = 0 if key == "air" else (2 if key == "water" else 15)
		definitions.append(definition)
	var registry: AstraeonBlockRegistry = REGISTRY.new()
	var errors: PackedStringArray = registry.build(definitions)
	assert(errors.is_empty(), str(errors))
	return registry

static func ids(registry: AstraeonBlockRegistry) -> PackedInt32Array:
	var values: PackedInt32Array = PackedInt32Array()
	for key: String in KEYS:
		values.append(registry.find_state(StringName("astraeon:" + key)))
	return values
