extends RefCounted
const Paths: Script = preload("res://game/core/gdscript/project_paths.gd")
const Standard: Script = preload("res://game/entities/common/gdscript/character_rig_standard.gd")
## One directory and selection ID per complete TP/FP pair. No legacy file reader.
const CLIPS: Dictionary[StringName, float] = {&"Idle": 3.0, &"Walk": 64.0 / 60.0, &"Run": 0.6, &"Sprint": 0.5, &"JumpStart": 44.0 / 60.0, &"Fall": 1.0, &"HoldBlock_R": 2.0, &"HoldBlock_L": 2.0}
const FP_CLIPS: Dictionary[StringName, float] = {&"FP_Idle": 2.0, &"FP_HoldBlock_R": 2.0, &"FP_HoldBlock_L": 2.0}
static var directory: String = Paths.characters_directory()
static var entries: Array[Dictionary] = []
static var errors: PackedStringArray = []
static var _cache: Dictionary[String, Dictionary] = {}
static var _scanned: bool = false

static func set_directory(path: String) -> void:
	directory = path
	_cache.clear()
	entries.clear()
	errors.clear()
	_scanned = false

static func ensure_directory() -> Error:
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))

static func scan() -> void:
	entries.clear()
	errors.clear()
	_scanned = true
	var error: Error = ensure_directory()
	if error != OK:
		errors.append("无法创建人物目录：" + directory + " / " + error_string(error))
		return
	var folders: PackedStringArray = DirAccess.get_directories_at(directory)
	folders.sort()
	var present: PackedStringArray = []
	for name: String in folders:
		if name.begins_with("."):
			errors.append("未完成的人物文件操作，请检查：" + directory.path_join(name))
			continue
		var folder: String = directory.path_join(name)
		present.append(folder)
		var tp: String = folder.path_join(name + "_tp.glb")
		var fp: String = folder.path_join(name + "_fp.glb")
		if not FileAccess.file_exists(tp) or not FileAccess.file_exists(fp):
			_cache.erase(folder)
			errors.append(name + "：需要同名的 " + name + "_tp.glb 和 " + name + "_fp.glb")
			continue
		var hash: String = FileAccess.get_sha256(tp) + FileAccess.get_sha256(fp)
		if not _cache.has(folder) or _cache[folder].hash != hash:
			var pair: Dictionary = _read_pair(folder)
			pair["hash"] = hash
			_cache[folder] = pair
		if _cache[folder].has("error"):
			errors.append(name + "：" + String(_cache[folder].error))
		else:
			entries.append({"id": StringName(name), "name": name, "folder": folder, "path": tp, "fp_path": fp})
	for file: String in DirAccess.get_files_at(directory):
		if file.get_extension().to_lower() == "glb":
			errors.append(file + "：不支持平铺 GLB，请放入同前缀的配对人物文件夹。")
	for folder: String in _cache.keys():
		if not folder in present:
			_cache.erase(folder)

static func ensure_scanned() -> void:
	if not _scanned:
		scan()

static func definition(id: StringName) -> Dictionary:
	ensure_scanned()
	for entry: Dictionary in entries:
		if entry.id == id:
			return entry
	return {}

static func instantiate(id: StringName, first_person: bool = false) -> Node3D:
	var entry: Dictionary = definition(id)
	if entry.is_empty():
		return null
	if not FileAccess.file_exists(entry.path) or not FileAccess.file_exists(entry.fp_path) or FileAccess.get_sha256(entry.path) + FileAccess.get_sha256(entry.fp_path) != _cache[entry.folder].hash:
		scan()
		entry = definition(id)
		if entry.is_empty():
			return null
	var scene: PackedScene = _cache[entry.folder].fp_scene if first_person else _cache[entry.folder].tp_scene
	return scene.instantiate() as Node3D

static func _read_pair(folder: String) -> Dictionary:
	var name: String = folder.get_file()
	if name.is_empty() or name.begins_with("."):
		return {"error": "人物文件夹名称无效：" + folder}
	var tp: Dictionary = _read_model(folder.path_join(name + "_tp.glb"), false)
	if tp.has("error"):
		return {"error": "第三人称：" + String(tp.error)}
	var fp: Dictionary = _read_model(folder.path_join(name + "_fp.glb"), true)
	if fp.has("error"):
		return {"error": "第一人称：" + String(fp.error)}
	return {"tp_scene": tp.scene, "fp_scene": fp.scene}

