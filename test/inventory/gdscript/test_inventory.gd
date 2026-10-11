extends SceneTree
var checks: int = 0
var failures: Array[String] = []
const CATALOG: AstraeonItemCatalog = preload("res://test/data/resources/item_reference/item_catalog.tres")
const LAYOUT: AstraeonInventoryDefinition = preload("res://game/data/inventory/resources/player_inventory.tres")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)

func fresh() -> AstraeonInventoryState:
	var state: AstraeonInventoryState = AstraeonInventoryState.new()
	state.configure(CATALOG, LAYOUT)
	return state

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var state: AstraeonInventoryState = fresh()
	check(state.snapshot().slots.size() == 40, "40 shared slots")
	check(state.insert(&"astraeon:dirt_item", 80) == 0 and state.stack_at(0).count == 64 and state.stack_at(1).count == 16, "Insertion splits stacks")
	var copy: AstraeonItemStack = state.stack_at(0)
	copy.count = 1
	check(state.stack_at(0).count == 64, "Readers cannot mutate slots")
	check(state.move(0, 10, 32, state.revision) and state.stack_at(0).count == 32 and state.stack_at(10).count == 32, "Split")
	check(state.move(10, 1, 32, state.revision) and state.stack_at(1).count == 48 and state.stack_at(10) == null, "Merge")
	check(not state.move(0, 2, 1, state.revision - 1), "Reject stale drag")
	check(state.insert(&"astraeon:log_item", 4) == 0, "Insert wood")
	check(state.move(2, 0, 4, state.revision) and state.stack_at(0).item.key == &"astraeon:log_item", "Swap full stacks")
	check(not state.move(0, 1, 1, state.revision), "Do not swap partial incompatible stacks")
	check(state.quick_move(0) and state.stack_at(0) == null and state.stack_at(10).item.key == &"astraeon:log_item", "Quick transfer")
	var snapshot: Dictionary = state.snapshot()
	state.before_commit = func(_candidate: Dictionary, _context: Dictionary) -> bool: return false
	check(not state.consume(1, 1) and state.snapshot() == snapshot, "Failed durable guard is atomic")
	state.before_commit = Callable()
	check(not state.consume(1, 999), "No negative quantities")
	check(state.select(9) and not state.select(10), "Exactly ten hotbar slots")
	var full: AstraeonInventoryState = fresh()
	check(full.insert(&"astraeon:dirt_item", 2561) == 1 and full.capacity(&"astraeon:log_item") == 0, "Capacity and leftovers")
	var malformed: Dictionary = state.snapshot().duplicate(true)
	malformed.slots[0] = {"item": "astraeon:missing", "count": 1}
	check(not state.restore(malformed), "Reject unknown item")
	var wood: AstraeonItemDefinition = state.items[&"astraeon:log_item"]
	check(wood.state_key(Vector3i.LEFT) == "astraeon:log/axis_x" and wood.state_key(Vector3i.BACK) == "astraeon:log/axis_z", "Placement face chooses axis")
	var content: AstraeonWorldContent = AstraeonWorldContent.new()
	check(content.build(PackedStringArray(["res://game/data/content/packages/astraeon.aebpack"])), "Current block content")
	var identity: Dictionary = {"generation": 2, "seed": 42, "layout": 0, "world_id": ""}
	var directory: String = "res://tmp/inventory-test/" + str(Time.get_ticks_usec())
	var registry: RefCounted = ClassDB.instantiate("AstraeonContentRegistry")
	var registered: Dictionary = registry.resolve(directory, content.bundle.contracts, PackedStringArray(content.bundle.packages.keys()))
	identity.world_id = registered.world_id
	var store: AstraeonInventoryStore = AstraeonInventoryStore.new()
	state = fresh()
	check(store.open(directory, identity, state), "Open inventory save")
	check(state.insert(&"astraeon:log_item", 1, {"position": Vector3i(-1, 40, -1), "state": "astraeon:air/default"}) == 0, "Write-ahead mining")
	var restored: AstraeonInventoryState = fresh()
	var recovered: AstraeonInventoryStore = AstraeonInventoryStore.new()
	check(recovered.open(directory, identity, restored) and restored.stack_at(0).count == 1 and recovered.pending.size() == 1, "Recover inventory and pending edit together: " + recovered.error)
	var stream: AstraeonNativeStream = AstraeonNativeStream.new()
	check(stream.open_world(directory, 42, 0, content.state_keys, identity.world_id), "Open native stream")
	var generator: AstraeonNativeGenerator = AstraeonNativeGenerator.new()
	generator.seed = 42
	generator.configure_content(content.state_keys)
	check(recovered.recover(stream, generator, content.state_keys), "Replay into native sections")
	var buffer: VoxelBuffer = VoxelBuffer.new()
	buffer.create(16, 16, 16)
	check(stream.load_voxel_block(buffer, Vector3i(-1, 2, -1), 0) == VoxelStream.RESULT_BLOCK_FOUND and buffer.get_voxel(15, 8, 15) == 0, "Recovered exact negative world coordinate: " + recovered.error)
	check(recovered.checkpoint() and recovered.pending.is_empty(), "Retire durable edits")
	var third: AstraeonInventoryStore = AstraeonInventoryStore.new()
	check(third.open(directory, identity, fresh()) and third.pending.is_empty(), "Checkpoint survives reopen")
	# Simulate an interrupted overwrite of the newer checkpoint; the prior WAL remains replayable.
	var broken: FileAccess = FileAccess.open(directory.path_join("inventory_" + ("a" if recovered._sequence % 2 == 0 else "b") + ".json"), FileAccess.WRITE)
	broken.store_string("{")
	broken.close()
	var interrupted: AstraeonInventoryStore = AstraeonInventoryStore.new()
	var interrupted_state: AstraeonInventoryState = fresh()
	check(interrupted.open(directory, identity, interrupted_state) and interrupted_state.stack_at(0).count == 1 and interrupted.pending.size() == 1, "Interrupted snapshot falls back to checked WAL")
	var wrong_identity: Dictionary = identity.duplicate()
	wrong_identity.seed = 43
	check(not AstraeonInventoryStore.new().open(directory, wrong_identity, fresh()), "Reject inventory from another seed")
	await test_ui()
	print("INVENTORY_TEST " + JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func test_ui() -> void:
	var scene: PackedScene = load("res://test/inventory/scenes/inventory_sample.tscn")
	var sample: Node = scene.instantiate()
	root.add_child(sample)
	await process_frame
	await process_frame
	var hud: AstraeonInventoryHUD = sample.hud
	var state: AstraeonInventoryState = sample.inventory
	check(hud._slots.size() == 50, "40 bag slots plus ten views of the hotbar")
	var before: int = state.stack_at(0).count
	hud.slot_clicked(0, MOUSE_BUTTON_RIGHT)
	hud.slot_clicked(20, MOUSE_BUTTON_LEFT)
	check(state.stack_at(20).count == ceili(before / 2.0), "Right click half then left click deposit")
	hud.slot_clicked(0, MOUSE_BUTTON_LEFT)
	hud.slot_clicked(21, MOUSE_BUTTON_RIGHT)
	hud.slot_clicked(22, MOUSE_BUTTON_RIGHT)
	check(state.stack_at(21).count == 1 and state.stack_at(22).count == 1 and state.cursor_stack() != null, "Repeated right click distributes single items")
	hud.set_open(false)
	check(state.cursor_stack() == null and state.stack_at(0) == null, "Closing deletes carried stack without restoring source")
	for index: int in range(10):
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = KEY_0 if index == 9 else KEY_1 + index
		event.pressed = true
		hud._input(event)
		check(state.selected == index, "Hotbar key " + str(index))
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	hud._input(wheel)
	check(state.selected == 0, "Wheel wraps last to first")
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	hud._input(wheel)
	check(state.selected == 9, "Wheel wraps first to last")
	hud.set_open(true)
	for resolution: Vector2i in [Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(3840,2160), Vector2i(3440,1440)]:
		root.size = resolution
		await process_frame
		await process_frame
		var frame: Control = hud._bag.get_child(0) as Control
		check(hud.get_global_rect().encloses(frame.get_global_rect()), "Bag fits " + str(resolution))
		var first: Rect2 = hud._slots[0].get_global_rect()
		check(is_equal_approx(first.size.x, first.size.y), "Square slots " + str(resolution))
	hud.set_page(&"storage")
	hud.slot_clicked(20, MOUSE_BUTTON_LEFT)
	check(state.stack_at(20) == null and state.cursor_stack() != null, "Pickup immediately frees source")
	hud.slot_clicked(13, MOUSE_BUTTON_LEFT)
	check(state.stack_at(13) != null and state.cursor_stack() == null, "Click deposits carried stack")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1920,1080)
		await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://tmp/inventory-ui")
		root.get_texture().get_image().save_png("res://tmp/inventory-ui/backpack.png")
		hud.set_open(false)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/inventory-ui/hotbar.png")
	sample.queue_free()
	await process_frame
