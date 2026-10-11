extends Node3D
const Paths: Script = preload("res://game/core/gdscript/project_paths.gd")
## Basic Voxel locomotion. Physics owns translation, takeoff and landing.
const Models: Script = preload("res://game/entities/common/gdscript/character_models.gd")
@export var model_id: StringName = &""
@export var settings_path: String = Paths.settings_file()
@export var motor: CharacterMotor
var animation_player: AnimationPlayer
@export var turn_speed: float = 12.0
@export var walk_reference_speed: float = 0.5141
@export var run_reference_speed: float = 4.3
@export var sprint_reference_speed: float = 5.6
@export var idle_clip: StringName = &"Idle"
@export var walk_clip: StringName = &"Walk"
@export var run_clip: StringName = &"Run"
@export var sprint_clip: StringName = &"Sprint"
@export var jump_start_clip: StringName = &"JumpStart"
@export var fall_clip: StringName = &"Fall"
@export var takeoff_time: float = 31.0 / 60.0

var third_person_model: Node3D
var first_person_model: Node3D
var first_person_skeleton: Skeleton3D
var first_person_animation: AnimationPlayer
var first_person: bool = false
var load_error: String = ""
var view_pivot: Node3D
const HoldPose: Script = preload("res://game/entities/common/gdscript/hold_pose.gd")
var hold_pose: RefCounted
var holding_block: bool = false
var _clip: StringName = &""
var hand_skeleton: Skeleton3D
var hand_bone: int = -1

func _ready() -> void:
	if model_id.is_empty():
		model_id = Models.load_id(settings_path)
	var model: Node3D = Models.instantiate(model_id)
	first_person_model = Models.instantiate(model_id, true)
	if model == null or first_person_model == null:
		load_error = "CharacterVisual cannot load character pair: " + String(model_id) + " / " + "; ".join(Models.Library.errors)
		push_error(load_error)
		if model != null:
			model.free()
		if first_person_model != null:
			first_person_model.free()
			first_person_model = null
		set_process(false)
		return
	third_person_model = model
	model.name = "Model"
	add_child(model)
	var skeletons: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() == 1:
		hand_skeleton = skeletons[0] as Skeleton3D
		hand_bone = hand_skeleton.find_bone("RightLowerArm")
	first_person_model.name = "FirstPersonModel"
	first_person_model.rotation.y = PI
	add_child(first_person_model)
	first_person_model.hide()
	first_person_skeleton = first_person_model.find_child("Skeleton3D", true, false) as Skeleton3D
	first_person_animation = first_person_model.get_node("AnimationPlayer") as AnimationPlayer
	first_person_animation.play("FP_Idle")
	for mesh: Node in first_person_model.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	animation_player = model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if motor == null or animation_player == null:
		push_error("CharacterVisual requires motor and animation_player.")
		set_process(false)
		return
	if not (0.0 < walk_reference_speed and walk_reference_speed < run_reference_speed and run_reference_speed < sprint_reference_speed):
		push_error("CharacterVisual requires increasing positive gait reference speeds.")
		set_process(false)
		return
	for clip: StringName in [idle_clip, walk_clip, run_clip, sprint_clip, jump_start_clip, fall_clip, &"HoldBlock_R"]:
		if not animation_player.has_animation(clip):
			push_error("CharacterVisual missing required animation: " + String(clip))
			set_process(false)
			return
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	hold_pose = HoldPose.new(model, animation_player.get_animation("HoldBlock_R"))
	if takeoff_time < 0.0 or takeoff_time >= animation_player.get_animation(jump_start_clip).length:
		push_error("CharacterVisual takeoff time is outside JumpStart.")
		set_process(false)

## Use the active view's authored grip; never mix FP offsets into the TP skeleton.
func throw_origin() -> Vector3:
	var rig: Skeleton3D = first_person_skeleton if first_person else hand_skeleton
	return (rig.global_transform * rig.get_bone_global_pose(rig.find_bone("Grip_R"))).origin

func _process(delta: float) -> void:
	_update_locomotion(delta)
	animation_player.advance(delta)
	hold_pose.call("apply", delta, holding_block)
	var fp_clip: StringName = &"FP_HoldBlock_R" if holding_block else &"FP_Idle"
	if first_person_animation.current_animation != fp_clip:
		first_person_animation.play(fp_clip, 0.12)

func _update_locomotion(delta: float) -> void:
	var actual: Vector3 = motor.get_real_velocity()
	var speed: float = Vector2(actual.x, actual.z).length()
	if view_pivot != null:
		global_basis = view_pivot.global_basis * Basis(Vector3.UP, PI)
	elif motor.move_intent.length_squared() > 0.001:
		var heading: float = atan2(motor.move_intent.x, motor.move_intent.z)
		rotation.y = lerp_angle(rotation.y, heading, 1.0 - exp(-turn_speed * delta))
	if not motor.is_on_floor():
		if motor.velocity.y > 0.0:
			# Skip anticipation: a button press launches immediately. Map ascent to
			# the remaining baked poses, including shortened jumps under ceilings.
			_play(jump_start_clip, 0.0)
			var launch_speed: float = maxf(sqrt(2.0 * motor.gravity * motor.jump_height), 0.001)
			var progress: float = 1.0 - clampf(motor.velocity.y / launch_speed, 0.0, 1.0)
			var end: float = animation_player.get_animation(jump_start_clip).length
			animation_player.seek(lerpf(takeoff_time, end, progress), true)
			animation_player.pause()
		else:
			_play(fall_clip)
			animation_player.speed_scale = 1.0
		return
	# Actual contact ends Fall; the asset has no separate landing clip.
	if speed <= 0.05:
		_play(idle_clip)
		animation_player.speed_scale = 1.0
		return
	var sprint_threshold: float = (run_reference_speed + sprint_reference_speed) * 0.5
	var sprinting: bool = speed > sprint_threshold + (-0.15 if _clip == sprint_clip else 0.15)
	var walking: bool = speed < walk_reference_speed * 1.5 + (0.08 if _clip == walk_clip else -0.08)
	var gait: StringName = sprint_clip if sprinting else (walk_clip if walking else run_clip)
	var reference: float = sprint_reference_speed if sprinting else (walk_reference_speed if walking else run_reference_speed)
	_play(gait)
	animation_player.speed_scale = clampf(speed / reference, 0.05, 1.6)

func _is_gait(clip: StringName) -> bool:
	return clip == walk_clip or clip == run_clip or clip == sprint_clip

func _play(clip: StringName, blend: float = 0.12) -> void:
	if _clip == clip:
		return
	var match_phase: bool = _is_gait(_clip) and _is_gait(clip)
	var phase: float = 0.0
	if match_phase:
		phase = fposmod(animation_player.current_animation_position / animation_player.get_animation(_clip).length, 1.0)
	_clip = clip
	animation_player.speed_scale = 1.0
	animation_player.play(clip, blend)
	if match_phase:
		animation_player.seek(phase * animation_player.get_animation(clip).length, true)

## The camera owns the independent FP model; both views belong to one character choice.
func set_view(camera: Camera3D, pivot: Node3D, enabled: bool) -> void:
	first_person = enabled
	view_pivot = pivot if enabled else null
	if first_person_model.get_parent() != camera:
		first_person_model.reparent(camera, false)
		first_person_model.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	third_person_model.visible = not enabled
	first_person_model.visible = enabled
	if enabled:
		global_basis = pivot.global_basis * Basis(Vector3.UP, PI)
	reset_physics_interpolation()
	first_person_model.reset_physics_interpolation()
