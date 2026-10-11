extends SceneTree
const WORLD: PackedScene = preload("res://test/entities/scenes/player_playground.tscn")
var failures: int = 0
var checks: int = 0
var content: AstraeonWorldContent

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func frames(count: int = 10) -> void:
	for frame: int in range(count):
		content.bundle.visuals.call("commit")
		await physics_frame
		await process_frame

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/held_" + name + ".png")

func run() -> void:
	root.get_node("MCPRuntimeServer").call("_stop_server")
	create_timer(45).timeout.connect(func() -> void: quit(2))
	content = AstraeonWorldContent.new()
	check(content.build(["res://game/data/content/packages/astraeon.aebpack"]), "Load current compiled content: " + content.error)
	if failures:
		quit(1)
		return
	var inventory: AstraeonInventoryState = AstraeonInventoryState.new()
	check(inventory.configure(content.item_catalog, preload("res://game/data/inventory/resources/player_inventory.tres")), "Configure inventory")
	var world: Node3D = WORLD.instantiate() as Node3D
	var player: CharacterMotor = world.get_node("Player") as CharacterMotor
	var visual: Node3D = player.get_node("Visual") as Node3D
	var controller: Node = player.get_node("Controller")
	visual.set("model_id", &"basic_voxel")
	root.add_child(world)
	controller.set_process_unhandled_input(false)
	var held: Node3D = preload("res://game/entities/player/gdscript/held_block.gd").new()
	held.configure(inventory, content.bundle, visual)
	world.add_child(held)
	held.failed.connect(func(message: String) -> void: check(false, message))
	await frames(30)
	check(not visual.holding_block and not held.display.visible, "Empty slot has no pose or block")
	check(inventory.insert(&"astraeon:grass_item", 2) == 0, "Equip grass")
	await frames(30)
	check(held.display.visible and visual.holding_block, "Selected block is visible")
	check(held.fp_display.is_visible_in_tree() and not held.display.is_visible_in_tree() and visual.first_person_animation.current_animation == "FP_HoldBlock_R", "FP uses its own grip and hold animation")
	check(held.visual_hash.is_empty() or held.material.albedo_texture != null, "Compiled color or texture is available")
	check(visual.hold_pose.weight == 1.0 and visual.hold_pose.tracks.size() >= 12, "Right-arm pose and shoulder tracks applied")
	var shape_tracks: int = 0
	for entry: Dictionary in visual.hold_pose.tracks:
		shape_tracks += int(visual.hold_pose.clip.track_get_type(entry.track) == Animation.TYPE_BLEND_SHAPE)
	check(shape_tracks == 4, "All four right shoulder correction tracks are layered")
	check(held.attachment.bone_name == &"Grip_R" and held.display.position == Vector3(0,0,0.06), "Block rests on Grip_R")
	var rig: Skeleton3D = visual.hand_skeleton
	var forearm: int = rig.find_bone("RightLowerArm")
	var pose: Quaternion = rig.get_bone_pose_rotation(forearm)
	var animator: AnimationPlayer = visual.animation_player
	await capture("first_forward")
	player.get_node("CameraPivot/SpringArm").rotation.x = deg_to_rad(-35)
	await frames()
	await capture("first_down")
	Input.action_press("move_forward")
	await frames(20)
	check(animator.current_animation == "Run" and player.get_real_velocity().length() > 4.0, "Run continues while holding")
	check(pose.angle_to(rig.get_bone_pose_rotation(forearm)) < 0.1, "Run does not replace holding forearm pose")
	Input.action_release("move_forward")
	Input.action_press("jump")
	await frames(3)
	check(animator.assigned_animation == "JumpStart" and player.velocity.y > 0 and visual.hold_pose.weight == 1.0, "Jump keeps holding overlay")
	Input.action_release("jump")
	await frames(50)
	controller.call("set_first_person", false)
	await frames()
	check(held.display.is_visible_in_tree() and not held.fp_display.is_visible_in_tree(), "Third person retains only its own held block")
	await capture("third")
	check(inventory.select(1), "Switch to empty hotbar slot")
	await frames()
	check(not held.display.visible and visual.hold_pose.weight == 0.0, "Slot change releases pose")
	check(inventory.select(0), "Switch back to block")
	await frames()
	check(held.display.visible and visual.hold_pose.weight == 1.0, "Slot change restores pose")
	check(inventory.consume(inventory.selected, 2), "Consume last blocks")
	await frames()
	check(not held.display.visible and visual.hold_pose.weight == 0.0, "Empty stack releases pose")
	check(inventory.insert(&"astraeon:pickaxe", 1) == 0, "Select tool")
	await frames()
	check(not held.display.visible and not visual.holding_block, "Tools do not use block pose")
	print("HELD_BLOCK checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
