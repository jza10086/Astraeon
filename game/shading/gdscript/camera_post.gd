@tool
extends CompositorEffect
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
## Main-camera HDR post passes. Scratch copy prevents in-place read/write races.
## One instance per stage/camera; no UI or reflection-camera compositor.
const COMPUTE: RDShaderFile = preload("res://game/shading/shaders/camera_post.glsl")
var motion_stage: bool = false
var _mutex: Mutex = Mutex.new()
var _parameters: PackedFloat32Array = PackedFloat32Array()
var _scale: float = 0.5
var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _sampler: RID
var _point_sampler: RID
var _scratch: RID
var _rays: RID
var _size: Vector2i
var _ray_size: Vector2i
var _reset: int = 2
func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	access_resolved_depth = true
	enabled = false
func configure_stage(motion: bool) -> void:
	motion_stage = motion
	needs_motion_vectors = motion
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_OPAQUE if motion else EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
func reset_history() -> void:
	_mutex.lock()
	_reset = 2
	_mutex.unlock()
func update(p: Profile, camera: Camera3D, sun: DirectionalLight3D) -> void:
	var was_enabled: bool = enabled
	enabled = p.motion_enabled if motion_stage else p.rays_mode == 1 or p.chroma_enabled
	if enabled and not was_enabled: reset_history()
	if not enabled: return
	var target: Vector3 = camera.global_position + sun.global_basis.z * 1000.0
	var uv: Vector2 = camera.unproject_position(target) / camera.get_viewport().get_visible_rect().size
	var valid: float = 0.0 if camera.is_position_behind(target) or not sun.visible else 1.0
	valid *= clampf((1.3-absf(uv.x-0.5)*2.0)*4.0,0,1)*clampf((1.3-absf(uv.y-0.5)*2.0)*4.0,0,1)
	var sun_color: Color = sun.light_color
	var packed_color: int = (sun_color.r8 << 16) | (sun_color.g8 << 8) | sun_color.b8
	var values: PackedFloat32Array = PackedFloat32Array([
		0,0,0,p.motion_shutter/360.0 if motion_stage else p.rays_strength,
		uv.x,uv.y,valid,p.rays_decay,
		p.motion_steps if motion_stage else p.rays_steps,p.motion_radius if motion_stage else p.rays_radius,
		p.motion_edge if motion_stage else p.rays_edge,p.chroma_pixels if p.chroma_enabled else 0.0,
		p.chroma_start,p.chroma_falloff,1.0 if p.rays_mode == 1 else 0.0,float(packed_color)])
	var inverse: Projection = camera.get_camera_projection().inverse()
	for column: int in range(4):
		for row: int in range(4): values.append(inverse[column][row])
	_mutex.lock()
	_parameters = values
	_scale = p.rays_resolution
	_mutex.unlock()
func _initialize_rd() -> bool:
	if _rd == null: _rd = RenderingServer.get_rendering_device()
	if _rd == null: return false
	if not _shader.is_valid():
		_shader = _rd.shader_create_from_spirv(COMPUTE.get_spirv())
		if not _shader.is_valid(): return false
		_pipeline = _rd.compute_pipeline_create(_shader)
		var state: RDSamplerState = RDSamplerState.new()
		state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		_sampler = _rd.sampler_create(state)
		state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		_point_sampler = _rd.sampler_create(state)
	return true
func _texture(size: Vector2i) -> RID:
	var format: RDTextureFormat = RDTextureFormat.new()
	format.width = size.x
	format.height = size.y
	format.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	return _rd.texture_create(format,RDTextureView.new())
func _dispatch(output: RID, color: RID, depth: RID, velocity: RID, ray: RID, size: Vector2i, parameters: PackedFloat32Array) -> void:
	var uniforms: Array[RDUniform] = []
	var textures: Array[RID] = [output,color,depth,velocity,ray]
	for index: int in range(5):
		var uniform: RDUniform = RDUniform.new()
		uniform.binding = index
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE if index == 0 else RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		if index != 0: uniform.add_id(_point_sampler if index in [2,3] else _sampler)
		uniform.add_id(textures[index])
		uniforms.append(uniform)
	var uniform_set: RID = UniformSetCacheRD.get_cache(_shader,0,uniforms)
	var list: int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list,_pipeline)
	_rd.compute_list_bind_uniform_set(list,uniform_set,0)
	var bytes: PackedByteArray = parameters.to_byte_array()
	_rd.compute_list_set_push_constant(list,bytes,bytes.size())
	_rd.compute_list_dispatch(list,ceili(size.x/8.0),ceili(size.y/8.0),1)
	_rd.compute_list_end()
func _render_callback(callback_type: int, data: RenderData) -> void:
	if callback_type != effect_callback_type or not _initialize_rd(): return
	var buffers: RenderSceneBuffersRD = data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null: return
	var size: Vector2i = buffers.get_internal_size()
	if size.x < 1 or size.y < 1: return
	_mutex.lock()
	var parameters: PackedFloat32Array = _parameters.duplicate()
	var scale: float = _scale
	var reset: bool = _reset > 0
	_reset = maxi(0,_reset-1)
	_mutex.unlock()
	if parameters.size() != 32: return
	var ray_size: Vector2i = Vector2i(maxi(1,int(size.x*scale)),maxi(1,int(size.y*scale)))
	if size != _size or ray_size != _ray_size:
		if _scratch.is_valid(): _rd.free_rid(_scratch)
		if _rays.is_valid(): _rd.free_rid(_rays)
		_size = size
		_ray_size = ray_size
		_scratch = _texture(size)
		_rays = _texture(ray_size)
		reset = true
	parameters[0] = size.x
	parameters[1] = size.y
	if motion_stage: parameters[15] = 1.0 if reset else 0.0
	for view: int in range(buffers.get_view_count()):
		var color: RID = buffers.get_color_layer(view)
		var depth: RID = buffers.get_depth_layer(view)
		var velocity: RID = buffers.get_velocity_layer(view) if motion_stage else depth
		# Scene color is sampleable/storage but not a transfer source on D3D12.
		parameters[2] = 3
		_dispatch(_scratch,color,depth,velocity,color,size,parameters)
		if motion_stage:
			parameters[2] = 0
			_dispatch(color,_scratch,depth,velocity,_scratch,size,parameters)
		else:
			if parameters[14] > 0.5:
				parameters[2] = 1
				_dispatch(_rays,_scratch,depth,velocity,_scratch,ray_size,parameters)
			parameters[2] = 2
			_dispatch(color,_scratch,depth,velocity,_rays,size,parameters)
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for rid: RID in [_shader,_sampler,_point_sampler,_scratch,_rays]:
			if rid.is_valid() and _rd != null: _rd.free_rid(rid)
