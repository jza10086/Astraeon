class_name AstraeonInventorySlot
extends Control
const ItemIcon: GDScript = preload("res://game/ui/inventory/gdscript/item_icon.gd")
var index: int = 0
var inventory: AstraeonInventoryState
var panel: Control
var in_bag: bool = false
var hovered: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(60, 60)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void: hovered = true; queue_redraw())
	mouse_exited.connect(func() -> void: hovered = false; queue_redraw())
	inventory.changed.connect(refresh)
	refresh()

func refresh() -> void:
	var stack: AstraeonItemStack = inventory.stack_at(index)
	tooltip_text = "空槽" if stack == null else stack.item.display_name + " × " + str(stack.count) + "\n" + String(stack.item.key)
	queue_redraw()

func _draw() -> void:
	var selected: bool = inventory.selected == index
	draw_rect(Rect2(Vector2.ZERO, size), Color("22252a"))
	draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), Color("73777d") if hovered else Color("65676c"))
	draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), Color("f3e4bd") if selected else Color("a5a7aa"), false, 3.0 if selected else 1.0)
	ItemIcon.draw_stack(self, inventory.stack_at(index))
	if index < 10:
		draw_string(ThemeDB.fallback_font, Vector2(5, 15), str((index + 1) % 10), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("eeeeee"))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			panel.slot_clicked(index, event.button_index, event.shift_pressed)
			accept_event()
