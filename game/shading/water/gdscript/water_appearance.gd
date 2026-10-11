@tool
class_name AstraeonWaterAppearance
extends Resource
## Shared water authoring data, read-only to consumers.
## No body bounds, level, camera state, reflection textures or quality budgets.
@export_group("Color and absorption")
@export_color_no_alpha var shallow_color: Color = Color(0.06, 0.4, 0.36)
@export_color_no_alpha var deep_color: Color = Color(0.012, 0.075, 0.15)
## Beer-Lambert coefficient in inverse meters. Zero means no depth absorption.
@export_range(0.0, 1.5, 0.01, "or_greater") var absorption: float = 0.22
@export_range(0.0, 1.0) var opacity: float = 1.0
@export_range(0.0, 1.0) var uniform_opacity: float = 0.65
@export_group("Surface")
@export_range(0.0, 1.0) var roughness: float = 0.22
@export_range(0.0, 1.0) var specular: float = 0.45
@export_group("Waves")
## Maximum combined displacement in meters in the current two-wave model.
@export_range(0.0, 0.3, 0.01, "or_greater") var wave_strength: float = 0.12
@export_range(0.01, 4.0, 0.01, "or_greater") var wave_scale: float = 1.0
## Multiplier on the current wave model clock, not fluid velocity.
@export_range(0.0, 4.0, 0.01, "or_greater") var wave_speed: float = 1.0
@export_group("Reflection response")
@export_range(0.0, 2.0, 0.01, "or_greater") var sky_strength: float = 1.0
@export_range(0.0, 1.0) var scene_reflection_strength: float = 1.0
@export_group("Underwater")
@export_color_no_alpha var underwater_color: Color = Color(0.015, 0.16, 0.23)
## Inverse smooth attenuation transition length; the enable switch is runtime policy.
@export_range(0.0, 2.0, 0.001, "or_greater") var underwater_attenuation_rate: float = 1.0 / 12.0
@export_range(0.0, 128.0, 0.1, "or_greater") var underwater_attenuation_start: float = 0.0

func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	for field: StringName in [&"opacity", &"uniform_opacity", &"roughness", &"specular", &"scene_reflection_strength"]:
		var value: float = float(get(field))
		if not is_finite(value) or value < 0.0 or value > 1.0:
			errors.append("%s must be finite and within [0, 1]" % field)
	for field: StringName in [&"absorption", &"wave_strength", &"wave_speed", &"sky_strength", &"underwater_attenuation_rate", &"underwater_attenuation_start"]:
		var value: float = float(get(field))
		if not is_finite(value) or value < 0.0:
			errors.append("%s must be finite and nonnegative" % field)
	for field: StringName in [&"wave_scale"]:
		var value: float = float(get(field))
		if not is_finite(value) or value <= 0.0:
			errors.append("%s must be finite and positive" % field)
	for field: StringName in [&"shallow_color", &"deep_color", &"underwater_color"]:
		var value: Color = get(field)
		if not is_equal_approx(value.a, 1.0):
			errors.append("%s alpha must be 1; use opacity instead" % field)
		for channel: float in [value.r, value.g, value.b]:
			if not is_finite(channel) or channel < 0.0 or channel > 1.0:
				errors.append("%s must use ordinary [0, 1] color channels" % field)
				break
	return errors

## Fresh parameter values only; caller owns material lifetime and runtime policy.
## Does not select a shader or enable effects. Rejected resources produce no payload.
func surface_parameters() -> Dictionary[StringName, Variant]:
	if not validate().is_empty():
		push_error("Invalid water appearance: %s" % validate())
		return {}
	return {
		&"water_shallow_color": shallow_color,
		&"water_deep_color": deep_color,
		&"water_absorption": absorption,
		&"water_opacity": opacity,
		&"water_low_opacity": uniform_opacity,
		&"water_roughness": roughness,
		&"water_specular": specular,
		&"wave_strength": wave_strength,
		&"wave_scale": wave_scale,
		&"water_sky_strength": sky_strength,
	}

## Only send this value to the selected reflection shader variant.
func scene_reflection_parameters(planar: bool) -> Dictionary[StringName, float]:
	return {&"planar_strength": scene_reflection_strength} if planar else {&"water_ssr_strength": scene_reflection_strength}
