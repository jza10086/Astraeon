extends RefCounted
## Finite reference fixture with production opacity/emission and GPU sampling semantics.
## Production remains C++ SectionLightCache; this solver is test-only.
## Coordinates are world voxel coordinates, bounds are half-open.
const AIR: int = 0
const STONE: int = 1
const LAMP: int = 2
const WOOD: int = 3
const LEAVES: int = 4
const STATE_KEYS: Array[StringName] = [&"shading_test:air", &"shading_test:stone", &"shading_test:lamp", &"shading_test:wood", &"shading_test:leaves"]
const MAX_LIGHT: int = 15
const DIRECTIONS: Array[Vector3i] = [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]
var _opacity: PackedByteArray = PackedByteArray()
var _emission: PackedByteArray = PackedByteArray()
var origin: Vector3i
var size: Vector3i
var voxels: VoxelBuffer = VoxelBuffer.new()

func cell_count() -> int:
	return size.x * size.y * size.z

func voxel_by_index(index: int) -> int:
	return voxels.get_voxel_v(position_of(index) - origin, VoxelBuffer.CHANNEL_TYPE)
var sky: PackedByteArray = PackedByteArray()
var block: PackedByteArray = PackedByteArray()
var revision: int = 0
var settled_revision: int = -1
var processed_cells: int = 0
var last_step_usec: int = 0
var total_step_usec: int = 0
var _direct: PackedByteArray = PackedByteArray()
var _queued: PackedByteArray = PackedByteArray()
var _queue: PackedInt32Array = PackedInt32Array()
var _head: int = 0
var _columns: Dictionary[Vector2i, bool] = {}

func configure(volume_origin: Vector3i, volume_size: Vector3i, catalog: AstraeonBlockCatalog = null) -> void:
	assert(volume_size.x > 0 and volume_size.y > 0 and volume_size.z > 0)
	_opacity.clear()
	_emission.clear()
	if catalog == null:
		var reader: RefCounted = ClassDB.instantiate("AstraeonContentPack")
		var data: Dictionary = reader.call("open_pack", "res://tmp/content/shading_test.aebpack")
		assert(not data.has("error"), str(data))
		_opacity.append(0)
		_emission.append(0)
		for i: int in range(1, STATE_KEYS.size()):
			for record: Dictionary in data.blocks:
				if String(record.id) == String(STATE_KEYS[i]):
					_opacity.append(int(record.opacity))
					_emission.append(int(record.emission))
	else:
		for key: StringName in STATE_KEYS:
			var definition: AstraeonBlockDefinition = null
			for candidate: AstraeonBlockDefinition in catalog.definitions:
				if candidate.key == key:
					assert(definition == null, "Duplicate fixture state")
					definition = candidate
			assert(definition != null, "Missing fixture state: " + String(key))
			assert(definition.light_opacity >= 0 and definition.light_opacity <= 15)
			assert(definition.light_emission >= 0 and definition.light_emission <= 15)
			_opacity.append(definition.light_opacity)
			_emission.append(definition.light_emission)
	origin = volume_origin
	size = volume_size
	var count: int = size.x * size.y * size.z
	voxels.create(size.x, size.y, size.z)
	voxels.set_channel_depth(VoxelBuffer.CHANNEL_TYPE, VoxelBuffer.DEPTH_16_BIT)
	sky.resize(count)
	block.resize(count)
	_direct.resize(count)
	_queued.resize(count)
	rebuild()

func contains(p: Vector3i) -> bool:
	var q: Vector3i = p - origin
	return q.x >= 0 and q.y >= 0 and q.z >= 0 and q.x < size.x and q.y < size.y and q.z < size.z

func index_of(p: Vector3i) -> int:
	var q: Vector3i = p - origin
	return q.x + size.x * (q.y + size.y * q.z)

func position_of(index: int) -> Vector3i:
	@warning_ignore("integer_division")
	return origin + Vector3i(index % size.x, (index / size.x) % size.y, index / (size.x * size.y))

func voxel_at(p: Vector3i) -> int:
	if not contains(p):
		return STONE # Unknown world never supplies light.
	return voxels.get_voxel_v(p - origin, VoxelBuffer.CHANNEL_TYPE)

## Unknown cells block light, matching the native section dependency boundary.
func opacity_at(p: Vector3i) -> int:
	return int(_opacity[voxel_at(p)]) if contains(p) else MAX_LIGHT

func emission_at(p: Vector3i) -> int:
	return int(_emission[voxel_at(p)]) if contains(p) else 0

func light_at(p: Vector3i) -> Vector2i:
	if not contains(p):
		return Vector2i.ZERO
	var index: int = index_of(p)
	return Vector2i(sky[index], block[index])

