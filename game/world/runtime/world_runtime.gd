class_name AstraeonWorldRuntime
extends Node3D
## Main-thread owner. Bounded in-flight work; saved revisions gate eviction.
signal task_record(record: Dictionary)
signal section_visible(coordinate: Vector3i, request_to_visible_us: int)
const WORKER: Script = preload("res://game/world/runtime/world_worker.gd")
const STORE: Script = preload("res://game/world/persistence/world_store.gd")
const MESHER: Script = preload("res://game/world/presentation/terrain_mesher.gd")
const SECTION: Script = preload("res://game/world/blocks/block_section.gd")
var horizontal_distance: int = 64
var vertical_distance: int = 32
var commit_budget_us: int = 2000
var resident_limit: int = 4096
var autosave_seconds: float = 30.0
var sections: Dictionary[Vector3i, AstraeonBlockSection] = {}
var failed: String = ""
var accepting: bool = true
var store: AstraeonWorldStore
var config: AstraeonWorldConfig
var _workers: Array[AstraeonWorldWorker] = []
var _desired: Dictionary[Vector3i, bool] = {}
var _visible: Dictionary[Vector3i, bool] = {}
var _requested: Dictionary[Vector3i, int] = {}
var _saved: Dictionary[Vector3i, int] = {}
var _mesh_revision: Dictionary[Vector3i, int] = {}
var _mesh_epoch: Dictionary[Vector3i, int] = {}
var _nodes: Dictionary[Vector3i, Node3D] = {}
var _center: Vector3i = Vector3i(2147483647, 0, 0)
var _generation: int = 0
var _tokens: Dictionary[Vector3i, int] = {}
var _mesh_requested: Dictionary[Vector3i, int] = {}
var _last_save_us: int = 0
var _material: StandardMaterial3D

func configure(settings: AstraeonWorldConfig, registry: AstraeonBlockRegistry, ids: PackedInt32Array, path: String, backend: int, encoding: int, organization: int, worker_count: int = 2) -> String:
	if horizontal_distance < 16 or horizontal_distance % 16 != 0 or vertical_distance < 16 or vertical_distance % 16 != 0:
		return "Loading distances must be positive multiples of 16"
	config = settings.duplicate() as AstraeonWorldConfig
	store = STORE.new()
	var error: String = store.configure(path, config.snapshot(), registry, organization, encoding)
	if not error.is_empty():
		return error
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	for index: int in range(clampi(worker_count, 1, 8)):
		var worker: AstraeonWorldWorker = WORKER.new()
		worker.store = store
		worker.ids = ids.duplicate()
		worker.backend = backend
		worker.state_count = registry.state_count()
		if not worker.generator.configure(config, ids):
			return "Invalid generator configuration"
		_workers.append(worker)
	return ""

func set_observer(position: Vector3) -> void:
	var center: Vector3i = SECTION.section_of(Vector3i(floori(position.x), floori(position.y), floori(position.z)))
	if center == _center or not accepting:
		return
	_center = center
	_generation += 1
	var previous: Dictionary[Vector3i, bool] = _desired.duplicate()
	_desired.clear()
	_visible.clear()
	var radius: int = horizontal_distance >> 4
	var height: int = vertical_distance >> 4
	for z: int in range(center.z - radius, center.z + radius + 1):
		for x: int in range(center.x - radius, center.x + radius + 1):
			if (2 * (x - center.x) + 1) ** 2 + (2 * (z - center.z) + 1) ** 2 > (2 * radius) ** 2:
				continue
			for y: int in range(maxi(config.min_y >> 4, center.y - height), mini(config.max_y >> 4, center.y + height + 1)):
				var coordinate: Vector3i = Vector3i(x, y, z)
				_visible[coordinate] = true
				_desired[coordinate] = true
				for direction: Vector3i in MESHER.DIRECTIONS:
					_desired[coordinate + direction] = true
	for coordinate: Vector3i in _desired:
		if not previous.has(coordinate):
			_requested[coordinate] = Time.get_ticks_usec()
			_tokens[coordinate] = _generation
	for coordinate: Vector3i in previous:
		if not _desired.has(coordinate):
			_tokens.erase(coordinate)
			if not sections.has(coordinate):
				_requested.erase(coordinate)
	for coordinate: Vector3i in _nodes.keys():
		if not _visible.has(coordinate):
			_nodes[coordinate].queue_free()
			_nodes.erase(coordinate)
			_mesh_revision.erase(coordinate)

