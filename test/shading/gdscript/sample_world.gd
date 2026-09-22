extends RefCounted
## Deterministic fixtures; no game saves or streaming ownership.
const Volume: Script = preload("res://test/shading/gdscript/light_volume.gd")
const ORIGIN: Vector3i = Vector3i(-32, -16, -32)
const SIZE: Vector3i = Vector3i(64, 64, 64)
const ROOF: AABB = AABB(Vector3(-8, 8, -8), Vector3(16, 1, 12))
const WINDOW: AABB = AABB(Vector3(-3, 3, 3), Vector3(4, 3, 1))
const LAMP_POSITION: Vector3i = Vector3i(-3, 2, -3)

static func box(edits: Dictionary[Vector3i, int], bounds: AABB, value: int) -> void:
	var start: Vector3i = Vector3i(bounds.position)
	var end: Vector3i = start + Vector3i(bounds.size)
	for z: int in range(start.z, end.z):
		for y: int in range(start.y, end.y):
			for x: int in range(start.x, end.x):
				edits[Vector3i(x, y, z)] = value

static func create() -> Volume:
	var volume: Volume = Volume.new()
	volume.configure(ORIGIN, SIZE)

	_fill(volume, AABB(Vector3(-32, -16, -32), Vector3(64, 17, 64)), Volume.STONE)
	# Main room, sealed unless the window or roof is opened.
	_fill(volume, AABB(Vector3(-8, 1, -8), Vector3(16, 8, 12)), Volume.WOOD)
	_fill(volume, AABB(Vector3(-7, 1, -7), Vector3(14, 7, 10)), Volume.AIR)
	_fill(volume, WINDOW, Volume.AIR)
	# Sealed underground gallery across x=0, plus a shaft outside the house.
	_fill(volume, AABB(Vector3(-18, -7, -3), Vector3(36, 5, 5)), Volume.AIR)
	_fill(volume, AABB(Vector3(15, -7, -3), Vector3(3, 8, 5)), Volume.AIR)
	# Opaque canopy and pillars expose direct-shadow differences.
	_fill(volume, AABB(Vector3(13, 1, 12), Vector3(2, 7, 2)), Volume.WOOD)
	_fill(volume, AABB(Vector3(10, 7, 9), Vector3(8, 3, 8)), Volume.LEAVES)
	_fill(volume, AABB(Vector3(-18, 1, 10), Vector3(2, 10, 2)), Volume.STONE)
	# Shallow/deep basin: geometry agrees with the fixed analytic water depths.
	_fill(volume, AABB(Vector3(12, -2, -25), Vector3(8, 3, 16)), Volume.AIR)
	_fill(volume, AABB(Vector3(20, -5, -25), Vector3(8, 6, 16)), Volume.AIR)
	for stair: int in range(5):
		_fill(volume, AABB(Vector3(-25 + stair, 1, 2), Vector3(1, stair + 1, 5)), Volume.STONE)
	_fill(volume, AABB(Vector3(-19, 1, 2), Vector3(1, 6, 5)), Volume.STONE)
	for distance: int in range(4):
		_fill(volume, AABB(Vector3(-25 + distance * 14, 1, -29), Vector3(2, 3 + distance, 2)), Volume.STONE)
	volume.rebuild()
	return volume

## Test layout authored as boxes; voxel fills execute in the production native buffer.
static func _fill(volume: Volume, bounds: AABB, value: int) -> void:
	var tool: VoxelTool = volume.voxels.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	tool.value = value
	var start: Vector3i = Vector3i(bounds.position) - volume.origin
	tool.do_box(start, start + Vector3i(bounds.size) - Vector3i.ONE)
