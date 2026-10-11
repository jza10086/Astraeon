extends RefCounted
const LightPages: Script = preload("res://test/shading/gdscript/light_page_fixture.gd")
## One native block mesh per 16^3 section. Light-only changes never rebuild geometry.
const Volume: Script = preload("res://test/shading/gdscript/light_volume.gd")
const LIGHT_SHADER: Shader = preload("res://game/shading/shaders/voxel_light.gdshader")
const PLANT_SHADER: Shader = preload("res://game/shading/shaders/plant.gdshader")
var materials: Array[ShaderMaterial] = []
var rebuilt_sections: int = 0
var last_build_usec: int = 0
var _content: AstraeonWorldContent
var _visual_hashes: PackedStringArray = []
var _volume: Volume
var _parent: Node3D
var _mesher: VoxelMesherBlocky
var _nodes: Dictionary[Vector3i, MeshInstance3D] = {}
var _dirty: Dictionary[Vector3i, bool] = {}
const Foliage: Script = preload("res://game/shading/blocks/gdscript/foliage_rendering.gd")
var _foliage_mode: int = -1

func configure(volume: Volume, parent: Node3D, texture: ImageTexture3D) -> void:
	_volume = volume
	_parent = parent
	var models: Array[VoxelBlockyModel] = [VoxelBlockyModelEmpty.new()]
	_content = AstraeonWorldContent.new()
	assert(_content.build(PackedStringArray(["res://tmp/content/shading_test.aebpack"])), _content.error)
	var keys: Array[String] = ["shading_test:stone/default", "shading_test:lamp/default", "shading_test:wood/default", "shading_test:leaves/default"]
	for i: int in range(keys.size()):
		var id: int = _content.state_keys.find(keys[i])
		var model: VoxelBlockyModelCube = _content.library.models[id] as VoxelBlockyModelCube
		var material: ShaderMaterial = model.get_material_override(0)
		LightPages.bind_fixture(material, texture, volume.origin, volume.size)
		materials.append(material)
		models.append(VoxelBlockyModelEmpty.new() if i == 1 else model)
		_visual_hashes.append_array(_content.bundle.state_visuals(PackedInt32Array([id])))
	_content.bundle.visuals.call("request", "shading_fixture", _visual_hashes)
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

## Policy changes only rebuild native section meshes; never restart light propagation.
func apply_foliage(mode: int) -> void:
	if mode == _foliage_mode:
		return
	if mode > 0 and _foliage_mode > 0:
		for model: VoxelBlockyModel in _mesher.library.models:
			if Foliage.is_foliage(model):
				Foliage.apply_material(model.get_material_override(0), mode)
	else:
		var replacement: VoxelMesherBlocky = _mesher.duplicate() as VoxelMesherBlocky
		replacement.library = Foliage.with_mode(_mesher.library, mode)
		_mesher = replacement
		var start: Vector3i = section_of(_volume.origin)
		var end: Vector3i = section_of(_volume.origin + _volume.size - Vector3i.ONE)
		for z: int in range(start.z, end.z + 1):
			for y: int in range(start.y, end.y + 1):
				for x: int in range(start.x, end.x + 1):
					_dirty[Vector3i(x, y, z)] = true
	_foliage_mode = mode

func pending_count() -> int:
	return _dirty.size()

## One section per call; native meshing is atomic and is not a hard time budget.
func step() -> void:
	_content.bundle.visuals.call("commit")
	if not _content.bundle.visuals.call("is_ready", _visual_hashes):
		return
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

func shutdown() -> void:
	if _content != null:
		_content.bundle.shutdown()
