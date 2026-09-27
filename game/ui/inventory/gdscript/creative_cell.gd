extends Control
const ItemIcon: GDScript = preload("res://game/ui/inventory/gdscript/item_icon.gd")
var item: AstraeonItemDefinition
var inventory: AstraeonInventoryState
var hovered: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(60, 60)
	tooltip_text = item.display_name + "\n" + String(item.key) + "\n" + " · ".join(item.search_tags) + "\n左键拿一个 · 中键拿一组 · 右键移除手上一个"
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void: hovered = true; queue_redraw())
	mouse_exited.connect(func() -> void: hovered = false; queue_redraw())

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("dce0e4") if hovered else Color("5b5d62"))
	draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color("898b90") if hovered else Color("797b80"))
	ItemIcon.draw_stack(self, AstraeonItemStack.new(item, 1))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				inventory.creative_pick(item.key)
			MOUSE_BUTTON_MIDDLE:
				inventory.creative_pick(item.key, true)
			MOUSE_BUTTON_RIGHT:
				inventory.discard_cursor(true)
			_:
				return
		accept_event()
