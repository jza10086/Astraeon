extends Node
## Player input and switchable first/third-person view; one camera for world consumers.
signal view_changed()

@export var motor: CharacterMotor
@export var camera_pivot: Node3D
@export var spring_arm: SpringArm3D
@export var camera: Camera3D
@export var visual: Node3D
@export var first_person: bool = true
@export var eye_height: float = 1.62
@export var mouse_sensitivity: float = 0.0025
@export var respawn_position: Vector3 = Vector3(0.0, 0.1, 3.0)
@export var respawn_below: float = -20.0
@export var input_enabled: bool = true:
	set(value):
		input_enabled = value
		_last_jump_press = -1.0
		if motor != null:
			motor.reset_motion()
var player_state: AstraeonPlayerState
var _last_jump_press: float = -1.0
@export var flight_double_tap_seconds: float = 0.3

var _view_change_pending: bool = false
var _requested_first_person: bool = true
var _third_person_height: float
var _third_person_distance: float
var _third_person_margin: float
var _third_person_mask: int
var _third_person_fov: float
var _third_person_near: float

func _ready() -> void:
	if motor == null or camera_pivot == null or spring_arm == null or camera == null or visual == null or spring_arm.shape == null:
		push_error("PlayerController requires motor, visual and camera references.")
		set_physics_process(false)
		set_process_unhandled_input(false)
		return
	spring_arm.add_excluded_object(motor.get_rid())
	_third_person_fov = camera.fov
	_third_person_near = camera.near
	if not String(visual.get("load_error")).is_empty():
		set_physics_process(false)
		set_process_unhandled_input(false)
		return
	_third_person_height = camera_pivot.position.y
	_third_person_distance = spring_arm.spring_length
	_third_person_margin = spring_arm.margin
	_third_person_mask = spring_arm.collision_mask
	if first_person:
		spring_arm.rotation.x = 0.0
	_requested_first_person = first_person
	if first_person:
		_apply_view(true)
	else:
		set_first_person(false)
	if input_enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if input_enabled:
		var axes: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		motor.move_intent = camera_pivot.global_basis * Vector3(axes.x, 0.0, axes.y) if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Vector3.ZERO
		motor.slow_walk_requested = not motor.flying and Input.is_action_pressed("slow_walk") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		motor.sprint_requested = Input.is_action_pressed("sprint") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		var captured: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		var jump_pressed: bool = Input.is_action_just_pressed("jump") and captured
		var toggled: bool = _handle_jump_press(float(Time.get_ticks_msec()) / 1000.0) if jump_pressed else false
		if not captured:
			_last_jump_press = -1.0
		motor.jump_requested = jump_pressed and not motor.flying and not toggled
		motor.flight_vertical = Input.get_axis("fly_down", "fly_up") if captured and motor.flying else 0.0
	else:
		motor.reset_motion()
		_last_jump_press = -1.0
	motor.step(delta)
	if _view_change_pending:
		_view_change_pending = false
		_apply_view(_requested_first_person)
	if motor.global_position.y < respawn_below:
		respawn()

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("capture_mouse") and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_view") and not event.is_echo() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		set_first_person(not _requested_first_person)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		camera_pivot.rotation.y -= motion.relative.x * mouse_sensitivity
		spring_arm.rotation.x = clampf(spring_arm.rotation.x - motion.relative.y * mouse_sensitivity, deg_to_rad(-85.0 if first_person else -65.0), deg_to_rad(85.0 if first_person else 20.0))

## Queue a camera cut for physics, where shape queries are safe. No partial visual state.
func set_first_person(enabled: bool) -> void:
	_requested_first_person = enabled
	_view_change_pending = true

func _apply_view(enabled: bool) -> void:
	first_person = enabled
	camera_pivot.position = Vector3.UP * (eye_height if enabled else _third_person_height)
	camera.fov = 58.7155 if enabled else _third_person_fov
	camera.near = 0.01 if enabled else _third_person_near
	# A zero-length, collision-free arm keeps the eye anchored inside the capsule.
	spring_arm.spring_length = 0.0 if enabled else _third_person_distance
	spring_arm.margin = 0.0 if enabled else _third_person_margin
	spring_arm.collision_mask = 0 if enabled else _third_person_mask
	if not enabled:
		spring_arm.rotation.x = clampf(spring_arm.rotation.x, deg_to_rad(-65.0), deg_to_rad(20.0))
	var distance: float = 0.0
	if not enabled:
		# Match SpringArm's shape sweep immediately rather than waiting for its
		# next internal tick. The same shape/mask/exclusion keeps wall clearance.
		var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		query.shape = spring_arm.shape
		query.transform = spring_arm.global_transform
		query.motion = spring_arm.global_basis.z * _third_person_distance
		query.margin = 0.0
		query.collision_mask = _third_person_mask
		query.exclude = [motor.get_rid()]
		var fractions: PackedFloat32Array = motor.get_world_3d().direct_space_state.cast_motion(query)
		distance = _third_person_distance * fractions[0]
	camera.position = Vector3(0.0, 0.0, distance)
	visual.visible = true
	visual.call("set_view", camera, camera_pivot, enabled)
	camera_pivot.reset_physics_interpolation()
	view_changed.emit()

func respawn() -> void:
	motor.global_position = respawn_position
	motor.reset_motion()

func _exit_tree() -> void:
	if input_enabled:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## State changes do not enable flight automatically. Survival always revokes it.
func apply_game_mode() -> void:
	_last_jump_press = -1.0
	if motor != null and (player_state == null or not player_state.is_creative()) and motor.flying:
		motor.flying = false
		motor.reset_motion()

func _handle_jump_press(now: float) -> bool:
	if player_state == null or not player_state.is_creative():
		_last_jump_press = -1.0
		return false
	if _last_jump_press >= 0.0 and now - _last_jump_press <= flight_double_tap_seconds:
		motor.flying = not motor.flying
		motor.reset_motion()
		_last_jump_press = -1.0
		return true
	else:
		_last_jump_press = now
	return false
