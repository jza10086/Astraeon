class_name AstraeonBlockLightAppearance
extends Resource
## Illumination request, independent of surface emission and renderer budgets.
enum ShadowPolicy { FOLLOW_GLOBAL, DISABLED }
@export var color: Color = Color.WHITE
@export_range(0.0, 64.0, 0.01, "or_greater") var energy: float = 0.0
@export_range(0.0, 128.0, 0.1, "or_greater") var range: float = 8.0
@export_range(0.001, 16.0, 0.001, "or_greater") var attenuation: float = 1.0
## Meters from block center, in authored coordinates.
@export var local_offset: Vector3 = Vector3.ZERO
@export_range(0.0, 4.0, 0.01, "or_greater") var source_radius: float = 0.0
@export var shadow_policy: ShadowPolicy = ShadowPolicy.FOLLOW_GLOBAL

func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	for field: StringName in [&"energy", &"range", &"source_radius"]:
		var value: float = float(get(field))
		if not is_finite(value) or value < 0.0:
			errors.append("%s must be finite and nonnegative" % field)
	if energy > 0.0 and range <= 0.0:
		errors.append("Enabled illumination requires a positive range")
	if not is_finite(attenuation) or attenuation <= 0.0:
		errors.append("attenuation must be finite and positive")
	if not local_offset.is_finite():
		errors.append("local_offset must be finite")
	for channel: float in [color.r, color.g, color.b, color.a]:
		if not is_finite(channel) or channel < 0.0 or channel > 1.0:
			errors.append("color must use ordinary [0, 1] channels")
			break
	if shadow_policy < ShadowPolicy.FOLLOW_GLOBAL or shadow_policy > ShadowPolicy.DISABLED:
		errors.append("Unsupported shadow_policy")
	return errors
