@tool
class_name AstraeonFluidDefinition
extends Resource
## Shared static fluid definition. World owns level, volume and flow; this resource does not simulate fluids.
@export var key: StringName
@export var display_name: String = ""
## Current fluid implementation is water; other appearance families require an explicit contract.
@export var appearance: AstraeonWaterAppearance
@export var collision_enabled: bool = false
@export_range(0, 15) var light_opacity: int = 1
