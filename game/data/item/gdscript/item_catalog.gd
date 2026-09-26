class_name AstraeonItemCatalog
extends Resource
## Ordered group IDs and localized labels. Keys, not labels, are referenced by items.
@export var creative_groups: Dictionary[StringName, String] = {&"astraeon_building": "建筑方块", &"astraeon_natural": "自然方块", &"astraeon_functional": "功能方块"}
@export var definitions: Array[AstraeonItemDefinition] = []

func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	for group_key: StringName in creative_groups:
		if not String(group_key).begins_with("astraeon_") or creative_groups[group_key].strip_edges().is_empty():
			errors.append("Invalid creative group: " + String(group_key))
	var keys: Dictionary[StringName, bool] = {}
	var blocks: Dictionary[StringName, bool] = {}
	for item: AstraeonItemDefinition in definitions:
		if item == null:
			errors.append("Null item")
			continue
		if not String(item.key).begins_with("astraeon_") or keys.has(item.key) or item.max_stack < 1:
			errors.append("Invalid or duplicate item: " + String(item.key))
		if not creative_groups.has(item.creative_group):
			errors.append("Unknown creative group: " + String(item.creative_group))
		var seen_tags: Dictionary[String, bool] = {}
		for tag: String in item.search_tags:
			if tag.strip_edges().is_empty() or tag != tag.strip_edges() or seen_tags.has(tag.to_lower()):
				errors.append("Empty or duplicate search tag: " + String(item.key))
			seen_tags[tag.to_lower()] = true
		keys[item.key] = true
		if item.block != null:
			if blocks.has(item.block.key):
				errors.append("Ambiguous block drop: " + String(item.block.key))
			blocks[item.block.key] = true
	return errors

## All query terms must match name, stable ID, group label, or search tags; case-insensitive.
## Empty group means all. Only placeable block items are returned; axis states are not duplicated.
func find_blocks(group: StringName = &"", query: String = "") -> Array[AstraeonItemDefinition]:
	var result: Array[AstraeonItemDefinition] = []
	var terms: PackedStringArray = query.to_lower().replace("\t", " ").split(" ", false)
	for item: AstraeonItemDefinition in definitions:
		if item == null or item.block == null or (group != &"" and item.creative_group != group):
			continue
		var text: String = (item.display_name + " " + String(item.key) + " " + String(item.block.key) + " " + creative_groups.get(item.creative_group, "") + " " + " ".join(item.search_tags)).to_lower()
		var matches: bool = true
		for term: String in terms:
			if not text.contains(term):
				matches = false
				break
		if matches:
			result.append(item)
	return result
