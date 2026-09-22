class_name AstraeonShadingProfile
extends Resource
## Defaults are copied for runtime. Only exported settings enter the local config.
@export_group("时间与天空")
@export_range(0.0, 24.0, 0.1) var hour: float = 12.0
@export var cycle_enabled: bool = false
@export_range(30.0, 3600.0) var day_seconds: float = 600.0
@export var sky_enhanced: bool = true
@export_group("基础光照")
@export var direct_enabled: bool = true
@export var block_color: Color = Color(1.0, 0.64, 0.32)
@export_range(0.0, 4.0) var block_energy: float = 1.3
@export_range(0.5, 3.0) var block_curve: float = 1.6
@export_range(0.1, 4.0, 0.05) var exposure: float = 1.0
@export_group("环境光渐变")
@export_range(0.0, 1.0, 0.05) var ambient_smoothing: float = 1.0
@export_range(0.0, 2.0, 0.05) var ambient_strength: float = 1.0
@export_range(0.5, 3.0, 0.05) var ambient_curve: float = 1.4
@export_range(0.0, 1.0, 0.05) var block_grid_strength: float = 1.0
@export_range(0.0, 0.2, 0.005) var ambient_minimum: float = 0.015
@export_color_no_alpha var ambient_minimum_color: Color = Color(0.7,0.75,0.85)
@export_group("局部光源")
@export_enum("仅自发光", "体素传播光", "点光源＋阴影", "点光源无阴影", "体素光＋限额点光源") var local_lighting_mode: int = 2
@export_range(0.0, 3.0, 0.05) var voxel_light_strength: float = 1.0
@export_range(0, 32, 1) var local_point_budget: int = 8
@export_range(0, 16, 1) var local_shadow_budget: int = 4
@export_color_no_alpha var lamp_emission_color: Color = Color(1.0,0.72,0.32)
@export_range(0.0, 8.0, 0.1) var lamp_emission_strength: float = 1.5
@export_group("光源批量测试")
@export_range(1, 32, 1) var test_light_count: int = 16
@export_group("测试人物")
@export var avatar_visible: bool = true
@export var avatar_animate: bool = true
@export_range(0.0, 3.0, 0.1) var avatar_speed: float = 1.0
@export_range(0.0, 2.0, 0.1) var avatar_travel: float = 1.0
@export_range(0.5, 3.0, 0.1) var avatar_scale: float = 1.4
@export_group("局部光源参数")
@export_range(0.0, 12.0, 0.1) var local_light_energy: float = 4.0
@export_range(2.0, 24.0, 1.0) var local_light_range: float = 12.0
@export var indirect_enabled: bool = true
@export_range(0.0, 0.25, 0.01) var indirect_strength: float = 0.04
@export_group("P1 · AO")
@export var ao_enabled: bool = true
@export_range(0.0, 1.0, 0.05) var ao_strength: float = 0.65
@export_group("P1 · 距离雾")
@export var fog_enabled: bool = true
@export_range(0.001, 0.1, 0.001) var fog_density: float = 0.006
@export_range(0.0, 100.0, 1.0) var fog_start: float = 24.0
@export_group("P1 · 抗锯齿与阴影")
@export_enum("关闭", "FXAA", "TAA") var aa_mode: int = 1
@export var shadows_enabled: bool = true
@export var hard_shadows: bool = false
@export_range(0.0, 4.0, 0.05) var shadow_blur: float = 1.0
@export_enum("1024", "2048", "4096", "8192") var shadow_resolution: int = 2
@export_range(16.0, 256.0, 8.0) var shadow_distance: float = 96.0
@export_enum("4 采样", "8 采样", "16 采样", "1 采样", "32 采样") var shadow_quality: int = 1
@export_range(0.0, 1.0, 0.01) var shadow_bias: float = 0.06
@export_range(0.0, 4.0, 0.05) var shadow_normal_bias: float = 2.0
@export_group("P2 · 水")
@export var water_enabled: bool = true
@export_enum("统一水色", "逐像素深度吸收") var water_quality: int = 1
@export var waves_enabled: bool = true
@export_range(0.0, 0.3, 0.01) var wave_strength: float = 0.12
@export var water_reflection: bool = true
@export_color_no_alpha var water_shallow_color: Color = Color(0.06, 0.4, 0.36)
@export_color_no_alpha var water_deep_color: Color = Color(0.012, 0.075, 0.15)
@export_range(0.01, 1.5, 0.01) var water_absorption: float = 0.22
@export_range(0.0, 1.0, 0.01) var water_opacity: float = 1.0
@export_range(0.0, 1.0, 0.01) var water_low_opacity: float = 0.65
@export_range(0.0, 1.0, 0.01) var water_roughness: float = 0.22
@export_range(0.0, 1.0, 0.05) var water_specular: float = 0.45
@export_range(0.2, 4.0, 0.1) var wave_scale: float = 1.0
@export_range(0.0, 4.0, 0.1) var wave_speed: float = 1.0
@export_range(0.0, 2.0, 0.05) var water_sky_strength: float = 1.0
@export_group("水面 · 场景反射")
@export_enum("关闭", "SSR", "平面反射") var water_reflection_mode: int = 2
@export_group("水面 · SSR 参数")
@export_range(0.0, 1.0, 0.05) var water_ssr_strength: float = 1.0
@export_range(4, 128, 1) var water_ssr_steps: int = 32
@export_range(0, 8, 1) var water_ssr_refinements: int = 5
@export_range(0.0, 0.3, 0.01) var water_ssr_normal_offset: float = 0.06
@export_range(4.0, 96.0, 1.0) var water_ssr_distance: float = 48.0
@export_range(0.02, 2.0, 0.02) var water_ssr_tolerance: float = 0.3
@export_range(0.01, 0.3, 0.01) var water_ssr_edge_fade: float = 0.08
@export_group("水面 · 平面反射参数")
@export_range(0.0, 1.0, 0.05) var planar_strength: float = 1.0
@export_range(0.1, 1.0, 0.05) var planar_resolution_scale: float = 0.5
@export_range(0, 120, 1) var planar_update_fps: int = 0
@export_range(16.0, 1600.0, 8.0) var planar_distance: float = 256.0
@export_range(-0.2, 0.3, 0.01) var planar_clip_offset: float = 0.02
@export_range(0.0, 0.1, 0.001) var planar_distortion: float = 0.015
@export_range(0.0, 6.0, 0.25) var planar_blur_pixels: float = 0.0
@export_range(0.001, 0.2, 0.001) var planar_edge_fade: float = 0.02
@export_enum("关闭", "FXAA") var planar_aa: int = 1
@export var planar_visible_only: bool = true
@export var planar_reflect_plants: bool = true
@export var planar_reflect_clouds: bool = true
@export var planar_fog: bool = true
@export_group("水下")
@export var underwater_enabled: bool = true
@export_color_no_alpha var underwater_color: Color = Color(0.015, 0.16, 0.23)
@export_range(1.0, 40.0, 1.0) var underwater_distance: float = 12.0
@export_group("P2 · 植被")
@export var wind_enabled: bool = true
@export_range(0.0, 0.5, 0.01) var wind_strength: float = 0.12
@export var translucency_enabled: bool = true
@export_range(0.0, 1.0, 0.05) var translucency_strength: float = 0.25
@export_group("P2 · 云")
@export var clouds_enabled: bool = true
@export var block_cloud_shadows: bool = true
@export_range(0.0, 1.0, 0.05) var cloud_shadow_strength: float = 0.55
@export_range(0.0, 1.0, 0.05) var cloud_shadow_softness: float = 0.3
@export_range(0.0, 1.0, 0.05) var cloud_coverage: float = 0.45
@export_range(0.0, 0.2, 0.005) var cloud_speed: float = 0.015
@export_group("P2 · Bloom")
@export var bloom_enabled: bool = false
@export_range(0.0, 2.0, 0.05) var bloom_strength: float = 0.6
@export_group("显示与帧率")
@export var show_fps: bool = true
@export_range(0, 360, 1) var max_fps: int = 0
@export var vsync_enabled: bool = false
@export_group("传播预算")
@export_range(256, 32768) var work_cells: int = 4096
@export_range(250, 8000) var work_usec: int = 2000

