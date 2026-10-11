extends Node3D
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
## Test-only assembly of reusable shading components and explicit sample adapters.
const CameraEffects: Script = preload("res://game/shading/gdscript/camera_effects.gd")
const Shafts: Script = preload("res://game/shading/gdscript/light_shafts.gd")
const CameraPost: Script = preload("res://game/shading/gdscript/camera_post.gd")
const Weather: Script = preload("res://test/shading/gdscript/weather_fixture.gd")
const Glass: Script = preload("res://game/shading/gdscript/colored_shadows.gd")
const Moving: Script = preload("res://game/shading/gdscript/moving_light.gd")
const Budget: Script = preload("res://game/shading/gdscript/light_budget.gd")
const SurfaceMap: Script = preload("res://test/shading/gdscript/surface_map_adapter.gd")
var sample: Node3D
var camera_effects: CameraEffects = CameraEffects.new()
var motion: CameraPost = CameraPost.new()
var post: CameraPost = CameraPost.new()
var shafts: Shafts = Shafts.new()
var weather: Weather = Weather.new()
var glass: Glass = Glass.new()
var moving: Moving = Moving.new()
var budget: Budget = Budget.new()
var metal_materials: Array[ShaderMaterial] = []
var receiver_materials: Array[ShaderMaterial] = []
var panes: Array[MeshInstance3D] = []
var fog: FogVolume = FogVolume.new()
var _clock: float = 0.0
var _budget_clock: float = 0.0
var _focus_clock: float = 0.0
var _focus_distance: float = 10.0
var _last_camera: Transform3D
func build_fixtures(owner_sample: Node3D) -> void:
	sample = owner_sample
	for index: int in range(3):
		var metal: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(1.5,2.0,1.5)
		metal.mesh = box
		metal.position = Vector3(15+index*3,2,9)
		var material: ShaderMaterial = sample._sections.materials[0].duplicate() as ShaderMaterial
		material.set_shader_parameter("base_color",Color(0.5+index*0.15,0.5,0.35))
		metal.material_override = material
		metal_materials.append(material)
		add_child(metal)
	var pane: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(6,6)
	pane.mesh = plane
	pane.position = Vector3(9,6,12)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.9,0.12,0.05,0.25)
	pane.material_override = material
	add_child(pane)
	panes.append(pane)
func configure(receivers: Array[ShaderMaterial]) -> void:
	receiver_materials = receivers
	add_child(weather)
	weather.configure(receivers)
	add_child(glass)
	glass.configure(receivers)
	for pane: MeshInstance3D in panes: glass.add_caster(pane)
	add_child(moving)
	motion.configure_stage(true)
	post.configure_stage(false)
	var compositor: Compositor = Compositor.new()
	add_child(shafts)
	shafts.configure(sample._camera)
	compositor.compositor_effects = [motion,shafts.effect,post]
	sample._camera.compositor = compositor
	_last_camera = sample._camera.global_transform
	fog.size = Vector3(12,7,12)
	fog.position = Vector3(0,3,0)
	fog.material = FogMaterial.new()
	add_child(fog)
	surface_changed()
func surface_changed() -> void:
	weather.set_surface_map(SurfaceMap.make_height_map(sample._volume,panes),Vector2(sample._volume.origin.x,sample._volume.origin.z),Vector2(sample._volume.size.x,sample._volume.size.z),sample._volume.revision)
func apply(p: Profile) -> void:
	camera_effects.apply(p,sample._camera,sample._environment,sample._sun)
	weather.apply(p)
	moving.apply(p)
	fog.visible = p.rays_mode == 2 and p.volume_local_density > 0.0
	(fog.material as FogMaterial).density = p.volume_local_density
	(fog.material as FogMaterial).albedo = p.volume_albedo
	sample._environment.adjustment_enabled = not is_equal_approx(p.color_saturation,1.0) or not is_equal_approx(p.color_contrast,1.0)
	sample._environment.adjustment_saturation = p.color_saturation
	sample._environment.adjustment_contrast = p.color_contrast
	for material: ShaderMaterial in receiver_materials:
		var metal: bool = material in metal_materials
		material.set_shader_parameter("material_roughness",(p.gloss_metal_roughness if metal else p.gloss_block_roughness) if p.gloss_enabled else 1.0)
		material.set_shader_parameter("material_metallic",(p.gloss_metal_metallic if metal else p.gloss_block_metallic) if p.gloss_enabled else 0.0)
		material.set_shader_parameter("material_specular",(p.gloss_metal_specular if metal else p.gloss_block_specular) if p.gloss_enabled else 0.0)
	_allocate(p)
func _allocate(p: Profile) -> void:
	# Reconstruct fixed requests before allocation (allocated energy is output only).
	sample._local_lights.apply(p)
	budget.clear_requests()
	for lamp: OmniLight3D in sample._local_lights.emitters.values():
		lamp.light_volumetric_fog_energy = p.volume_local_energy if p.rays_mode == 2 else 0.0
		budget.register(lamp,lamp.light_energy,lamp.shadow_enabled)
	budget.register(moving.light,moving.energy,moving.request_shadows,moving.priority)
	budget.allocate(sample._camera.global_position,p.light_budget,p.light_shadow_budget,p.light_hysteresis)
func reset_camera() -> void:
	motion.reset_history()
	post.reset_history()
func tick(delta: float, p: Profile) -> void:
	_clock += delta
	var camera: Camera3D = sample._camera
	if p.moving_mode == 1:
		moving.global_transform = camera.global_transform
		moving.global_position += camera.global_basis*Vector3(0.35,-0.25,-0.5)
	elif p.moving_mode == 2:
		moving.global_position = Vector3(9+cos(_clock*p.moving_speed)*5,3,12+sin(_clock*p.moving_speed)*5)
	_budget_clock += delta
	if _budget_clock >= 0.2:
		_budget_clock = 0.0
		_allocate(p)
	glass.tick(p,sample._sun,camera.global_position)
	if weather.tick(delta,p,camera.global_position): sample._apply_lighting()
	if camera.global_position.distance_to(_last_camera.origin)>3.0 or camera.global_basis.z.dot(_last_camera.basis.z)<0.7: reset_camera()
	_last_camera = camera.global_transform
	motion.update(p,camera,sample._sun)
	post.update(p,camera,sample._sun)
	shafts.tick(p,sample._sun,sample._block_clouds,weather.cloud_weight)
	if p.dof_mode == 2:
		_focus_clock += delta
		if _focus_clock > 0.1:
			_focus_clock = 0.0
			_focus_distance = 100.0
			for step: int in range(1,401):
				var distance: float = step*0.25
				var position: Vector3i = Vector3i((camera.global_position-camera.global_basis.z*distance).floor())
				if sample._volume.contains(position) and sample._volume.voxel_at(position)!=0:
					_focus_distance = distance
					break
		camera_effects.update_focus(p,_focus_distance,delta)
