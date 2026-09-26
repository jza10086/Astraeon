class_name AstraeonInventoryDefinition
extends Resource
## Current player layout: ten shared hotbar slots followed by thirty storage slots.
@export var hotbar_slots: int = 10
@export var storage_rows: int = 3

func slot_count() -> int:
	return hotbar_slots * (storage_rows + 1)
