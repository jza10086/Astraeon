@tool
class_name AstraeonBreakingTextureGroup
extends Resource
## Ten left-to-right square masks. RGB white marks cracks; black leaves the surface unchanged.
@export var stages_texture: Texture2D
@export var tint: Color = Color(0.025, 0.02, 0.018, 1.0)
@export_range(0.0, 1.0) var strength: float = 0.9

func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if stages_texture == null:
		errors.append("stages_texture is required")
	elif stages_texture.get_height() < 1 or stages_texture.get_height() > 1024 or stages_texture.get_width() != stages_texture.get_height() * 10:
		errors.append("stages_texture must be ten horizontal square masks, 1..1024 pixels per stage")
	if not is_finite(strength) or strength < 0.0 or strength > 1.0:
		errors.append("strength must be finite and within [0,1]")
	for channel: float in [tint.r, tint.g, tint.b, tint.a]:
		if not is_finite(channel) or channel < 0.0 or channel > 1.0:
			errors.append("tint must be finite and within [0,1]")
	return errors
