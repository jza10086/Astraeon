extends Control
## Centered aiming guide; visibility follows gameplay input without consuming mouse events.
@export var world: Node

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	if world == null:
		push_error("Crosshair requires a world reference.")
		set_process(false)
		return
	resized.connect(queue_redraw)

func _process(_delta: float) -> void:
	visible = world.ready_to_play and not world.failed and not get_tree().paused and bool(world.controller.get("input_enabled")) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func _draw() -> void:
	var center: Vector2 = (size * 0.5).floor()
	# 24 px across at the 1080p UI baseline, with a 4 px central aiming gap.
	var arms: Array[Rect2] = [
		Rect2(-12, -1, 10, 2), Rect2(2, -1, 10, 2),
		Rect2(-1, -12, 2, 10), Rect2(-1, 2, 2, 10)]
	for arm: Rect2 in arms:
		draw_rect(Rect2(center + arm.position - Vector2.ONE, arm.size + Vector2(2, 2)), Color(0, 0, 0, 0.8))
	for arm: Rect2 in arms:
		draw_rect(Rect2(center + arm.position, arm.size), Color(1, 1, 1, 0.95))
