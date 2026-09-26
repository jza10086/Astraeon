class_name AstraeonItemCatalog
extends Resource
@export var definitions: Array[AstraeonItemDefinition] = []

func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	var keys: Dictionary[StringName, bool] = {}
	var blocks: Dictionary[StringName, bool] = {}
	for item: AstraeonItemDefinition in definitions:
		if item == null:
			errors.append("Null item")
			continue
		if not String(item.key).begins_with("astraeon_") or keys.has(item.key) or item.max_stack < 1:
			errors.append("Invalid or duplicate item: " + String(item.key))
		keys[item.key] = true
		if item.block != null:
			if blocks.has(item.block.key):
				errors.append("Ambiguous block drop: " + String(item.block.key))
			blocks[item.block.key] = true
	return errors