func edit(world_position: Vector3i, state: int) -> bool:
	var coordinate: Vector3i = SECTION.section_of(world_position)
	if not sections.has(coordinate):
		return false
	var before: int = sections[coordinate].revision()
	if not sections[coordinate].set_state(SECTION.world_to_local(world_position), state):
		return false
	if sections[coordinate].revision() != before:
		_invalidate(coordinate)
	return true

func _invalidate(coordinate: Vector3i) -> void:
	var affected: Array[Vector3i] = [coordinate]
	for direction: Vector3i in MESHER.DIRECTIONS:
		affected.append(coordinate + direction)
	for key: Vector3i in affected:
		_mesh_epoch[key] = int(_mesh_epoch.get(key, 0)) + 1
		_mesh_revision.erase(key)
		_mesh_requested[key] = Time.get_ticks_usec()

func dirty_count() -> int:
	var count: int = 0
	for coordinate: Vector3i in sections:
		if int(_saved.get(coordinate, -1)) != sections[coordinate].revision():
			count += 1
	return count

func pending_count() -> int:
	var count: int = 0
	for worker: AstraeonWorldWorker in _workers:
		if worker.task_id != -1:
			count += 1
	return count

func missing_count() -> int:
	var count: int = 0
	for coordinate: Vector3i in _desired:
		if not sections.has(coordinate):
			count += 1
	return count

func visible_missing_count() -> int:
	var count: int = 0
	for coordinate: Vector3i in _visible:
		if not _mesh_revision.has(coordinate):
			count += 1
	return count

func flush_saves() -> void:
	_last_save_us = -1000000000000

func stop_requests() -> void:
	accepting = false
	flush_saves()

func _busy(kind: String, coordinate: Vector3i) -> bool:
	for worker: AstraeonWorldWorker in _workers:
		if worker.task_id != -1 and worker.job.kind == kind and worker.job.coordinate == coordinate:
			return true
	return false

func _process(_delta: float) -> void:
	if not failed.is_empty():
		return
	var frame_start: int = Time.get_ticks_usec()
	for worker: AstraeonWorldWorker in _workers:
		if worker.task_id != -1 and WorkerThreadPool.is_task_completed(worker.task_id):
			WorkerThreadPool.wait_for_task_completion(worker.task_id)
			_accept(worker)
			worker.task_id = -1
			worker.job = {}
			worker.result = {}
			if Time.get_ticks_usec() - frame_start >= commit_budget_us:
				break
	if not failed.is_empty():
		return
	for coordinate: Vector3i in sections.keys():
		if not _desired.has(coordinate) and int(_saved.get(coordinate, -1)) == sections[coordinate].revision() and not _busy("mesh", coordinate) and not _busy("save", coordinate):
			sections.erase(coordinate)
			_saved.erase(coordinate)
			_mesh_revision.erase(coordinate)
			_requested.erase(coordinate)
	for coordinate: Vector3i in _mesh_epoch.keys():
		if not _desired.has(coordinate) and not sections.has(coordinate) and not _busy("mesh", coordinate):
			_mesh_epoch.erase(coordinate)
			_mesh_requested.erase(coordinate)
	var save_due: bool = Time.get_ticks_usec() - _last_save_us >= int(autosave_seconds * 1000000.0)
	for worker: AstraeonWorldWorker in _workers:
		if worker.task_id == -1:
			var job: Dictionary = _next_job(save_due)
			if not job.is_empty():
				worker.job = job
				worker.task_id = WorkerThreadPool.add_task(worker.execute)
	if save_due and dirty_count() == 0:
		_last_save_us = Time.get_ticks_usec()

