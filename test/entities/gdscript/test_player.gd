extends SceneTree
## Real physics and imported-animation regression, no editor import or benchmark.
const WORLD: PackedScene = preload("res://test/entities/scenes/player_playground.tscn")
var failures: Array[String] = []
var checks: int = 0
var player: CharacterMotor
var animator: AnimationPlayer
var world: Node3D
var model_id: StringName = &"basic_voxel"

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
	var runtime: Node = root.get_node_or_null("MCPRuntimeServer")
	if runtime != null:
		runtime.call("_stop_server")
	create_timer(60.0).timeout.connect(_on_timeout)
	world = WORLD.instantiate() as Node3D
	player = world.get_node("Player") as CharacterMotor
	player.get_node("Visual").set("model_id", model_id)
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
	_check(straight_distance > 3.8 and straight_distance < 4.35, "Movement matches 4.3 m/s")
	_check(animator.current_animation == "Run" and animator.is_playing(), "Run animation plays at normal movement speed")
	player.sprint_requested = true
	await _frames(30)
	_check(absf(player.velocity.x - 5.6) < 0.02, "Sprint reaches 5.6 m/s")
	_check(animator.current_animation == "Sprint" and animator.is_playing(), "Sprint animation plays at sprint speed")
	player.sprint_requested = false
	player.move_intent = Vector3.ZERO
	await _frames(20)
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
	var fall_seen: bool = false
	for frame: int in range(60):
		await _frames(1)
		peak = maxf(peak, player.position.y)
		jump_seen = jump_seen or (not player.is_on_floor() and animator.assigned_animation == "JumpStart")
		fall_seen = fall_seen or (not player.is_on_floor() and player.velocity.y <= 0.0 and animator.current_animation == "Fall" and animator.is_playing())
		if frame == 2:
			_check(player.position.y > 0.1 and animator.current_animation_position >= 31.0 / 60.0, "Immediate physics takeoff skips anticipation")
		if frame == 15:
			player.jump_requested = true
	_check(peak > 1.15 and peak < 1.4, "Jump height and no double jump")
	_check(jump_seen, "JumpStart samples ascent")
	_check(fall_seen, "Fall loops during descent")
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
	await _place(Vector3(3.7, 0.1, -5.1))
	player.move_intent = Vector3.FORWARD
	await _frames(30)
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
	_check(skeleton != null and skeleton.get_bone_count() == 21, "Imported skeleton remains intact")
	for clip: StringName in [&"Idle", &"Walk", &"Run", &"Sprint", &"Fall"]:
		_check(animator.get_animation(clip).loop_mode == Animation.LOOP_LINEAR, "Loop flag: " + String(clip))
	_check(animator.get_animation(&"JumpStart").loop_mode == Animation.LOOP_NONE, "Jump does not loop")
	_check(absf(animator.get_animation(&"Run").length - 0.600000) < 0.001, "Run duration")
	_check(absf(animator.get_animation(&"Sprint").length - 0.500000) < 0.001, "Sprint duration")
	var body: MeshInstance3D = skeleton.find_child("Body", true, false) as MeshInstance3D
	_check(body.mesh.get_blend_shape_count() == 8, "Eight shoulder corrective shapes imported")
	_check((body.mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) != 0, "Eight-weight skin layout preserved")
	for side: String in ["Left", "Right"]:
		var scapula: int = skeleton.find_bone(side + "Scapula")
		var shoulder: int = skeleton.find_bone(side + "Shoulder")
		_check(scapula >= 0 and shoulder >= 0 and skeleton.get_bone_parent(scapula) == skeleton.find_bone("UpperChest") and skeleton.get_bone_parent(shoulder) == scapula, side + " scapula hierarchy")
	for clip: StringName in [&"Idle", &"Walk", &"Run", &"Sprint", &"JumpStart", &"Fall"]:
		var animation: Animation = animator.get_animation(clip)
		var shape_tracks: int = 0
		for track: int in range(animation.get_track_count()):
			if animation.track_get_type(track) == Animation.TYPE_BLEND_SHAPE:
				shape_tracks += 1
		_check(shape_tracks == 8, String(clip) + " animates all shoulder shapes")
	await _place(Vector3(0, 0.1, 3))
	player.slow_walk_requested = true
	player.move_intent = Vector3(1, 0, 1)
	await _frames(20)
	_check(animator.current_animation == "Walk" and absf(animator.speed_scale - 1.0) < 0.05, "Slow movement uses Walk at its reference speed")
	_check(absf(Vector2(player.velocity.x, player.velocity.z).length() - 0.5141) < 0.01, "Slow diagonal speed is normalized")
	player.slow_walk_requested = false
	player.move_intent = Vector3.ZERO
	await _frames(20)
	player.jump_requested = true
	await _frames(4)
	_check(animator.assigned_animation == "JumpStart" and not player.is_on_floor(), "Repeated jump restarts ascent after landing")
	await _frames(60)
	await _place(Vector3(0, 10, 3))
	_check(not player.is_on_floor() and animator.current_animation == "Fall", "Ledge fall skips JumpStart anticipation")
	await _frames(15)
	_check(not player.is_on_floor() and animator.current_animation == "Fall" and animator.is_playing(), "Long fall remains animated before contact")
	await _frames(70)
	_check(player.is_on_floor() and animator.current_animation == "Idle", "Long fall ends only at actual landing")
	if DisplayServer.get_name() != "headless":
		await _test_camera_cut()
		await _test_camera_modes()
		await _test_window_input()
	else:
		print("ENTITY_TEST window input skipped: headless display cannot capture mouse")
	print("ENTITY_TEST model=%s checks=%d failures=%d" % [model_id, checks, failures.size()])
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
	var ctrl: InputEventKey = InputEventKey.new()
	ctrl.physical_keycode = KEY_CTRL
	ctrl.pressed = true
	Input.parse_input_event(ctrl)
	Input.action_press("move_forward")
	await _frames(20)
	_check(Input.is_action_pressed("slow_walk"), "Physical Ctrl maps to slow_walk")
	_check(absf(Vector2(player.velocity.x, player.velocity.z).length() - 0.5141) < 0.01 and animator.current_animation == "Walk", "Ctrl moves slowly with Walk animation")
	Input.action_press("sprint")
	await _frames(20)
	_check(absf(Vector2(player.velocity.x, player.velocity.z).length() - 0.5141) < 0.01, "Slow walk takes priority over sprint")
	Input.action_release("sprint")
	ctrl.pressed = false
	Input.parse_input_event(ctrl)
	await _frames(20)
	_check(absf(Vector2(player.velocity.x, player.velocity.z).length() - 4.3) < 0.01 and animator.current_animation == "Run", "Releasing Ctrl restores normal running")
	Input.action_release("move_forward")
	await _frames(20)
	controller.set("input_enabled", false)
	await _place(Vector3(0, 0.1, 3))
	controller.set("input_enabled", true)
	origin = player.position
	Input.action_press("move_forward")
	await _frames(30)
	Input.action_press("sprint")
	await _frames(20)
	_check(absf(Vector2(player.velocity.x, player.velocity.z).length() - 5.6) < 0.05, "Shift input selects sprint")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _frames(20)
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
	Input.action_press("slow_walk")
	await _frames(2)
	_check(not player.slow_walk_requested, "Released mouse disables slow walk request")
	Input.action_release("slow_walk")
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

