extends SceneTree
var checks: int = 0
var failures: Array[String] = []
var world: Node3D
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	world = load("res://game/core/main.tscn").instantiate()
	world.world_directory = "res://tmp/drop-world/" + str(Time.get_ticks_usec())
	world.shading_settings_path = world.world_directory + "/settings.cfg"
	preload("res://test/survival/gdscript/world_fixture.gd").prepare(world)
	root.add_child(world)
	var deadline: int = Time.get_ticks_msec() + 45000
	while not world.ready_to_play and not world.failed and Time.get_ticks_msec() < deadline:
		await process_frame
	check(world.ready_to_play, "World ready with native drops")
	if not world.ready_to_play:
		finish()
		return
	world._autosave_elapsed = -999.0
	world.dropped_items.set_physics_process(false)
	world.controller.set_physics_process(false)
	world.player.set_physics_process(false)
	world.inventory.insert(&"astraeon:log_item", 3)
	var drop_event: InputEventKey = InputEventKey.new()
	drop_event.physical_keycode = KEY_Q
	drop_event.pressed = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	world._unhandled_input(drop_event)
	check(world.dropped_items.pool.call("get_count") == 1 and world.inventory.stack_at(0).count == 2, "Selected-slot throw transfers one")
	world.set_game_mode(1)
	world.inventory.creative_pick(&"astraeon:sword")
	world.inventory_hud.set_open(true)
	world.inventory_hud.set_open(false)
	check(world.dropped_items.pool.call("get_count") == 2 and world.inventory.cursor_stack() == null, "Closing inventory spawns cursor item")
	world.set_game_mode(0)
	var pos: Vector3i = Vector3i(4, int(world.generator.sample_column(4,4).height), 4)
	var before: Dictionary = world.inventory.snapshot()
	check(world.inventory_interaction.edit(pos, false), "Mining creates a drop transaction")
	check(world.voxel_tool.get_voxel(pos) == 0 and world.dropped_items.pool.call("get_count") == 3 and world.inventory.snapshot() == before, "Mining edits terrain without direct inventory grant")
	world.set_game_mode(1)
	world.inventory.clear_inventory()
	world.set_game_mode(0)
	world.inventory.insert(&"astraeon:dirt_item", 2560)
	world.inventory.consume(0, 12)
	var center: Vector3 = world.player.position + Vector3(0.2,0.5,0)
	check(world.dropped_items.spawn_item(&"astraeon:dirt_item",40,center,Vector3.ZERO,0.0) and world.inventory.commit_world(), "Spawn pickup fixture durably")
	world.dropped_items.pickup_nearby()
	var near: Array = world.dropped_items.pool.call("nearby", center, 0.3, true)
	check(world.inventory.stack_at(0).count == 64 and near.size() == 1 and near[0].count == 28, "Partial pickup adds 12 and leaves 28")
	before = world.dropped_items.pool.call("snapshot")
	world.dropped_items.pickup_nearby()
	check(world.dropped_items.pool.call("snapshot") == before, "Full bag leaves ground stack intact")
	var next: Vector3i = Vector3i(5, int(world.generator.sample_column(5,4).height), 4)
	check(world.inventory_interaction.edit(next,false) and world.voxel_tool.get_voxel(next) == 0, "Full bag can still mine into ground drop")
	await world.save_world(false)
	check(not world.failed and world.inventory_store.pending.is_empty(), "Checkpoint terrain plus drops")
	var restored_inventory: AstraeonInventoryState = AstraeonInventoryState.new()
	restored_inventory.configure(world.item_catalog, world.inventory_definition)
	var restored_manager: Node3D = load("res://game/entities/dropped_items/gdscript/dropped_items.gd").new()
	restored_manager.configure(world)
	var restored_store: AstraeonInventoryStore = AstraeonInventoryStore.new()
	restored_store.dropped_items = restored_manager.pool
	var identity: Dictionary = {"generation":2,"seed":world.seed,"layout":world.biome_layout,"world_id":world.content.bundle.world_id}
	check(restored_store.open(world.world_directory, identity, restored_inventory), "Open current inventory/drop snapshot")
	check(restored_inventory.snapshot() == world.inventory.snapshot() and restored_manager.pool.call("snapshot") == world.dropped_items.pool.call("snapshot"), "Exact paired inventory and drops round trip")
	restored_manager.free()
	world.set_game_mode(1)
	world.inventory.clear_inventory()
	world.set_game_mode(0)
	world.inventory.insert(&"astraeon:log_item", 7)
	drop_event.shift_pressed = true
	world._unhandled_input(drop_event)
	check(world.inventory.stack_at(0) == null, "Shift+Q throws selected full stack")
	# Stationary visual fixtures in front of the actual main-world camera.
	var forward: Vector3 = -world.camera.global_basis.z
	var right: Vector3 = world.camera.global_basis.x
	world.dropped_items.spawn_item(&"astraeon:grass_item", 1, world.camera.global_position + forward * 1.5 - right * 0.3, Vector3.ZERO)
	world.dropped_items.spawn_item(&"astraeon:sword", 1, world.camera.global_position + forward * 1.5 + right * 0.3, Vector3.ZERO)
	# Render near ground records using shared item meshes.
	deadline = Time.get_ticks_msec() + 5000
	var visible_count: int = world.dropped_items.pool.call("nearby", world.player.position, 32.0, false).size()
	while world.dropped_items._views.size() < visible_count and Time.get_ticks_msec() < deadline:
		world.dropped_items._update_views()
		await process_frame
	check(world.dropped_items._views.size() == visible_count, "All derived block and tool views are ready")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/dropped-items/world.png")
	if "--failure" in OS.get_cmdline_user_args():
		var inventory_before: Dictionary = world.inventory.snapshot()
		var drops_before: Dictionary = world.dropped_items.pool.call("snapshot")
		var sequence_before: int = world.inventory_store._sequence
		check(not world.dropped_items.spawn_item(&"missing:item", 1, world.player.position, Vector3.ZERO), "Generation failure returns false")
		check(world.failed and paused and world.inventory.locked and not world.ready_to_play, "Failure halts world and locks inventory")
		check(not world.dropped_items.spawn_item(&"astraeon:sword", 1, world.player.position, Vector3.ZERO), "Failed world cannot spawn replacement")
		check(not await world.save_world(false) and world.inventory_store._sequence == sequence_before, "Failed state cannot be persisted")
		check(world.dropped_items.pool.call("snapshot") == drops_before and world.inventory.snapshot() == inventory_before, "Failure neither adds replacement nor returns items")
	finish()
func finish() -> void:
	print("DROPPED_WORLD_TEST ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
