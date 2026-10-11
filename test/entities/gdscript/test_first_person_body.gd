extends SceneTree
const WORLD: PackedScene = preload("res://test/entities/scenes/player_playground.tscn")
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func frames(count: int = 4) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/body_" + name + ".png")

func run() -> void:
	root.get_node("MCPRuntimeServer").call("_stop_server")
	create_timer(45.0).timeout.connect(func() -> void: quit(2))
	var world: Node3D = WORLD.instantiate() as Node3D
	var player: CharacterMotor = world.get_node("Player") as CharacterMotor
	var controller: Node = player.get_node("Controller")
	var visual: Node3D = player.get_node("Visual") as Node3D
	visual.set("model_id", &"basic_voxel")
	root.add_child(world)
	controller.set_process_unhandled_input(false)
	var pivot: Node3D = player.get_node("CameraPivot") as Node3D
	var arm: SpringArm3D = pivot.get_node("SpringArm") as SpringArm3D
	var animation: AnimationPlayer = visual.get_node("Model/AnimationPlayer") as AnimationPlayer
	var skeleton: Skeleton3D = visual.find_child("Skeleton3D", true, false) as Skeleton3D
	var mesh: MeshInstance3D = skeleton.get_node("Body") as MeshInstance3D
	await frames(30)
	check(player.is_on_floor(), "Ground collision")
	check(skeleton.get_bone_count() == 21 and skeleton.find_bone("Grip_R") >= 0 and skeleton.find_bone("Grip_L") >= 0, "21 bones including grips")
	for clip: StringName in [&"Idle", &"Walk", &"Run", &"Sprint", &"JumpStart", &"Fall", &"HoldBlock_R", &"HoldBlock_L"]:
		check(animation.has_animation(clip), "Animation " + String(clip))
		check(animation.get_animation(clip).loop_mode == (Animation.LOOP_NONE if clip == &"JumpStart" else Animation.LOOP_LINEAR), "Loop " + String(clip))
	var body_mesh: Mesh = mesh.mesh
	check(not mesh.is_visible_in_tree() and visual.first_person_model.is_visible_in_tree(), "Only the separate FP model is visible")
	check(visual.first_person_model.get_parent() is Camera3D and visual.first_person_animation.current_animation == "FP_Idle", "FP model follows the camera and owns its animation")
	var fp_mesh: MeshInstance3D = visual.first_person_model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	check(fp_mesh.mesh.surface_get_array_index_len(0) == 1952 * 3, "Authored arms mesh is used without body extraction")
	check(mesh.get_blend_shape_count() == 8, "Shoulder morphs retained")
	await capture("forward")
	arm.rotation.x = deg_to_rad(-80.0)
	await frames()
	await capture("down")
	pivot.rotation.y = 1.0
	await frames()
	check(visual.global_basis.z.dot(-pivot.global_basis.z) > 0.999, "Body follows camera yaw")
	Input.action_press("move_forward")
	await frames(20)
	check(animation.current_animation == "Run" and player.get_real_velocity().length() > 4.0, "Visible-body running")
	await capture("run")
	Input.action_release("move_forward")
	Input.action_press("jump")
	await frames(3)
	check(player.velocity.y > 0.0 and animation.assigned_animation == "JumpStart", "Jump ascent animation")
	Input.action_release("jump")
	await frames(50)
	check(player.is_on_floor() and animation.current_animation == "Idle", "Landing returns to Idle")
	controller.call("set_first_person", false)
	await frames()
	check(mesh.mesh == body_mesh and mesh.is_visible_in_tree() and not visual.first_person_model.visible, "Third person shows the full paired mesh")
	await capture("third")
	controller.call("set_first_person", true)
	await frames()
	check(not mesh.is_visible_in_tree() and visual.first_person_model.is_visible_in_tree() and arm.spring_length == 0.0, "Switch restores separate FP arms and anchored eye")
	print("FIRST_PERSON_PAIR checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
