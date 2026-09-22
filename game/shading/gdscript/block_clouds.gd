extends Node3D
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
## Finite repeating cloud layer: one merged mesh, nine instances, one matching mask.
const GRID: int = 32
const CELL: float = 24.0
const PERIOD: float = GRID * CELL
const HEIGHT: float = 90.0
const THICKNESS: float = 10.0
const CLOUD_SHADER: Shader = preload("res://game/shading/shaders/block_cloud.gdshader")
var mask: ImageTexture
var material: ShaderMaterial
var geometry: MultiMeshInstance3D
var cells: PackedByteArray = PackedByteArray()
var rebuilds: int = 0
var offset: Vector2 = Vector2.ZERO
var _coverage: float = -1.0
var _receivers: Array[ShaderMaterial] = []
var _vertices: PackedVector3Array = PackedVector3Array()
var _normals: PackedVector3Array = PackedVector3Array()

func configure(receivers: Array[ShaderMaterial]) -> void:
	_receivers = receivers
	material = ShaderMaterial.new()
	material.shader = CLOUD_SHADER
	geometry = MultiMeshInstance3D.new()
	geometry.layers = 1 << 16
	geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	geometry.material_override = material
	add_child(geometry)

func occupied(x: int, z: int) -> bool:
	return cells[posmod(x, GRID) + posmod(z, GRID) * GRID] != 0

func _quad(p: Vector3, u: Vector3, v: Vector3, normal: Vector3) -> void:
	for corner: Vector3 in [p, p + u, p + u + v, p, p + u + v, p + v]:
		_vertices.append(corner)
		_normals.append(normal)

func _build(coverage: float) -> void:
	_coverage = coverage
	rebuilds += 1
	cells.resize(GRID * GRID)
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = 72419
	noise.frequency = 0.16
	noise.fractal_octaves = 3
	var image: Image = Image.create_empty(GRID, GRID, false, Image.FORMAT_R8)
	for z: int in range(GRID):
		for x: int in range(GRID):
			var tx: float = float(x) / GRID
			var tz: float = float(z) / GRID
			# Blend opposite noise edges to make the coverage periodic.
			var first: float = lerpf(noise.get_noise_2d(x,z), noise.get_noise_2d(x-GRID,z),tx)
			var second: float = lerpf(noise.get_noise_2d(x,z-GRID), noise.get_noise_2d(x-GRID,z-GRID),tx)
			var value: float = lerpf(first,second,tz) * 0.5 + 0.5
			var filled: bool = coverage >= 1.0 or (coverage > 0.0 and value > 1.0 - coverage)
			cells[x + z * GRID] = 1 if filled else 0
			image.set_pixel(x,z,Color.WHITE if filled else Color.BLACK)
	if mask == null:
		mask = ImageTexture.create_from_image(image)
	else:
		mask.update(image)
	_vertices.clear()
	_normals.clear()
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(GRID * GRID)
	for z: int in range(GRID):
		for x: int in range(GRID):
			if not occupied(x,z) or visited[x + z * GRID] != 0:
				continue
			var width: int = 1
			while x + width < GRID and occupied(x+width,z) and visited[x+width+z*GRID] == 0:
				width += 1
			var depth: int = 1
			var grow: bool = true
			while z + depth < GRID and grow:
				for dx: int in range(width):
					if not occupied(x+dx,z+depth) or visited[x+dx+(z+depth)*GRID] != 0:
						grow = false
						break
				if grow:
					depth += 1
			for dz: int in range(depth):
				for dx: int in range(width):
					visited[x+dx+(z+dz)*GRID] = 1
			_quad(Vector3(x*CELL,HEIGHT+THICKNESS,z*CELL),Vector3.RIGHT*width*CELL,Vector3.BACK*depth*CELL,Vector3.UP)
			_quad(Vector3(x*CELL,HEIGHT,z*CELL),Vector3.BACK*depth*CELL,Vector3.RIGHT*width*CELL,Vector3.DOWN)
	# Only exposed perimeter faces, never internal cube faces.
	for z: int in range(GRID):
		for x: int in range(GRID):
			if not occupied(x,z):
				continue
			var p: Vector3 = Vector3(x*CELL,HEIGHT,z*CELL)
			if not occupied(x+1,z):
				_quad(p+Vector3.RIGHT*CELL,Vector3.BACK*CELL,Vector3.UP*THICKNESS,Vector3.RIGHT)
			if not occupied(x-1,z):
				_quad(p,Vector3.UP*THICKNESS,Vector3.BACK*CELL,Vector3.LEFT)
			if not occupied(x,z+1):
				_quad(p+Vector3.BACK*CELL,Vector3.UP*THICKNESS,Vector3.RIGHT*CELL,Vector3.BACK)
			if not occupied(x,z-1):
				_quad(p,Vector3.RIGHT*CELL,Vector3.UP*THICKNESS,Vector3.FORWARD)
	var mesh: ArrayMesh = ArrayMesh.new()
	if not _vertices.is_empty():
		var arrays: Array[Variant] = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vertices
		arrays[Mesh.ARRAY_NORMAL] = _normals
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var instances: MultiMesh = MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = mesh
	instances.instance_count = 9
	for z: int in range(3):
		for x: int in range(3):
			instances.set_instance_transform(x+z*3,Transform3D(Basis.IDENTITY,Vector3((x-1)*PERIOD,0,(z-1)*PERIOD)))
	geometry.multimesh = instances
	for receiver: ShaderMaterial in _receivers:
		receiver.set_shader_parameter("block_cloud_mask",mask)

func apply(settings: Profile, horizon: Color, toward_light: Vector3) -> void:
	visible = settings.clouds_enabled
	if visible and not is_equal_approx(_coverage,settings.cloud_coverage):
		_build(settings.cloud_coverage)
	material.set_shader_parameter("cloud_horizon",horizon)
	material.set_shader_parameter("cloud_lit",horizon.lerp(Color.WHITE,0.5) * clampf(horizon.get_luminance()*2.0,0.015,1.0))
	material.set_shader_parameter("light_direction",toward_light)
	for receiver: ShaderMaterial in _receivers:
		receiver.set_shader_parameter("cloud_shadow_enabled",visible and settings.block_cloud_shadows)
		receiver.set_shader_parameter("cloud_light_direction",toward_light)
		receiver.set_shader_parameter("cloud_shadow_strength",settings.cloud_shadow_strength)
		receiver.set_shader_parameter("cloud_shadow_softness",settings.cloud_shadow_softness)

func tick(clock: float, camera_position: Vector3) -> void:
	if not visible:
		return
	var next_offset: Vector2 = Vector2(clock * 22.0, clock * 7.0)
	if next_offset != offset:
		offset = next_offset
		for receiver: ShaderMaterial in _receivers:
			receiver.set_shader_parameter("block_cloud_offset",offset)
	position = Vector3(floorf((camera_position.x-offset.x)/PERIOD)*PERIOD+offset.x,0.0,floorf((camera_position.z-offset.y)/PERIOD)*PERIOD+offset.y)
