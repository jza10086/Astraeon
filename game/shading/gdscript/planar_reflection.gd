extends Node
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
## One mirrored camera for a world-supplied horizontal water plane. Shares geometry, never the main camera.
@export var water_height: float = 0.75
@export var water_bounds: AABB = AABB(Vector3(12,0.4,-25),Vector3(16,0.7,16))
const CAPTURE_MARKER: int = 1 << 19
const WATER_LAYER: int = 1 << 18
const PLANT_LAYER: int = 1 << 17
const CLOUD_LAYER: int = 1 << 16
var viewport: SubViewport
var camera: Camera3D
var captures: int = 0
var active: bool = false
var _source: Camera3D
var _materials: Array[ShaderMaterial] = []
var _clip_materials: Array[ShaderMaterial] = []
var _elapsed: float = 0.0
var _force: bool = true
var _valid: bool = false

func configure(source: Camera3D, materials: Array[ShaderMaterial], clips: Array[ShaderMaterial]) -> void:
	_source = source
	_materials = materials
	_clip_materials = clips
	_source.cull_mask &= ~CAPTURE_MARKER
	viewport = SubViewport.new()
	viewport.name = "PlanarCapture"
	viewport.world_3d = source.get_world_3d()
	viewport.size = Vector2i(960,540)
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.disable_3d = false
	add_child(viewport)
	camera = Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	camera.attributes = CameraAttributesPractical.new()
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("planar_texture", viewport.get_texture())

func apply(settings: Profile, environment: Environment) -> void:
	var was_active: bool = active
	active = settings.water_enabled and settings.water_reflection_mode == 2 and settings.planar_strength > 0.0
	_force = _force or not was_active
	if not active:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_valid = false
		_set_valid(false)
		return
	var capture_environment: Environment = environment.duplicate() as Environment
	# Capture scene-linear HDR; the main viewport performs the only tone mapping.
	capture_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	capture_environment.tonemap_exposure = 1.0
	capture_environment.glow_enabled = false
	capture_environment.adjustment_enabled = false
	capture_environment.ssao_enabled = settings.planar_ssao and settings.ssao_enabled
	capture_environment.volumetric_fog_enabled = settings.planar_volumetric and settings.rays_mode == 2
	capture_environment.fog_enabled = settings.planar_fog and settings.fog_enabled
	camera.environment = capture_environment
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if settings.planar_aa == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	camera.cull_mask = (_source.cull_mask & ~WATER_LAYER) | CAPTURE_MARKER
	if not settings.planar_reflect_plants:
		camera.cull_mask &= ~PLANT_LAYER
	if not settings.planar_reflect_clouds:
		camera.cull_mask &= ~CLOUD_LAYER
	for material: ShaderMaterial in _clip_materials:
		material.set_shader_parameter("reflection_clip_height", water_height + settings.planar_clip_offset)
		material.set_shader_parameter("reflection_plants", settings.planar_reflect_plants)

func _set_valid(value: bool) -> void:
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("planar_valid", value)

func _pool_in_view() -> bool:
	# Conservative AABB/frustum overlap; unlike checking only the center, works above the pool.
	var bounds: AABB = water_bounds
	for plane: Plane in _source.get_frustum():
		var outside: bool = true
		for index: int in range(8):
			if not plane.is_point_over(bounds.get_endpoint(index)):
				outside = false
				break
		if outside:
			return false
	return true

func tick(delta: float, settings: Profile) -> void:
	if not active:
		return
	if _source.global_position.y <= water_height + 0.02 or (settings.planar_visible_only and not _pool_in_view()):
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_valid = false
		_set_valid(false)
		_force = true
		return
	_elapsed += delta
	var source_size: Vector2 = _source.get_viewport().get_visible_rect().size
	var size: Vector2i = Vector2i(maxi(16,roundi(source_size.x*settings.planar_resolution_scale)),maxi(16,roundi(source_size.y*settings.planar_resolution_scale)))
	if viewport.size != size:
		viewport.size = size
		_force = true
	if not _force and settings.planar_update_fps > 0 and _elapsed < 1.0 / settings.planar_update_fps:
		return
	_elapsed = 0.0
	_force = false
	camera.keep_aspect = _source.keep_aspect
	camera.fov = _source.fov
	camera.near = _source.near
	camera.far = settings.planar_distance
	var transform: Transform3D = _source.global_transform
	var origin: Vector3 = transform.origin
	origin.y = 2.0 * water_height - origin.y
	var forward: Vector3 = -transform.basis.z
	var up: Vector3 = transform.basis.y
	forward.y = -forward.y
	up.y = -up.y
	camera.global_transform = Transform3D(Basis.looking_at(forward,up),origin)
	var view_projection: Projection = camera.get_camera_projection() * Projection(camera.global_transform.affine_inverse())
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("planar_view_projection", view_projection)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_valid = true
	_set_valid(true)
	captures += 1
