class_name AstraeonBlockLibraryBuilder
extends RefCounted
## Test-only reference for the removed runtime pixel-atlas compilation path.
## Resources/materials are per shared state, never per voxel. Unsupported surfaces fail explicitly.
static func build_block(definition: AstraeonBlockDefinition, orientation: Basis) -> VoxelBlockyModelCube:
	var appearance: AstraeonBlockAppearance = definition.appearance
	if appearance == null or not appearance.validate().is_empty() or not AstraeonBlockAppearance.is_cube_rotation(orientation):
		push_error("Invalid appearance/orientation: " + String(definition.key))
		return null
	var resolution: int = appearance.texture_resolution
	var image: Image = Image.create(6 * resolution, resolution, false, Image.FORMAT_RGBA8)
	var emission: Image = Image.create(6 * resolution, resolution, false, Image.FORMAT_RGBF)
	var max_emission: float = 0.0
	for face: int in range(6):
		max_emission = maxf(max_emission, appearance.surface_for_face(face).emission_energy)
	var orm: Image = Image.create(6 * resolution, resolution, false, Image.FORMAT_RGB8)
	var model: VoxelBlockyModelCube = VoxelBlockyModelCube.new()
	model.atlas_size_in_tiles = Vector2i(6, 1)
	var sides: Array[int] = [VoxelBlockyModel.SIDE_POSITIVE_Y, VoxelBlockyModel.SIDE_NEGATIVE_Y, VoxelBlockyModel.SIDE_NEGATIVE_Z, VoxelBlockyModel.SIDE_POSITIVE_Z, VoxelBlockyModel.SIDE_NEGATIVE_X, VoxelBlockyModel.SIDE_POSITIVE_X]
	for face: int in range(6):
		var authored: int = appearance.authored_face_for_world(face, orientation)
		var surface: AstraeonBlockSurface = appearance.surface_for_face(authored)
		if surface.normal_texture != null or surface.orm_texture != null or surface.emission_texture != null or surface.alpha_mode == AstraeonBlockSurface.AlphaMode.BLEND:
			push_error("Block compiler supports albedo textures, opaque/cutout and constant emission only")
			return null
		if surface.alpha_mode != appearance.default_surface.alpha_mode or surface.double_sided != appearance.default_surface.double_sided or surface.alpha_cutoff != appearance.default_surface.alpha_cutoff or surface.specular != appearance.default_surface.specular:
			push_error("All faces must share alpha mode, cutoff, sidedness and specular")
			return null
		var source: Image = surface.albedo_texture.get_image() if surface.albedo_texture != null else null
		if source != null and source.is_compressed():
			if source.decompress() != OK:
				return null
		for y: int in range(resolution):
			for x: int in range(resolution):
				var color: Color = surface.base_color
				if source != null:
					var uv: Vector2 = appearance.transform_uv(authored, Vector2(x + 0.5, y + 0.5) / float(resolution))
					color *= source.get_pixel(clampi(int(uv.x * source.get_width()), 0, source.get_width()-1), clampi(int(uv.y * source.get_height()), 0, source.get_height()-1))
				image.set_pixel(face * resolution + x, y, color)
		var glow: Color = surface.emission_color * (surface.emission_energy / max_emission if max_emission > 0.0 else 0.0)
		emission.fill_rect(Rect2i(face * resolution, 0, resolution, resolution), glow)
		orm.fill_rect(Rect2i(face * resolution, 0, resolution, resolution), Color(1.0, surface.roughness, surface.metallic))
		model.set_tile(sides[face], Vector2i(face, 0))
	var material: ORMMaterial3D = ORMMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.orm_texture = ImageTexture.create_from_image(orm)
	if appearance.default_surface.alpha_mode == AstraeonBlockSurface.AlphaMode.CUTOUT:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = appearance.default_surface.alpha_cutoff
		model.transparency_index = 2
	if appearance.default_surface.double_sided:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if max_emission > 0.0:
		material.emission_enabled = true
		material.emission = Color.WHITE
		material.emission_energy_multiplier = max_emission
		material.emission_texture = ImageTexture.create_from_image(emission)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.metallic_specular = appearance.default_surface.specular
	model.set_material_override(0, material)
	if appearance.foliage_layers:
		model.set_meta("astraeon_foliage_layers", true)
		model.culls_neighbors = false
		# Opposing faces at a shared boundary are each visible from their own front only.
		material.cull_mode = BaseMaterial3D.CULL_BACK
	model.set_mesh_collision_enabled(0, definition.collision_enabled)
	if not definition.collision_enabled:
		model.collision_aabbs = []
	return model

## Uniform-color water fallback. Waves, depth absorption and scene reflections remain shading work.
static func build_water(definition: AstraeonFluidDefinition) -> VoxelBlockyModelCube:
	if definition.appearance == null or not definition.appearance.validate().is_empty():
		push_error("Invalid water appearance")
		return null
	var appearance: AstraeonWaterAppearance = definition.appearance
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = appearance.shallow_color.lerp(appearance.deep_color, 1.0 - exp(-appearance.absorption * 3.0))
	material.albedo_color.a = appearance.uniform_opacity * appearance.opacity
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = appearance.roughness
	material.metallic_specular = appearance.specular
	var model: VoxelBlockyModelCube = VoxelBlockyModelCube.new()
	model.set_material_override(0, material)
	model.transparency_index = 1
	model.set_mesh_collision_enabled(0, definition.collision_enabled)
	if not definition.collision_enabled:
		model.collision_aabbs = []
	return model
