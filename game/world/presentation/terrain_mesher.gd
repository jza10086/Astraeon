class_name AstraeonTerrainMesher
extends RefCounted
## Shared exposed-face mesher. Water is an opaque blue fixture without collision.
const SECTION: Script = preload("res://game/world/blocks/block_section.gd")
const DIRECTIONS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const CORNERS: Array[Vector3] = [Vector3(1,0,0), Vector3(1,1,0), Vector3(1,1,1), Vector3(1,0,1), Vector3(0,0,1), Vector3(0,1,1), Vector3(0,1,0), Vector3(0,0,0), Vector3(0,1,1), Vector3(1,1,1), Vector3(1,1,0), Vector3(0,1,0), Vector3(0,0,0), Vector3(1,0,0), Vector3(1,0,1), Vector3(0,0,1), Vector3(1,0,1), Vector3(1,1,1), Vector3(0,1,1), Vector3(0,0,1), Vector3(0,0,0), Vector3(0,1,0), Vector3(1,1,0), Vector3(1,0,0)]
const TRIANGLE: Array[int] = [0, 2, 1, 0, 3, 2]
const COLORS: Array[Color] = [Color.TRANSPARENT, Color(0.48,0.49,0.51), Color(0.43,0.29,0.17), Color(0.28,0.58,0.2), Color(0.83,0.74,0.45), Color(0.12,0.36,0.72)]

static func build(coordinate: Vector3i, snapshots: Dictionary, ids: PackedInt32Array, state_count: int, backend: int) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var sections: Dictionary[Vector3i, AstraeonBlockSection] = {}
	for key: Vector3i in snapshots:
		var section: AstraeonBlockSection = SECTION.new()
		if not section.configure(key, state_count, backend) or not section.import_states(snapshots[key]):
			return {"error": "Mesh snapshot rejected"}
		sections[key] = section
	var imported: int = Time.get_ticks_usec()
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var collision: PackedVector3Array = PackedVector3Array()
	var center: AstraeonBlockSection = sections[coordinate]
	for z: int in range(16):
		for y: int in range(16):
			for x: int in range(16):
				var local: Vector3i = Vector3i(x, y, z)
				var state: int = center.get_state(local)
				if state == ids[0]:
					continue
				for face: int in range(6):
					var neighbor: Vector3i = local + DIRECTIONS[face]
					var neighbor_coordinate: Vector3i = coordinate + SECTION.section_of(neighbor)
					# Missing neighbors stay hidden until loaded; one-section halo provides boundaries.
					if not sections.has(neighbor_coordinate):
						continue
					var other: int = sections[neighbor_coordinate].get_state(SECTION.world_to_local(neighbor))
					if other != ids[0] and not (other == ids[5] and state != ids[5]):
						continue
					for corner: int in TRIANGLE:
						var vertex: Vector3 = Vector3(local) + CORNERS[face * 4 + corner]
						vertices.append(vertex)
						normals.append(Vector3(DIRECTIONS[face]))
						colors.append(COLORS[maxi(0, ids.find(state))])
						if state != ids[5]:
							collision.append(vertex)
	return {"vertices": vertices, "normals": normals, "colors": colors, "collision": collision, "mesh_import_us": imported - started, "mesh_build_us": Time.get_ticks_usec() - imported, "triangles": vertices.size() / 3, "collision_triangles": collision.size() / 3}
