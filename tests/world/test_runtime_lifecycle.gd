extends SceneTree
## Integration regression for async ownership, edits during save and stale requests.
const CONFIG: Script = preload("res://game/world/generation/world_config.gd")
const CATALOG: Script = preload("res://game/world/generation/terrain_catalog.gd")
const RUNTIME: Script = preload("res://game/world/runtime/world_runtime.gd")
const STORE: Script = preload("res://game/world/persistence/world_store.gd")
const SECTION: Script = preload("res://game/world/blocks/block_section.gd")
var world: AstraeonWorldRuntime
var failures: PackedStringArray = PackedStringArray()
var checks: int = 0

func _initialize() -> void:
	if not "--run" in OS.get_cmdline_user_args():
		quit()
		return
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)

func settled() -> bool:
	var deadline: int = Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if not world.failed.is_empty():
			return false
		if world.missing_count() == 0 and world.visible_missing_count() == 0 and world.pending_count() == 0 and world.dirty_count() == 0:
			return true
	return false

func _run() -> void:
	var registry: AstraeonBlockRegistry = CATALOG.build_registry()
	var ids: PackedInt32Array = CATALOG.ids(registry)
	var config: AstraeonWorldConfig = CONFIG.new()
	config.layout = 1
	config.generation_mode = 1
	var path: String = "res://tmp/world_validation_20260917/lifecycle_" + str(Time.get_ticks_usec())
	world = RUNTIME.new()
	world.horizontal_distance = 16
	world.vertical_distance = 16
	var error: String = world.configure(config, registry, ids, path, 1, 1, 1)
	check(error.is_empty(), "configure")
	if not error.is_empty():
		quit(2)
		return
	root.add_child(world)
	world.set_observer(Vector3(64, 40, 64))
	check(await settled(), "initial visible, collision, and save completion")
	var position: Vector3i = Vector3i(64, 40, 64)
	check(world.edit(position, ids[4]), "first edit")
	world.flush_saves()
	await process_frame
	check(world.edit(position, ids[1]), "edit while async snapshot is in flight")
	world.flush_saves()
	check(await settled(), "latest revision eventually saved and meshed")
	var reopened: AstraeonWorldStore = STORE.new()
	check(reopened.configure(path, config.snapshot(), registry, 1, 1).is_empty(), "reopen")
	var loaded: Dictionary = reopened.load_section(SECTION.section_of(position))
	check(loaded.has("states") and loaded.states[SECTION.index_of(SECTION.world_to_local(position))] == ids[1], "newer edit survives disk round trip")
	world.set_observer(Vector3(-640, 40, -640))
	await process_frame
	world.set_observer(Vector3(640, 40, 640))
	await process_frame
	world.set_observer(Vector3(64, 40, 64))
	check(await settled(), "rapid request cancellation returns to complete terrain")
	check(world.sections[SECTION.section_of(position)].get_state(SECTION.world_to_local(position)) == ids[1], "stale work did not overwrite saved edit")
	world.stop_requests()
	check(await settled(), "shutdown drains writes")
	print("WORLD_LIFECYCLE_RESULT " + JSON.stringify({"checks": checks, "failures": failures, "world": path}))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 2)
