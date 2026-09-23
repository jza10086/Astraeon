extends RefCounted
const LightPages: Script = preload("res://test/shading/gdscript/light_page_fixture.gd")
## One native block mesh per 16^3 section. Light-only changes never rebuild geometry.
const Volume: Script = preload("res://test/shading/gdscript/light_volume.gd")
const LIGHT_SHADER: Shader = preload("res://game/shading/shaders/voxel_light.gdshader")
const PLANT_SHADER: Shader = preload("res://game/shading/shaders/plant.gdshader")
var materials: Array[ShaderMaterial] = []
var rebuilt_sections: int = 0
var last_build_usec: int = 0
var _volume: Volume
var _parent: Node3D
var _mesher: VoxelMesherBlocky
var _nodes: Dictionary[Vector3i, MeshInstance3D] = {}
var _dirty: Dictionary[Vector3i, bool] = {}

func configure(volume: Volume, parent: Node3D, texture: ImageTexture3D) -> void:
	_volume = volume
	_parent = parent
	var models: Array[VoxelBlockyModel] = [VoxelBlockyModelEmpty.new()]
	var catalog: AstraeonBlockCatalog = preload("res://test/shading/resources/blocks/catalog.tres")
	var keys: Array[StringName] = [&"shading_test_stone", &"shading_test_lamp", &"shading_test_wood", &"shading_test_leaves"]
	for i: int in range(keys.size()):
		var definition: AstraeonBlockDefinition
		for candidate: AstraeonBlockDefinition in catalog.definitions:
			if candidate.key == keys[i]:
				definition = candidate
		assert(definition != null, "Missing shading fixture definition")
		var model: VoxelBlockyModelCube = AstraeonBlockLibraryBuilder.build_block(definition, Basis.IDENTITY)
		assert(model != null, "Invalid shading fixture appearance")
		var compiled: ORMMaterial3D = model.get_material_override(0)
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = PLANT_SHADER if i == 3 else LIGHT_SHADER
		LightPages.bind_fixture(material,texture,volume.origin,volume.size)
		material.set_shader_parameter("base_color", Color.WHITE)
		material.set_shader_parameter("use_block_atlas", true)
		material.set_shader_parameter("block_atlas", compiled.albedo_texture)
		material.set_shader_parameter("block_cutout", definition.appearance.default_surface.alpha_mode == AstraeonBlockSurface.AlphaMode.CUTOUT)
		material.set_shader_parameter("block_alpha_cutoff", definition.appearance.default_surface.alpha_cutoff)
		material.set_shader_parameter("self_emission", definition.appearance.default_surface.emission_energy)
		material.set_shader_parameter("material_roughness", definition.appearance.default_surface.roughness)
		material.set_shader_parameter("material_specular", definition.appearance.default_surface.specular)
		materials.append(material)
		model.set_material_override(0, material)
		# Lamp surfaces are drawn by the local-light fixture to avoid self-shadowing.
		models.append(VoxelBlockyModelEmpty.new() if i == 1 else model)
	var library: VoxelBlockyLibrary = VoxelBlockyLibrary.new()
	library.models = models
	library.bake()
	_mesher = VoxelMesherBlocky.new()
	_mesher.library = library
	var start: Vector3i = section_of(volume.origin)
	var end: Vector3i = section_of(volume.origin + volume.size - Vector3i.ONE)
	for z: int in range(start.z, end.z + 1):
		for y: int in range(start.y, end.y + 1):
			for x: int in range(start.x, end.x + 1):
				_dirty[Vector3i(x, y, z)] = true

static func section_of(p: Vector3i) -> Vector3i:
	return Vector3i(floori(float(p.x) / 16.0), floori(float(p.y) / 16.0), floori(float(p.z) / 16.0))

func invalidate(changed: Array[Vector3i]) -> void:
	# Full one-voxel halo is needed for both face culling and corner AO.
	for p: Vector3i in changed:
		for z: int in range(-1, 2):
			for y: int in range(-1, 2):
				for x: int in range(-1, 2):
					var neighbor: Vector3i = p + Vector3i(x, y, z)
					if _volume.contains(neighbor):
						_dirty[section_of(neighbor)] = true

func pending_count() -> int:
	return _dirty.size()

## One section per call; native meshing is atomic and is not a hard time budget.
func step() -> void:
	if _dirty.is_empty():
		return
	var begin: int = Time.get_ticks_usec()
	var section: Vector3i = _dirty.keys()[0]
	_dirty.erase(section)
	var minimum: int = _mesher.get_minimum_padding()
	var extent: int = 16 + minimum + _mesher.get_maximum_padding()
	var buffer: VoxelBuffer = VoxelBuffer.new()
	buffer.create(extent, extent, extent)
	var section_origin: Vector3i = section * 16
	buffer.set_channel_depth(VoxelBuffer.CHANNEL_TYPE, VoxelBuffer.DEPTH_16_BIT)
	var source_min: Vector3i = section_origin - Vector3i.ONE * minimum - _volume.origin
	var clipped_min: Vector3i = source_min.max(Vector3i.ZERO)
	var clipped_max: Vector3i = (source_min + Vector3i.ONE * extent).min(_volume.size)
	buffer.copy_channel_from_area(_volume.voxels, clipped_min, clipped_max, clipped_min - source_min, VoxelBuffer.CHANNEL_TYPE)
	var mesh: Mesh = _mesher.build_mesh(buffer, [])
	if not _nodes.has(section):
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.position = Vector3(section_origin)
		instance.extra_cull_margin = 0.5
		_parent.add_child(instance)
		_nodes[section] = instance
	_nodes[section].mesh = mesh
	rebuilt_sections += 1
	last_build_usec = Time.get_ticks_usec() - begin
