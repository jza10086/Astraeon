extends SceneTree
var checks: int = 0
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var catalog: AstraeonItemCatalog = load("res://game/data/item/resources/item_catalog.tres")
	check(catalog.validate().is_empty(), "Catalog validation")
	check(catalog.find_blocks().size() == 5, "All five blocks without orientation duplicates")
	check(catalog.find_blocks(&"astraeon_natural").size() == 3, "Natural group")
	check(catalog.find_blocks(&"astraeon_functional", "灯").size() == 1, "Group plus tag")
	check(catalog.find_blocks(&"", "WOOD 朝向").size() == 1, "Case-insensitive AND terms")
	check(catalog.find_blocks(&"", "astraeon_grass").size() == 1, "Stable ID search")
	check(catalog.find_blocks(&"", "不存在").is_empty(), "Empty result")
	var copy: AstraeonItemCatalog = AstraeonItemCatalog.new()
	copy.definitions = [catalog.definitions[0].duplicate()]
	copy.definitions[0].creative_group = &"unknown"
	check(not copy.validate().is_empty(), "Reject unknown group")
	copy = AstraeonItemCatalog.new()
	copy.definitions = [catalog.definitions[0].duplicate()]
	copy.definitions[0].search_tags = PackedStringArray(["wood", "WOOD"])
	check(not copy.validate().is_empty(), "Reject repeated tags")
	var sample: Node = load("res://test/inventory/scenes/inventory_sample.tscn").instantiate()
	root.add_child(sample)
	await process_frame
	var hud: AstraeonInventoryHUD = sample.get("hud") as AstraeonInventoryHUD
	if hud == null:
		# The sample owns its HUD via a direct public variable.
		hud = sample.get("hud")
	var browser: VBoxContainer = hud.creative_browser
	browser.get_parent().current_tab = 1
	await process_frame
	check(browser.visible and browser.results.size() == 5, "Creative page shows all blocks")
	browser.select_group(&"astraeon_building")
	check(browser.results.size() == 1, "Group UI filter")
	browser.select_group(&"")
	browser.search.text = "灯"
	browser.refresh()
	check(browser.results.size() == 1, "Search UI filter")
	browser.search.grab_focus()
	await process_frame
	var old_selection: int = hud.inventory.selected
	for key: Key in [KEY_E, KEY_2]:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = key
		event.keycode = key
		event.pressed = true
		hud._input(event)
	check(hud.opened and hud.inventory.selected == old_selection, "Typing does not close or switch hotbar")
	var before: int = hud.inventory.capacity(&"astraeon_log_item")
	check(browser.grant(&"astraeon_log_item"), "Grant stack")
	check(hud.inventory.capacity(&"astraeon_log_item") == before - 64, "Grant exactly 64")
	hud.inventory.locked = true
	check(not browser.grant(&"astraeon_log_item"), "Reject while saving")
	hud.inventory.locked = false
	hud.inventory.before_commit = func(_snapshot: Dictionary, _context: Dictionary) -> bool: return false
	check(not browser.grant(&"astraeon_log_item"), "Reject durable guard failure")
	hud.inventory.before_commit = Callable()
	hud.inventory.insert(&"astraeon_dirt_item", 99999)
	check(browser.grant(&"astraeon_log_item"), "Partial capacity grants only available space")
	var full_snapshot: Dictionary = hud.inventory.snapshot()
	check(not browser.grant(&"astraeon_log_item") and hud.inventory.snapshot() == full_snapshot, "Full inventory preserves contents")
	browser.search.text = ""
	browser.refresh()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/inventory-work/creative.png")
	print("CREATIVE_TEST ", JSON.stringify({"checks":checks,"failures":failures}))
	sample.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
