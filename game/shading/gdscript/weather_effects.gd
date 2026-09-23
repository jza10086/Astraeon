extends Node3D
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
## Receives a local surface-height map from the world adapter; never queries voxels.
## Wetness is a derived shading cache, reset when an exposed surface changes height.
var section_cache: RefCounted
var rain: GPUParticles3D = GPUParticles3D.new()
var receivers: Array[ShaderMaterial] = []
var cloud_weight: float = 0.0
var rain_weight: float = 0.0
var _timer: float = 0.0
var _material: ShaderMaterial = ShaderMaterial.new()
var _process_material: ParticleProcessMaterial = ParticleProcessMaterial.new()
var _last_count: int = 0
var _applied_weights: Vector2 = Vector2.ZERO
func configure(materials: Array[ShaderMaterial]) -> void:
	receivers = materials
	add_child(rain)
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain.local_coords = false
	rain.emitting = false
	_material.shader = preload("res://game/shading/shaders/rain.gdshader")
	var quad: QuadMesh = QuadMesh.new()
	quad.material = _material
	rain.draw_pass_1 = quad
	_process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_process_material.direction = Vector3.DOWN
	_process_material.spread = 0.0
	_process_material.gravity = Vector3.ZERO
	rain.process_material = _process_material
func configure_cache(cache: RefCounted) -> void:
	section_cache = cache
	section_cache.call("bind_weather_material",_material)
func apply(p: Profile) -> void:
	if _last_count != p.rain_count:
		rain.amount = p.rain_count
		_last_count = p.rain_count
	(rain.draw_pass_1 as QuadMesh).size = Vector2(p.rain_width,p.rain_length)
	_material.set_shader_parameter("opacity",p.rain_alpha)
	_process_material.emission_box_extents = Vector3(p.rain_area,0.1,p.rain_area)
	_process_material.initial_velocity_min = p.rain_speed
	_process_material.initial_velocity_max = p.rain_speed
	rain.lifetime = 64.0 / p.rain_speed
	rain.visibility_aabb = AABB(Vector3(-p.rain_area,-64,-p.rain_area),Vector3(p.rain_area*2,65,p.rain_area*2))
	for material: ShaderMaterial in receivers:
		material.set_shader_parameter("wet_active",p.wet_enabled)
		material.set_shader_parameter("wet_darken",p.wet_darken)
		material.set_shader_parameter("wet_roughness",p.wet_roughness)
		material.set_shader_parameter("wet_specular",p.wet_specular)
func tick(delta: float, p: Profile, camera_position: Vector3) -> bool:
	var cloud_target: float = p.weather_weight if p.weather_mode > 0 else 0.0
	var rain_target: float = p.weather_weight if p.weather_mode == 2 else 0.0
	cloud_weight = move_toward(cloud_weight,cloud_target,delta/p.weather_transition)
	rain_weight = move_toward(rain_weight,rain_target,delta/p.weather_transition)
	rain.emitting = p.rain_enabled and rain_weight > 0.001 and has_surface_data()
	rain.visible = rain.emitting
	if rain.emitting:
		rain.global_position = camera_position + Vector3.UP*24.0
		rain.amount_ratio = maxf(0.001,rain_weight)
	_timer += delta
	if _timer < 0.1: return false
	var elapsed: float = _timer
	_timer = 0.0
	_tick_surface(elapsed,p)
	var changed_weights: bool = _applied_weights != Vector2(cloud_weight,rain_weight)
	_applied_weights = Vector2(cloud_weight,rain_weight)
	return changed_weights

func has_surface_data() -> bool:
	return section_cache != null
func _tick_surface(_elapsed: float, p: Profile) -> void:
	if section_cache != null:
		section_cache.call("set_weather",rain_weight,p.wet_accumulation,p.wet_drying,p.wet_enabled)
