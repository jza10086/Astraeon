@tool
class_name AstraeonContentBundle
extends RefCounted
## Compiled data assembly; no ResourceLoader calls, source images or per-pixel operations.
var error: String = ""
var blocks: Dictionary[String, Dictionary] = {}
var items: Array[Dictionary] = []
var packages: Dictionary[String, Dictionary] = {}
var paths: Dictionary[String, String] = {}
var contracts: Dictionary = {"astraeon:air/default": "air-v1".sha256_text()}
var state_records: Dictionary[String, Dictionary] = {}
var state_keys: PackedStringArray = []
var world_id: String = ""
var visuals: RefCounted

func open(package_paths: PackedStringArray, world_directory: String = "") -> bool:
	if not packages.is_empty() or not ClassDB.class_exists("AstraeonVisualCache"):
		error = "Bundle already open or native content extension unavailable"
		return false
	var pending: Dictionary[String, Dictionary] = {}
	var readers: Array[RefCounted] = []
	for path: String in package_paths:
		var reader: RefCounted = ClassDB.instantiate("AstraeonContentPack")
		var data: Dictionary = reader.call("open_pack", path)
		if data.has("error"):
			error = String(data.error)
			return false
		if pending.has(String(data.id)):
			error = "Duplicate package: " + String(data.id)
			return false
		pending[String(data.id)] = data
		paths[String(data.id)] = path
		readers.append(reader)
	var visiting: Dictionary[String, int] = {}
	for id: String in pending:
		if not _dependency(id, pending, visiting):
			return false
	var item_ids: Dictionary[String, bool] = {}
	for id: String in pending:
		var pack: Dictionary = pending[id]
		for record: Dictionary in pack.blocks:
			var key: String = record.id
			if blocks.has(key) or key.get_slice(":", 0) != id:
				error = "Duplicate block or foreign namespace: " + key
				return false
			if not record.has("breaking") or not record.breaking is Dictionary:
				error = "Unsupported breaking appearance record; rebuild content package: " + key
				return false
			var breaking: Dictionary = record.breaking
			if not breaking.is_empty():
				var tint: Variant = breaking.get("tint")
				if not breaking.get("visual") is String or String(breaking.visual).length() != 64 or not breaking.get("resolution") is float and not breaking.get("resolution") is int:
					error = "Invalid breaking visual: " + key
					return false
				if not is_finite(float(breaking.resolution)) or float(breaking.resolution) != floorf(float(breaking.resolution)) or int(breaking.resolution) < 1 or int(breaking.resolution) > 1024 or breaking.get("stages", 0) != 10 or not tint is Array or tint.size() != 4 or not breaking.get("strength") is float and not breaking.get("strength") is int:
					error = "Invalid breaking group: " + key
					return false
				if not is_finite(float(breaking.strength)) or float(breaking.strength) < 0.0 or float(breaking.strength) > 1.0:
					error = "Invalid breaking strength: " + key
					return false
				for channel: Variant in tint:
					if (not channel is float and not channel is int) or not is_finite(float(channel)) or float(channel) < 0.0 or float(channel) > 1.0:
						error = "Invalid breaking tint: " + key
						return false
			record["package"] = id
			blocks[key] = record
			for state: Dictionary in record.states:
				var state_key: String = key + "/" + String(state.name)
				state_records[state_key] = {"block": key, "state": state}
				var logical: Dictionary = {"collision": record.collision, "opacity": record.opacity, "emission": record.emission, "kind": record.kind, "hardness": record.get("hardness", 0.0), "required_tool_tag": record.get("required_tool_tag", ""), "mining_recovery_seconds": record.get("mining_recovery_seconds", 0.0), "state": {"name": state.name, "rotation": state.logical_rotation, "properties": state.get("properties", {})}, "alpha": record.get("surface", {}).get("alpha", 0), "foliage": record.get("surface", {}).get("foliage_layers", false)}
				contracts[state_key] = JSON.stringify(logical, "", true, true).sha256_text()
		for item: Dictionary in pack.items:
			var key: String = item.id
			if item_ids.has(key) or key.get_slice(":", 0) != id:
				error = "Duplicate item or foreign namespace: " + key
				return false
			var dependency: String = String(item.block).get_slice(":", 0)
			if not String(item.block).is_empty() and dependency != id and not pack.dependencies.has(dependency):
				error = "Undeclared item dependency: " + key
				return false
			item_ids[key] = true
			item["package"] = id
			items.append(item)
	for item: Dictionary in items:
		if not String(item.block).is_empty() and not blocks.has(String(item.block)):
			error = "Missing item block: " + String(item.block)
			return false
	var water_count: int = 0
	for record: Dictionary in blocks.values():
		water_count += int(record.kind == "water")
	if water_count > 1:
		error = "The current world supports one water definition"
		return false
	var drops: Dictionary[String, bool] = {}
	for item: Dictionary in items:
		if not String(item.block).is_empty() and drops.has(String(item.block)):
			error = "Ambiguous item drop for block: " + String(item.block)
			return false
		if not String(item.block).is_empty():
			drops[String(item.block)] = true
		if bool(item.orient_to_face):
			for axis: String in ["x", "y", "z"]:
				if not state_records.has(String(item.block) + "/axis_" + axis):
					error = "Oriented item requires axis_x/y/z states: " + String(item.id)
					return false
		var tags: Dictionary[String, bool] = {}
		for tag: Variant in item.tags:
			if not tag is String or String(tag).strip_edges() != tag or String(tag).is_empty() or tags.has(String(tag).to_lower()):
				error = "Invalid search tag: " + String(item.id)
				return false
			tags[String(tag).to_lower()] = true
	for pack: Dictionary in pending.values():
		var groups: Variant = pack.get("groups", {})
		if not groups is Dictionary:
			error = "Invalid creative group labels"
			return false
		for label: Variant in groups.values():
			if not label is String or String(label).strip_edges().is_empty():
				error = "Invalid creative group label"
				return false
	if contracts.size() > 65536:
		error = "More than 65536 states"
		return false
	visuals = ClassDB.instantiate("AstraeonVisualCache")
	for key: String in blocks:
		var record: Dictionary = blocks[key]
		if not String(record.visual).is_empty():
			var size: int = int(record.surface.resolution)
			if not visuals.call("register_visual", record.visual, paths[record.package], 6 * size, size, record.load_policy == "preload"):
				error = "Invalid visual resource dimensions: " + key
				return false
	for record: Dictionary in blocks.values():
		var breaking: Dictionary = record.breaking
		if not breaking.is_empty():
			var size: int = int(breaking.resolution)
			if not visuals.call("register_visual", breaking.visual, paths[record.package], size * 10, size, false):
				error = "Invalid breaking payload: " + String(record.id)
				return false
	for item: Dictionary in items:
		if item.has("icon"):
			if not visuals.call("register_visual", item.icon, paths[item.package], int(item.icon_width), int(item.icon_height), false):
				error = "Invalid item icon: " + String(item.id)
				return false
	if world_directory.is_empty():
		var keys: Array = contracts.keys()
		keys.erase("astraeon:air/default")
		keys.sort()
		state_keys = PackedStringArray(["astraeon:air/default"])
		state_keys.append_array(PackedStringArray(keys))
	else:
		var registry: RefCounted = ClassDB.instantiate("AstraeonContentRegistry")
		var result: Dictionary = registry.call("resolve", world_directory, contracts, PackedStringArray(pending.keys()))
		if result.has("error"):
			error = String(result.error)
			return false
		state_keys = result.state_keys
		world_id = result.world_id
	packages = pending
	return true

func _dependency(id: String, all: Dictionary[String, Dictionary], marks: Dictionary[String, int]) -> bool:
	if not all.has(id):
		error = "Missing dependency: " + id
		return false
	if marks.get(id, 0) == 1:
		error = "Content dependency cycle: " + id
		return false
	if marks.get(id, 0) == 2:
		return true
	marks[id] = 1
	for dependency: String in all[id].dependencies:
		if not _dependency(dependency, all, marks):
			return false
	marks[id] = 2
	return true

func state_visuals(ids: PackedInt32Array) -> PackedStringArray:
	var hashes: Dictionary[String, bool] = {}
	for id: int in ids:
		if id > 0 and id < state_keys.size():
			var hash: String = blocks[state_records[state_keys[id]].block].visual
			if not hash.is_empty():
				hashes[hash] = true
	return PackedStringArray(hashes.keys())

func shutdown() -> void:
	if visuals != null:
		visuals.call("shutdown")
