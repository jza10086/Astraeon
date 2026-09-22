extends RefCounted
## One native block mesh per 16^3 section. Light-only changes never rebuild geometry.
const Volume: Script = preload("res://test/shader/gdscript/light_volume.gd")
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
	var colors: Array[Color] = [Color(0.58, 0.62, 0.65), Color(1.0, 0.72, 0.32), Color(0.55, 0.33, 0.15), Color(0.25, 0.48, 0.2)]
	for i: int in range(colors.size()):
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = PLANT_SHADER if i == 3 else LIGHT_SHADER
		material.set_shader_parameter("base_color", colors[i])
		material.set_shader_parameter("volume_origin", Vector3(volume.origin))
		material.set_shader_parameter("volume_size", Vector3(volume.size))
		material.set_shader_parameter("light_volume", texture)
		material.set_shader_parameter("self_emission", 1.5 if i == 1 else 0.0)
		materials.append(material)
		var model: VoxelBlockyModelCube = VoxelBlockyModelCube.new()
		model.atlas_size_in_tiles = Vector2i.ONE
		model.set_material_override(0, material)
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
	for z: int in range(extent):
		for y: int in range(extent):
			for x: int in range(extent):
				var p: Vector3i = section_origin + Vector3i(x, y, z) - Vector3i.ONE * minimum
				# Exterior faces remain visible; illumination still treats outside as unknown.
				var value: int = _volume.voxel_at(p) if _volume.contains(p) else Volume.AIR
				buffer.set_voxel(value, x, y, z, VoxelBuffer.CHANNEL_TYPE)
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
