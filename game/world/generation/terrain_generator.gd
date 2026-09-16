class_name AstraeonTerrainGenerator
extends RefCounted
## One instance per worker. G1/G2 are exact; G3 interpolates globally aligned samples.
const CONFIG: Script = preload("res://game/world/generation/world_config.gd")
const SECTION: Script = preload("res://game/world/blocks/block_section.gd")
const FACTORY: Script = preload("res://game/world/blocks/storage/block_storage_factory.gd")
var config: AstraeonWorldConfig
var _continental: FastNoiseLite = FastNoiseLite.new()
var _dryness: FastNoiseLite = FastNoiseLite.new()
var _mountains: FastNoiseLite = FastNoiseLite.new()
var _detail: FastNoiseLite = FastNoiseLite.new()
var _cache: Dictionary[Vector2i, PackedInt32Array] = {}
var _order: Array[Vector2i] = []
var _ids: PackedInt32Array = PackedInt32Array()
var cache_hits: int = 0
var cache_misses: int = 0
var cache_evictions: int = 0

func configure(settings: AstraeonWorldConfig, ids: PackedInt32Array) -> bool:
	if not settings.valid() or ids.size() != 6:
		return false
	config = settings.duplicate() as AstraeonWorldConfig
	_ids = ids.duplicate()
	var noises: Array[FastNoiseLite] = [_continental, _dryness, _mountains, _detail]
	var frequencies: Array[float] = [0.0018, 0.0023, 0.0031, 0.018]
	for index: int in range(noises.size()):
		noises[index].seed = int((config.world_seed + index * 104729) & 0x7fffffff)
		noises[index].frequency = frequencies[index]
		noises[index].fractal_octaves = 3
	return true

## Returns continuous height and a surface biome label: plain, desert, mountain, ocean.
func sample_exact(x: int, z: int) -> Vector2:
	var land: float = smoothstep(-0.22, 0.08, _continental.get_noise_2d(x, z))
	var mountain: float = smoothstep(0.05, 0.45, _mountains.get_noise_2d(x, z)) * land
	var dry: float = smoothstep(-0.05, 0.3, _dryness.get_noise_2d(x, z))
	if config.layout == 1:
		# Continuous transitions inside a repeating 1024-voxel test strip.
		var band: float = fposmod(float(x), 1024.0)
		land = 1.0 - smoothstep(736.0, 800.0, band) + smoothstep(960.0, 1024.0, band)
		mountain = smoothstep(480.0, 544.0, band) * (1.0 - smoothstep(704.0, 768.0, band))
		dry = smoothstep(224.0, 288.0, band) * (1.0 - smoothstep(448.0, 512.0, band))
	var detail: float = _detail.get_noise_2d(x, z)
	var height: float = float(config.sea_level) + lerpf(-24.0, 10.0 + detail * lerpf(4.0, 9.0, dry), land) + mountain * (76.0 + detail * 26.0)
	var biome: int = 3 if land < 0.5 else (2 if mountain > 0.45 else (1 if dry > 0.5 else 0))
	return Vector2(clampf(height, config.min_y + 2.0, config.max_y - 2.0), float(biome))

func column(coordinate: Vector2i) -> PackedInt32Array:
	if config.generation_mode == 1 and _cache.has(coordinate):
		cache_hits += 1
		_order.erase(coordinate)
		_order.append(coordinate)
		return _cache[coordinate]
	cache_misses += 1
	var data: PackedInt32Array = PackedInt32Array()
	data.resize(512)
	# G3 caches lattice samples within this column, rather than evaluating four noises per voxel.
	var samples: Dictionary[Vector2i, Vector2] = {}
	for z: int in range(16):
		for x: int in range(16):
			var wx: int = coordinate.x * 16 + x
			var wz: int = coordinate.y * 16 + z
			var value: Vector2
			if config.generation_mode == 2:
				var step: int = config.sample_step
				var anchor: Vector2i = Vector2i(int(floor(float(wx) / step)) * step, int(floor(float(wz) / step)) * step)
				var corners: Array[Vector2i] = [anchor, anchor + Vector2i(step, 0), anchor + Vector2i(0, step), anchor + Vector2i(step, step)]
				for point: Vector2i in corners:
					if not samples.has(point):
						samples[point] = sample_exact(point.x, point.y)
				var tx: float = float(wx - anchor.x) / step
				var tz: float = float(wz - anchor.y) / step
				value = Vector2(lerpf(lerpf(samples[corners[0]].x, samples[corners[1]].x, tx), lerpf(samples[corners[2]].x, samples[corners[3]].x, tx), tz), samples[anchor].y)
			else:
				value = sample_exact(wx, wz)
			data[(x + 16 * z) * 2] = int(floor(value.x))
			data[(x + 16 * z) * 2 + 1] = int(value.y)
	if config.generation_mode == 1:
		while _order.size() >= config.cache_columns:
			_cache.erase(_order.pop_front())
			cache_evictions += 1
		_cache[coordinate] = data
		_order.append(coordinate)
	return data

func generate(coordinate: Vector3i, state_count: int, backend: int) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var surface: PackedInt32Array = column(Vector2i(coordinate.x, coordinate.z))
	var sampled: int = Time.get_ticks_usec()
	var values: PackedInt32Array = PackedInt32Array()
	values.resize(4096)
	for z: int in range(16):
		for y: int in range(16):
			for x: int in range(16):
				var wy: int = coordinate.y * 16 + y
				var height: int = surface[(x + 16 * z) * 2]
				var biome: int = surface[(x + 16 * z) * 2 + 1]
				var state: int = _ids[0]
				if wy >= config.min_y and wy < config.max_y:
					if wy <= height:
						state = _ids[1]
						if biome == 1 or biome == 3:
							if wy >= height - 3:
								state = _ids[4]
						elif biome == 0:
							if wy == height:
								state = _ids[3]
							elif wy >= height - 3:
								state = _ids[2]
					elif wy < config.sea_level:
						state = _ids[5]
				values[x + 16 * (y + 16 * z)] = state
	var filled: int = Time.get_ticks_usec()
	var section: AstraeonBlockSection = SECTION.new()
	if not section.configure(coordinate, state_count, backend) or not section.import_states(values):
		return {"error": "Generated section rejected"}
	return {"section": section, "sample_us": sampled - started, "fill_us": filled - sampled, "import_us": Time.get_ticks_usec() - filled, "cache_hits": cache_hits, "cache_misses": cache_misses, "cache_evictions": cache_evictions, "cache_payload_bytes": _cache.size() * 2048}

