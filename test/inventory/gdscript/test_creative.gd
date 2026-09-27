extends SceneTree
var checks: int = 0
var failures: Array[String] = []
const CATALOG: AstraeonItemCatalog = preload("res://game/data/item/resources/item_catalog.tres")
const LAYOUT: AstraeonInventoryDefinition = preload("res://game/data/inventory/resources/player_inventory.tres")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
func fresh() -> AstraeonInventoryState:
	var state: AstraeonInventoryState = AstraeonInventoryState.new()
	state.configure(CATALOG, LAYOUT)
	return state
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	check(CATALOG.validate().is_empty(), "Catalog validation")
	check(CATALOG.find_blocks().size() == 5, "All five blocks without axis duplicates")
	check(CATALOG.find_blocks(&"astraeon_natural").size() == 3, "Natural group")
	check(CATALOG.find_blocks(&"astraeon_functional", "灯").size() == 1, "Group plus tag")
	check(CATALOG.find_blocks(&"", "WOOD 朝向").size() == 1, "Case-insensitive AND terms")
	check(CATALOG.find_blocks(&"", "astraeon_grass").size() == 1, "Stable ID search")
	check(CATALOG.find_blocks(&"", "不存在").is_empty(), "Empty result")
	var copy: AstraeonItemCatalog = AstraeonItemCatalog.new()
	copy.definitions = [CATALOG.definitions[0].duplicate()]
	copy.definitions[0].creative_group = &"unknown"
	check(not copy.validate().is_empty(), "Reject unknown group")
	copy = AstraeonItemCatalog.new()
	copy.definitions = [CATALOG.definitions[0].duplicate()]
	copy.definitions[0].search_tags = PackedStringArray(["wood", "WOOD"])
	check(not copy.validate().is_empty(), "Reject repeated tags")
	var state: AstraeonInventoryState = fresh()
	state.insert(&"astraeon_dirt_item", 2560)
	var full: Dictionary = state.snapshot()
	check(state.creative_pick(&"astraeon_log_item") and state.cursor_stack().count == 1 and state.snapshot() == full, "Full backpack can carry one extra item")
	state.creative_pick(&"astraeon_log_item")
	check(state.cursor_stack().count == 2, "Repeated click adds one")
	state.creative_pick(&"astraeon_log_item", true)
	check(state.cursor_stack().count == 64 and state.snapshot() == full, "Middle copies max stack without reserving space")
	state.creative_pick(&"astraeon_log_item")
	check(state.cursor_stack().count == 64, "Cursor respects max stack")
	var isolated: AstraeonItemStack = state.cursor_stack()
	isolated.count = 1
	check(state.cursor_stack().count == 64, "Cursor readers get copies")
	check(state.click_slot(0) and state.stack_at(0).item.key == &"astraeon_log_item" and state.cursor_stack().item.key == &"astraeon_dirt_item", "Full bag click swaps without loss")
	state.discard_cursor(true)
	check(state.cursor_stack().count == 63, "Right removal deletes one")
	state.discard_cursor()
	check(state.cursor_stack() == null, "Discard entire cursor")
	state = fresh()
	state.insert(&"astraeon_dirt_item", 5)
	check(state.click_slot(0, true) and state.cursor_stack().count == 3 and state.stack_at(0).count == 2, "Half pickup rounds up and removes immediately")
	check(state.click_slot(1, true) and state.cursor_stack().count == 2 and state.stack_at(1).count == 1, "Right deposit places one")
	check(state.click_slot(0) and state.cursor_stack() == null and state.stack_at(0).count == 4, "Merge carried remainder")
	state.clone_to_cursor(0)
	check(state.cursor_stack().count == 64 and state.stack_at(0).count == 4, "Middle clone preserves source")
	state.click_slot(0)
	check(state.stack_at(0).count == 64 and state.cursor_stack().count == 4, "Partial merge retains excess on cursor")
	check(not state.click_slot(0) and state.cursor_stack().count == 4, "Full same-type target leaves cursor unchanged")
	state.locked = true
	check(not state.creative_pick(&"astraeon_log_item") and not state.click_slot(2), "Save lock rejects pickup and deposit")
	state.discard_cursor()
	check(state.cursor_stack() == null, "Close may discard transient cursor during save")
	state.locked = false
	var stored: Dictionary = state.snapshot()
	state.before_commit = func(_snapshot: Dictionary, _context: Dictionary) -> bool: return false
	check(not state.click_slot(0) and state.cursor_stack() == null and state.snapshot() == stored, "Failed pickup does not duplicate")
	state.creative_pick(&"astraeon_log_item", true)
	check(not state.click_slot(0) and state.cursor_stack().count == 64 and state.cursor_stack().item.key == &"astraeon_log_item" and state.snapshot() == stored, "Failed swap keeps both sides unchanged")
	check(not state.clear_inventory() and state.cursor_stack() != null and state.snapshot() == stored, "Failed trash-all is atomic")
	state.before_commit = Callable()
	check(state.clear_inventory() and state.cursor_stack() == null and state.capacity(&"astraeon_dirt_item") == 2560, "Trash-all clears stored and cursor")
	state.insert(&"astraeon_dirt_item", 3)
	state.creative_pick(&"astraeon_log_item")
	check(state.quick_move(0) and state.cursor_stack().count == 1, "Quick move preserves independent cursor")
	# Pickup is already durable; restoring a snapshot never restores a transient cursor.
	var directory: String = "res://tmp/cursor-save/" + str(Time.get_ticks_usec())
	var store: AstraeonInventoryStore = AstraeonInventoryStore.new()
	var identity: Dictionary = {"generation":2,"seed":10,"layout":0,"states":"cursor-test"}
	check(store.open(directory, identity, state), "Open cursor persistence fixture")
	state.discard_cursor()
	check(state.click_slot(10), "Durable pickup")
	var restored: AstraeonInventoryState = fresh()
	check(AstraeonInventoryStore.new().open(directory, identity, restored) and restored.stack_at(10) == null and restored.cursor_stack() == null, "Reopen does not duplicate picked-up items")
	await test_ui()
	print("CREATIVE_TEST ", JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func test_ui() -> void:
	var sample: Node = load("res://test/inventory/scenes/inventory_sample.tscn").instantiate()
	root.add_child(sample)
	await process_frame
	await process_frame
	var hud: AstraeonInventoryHUD = sample.hud
	var state: AstraeonInventoryState = sample.inventory
	var browser: VBoxContainer = hud.creative_browser
	check(hud._search_tab.get_global_rect().end.x == hud._storage_tab.get_global_rect().end.x and hud._search_tab.global_position.y < hud._storage_tab.global_position.y, "Search upper right and storage lower right aligned")
	hud.set_page(&"search")
	await process_frame
	check(browser.results.size() == 5 and browser.search.visible, "Search page initially lists all blocks")
	browser.search.text = "灯"
	browser.refresh()
	check(browser.results.size() == 1, "Search UI filter")
	var previous: int = state.selected
	for key: Key in [KEY_E, KEY_2]:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = key
		event.keycode = key
		event.pressed = true
		hud._input(event)
	check(hud.opened and state.selected == previous, "Search typing does not close or select hotbar")
	hud.set_page(&"astraeon_building")
	await process_frame
	check(browser.results.size() == 1 and not browser.search.visible, "Category ignores search query")
	var cell: Control = browser._grid.get_child(0)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.pressed = true
	event.button_index = MOUSE_BUTTON_LEFT
	var before: Dictionary = state.snapshot()
	cell._gui_input(event)
	check(state.cursor_stack().count == 1 and state.snapshot() == before, "Catalog left takes one onto cursor only")
	event.button_index = MOUSE_BUTTON_MIDDLE
	cell._gui_input(event)
	check(state.cursor_stack().count == 64 and state.snapshot() == before, "Catalog middle takes full stack onto cursor")
	hud.set_page(&"storage")
	check(state.cursor_stack().count == 64 and hud._storage.visible, "Changing tab preserves held stack")
	hud.slot_clicked(20, MOUSE_BUTTON_RIGHT)
	check(state.stack_at(20).count == 1 and state.cursor_stack().count == 63, "Click storage deposits one")
	hud.slot_clicked(21, MOUSE_BUTTON_LEFT)
	check(state.stack_at(21).count == 63 and state.cursor_stack() == null, "Click storage deposits rest")
	hud.slot_clicked(21, MOUSE_BUTTON_LEFT)
	check(state.stack_at(21) == null and hud._cursor_preview.visible, "Owned pickup follows pointer without reserving slot")
	event.button_index = MOUSE_BUTTON_RIGHT
	hud._trash_input(event)
	check(state.cursor_stack().count == 62, "Trash right removes one")
	hud.set_open(false)
	check(state.cursor_stack() == null and state.stack_at(21) == null, "Closing deletes cursor instead of returning it")
	hud.set_open(true)
	state.creative_pick(&"astraeon_log_item", true)
	event.button_index = MOUSE_BUTTON_LEFT
	hud._background_input(event)
	check(state.cursor_stack() == null, "Click outside deletes held stack")
	# Send pointer events through the viewport, not only directly to callback methods.
	await pointer_click(hud._tabs[&"astraeon_building"], MOUSE_BUTTON_LEFT)
	await process_frame
	check(hud.page == &"astraeon_building", "Viewport click selects category tab")
	await pointer_click(browser._grid.get_child(0), MOUSE_BUTTON_MIDDLE)
	check(state.cursor_stack() != null and state.cursor_stack().count == 64, "Viewport middle-click picks a full stack")
	await pointer_click(hud._storage_tab, MOUSE_BUTTON_LEFT)
	check(hud.page == &"storage" and state.cursor_stack() != null, "Viewport tab click preserves cursor")
	await pointer_click(hud._slots[19], MOUSE_BUTTON_LEFT)
	check(state.stack_at(29) != null and state.cursor_stack() == null, "Viewport click deposits despite cursor overlay")
	await pointer_click(hud._slots[19], MOUSE_BUTTON_LEFT)
	await pointer_click(hud._trash, MOUSE_BUTTON_LEFT)
	check(state.stack_at(29) == null and state.cursor_stack() == null, "Viewport trash click deletes held item")
	for resolution: Vector2i in [Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(3840,2160), Vector2i(3440,1440)]:
		root.size = resolution
		await process_frame
		await process_frame
		check(hud.get_global_rect().encloses((hud._bag.get_child(0) as Control).get_global_rect()), "Layout fits " + str(resolution))
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1920,1080)
		hud.set_page(&"search")
		browser.search.text = ""
		browser.refresh()
		state.creative_pick(&"astraeon_log_item", true)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/inventory-work/cursor_creative.png")
		hud.set_page(&"storage")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/inventory-work/cursor_storage.png")
	sample.queue_free()
	await process_frame

func pointer_click(control: Control, button: MouseButton) -> void:
	await process_frame
	var point: Vector2 = control.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = point
		event.global_position = point
		Input.parse_input_event(event)
		await process_frame
