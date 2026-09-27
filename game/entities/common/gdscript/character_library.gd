extends RefCounted
const Paths: Script = preload("res://game/core/gdscript/project_paths.gd")
## External, self-contained GLBs. Editor imports and scripts are never loaded here.
const BASE: PackedScene = preload("res://game/entities/player/assets/basic_voxel.glb")
const CLIPS: Dictionary[StringName, float] = {&"Idle": 3.0, &"Walk": 64.0 / 60.0, &"Run": 0.6, &"Sprint": 0.5, &"JumpStart": 44.0 / 60.0, &"Fall": 1.0}
static var directory: String = Paths.characters_directory()
static var entries: Array[Dictionary] = []
static var errors: PackedStringArray = []
static var _cache: Dictionary[String, Dictionary] = {}
static var _scanned: bool = false

## Override the storage root for isolated fixtures; clear all derived cache state.
static func set_directory(path: String) -> void:
	directory = path
	_cache.clear()
	entries.clear()
	errors.clear()
	_scanned = false

static func ensure_directory() -> Error:
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))

## Explicitly called on menu entry; hashes detect same-name replacements.
static func scan() -> void:
	entries.clear()
	errors.clear()
	_scanned = true
	if ensure_directory() != OK:
		errors.append("无法创建人物目录：" + directory)
		return
	var files: PackedStringArray = DirAccess.get_files_at(directory)
	files.sort()
	var present: PackedStringArray = []
	for file: String in files:
		if file.get_extension().to_lower() != "glb":
			continue
		var path: String = directory.path_join(file)
		present.append(path)
		var hash: String = FileAccess.get_sha256(path)
		if not _cache.has(path) or _cache[path].hash != hash:
			var result: Dictionary = _read_model(path)
			result["hash"] = hash
			_cache[path] = result
		if _cache[path].has("error"):
			errors.append(file + "：" + String(_cache[path].error))
		else:
			entries.append({"id": StringName("user/" + file), "name": file.get_basename(), "path": path})
	for path: String in _cache.keys():
		if not path in present:
			_cache.erase(path)

static func ensure_scanned() -> void:
	if not _scanned:
		scan()

static func definition(id: StringName) -> Dictionary:
	ensure_scanned()
	for entry: Dictionary in entries:
		if entry.id == id:
			return entry
	return {}

static func instantiate(id: StringName) -> Node3D:
	var entry: Dictionary = definition(id)
	if entry.is_empty():
		return null
	# Recheck at use time as users can remove or replace a file while the menu is open.
	if not FileAccess.file_exists(entry.path) or FileAccess.get_sha256(entry.path) != _cache[entry.path].hash:
		scan()
		entry = definition(id)
		if entry.is_empty():
			return null
	return (_cache[entry.path].scene as PackedScene).instantiate() as Node3D

## Validate before copying, then publish with a rename; never overwrite an existing name.
static func import_file(source: String) -> Dictionary:
	if source.get_extension().to_lower() != "glb":
		return {"error": "请选择自包含的 GLB 文件。"}
	var result: Dictionary = _read_model(source)
	if result.has("error"):
		return result
	var error: Error = ensure_directory()
	if error != OK:
		return {"error": "无法创建人物目录：" + error_string(error)}
	var file: String = source.get_file()
	var target: String = directory.path_join(file)
	var source_hash: String = FileAccess.get_sha256(source)
	if FileAccess.file_exists(target):
		if FileAccess.get_sha256(target) != source_hash:
			return {"error": "已存在同名人物，请重命名文件后导入：" + file}
	else:
		var temporary: String = target + ".importing"
		error = DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(temporary))
		if error == OK and FileAccess.get_sha256(temporary) != source_hash:
			error = ERR_FILE_CORRUPT
		if error == OK:
			error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(target))
		if error != OK:
			if FileAccess.file_exists(temporary):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
			return {"error": "复制人物失败：" + error_string(error)}
	result["hash"] = source_hash
	_cache[target] = result
	scan()
	return {"id": StringName("user/" + file)}

## Only delete the exact scanned GLB inside the configured user directory.
static func delete_file(id: StringName) -> Error:
	var entry: Dictionary = definition(id)
	if entry.is_empty():
		return ERR_INVALID_PARAMETER
	var path: String = ProjectSettings.globalize_path(entry.path).simplify_path()
	if path.get_base_dir() != ProjectSettings.globalize_path(directory).simplify_path() or path.get_extension().to_lower() != "glb":
		return ERR_INVALID_PARAMETER
	var error: Error = DirAccess.remove_absolute(path)
	if error == OK:
		scan()
	return error

