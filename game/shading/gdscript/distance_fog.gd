extends RefCounted
## Shared main-world/lab distance fog policy. Does not change streaming or camera clipping.
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")

## Rate is inverse transition length in metres; 0 removes distance attenuation.
## Godot uses a smoothstep ramp over camera-to-fragment distance, not a water-only path.
static func apply(environment: Environment, settings: Profile, underwater: bool, air_color: Color) -> void:
	var wet: bool = underwater and settings.water_enabled and settings.underwater_enabled
	var rate: float = maxf(settings.underwater_attenuation_rate, 0.0)
	environment.fog_enabled = (settings.underwater_visibility_enabled and rate > 0.0) if wet else settings.fog_enabled
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = settings.underwater_color if wet else air_color
	environment.fog_light_energy = 0.6 if wet else 1.0
	environment.fog_sky_affect = 1.0 if wet else 0.0
	var begin: float = maxf(settings.underwater_attenuation_start, 0.0) if wet else settings.fog_start
	environment.fog_depth_begin = begin
	environment.fog_depth_end = begin + (1.0 / maxf(rate, 0.000001) if wet else 1.0 / maxf(settings.fog_density, 0.000001))
	environment.fog_depth_curve = 1.0
