extends Node3D
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
## Two small orthographic captures of explicitly registered glass only.
## RGB transmittance and nearest linear depth are separate to avoid alpha sorting.
var viewports: Array[SubViewport] = []
var cameras: Array[Camera3D] = []
var copies: Array[MeshInstance3D] = []
var casters: Array[MeshInstance3D] = []
var receivers: Array[ShaderMaterial] = []
var captures: int = 0
var _active: bool = false
var _signature: Array = []
func configure(materials: Array[ShaderMaterial]) -> void:
	receivers = materials
	for pass_index: int in range(2):
		var viewport: SubViewport = SubViewport.new()
		viewport.own_world_3d = true
		viewport.use_hdr_2d = true # Preserve linear depth/transmittance without sRGB encoding.
		viewport.size = Vector2i(1024,1024)
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(viewport)
		var camera: Camera3D = Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.near = 0.01
		camera.far = 256.0
		camera.attributes = CameraAttributesPractical.new()
		camera.environment = Environment.new()
		camera.environment.background_mode = Environment.BG_COLOR
		camera.environment.background_color = Color.WHITE
		camera.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		viewport.add_child(camera)
		camera.current = true
		viewports.append(viewport)
		cameras.append(camera)
	for material: ShaderMaterial in receivers:
		material.set_shader_parameter("glass_depth_map", viewports[0].get_texture())
		material.set_shader_parameter("glass_color_map", viewports[1].get_texture())
func add_caster(caster: MeshInstance3D) -> void:
	casters.append(caster)
	caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for index: int in range(2):
		var copy: MeshInstance3D = MeshInstance3D.new()
		copy.mesh = caster.mesh
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = preload("res://game/shading/shaders/glass_capture.gdshader")
		material.set_shader_parameter("depth_pass", index == 0)
		copy.material_override = material
		viewports[index].add_child(copy)
		copies.append(copy)
	_signature.clear()
func remove_caster(caster: MeshInstance3D) -> void:
	var index: int = casters.find(caster)
	if index < 0: return
	if is_instance_valid(caster): caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for pass_index: int in range(2):
		copies[index*2].queue_free()
		copies.remove_at(index*2)
	casters.remove_at(index)
	_signature.clear()

func tick(p: Profile, sun: DirectionalLight3D, observer: Vector3) -> void:
	for index: int in range(casters.size()-1,-1,-1):
		if not is_instance_valid(casters[index]):
			for pass_index: int in range(2):
				copies[index*2].queue_free()
				copies.remove_at(index*2)
			casters.remove_at(index)
			_signature.clear()
	var active: bool = p.glass_enabled and sun.visible and not casters.is_empty()
	if active != _active:
		_active = active
		_signature.clear()
		for material: ShaderMaterial in receivers: material.set_shader_parameter("glass_active", active)
	if not active: return
	var resolution: int = 512 << p.glass_resolution
	var basis: Basis = sun.global_basis
	var local: Vector3 = basis.inverse() * observer
	var texel: float = p.glass_range / resolution
	local.x = snappedf(local.x, texel)
	local.y = snappedf(local.y, texel)
	local.z = snappedf(local.z, 8.0)
	var transform: Transform3D = Transform3D(basis, basis * local + basis.z * 100.0)
	var signature: Array = [transform,p.glass_color,p.glass_transmission,p.glass_range,resolution,p.glass_bias,p.glass_filter,p.glass_filter_mode]
	for caster: MeshInstance3D in casters: signature.append(caster.global_transform)
	if signature == _signature: return
	_signature = signature
	for index: int in range(2):
		viewports[index].size = Vector2i(resolution,resolution)
		cameras[index].size = p.glass_range
		cameras[index].global_transform = transform
		viewports[index].render_target_update_mode = SubViewport.UPDATE_ONCE
	for index: int in range(casters.size()):
		var caster: MeshInstance3D = casters[index]
		var visible_material: StandardMaterial3D = caster.material_override as StandardMaterial3D
		visible_material.albedo_color = Color(p.glass_color, 0.25)
		for pass_index: int in range(2):
			var copy: MeshInstance3D = copies[index*2+pass_index]
			copy.global_transform = caster.global_transform
			(copy.material_override as ShaderMaterial).set_shader_parameter("transmission",p.glass_color*p.glass_transmission)
	for material: ShaderMaterial in receivers:
		material.set_shader_parameter("glass_view", transform.affine_inverse())
		material.set_shader_parameter("glass_projection", cameras[0].get_camera_projection())
		material.set_shader_parameter("glass_bias", p.glass_bias)
		material.set_shader_parameter("glass_filter", p.glass_filter)
		material.set_shader_parameter("glass_filter_mode", p.glass_filter_mode)
		material.set_shader_parameter("glass_texel", 1.0/resolution)
	captures += 1
