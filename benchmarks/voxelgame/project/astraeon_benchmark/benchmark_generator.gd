extends "res://blocky_game/generator/generator.gd"
## Controlled fixtures, not production biomes. Reuses upstream block/foliage generation.
var profile: String = "plain"

func configure(selected: String, selected_seed: int) -> void:
	profile = selected
	_heightmap_noise.seed = selected_seed
	_heightmap_min_y = -128
	_heightmap_max_y = 320
	_heightmap_range = 448
	_trees_min_y = 0
	_trees_max_y = 352

func _get_height_at(x: int, z: int) -> int:
	var noise_value: float = _heightmap_noise.get_noise_2d(x, z)
	var mountain_weight: float = 1.0 if profile == "mountain" else 0.0
	if profile == "mixed":
		# 1200 m repeating route: plains, forest, then mountain; smooth transitions.
		var band: float = fposmod(float(x), 1200.0)
		mountain_weight = smoothstep(700.0, 850.0, band) * (1.0 - smoothstep(1050.0, 1200.0, band))
	return int(32.0 + noise_value * 5.0 + mountain_weight * (110.0 + noise_value * 90.0))

func _get_tree_instances_in_chunk(cpos: Vector3i, offset: Vector3i, chunk_size: int, tree_instances: Array) -> void:
	var forest: bool = profile == "forest"
	if profile == "mixed":
		var band: float = fposmod(float(cpos.x * chunk_size), 1200.0)
		forest = band >= 350.0 and band < 700.0
	if forest:
		super._get_tree_instances_in_chunk(cpos, offset, chunk_size, tree_instances)
