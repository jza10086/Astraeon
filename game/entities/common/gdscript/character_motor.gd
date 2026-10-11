class_name CharacterMotor
extends CharacterBody3D
## Shared physical movement. Input or AI supplies world-space intent.

@export var flight_speed: float = 8.0
@export var flight_sprint_speed: float = 16.0
var flying: bool = false
var flight_vertical: float = 0.0

@export var slow_walk_speed: float = 0.5141
@export var walk_speed: float = 4.3
@export var run_speed: float = 5.6
@export var acceleration: float = 25.0
@export var braking: float = 30.0
@export var air_acceleration: float = 8.0
@export var gravity: float = 20.0
@export var jump_height: float = 1.25
@export var coyote_time: float = 0.10
@export var jump_buffer_time: float = 0.12

var move_intent: Vector3 = Vector3.ZERO
var slow_walk_requested: bool = false
var sprint_requested: bool = false
var jump_requested: bool = false
var jumped_this_frame: bool = false
var _coyote_remaining: float = 0.0
var _jump_remaining: float = 0.0

## Called once per physics tick by the owning controller.
func step(delta: float) -> void:
	jumped_this_frame = false
	if flying:
		var direction: Vector3 = Vector3(move_intent.x, flight_vertical, move_intent.z).limit_length(1.0)
		velocity = direction * (flight_sprint_speed if sprint_requested else flight_speed)
		jump_requested = false
		_coyote_remaining = 0.0
		_jump_remaining = 0.0
		move_and_slide()
		return
	_coyote_remaining = coyote_time if is_on_floor() else maxf(0.0, _coyote_remaining - delta)
	_jump_remaining = jump_buffer_time if jump_requested else maxf(0.0, _jump_remaining - delta)
	jump_requested = false
	var direction: Vector3 = Vector3(move_intent.x, 0.0, move_intent.z).limit_length(1.0)
	var target_speed: float = slow_walk_speed if slow_walk_requested else (run_speed if sprint_requested else walk_speed)
	var target: Vector3 = direction * target_speed
	var rate: float = acceleration if direction.length_squared() > 0.0 else braking
	if not is_on_floor():
		rate = air_acceleration
	var horizontal: Vector2 = Vector2(velocity.x, velocity.z).move_toward(Vector2(target.x, target.z), rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	if _jump_remaining > 0.0 and _coyote_remaining > 0.0:
		velocity.y = sqrt(2.0 * gravity * jump_height)
		_jump_remaining = 0.0
		_coyote_remaining = 0.0
		jumped_this_frame = true
	move_and_slide()
	if is_on_ceiling() and velocity.y > 0.0:
		velocity.y = 0.0

func reset_motion() -> void:
	flight_vertical = 0.0
	velocity = Vector3.ZERO
	move_intent = Vector3.ZERO
	slow_walk_requested = false
	sprint_requested = false
	jump_requested = false
	_coyote_remaining = 0.0
	_jump_remaining = 0.0
