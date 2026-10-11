extends Node
## Production world, UI, physics and save transactions; all data stays in tmp.
var checks: int = 0
var failures: Array[String] = []
var world: Node3D
var output: String = "res://tmp/modes-world"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)

func frames(count: int = 3) -> void:
	for index: int in count:
		await get_tree().process_frame

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	world = preload("res://game/core/main.tscn").instantiate()
	world.world_directory = output + "/world-" + str(Time.get_ticks_usec())
	world.shading_settings_path = world.world_directory + "/settings.cfg"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.horizontal_distance = 16
	world.vertical_distance = 16
	preload("res://test/survival/gdscript/world_fixture.gd").prepare(world)
	add_child(world)
	var deadline: int = Time.get_ticks_msec() + 60000
	while not world.ready_to_play and not world.failed and Time.get_ticks_msec() < deadline:
		await frames(1)
	check(world.ready_to_play, "Production world ready")
	if not world.ready_to_play:
		finish()
		return
	world._autosave_elapsed = -999.0
	world.controller.set_physics_process(false)
	world.dropped_items.set_physics_process(false)
	var hud: AstraeonInventoryHUD = world.inventory_hud
	var state: AstraeonPlayerState = world.player_state
	check(state.health == 10 and state.hunger == 10 and not state.is_creative(), "World starts in survival")
	hud.set_open(true)
	check(hud._storage.visible and not hud.creative_browser.visible and not hud._mode_tabs.visible and not hud._trash.visible, "Survival window hides privileged UI")
	check(not world.inventory.creative_pick(&"astraeon:dirt_item"), "Survival cannot invoke creative API")
	hud.set_open(false)
	world.pause_menu.open_menu()
	world.pause_menu._mode_selected(1)
	check(get_tree().paused and state.is_creative(), "Pause switch keeps pause active")
	world.pause_menu.resume_game()
	check(world.inventory.creative_pick(&"astraeon:dirt_item") and world.inventory.click_slot(0), "Creative obtains one block")
	var position: Vector3i = Vector3i(4, int(world.generator.sample_column(4, 4).height) + 1, 4)
	world.set_block(position, 0)
	deadline = Time.get_ticks_msec() + 10000
	var placed: bool = world.inventory_interaction.edit(position, true)
	while not placed and Time.get_ticks_msec() < deadline:
		await frames(1)
		placed = world.inventory_interaction.edit(position, true)
	check(placed and world.inventory.stack_at(0).count == 1, "Creative placement is free")
	check(not world.inventory_store.pending.is_empty(), "Creative placement enters WAL")
	var drops: int = world.dropped_items.pool.call("get_count")
	check(world.inventory_interaction.edit(position, false) and int(world.dropped_items.pool.call("get_count")) == drops, "Creative mining has no drops")
	world.set_game_mode(0)
	check(world.inventory.stack_at(0).count == 1, "Modes share inventory")
	check(world.inventory_interaction.edit(position, true) and world.inventory.stack_at(0) == null, "Survival consumes placement")
	check(world.inventory_interaction.edit(position, false) and int(world.dropped_items.pool.call("get_count")) == drops + 1, "Survival mining creates drop")
	state.decrease_health(3)
	state.decrease_hunger(4)
	check(hud._health_text.text == "生命 7/10" and hud._hunger_text.text == "饱食度 6/10", "HUD updates exact values")
	world.set_game_mode(1)
	state.decrease_health(1)
	check(state.health == 6 and state.hunger == 6, "Creative explicit decrement works")
	world.controller._handle_jump_press(1.0)
	world.controller._handle_jump_press(1.2)
	check(world.player.flying, "Double jump enters flight")
	world.player.position.y += 6.0
	world.player.move_intent = Vector3.RIGHT
	world.player.flight_vertical = 1.0
	await get_tree().physics_frame
	world.player.step(1.0 / 60.0)
	check(is_equal_approx(world.player.velocity.length(), 8.0) and world.player.velocity.y > 0, "Normalized upward flight speed")
	world.player.sprint_requested = true
	await get_tree().physics_frame
	world.player.step(1.0 / 60.0)
	check(is_equal_approx(world.player.velocity.length(), 16.0), "Accelerated flight speed")
	world.player.reset_motion()
	await get_tree().physics_frame
	world.player.step(1.0 / 60.0)
	check(world.player.velocity == Vector3.ZERO, "Flight hovers without input")
	world.player.flight_vertical = -1.0
	await get_tree().physics_frame
	world.player.step(1.0 / 60.0)
	check(world.player.velocity.y < 0, "Flight descends")
	world.controller._handle_jump_press(2.0)
	hud.set_open(true)
	check(world.player.flight_vertical == 0 and world.controller._last_jump_press < 0, "Bag clears flight input and double tap")
	hud.set_open(false)
	world.pause_menu.open_menu()
	world.pause_menu._mode_selected(0)
	check(not world.player.flying and world.player.velocity == Vector3.ZERO, "Survival revokes flight")
	world.pause_menu.resume_game()
	# Test collision against an isolated fixture wall using the actual character motor.
	world.set_game_mode(1)
	world.player.flying = true
	var wall: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1, 6, 6)
	collision.shape = box
	wall.add_child(collision)
	add_child(wall)
	wall.global_position = world.player.global_position + Vector3(2, 1, 0)
	var before_x: float = world.player.global_position.x
	world.player.move_intent = Vector3.RIGHT
	for index: int in 30:
		await get_tree().physics_frame
		world.player.step(1.0 / 60.0)
	check(world.player.global_position.x < before_x + 1.5, "Flight respects collisions")
	wall.queue_free()
	world.player.reset_motion()
	world.set_game_mode(0)
	await verify_layout(hud)
	world.set_game_mode(1)
	world.inventory.creative_pick(&"astraeon:sword")
	hud.set_open(true)
	drops = world.dropped_items.pool.call("get_count")
	hud.set_open(false)
	check(not hud.opened and world.inventory.cursor_stack() == null and int(world.dropped_items.pool.call("get_count")) == drops + 1, "Close commits cursor drop once")
	world.pause_menu.open_menu()
	print("MODE_SAVE_START ", VoxelEngine.get_stats())
	check(await world.save_world(false, true), "Final checkpoint includes player state")
	print("MODE_SAVE_END ", VoxelEngine.get_stats())
	if world.failed:
		finish()
		return
	world.pause_menu.resume_game()
	var restored: AstraeonInventoryState = AstraeonInventoryState.new()
	restored.configure(world.item_catalog, world.inventory_definition)
	var manager: Node3D = preload("res://game/entities/dropped_items/gdscript/dropped_items.gd").new()
	manager.configure(world)
	var store: AstraeonInventoryStore = AstraeonInventoryStore.new()
	store.dropped_items = manager.pool
	check(store.open(world.world_directory, {"generation": 2, "seed": world.seed, "layout": world.biome_layout, "world_id": world.content.bundle.world_id}, restored), "Reopen checkpoint")
	check(restored.player_state.snapshot() == state.snapshot() and restored.snapshot() == world.inventory.snapshot(), "World round trip preserves shared state")
	manager.free()
	# Reject an actual staged drop commit; stop the world and preserve both pre-operation states.
	world.inventory.creative_pick(&"astraeon:sword")
	hud.set_open(true)
	var previous_inventory: Dictionary = world.inventory.snapshot()
	var previous_drops: Dictionary = world.dropped_items.pool.call("snapshot")
	world.inventory.before_commit = func(_candidate: Dictionary, _context: Dictionary) -> bool: return false
	hud.set_open(false)
	check(hud.opened and world.failed and world.inventory.snapshot() == previous_inventory and world.dropped_items.pool.call("snapshot") == previous_drops, "Failed close preserves held items and rolls back uncommitted drop")
	finish()

