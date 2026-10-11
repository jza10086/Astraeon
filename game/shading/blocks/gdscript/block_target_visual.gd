extends MeshInstance3D
## One reusable, depth-tested selection box. No per-voxel materials or terrain rebuilds.
@export var outline_color: Color = Color.BLACK
@export_range(0.5, 5.0) var width_pixels: float = 2.0

func _ready() -> void:
	name = "BlockTargetOutline"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	layers = 1
	extra_cull_margin = 0.01
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = preload("res://game/shading/blocks/shaders/block_target.gdshader")
	material.set_shader_parameter("outline_color", outline_color)
	material.set_shader_parameter("width_pixels", width_pixels)
	material_override = material
	mesh = _create_box()
	hide()

## The supplied cell comes from the authoritative world interaction raycast.
func show_cell(cell: Vector3i) -> void:
	global_position = Vector3(cell)
	show()

func _create_box() -> ArrayMesh:
	var vertices: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var indices: PackedInt32Array = []
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	for normal: Vector3 in axes:
		var tangent: Vector3 = Vector3.RIGHT if absf(normal.y) > 0.5 else Vector3.UP.cross(normal)
		var bitangent: Vector3 = normal.cross(tangent)
		var center: Vector3 = Vector3.ONE * 0.5 + normal * 0.502
		var start: int = vertices.size()
		for uv: Vector2 in [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]:
			vertices.append(center + tangent * (uv.x - 0.5) * 1.004 + bitangent * (uv.y - 0.5) * 1.004)
			uvs.append(uv)
		for index: int in [0, 2, 1, 0, 3, 2]:
			indices.append(start + index)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result: ArrayMesh = ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result
