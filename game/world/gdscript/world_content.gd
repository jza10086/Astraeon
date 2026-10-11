class_name AstraeonWorldContent
extends RefCounted
## Immutable compiled content plus the world's append-only numeric state table.
var state_keys: PackedStringArray = []
var library: VoxelBlockyLibrary
var opacity: PackedByteArray = PackedByteArray([0])
var sources: PackedByteArray = PackedByteArray([0])
var emission: PackedByteArray = PackedByteArray([0])
var light_definitions: Dictionary[int, AstraeonBlockLightAppearance] = {}
var light_offsets: Dictionary[int, Vector3] = {}
var water_id: int = -1
var grass_id: int = -1
var dirt_id: int = -1
var bundle: AstraeonContentBundle
var error: String = ""
var water_definition: AstraeonFluidDefinition
var item_catalog: AstraeonItemCatalog
const Builder: Script = preload("res://game/shading/blocks/gdscript/compiled_block_builder.gd")

func build(paths: PackedStringArray, world_directory: String = "") -> bool:
	if library != null:
		return false
	bundle = AstraeonContentBundle.new()
	if not bundle.open(paths, world_directory):
		error = bundle.error
		return false
	state_keys = bundle.state_keys
	var models: Array[VoxelBlockyModel] = [VoxelBlockyModelEmpty.new()]
	var shared: Dictionary[String, Material] = {}
	for id: int in range(1, state_keys.size()):
		var entry: Dictionary = bundle.state_records[state_keys[id]]
		var record: Dictionary = bundle.blocks[entry.block]
		# Material identity is independent of orientation and block logic.
		var visual_key: String = JSON.stringify([record.get("surface", {}), record.visual, record.kind, record.breaking], "", true, true)
		var model: VoxelBlockyModelCube = Builder.block(record, int(entry.state.rotation), bundle.visuals, shared.get(visual_key, null))
		shared[visual_key] = model.get_material_override(0)
		models.append(model)
		opacity.append(int(record.opacity))
		emission.append(int(record.emission))
		sources.append(1 if record.has("light") and float(record.light.energy) > 0.0 else 0)
		if record.has("light"):
			var light: AstraeonBlockLightAppearance = AstraeonBlockLightAppearance.new()
			light.color = color(record.light.color)
			light.energy = float(record.light.energy)
			light.range = float(record.light.range)
			light.attenuation = float(record.light.attenuation)
			light.source_radius = float(record.light.radius)
			light.shadow_policy = int(record.light.shadow_policy) as AstraeonBlockLightAppearance.ShadowPolicy
			var offset: Array = entry.state.get("light_offset", record.light.offset)
			light_offsets[id] = Vector3(offset[0], offset[1], offset[2])
			light_definitions[id] = light
		if record.kind == "water":
			if water_id >= 0:
				error = "This world currently supports one water definition"
				return false
			water_id = id
			water_definition = AstraeonFluidDefinition.new()
			water_definition.key = StringName(record.id)
			water_definition.display_name = record.name
			water_definition.collision_enabled = bool(record.collision)
			water_definition.light_opacity = int(record.opacity)
			water_definition.appearance = AstraeonWaterAppearance.new()
			for field: String in record.water:
				water_definition.appearance.set(field, color(record.water[field]) if record.water[field] is Array else record.water[field])
	grass_id = state_keys.find("astraeon:grass/default")
	dirt_id = state_keys.find("astraeon:dirt/default")
	library = VoxelBlockyLibrary.new()
	library.models = models
	library.bake()
	_build_items()
	return true

func _build_items() -> void:
	item_catalog = AstraeonItemCatalog.new()
	for record: Dictionary in bundle.items:
		var item: AstraeonItemDefinition = AstraeonItemDefinition.new()
		item.key = StringName(record.id)
		item.display_name = record.name
		item.max_stack = int(record.max_stack)
		item.creative_group = StringName(record.group)
		item_catalog.creative_groups[item.creative_group] = String(bundle.packages[record.package].get("groups", {}).get(String(record.group), String(record.group)))
		item.search_tags = PackedStringArray(record.tags)
		item.tool_tags = PackedStringArray(record.tool_tags)
		item.mining_speed = float(record.mining_speed)
		item.icon_color = color(record.color)
		item.orient_to_face = bool(record.orient_to_face)
		if not String(record.block).is_empty():
			var block: Dictionary = bundle.blocks[record.block]
			item.block = AstraeonBlockDefinition.new()
			item.block.key = StringName(block.id)
			item.block.default_state = StringName(block.default_state)
			item.block.hardness = float(block.get("hardness", 1.0))
		if record.has("icon"):
			item.set_meta("content_icon", record.icon)
			item.set_meta("content_cache", bundle.visuals)
		item_catalog.definitions.append(item)

static func color(channels: Array) -> Color:
	return Color(channels[0], channels[1], channels[2], channels[3] if channels.size() > 3 else 1.0)
