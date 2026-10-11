@tool
extends RefCounted
## Authoring frontend: explicit records only. Native code owns pixel processing and container I/O.
const COMPILER_VERSION: String = "aeb-content-1.5"
const WATER_FIELDS: PackedStringArray = ["shallow_color", "deep_color", "absorption", "opacity", "uniform_opacity", "roughness", "specular", "wave_strength", "wave_scale", "wave_speed", "sky_strength", "scene_reflection_strength", "underwater_color", "underwater_attenuation_rate", "underwater_attenuation_start"]
var error: String = ""
var _native: RefCounted
var _images: Dictionary[String, Image] = {}
var _blobs: Dictionary = {}
var _visuals: Dictionary = {}
var _cache_directory: String = "res://tmp/content/compiler_cache"
var cache_hits: int = 0
var compiled_visuals: int = 0

func build(manifest: Resource, output: String, validate_only: bool = false) -> Dictionary:
	if not ClassDB.class_exists("AstraeonContentPack"):
		return {"error": "Content compiler DLL is not loaded; restart with the rebuilt extension"}
	_native = ClassDB.instantiate("AstraeonContentPack")
	error = ""
	_blobs.clear()
	_visuals.clear()
	_images.clear()
	cache_hits = 0
	compiled_visuals = 0
	if not manifest is AstraeonContentManifest or manifest.content_api != 1:
		return {"error": "Unsupported content API"}
	var resolver: RefCounted = preload("res://tools/content/project_resolver.gd").new()
	var resolved: Dictionary = resolver.resolve(manifest)
	if resolved.has("error"):
		return resolved
	var definitions: Dictionary = {"api": 1, "id": manifest.package_id, "name": manifest.display_name, "compiler": COMPILER_VERSION, "dependencies": Array(manifest.dependencies), "groups": _string_dictionary(manifest.creative_groups), "blocks": [], "items": []}
	var keys: Dictionary[String, bool] = {}
	for block: AstraeonBlockDefinition in resolved.blocks:
		if block == null or not _id(String(block.key)) or keys.has(String(block.key)) or block.appearance == null:
			return {"error": "Missing, duplicate or non-namespaced block ID"}
		if not is_finite(block.hardness) or block.hardness < 0.0:
			return {"error": "Invalid block hardness: " + String(block.key)}
		if (not block.required_tool_tag.is_empty() and not _id(String(block.required_tool_tag))) or not is_finite(block.mining_recovery_seconds) or block.mining_recovery_seconds < 0.0 or block.mining_recovery_seconds > 3600.0:
			return {"error": "Invalid mining tag/recovery: " + String(block.key)}
		keys[String(block.key)] = true
		var appearance: AstraeonBlockAppearance = block.appearance
		if not appearance.validate().is_empty():
			return {"error": "%s: %s" % [block.key, appearance.validate()]}
		var visual: Dictionary = _compile_appearance(appearance)
		if not error.is_empty():
			return {"error": error}
		var states: Array = []
		if block.states.is_empty():
			states.append({"name": "default", "logical_rotation": 0, "rotation": _native.call("rotation_index", appearance.authoring_orientation)})
		for state: AstraeonBlockStateDefinition in block.states:
			if state == null or not AstraeonBlockAppearance.is_cube_rotation(state.orientation):
				return {"error": "Invalid state rotation: " + String(block.key)}
			states.append({"name": String(state.key), "logical_rotation": _native.call("rotation_index", state.orientation), "rotation": _native.call("rotation_index", appearance.combined_orientation(state.orientation)), "properties": _string_dictionary(state.properties)})
		for state: Dictionary in states:
			if appearance.light != null:
				# Resolve rotation through the same native table used for meshes.
				var basis: Basis = appearance.authoring_orientation
				for authored_state: AstraeonBlockStateDefinition in block.states:
					if String(authored_state.key) == String(state.name):
						basis = appearance.combined_orientation(authored_state.orientation)
				var offset: Vector3 = basis * appearance.light.local_offset
				state["light_offset"] = [offset.x, offset.y, offset.z]
		states.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.name) < String(b.name))
		var record: Dictionary = {"id": String(block.key), "name": block.display_name, "hardness": block.hardness, "required_tool_tag": String(block.required_tool_tag), "mining_recovery_seconds": block.mining_recovery_seconds, "collision": block.collision_enabled, "opacity": block.light_opacity, "emission": block.light_emission, "load_policy": block.load_policy, "default_state": String(block.default_state), "states": states, "visual": visual.get("hash", ""), "surface": visual.parameters, "kind": "cube"}
		if appearance.light != null:
			var light: AstraeonBlockLightAppearance = appearance.light
			record["light"] = {"color": _color(light.color), "energy": light.energy, "range": light.range, "attenuation": light.attenuation, "offset": [light.local_offset.x, light.local_offset.y, light.local_offset.z], "radius": light.source_radius, "shadow_policy": light.shadow_policy}
		var breaking: Dictionary = _compile_breaking(appearance.breaking)
		if not error.is_empty():
			return {"error": error}
		record["breaking"] = breaking
		definitions.blocks.append(record)
	for fluid: AstraeonFluidDefinition in manifest.fluids:
		if fluid == null or not _id(String(fluid.key)) or keys.has(String(fluid.key)) or fluid.appearance == null or not fluid.appearance.validate().is_empty():
			return {"error": "Invalid or duplicate fluid"}
		keys[String(fluid.key)] = true
		var water: Dictionary = {}
		for field: String in WATER_FIELDS:
			var value: Variant = fluid.appearance.get(field)
			water[field] = _color(value) if value is Color else value
		definitions.blocks.append({"id": String(fluid.key), "name": fluid.display_name, "kind": "water", "breaking": {}, "collision": fluid.collision_enabled, "opacity": fluid.light_opacity, "emission": 0, "load_policy": "preload", "default_state": "default", "states": [{"name": "default", "logical_rotation": 0, "rotation": 0}], "visual": "", "water": water})
	for item: AstraeonItemDefinition in resolved.items:
		if item == null or not _id(String(item.key)) or (item.block == null and item.orient_to_face):
			return {"error": "Invalid item or orientation without block"}
		if not is_finite(item.mining_speed) or item.mining_speed < 1.0 or item.mining_speed > 1000.0:
			return {"error": "Invalid mining speed: " + String(item.key)}
		var seen_tool_tags: Dictionary[String, bool] = {}
		for tag: String in item.tool_tags:
			if not _id(tag) or seen_tool_tags.has(tag):
				return {"error": "Invalid or duplicate tool tag: " + String(item.key)}
			seen_tool_tags[tag] = true
		var icon: Dictionary = {}
		if item.icon != null:
			var source: Image = _image(item.icon)
			if source == null:
				return {"error": error}
			var pixels: PackedByteArray = _visual_payload(source.get_data(), source.get_width(), source.get_height())
			var hash: String = _hash(pixels)
			_blobs[hash] = pixels
			icon = {"icon": hash, "icon_width": source.get_width(), "icon_height": source.get_height()}
		var record: Dictionary = {"id": String(item.key), "name": item.display_name, "block": String(item.block.key) if item.block != null else "", "max_stack": item.max_stack, "tool_tags": Array(item.tool_tags), "mining_speed": item.mining_speed, "group": String(item.creative_group), "tags": Array(item.search_tags), "orient_to_face": item.orient_to_face, "color": _color(item.icon_color)}
		record.merge(icon)
		definitions.items.append(record)
	definitions.blocks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.id) < String(b.id))
	definitions.items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.id) < String(b.id))
	# Validation uses exactly the writer's schema; the disposable output never replaces a shipping pack.
	var target: String = "res://tmp/content/validate.aebpack" if validate_only else output
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if directory_error != OK: return {"error": "Cannot create output directory " + target.get_base_dir() + ": " + error_string(directory_error)}
	var canonical: Dictionary = JSON.parse_string(JSON.stringify(definitions, "", true, true))
	var result: Dictionary = _native.call("write_pack", target, canonical, _blobs)
	if not validate_only and not result.has("error") and not manifest.resource_path.is_empty():
		var dependencies: Dictionary[String, String] = {}
		_source_hashes(manifest.resource_path, dependencies)
		dependencies.merge(resolver.source_hashes)
		_source_hashes("res://tools/content/project_resolver.gd", dependencies)
		_source_hashes("res://tools/content/compiler.gd", dependencies)
		_source_hashes("res://game/data/native/content/astraeon_content_pack.cpp", dependencies)
		var receipt_path: String = output + ".receipt.json"
		var receipt: FileAccess = FileAccess.open(receipt_path + ".pending", FileAccess.WRITE)
		if receipt == null: return {"error": "Pack written but cannot write build receipt " + receipt_path + ": " + error_string(FileAccess.get_open_error())}
		receipt.store_string(JSON.stringify({"pack_sha256": FileAccess.get_sha256(output), "sources": dependencies}, "", true, true))
		receipt.flush()
		var receipt_error: Error = receipt.get_error()
		receipt.close()
		if receipt_error == OK: receipt_error = DirAccess.rename_absolute(receipt_path + ".pending", receipt_path)
		if receipt_error != OK: return {"error": "Pack written but cannot commit build receipt " + receipt_path + ": " + error_string(receipt_error)}
	result["compiled_visuals"] = compiled_visuals
	result["cache_hits"] = cache_hits
	result["decoded_images"] = _images.size()
	return result

