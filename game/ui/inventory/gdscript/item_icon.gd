extends Control
## Shared lightweight icon painter for owned slots, catalog cells and the mouse cursor.
var stack: AstraeonItemStack

func _ready() -> void:
	custom_minimum_size = Vector2(60, 60)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	draw_stack(self, stack)

static func draw_stack(target: Control, value: AstraeonItemStack) -> void:
	if value == null:
		return
	if value.item.icon != null:
		target.draw_texture_rect(value.item.icon, Rect2(Vector2(10, 8), Vector2(40, 40)), false)
	else:
		var tint: Color = value.item.icon_color
		target.draw_colored_polygon(PackedVector2Array([Vector2(12, 20),Vector2(30, 10),Vector2(48, 20),Vector2(30, 30)]), tint.lightened(0.15))
		target.draw_colored_polygon(PackedVector2Array([Vector2(12, 20),Vector2(30, 30),Vector2(30, 49),Vector2(12, 39)]), tint.darkened(0.2))
		target.draw_colored_polygon(PackedVector2Array([Vector2(30, 30),Vector2(48, 20),Vector2(48, 39),Vector2(30, 49)]), tint)
	if value.count > 1:
		var text: String = str(value.count)
		var x: float = 55 - ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		target.draw_string(ThemeDB.fallback_font, Vector2(x + 1, 55), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color.BLACK)
		target.draw_string(ThemeDB.fallback_font, Vector2(x, 54), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color.WHITE)
