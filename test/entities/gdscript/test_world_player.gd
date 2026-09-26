extends SceneTree
## Integration smoke test using an isolated temporary native world.
const WORLD: PackedScene = preload("res://game/core/main.tscn")
var world: Node3D
var failed: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/basic_voxel_" + name + ".png")

func _run() -> void:
	create_timer(90.0).timeout.connect(_timeout)
	world = WORLD.instantiate() as Node3D
	world.set("world_directory", "res://tmp/basic_voxel_entity_world")
	world.set("shading_settings_path", "res://tmp/basic_voxel_entity_settings.cfg")
	world.set("biome_layout", 1)
	var player: CharacterMotor = world.get_node("Player") as CharacterMotor
	player.get_node("Controller").set("input_enabled", false)
	root.add_child(world)
	while not bool(world.get("ready_to_play")):
		await process_frame
	await _ticks(30)
	_check(player.is_on_floor(), "Native world spawn has collision")
	var start: Vector3 = player.position
	var animator: AnimationPlayer = player.get_node("Visual/Model/AnimationPlayer") as AnimationPlayer
	await _capture("world_idle")
	player.move_intent = Vector3.RIGHT
	await _ticks(40)
	_check(animator.current_animation == "Run", "Native world walk animation")
	await _capture("world_walk")
	player.sprint_requested = true
	await _ticks(40)
	_check(animator.current_animation == "Sprint", "Native world sprint animation")
	await _capture("world_run")
	player.jump_requested = true
	await _ticks(12)
	_check(not player.is_on_floor() and animator.assigned_animation == "JumpStart", "Native world jump")
	await _capture("world_jump")
	player.move_intent = Vector3.ZERO
	player.sprint_requested = false
	await _ticks(60)
	_check(player.is_on_floor(), "Native world landing collision")
	_check(player.position.distance_to(start) > 3.0, "Native world player moved")
	world.call("save_world", false)
	while bool(world.get("saving")):
		await process_frame
	print("BASIC_VOXEL_WORLD_TEST failures=%d" % int(failed))
	world.queue_free()
	await _ticks(3)
	quit(1 if failed else 0)

func _timeout() -> void:
	push_error("BASIC_VOXEL_WORLD_TEST timeout")
	quit(1)
