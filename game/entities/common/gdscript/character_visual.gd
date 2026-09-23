extends Node3D
## Current V8 locomotion clips. Physics owns translation and jump phase.
@export var motor: CharacterMotor
@export var animation_player: AnimationPlayer
@export var turn_speed: float = 12.0
@export var walk_reference_speed: float = 4.3
@export var run_reference_speed: float = 5.6
@export var idle_clip: StringName = &"Idle"
@export var walk_clip: StringName = &"Walk_4_3"
@export var run_clip: StringName = &"Run_5_6"
@export var jump_clip: StringName = &"Jump"
@export var takeoff_time: float = 0.2
@export var apex_time: float = 0.5
@export var landing_time: float = 0.8

var _clip: StringName = &""
var _was_airborne: bool = false
var _landing_remaining: float = 0.0

func _ready() -> void:
	if motor == null or animation_player == null:
		push_error("CharacterVisual requires motor and animation_player.")
		set_process(false)
		return
	if walk_reference_speed <= 0.0 or run_reference_speed <= 0.0:
		push_error("CharacterVisual reference speeds must be positive.")
		set_process(false)
		return
	for clip: StringName in [idle_clip, walk_clip, run_clip, jump_clip]:
		if not animation_player.has_animation(clip):
			push_error("CharacterVisual missing required animation: " + String(clip))
			set_process(false)
			return
	var jump_length: float = animation_player.get_animation(jump_clip).length
	if not (0.0 <= takeoff_time and takeoff_time < apex_time and apex_time < landing_time and landing_time < jump_length):
		push_error("CharacterVisual jump phase times are invalid.")
		set_process(false)

func _process(delta: float) -> void:
	var actual: Vector3 = motor.get_real_velocity()
	var horizontal_speed: float = Vector2(actual.x, actual.z).length()
	if motor.move_intent.length_squared() > 0.001:
		var heading: float = atan2(motor.move_intent.x, motor.move_intent.z)
		rotation.y = lerp_angle(rotation.y, heading, 1.0 - exp(-turn_speed * delta))
	if not motor.is_on_floor():
		_was_airborne = true
		_landing_remaining = 0.0
		_play(jump_clip)
		# Sample the baked airborne interval by vertical velocity, including
		# early ceiling hits and long falls; never play landing in mid-air.
		var launch_speed: float = maxf(sqrt(2.0 * motor.gravity * motor.jump_height), 0.001)
		var phase: float = clampf(motor.velocity.y / launch_speed, -1.0, 1.0)
		var sample_time: float = lerpf(apex_time, takeoff_time, phase) if phase >= 0.0 else lerpf(apex_time, landing_time - 0.01, -phase)
		animation_player.seek(sample_time, true)
		animation_player.pause()
		return
	if _was_airborne:
		_was_airborne = false
		_landing_remaining = animation_player.get_animation(jump_clip).length - landing_time
		animation_player.play(jump_clip)
		animation_player.speed_scale = 1.0
		animation_player.seek(landing_time, true)
	if horizontal_speed > 0.05:
		_landing_remaining = 0.0
		# Match gait to achieved speed, so blocked/accelerating runners do not
		# play full-speed sprinting. Hysteresis prevents threshold chatter.
		var threshold: float = (walk_reference_speed + run_reference_speed) * 0.5
		var running: bool = horizontal_speed > threshold + (-0.15 if _clip == run_clip else 0.15)
		_play(run_clip if running else walk_clip)
		var reference: float = run_reference_speed if running else walk_reference_speed
		animation_player.speed_scale = clampf(horizontal_speed / reference, 0.05, 1.5)
	elif _landing_remaining > 0.0:
		_landing_remaining = maxf(0.0, _landing_remaining - delta)
	else:
		_play(idle_clip)
		animation_player.speed_scale = 1.0

func _play(clip: StringName) -> void:
	if _clip == clip:
		return
	_clip = clip
	animation_player.speed_scale = 1.0
	animation_player.play(clip, 0.12)
