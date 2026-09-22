class_name AstraeonBlockAppearance
extends Resource
## Shared appearance, without world position or instance state.
enum Face { TOP, BOTTOM, FRONT, BACK, LEFT, RIGHT }
const NORMALS: Array[Vector3] = [Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]
## UV u/v tangents in authored coordinates. u cross v = outward normal.
const U_AXES: Array[Vector3] = [Vector3.RIGHT, Vector3.RIGHT, Vector3.LEFT, Vector3.RIGHT, Vector3.BACK, Vector3.FORWARD]
const V_AXES: Array[Vector3] = [Vector3.FORWARD, Vector3.BACK, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]
@export var default_surface: AstraeonBlockSurface
## Sparse face dictionaries. Missing entries use the defaults, never legacy formats.
@export var face_surfaces: Dictionary[int, AstraeonBlockSurface] = {}
@export var face_uv_rotations: Dictionary[int, int] = {}
## Vector2i components must be 0 or 1.
@export var face_uv_mirrors: Dictionary[int, Vector2i] = {}
@export var authoring_orientation: Basis = Basis.IDENTITY
@export var light: AstraeonBlockLightAppearance

func surface_for_face(face: Face) -> AstraeonBlockSurface:
	return face_surfaces.get(face, default_surface)

## Rotation only: reject reflection, scaling, shear and non-axis-aligned bases.
static func is_cube_rotation(value: Basis) -> bool:
	if not value.is_finite() or not is_equal_approx(value.determinant(), 1.0):
		return false
	if not (value.transposed() * value).is_equal_approx(Basis.IDENTITY):
		return false
	for axis: Vector3 in [value.x, value.y, value.z]:
		if not axis.is_equal_approx(axis.round()):
			return false
	return true

func combined_orientation(instance_orientation: Basis = Basis.IDENTITY) -> Basis:
	assert(is_cube_rotation(authoring_orientation) and is_cube_rotation(instance_orientation), "Invalid block orientation")
	return instance_orientation * authoring_orientation

## Returns the authored face that now points in a specified world direction.
func authored_face_for_world(world_face: Face, instance_orientation: Basis = Basis.IDENTITY) -> Face:
	var local_normal: Vector3 = combined_orientation(instance_orientation).transposed() * NORMALS[world_face]
	for face: int in range(6):
		if local_normal.is_equal_approx(NORMALS[face]):
			return face as Face
	assert(false, "Invalid face transform")
	return Face.TOP

## Mirrors first, then positive quarter turns in UV coordinates, about the center.
func transform_uv(face: Face, uv: Vector2) -> Vector2:
	var mirrors: Vector2i = face_uv_mirrors.get(face, Vector2i.ZERO)
	var result: Vector2 = uv
	if mirrors.x == 1:
		result.x = 1.0 - result.x
	if mirrors.y == 1:
		result.y = 1.0 - result.y
	var turns: int = int(face_uv_rotations.get(face, 0)) / 90
	for turn: int in range(turns):
		result = Vector2(1.0 - result.y, result.x)
	return result

## Converts a decoded normal-map vector to world space, including UV mirrors.
## Columns are dPosition/dTextureU, dPosition/dTextureV, and outward normal.
func face_tangent_basis(face: Face, instance_orientation: Basis = Basis.IDENTITY) -> Basis:
	var origin: Vector2 = transform_uv(face, Vector2.ZERO)
	var du: Vector2 = transform_uv(face, Vector2.RIGHT) - origin
	var dv: Vector2 = transform_uv(face, Vector2.DOWN) - origin
	var tangent: Vector3 = U_AXES[face] * du.x + V_AXES[face] * dv.x
	var bitangent: Vector3 = U_AXES[face] * du.y + V_AXES[face] * dv.y
	return combined_orientation(instance_orientation) * Basis(tangent, bitangent, NORMALS[face])

func light_offset(instance_orientation: Basis = Basis.IDENTITY) -> Vector3:
	return combined_orientation(instance_orientation) * light.local_offset if light != null else Vector3.ZERO

func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if default_surface == null:
		errors.append("default_surface is required")
	else:
		for error: String in default_surface.validate():
			errors.append("default_surface: " + error)
	for face: int in face_surfaces:
		if face < 0 or face > 5 or face_surfaces[face] == null:
			errors.append("face_surfaces requires a valid face and non-null surface")
		else:
			for error: String in face_surfaces[face].validate():
				errors.append("face %d: %s" % [face, error])
	for face: int in face_uv_rotations:
		if face < 0 or face > 5 or face_uv_rotations[face] not in [0, 90, 180, 270]:
			errors.append("face_uv_rotations requires valid faces and quarter turns")
	for face: int in face_uv_mirrors:
		var mirror: Vector2i = face_uv_mirrors[face]
		if face < 0 or face > 5 or mirror.x not in [0, 1] or mirror.y not in [0, 1]:
			errors.append("face_uv_mirrors requires valid faces and binary components")
	if not is_cube_rotation(authoring_orientation):
		errors.append("authoring_orientation must be a proper cube rotation")
	if light != null:
		for error: String in light.validate():
			errors.append("light: " + error)
	return errors
