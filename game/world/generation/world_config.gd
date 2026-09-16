class_name AstraeonWorldConfig
extends Resource
## Immutable after configure; export a value snapshot into every world manifest.
@export var world_seed: int = 20260916
@export var generator_version: int = 1
@export_enum("Independent", "Column cache", "Interpolated") var generation_mode: int = 0
@export_enum("Natural", "Controlled") var layout: int = 0
@export var min_y: int = -64
@export var max_y: int = 192
@export var sea_level: int = 32
@export var sample_step: int = 4
@export var cache_columns: int = 256

func snapshot() -> Dictionary:
	return {"seed": str(world_seed), "generator_version": generator_version, "generation_mode": generation_mode, "layout": layout, "min_y": min_y, "max_y": max_y, "sea_level": sea_level, "sample_step": sample_step, "cache_columns": cache_columns}

func valid() -> bool:
	return generator_version == 1 and generation_mode >= 0 and generation_mode <= 2 and layout >= 0 and layout <= 1 and min_y % 16 == 0 and max_y % 16 == 0 and min_y < sea_level and sea_level < max_y and sample_step in [2, 4, 8] and cache_columns > 0
