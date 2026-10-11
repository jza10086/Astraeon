@tool
class_name AstraeonBlockDefinition
extends Resource
## Shared authoring template; compiled offline to the native content package contract.
const STATE_DEFINITION: Script = preload("res://game/data/block/gdscript/block_state_definition.gd")
@export var key: StringName
## Shared visual definition; never store instance state in this resource.
@export var appearance: AstraeonBlockAppearance
@export var display_name: String = ""
## Minecraft-style hardness; mining durability is hardness * 1.5.
@export var hardness: float = 1.0
## Exactly one acceleration tag. Empty allows no tool bonus; bare hands can still mine.
@export var required_tool_tag: StringName = &""
## Seconds without mining before damage is cleared; zero clears on interruption.
@export_range(0.0, 3600.0, 0.5) var mining_recovery_seconds: float = 30.0
@export var collision_enabled: bool = true
@export_range(0, 15) var light_opacity: int = 15
@export_range(0, 15) var light_emission: int = 0
## Empty means one state named "default". Variants are explicit, avoiding a Cartesian explosion.
@export var states: Array[AstraeonBlockStateDefinition] = []

## Explicit default when states are supplied; empty states use the implicit default.
@export var default_state: StringName = &"default"

## Visual residency policy; logic definitions always remain available.
@export_enum("preload", "on_demand") var load_policy: String = "preload"
