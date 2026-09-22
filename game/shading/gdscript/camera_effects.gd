extends RefCounted
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
## Camera-local attributes; mirror cameras receive their own neutral attributes.
var attributes: CameraAttributesPractical = CameraAttributesPractical.new()
var focus: float = 10.0
func apply(p: Profile, camera: Camera3D, environment: Environment, sun: DirectionalLight3D) -> void:
	camera.attributes = attributes
	attributes.auto_exposure_enabled = p.exposure_mode == 1
	attributes.auto_exposure_min_sensitivity = minf(p.auto_min_iso, p.auto_max_iso)
	attributes.auto_exposure_max_sensitivity = maxf(p.auto_min_iso, p.auto_max_iso)
	attributes.auto_exposure_speed = p.auto_speed
	attributes.auto_exposure_scale = p.auto_scale
	attributes.exposure_multiplier = 1.0
	environment.tonemap_exposure = p.exposure if p.exposure_mode == 0 else 1.0
	attributes.dof_blur_near_enabled = p.dof_mode != 0 and p.dof_near
	attributes.dof_blur_far_enabled = p.dof_mode != 0 and p.dof_far
	attributes.dof_blur_amount = p.dof_amount
	attributes.dof_blur_near_transition = p.dof_near_transition
	attributes.dof_blur_far_transition = p.dof_far_transition
	if p.dof_mode == 1: focus = p.dof_focus
	update_focus(p, focus, 0.0)
	environment.ssao_enabled = p.ssao_enabled
	environment.ssao_radius = p.ssao_radius
	environment.ssao_intensity = p.ssao_intensity
	environment.ssao_power = p.ssao_power
	environment.ssao_detail = p.ssao_detail
	environment.ssao_sharpness = p.ssao_sharpness
	environment.ssao_light_affect = p.ssao_light_affect
	RenderingServer.environment_set_ssao_quality(p.ssao_quality, p.ssao_half_size, p.ssao_adaptive, p.ssao_blur_passes, 50.0, 150.0)
	environment.volumetric_fog_enabled = p.rays_mode == 2
	environment.volumetric_fog_density = p.volume_density
	environment.volumetric_fog_albedo = p.volume_albedo
	environment.volumetric_fog_anisotropy = p.volume_anisotropy
	environment.volumetric_fog_length = p.volume_length
	environment.volumetric_fog_temporal_reprojection_enabled = p.volume_temporal
	environment.volumetric_fog_temporal_reprojection_amount = p.volume_temporal_amount
	RenderingServer.environment_set_volumetric_fog_volume_size(p.volume_grid, p.volume_depth)
	sun.light_volumetric_fog_energy = p.volume_sun_energy if p.rays_mode == 2 else 0.0

func update_focus(p: Profile, distance: float, delta: float) -> void:
	if p.dof_mode == 2: focus = lerpf(focus, distance, 1.0 - exp(-delta * p.dof_focus_speed))
	attributes.dof_blur_near_distance = maxf(0.01, focus - p.dof_near_zone)
	attributes.dof_blur_far_distance = focus + p.dof_far_zone
