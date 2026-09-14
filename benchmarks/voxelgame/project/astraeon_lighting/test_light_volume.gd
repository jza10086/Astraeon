extends SceneTree
## CPU-only correctness tests; does not instantiate the sample or start rendering.
const Volume: Script = preload("res://astraeon_lighting/light_volume.gd")
const Fixtures: Script = preload("res://astraeon_lighting/sample_world.gd")
const Sections: Script = preload("res://astraeon_lighting/section_meshes.gd")
var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _settle(volume: Volume) -> void:
	var passes: int = 0
	while not volume.is_settled() and passes < 10000:
		volume.step(32768, 0)
		passes += 1
	_check(volume.is_settled(), "Solver must converge")

# Independent oracle: reset to zero, seed sources, positive-only flood.
# Unlike incremental relaxation this never carries previous light values.
func _oracle(volume: Volume) -> Array[PackedByteArray]:
	var result: Array[PackedByteArray] = []
	for channel: int in range(2):
		var values: PackedByteArray = PackedByteArray()
		values.resize(volume.voxels.size())
		values.fill(0)
		var queue: Array[int] = []
		if channel == 0:
			for z: int in range(volume.origin.z, volume.origin.z + volume.size.z):
				for x: int in range(volume.origin.x, volume.origin.x + volume.size.x):
					for y: int in range(volume.origin.y + volume.size.y - 1, volume.origin.y - 1, -1):
						var p: Vector3i = Vector3i(x, y, z)
						if volume.voxel_at(p) != Volume.AIR:
							break
						var index: int = volume.index_of(p)
						values[index] = 15
						queue.append(index)
		else:
			for index: int in range(volume.voxels.size()):
				if volume.voxels[index] == Volume.LAMP:
					values[index] = 15
					queue.append(index)
		var head: int = 0
		while head < queue.size():
			var index: int = queue[head]
			head += 1
			var p: Vector3i = volume.position_of(index)
			for direction: Vector3i in Volume.DIRECTIONS:
				var neighbor: Vector3i = p + direction
				if volume.contains(neighbor) and volume.voxel_at(neighbor) == Volume.AIR:
					var ni: int = volume.index_of(neighbor)
					var next: int = int(values[index]) - 1
					if next > values[ni]:
						values[ni] = next
						queue.append(ni)
		result.append(values)
	return result

func _compare(volume: Volume, label: String) -> void:
	_settle(volume)
	var expected: Array[PackedByteArray] = _oracle(volume)
	_check(volume.sky == expected[0], label + ": sky differs from oracle")
	_check(volume.block == expected[1], label + ": block differs from oracle")
	print("LIGHT_CASE ", label)

func _run() -> void:
	var volume: Volume = Volume.new()
	volume.configure(Vector3i(-16, -8, -8), Vector3i(32, 16, 16))
	_compare(volume, "open negative-coordinate volume")
	_check(volume.light_at(Vector3i(-1, -7, -1)).x == 15, "Vertical open sky must not attenuate")
	_check(volume.light_at(Vector3i(16, 0, 0)) == Vector2i.ZERO, "Outside boundary has no light")
	_check(Sections.section_of(Vector3i(-1, -17, 16)) == Vector3i(-1, -2, 1), "Floor section coordinates")
	var edits: Dictionary[Vector3i, int] = {}
	Fixtures.box(edits, AABB(Vector3(-16, -8, -8), Vector3(32, 16, 16)), Volume.STONE)
	Fixtures.box(edits, AABB(Vector3(-15, -7, -7), Vector3(30, 14, 14)), Volume.AIR)
	volume.apply_edits(edits)
	_compare(volume, "seal previously sunlit room")
	_check(volume.light_at(Vector3i.ZERO) == Vector2i.ZERO, "Sealed center must be dark")
	edits = {Vector3i(0, 7, 0): Volume.AIR}
	volume.apply_edits(edits)
	_compare(volume, "open roof")
	_check(volume.light_at(Vector3i.ZERO).x == 15, "Opened shaft receives full sky")
	_check(volume.light_at(Vector3i(1, 0, 0)).x == 14, "Lateral sky loses one level")
	edits = {Vector3i(0, 7, 0): Volume.STONE}
	volume.apply_edits(edits)
	_compare(volume, "close roof")
	edits = {Vector3i(-3, 0, 0): Volume.LAMP, Vector3i(3, 0, 0): Volume.LAMP}
	volume.apply_edits(edits)
	_compare(volume, "overlapping light sources across section boundary")
	_check(volume.light_at(Vector3i.ZERO).y == 12, "Block light distance")
	edits = {Vector3i(-3, 0, 0): Volume.AIR}
	volume.apply_edits(edits)
	_compare(volume, "remove one overlapping source")
	_check(volume.light_at(Vector3i.ZERO).y == 12, "Other source must survive")
	edits = {Vector3i(3, 0, 0): Volume.AIR}
	volume.apply_edits(edits)
	_compare(volume, "remove final source")
	_check(volume.light_at(Vector3i.ZERO).y == 0, "No stale light cycles")
	edits.clear()
	Fixtures.box(edits, AABB(Vector3(-8, 1, -4), Vector3(16, 1, 8)), Volume.LAMP)
	_check(volume.apply_edits(edits).size() == 128, "128 actual changed cells")
	_compare(volume, "128 source placement")
	edits.clear()
	Fixtures.box(edits, AABB(Vector3(-8, 1, -4), Vector3(16, 1, 8)), Volume.AIR)
	volume.apply_edits(edits)
	_compare(volume, "128 source removal")
	# Change topology and source again before the previous work has settled.
	edits = {Vector3i(0, 7, 0): Volume.AIR, Vector3i(0, 0, 0): Volume.LAMP}
	volume.apply_edits(edits)
	volume.step(1, 0)
	_check(not volume.is_settled(), "Partial work must not publish")
	edits = {Vector3i(0, 7, 0): Volume.STONE, Vector3i(0, 0, 0): Volume.STONE, Vector3i(-1, 0, 0): Volume.LAMP}
	volume.apply_edits(edits)
	_compare(volume, "edits during unfinished propagation")
	_check(volume.settled_revision == volume.revision, "Only latest revision settles")
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 20260914
	for batch: int in range(4):
		edits.clear()
		for i: int in range(40):
			edits[Vector3i(random.randi_range(-14, 13), random.randi_range(-6, 6), random.randi_range(-6, 6))] = random.randi_range(0, 2)
		volume.apply_edits(edits)
		_compare(volume, "random topology batch %d" % batch)
	var images: Array[Image] = volume.make_images()
	var p: Vector3i = Vector3i(-1, 0, 0)
	var q: Vector3i = p - volume.origin
	var sampled: Color = images[q.z].get_pixel(q.x, q.y)
	var light: Vector2i = volume.light_at(p)
	_check(is_equal_approx(sampled.r, float(light.x) / 15.0), "RG adapter sky axis/channel")
	_check(is_equal_approx(sampled.g, float(light.y) / 15.0), "RG adapter block axis/channel")
	var before: int = volume.revision
	var no_change: Dictionary[Vector3i, int] = {p: volume.voxel_at(p)}
	_check(volume.apply_edits(no_change).is_empty() and volume.revision == before, "No-op does not schedule work")
	var full: Volume = Fixtures.create()
	_compare(full, "complete 64-cube fixture")
	_check(full.light_at(Vector3i(-10, -4, 0)).x == 0, "Deep underground gallery stays dark")
	print("LIGHT_VOLUME ", "PASS" if _failures == 0 else "FAIL", " checks=", _checks, " failures=", _failures)
	quit(0 if _failures == 0 else 1)
