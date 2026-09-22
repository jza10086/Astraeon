extends Node3D
## Fixed collision fixtures; deliberately independent of experimental world generation.

func _ready() -> void:
	_box("Platform", Vector3(2.0, 0.5, 0.0), Vector3(2.0, 1.0, 2.0), Color(0.5, 0.4, 0.25))
	_box("Wall", Vector3(-3.0, 1.5, 0.0), Vector3(0.5, 3.0, 4.0), Color(0.35, 0.4, 0.5))
	_box("LowCeiling", Vector3(0.0, 2.15, -3.5), Vector3(2.0, 0.3, 2.0), Color(0.55, 0.35, 0.3))
	var ramp: StaticBody3D = _box("Ramp", Vector3(3.7, 0.40, -3.0), Vector3(1.5, 0.25, 3.0), Color(0.35, 0.45, 0.55))
	ramp.rotation.x = deg_to_rad(20.0)

func _box(node_name: String, center: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name
	body.position = center
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	var display: MeshInstance3D = MeshInstance3D.new()
	display.mesh = mesh
	body.add_child(display)
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	return body