func _compile_breaking(group: AstraeonBreakingTextureGroup) -> Dictionary:
	if group == null:
		return {}
	if group.stages_texture == null or not is_finite(group.strength) or group.strength < 0.0 or group.strength > 1.0:
		error = "Invalid breaking texture group"
		return {}
	var source: Image = _image(group.stages_texture)
	if source == null:
		return {}
	var size: int = source.get_height()
	if size < 1 or size > 1024 or source.get_width() != size * 10:
		error = "Breaking group must contain exactly ten square stages in one horizontal strip (1..1024 pixels per stage)"
		return {}
	var bytes: PackedByteArray = _visual_payload(source.get_data(), source.get_width(), size)
	var hash: String = _hash(bytes)
	_blobs[hash] = bytes
	return {"visual": hash, "resolution": size, "stages": 10, "tint": _color(group.tint), "strength": group.strength}

func _compile_appearance(appearance: AstraeonBlockAppearance) -> Dictionary:
	var faces: Array = []
	var fingerprint: Array = [COMPILER_VERSION, appearance.texture_resolution]
	var mode: AstraeonBlockSurface = appearance.default_surface
	for face: int in range(6):
		var s: AstraeonBlockSurface = appearance.surface_for_face(face)
		if s.normal_texture != null or s.orm_texture != null or s.emission_texture != null or s.alpha_mode == AstraeonBlockSurface.AlphaMode.BLEND:
			error = "Unsupported texture channel or blended block"
			return {}
		if s.alpha_mode != mode.alpha_mode or s.alpha_cutoff != mode.alpha_cutoff or s.double_sided != mode.double_sided or s.specular != mode.specular:
			error = "All faces must share alpha, cutoff, sidedness and specular"
			return {}
		var im: Image = _image(s.albedo_texture) if s.albedo_texture != null else null
		if not error.is_empty():
			return {}
		var glow: Color = s.emission_color * s.emission_energy
		var rotation: int = appearance.face_uv_rotations.get(face, 0)
		var mirror: Vector2i = appearance.face_uv_mirrors.get(face, Vector2i.ZERO)
		faces.append({"image": im, "color": s.base_color, "roughness": s.roughness, "metallic": s.metallic, "emission": glow, "rotation": rotation, "mirror": mirror})
		fingerprint.append([_hash(im.get_data()) if im != null else "", im.get_width() if im != null else 0, im.get_height() if im != null else 0, _color(s.base_color), s.roughness, s.metallic, _color(glow), rotation, mirror.x, mirror.y])
	fingerprint.append([mode.alpha_mode, mode.alpha_cutoff, mode.double_sided, mode.specular, appearance.foliage_layers])
	var key: String = JSON.stringify(fingerprint, "", true, true).sha256_text()
	if _visuals.has(key):
		cache_hits += 1
		return _visuals[key]
	DirAccess.make_dir_recursive_absolute(_cache_directory)
	var cache_path: String = _cache_directory.path_join(key + ".json")
	var cached: Variant = JSON.parse_string(FileAccess.get_file_as_string(cache_path)) if FileAccess.file_exists(cache_path) else null
	if cached is Dictionary and cached.has("parameters"):
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(_cache_directory.path_join(key + ".rgba")) if not String(cached.hash).is_empty() else PackedByteArray()
		if (String(cached.hash).is_empty() and bytes.is_empty()) or _hash(bytes) == cached.hash:
			if not bytes.is_empty():
				_blobs[cached.hash] = bytes
			cache_hits += 1
			_visuals[key] = cached
			return cached
	var result: Dictionary = _native.call("compile_visual", faces, appearance.texture_resolution)
	if result.has("error"):
		error = result.error
		return {}
	var pixels: PackedByteArray = result.pixels
	if not pixels.is_empty():
		pixels = _visual_payload(pixels, appearance.texture_resolution * 6, appearance.texture_resolution)
	result.erase("pixels")
	result.merge({"alpha": mode.alpha_mode, "cutoff": mode.alpha_cutoff, "double_sided": mode.double_sided, "specular": mode.specular, "foliage_layers": appearance.foliage_layers})
	var hash: String = "" if pixels.is_empty() else _hash(pixels)
	if not pixels.is_empty():
		_blobs[hash] = pixels
		var raw_file: FileAccess = FileAccess.open(_cache_directory.path_join(key + ".rgba"), FileAccess.WRITE)
		if raw_file != null:
			raw_file.store_buffer(pixels)
	var compiled: Dictionary = {"hash": hash, "parameters": result}
	var cache_file: FileAccess = FileAccess.open(cache_path, FileAccess.WRITE)
	if cache_file != null:
		cache_file.store_string(JSON.stringify(compiled, "", true, true))
	_visuals[key] = compiled
	compiled_visuals += 1
	return compiled

