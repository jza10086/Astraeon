extends Node
## Player-only input and temporary third-person camera, separate from the motor.
@export var motor: CharacterMotor
@export var camera_pivot: Node3D
@export var spring_arm: SpringArm3D
@export var camera: Camera3D
@export var mouse_sensitivity: float = 0.0025
@export var respawn_position: Vector3 = Vector3(0.0, 0.1, 3.0)
@export var respawn_below: float = -20.0
@export var input_enabled: bool = true

func _ready() -> void:
	if motor == null or camera_pivot == null or spring_arm == null or camera == null:
		push_error("PlayerController requires motor and camera references.")
		set_physics_process(false)
		set_process_unhandled_input(false)
		return
	spring_arm.add_excluded_object(motor.get_rid())
	if input_enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if input_enabled:
		var axes: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		motor.move_intent = camera_pivot.global_basis * Vector3(axes.x, 0.0, axes.y) if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Vector3.ZERO
		motor.sprint_requested = Input.is_action_pressed("sprint") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		motor.jump_requested = Input.is_action_just_pressed("jump") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	motor.step(delta)
	if motor.global_position.y < respawn_below:
		respawn()

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("capture_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		camera_pivot.rotation.y -= motion.relative.x * mouse_sensitivity
		spring_arm.rotation.x = clampf(spring_arm.rotation.x - motion.relative.y * mouse_sensitivity, deg_to_rad(-65.0), deg_to_rad(20.0))

func respawn() -> void:
	motor.global_position = respawn_position
	motor.reset_motion()

func _exit_tree() -> void:
	if input_enabled:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