@export_group("扩展模块")
@export_range(0,2,0.01) var color_saturation: float = 1.0
@export_range(0.5,2,0.01) var color_contrast: float = 1.0
@export_range(0,4,0.05) var color_night_brightness: float = 1.0
@export_color_no_alpha var color_night_direct: Color = Color(0.5,0.65,1)
@export_color_no_alpha var color_night_zenith: Color = Color(0.005,0.009,0.025)
@export_color_no_alpha var color_night_horizon: Color = Color(0.015,0.02,0.045)
@export_color_no_alpha var color_night_ambient: Color = Color(0.025,0.035,0.07)
@export_color_no_alpha var color_night_fog: Color = Color(0.015,0.02,0.045)
@export_range(0,8,0.05) var color_night_energy: float = 0.08
@export_color_no_alpha var color_dawn_direct: Color = Color(1,0.5,0.3)
@export_color_no_alpha var color_dawn_zenith: Color = Color(0.15,0.18,0.35)
@export_color_no_alpha var color_dawn_horizon: Color = Color(0.9,0.43,0.25)
@export_color_no_alpha var color_dawn_ambient: Color = Color(0.4,0.3,0.28)
@export_color_no_alpha var color_dawn_fog: Color = Color(0.7,0.4,0.3)
@export_range(0,8,0.05) var color_dawn_energy: float = 1.8
@export_color_no_alpha var color_noon_direct: Color = Color(1,0.95,0.83)
@export_color_no_alpha var color_noon_zenith: Color = Color(0.12,0.32,0.7)
@export_color_no_alpha var color_noon_horizon: Color = Color(0.64,0.78,0.95)
@export_color_no_alpha var color_noon_ambient: Color = Color(0.42,0.51,0.66)
@export_color_no_alpha var color_noon_fog: Color = Color(0.64,0.78,0.95)
@export_range(0,8,0.05) var color_noon_energy: float = 1.8
@export_color_no_alpha var color_dusk_direct: Color = Color(1,0.38,0.12)
@export_color_no_alpha var color_dusk_zenith: Color = Color(0.18,0.14,0.3)
@export_color_no_alpha var color_dusk_horizon: Color = Color(0.95,0.3,0.12)
@export_color_no_alpha var color_dusk_ambient: Color = Color(0.48,0.27,0.22)
@export_color_no_alpha var color_dusk_fog: Color = Color(0.7,0.29,0.23)
@export_range(0,8,0.05) var color_dusk_energy: float = 1.8
@export_enum("固定","自动") var exposure_mode: int = 0
@export_range(0,6400,10) var auto_min_iso: float = 50.0
@export_range(1,12800,10) var auto_max_iso: float = 800.0
@export_range(0.01,10,0.01) var auto_speed: float = 0.5
@export_range(0.01,8,0.01) var auto_scale: float = 1.0
@export_enum("关闭","手动焦点","中心射线自动焦点") var dof_mode: int = 0
@export_range(0.1,200,0.1) var dof_focus: float = 10.0
@export_range(0,100,0.1) var dof_near_zone: float = 2.0
@export_range(0,100,0.1) var dof_far_zone: float = 4.0
@export_range(0.1,100,0.1) var dof_near_transition: float = 2.0
@export_range(0.1,100,0.1) var dof_far_transition: float = 8.0
@export_range(0,1,0.01) var dof_amount: float = 0.1
@export_range(0.1,20,0.1) var dof_focus_speed: float = 5.0
@export var dof_near: bool = true
@export var dof_far: bool = true
@export var ssao_enabled: bool = false
@export_range(0.01,16,0.01) var ssao_radius: float = 1.0
@export_range(0,8,0.05) var ssao_intensity: float = 1.0
@export_range(0.1,6,0.1) var ssao_power: float = 1.5
@export_range(0,5,0.05) var ssao_detail: float = 0.5
@export_range(0,1,0.01) var ssao_sharpness: float = 0.98
@export_range(0,1,0.05) var ssao_light_affect: float = 0.0
@export_range(0,1,0.05) var ssao_adaptive: float = 0.5
@export var ssao_half_size: bool = true
@export_enum("Very Low（引擎）","Low（引擎）","Medium（引擎）","High（引擎）","Ultra 自适应（引擎）") var ssao_quality: int = 2
@export_range(0,6,1) var ssao_blur_passes: int = 2
@export_enum("关闭","屏幕空间光束","真实体积光") var rays_mode: int = 0
@export_range(0,4,0.01) var rays_strength: float = 0.3
@export_range(0.05,2,0.05) var rays_radius: float = 0.8
@export_range(0.8,1,0.001) var rays_decay: float = 0.97
@export_range(0.25,1,0.25) var rays_resolution: float = 0.5
@export_range(0.001,1,0.001) var rays_edge: float = 0.1
@export_range(4,96,1) var rays_steps: int = 32
@export_range(0,0.1,0.001) var volume_density: float = 0.008
@export_range(0,0.3,0.001) var volume_local_density: float = 0.04
@export_range(-0.9,0.9,0.01) var volume_anisotropy: float = 0.6
@export_range(8,256,1) var volume_length: float = 96.0
@export_range(0,0.99,0.01) var volume_temporal_amount: float = 0.9
@export_range(0,8,0.05) var volume_sun_energy: float = 1.0
@export_range(0,8,0.05) var volume_local_energy: float = 0.5
@export_color_no_alpha var volume_albedo: Color = Color(0.9,0.93,1)
@export var volume_temporal: bool = true
@export_range(32,256,8) var volume_grid: int = 64
@export_range(32,256,8) var volume_depth: int = 64
@export var planar_ssao: bool = false
@export var planar_volumetric: bool = false
@export_enum("关闭","相机手持演示","环绕移动演示") var moving_mode: int = 0
@export_color_no_alpha var moving_color: Color = Color(1,0.74,0.4)
@export_range(0,16,0.1) var moving_energy: float = 4.0
@export_range(1,32,0.5) var moving_range: float = 12.0
@export_range(0.1,8,0.1) var moving_attenuation: float = 2.0
@export_range(0,5,0.05) var moving_speed: float = 1.0
@export_range(0,8,0.05) var moving_volume_energy: float = 0.0
@export var moving_shadows: bool = true
@export_range(0,100,1) var moving_priority: int = 10
@export_range(0,64,1) var light_budget: int = 32
@export_range(0,32,1) var light_shadow_budget: int = 8
@export_range(0,10,0.1) var light_hysteresis: float = 2.0
@export_enum("晴天","阴天","降雨") var weather_mode: int = 0
@export_range(0,1,0.05) var weather_weight: float = 1.0
@export_range(0.1,60,0.1) var weather_transition: float = 5.0
@export_range(0,1,0.05) var weather_cloud: float = 0.9
@export_range(0,4,0.1) var weather_wind: float = 1.5
@export var rain_enabled: bool = true
@export_range(128,16000,128) var rain_count: int = 4000
@export_range(4,48,1) var rain_area: float = 16.0
@export_range(2,40,1) var rain_speed: float = 18.0
@export_range(0.02,2,0.01) var rain_length: float = 0.35
@export_range(0.002,0.1,0.001) var rain_width: float = 0.015
@export_range(0,1,0.01) var rain_alpha: float = 0.3
@export var wet_enabled: bool = true
@export_range(0.001,2,0.001) var wet_accumulation: float = 0.2
@export_range(0.001,1,0.001) var wet_drying: float = 0.03
@export_range(0,0.8,0.01) var wet_darken: float = 0.25
@export_range(0.02,1,0.01) var wet_roughness: float = 0.18
@export_range(0,1,0.01) var wet_specular: float = 0.65
@export var gloss_enabled: bool = true
@export_range(0.02,1,0.01) var gloss_block_roughness: float = 0.9
@export_range(0,1,0.01) var gloss_block_metallic: float = 0.0
@export_range(0,1,0.01) var gloss_block_specular: float = 0.25
@export_range(0.02,1,0.01) var gloss_metal_roughness: float = 0.22
@export_range(0,1,0.01) var gloss_metal_metallic: float = 0.9
@export_range(0,1,0.01) var gloss_metal_specular: float = 0.5
@export var glass_enabled: bool = false
@export_color_no_alpha var glass_color: Color = Color(0.9,0.12,0.05)
@export_range(0,1,0.01) var glass_transmission: float = 0.7
@export_range(16,128,1) var glass_range: float = 64.0
@export_range(0.001,1,0.001) var glass_bias: float = 0.08
@export_range(0,4,0.25) var glass_filter: float = 1.0
@export_enum("最近邻", "原四点", "双线性比较", "3×3 Tent", "5×5 Tent", "圆盘 8 点", "圆盘 16 点") var glass_filter_mode: int = 2
@export_enum("512","1024","2048","4096") var glass_resolution: int = 1
@export var motion_enabled: bool = false
@export_range(0,360,1) var motion_shutter: float = 90.0
@export_range(0,64,1) var motion_radius: float = 16.0
@export_range(0.01,5,0.01) var motion_edge: float = 0.3
@export_range(2,32,1) var motion_steps: int = 8
@export var chroma_enabled: bool = false
@export_range(0,8,0.1) var chroma_pixels: float = 1.5
@export_range(0,0.99,0.01) var chroma_start: float = 0.4
@export_range(0.1,8,0.1) var chroma_falloff: float = 2.0