func _next_job(save_due: bool) -> Dictionary:
	# Saves receive priority when due or evicting; initial generation also persists immediately.
	for coordinate: Vector3i in sections:
		var revision: int = sections[coordinate].revision()
		if int(_saved.get(coordinate, -1)) != revision and (save_due or not _desired.has(coordinate) or int(_saved.get(coordinate, -1)) == -1) and not _busy("save", coordinate):
			var started: int = Time.get_ticks_usec()
			var states: PackedInt32Array = sections[coordinate].export_states()
			return {"kind": "save", "coordinate": coordinate, "revision": revision, "states": states, "snapshot_us": Time.get_ticks_usec() - started, "queued_us": started}
	if not accepting:
		return {}
	var coordinates: Array[Vector3i] = _desired.keys()
	coordinates.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return (a - _center).length_squared() < (b - _center).length_squared())
	# Ready meshes precede further reads so continuous movement cannot starve rendering.
	for coordinate: Vector3i in coordinates:
		if not _visible.has(coordinate):
			continue
		if not sections.has(coordinate) or _mesh_revision.has(coordinate) or _busy("mesh", coordinate):
			continue
		var neighbors: Array[Vector3i] = [coordinate]
		var ready: bool = true
		for direction: Vector3i in MESHER.DIRECTIONS:
			neighbors.append(coordinate + direction)
		for neighbor: Vector3i in neighbors:
			if not sections.has(neighbor):
				ready = false
		if not ready:
			continue
		var started: int = Time.get_ticks_usec()
		var snapshots: Dictionary = {}
		for neighbor: Vector3i in neighbors:
			snapshots[neighbor] = sections[neighbor].export_states()
		return {"kind": "mesh", "coordinate": coordinate, "revision": sections[coordinate].revision(), "epoch": _mesh_epoch.get(coordinate, 0), "snapshots": snapshots, "snapshot_us": Time.get_ticks_usec() - started, "queued_us": _mesh_requested.get(coordinate, started)}
	for coordinate: Vector3i in coordinates:
		if not sections.has(coordinate) and not _busy("load", coordinate) and sections.size() + pending_count() < resident_limit:
			return {"kind": "load", "coordinate": coordinate, "generation": _tokens[coordinate], "queued_us": _requested[coordinate]}
	return {}

func _accept(worker: AstraeonWorldWorker) -> void:
	var result: Dictionary = worker.result
	var job: Dictionary = worker.job
	var coordinate: Vector3i = job.coordinate
	var record: Dictionary = job.duplicate()
	record.erase("states")
	record.erase("snapshots")
	for key: String in result:
		if key not in ["section", "vertices", "normals", "colors", "collision"]:
			record[key] = result[key]
	record["queue_wait_us"] = int(result.worker_started_us) - int(job.queued_us)
	record["resident_sections"] = sections.size()
	record["dirty_sections"] = dirty_count()
	if result.has("error"):
		failed = str(result.error)
		task_record.emit(record)
		return
	var started: int = Time.get_ticks_usec()
	match job.kind:
		"load":
			if not _desired.has(coordinate) or int(job.generation) != int(_tokens.get(coordinate, -1)):
				record["discarded"] = true
			else:
				sections[coordinate] = result.section
				_saved[coordinate] = -1 if result.get("generated", false) else sections[coordinate].revision()
				_invalidate(coordinate)
		"save":
			_saved[coordinate] = job.revision
		"mesh":
			if not _visible.has(coordinate) or not sections.has(coordinate) or int(job.epoch) != int(_mesh_epoch.get(coordinate, 0)) or job.revision != sections[coordinate].revision():
				record["discarded"] = true
			else:
				if _nodes.has(coordinate):
					_nodes[coordinate].queue_free()
				var node: Node3D = Node3D.new()
				node.position = Vector3(coordinate * 16)
				if not result.vertices.is_empty():
					var arrays: Array = []
					arrays.resize(Mesh.ARRAY_MAX)
					arrays[Mesh.ARRAY_VERTEX] = result.vertices
					arrays[Mesh.ARRAY_NORMAL] = result.normals
					arrays[Mesh.ARRAY_COLOR] = result.colors
					var mesh: ArrayMesh = ArrayMesh.new()
					mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
					var visual: MeshInstance3D = MeshInstance3D.new()
					visual.mesh = mesh
					visual.material_override = _material
					node.add_child(visual)
				var collision_started: int = Time.get_ticks_usec()
				if not result.collision.is_empty():
					var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
					shape.set_faces(result.collision)
					var body: StaticBody3D = StaticBody3D.new()
					var collider: CollisionShape3D = CollisionShape3D.new()
					collider.shape = shape
					body.add_child(collider)
					node.add_child(body)
				add_child(node)
				record["collision_commit_us"] = Time.get_ticks_usec() - collision_started
				_nodes[coordinate] = node
				_mesh_revision[coordinate] = job.revision
				var latency: int = Time.get_ticks_usec() - int(_requested.get(coordinate, started))
				record["request_to_visible_us"] = latency
				section_visible.emit(coordinate, latency)
	record["main_commit_us"] = Time.get_ticks_usec() - started
	task_record.emit(record)

func _exit_tree() -> void:
	for worker: AstraeonWorldWorker in _workers:
		if worker.task_id != -1:
			WorkerThreadPool.wait_for_task_completion(worker.task_id)

