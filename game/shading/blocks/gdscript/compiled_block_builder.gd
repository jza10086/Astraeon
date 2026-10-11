@tool
extends RefCounted
## Builds shared models/materials from lightweight compiled records. No image processing.
static var _double_sided_opaque: Shader
static func block(record: Dictionary, rotation: int, cache: RefCounted, shared_material: Material = null) -> VoxelBlockyModelCube:
	var model: VoxelBlockyModelCube = VoxelBlockyModelCube.new()
	model.atlas_size_in_tiles = Vector2i(6, 1)
	var sides: Array[int] = [VoxelBlockyModel.SIDE_POSITIVE_Y, VoxelBlockyModel.SIDE_NEGATIVE_Y, VoxelBlockyModel.SIDE_NEGATIVE_Z, VoxelBlockyModel.SIDE_POSITIVE_Z, VoxelBlockyModel.SIDE_NEGATIVE_X, VoxelBlockyModel.SIDE_POSITIVE_X]
	for face: int in range(6):
		model.set_tile(sides[face], Vector2i(face, 0))
	model.mesh_ortho_rotation_index = rotation
	model.set_mesh_collision_enabled(0, bool(record.collision))
	if not bool(record.collision):
		model.collision_aabbs = []
	if record.kind == "cube":
		if int(record.surface.alpha) == 1:
			model.transparency_index = 2
		if bool(record.surface.foliage_layers):
			model.set_meta("astraeon_foliage_layers", true)
			model.culls_neighbors = false
	else:
		model.transparency_index = 1
	if shared_material != null:
		model.set_material_override(0, shared_material)
		return model
	var material: ShaderMaterial = ShaderMaterial.new()
	if record.kind == "water":
		material.shader = preload("res://game/shading/shaders/water.gdshader")
		model.transparency_index = 1
	else:
		var surface: Dictionary = record.surface
		var cutout: bool = int(surface.alpha) == 1
		material.shader = preload("res://game/shading/shaders/plant.gdshader") if cutout else preload("res://game/shading/shaders/voxel_light.gdshader")
		if not cutout and bool(surface.double_sided):
			if _double_sided_opaque == null:
				_double_sided_opaque = Shader.new()
				_double_sided_opaque.code = material.shader.code.replace("render_mode diffuse_lambert;", "render_mode diffuse_lambert, cull_disabled;")
			material.shader = _double_sided_opaque
		elif cutout and not bool(surface.double_sided):
			material.shader = preload("res://game/shading/shaders/plant_layered.gdshader")
		material.set_shader_parameter("pack_surface", true)
		material.set_shader_parameter("pack_textured", not String(record.visual).is_empty())
		material.set_shader_parameter("use_block_atlas", true)
		material.set_shader_parameter("authored_surface", true)
		material.set_shader_parameter("base_color", Color.WHITE)
		material.set_shader_parameter("block_cutout", cutout)
		material.set_shader_parameter("block_alpha_cutoff", float(surface.cutoff))
		material.set_shader_parameter("authored_specular", float(surface.specular))
		var colors: PackedColorArray = []
		var orm: PackedVector2Array = []
		var glow: PackedVector3Array = []
		for face: int in range(6):
			var color: Array = surface.colors[face]
			colors.append(Color(color[0], color[1], color[2], color[3]))
			orm.append(Vector2(surface.orm[face][0], surface.orm[face][1]))
			glow.append(Vector3(surface.glow[face][0], surface.glow[face][1], surface.glow[face][2]))
		material.set_shader_parameter("pack_colors", colors)
		material.set_shader_parameter("pack_orm", orm)
		material.set_shader_parameter("pack_glow", glow)
		if cutout:
			model.transparency_index = 2
		if bool(surface.foliage_layers):
			model.set_meta("astraeon_foliage_layers", true)
			model.culls_neighbors = false
		if not String(record.visual).is_empty():
			material.set_meta("astraeon_visual_hash", record.visual)
			cache.call("bind_material", record.visual, material)
	model.set_material_override(0, material)
	return model
