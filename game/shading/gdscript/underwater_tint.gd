extends CanvasLayer
## View-local color filter after 3D tonemapping and before HUD. No scene-color copy.
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
var overlay: ColorRect = ColorRect.new()

func _init() -> void:
	layer = -1
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## Only replace disabled distance attenuation; do not stack a tint over underwater fog.
func apply(settings: Profile, underwater: bool) -> void:
	var active: bool = underwater and settings.water_enabled and settings.underwater_enabled
	active = active and (not settings.underwater_visibility_enabled or settings.underwater_attenuation_rate <= 0.0)
	var tint: Color = settings.underwater_color
	tint.a = clampf(settings.underwater_tint_opacity, 0.0, 1.0)
	overlay.color = tint
	overlay.visible = active and tint.a > 0.0