@export_enum("关闭", "程序化圆盘", "贴图圆盘") var celestial_mode: int = 1
@export_range(0.1,12.0,0.1) var celestial_sun_size: float = 1.0
@export_range(0.1,12.0,0.1) var celestial_moon_size: float = 1.2
@export_range(0,30,0.1) var celestial_sun_energy: float = 5.0
@export_range(0,10,0.1) var celestial_moon_energy: float = 1.0
@export_color_no_alpha var celestial_sun_color: Color = Color(1.0,0.9,0.7)
@export_color_no_alpha var celestial_moon_color: Color = Color(0.65,0.75,1.0)
@export_range(0.001,0.5,0.001) var celestial_edge: float = 0.02
@export_range(0,4,0.05) var celestial_halo: float = 0.25

## Primary voxel lighting and the optional weak fill have separate controls.
func effective_block_strength() -> float:
	if local_lighting_mode == 0:
		return 0.0
	if local_lighting_mode == 1 or local_lighting_mode == 4:
		return voxel_light_strength
	return indirect_strength if indirect_enabled else 0.0

func settings_properties() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for property: Dictionary in get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_EDITOR:
			result.append(property)
	return result

## Load known, type-checked fields; missing fields retain current defaults.
func load_settings(path: String = "user://settings.cfg") -> Error:
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(path)
	if error != OK:
		return error
	if config.get_value("shading", "format", "") != "astraeon-shading-20260922":
		return ERR_FILE_UNRECOGNIZED
	var known: Array[String] = ["format"]
	for property: Dictionary in settings_properties():
		known.append(property.name)
	for key: String in config.get_section_keys("shading"):
		if key not in known:
			return ERR_FILE_UNRECOGNIZED
	for property: Dictionary in settings_properties():
		var key: String = property.name
		var value: Variant = config.get_value("shading", key, get(key))
		var expected: int = property.type
		if expected == TYPE_FLOAT or expected == TYPE_INT:
			if not (value is float or value is int) or not is_finite(float(value)):
				continue
			var numeric: float = float(value)
			if property.hint == PROPERTY_HINT_RANGE:
				var limits: PackedStringArray = str(property.hint_string).split(",")
				numeric = clampf(numeric, float(limits[0]), float(limits[1]))
			elif property.hint == PROPERTY_HINT_ENUM:
				numeric = clampf(numeric, 0, str(property.hint_string).split(",").size() - 1)
			set(key, int(numeric) if expected == TYPE_INT else numeric)
		elif typeof(value) == expected:
			set(key, value)
	return OK

func save_settings(path: String = "user://settings.cfg") -> Error:
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(path)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		return error # Do not overwrite an unreadable file.
	if config.has_section("shading"):
		config.erase_section("shading")
	config.set_value("shading", "format", "astraeon-shading-20260922")
	for property: Dictionary in settings_properties():
		config.set_value("shading", property.name, get(property.name))
	var temporary: String = path + ".tmp"
	error = config.save(temporary)
	if error != OK:
		return error
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
