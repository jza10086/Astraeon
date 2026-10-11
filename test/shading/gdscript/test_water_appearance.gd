extends SceneTree
var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var water: AstraeonWaterAppearance = load("res://game/shading/water/resources/default_water.tres")
	check(water != null and water.validate().is_empty(), "Default resource loads")
	var copy: AstraeonWaterAppearance = water.duplicate(true)
	copy.absorption = 0.0
	copy.wave_strength = 0.0
	copy.wave_speed = 0.0
	copy.opacity = 0.0
	check(copy.validate().is_empty(), "Zero absorption, motion and opacity are supported")
	check(water.absorption == 0.22 and water.opacity == 1.0, "Shared template unchanged")
	var parameters: Dictionary[StringName, Variant] = water.surface_parameters()
	parameters[&"water_opacity"] = 0.0
	check(water.surface_parameters()[&"water_opacity"] == 1.0, "Payload is independent")
	check(not parameters.has(&"clock") and not parameters.has(&"depth_absorption"), "Runtime state and quality excluded")
	check(water.scene_reflection_parameters(true).has(&"planar_strength"), "Planar variant mapping")
	check(water.scene_reflection_parameters(false).has(&"water_ssr_strength"), "SSR variant mapping")
	for field: StringName in [&"absorption", &"opacity", &"uniform_opacity", &"roughness", &"specular", &"wave_strength", &"wave_speed", &"wave_scale", &"sky_strength", &"scene_reflection_strength", &"underwater_attenuation_rate", &"underwater_attenuation_start"]:
		for invalid: float in [-1.0, NAN, INF]:
			copy = water.duplicate(true)
			copy.set(field, invalid)
			check(not copy.validate().is_empty(), "Reject invalid %s" % field)
	for field: StringName in [&"shallow_color", &"deep_color", &"underwater_color"]:
		copy = water.duplicate(true)
		copy.set(field, Color(1, 1, 1, 0.5))
		check(not copy.validate().is_empty(), "Reject conflicting color alpha")
		copy.set(field, Color(INF, 1, 1))
		check(not copy.validate().is_empty(), "Reject nonfinite color")
	DirAccess.make_dir_recursive_absolute("res://tmp/water-appearance")
	var path: String = "res://tmp/water-appearance/roundtrip.tres"
	copy = water.duplicate(true)
	copy.absorption = 0.7
	copy.wave_speed = 2.0
	copy.underwater_attenuation_rate = 0.25
	copy.underwater_attenuation_start = 2.0
	check(ResourceSaver.save(copy, path) == OK, "Save custom water")
	var restored: AstraeonWaterAppearance = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(restored != null and restored.validate().is_empty(), "Reload custom water")
	check(restored.absorption == 0.7 and restored.wave_speed == 2.0 and restored.underwater_attenuation_rate == 0.25 and restored.underwater_attenuation_start == 2.0, "Roundtrip preserves material and underwater fields")
	print("WATER_APPEARANCE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
