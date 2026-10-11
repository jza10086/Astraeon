@tool
class_name AstraeonItemDefinition
extends Resource
## Shared immutable authoring definition. Quantity and selected slot belong to InventoryState.
@export var key: StringName
@export var display_name: String
@export var icon: Texture2D
@export var icon_color: Color = Color.WHITE
@export_range(1, 999) var max_stack: int = 64
## Creative browsing only; never infer collision, recipes or other gameplay from these tags.
@export var creative_group: StringName = &"astraeon_building"
@export var search_tags: PackedStringArray = []
## Gameplay tags are exact, namespaced IDs, independent of creative search keywords.
@export var tool_tags: PackedStringArray = []
## Durability removed per second when the block's required tag matches.
@export_range(1.0, 1000.0, 0.5) var mining_speed: float = 1.0
@export var block: AstraeonBlockDefinition
## Resolve axis from the placement face; inventory stacks never carry world orientation.
@export var orient_to_face: bool = false

func state_key(normal: Vector3i) -> String:
	if block == null:
		return ""
	var state: String = String(block.default_state)
	if orient_to_face:
		state = "axis_x" if normal.x != 0 else ("axis_z" if normal.z != 0 else "axis_y")
	return String(block.key) + "/" + state