func _test_camera_modes() -> void:
	var controller: Node = player.get_node("Controller")
	var camera: Camera3D = controller.get("camera") as Camera3D
	var pivot: Node3D = controller.get("camera_pivot") as Node3D
	var arm: SpringArm3D = controller.get("spring_arm") as SpringArm3D
	var visual: Node3D = player.get_node("Visual") as Node3D
	_check(bool(controller.get("first_person")) and visual.first_person_model.visible, "First person defaults to separate arms")
	_check(camera.global_position.distance_to(player.get_node("CameraPivot").global_position) < 0.001, "First person eye stays at 1.62 meters")
	_check(root.get_camera_3d() == camera, "First person uses existing active camera")
	controller.set("input_enabled", true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(0, -10000)
	controller.call("_unhandled_input", motion)
	_check(absf(arm.rotation.x - deg_to_rad(85)) < 0.001, "First person can look up with pitch limit")
	motion.relative = Vector2(0, 10000)
	controller.call("_unhandled_input", motion)
	_check(absf(arm.rotation.x - deg_to_rad(-85)) < 0.001, "First person can look down with pitch limit")
	var toggle: InputEventKey = InputEventKey.new()
	toggle.physical_keycode = KEY_V
	toggle.pressed = true
	Input.parse_input_event(toggle.duplicate())
	await _frames(3)
	_check(not bool(controller.get("first_person")) and visual.third_person_model.visible and arm.spring_length == 4.0, "V restores third person model and camera arm")
	_check(root.get_camera_3d() == camera and camera.global_position.distance_to(pivot.global_position) > 0.1, "Third person retains camera reference and offset")
	toggle.pressed = false
	Input.parse_input_event(toggle.duplicate())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	toggle.pressed = true
	Input.parse_input_event(toggle.duplicate())
	await _frames(2)
	_check(not bool(controller.get("first_person")), "Released mouse blocks view toggle")
	toggle.pressed = false
	Input.parse_input_event(toggle.duplicate())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	toggle.pressed = true
	Input.parse_input_event(toggle.duplicate())
	await _frames(3)
	_check(bool(controller.get("first_person")) and visual.first_person_model.visible and camera.global_position.distance_to(player.get_node("CameraPivot").global_position) < 0.001, "V returns to anchored first person")
	toggle.pressed = false
	Input.parse_input_event(toggle.duplicate())
	arm.rotation.x = 0.0
	controller.set("input_enabled", false)
	await _place(Vector3(-2.4, 0.1, 0))
	_check(camera.global_position.distance_to(player.get_node("CameraPivot").global_position) < 0.001, "Wall does not displace first person eye")
	await _place(Vector3(0, 0.1, 3))

func _test_camera_cut() -> void:
	var controller: Node = player.get_node("Controller")
	var camera: Camera3D = controller.get("camera") as Camera3D
	var pivot: Node3D = controller.get("camera_pivot") as Node3D
	var arm: SpringArm3D = controller.get("spring_arm") as SpringArm3D
	var visual: Node3D = player.get_node("Visual") as Node3D
	await _place(Vector3(0, 0.1, 3))
	var before: Vector3 = camera.global_position
	controller.call("set_first_person", false)
	_check(visual.first_person_model.visible and camera.global_position.is_equal_approx(before), "Queued view change exposes no intermediate state")
	await controller.view_changed
	_check(visual.third_person_model.visible and absf(camera.position.z - 4.0) < 0.001, "Camera is positioned on the exact cut, before another frame")
	controller.call("set_first_person", true)
	await controller.view_changed
	_check(visual.first_person_model.visible and camera.global_position.distance_to(player.get_node("CameraPivot").global_position) < 0.001, "First person cut shows arms and anchors eye atomically")
	await _place(Vector3(-1.5, 0.1, 0))
	pivot.rotation.y = -PI / 2.0
	arm.rotation.x = 0.0
	controller.call("set_first_person", false)
	await controller.view_changed
	var cut_distance: float = camera.position.z
	_check(cut_distance > 0.1 and cut_distance < 1.3 and camera.global_position.x > -2.75, "Third person cut uses wall-safe position immediately")
	await _frames(1)
	_check(absf(camera.position.z - cut_distance) < 0.02, "Next SpringArm tick does not correct the cut position")
	controller.call("set_first_person", true)
	await controller.view_changed
	pivot.rotation.y = 0.0
	await _place(Vector3(0, 0.1, 3))
