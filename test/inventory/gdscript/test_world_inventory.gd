extends SceneTree
var failures: Array[String] = []
var checks: int = 0
var world: Node3D

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func press(key: int) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func run() -> void:
	world = load("res://game/core/main.tscn").instantiate()
	world.world_directory = "res://tmp/inventory-world/" + str(Time.get_ticks_usec())
	world.shading_settings_path = "res://tmp/inventory-world/settings.cfg"
	root.add_child(world)
	var deadline: int = Time.get_ticks_msec() + 45000
	while not world.ready_to_play and Time.get_ticks_msec() < deadline:
		await process_frame
	check(world.ready_to_play, "World ready with inventory")
	if not world.ready_to_play:
		finish()
		return
	world._autosave_elapsed = -999.0
	await press(KEY_E)
	check(world.inventory_hud.opened and not world.controller.input_enabled, "E opens modal and locks movement")
	await press(KEY_F6)
	check(world.inventory_hud.opened and not world.shading._menu.visible and not world.controller.input_enabled, "Settings cannot steal inventory modal")
	await press(KEY_ESCAPE)
	check(not world.inventory_hud.opened and world.controller.input_enabled, "Esc restores controller")
	await press(KEY_F6)
	check(world.shading._menu.visible, "Settings can open normally")
	await press(KEY_E)
	check(not world.inventory_hud.opened, "Bag cannot open over settings")
	await press(KEY_F6)
	var height: int = int(world.generator.sample_column(4, 4).height)
	var position: Vector3i = Vector3i(4, height, 4)
	var original: int = world.voxel_tool.get_voxel(position)
	check(world.inventory_interaction.edit(position, false), "Mine into inventory")
	check(world.voxel_tool.get_voxel(position) == 0 and world.inventory.stack_at(0).count == 1, "Voxel removal and item grant")
	check(world.inventory_interaction.edit(position, true), "Place consumes item")
	check(world.voxel_tool.get_voxel(position) == original and world.inventory.stack_at(0) == null, "Placement and decrement")
	check(not world.inventory_interaction.edit(position + Vector3i.UP, true), "Empty slot cannot place")
	world.inventory.insert(&"astraeon_log_item", 2)
	check(world.inventory_interaction.edit(position + Vector3i.UP, true, Vector3i.RIGHT), "Place horizontal log")
	check(world.voxel_tool.get_voxel(position + Vector3i.UP) == world.content.state_keys.find("astraeon_log/axis_x"), "Actual world log axis")
	var occupied: Vector3i = Vector3i(world.player.position.floor())
	check(not world.inventory_interaction.edit(occupied, true), "Reject player intersection")
	world.inventory.insert(&"astraeon_dirt_item", 3000)
	var next_position: Vector3i = Vector3i(5, int(world.generator.sample_column(5, 4).height), 4)
	var previous: int = world.voxel_tool.get_voxel(next_position)
	# All slots are full after filling any existing wood stack explicitly.
	world.inventory.insert(&"astraeon_log_item", 63)
	check(not world.inventory_interaction.edit(next_position, false) and world.voxel_tool.get_voxel(next_position) == previous, "Full inventory refuses mining without modifying terrain")
	await world.save_world(false)
	check(world.stream.get_last_error().is_empty() and world.inventory_store.error.is_empty(), "Save terrain and inventory")
	var state: AstraeonInventoryState = AstraeonInventoryState.new()
	state.configure(world.item_catalog, world.inventory_definition)
	var store: AstraeonInventoryStore = AstraeonInventoryStore.new()
	var identity: Dictionary = {"generation": 2, "seed": world.seed, "layout": world.biome_layout, "states": "\n".join(world.content.state_keys).sha256_text()}
	check(store.open(world.world_directory, identity, state) and state.snapshot() == world.inventory.snapshot(), "Reload exact inventory")
	finish()

func finish() -> void:
	print("WORLD_INVENTORY_TEST " + JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
