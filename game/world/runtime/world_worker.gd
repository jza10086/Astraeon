class_name AstraeonWorldWorker
extends RefCounted
const GENERATOR: Script = preload("res://game/world/generation/terrain_generator.gd")
const SECTION: Script = preload("res://game/world/blocks/block_section.gd")
const MESHER: Script = preload("res://game/world/presentation/terrain_mesher.gd")
var generator: AstraeonTerrainGenerator = GENERATOR.new()
var store: AstraeonWorldStore
var ids: PackedInt32Array
var backend: int
var state_count: int
var task_id: int = -1
var job: Dictionary = {}
var result: Dictionary = {}

func execute() -> void:
	var started: int = Time.get_ticks_usec()
	match job.kind:
		"load":
			result = store.load_section(job.coordinate)
			if result.get("missing", false):
				result = generator.generate(job.coordinate, state_count, backend)
				result["generated"] = true
			elif result.has("states"):
				var section: AstraeonBlockSection = SECTION.new()
				var imported: int = Time.get_ticks_usec()
				if not section.configure(job.coordinate, state_count, backend) or not section.import_states(result.states):
					result = {"error": "Loaded section rejected"}
				else:
					result.erase("states")
					result["section"] = section
					result["import_us"] = Time.get_ticks_usec() - imported
		"save":
			result = store.save_section(job.coordinate, job.revision, job.states)
		"mesh":
			result = MESHER.build(job.coordinate, job.snapshots, ids, state_count, backend)
	result["worker_started_us"] = started
	result["worker_finished_us"] = Time.get_ticks_usec()
	result["worker_us"] = Time.get_ticks_usec() - started