## Apply a whole transaction before advancing the solver. Last value per voxel wins.
## Returns actual changed cells for independent geometry invalidation.
func apply_edits(edits: Dictionary[Vector3i, int]) -> Array[Vector3i]:
	var changed: Array[Vector3i] = []
	for p: Vector3i in edits:
		var value: int = edits[p]
		assert(value >= AIR and value <= LEAVES)
		if not contains(p):
			continue
		var index: int = index_of(p)
		if voxel_by_index(index) == value:
			continue
		voxels.set_voxel_v(value, p - origin, VoxelBuffer.CHANNEL_TYPE)
		changed.append(p)
		_columns[Vector2i(p.x, p.z)] = true
		_enqueue(index)
		_enqueue_neighbors(p)
	if not changed.is_empty():
		revision += 1
	return changed

## Reference reset also serves initialization; ordinary edits do not call this.
func rebuild() -> void:
	sky.fill(0)
	block.fill(0)
	_direct.fill(0)
	_queued.fill(0)
	_queue.clear()
	_head = 0
	_columns.clear()
	for z: int in range(origin.z, origin.z + size.z):
		for x: int in range(origin.x, origin.x + size.x):
			_columns[Vector2i(x, z)] = true
	# Include emissive sources even when fully enclosed.
	for index: int in range(cell_count()):
		if _emission[voxel_by_index(index)] > 0:
			_enqueue(index)
	revision += 1
	settled_revision = -1

func pending_count() -> int:
	return _queue.size() - _head + _columns.size() * size.y

func is_settled() -> bool:
	return _columns.is_empty() and _head == _queue.size() and settled_revision == revision

## Budgeted main-thread relaxation handles both removal and re-spreading.
## Every non-source edge loses one level, so stale cycles decay to zero.
## A column scan is atomic (64 cells in the sample); time budget is soft.
func step(max_cells: int = 4096, budget_usec: int = 2000) -> bool:
	var begin: int = Time.get_ticks_usec()
	var work: int = 0
	while not _columns.is_empty() and work < max_cells:
		var column: Vector2i = _columns.keys()[0]
		_columns.erase(column)
		_refresh_column(column)
		work += size.y
		if budget_usec > 0 and Time.get_ticks_usec() - begin >= budget_usec:
			break
	while _columns.is_empty() and _head < _queue.size() and work < max_cells:
		if budget_usec > 0 and Time.get_ticks_usec() - begin >= budget_usec:
			break
		var index: int = _queue[_head]
		_head += 1
		_queued[index] = 0
		var p: Vector3i = position_of(index)
		var next_sky: int = _direct[index]
		var id: int = voxel_by_index(index)
		var next_block: int = _emission[id]
		var attenuation: int = _opacity[id]
		if attenuation < MAX_LIGHT:
			for direction: Vector3i in DIRECTIONS:
				var neighbor: Vector3i = p + direction
				if contains(neighbor):
					var ni: int = index_of(neighbor)
					next_sky = maxi(next_sky, int(sky[ni]) - maxi(1, attenuation))
					next_block = maxi(next_block, int(block[ni]) - maxi(1, attenuation))
		if next_sky != sky[index] or next_block != block[index]:
			sky[index] = next_sky
			block[index] = next_block
			_enqueue_neighbors(p)
		work += 1
	processed_cells += work
	if _head == _queue.size():
		_queue.clear()
		_head = 0
		if _columns.is_empty():
			settled_revision = revision
	elif _head > 65536:
		_queue = _queue.slice(_head)
		_head = 0
	last_step_usec = Time.get_ticks_usec() - begin
	total_step_usec += last_step_usec
	return is_settled()

func _refresh_column(column: Vector2i) -> void:
	var incoming: int = MAX_LIGHT
	for y: int in range(origin.y + size.y - 1, origin.y - 1, -1):
		var p: Vector3i = Vector3i(column.x, y, column.y)
		var index: int = index_of(p)
		var value: int = maxi(0, incoming - int(_opacity[voxel_by_index(index)]))
		incoming = value
		if _direct[index] != value:
			_direct[index] = value
			_enqueue(index)

func _enqueue(index: int) -> void:
	if _queued[index] == 0:
		_queued[index] = 1
		_queue.append(index)

func _enqueue_neighbors(p: Vector3i) -> void:
	for direction: Vector3i in DIRECTIONS:
		var neighbor: Vector3i = p + direction
		if contains(neighbor):
			_enqueue(index_of(neighbor))

## RGBA8 matches native pack(): sky, block, transmissive sampling mask, reserved.
## This bounded prototype uploads the complete texture only after convergence.
func make_images() -> Array[Image]:
	assert(is_settled())
	var images: Array[Image] = []
	for z: int in range(size.z):
		var data: PackedByteArray = PackedByteArray()
		data.resize(size.x * size.y * 4)
		for y: int in range(size.y):
			for x: int in range(size.x):
				var index: int = x + size.x * (y + size.y * z)
				var pixel: int = 4 * (x + size.x * y)
				data[pixel] = sky[index] * 17
				data[pixel + 1] = block[index] * 17
				data[pixel + 2] = 255 if _opacity[voxel_by_index(index)] < MAX_LIGHT else 0
				data[pixel + 3] = 255
		images.append(Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, data))
	return images
