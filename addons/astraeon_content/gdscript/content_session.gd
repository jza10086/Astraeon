@tool
extends RefCounted
## Private authoring document. All mutations, undo history and file ownership live here.
signal changed(rebuild: bool)
const Compiler = preload("res://tools/content/compiler.gd")
var project: AstraeonContentManifest
var path: String = ""
var error: String = ""
var block_paths: Array[String] = []
var item_paths: Array[String] = []
var fluid_paths: Array[String] = []
var fingerprints: Dictionary[String, String] = {}
var history: UndoRedo = UndoRedo.new()
var saved_version: int = 1

func dirty() -> bool:
	return project != null and history.get_version() != saved_version

func open_project(file: String) -> bool:
	error = ""
	if not FileAccess.file_exists(file):
		error = "包工程不存在：" + file
		return false
	var loaded: Resource = ResourceLoader.load(file, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if not loaded is AstraeonContentManifest or loaded.project_format != 2:
		error = "不支持的包工程格式（需要 2）：" + file
		return false
	for resource: Resource in loaded.blocks + loaded.items + loaded.fluids:
		if resource == null or resource.resource_path.is_empty() or "::" in resource.resource_path:
			error = "包索引需要独立资源文件：" + file
			return false
	for asset: AstraeonBlockAsset in loaded.blocks:
		if asset.block == null or asset.block.appearance == null or asset.block.appearance.default_surface == null or asset.block.states.has(null):
			error = "方块文件不完整：" + asset.resource_path
			return false
	for asset: AstraeonItemAsset in loaded.items:
		if asset.item == null:
			error = "物品文件不完整：" + asset.resource_path
			return false
	for fluid: AstraeonFluidDefinition in loaded.fluids:
		if fluid.appearance == null:
			error = "流体材质缺失：" + fluid.resource_path
			return false
	project = loaded.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	path = file
	block_paths.clear()
	item_paths.clear()
	fluid_paths.clear()
	for asset: AstraeonBlockAsset in loaded.blocks: block_paths.append(asset.resource_path)
	for asset: AstraeonItemAsset in loaded.items: item_paths.append(asset.resource_path)
	for fluid: AstraeonFluidDefinition in loaded.fluids: fluid_paths.append(fluid.resource_path)
	history.clear_history()
	saved_version = history.get_version()
	remember_files()
	changed.emit(true)
	return true

func create_project(file: String, namespace_id: String) -> bool:
	if not Compiler._id(namespace_id + ":example") or ":" in namespace_id:
		error = "命名空间无效：" + namespace_id
		return false
	if FileAccess.file_exists(file):
		error = "工程文件已存在：" + file
		return false
	project = AstraeonContentManifest.new()
	project.package_id = namespace_id
	project.display_name = namespace_id
	path = file
	block_paths.clear()
	item_paths.clear()
	fluid_paths.clear()
	fingerprints.clear()
	history.clear_history()
	saved_version = -1
	changed.emit(true)
	return true

func snapshot() -> Dictionary:
	return {"project": project.duplicate_deep(Resource.DEEP_DUPLICATE_ALL), "blocks": block_paths.duplicate(), "items": item_paths.duplicate(), "fluids": fluid_paths.duplicate()}

func restore(state: Dictionary) -> void:
	project = state.project.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	block_paths.assign(state.blocks)
	item_paths.assign(state.items)
	fluid_paths.assign(state.fluids)
	changed.emit(true)

func commit(before: Dictionary, label: String, rebuild: bool = false) -> void:
	history.create_action(label)
	history.add_do_method(restore.bind(snapshot()))
	history.add_undo_method(restore.bind(before))
	history.commit_action(false)
	changed.emit(rebuild)

func edit(target: Resource, property: StringName, value: Variant, rebuild: bool = false) -> void:
	if target.get(property) == value: return
	var before: Dictionary = snapshot()
	target.set(property, value)
	commit(before, String(property), rebuild)

func undo() -> void:
	if history.has_undo(): history.undo()

func redo() -> void:
	if history.has_redo(): history.redo()

## Rows are views into owned files. Paired items never become separate item assets.
func rows(kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if project == null: return result
	if kind == "block":
		for index: int in range(project.blocks.size()):
			result.append({"kind": kind, "index": index, "asset": project.blocks[index], "data": project.blocks[index].block, "file": block_paths[index], "owner": ""})
	elif kind == "item":
		for index: int in range(project.items.size()):
			result.append({"kind": kind, "index": index, "asset": project.items[index], "data": project.items[index].item, "file": item_paths[index], "owner": ""})
		for index: int in range(project.blocks.size()):
			if project.blocks[index].item != null:
				result.append({"kind": "paired", "index": index, "asset": project.blocks[index], "data": project.blocks[index].item, "file": block_paths[index], "owner": String(project.blocks[index].block.key)})
	elif kind == "fluid":
		for index: int in range(project.fluids.size()):
			result.append({"kind": kind, "index": index, "asset": project.fluids[index], "data": project.fluids[index], "file": fluid_paths[index], "owner": ""})
	return result

func validate_id(id: String) -> bool:
	if not Compiler._id(id) or id.get_slice(":", 0) != project.package_id:
		error = "ID 必须使用当前命名空间，格式 " + project.package_id + ":name"
		return false
	for kind: String in ["block", "item", "fluid"]:
		for row: Dictionary in rows(kind):
			if String(row.data.key) == id:
				error = "重复内容 ID：" + id
				return false
	return true

func add(kind: String, id: String, paired: bool = true, source: Dictionary = {}) -> bool:
	error = ""
	if not validate_id(id): return false
	if kind == "block" and paired and not validate_id(id + "_item"): return false
	var before: Dictionary = snapshot()
	var base: String = path.get_base_dir()
	var slug: String = id.get_slice(":", 1)
	if kind == "block":
		var asset: AstraeonBlockAsset = AstraeonBlockAsset.new()
		if not source.is_empty():
			asset = source.asset.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		else:
			asset.block = AstraeonBlockDefinition.new()
			asset.block.appearance = AstraeonBlockAppearance.new()
			asset.block.appearance.default_surface = AstraeonBlockSurface.new()
		asset.block.key = StringName(id)
		asset.block.display_name = slug
		if paired:
			if asset.item == null: asset.item = AstraeonItemDefinition.new()
			asset.item.key = StringName(id + "_item")
			asset.item.display_name = slug
			asset.item.block = null
		else:
			asset.item = null
			asset.image_slots.erase("item/icon")
		project.blocks.append(asset)
		block_paths.append(base.path_join("blocks/" + slug + ".tres"))
	elif kind == "item":
		var asset: AstraeonItemAsset = AstraeonItemAsset.new()
		asset.item = AstraeonItemDefinition.new() if source.is_empty() else source.data.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		asset.item.key = StringName(id)
		asset.item.display_name = slug
		asset.item.block = null
		asset.item.orient_to_face = false
		if not source.is_empty():
			asset.icon_image = source.asset.image_slots.get("item/icon", &"") if source.kind == "paired" else source.asset.icon_image
		project.items.append(asset)
		item_paths.append(base.path_join("items/" + slug + ".tres"))
	else:
		var fluid: AstraeonFluidDefinition = AstraeonFluidDefinition.new() if source.is_empty() else source.data.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		fluid.key = StringName(id)
		fluid.display_name = slug
		if fluid.appearance == null: fluid.appearance = AstraeonWaterAppearance.new()
		project.fluids.append(fluid)
		fluid_paths.append(base.path_join("fluids/" + slug + ".tres"))
	commit(before, "新增 / 复制资源", true)
	return true

func remove(row: Dictionary) -> bool:
	error = ""
	var id: StringName = row.data.key
	# Explicit reference check; owned paired item is removed with its block.
	for asset: AstraeonItemAsset in project.items:
		if asset.item.block != null and asset.item.block.key == id:
			error = "被物品引用：" + String(asset.item.key)
			return false
	var before: Dictionary = snapshot()
	match String(row.kind):
		"block":
			project.blocks.remove_at(row.index)
			block_paths.remove_at(row.index)
		"paired":
			project.blocks[row.index].item = null
			project.blocks[row.index].image_slots.erase("item/icon")
		"item":
			project.items.remove_at(row.index)
			item_paths.remove_at(row.index)
		"fluid":
			project.fluids.remove_at(row.index)
			fluid_paths.remove_at(row.index)
	commit(before, "移出包（保留文件）", true)
	return true

func image_path(key: StringName) -> String:
	var source: String = project.image_sources.get(key, "")
	if source.is_empty(): return ""
	if source.is_absolute_path(): return source.simplify_path()
	return ProjectSettings.globalize_path(path.get_base_dir()).path_join(source).simplify_path()

static func relative_image(base: String, file: String) -> String:
	var a: PackedStringArray = ProjectSettings.globalize_path(base).replace("\\", "/").simplify_path().split("/")
	var b: PackedStringArray = file.replace("\\", "/").simplify_path().split("/")
	if a[0].to_lower() != b[0].to_lower(): return file
	var index: int = 0
	while index < mini(a.size(), b.size()) and a[index].to_lower() == b[index].to_lower(): index += 1
	var parts: PackedStringArray = []
	for unused: int in range(a.size() - index): parts.append("..")
	parts.append_array(b.slice(index))
	return "/".join(parts)

func set_image(asset: Resource, slot: String, key: StringName) -> void:
	var before: Dictionary = snapshot()
	if asset is AstraeonBlockAsset:
		if key.is_empty(): asset.image_slots.erase(slot)
		else: asset.image_slots[slot] = key
	else: asset.icon_image = key
	commit(before, "图片索引", true)

func bind_file(asset: Resource, slot: String, file: String) -> bool:
	error = ""
	if not FileAccess.file_exists(file):
		error = "图片不存在：" + file
		return false
	var before: Dictionary = snapshot()
	var key: StringName = StringName("image_" + file.sha256_text().left(12))
	for known: StringName in project.image_sources:
		if image_path(known) == file.simplify_path(): key = known
	project.image_sources[key] = relative_image(path.get_base_dir(), file)
	if asset is AstraeonBlockAsset: asset.image_slots[slot] = key
	else: asset.icon_image = key
	commit(before, "选择源图片", true)
	return true

func remove_image(key: StringName) -> bool:
	for asset: AstraeonBlockAsset in project.blocks:
		for slot: String in asset.image_slots:
			if asset.image_slots[slot] == key:
				error = "图片被引用：" + String(asset.block.key) + " / " + slot
				return false
	for asset: AstraeonItemAsset in project.items:
		if asset.icon_image == key:
			error = "图片被引用：" + String(asset.item.key)
			return false
	var before: Dictionary = snapshot()
	project.image_sources.erase(key)
	commit(before, "移除图片索引", true)
	return true

func all_files() -> Array[String]:
	var files: Array[String] = [path]
	files.append_array(block_paths)
	files.append_array(item_paths)
	files.append_array(fluid_paths)
	return files

func remember_files() -> void:
	fingerprints.clear()
	for file: String in all_files():
		fingerprints[file] = FileAccess.get_sha256(file) if FileAccess.file_exists(file) else ""

func external_changes() -> PackedStringArray:
	var changed_files: PackedStringArray = []
	for file: String in all_files():
		var current: String = FileAccess.get_sha256(file) if FileAccess.file_exists(file) else ""
		if current != fingerprints.get(file, ""): changed_files.append(file)
	return changed_files

func save_all(overwrite: bool = false) -> bool:
	error = ""
	if project == null: return false
	var changes: PackedStringArray = external_changes()
	if not overwrite and not changes.is_empty():
		error = "文件已在外部变化：\n" + "\n".join(changes)
		return false
	var saved: AstraeonContentManifest = project.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	# Each source file uses atomic replacement; manifest commits after its referenced files.
	for index: int in range(project.blocks.size()):
		if not save_resource(project.blocks[index], block_paths[index]): return false
		saved.blocks[index] = ResourceLoader.load(block_paths[index], "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	for index: int in range(project.items.size()):
		if not save_resource(project.items[index], item_paths[index]): return false
		saved.items[index] = ResourceLoader.load(item_paths[index], "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	for index: int in range(project.fluids.size()):
		if not save_resource(project.fluids[index], fluid_paths[index]): return false
		saved.fluids[index] = ResourceLoader.load(fluid_paths[index], "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if not save_resource(saved, path): return false
	remember_files()
	saved_version = history.get_version()
	changed.emit(false)
	return true

func save_resource(resource: Resource, file: String) -> bool:
	var code: Error = DirAccess.make_dir_recursive_absolute(file.get_base_dir())
	if code != OK:
		error = "无法创建目录 " + file.get_base_dir() + ": " + error_string(code)
		return false
	var temporary: String = file.get_basename() + ".pending.tres"
	code = ResourceSaver.save(resource, temporary)
	if code == OK: code = DirAccess.rename_absolute(temporary, file)
	if code != OK:
		error = "保存失败 " + file + ": " + error_string(code)
		return false
	return true

## Private compiler input with absolute indexed sources; never registers source paths in cache.
func compiler_input(row: Dictionary = {}) -> AstraeonContentManifest:
	var copy: AstraeonContentManifest = project.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	for key: StringName in copy.image_sources: copy.image_sources[key] = image_path(key)
	if not row.is_empty():
		copy.blocks.clear()
		copy.items.clear()
		copy.fluids.clear()
		copy.dependencies.clear()
		match String(row.kind):
			"block", "paired":
				copy.blocks.append(row.asset.duplicate_deep(Resource.DEEP_DUPLICATE_ALL))
			"item":
				copy.items.append(row.asset.duplicate_deep(Resource.DEEP_DUPLICATE_ALL))
			"fluid":
				copy.fluids.append(row.asset.duplicate_deep(Resource.DEEP_DUPLICATE_ALL))
	return copy

func compile(output: String, validate_only: bool = false) -> Dictionary:
	var identifiers: Dictionary[String, bool] = {}
	for category: String in ["block", "item", "fluid"]:
		for row: Dictionary in rows(category):
			var id: String = String(row.data.key)
			if not Compiler._id(id) or id.get_slice(":",0) != project.package_id or identifiers.has(id):
				return {"error": row.file + " · key：无效、重复或其他命名空间的内容 ID：" + id}
			identifiers[id] = true
	var compiler: RefCounted = Compiler.new()
	var source: AstraeonContentManifest = compiler_input() if validate_only else ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	return compiler.build(source, output, validate_only)
