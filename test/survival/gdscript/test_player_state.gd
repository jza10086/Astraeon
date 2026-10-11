extends Node
const CATALOG: AstraeonItemCatalog = preload("res://test/data/resources/item_reference/item_catalog.tres")
const LAYOUT: AstraeonInventoryDefinition = preload("res://game/data/inventory/resources/player_inventory.tres")
const Slots: Script = preload("res://game/core/gdscript/world_selection.gd")
var checks: int = 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)

func fresh() -> AstraeonInventoryState:
	var inventory: AstraeonInventoryState = AstraeonInventoryState.new()
	inventory.configure(CATALOG, LAYOUT)
	return inventory

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var inventory: AstraeonInventoryState = fresh()
	var state: AstraeonPlayerState = inventory.player_state
	check(state.health == 10 and state.hunger == 10 and not state.is_creative(), "Initial survival 10/10")
	check(not state.decrease_health(-1) and not state.increase_hunger(-2), "Reject negative amounts")
	check(state.decrease_health(3) and state.health == 7, "Health decrement")
	check(state.decrease_hunger(4) and state.hunger == 6, "Hunger decrement")
	check(state.set_mode(1) and state.health == 7 and state.hunger == 6, "Mode preserves stats")
	check(state.decrease_health(1) and state.decrease_hunger(1) and state.health == 6 and state.hunger == 5, "Creative direct APIs still decrement")
	check(state.increase_health(99) and state.increase_hunger(99) and state.health == 10 and state.hunger == 10, "Clamp upper bounds")
	check(state.decrease_health(99) and state.decrease_hunger(99) and state.health == 0 and state.hunger == 0, "Clamp zero without death")
	check(not state.set_mode(2), "Reject unknown mode")
	var original: Dictionary = state.snapshot()
	state.before_commit = func(_candidate: Dictionary) -> bool: return false
	check(not state.increase_health(1) and not state.set_mode(0) and state.snapshot() == original, "Failed state writes preserve all fields")
	state.before_commit = Callable()
	state.can_change = func() -> bool: return false
	check(not state.increase_hunger(1), "Busy guard")
	state.can_change = Callable()
	state.set_mode(0)
	inventory.insert(&"astraeon:dirt_item", 3)
	check(not inventory.creative_pick(&"astraeon:log_item") and not inventory.clone_to_cursor(0) and not inventory.clear_inventory(), "Survival blocks privileged APIs")
	inventory.click_slot(0)
	check(not inventory.discard_cursor() and inventory.cursor_stack().count == 3, "Survival cannot delete cursor")
	state.set_mode(1)
	check(inventory.cursor_stack().count == 3 and inventory.stack_at(0) == null, "Shared cursor across modes")
	check(inventory.creative_pick(&"astraeon:log_item", true), "Creative pick")
	var snapshot: Dictionary = inventory.snapshot()
	inventory.before_commit = func(_candidate: Dictionary, _context: Dictionary) -> bool: return false
	check(not inventory.creative_pick(&"astraeon:dirt_item") and not inventory.discard_cursor() and inventory.snapshot() == snapshot, "Failed cursor writes are atomic")
	inventory.before_commit = Callable()
	var directory: String = "res://tmp/survival-state/" + str(Time.get_ticks_usec())
	var identity: Dictionary = {"generation": 2, "seed": 42, "layout": 0, "world_id": "mode-test"}
	var store: AstraeonInventoryStore = AstraeonInventoryStore.new()
	check(store.open(directory, identity, inventory), "Initial player snapshot")
	state.increase_health(8)
	state.increase_hunger(6)
	inventory.commit_world({"position": Vector3i(-1, 40, -1), "state": "astraeon:air/default"})
	var restored: AstraeonInventoryState = fresh()
	var reader: AstraeonInventoryStore = AstraeonInventoryStore.new()
	check(reader.open(directory, identity, restored), "Read current format")
	check(restored.snapshot() == inventory.snapshot() and restored.player_state.snapshot() == state.snapshot() and reader.pending.size() == 1, "Cursor/stats/mode/edit round trip")
	check(state.set_mode(0), "Save mode switch")
	var latest: String = directory.path_join("inventory_" + ("a" if store._sequence % 2 == 0 else "b") + ".json")
	var file: FileAccess = FileAccess.open(latest, FileAccess.WRITE)
	file.store_string("interrupted")
	file.close()
	var recovered: AstraeonInventoryState = fresh()
	check(AstraeonInventoryStore.new().open(directory, identity, recovered) and recovered.player_state.is_creative() and recovered.cursor_stack().count == 64, "Alternate valid snapshot recovery")
	var old_directory: String = directory + "/old"
	DirAccess.make_dir_recursive_absolute(old_directory)
	var body: String = JSON.stringify({"version": 3, "world": identity})
	file = FileAccess.open(old_directory + "/inventory_a.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"body": body, "sha256": body.sha256_text()}))
	file.close()
	check(not AstraeonInventoryStore.new().open(old_directory, identity, fresh()), "Reject old inventory format")
	var created: Dictionary = Slots.create_new(directory + "/worlds/unused", directory + "/settings.cfg", "creative", 42, 0, 1)
	check(created.has("directory") and Slots.parameters(created.directory).initial_mode == 1, "Creation saves selected mode")
	var config: ConfigFile = ConfigFile.new()
	config.set_value("world", "format", 1)
	config.save(old_directory + "/world.cfg")
	check(Slots.parameters(old_directory).has("error"), "Reject old world format")
	# Native candidate plus carried removal are committed by the same guard.
	var drop_inventory: AstraeonInventoryState = fresh()
	drop_inventory.insert(&"astraeon:dirt_item", 2)
	drop_inventory.click_slot(0)
	var pool: RefCounted = ClassDB.instantiate("AstraeonDroppedItems")
	pool.call("configure", PackedStringArray(["astraeon:dirt_item"]), PackedInt32Array([64]), PackedByteArray([0, 1]))
	var drop_store: AstraeonInventoryStore = AstraeonInventoryStore.new()
	drop_store.dropped_items = pool
	check(drop_store.open(directory + "/drops", identity, drop_inventory), "Drop fixture")
	pool.call("spawn", "astraeon:dirt_item", 2, Vector3(0, 40, 0), Vector3.ZERO, 0.8)
	check(drop_inventory.consume_cursor(), "Commit staged drop with cursor removal")
	var saved: AstraeonInventoryState = fresh()
	var saved_pool: RefCounted = ClassDB.instantiate("AstraeonDroppedItems")
	saved_pool.call("configure", PackedStringArray(["astraeon:dirt_item"]), PackedInt32Array([64]), PackedByteArray([0, 1]))
	var saved_store: AstraeonInventoryStore = AstraeonInventoryStore.new()
	saved_store.dropped_items = saved_pool
	check(saved_store.open(directory + "/drops", identity, saved) and saved.cursor_stack() == null and int(saved_pool.call("get_count")) == 1, "Drop persisted exactly once")
	print("PLAYER_STATE_TEST ", JSON.stringify({"checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
