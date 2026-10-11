extends Node
## Isolated interactive inventory sample: no world, physics, save file or native terrain required.
var inventory: AstraeonInventoryState
var hud: AstraeonInventoryHUD

func _ready() -> void:
	inventory = AstraeonInventoryState.new()
	inventory.player_state.set_mode(AstraeonPlayerState.Mode.CREATIVE)
	inventory.configure(preload("res://test/data/resources/item_reference/item_catalog.tres"), preload("res://game/data/inventory/resources/player_inventory.tres"))
	for key: StringName in inventory.items:
		inventory.insert(key, 96 if key == &"astraeon:dirt_item" else mini(32, inventory.items[key].max_stack))
	inventory.quick_move(1)
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var background: ColorRect = ColorRect.new()
	background.color = Color("253343")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(background)
	hud = preload("res://game/ui/inventory/scenes/inventory_hud.tscn").instantiate() as AstraeonInventoryHUD
	hud.inventory = inventory
	hud.drop_cursor = inventory.discard_cursor
	hud.can_interact = func() -> bool: return true
	hud.open_changed.connect(func(opened: bool) -> void: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if opened else Input.MOUSE_MODE_CAPTURED)
	layer.add_child(hud)
	hud.set_open(true)
