@tool
extends RefCounted
## Offline only. Resolve explicit developer-selected image paths into private compiler inputs.
var error: String = ""
var source_hashes: Dictionary[String, String] = {}
var _textures: Dictionary[String, Texture2D] = {}
var _project: AstraeonContentManifest

func resolve(project: AstraeonContentManifest) -> Dictionary:
	_project = project
	error = ""
	source_hashes.clear()
	_textures.clear()
	if project == null or project.project_format != 2:
		return {"error": "Unsupported content project format (expected 2)"}
	var blocks: Array[AstraeonBlockDefinition] = []
	var items: Array[AstraeonItemDefinition] = []
	for asset: AstraeonBlockAsset in project.blocks:
		if asset == null or asset.block == null or asset.block.appearance == null:
			return {"error": "Block asset requires a block and appearance"}
		var block: AstraeonBlockDefinition = asset.block.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as AstraeonBlockDefinition
		var appearance: AstraeonBlockAppearance = block.appearance
		var surfaces: Dictionary[String, AstraeonBlockSurface] = {"surface/default": appearance.default_surface}
		for face: int in appearance.face_surfaces:
			surfaces["surface/" + str(face)] = appearance.face_surfaces[face]
		for slot: String in surfaces:
			var surface: AstraeonBlockSurface = surfaces[slot]
			if surface == null or surface.albedo_texture != null or surface.normal_texture != null or surface.orm_texture != null or surface.emission_texture != null:
				return {"error": "Use project image indexes, not embedded/imported textures: " + String(block.key) + " " + slot}
		if appearance.breaking != null and appearance.breaking.stages_texture != null:
			return {"error": "Use the breaking image slot: " + String(block.key)}
		var item: AstraeonItemDefinition
		if asset.item != null:
			if asset.item.block != null or asset.item.icon != null:
				return {"error": "Embedded block item must not reference a block or texture: " + String(block.key)}
			item = asset.item.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as AstraeonItemDefinition
			item.block = block
			items.append(item)
		for slot: String in asset.image_slots:
			var texture: Texture2D = _image(asset.image_slots[slot])
			if texture == null:
				return {"error": String(block.key) + " " + slot + ": " + error}
			if surfaces.has(slot):
				surfaces[slot].albedo_texture = texture
			elif slot == "breaking" and appearance.breaking != null:
				appearance.breaking.stages_texture = texture
			elif slot == "item/icon" and item != null:
				item.icon = texture
			else:
				return {"error": "Unknown or unavailable image slot: " + String(block.key) + " " + slot}
		blocks.append(block)
	for asset: AstraeonItemAsset in project.items:
		if asset == null or asset.item == null or asset.item.block != null or asset.item.icon != null:
			return {"error": "Independent item asset must contain a non-block item without imported textures"}
		var item: AstraeonItemDefinition = asset.item.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as AstraeonItemDefinition
		if not asset.icon_image.is_empty():
			item.icon = _image(asset.icon_image)
			if item.icon == null:
				return {"error": String(item.key) + ": " + error}
		items.append(item)
	return {"blocks": blocks, "items": items}

func _image(key: StringName) -> Texture2D:
	if key.is_empty() or not _project.image_sources.has(key):
		error = "Missing image index: " + String(key)
		return null
	var source: String = _project.image_sources[key]
	if source.is_empty() or source.begins_with("user://") or "://" in source:
		error = "Image source must be an explicit filesystem path (absolute or project-relative): " + source
		return null
	var path: String = source
	if not path.is_absolute_path():
		if _project.resource_path.is_empty():
			error = "Relative image path requires a saved package project: " + source
			return null
		path = ProjectSettings.globalize_path(_project.resource_path.get_base_dir()).path_join(source)
	path = path.simplify_path()
	if _textures.has(path):
		return _textures[path]
	if not FileAccess.file_exists(path):
		error = "Image source not found: " + path
		return null
	var image: Image = Image.new()
	var code: Error = image.load(path)
	if code != OK or image.is_empty():
		error = "Cannot decode image " + path + ": " + error_string(code)
		return null
	image.convert(Image.FORMAT_RGBA8)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	source_hashes[path] = FileAccess.get_sha256(path)
	_textures[path] = texture
	return texture
