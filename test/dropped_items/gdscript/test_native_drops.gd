extends SceneTree
var checks: int = 0
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
func fresh() -> RefCounted:
	var pool: RefCounted = ClassDB.instantiate("AstraeonDroppedItems")
	pool.call("configure", PackedStringArray(["astraeon:dirt_item", "astraeon:sword"]), PackedInt32Array([64, 1]), PackedByteArray([0, 1]))
	return pool
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var buffer: VoxelBuffer = VoxelBuffer.new()
	buffer.create(32, 32, 32)
	for x: int in range(32):
		for z: int in range(32):
			buffer.set_voxel(1, x, 4, z)
	var tool: VoxelTool = buffer.get_voxel_tool()
	var pool: RefCounted = fresh()
	var id: int = pool.call("spawn", "astraeon:dirt_item", 40, Vector3(8, 9, 8), Vector3.ZERO, 0.5)
	check(id > 0 and pool.call("get_count") == 1, "Spawn compact record")
	check(pool.call("nearby", Vector3(8,9,8), 2.0, true).is_empty(), "Pickup delay")
	for frame: int in range(180):
		pool.call("step", 1.0/60, Vector3(8,8,8), tool)
	var record: Dictionary = pool.call("nearby", Vector3(8,8,8), 10.0, false)[0]
	check(record.position.y > 5.1 and record.position.y < 5.25 and record.sleeping, "Gravity landing and sleep")
	check(pool.call("nearby", record.position, 1.0, true).size() == 1, "Delay expires")
	check(pool.call("take", id, 12) and pool.call("nearby", record.position, 1.0, true)[0].count == 28, "Partial pickup leaves 28")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(pool.call("snapshot")))
	var restored: RefCounted = fresh()
	check(restored.call("restore", saved) and restored.call("snapshot") == pool.call("snapshot"), "JSON round trip uses stable IDs")
	var before: Dictionary = pool.call("snapshot")
	pool.call("step", 1.0/60, Vector3(1000,8,1000), tool)
	check(pool.call("snapshot") == before, "Distant chunks freeze")
	for x: int in range(7,10):
		for z: int in range(7,10):
			buffer.set_voxel(0, x, 4, z)
	for frame: int in range(20):
		pool.call("step", 1.0/60, Vector3(8,8,8), tool)
	check(pool.call("nearby", Vector3(8,8,8), 10.0, false)[0].position.y < record.position.y - 0.5, "Removing support wakes sleeping item")
	pool = fresh()
	pool.call("spawn", "astraeon:sword", 1, Vector3(-0.5,8,-16.5), Vector3.ZERO, 0.0)
	check(pool.call("snapshot").chunks.has("-1,-2"), "Negative chunk floor division")
	before = pool.call("snapshot")
	pool.call("step", 0.1, Vector3(-0.5,8,-16.5), tool)
	check(pool.call("snapshot") == before, "Unloaded terrain freezes motion")
	pool = fresh()
	pool.call("spawn", "astraeon:dirt_item", 1, Vector3(15.7,10,8), Vector3(5,0,0), 0.0)
	for frame: int in range(30):
		pool.call("step", 1.0/60, Vector3(16,8,8), tool)
	check(pool.call("snapshot").chunks.has("1,0") and not pool.call("snapshot").chunks.has("0,0"), "Crossing chunk moves ownership")
	var invalid: RefCounted = fresh()
	check(invalid.call("spawn", "astraeon:sword", 2, Vector3(8,8,8), Vector3.ZERO, 0.0) == 0 and not String(invalid.call("get_error")).is_empty(), "Invalid spawn reports exact failure")
	check(invalid.call("spawn", "astraeon:sword", 1, Vector3(8,8,8), Vector3.ZERO, 0.0) == 0, "Failed pool does not resume")
	var bad: Dictionary = saved.duplicate(true)
	bad.chunks["0,0"][0].item = "missing:item"
	check(not fresh().call("restore", bad), "Unknown saved item rejected")
	bad = saved.duplicate(true)
	bad.chunks["0,0"][0].count = 4294967297
	check(not fresh().call("restore", bad), "Oversized count cannot wrap into a valid stack")
	bad = saved.duplicate(true)
	bad.chunks["0,0"][0].delay = "0"
	check(not fresh().call("restore", bad), "Non-numeric delay rejected")
	print("DROPPED_NATIVE_TEST ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
