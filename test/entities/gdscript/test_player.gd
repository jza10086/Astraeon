extends SceneTree
## Real physics and imported-animation regression, no editor import or benchmark.
const WORLD: PackedScene = preload("res://game/core/main.tscn")
var failures: Array[String] = []
var checks: int = 0
var player: CharacterMotor
var animator: AnimationPlayer
var world: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _frames(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame

func _place(at: Vector3) -> void:
	player.position = at
	player.reset_motion()
	await _frames(15)

func _run() -> void:
	create_timer(60.0).timeout.connect(_on_timeout)
	world = WORLD.instantiate() as Node3D
	player = world.get_node("Player") as CharacterMotor
	player.get_node("Controller").set("input_enabled", false)
	root.add_child(world)
	animator = player.get_node("Visual/Model/AnimationPlayer") as AnimationPlayer
	await _frames(30)
	_check(player.is_on_floor() and absf(player.position.y) < 0.02, "Spawn settles on ground")
	_check(animator.current_animation == "Idle", "Idle animation plays")
	var origin: Vector3 = player.position
	player.move_intent = Vector3.RIGHT
	await _frames(60)
	var straight_distance: float = player.position.distance_to(origin)
	_check(straight_distance > 0.9 and straight_distance < 1.2, "Movement matches 1.1 m/s")
	_check(animator.current_animation == "Run" and animator.is_playing(), "Run animation plays")
	player.move_intent = Vector3.ZERO
	await _frames(15)
	_check(Vector2(player.velocity.x, player.velocity.z).length() < 0.01, "Braking stops movement")
	await _place(Vector3(0, 0.1, 3))
	origin = player.position
	player.move_intent = Vector3(1, 0, 1)
	await _frames(60)
	_check(absf(player.position.distance_to(origin) - straight_distance) < 0.04, "Diagonal movement is normalized")
	await _place(Vector3(0, 0.1, 3))
	player.jump_requested = true
	var peak: float = 0.0
	var jump_seen: bool = false
	for frame: int in range(60):
		await _frames(1)
		peak = maxf(peak, player.position.y)
		jump_seen = jump_seen or animator.current_animation == "Jump"
		if frame == 15:
			player.jump_requested = true
	_check(peak > 1.15 and peak < 1.4, "Jump height and no double jump")
	_check(jump_seen, "Jump animation plays while airborne")
	_check(player.is_on_floor() and animator.current_animation == "Idle", "Physics landing restores Idle")
	await _place(Vector3(-2, 0.1, 0))
	player.move_intent = Vector3.LEFT
	await _frames(90)
	_check(player.position.x > -2.47 and player.position.x < -2.35, "Wall blocks capsule")
	_check(animator.current_animation == "Idle", "Blocked character stops running animation")
	await _place(Vector3(0, 0.1, -3.5))
	player.jump_requested = true
	peak = 0.0
	for frame: int in range(45):
		await _frames(1)
		peak = maxf(peak, player.position.y)
	_check(peak < 0.24 and player.is_on_floor(), "Low ceiling blocks jump and player lands")
	await _place(Vector3(0.65, 0.1, 0))
	player.move_intent = Vector3.RIGHT
	player.jump_requested = true
	await _frames(60)
	_check(player.is_on_floor() and absf(player.position.y - 1.0) < 0.03, "Jump reaches one-meter platform")
	await _place(Vector3(3.7, 0.1, -1.1))
	player.move_intent = Vector3.FORWARD
	await _frames(90)
	_check(player.is_on_floor() and player.position.y > 0.25, "Walk up slope without falling through")
	await _place(Vector3(2, 2.5, 0))
	await _frames(45)
	_check(player.is_on_floor() and absf(player.position.y - 1.0) < 0.03, "Platform collision supports player")
	player.move_intent = Vector3.BACK
	await _frames(100)
	player.move_intent = Vector3.ZERO
	await _frames(45)
	_check(player.is_on_floor() and player.position.y < 0.03, "Walking off platform falls and lands")
	await _place(Vector3(0, 0.1, 3))
	player.position.y = -21.0
	await _frames(20)
	_check(player.is_on_floor() and player.position.distance_to(Vector3(0, 0, 3)) < 0.03, "Void respawn resets player")
	var skeleton: Skeleton3D = player.find_child("Skeleton3D", true, false) as Skeleton3D
	_check(skeleton != null and skeleton.get_bone_count() == 42, "Imported skeleton remains intact")
	if DisplayServer.get_name() != "headless":
		await _test_window_input()
	else:
		print("ENTITY_TEST window input skipped: headless display cannot capture mouse")
	print("ENTITY_TEST checks=%d failures=%d" % [checks, failures.size()])
	world.queue_free()
	await _frames(2)
	quit(0 if failures.is_empty() else 1)

func _on_timeout() -> void:
	push_error("ENTITY_TEST timed out")
	quit(1)

func _test_window_input() -> void:
	var origin: Vector3 = player.position
	var controller: Node = player.get_node("Controller")
	controller.set("input_enabled", true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	origin = player.position
	Input.action_press("move_forward")
	await _frames(30)
	Input.action_release("move_forward")
	await _frames(10)
	_check(player.position.z < origin.z - 0.4, "Player input drives motor")
	Input.action_press("jump")
	await _frames(5)
	Input.action_release("jump")
	_check(player.position.y > 0.2, "Player jump input drives physics")
	await _frames(60)
	var release: InputEventAction = InputEventAction.new()
	release.action = "release_mouse"
	release.pressed = true
	controller.call("_unhandled_input", release)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Escape releases mouse")
	Input.action_press("move_forward")
	origin = player.position
	await _frames(15)
	Input.action_release("move_forward")
	_check(player.position.distance_to(origin) < 0.02, "Released mouse disables movement")
	var capture: InputEventAction = InputEventAction.new()
	capture.action = "capture_mouse"
	capture.pressed = true
	controller.call("_unhandled_input", capture)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Click recaptures mouse")
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(100, 50)
	controller.call("_unhandled_input", motion)
	_check(absf(player.get_node("CameraPivot").get("rotation").y + 0.25) < 0.01, "Mouse rotates camera")
	controller.set("input_enabled", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
