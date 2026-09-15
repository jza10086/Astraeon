extends Node3D
## Finite lab emitters, indexed only on edits. Not a production light allocator.
const Volume: Script = preload("res://astraeon_lighting/light_volume.gd")
var emitters: Dictionary[Vector3i, OmniLight3D] = {}
var active_points: int = 0
var active_shadows: int = 0
var _observer: Vector3 = Vector3.ZERO
var _elapsed: float = 0.0
var _volume: Volume
var _material: ShaderMaterial

func configure(volume: Volume) -> void:
	_volume = volume
	_material = ShaderMaterial.new()
	_material.shader = preload("res://astraeon_lighting/lamp_surface.gdshader")
	_material.set_shader_parameter("lamp_color", Color(1.0,0.72,0.32))
	var lamps: Array[Vector3i] = []
	for index: int in range(volume.voxels.size()):
		if volume.voxels[index] == Volume.LAMP:
			lamps.append(volume.position_of(index))
	sync_edits(lamps)

func sync_edits(changed: Array[Vector3i]) -> void:
	for p: Vector3i in changed:
		if _volume.voxel_at(p) == Volume.LAMP:
			if emitters.has(p):
				continue
			var light: OmniLight3D = OmniLight3D.new()
			light.position = Vector3(p) + Vector3.ONE * 0.5
			light.shadow_enabled = true
			light.shadow_bias = 0.05
			light.shadow_normal_bias = 1.0
			add_child(light)
			var surface: MeshInstance3D = MeshInstance3D.new()
			surface.mesh = BoxMesh.new()
			surface.material_override = _material
			surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			light.add_child(surface)
			emitters[p] = light
		elif emitters.has(p):
			emitters[p].queue_free()
			emitters.erase(p)

func apply(settings: AstraeonLightingProfile) -> void:
	_material.set_shader_parameter("lamp_color", settings.lamp_emission_color)
	_material.set_shader_parameter("lamp_emission_strength", settings.lamp_emission_strength)
	var ordered: Array[Vector3i] = []
	ordered.assign(emitters.keys())
	if settings.local_lighting_mode == 4:
		ordered.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
			var da: float = (Vector3(a)+Vector3.ONE*0.5).distance_squared_to(_observer)
			var db: float = (Vector3(b)+Vector3.ONE*0.5).distance_squared_to(_observer)
			return a < b if da == db else da < db)
	active_points = 0
	active_shadows = 0
	for i: int in range(ordered.size()):
		var light: OmniLight3D = emitters[ordered[i]]
		var enabled: bool = settings.local_lights_enabled and settings.local_lighting_mode >= 2
		if settings.local_lighting_mode == 4:
			enabled = enabled and i < settings.local_point_budget
		var shadows: bool = enabled and (settings.local_lighting_mode == 2 or (settings.local_lighting_mode == 4 and i < settings.local_shadow_budget))
		light.light_energy = settings.local_light_energy if enabled else 0.0
		light.shadow_enabled = shadows and settings.local_light_energy > 0.0
		light.light_color = settings.block_color
		light.omni_range = settings.local_light_range
		light.omni_attenuation = 2.0
		light.shadow_blur = 0.0 if settings.hard_shadows else settings.shadow_blur
		if enabled and light.light_energy > 0.0:
			active_points += 1
		if light.shadow_enabled:
			active_shadows += 1

func tick(delta: float, settings: AstraeonLightingProfile, observer: Vector3) -> void:
	_observer = observer
	_elapsed += delta
	if settings.local_lighting_mode == 4 and _elapsed >= 0.2:
		_elapsed = 0.0
		apply(settings)
