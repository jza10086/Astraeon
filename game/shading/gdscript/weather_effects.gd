extends Node3D
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
## Receives a local surface-height map from the world adapter; never queries voxels.
## Wetness is a derived shading cache, reset when an exposed surface changes height.
var rain: GPUParticles3D = GPUParticles3D.new()
var roof: Image
var wet: Image
var wet_texture: ImageTexture
var roof_texture: ImageTexture
var origin: Vector2
var extent: Vector2
var receivers: Array[ShaderMaterial] = []
var cloud_weight: float = 0.0
var rain_weight: float = 0.0
var _timer: float = 0.0
var _material: ShaderMaterial = ShaderMaterial.new()
var _process_material: ParticleProcessMaterial = ParticleProcessMaterial.new()
var _last_count: int = 0
var revision: int = -1
var _has_wet: bool = false
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
func set_surface_map(image: Image, map_origin: Vector2, map_extent: Vector2, new_revision: int) -> void:
	if new_revision == revision: return
	var previous: Image = wet
	wet = Image.create_empty(image.get_width(),image.get_height(),false,Image.FORMAT_RGF)
	for z: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var h: float = image.get_pixel(x,z).r
			var retained: float = 0.0
			if previous != null and previous.get_size() == image.get_size() and map_origin == origin and map_extent == extent:
				var old: Color = previous.get_pixel(x,z)
				if is_equal_approx(old.r,h): retained = old.g
			wet.set_pixel(x,z,Color(h,retained,0.0,1.0))
	roof = image
	origin = map_origin
	extent = map_extent
	revision = new_revision
	wet_texture = ImageTexture.create_from_image(wet)
	roof_texture = ImageTexture.create_from_image(roof)
	_material.set_shader_parameter("roof_map",roof_texture)
	_material.set_shader_parameter("roof_origin",origin)
	_material.set_shader_parameter("roof_size",extent)
	for material: ShaderMaterial in receivers:
		material.set_shader_parameter("wet_map",wet_texture)
		material.set_shader_parameter("wet_origin",origin)
		material.set_shader_parameter("wet_size",extent)
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
	rain.emitting = p.rain_enabled and rain_weight > 0.001 and roof != null
	rain.visible = rain.emitting
	if rain.emitting:
		rain.global_position = camera_position + Vector3.UP*24.0
		rain.amount_ratio = maxf(0.001,rain_weight)
	_timer += delta
	if _timer < 0.1: return false
	var elapsed: float = _timer
	_timer = 0.0
	if p.wet_enabled and wet != null and (rain_weight > 0.0 or _has_wet):
		_has_wet = false
		var changed: bool = false
		for z: int in range(wet.get_height()):
			for x: int in range(wet.get_width()):
				var value: Color = wet.get_pixel(x,z)
				var amount: float = clampf(value.g+elapsed*(rain_weight*p.wet_accumulation-(1.0-rain_weight)*p.wet_drying),0.0,1.0)
				_has_wet = _has_wet or amount > 0.0
				if not is_equal_approx(value.g,amount):
					value.g = amount
					wet.set_pixel(x,z,value)
					changed = true
		if changed: wet_texture.update(wet)
	var changed_weights: bool = _applied_weights != Vector2(cloud_weight,rain_weight)
	_applied_weights = Vector2(cloud_weight,rain_weight)
	return changed_weights
