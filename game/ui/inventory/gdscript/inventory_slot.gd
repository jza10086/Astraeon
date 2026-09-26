class_name AstraeonInventorySlot
extends Control
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
	tooltip_text = "空槽" if stack == null else stack.item.display_name + " × " + str(stack.count) + "
" + String(stack.item.key)
	queue_redraw()

func _draw() -> void:
	var selected: bool = inventory.selected == index
	draw_rect(Rect2(Vector2.ZERO, size), Color("22252a"))
	draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), Color("555960") if hovered else Color("3a3e44"))
	draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), Color("f3e4bd") if selected else Color("86898d"), false, 3.0 if selected else 1.0)
	var stack: AstraeonItemStack = inventory.stack_at(index)
	if stack != null:
		if stack.item.icon != null:
			draw_texture_rect(stack.item.icon, Rect2(Vector2(13, 10), Vector2(34, 34)), false)
		else:
			var tint: Color = stack.item.icon_color
			draw_colored_polygon(PackedVector2Array([Vector2(12, 20),Vector2(30, 10),Vector2(48, 20),Vector2(30, 30)]), tint.lightened(0.15))
			draw_colored_polygon(PackedVector2Array([Vector2(12, 20),Vector2(30, 30),Vector2(30, 49),Vector2(12, 39)]), tint.darkened(0.2))
			draw_colored_polygon(PackedVector2Array([Vector2(30, 30),Vector2(48, 20),Vector2(48, 39),Vector2(30, 49)]), tint)
		if stack.count > 1:
			var text: String = str(stack.count)
			var x: float = size.x - 5 - ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
			draw_string(ThemeDB.fallback_font, Vector2(x + 1, size.y - 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color.BLACK)
			draw_string(ThemeDB.fallback_font, Vector2(x, size.y - 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color.WHITE)
	if index < 10:
		draw_string(ThemeDB.fallback_font, Vector2(5, 15), str((index + 1) % 10), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("d1d1d1"))
	if in_bag and panel.source_slot == index:
		draw_rect(Rect2(Vector2(5, 5), size - Vector2(10, 10)), Color("82c6ef"), false, 2.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			panel.slot_clicked(index, event.button_index == MOUSE_BUTTON_RIGHT, event.shift_pressed)
			accept_event()

func _get_drag_data(_position: Vector2) -> Variant:
	if not in_bag or inventory.locked:
		return null
	var stack: AstraeonItemStack = inventory.stack_at(index)
	if stack == null:
		return null
	var label: Label = Label.new()
	label.text = stack.item.display_name + " × " + str(stack.count)
	label.add_theme_font_size_override("font_size", 22)
	set_drag_preview(label)
	panel.cancel_source()
	return {"inventory": inventory, "source": index, "revision": inventory.revision, "count": stack.count}

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return in_bag and data is Dictionary and data.get("inventory") == inventory and data.get("revision") == inventory.revision and int(data.get("source", -1)) != index

func _drop_data(_position: Vector2, data: Variant) -> void:
	inventory.move(int(data.source), index, int(data.count), int(data.revision))
	panel.cancel_source()
