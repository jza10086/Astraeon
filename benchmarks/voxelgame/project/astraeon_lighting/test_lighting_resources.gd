extends SceneTree
## Resource/component contract checks only; never starts the sample scene.
const Volume: Script = preload("res://astraeon_lighting/light_volume.gd")
const Sections: Script = preload("res://astraeon_lighting/section_meshes.gd")
var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _run() -> void:
	var scene: PackedScene = load("res://astraeon_lighting/lighting_sample.tscn") as PackedScene
	_check(scene != null and scene.can_instantiate(), "Sample scene resource must load")
	var defaults: AstraeonLightingProfile = load("res://astraeon_lighting/default_profile.tres") as AstraeonLightingProfile
	var runtime: AstraeonLightingProfile = defaults.duplicate(true) as AstraeonLightingProfile
	runtime.hour = 0.0
	_check(defaults.hour == 12.0, "Runtime settings must not mutate defaults")
	var volume: Volume = Volume.new()
	volume.configure(Vector3i(-16, 0, 0), Vector3i(32, 16, 16))
	var edits: Dictionary[Vector3i, int] = {Vector3i(-1, 1, 1): Volume.STONE}
	volume.apply_edits(edits)
	while not volume.is_settled():
		volume.step(32768, 0)
	var texture: ImageTexture3D = ImageTexture3D.new()
	var images: Array[Image] = volume.make_images()
	_check(texture.create(Image.FORMAT_RGBA8, 32, 16, 16, false, images) == OK, "Texture resource creation")
	var parent: Node3D = Node3D.new() # Unattached, no gameplay or camera.
	var sections: Sections = Sections.new()
	sections.configure(volume, parent, texture)
	while sections.pending_count() > 0:
		sections.step()
	var occupied: int = 0
	for child: Node in parent.get_children():
		var instance: MeshInstance3D = child as MeshInstance3D
		if instance.mesh != null:
			occupied += 1
			var bounds: AABB = instance.mesh.get_aabb()
			_check(bounds.position.is_equal_approx(Vector3(15, 1, 1)), "Native mesher padding origin")
			_check(bounds.size.is_equal_approx(Vector3.ONE), "Single voxel mesh extent")
			_check(instance.position == Vector3(-16, 0, 0), "Negative section transform")
			_check(instance.mesh.surface_get_material(0) is ShaderMaterial, "Dedicated light shader bound")
			var uv: PackedVector2Array = instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
			var maximum_uv: float = 0.0
			for value: Vector2 in uv:
				maximum_uv = maxf(maximum_uv, value.x)
			_check(maximum_uv > 0.9, "Procedural material requires full-range UVs")
	_check(occupied == 1, "Only occupied section has geometry")
	var rebuild_count: int = sections.rebuilt_sections
	# Display changes stay on materials and never dirty geometry or solver.
	var revision: int = volume.revision
	for material: ShaderMaterial in sections.materials:
		material.set_shader_parameter("sky_color", Color(0.02, 0.03, 0.05))
	_check(sections.pending_count() == 0 and sections.rebuilt_sections == rebuild_count, "Light-only material update has no remesh")
	_check(volume.revision == revision and volume.is_settled(), "Time/color update has no propagation")
	edits = {Vector3i(0, 1, 1): Volume.LAMP}
	var changed: Array[Vector3i] = volume.apply_edits(edits)
	sections.invalidate(changed)
	_check(sections.pending_count() == 2, "Boundary edit invalidates both section meshes")
	while sections.pending_count() > 0:
		sections.step()
	edits = {Vector3i(-1, 1, 1): Volume.AIR, Vector3i(0, 1, 1): Volume.AIR}
	sections.invalidate(volume.apply_edits(edits))
	while sections.pending_count() > 0:
		sections.step()
	for child: Node in parent.get_children():
		var instance: MeshInstance3D = child as MeshInstance3D
		_check(instance.mesh == null, "Removal clears old mesh")
	parent.free()
	print("LIGHT_RESOURCES ", "PASS" if _failures == 0 else "FAIL", " failures=", _failures)
	quit(0 if _failures == 0 else 1)