## Validate both files, then atomically publish the complete folder.
static func import_folder(source: String) -> Dictionary:
	source = ProjectSettings.globalize_path(source).simplify_path().trim_suffix("/")
	var pair: Dictionary = _read_pair(source)
	if pair.has("error"):
		return pair
	var error: Error = ensure_directory()
	if error != OK:
		return {"error": "创建人物目录失败：" + error_string(error)}
	var name: String = source.get_file()
	var target: String = ProjectSettings.globalize_path(directory).path_join(name)
	var files: PackedStringArray = [name + "_tp.glb", name + "_fp.glb"]
	if DirAccess.dir_exists_absolute(target):
		for file: String in files:
			if not FileAccess.file_exists(target.path_join(file)) or FileAccess.get_sha256(target.path_join(file)) != FileAccess.get_sha256(source.path_join(file)):
				return {"error": "已存在不同内容的人物文件夹：" + target}
	else:
		var temporary: String = ProjectSettings.globalize_path(directory).path_join(".importing_" + name)
		if DirAccess.dir_exists_absolute(temporary):
			return {"error": "存在未完成的导入目录，请检查：" + temporary}
		error = DirAccess.make_dir_absolute(temporary)
		if error != OK:
			return {"error": "创建临时目录失败：" + temporary + " / " + error_string(error)}
		for file: String in files:
			error = DirAccess.copy_absolute(source.path_join(file), temporary.path_join(file))
			if error != OK:
				return {"error": "复制失败：" + file + " / " + error_string(error) + "；临时目录：" + temporary}
			if FileAccess.get_sha256(source.path_join(file)) != FileAccess.get_sha256(temporary.path_join(file)):
				return {"error": "复制校验失败：" + temporary.path_join(file)}
		# Revalidate the copied snapshot before publishing; source files may change.
		for file: String in files:
			var copied: Dictionary = _read_model(temporary.path_join(file), file.ends_with("_fp.glb"))
			if copied.has("error"):
				return copied
		error = DirAccess.rename_absolute(temporary, target)
		if error != OK:
			return {"error": "发布人物失败：" + target + " / " + error_string(error)}
	scan()
	return {"id": StringName(name)}

## Remove only a scanned pair; never recursively delete unknown folder contents.
static func delete_folder(id: StringName) -> Error:
	var entry: Dictionary = definition(id)
	if entry.is_empty():
		return ERR_INVALID_PARAMETER
	var folder: String = ProjectSettings.globalize_path(entry.folder).simplify_path()
	if folder.get_base_dir() != ProjectSettings.globalize_path(directory).simplify_path():
		return ERR_INVALID_PARAMETER
	var files: PackedStringArray = DirAccess.get_files_at(folder)
	if files.size() != 2 or not DirAccess.get_directories_at(folder).is_empty() or not String(id) + "_tp.glb" in files or not String(id) + "_fp.glb" in files:
		return ERR_INVALID_DATA
	var removed: String = folder.get_base_dir().path_join(".deleting_" + String(id))
	if DirAccess.dir_exists_absolute(removed):
		return ERR_ALREADY_EXISTS
	var error: Error = DirAccess.rename_absolute(folder, removed)
	if error != OK:
		return error
	for file: String in files:
		error = DirAccess.remove_absolute(removed.path_join(file))
		if error != OK:
			return error
	error = DirAccess.remove_absolute(removed)
	scan()
	return error

static func _read_model(path: String, first_person: bool) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "无法读取文件：" + path + " / " + error_string(FileAccess.get_open_error())}
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
	var problem: String = _validate(model, first_person)
	if not problem.is_empty():
		model.free()
		return {"error": problem}
	var scene: PackedScene = PackedScene.new()
	error = scene.pack(model)
	model.free()
	return {"scene": scene} if error == OK else {"error": "无法保存人物场景：" + error_string(error)}

static func _validate(model: Node3D, first_person: bool) -> String:
	var skeletons: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
	var animation: AnimationPlayer = model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if skeletons.size() != 1 or animation == null:
		return "需要一个骨架和根节点下的 AnimationPlayer。"
	if model.find_children("*", "MeshInstance3D", true, false).is_empty():
		return "人物没有网格。"
	var skeleton: Skeleton3D = skeletons[0] as Skeleton3D
	for name: StringName in Standard.BONES:
		var expected: Dictionary = Standard.BONES[name]
		var bone: int = skeleton.find_bone(name)
		if bone < 0:
			return "缺少标准骨：" + String(name)
		var parent: int = skeleton.get_bone_parent(bone)
		var parent_name: StringName = skeleton.get_bone_name(parent) if parent >= 0 else &""
		if parent_name != expected.parent:
			return "骨层级不匹配：" + String(name)
		var rest: Transform3D = skeleton.get_bone_rest(bone)
		var reference: Transform3D = expected.rest
		if rest.origin.distance_to(reference.origin) > 0.001 or not rest.basis.is_equal_approx(reference.basis):
			return "骨骼静止姿态或比例不匹配：" + String(name)
	var root: Transform3D = Standard.FP_ROOT if first_person else Standard.TP_ROOT
	if not _root_transform(skeleton).is_equal_approx(root):
		return "骨架根变换不符合对应视角的标准。"
	var clips: Dictionary[StringName, float] = FP_CLIPS if first_person else CLIPS
	for clip: StringName in clips:
		if not animation.has_animation(clip):
			return "缺少动作：" + String(clip)
		var action: Animation = animation.get_animation(clip)
		if absf(action.length - clips[clip]) > 0.01:
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
