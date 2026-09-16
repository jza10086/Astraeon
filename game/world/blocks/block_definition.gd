class_name AstraeonBlockDefinition
extends Resource
## Shared authoring template. Registries copy gameplay fields; never mutate this for a voxel.
const STATE_DEFINITION: Script = preload("res://game/world/blocks/block_state_definition.gd")
@export var key: StringName
@export var display_name: String = ""
@export var hardness: float = 1.0
@export var collision_enabled: bool = true
@export_range(0, 15) var light_opacity: int = 15
@export_range(0, 15) var light_emission: int = 0
## Empty means one state named "default". Variants are explicit, avoiding a Cartesian explosion.
@export var states: Array[AstraeonBlockStateDefinition] = []
