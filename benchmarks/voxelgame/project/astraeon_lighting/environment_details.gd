extends Node3D
## Local finite water and grass fixtures. No world streaming or liquid simulation.
const WATER_SHADER: Shader = preload("res://astraeon_lighting/water.gdshader")
const PLANT_SHADER: Shader = preload("res://astraeon_lighting/plant.gdshader")
const POOL: AABB = AABB(Vector3(12, -5, -25), Vector3(16, 5.75, 16))
var water_materials: Array[ShaderMaterial] = []
var grass_material: ShaderMaterial
var water_nodes: Array[MeshInstance3D] = []
var water_clock: float = 0.0
var wind_clock: float = 0.0

func configure(texture: ImageTexture3D, origin: Vector3i, size: Vector3i) -> void:
	for side: int in range(2):
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = WATER_SHADER
		water_materials.append(material)
		var plane: PlaneMesh = PlaneMesh.new()
		plane.size = Vector2(8, 16)
		plane.subdivide_width = 16
		plane.subdivide_depth = 32
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.mesh = plane
		instance.material_override = material
		instance.position = Vector3(16 + side * 8, 0.75, -17)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		water_nodes.append(instance)
	grass_material = ShaderMaterial.new()
	grass_material.shader = PLANT_SHADER
	grass_material.set_shader_parameter("base_color", Color(0.25, 0.5, 0.14))
	grass_material.set_shader_parameter("light_volume", texture)
	grass_material.set_shader_parameter("volume_origin", Vector3(origin))
	grass_material.set_shader_parameter("volume_size", Vector3(size))
	grass_material.set_shader_parameter("grass", true)
	# Two crossed cutout quads per clump; no per-voxel nodes in production terrain.
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.8, 1.3)
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = 128
	for i: int in range(64):
		@warning_ignore("integer_division")
		var p: Vector3 = Vector3(-26 + (i % 8) * 1.2, 1.65, -21 + (i / 8) * 1.2)
		for side: int in range(2):
			multimesh.set_instance_transform(i * 2 + side, Transform3D(Basis(Vector3.UP, side * PI / 2.0 + i * 0.37), p))
	var plants: MultiMeshInstance3D = MultiMeshInstance3D.new()
	plants.multimesh = multimesh
	plants.material_override = grass_material
	plants.custom_aabb = AABB(Vector3(-28, 0, -23), Vector3(14, 5, 14))
	add_child(plants)

func is_underwater(p: Vector3) -> bool:
	var bottom: float = -2.0 if p.x < 20.0 else -5.0
	return POOL.has_point(p) and p.y >= bottom

func apply(settings: AstraeonLightingProfile, sky_color: Color, horizon: Color) -> void:
	for node: MeshInstance3D in water_nodes:
		node.visible = settings.water_enabled
	for material: ShaderMaterial in water_materials:
		material.set_shader_parameter("depth_absorption", settings.water_quality == 1)
		material.set_shader_parameter("waves_enabled", settings.waves_enabled)
		material.set_shader_parameter("reflection_enabled", settings.water_reflection)
		material.set_shader_parameter("wave_strength", settings.wave_strength)
		material.set_shader_parameter("sky_color", sky_color)
		material.set_shader_parameter("horizon", horizon)

func tick(delta: float, settings: AstraeonLightingProfile, leaf_material: ShaderMaterial) -> void:
	if settings.water_enabled and settings.waves_enabled:
		water_clock += delta
		for material: ShaderMaterial in water_materials:
			material.set_shader_parameter("clock", water_clock)
	if settings.wind_enabled:
		wind_clock += delta
		leaf_material.set_shader_parameter("wind_clock", wind_clock)
		grass_material.set_shader_parameter("wind_clock", wind_clock)
