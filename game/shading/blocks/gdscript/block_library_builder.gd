class_name AstraeonBlockLibraryBuilder
extends RefCounted
## Startup-only compiler for the current solid-color block definitions.
## Resources/materials are per shared state, never per voxel. Unsupported surfaces fail explicitly.
static func build_block(definition: AstraeonBlockDefinition, orientation: Basis) -> VoxelBlockyModelCube:
	var appearance: AstraeonBlockAppearance = definition.appearance
	if appearance == null or not appearance.validate().is_empty() or not AstraeonBlockAppearance.is_cube_rotation(orientation):
		push_error("Invalid appearance/orientation: " + String(definition.key))
		return null
	var image: Image = Image.create(96, 16, false, Image.FORMAT_RGBA8)
	var orm: Image = Image.create(96, 16, false, Image.FORMAT_RGB8)
	var model: VoxelBlockyModelCube = VoxelBlockyModelCube.new()
	model.atlas_size_in_tiles = Vector2i(6, 1)
	var sides: Array[int] = [VoxelBlockyModel.SIDE_POSITIVE_Y, VoxelBlockyModel.SIDE_NEGATIVE_Y, VoxelBlockyModel.SIDE_NEGATIVE_Z, VoxelBlockyModel.SIDE_POSITIVE_Z, VoxelBlockyModel.SIDE_NEGATIVE_X, VoxelBlockyModel.SIDE_POSITIVE_X]
	for face: int in range(6):
		var authored: int = appearance.authored_face_for_world(face, orientation)
		var surface: AstraeonBlockSurface = appearance.surface_for_face(authored)
		if surface.albedo_texture != null or surface.normal_texture != null or surface.orm_texture != null or surface.emission_texture != null or surface.emission_energy != 0.0 or surface.alpha_mode != AstraeonBlockSurface.AlphaMode.OPAQUE:
			push_error("Current native block compiler requires opaque solid-color surfaces")
			return null
		image.fill_rect(Rect2i(face * 16, 0, 16, 16), surface.base_color)
		orm.fill_rect(Rect2i(face * 16, 0, 16, 16), Color(1.0, surface.roughness, surface.metallic))
		model.set_tile(sides[face], Vector2i(face, 0))
	var material: ORMMaterial3D = ORMMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.orm_texture = ImageTexture.create_from_image(orm)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.metallic_specular = appearance.default_surface.specular
	model.set_material_override(0, material)
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
