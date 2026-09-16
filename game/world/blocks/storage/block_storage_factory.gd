class_name AstraeonBlockStorageFactory
extends RefCounted
## Explicit selection remains available. Recommendation comes from the 2026-09-16 local suite.
const STORAGE: Script = preload("res://game/world/blocks/storage/block_storage.gd")
const DIRECT32: Script = preload("res://game/world/blocks/storage/direct32_storage.gd")
const DIRECT16: Script = preload("res://game/world/blocks/storage/direct16_storage.gd")
const PALETTE: Script = preload("res://game/world/blocks/storage/palette_storage.gd")
enum Backend { DIRECT32, DIRECT16, PALETTE }
## Active-section baseline, not a claim about release rendering or native VoxelBuffer.
const RECOMMENDED_ACTIVE_BACKEND: Backend = Backend.DIRECT16

static func create(backend: Backend) -> AstraeonBlockStorage:
	match backend:
		Backend.DIRECT32:
			return DIRECT32.new()
		Backend.DIRECT16:
			return DIRECT16.new()
		Backend.PALETTE:
			return PALETTE.new()
	return null

## Independent copy. Source is never mutated.
static func convert(source: AstraeonBlockStorage, backend: Backend) -> AstraeonBlockStorage:
	if source == null:
		return null
	var target: AstraeonBlockStorage = create(backend)
	if target == null or not target.import_states(source.export_states()):
		return null
	return target
