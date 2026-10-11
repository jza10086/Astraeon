extends SceneTree
var checks: int = 0
var failures: Array[String] = []
const KEYS: PackedStringArray = ["astraeon:sword", "astraeon:shovel", "astraeon:pickaxe", "astraeon:axe"]
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var source: AstraeonItemCatalog = load("res://test/data/resources/item_reference/item_catalog.tres")
	check(source.validate().is_empty(), "Source catalog valid")
	check(source.find_items(&"astraeon_tools").size() == 4, "Four tool definitions")
	check(source.find_items(&"", "PICKAXE").size() == 1, "Tool search by English tag")
	var content: AstraeonWorldContent = AstraeonWorldContent.new()
	check(content.build(PackedStringArray(["res://game/data/content/packages/astraeon.aebpack"])), "Compiled content builds: " + content.error)
	if content.item_catalog == null:
		finish()
		return
	check(content.item_catalog.validate().is_empty() and content.item_catalog.definitions.size() == 9, "Compiled catalog preserves nine items")
	var state: AstraeonInventoryState = AstraeonInventoryState.new()
	state.player_state.set_mode(AstraeonPlayerState.Mode.CREATIVE)
	state.configure(content.item_catalog, load("res://game/data/inventory/resources/player_inventory.tres"))
	for key: String in KEYS:
		var item: AstraeonItemDefinition = state.items[StringName(key)]
		check(item.block == null and item.state_key(Vector3i.UP).is_empty() and item.max_stack == 1, "Nonplaceable singleton " + key)
		check(item.has_meta("content_icon"), "Compiled icon " + key)
		check(state.creative_pick(StringName(key), true) and state.cursor_stack().count == 1, "Middle pick respects singleton " + key)
		check(state.click_slot(KEYS.find(key)) and state.cursor_stack() == null, "Store tool " + key)
	check(state.insert(&"astraeon:sword", 2) == 0 and state.stack_at(4).count == 1 and state.stack_at(5).count == 1, "Tools occupy separate slots")
	state.click_slot(0)
	check(not state.click_slot(4) and state.cursor_stack().count == 1 and state.stack_at(4).count == 1, "Tools cannot merge above one")
	state.click_slot(1)
	check(state.stack_at(1).item.key == &"astraeon:sword" and state.cursor_stack().item.key == &"astraeon:shovel", "Different tools swap")
	state.click_slot(0)
	var store: AstraeonInventoryStore = AstraeonInventoryStore.new()
	var directory: String = "res://tmp/tool-items/" + str(Time.get_ticks_usec())
	var identity: Dictionary = {"generation":2,"seed":123,"layout":0,"world_id":"tools-test"}
	check(store.open(directory, identity, state) and store.checkpoint(), "Save tool inventory")
	var restored: AstraeonInventoryState = AstraeonInventoryState.new()
	restored.configure(content.item_catalog, load("res://game/data/inventory/resources/player_inventory.tres"))
	check(AstraeonInventoryStore.new().open(directory, identity, restored) and restored.snapshot() == state.snapshot(), "Tool save round trip")
	var interaction: AstraeonInventoryInteraction = AstraeonInventoryInteraction.new()
	interaction.configure(null, state)
	check(interaction.drops.size() == 5, "Tools do not register voxel drop mappings")
	var hud: AstraeonInventoryHUD = load("res://game/ui/inventory/scenes/inventory_hud.tscn").instantiate()
	hud.inventory = state
	hud.drop_cursor = state.discard_cursor
	root.add_child(hud)
	hud.set_open(true)
	hud.set_page(&"astraeon_tools")
	await process_frame
	check(hud.creative_browser.results.size() == 4, "Tools page uses compiled catalog")
	var hashes: PackedStringArray = []
	for key: String in KEYS:
		hashes.append(String(state.items[StringName(key)].get_meta("content_icon")))
	content.bundle.visuals.call("request", "tool-test", hashes)
	var deadline: int = Time.get_ticks_msec() + 5000
	while not content.bundle.visuals.call("is_ready", hashes) and Time.get_ticks_msec() < deadline:
		content.bundle.visuals.call("commit")
		await process_frame
	check(content.bundle.visuals.call("is_ready", hashes), "Compiled tool icons become resident")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/item-tools/tools.png")
	content.bundle.visuals.call("release", "tool-test")
	hud.queue_free()
	await process_frame
	finish()
func finish() -> void:
	print("TOOL_ITEMS_TEST ", JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)