func _image(texture: Texture2D) -> Image:
	var key: String = texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_instance_id())
	if _images.has(key):
		return _images[key]
	var image: Image = texture.get_image()
	if image == null or image.is_empty() or (image.is_compressed() and image.decompress() != OK):
		error = "Cannot decode source image: " + key
		return null
	image.convert(Image.FORMAT_RGBA8)
	_images[key] = image
	return image

static func _hash(bytes: PackedByteArray) -> String:
	var hashing: HashingContext = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()

static func _color(value: Color) -> Array:
	return [value.r, value.g, value.b, value.a]

static func _id(value: String) -> bool:
	var parts: PackedStringArray = value.split(":")
	if parts.size() != 2 or parts[0].is_empty() or parts[1].is_empty():
		return false
	for character: String in value:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789_:-.":
			return false
	return true

static func _string_dictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in source:
		result[String(key)] = String(source[key])
	return result

static func _source_hashes(path: String, hashes: Dictionary[String, String]) -> void:
	if hashes.has(path) or not FileAccess.file_exists(path):
		return
	hashes[path] = FileAccess.get_sha256(path)
	if path.get_extension() in ["tres", "res", "tscn"]:
		for dependency: String in ResourceLoader.get_dependencies(path):
			var target: String = dependency.split("::")[-1]
			_source_hashes(target, hashes)

static func _visual_payload(pixels: PackedByteArray, width: int, height: int) -> PackedByteArray:
	# Hash interpretation as well as pixel bytes: RGBA8, sRGB albedo, nearest, no mipmaps.
	var header: PackedByteArray = PackedByteArray()
	header.resize(16)
	header.encode_u32(0, 0x31545641) # AVT1
	header.encode_u32(4, width)
	header.encode_u32(8, height)
	header.encode_u32(12, 1)
	header.append_array(pixels)
	return header
