extends Node3D
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
## Transform-driven real point source. No voxel-light injection or inventory coupling.
@export var color: Color = Color(1.0, 0.74, 0.4)
@export_range(0.0, 16.0) var energy: float = 4.0
@export_range(1.0, 32.0) var radius: float = 12.0
@export var request_shadows: bool = true
@export var priority: int = 10
var light: OmniLight3D = OmniLight3D.new()
func _ready() -> void:
	add_child(light)
	light.shadow_bias = 0.05
	light.shadow_normal_bias = 1.0
func apply(p: Profile) -> void:
	color = p.moving_color
	energy = p.moving_energy if p.moving_mode != 0 else 0.0
	radius = p.moving_range
	request_shadows = p.moving_shadows
	priority = p.moving_priority
	light.light_color = color
	light.omni_range = radius
	light.omni_attenuation = p.moving_attenuation
	light.shadow_blur = 0.0 if p.hard_shadows else p.shadow_blur
	light.light_volumetric_fog_energy = p.moving_volume_energy if p.rays_mode == 2 else 0.0
