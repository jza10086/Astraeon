class_name AstraeonLightingProfile
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
@export_group("局部光源")
@export var local_lights_enabled: bool = true
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
@export_enum("低", "中", "高") var shadow_quality: int = 1
@export_range(0.0, 1.0, 0.01) var shadow_bias: float = 0.06
@export_range(0.0, 4.0, 0.05) var shadow_normal_bias: float = 1.7
@export_group("P2 · 水")
@export var water_enabled: bool = true
@export_enum("低：统一水色", "标准：深度吸收") var water_quality: int = 1
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
@export_group("水面 · 屏幕空间反射")
@export var water_ssr: bool = true
@export_range(0.0, 1.0, 0.05) var water_ssr_strength: float = 1.0
@export_enum("低：16 步", "中：32 步", "高：64 步") var water_ssr_quality: int = 1
@export_range(4.0, 96.0, 1.0) var water_ssr_distance: float = 48.0
@export_range(0.02, 2.0, 0.02) var water_ssr_tolerance: float = 0.3
@export_range(0.01, 0.3, 0.01) var water_ssr_edge_fade: float = 0.08
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
@export_enum("写实简化体积云", "方块体积云") var cloud_type: int = 1
@export var block_cloud_shadows: bool = true
@export_range(0.0, 1.0, 0.05) var cloud_shadow_strength: float = 0.55
@export_range(0.0, 1.0, 0.05) var cloud_shadow_softness: float = 0.3
@export_range(8, 48, 4) var cloud_steps: int = 24
@export var cloud_morph: bool = false
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
	for property: Dictionary in settings_properties():
		var key: String = property.name
		var fallback: Variant = config.get_value("lighting_p0", key, get(key))
		var value: Variant = config.get_value("lighting", key, fallback)
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
	for property: Dictionary in settings_properties():
		config.set_value("lighting", property.name, get(property.name))
	return config.save(path)
