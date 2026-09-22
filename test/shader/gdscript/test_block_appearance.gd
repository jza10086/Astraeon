extends SceneTree
const Appearance: Script = preload("res://game/shading/blocks/gdscript/block_appearance.gd")
const Surface: Script = preload("res://game/shading/blocks/gdscript/block_surface.gd")
const Light: Script = preload("res://game/shading/blocks/gdscript/block_light_appearance.gd")
var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var appearance: AstraeonBlockAppearance = load("res://game/shading/blocks/resources/log.tres")
	check(appearance != null and appearance.validate().is_empty(), "Load and validate log")
	var original: Color = appearance.default_surface.base_color
	var rotations: int = 0
	var bases: Array[Basis] = []
	for x: int in range(4):
		for y: int in range(4):
			for z: int in range(4):
				var candidate: Basis = Basis.from_euler(Vector3(x, y, z) * PI / 2.0)
				var found: bool = false
				for existing: Basis in bases:
					found = found or existing.is_equal_approx(candidate)
				if not found:
					bases.append(candidate)
	for basis: Basis in bases:
		check(Appearance.is_cube_rotation(basis), "Accept cube rotation")
		rotations += 1
		for face: int in range(6):
			var source: int = appearance.authored_face_for_world(face, basis)
			check((basis * Appearance.NORMALS[source]).is_equal_approx(Appearance.NORMALS[face]), "Face mapping")
			check(appearance.surface_for_face(source) != null, "Face fallback")
	check(rotations == 24, "All rotations covered")
	var modified: AstraeonBlockAppearance = appearance.duplicate(true)
	for degrees: int in [0, 90, 180, 270]:
		for mx: int in [0, 1]:
			for my: int in [0, 1]:
				modified.face_uv_rotations[2] = degrees
				modified.face_uv_mirrors[2] = Vector2i(mx, my)
				var frame: Basis = modified.face_tangent_basis(2)
				var uv0: Vector2 = modified.transform_uv(2, Vector2.ZERO)
				var du: Vector2 = modified.transform_uv(2, Vector2.RIGHT) - uv0
				var dv: Vector2 = modified.transform_uv(2, Vector2.DOWN) - uv0
				check((frame.x * du.x + frame.y * du.y).is_equal_approx(Appearance.U_AXES[2]), "UV inverse tangent")
				check((frame.x * dv.x + frame.y * dv.y).is_equal_approx(Appearance.V_AXES[2]), "UV inverse bitangent")
	check(appearance.face_uv_rotations.is_empty(), "Original mappings remain unchanged")
	check(appearance.default_surface.base_color == original, "Shared surface remains unchanged")
	var lamp: AstraeonBlockAppearance = load("res://game/shading/blocks/resources/lamp.tres")
	check(lamp.validate().is_empty(), "Lamp validates")
	var energy: float = lamp.light.energy
	check(lamp.default_surface.emission_rgb(Vector3.ONE, 0.0) == Vector3.ZERO, "Instance emission off")
	check(lamp.light.energy == energy, "Surface emission does not change illumination")
	modified.light = Light.new()
	modified.light.local_offset = Vector3(0.25, 0.5, 0.0)
	modified.authoring_orientation = Basis(Vector3.UP, PI / 2.0)
	var instance: Basis = Basis(Vector3.RIGHT, PI / 2.0)
	check(modified.light_offset(instance).is_equal_approx(instance * modified.authoring_orientation * modified.light.local_offset), "Offset transform order")
	modified.authoring_orientation = Basis.from_scale(Vector3(-1, 1, 1))
	check(not modified.validate().is_empty(), "Reject reflection")
	modified.authoring_orientation = Basis(Vector3.UP, 0.2)
	check(not modified.validate().is_empty(), "Reject arbitrary rotation")
	var surface: AstraeonBlockSurface = Surface.new()
	surface.roughness = NAN
	check(not surface.validate().is_empty(), "Reject nonfinite fields")
	var light: AstraeonBlockLightAppearance = Light.new()
	light.energy = 1.0
	light.range = 0.0
	check(not light.validate().is_empty(), "Reject enabled zero range")
	var catalog: AstraeonBlockCatalog = load("res://game/data/block/resources/example_catalog.tres")
	check(catalog.definitions[2].appearance == lamp, "Catalog shares cached appearance")
	DirAccess.make_dir_recursive_absolute("res://tmp/block-appearance")
	var path: String = "res://tmp/block-appearance/roundtrip.tres"
	check(ResourceSaver.save(lamp, path) == OK, "Save resource")
	var restored: AstraeonBlockAppearance = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(restored != null and restored.validate().is_empty(), "Load saved resource")
	check(restored.light.energy == lamp.light.energy and restored.default_surface.emission_energy == lamp.default_surface.emission_energy, "Preserve independent energies")
	print("BLOCK_APPEARANCE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
