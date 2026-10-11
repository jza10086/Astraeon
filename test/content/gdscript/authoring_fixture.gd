extends RefCounted
## Tests only: construct indexed source images from generated fixture pixels.
static func add_block(project: AstraeonContentManifest, block: AstraeonBlockDefinition) -> AstraeonBlockAsset:
	var asset: AstraeonBlockAsset = AstraeonBlockAsset.new()
	asset.block = block
	project.blocks.append(asset)
	var surfaces: Dictionary[String, AstraeonBlockSurface] = {"surface/default": block.appearance.default_surface}
	for face: int in block.appearance.face_surfaces:
		surfaces["surface/" + str(face)] = block.appearance.face_surfaces[face]
	for slot: String in surfaces:
		if surfaces[slot].albedo_texture != null:
			bind_image(project, asset, slot, surfaces[slot].albedo_texture.get_image())
			surfaces[slot].albedo_texture = null
	if block.appearance.breaking != null and block.appearance.breaking.stages_texture != null:
		bind_image(project, asset, "breaking", block.appearance.breaking.stages_texture.get_image())
		block.appearance.breaking.stages_texture = null
	return asset

static func bind_image(project: AstraeonContentManifest, asset: AstraeonBlockAsset, slot: String, image: Image) -> void:
	var key: StringName = StringName(String(asset.block.key).replace(":", "_") + "_" + slot.replace("/", "_"))
	var directory: String = "res://tmp/content/fixture_images"
	assert(DirAccess.make_dir_recursive_absolute(directory) == OK)
	var path: String = directory.path_join(String(key) + ".png")
	assert(image.save_png(path) == OK, "Fixture image write failed: " + path)
	project.image_sources[key] = ProjectSettings.globalize_path(path)
	asset.image_slots[slot] = key

## Save editable fixture assets and portable source-image indexes for the SDK.
static func save_project(project: AstraeonContentManifest, path: String) -> Error:
	var base: String = path.get_base_dir().path_join(project.package_id)
	var code: Error = DirAccess.make_dir_recursive_absolute(base + "/blocks")
	if code != OK: return code
	code = DirAccess.make_dir_recursive_absolute(base + "/images")
	if code != OK: return code
	var ignore: FileAccess = FileAccess.open(base + "/images/.gdignore", FileAccess.WRITE)
	if ignore == null: return FileAccess.get_open_error()
	ignore.close()
	for key: StringName in project.image_sources:
		var destination: String = base + "/images/" + String(key) + ".png"
		code = DirAccess.copy_absolute(project.image_sources[key], destination)
		if code != OK: return code
		project.image_sources[key] = destination.trim_prefix(path.get_base_dir() + "/")
	for asset: AstraeonBlockAsset in project.blocks:
		code = ResourceSaver.save(asset, base + "/blocks/" + String(asset.block.key).get_slice(":", 1) + ".tres", ResourceSaver.FLAG_CHANGE_PATH)
		if code != OK: return code
		asset.take_over_path(base + "/blocks/" + String(asset.block.key).get_slice(":", 1) + ".tres")
	project.take_over_path(path)
	return ResourceSaver.save(project, path)
