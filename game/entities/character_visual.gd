extends Node3D
## Plays the unchanged HK416 clips. Physics owns travel and landing.
@export var motor: CharacterMotor
@export var animation_player: AnimationPlayer
@export var turn_speed: float = 12.0
@export var reference_speed: float = 1.1
var _clip: StringName = &""

func _ready() -> void:
	if motor == null or animation_player == null:
		push_error("CharacterVisual requires motor and animation_player.")
		set_process(false)
		return
	for clip: StringName in [&"Idle", &"Run", &"Jump"]:
		if not animation_player.has_animation(clip):
			push_error("CharacterVisual missing animation: " + String(clip))
			set_process(false)

func _process(delta: float) -> void:
	var actual: Vector3 = motor.get_real_velocity()
	var horizontal_speed: float = Vector2(actual.x, actual.z).length()
	if motor.move_intent.length_squared() > 0.001:
		var heading: float = atan2(motor.move_intent.x, motor.move_intent.z)
		rotation.y = lerp_angle(rotation.y, heading, 1.0 - exp(-turn_speed * delta))
	var desired: StringName = &"Idle"
	if not motor.is_on_floor():
		desired = &"Jump"
	elif horizontal_speed > 0.05:
		desired = &"Run"
	if desired != _clip:
		_clip = desired
		animation_player.play(desired, 0.12)
		if desired == &"Jump":
			# Skip the existing anticipation; hold airborne pose until real landing.
			animation_player.seek(0.32 if motor.velocity.y > 0.0 else 0.60, true)
	animation_player.speed_scale = clampf(horizontal_speed / reference_speed, 0.5, 1.5) if desired == &"Run" else 1.0
	if desired == &"Jump" and animation_player.current_animation_position >= 0.60:
		animation_player.seek(0.60, true)
		animation_player.pause()
