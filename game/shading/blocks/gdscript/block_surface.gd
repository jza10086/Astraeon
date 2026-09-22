class_name AstraeonBlockSurface
extends Resource
## Shared authoring data. Treat as read-only after loading; no per-voxel material.
enum AlphaMode { OPAQUE, CUTOUT, BLEND }

@export_group("Base")
@export var base_color: Color = Color.WHITE
@export var albedo_texture: Texture2D
@export var normal_texture: Texture2D
@export_range(0.0, 8.0) var normal_strength: float = 1.0
@export_group("Surface")
@export_range(0.0, 1.0) var roughness: float = 1.0
@export_range(0.0, 1.0) var metallic: float = 0.0
@export_range(0.0, 1.0) var specular: float = 0.5
## Linear data: R=material AO, G=roughness multiplier, B=metallic multiplier.
@export var orm_texture: Texture2D
@export_group("Transparency")
@export var alpha_mode: AlphaMode = AlphaMode.OPAQUE
@export_range(0.0, 1.0) var alpha_cutoff: float = 0.5
@export var double_sided: bool = false
@export_group("Emission")
@export var emission_color: Color = Color.WHITE
@export_range(0.0, 64.0, 0.01, "or_greater") var emission_energy: float = 0.0
@export var emission_texture: Texture2D

## No surrounding illumination is inferred from this result.
func emission_rgb(texture_rgb: Vector3 = Vector3.ONE, instance_multiplier: float = 1.0) -> Vector3:
	return texture_rgb * Vector3(emission_color.r, emission_color.g, emission_color.b) * emission_energy * maxf(instance_multiplier, 0.0)

func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	for field: StringName in [&"roughness", &"metallic", &"specular", &"alpha_cutoff"]:
		var value: float = float(get(field))
		if not is_finite(value) or value < 0.0 or value > 1.0:
			errors.append("%s must be finite and within [0, 1]" % field)
	for field: StringName in [&"normal_strength", &"emission_energy"]:
		var value: float = float(get(field))
		if not is_finite(value) or value < 0.0:
			errors.append("%s must be finite and nonnegative" % field)
	for field: StringName in [&"base_color", &"emission_color"]:
		var value: Color = get(field)
		for channel: float in [value.r, value.g, value.b, value.a]:
			if not is_finite(channel) or channel < 0.0 or channel > 1.0:
				errors.append("%s must use ordinary [0, 1] color channels" % field)
				break
	if alpha_mode < AlphaMode.OPAQUE or alpha_mode > AlphaMode.BLEND:
		errors.append("Unsupported alpha_mode")
	return errors
