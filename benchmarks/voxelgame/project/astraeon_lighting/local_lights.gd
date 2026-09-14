extends Node3D
## Finite lab emitters, indexed only on edits. Not a production light allocator.
const Volume: Script = preload("res://astraeon_lighting/light_volume.gd")
var emitters: Dictionary[Vector3i, OmniLight3D] = {}
var _volume: Volume
var _material: StandardMaterial3D

func configure(volume: Volume) -> void:
	_volume = volume
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = Color(1.0, 0.72, 0.32)
	_material.emission_enabled = true
	_material.emission = Color(1.0, 0.72, 0.32)
	_material.emission_energy_multiplier = 1.5
	var lamps: Array[Vector3i] = []
	for index: int in range(volume.voxels.size()):
		if volume.voxels[index] == Volume.LAMP:
			lamps.append(volume.position_of(index))
	sync_edits(lamps)

func sync_edits(changed: Array[Vector3i]) -> void:
	for p: Vector3i in changed:
		if _volume.voxel_at(p) == Volume.LAMP:
			if emitters.has(p):
				continue
			var light: OmniLight3D = OmniLight3D.new()
			light.position = Vector3(p) + Vector3.ONE * 0.5
			light.shadow_enabled = true
			light.shadow_bias = 0.05
			light.shadow_normal_bias = 1.0
			add_child(light)
			var surface: MeshInstance3D = MeshInstance3D.new()
			surface.mesh = BoxMesh.new()
			surface.material_override = _material
			surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			light.add_child(surface)
			emitters[p] = light
		elif emitters.has(p):
			emitters[p].queue_free()
			emitters.erase(p)

func apply(settings: AstraeonLightingProfile) -> void:
	for light: OmniLight3D in emitters.values():
		# Energy zero leaves the emissive surface visible when direct light is disabled.
		light.light_energy = settings.local_light_energy if settings.local_lights_enabled else 0.0
		light.light_color = settings.block_color
		light.omni_range = settings.local_light_range
		light.omni_attenuation = 2.0
		light.shadow_blur = 0.0 if settings.hard_shadows else settings.shadow_blur