static func _read_model(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "无法读取文件。"}
	if file.get_length() < 20 or file.get_length() > 134217728:
		return {"error": "GLB 文件大小须小于 128 MiB，且包含有效内容。"}
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	if bytes.decode_u32(0) != 0x46546c67 or bytes.decode_u32(4) != 2 or bytes.decode_u32(8) != bytes.size() or bytes.decode_u32(16) != 0x4e4f534a:
		return {"error": "不是有效的 GLB 2.0 文件。"}
	var json_length: int = bytes.decode_u32(12)
	if json_length <= 0 or json_length > bytes.size() - 20:
		return {"error": "GLB 数据不完整。"}
	var parser: JSON = JSON.new()
	if parser.parse(bytes.slice(20, 20 + json_length).get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return {"error": "GLB 描述无法解析。"}
	var metadata: Dictionary = parser.data
	for group: String in ["buffers", "images"]:
		var items: Variant = metadata.get(group, [])
		if not items is Array:
			return {"error": "GLB 的 " + group + " 格式无效。"}
		for item: Variant in items:
			if not item is Dictionary:
				return {"error": "GLB 资源描述无效。"}
			if item.has("uri") and (not item.uri is String or not String(item.uri).begins_with("data:")):
				return {"error": "请将贴图与数据嵌入 GLB，不支持外部文件引用。"}
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	var flags: int = GLTFDocument.IMPORT_FLAG_GENERATE_TANGENT_ARRAYS | GLTFDocument.IMPORT_FLAG_USE_NAMED_SKIN_BINDS | GLTFDocument.IMPORT_FLAG_FORCE_DISABLE_MESH_COMPRESSION
	var error: Error = document.append_from_buffer(bytes, "", state, flags)
	if error != OK:
		return {"error": "GLB 加载失败：" + error_string(error)}
	var model: Node3D = document.generate_scene(state, 240.0, false, false) as Node3D
	if model == null:
		return {"error": "无法生成人物场景。"}
	var problem: String = _validate(model)
	if not problem.is_empty():
		model.free()
		return {"error": problem}
	var scene: PackedScene = PackedScene.new()
	error = scene.pack(model)
	model.free()
	return {"scene": scene} if error == OK else {"error": "无法保存人物场景：" + error_string(error)}

static func _validate(model: Node3D) -> String:
	var skeletons: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
	var animation: AnimationPlayer = model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if skeletons.size() != 1 or animation == null:
		return "需要一个骨架和根节点下的 AnimationPlayer。"
	if model.find_children("*", "MeshInstance3D", true, false).is_empty():
		return "人物没有网格。"
	var reference: Node3D = BASE.instantiate() as Node3D
	var baseline: Skeleton3D = reference.find_child("Skeleton3D", true, false) as Skeleton3D
	var skeleton: Skeleton3D = skeletons[0] as Skeleton3D
	var problem: String = ""
	for index: int in range(baseline.get_bone_count()):
		var name: String = baseline.get_bone_name(index)
		var bone: int = skeleton.find_bone(name)
		if bone < 0:
			problem = "缺少标准主体骨：" + name
			break
		var parent: int = baseline.get_bone_parent(index)
		var actual_parent: int = skeleton.get_bone_parent(bone)
		if (parent < 0 and actual_parent >= 0) or (parent >= 0 and (actual_parent < 0 or skeleton.get_bone_name(actual_parent) != baseline.get_bone_name(parent))):
			problem = "主体骨层级不匹配：" + name
			break
		var rest: Transform3D = skeleton.get_bone_rest(bone)
		var expected: Transform3D = baseline.get_bone_rest(index)
		if rest.origin.distance_to(expected.origin) > 0.001 or not rest.basis.is_equal_approx(expected.basis):
			problem = "主体骨静止姿态或比例不匹配：" + name
			break
	if not _root_transform(skeleton).is_equal_approx(_root_transform(baseline)):
		problem = "骨架根变换不符合标准，请保持人物原点、朝向和缩放。"
	reference.free()
	if not problem.is_empty():
		return problem
	for clip: StringName in CLIPS:
		if not animation.has_animation(clip):
			return "缺少动作：" + String(clip)
		var action: Animation = animation.get_animation(clip)
		if absf(action.length - CLIPS[clip]) > 0.01:
			return "动作时长不符合当前标准：" + String(clip)
		action.loop_mode = Animation.LOOP_NONE if clip == &"JumpStart" else Animation.LOOP_LINEAR
	return ""

static func _root_transform(node: Node3D) -> Transform3D:
	var transform: Transform3D = node.transform
	var parent: Node = node.get_parent()
	while parent is Node3D:
		transform = (parent as Node3D).transform * transform
		parent = parent.get_parent()
	return transform