func verify_layout(live_hud: AstraeonInventoryHUD) -> void:
	var viewport_node: SubViewport = SubViewport.new()
	viewport_node.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_node.disable_3d = true
	add_child(viewport_node)
	var background: ColorRect = ColorRect.new()
	background.color = Color("253343")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_node.add_child(background)
	var hud: AstraeonInventoryHUD = preload("res://game/ui/inventory/scenes/inventory_hud.tscn").instantiate()
	hud.inventory = live_hud.inventory
	hud.drop_cursor = live_hud.drop_cursor
	hud.can_interact = func() -> bool: return false
	viewport_node.add_child(hud)
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(3440, 1440)]:
		viewport_node.size = size
		viewport_node.size_2d_override = Vector2i(maxi(1920, roundi(size.x * 1080.0 / size.y)), maxi(1080, roundi(size.y * 1920.0 / size.x)))
		viewport_node.size_2d_override_stretch = true
		await frames(6)
		var viewport: Rect2 = viewport_node.get_visible_rect()
		check(viewport.encloses(hud._vitals.get_global_rect()) and not hud._vitals.get_global_rect().intersects(hud._bar.get_global_rect()), "Vitals fit " + str(size))
		check(viewport_node.get_texture().get_image().get_size() == size, "Actual render resolution " + str(size))
		check(hud._health_bar.size == Vector2(310, 26) and hud._hunger_bar.size == Vector2(310, 26), "Bar dimensions " + str(size))
		await RenderingServer.frame_post_draw
		viewport_node.get_texture().get_image().save_png(output + "/hud_%dx%d.png" % [size.x, size.y])
		hud.set_open(true)
		await frames()
		check(not hud._vitals.visible and viewport.encloses(hud._storage.get_global_rect()), "Survival bag fits " + str(size))
		if size.x == 1920:
			await RenderingServer.frame_post_draw
			viewport_node.get_texture().get_image().save_png(output + "/survival_bag.png")
		hud.set_open(false)
	world.set_game_mode(1)
	hud.set_open(true)
	hud.set_page(&"search")
	await frames()
	check(hud.creative_browser.visible and hud._mode_tabs.visible, "Creative window remains available")
	await RenderingServer.frame_post_draw
	viewport_node.get_texture().get_image().save_png(output + "/creative_bag.png")
	hud.set_open(false)
	viewport_node.queue_free()
	await frames()

func finish() -> void:
	var result: Dictionary = {"checks": checks, "failures": failures}
	var file: FileAccess = FileAccess.open(output + "/result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("MODES_WORLD_TEST ", JSON.stringify(result))
	get_tree().paused = false
	get_tree().quit(0 if failures.is_empty() else 1)
