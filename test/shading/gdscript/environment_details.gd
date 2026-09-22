extends Node3D
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
## Local finite water and grass fixtures. No world streaming or liquid simulation.
const WATER_SHADER: Shader = preload("res://game/shading/shaders/water.gdshader")
const SSR_SHADER: Shader = preload("res://game/shading/shaders/water_reflective.gdshader")
const PLANAR_SHADER: Shader = preload("res://game/shading/shaders/water_planar.gdshader")
const PLANT_SHADER: Shader = preload("res://game/shading/shaders/plant.gdshader")
const POOL: AABB = AABB(Vector3(12, -5, -25), Vector3(16, 5.75, 16))
var water_materials: Array[ShaderMaterial] = []
var marker_materials: Array[ShaderMaterial] = []
var grass_material: ShaderMaterial
var water_nodes: Array[MeshInstance3D] = []
var water_clock: float = 0.0
var wind_clock: float = 0.0

func configure(texture: ImageTexture3D, origin: Vector3i, size: Vector3i) -> void:
	for side: int in range(2):
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = WATER_SHADER
		var definition: AstraeonFluidDefinition = preload("res://test/shading/resources/blocks/shading_test_water.tres")
		for parameter: StringName in definition.appearance.surface_parameters():
			material.set_shader_parameter(parameter, definition.appearance.surface_parameters()[parameter])
		water_materials.append(material)
		var plane: PlaneMesh = PlaneMesh.new()
		plane.size = Vector2(8, 16)
		plane.subdivide_width = 16
		plane.subdivide_depth = 32
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.mesh = plane
		instance.layers = 1 << 18
		instance.material_override = material
		instance.position = Vector3(16 + side * 8, 0.75, -17)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		water_nodes.append(instance)
	# Opaque colored markers make screen-space reflection alignment easy to inspect.
	for i: int in range(3):
		var marker: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(1.6, 5.0 + i, 1.6)
		var marker_material: ShaderMaterial = ShaderMaterial.new()
		marker_material.shader = preload("res://game/shading/shaders/voxel_light.gdshader")
		var colors: Array[Color] = [Color(0.85, 0.12, 0.06), Color(0.08, 0.25, 0.9), Color(0.9, 0.65, 0.08)]
		marker_material.set_shader_parameter("base_color", colors[i])
		marker_material.set_shader_parameter("light_volume", texture)
		marker_material.set_shader_parameter("volume_origin", Vector3(origin))
		marker_material.set_shader_parameter("volume_size", Vector3(size))
		marker_materials.append(marker_material)
		marker.mesh = box
		marker.material_override = marker_material
		marker.position = Vector3(14 + i * 6, 1.0 + box.size.y * 0.5, -27)
		add_child(marker)
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
	plants.layers = 1 << 17
	plants.material_override = grass_material
	plants.custom_aabb = AABB(Vector3(-28, 0, -23), Vector3(14, 5, 14))
	add_child(plants)

func is_underwater(p: Vector3) -> bool:
	var bottom: float = -2.0 if p.x < 20.0 else -5.0
	return POOL.has_point(p) and p.y >= bottom

func apply(settings: Profile, sky_color: Color, horizon: Color) -> void:
	for node: MeshInstance3D in water_nodes:
		node.visible = settings.water_enabled
		node.extra_cull_margin = settings.wave_strength
	for material: ShaderMaterial in water_materials:
		var desired_shader: Shader = SSR_SHADER if settings.water_enabled and settings.water_reflection_mode == 1 and settings.water_ssr_strength > 0.0 else WATER_SHADER
		if settings.water_enabled and settings.water_reflection_mode == 2 and settings.planar_strength > 0.0:
			desired_shader = PLANAR_SHADER
		if material.shader != desired_shader:
			material.shader = desired_shader
		for key: StringName in [&"water_shallow_color", &"water_deep_color", &"water_absorption", &"water_opacity", &"water_low_opacity", &"water_roughness", &"water_specular", &"wave_scale", &"water_sky_strength", &"water_ssr_strength", &"water_ssr_distance", &"water_ssr_tolerance", &"water_ssr_edge_fade", &"water_ssr_refinements", &"water_ssr_normal_offset", &"planar_strength", &"planar_distortion", &"planar_blur_pixels", &"planar_edge_fade"]:
			material.set_shader_parameter(key, settings.get(key))
		material.set_shader_parameter("water_ssr_steps", settings.water_ssr_steps)
		material.set_shader_parameter("depth_absorption", settings.water_quality == 1)
		material.set_shader_parameter("waves_enabled", settings.waves_enabled)
		material.set_shader_parameter("reflection_enabled", settings.water_reflection)
		material.set_shader_parameter("wave_strength", settings.wave_strength)
		material.set_shader_parameter("sky_color", sky_color)
		material.set_shader_parameter("horizon", horizon)

func tick(delta: float, settings: Profile, leaf_material: ShaderMaterial) -> void:
	if settings.water_enabled and settings.waves_enabled and settings.wave_speed > 0.0:
		water_clock += delta * settings.wave_speed
		for material: ShaderMaterial in water_materials:
			material.set_shader_parameter("clock", water_clock)
	if settings.wind_enabled:
		wind_clock += delta
		leaf_material.set_shader_parameter("wind_clock", wind_clock)
		grass_material.set_shader_parameter("wind_clock", wind_clock)
