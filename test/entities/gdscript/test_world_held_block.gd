extends SceneTree
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	root.get_node("MCPRuntimeServer").call("_stop_server")
	create_timer(90).timeout.connect(func() -> void: quit(2))
	var world: Node3D = load("res://game/core/main.tscn").instantiate() as Node3D
	world.world_directory = "res://tmp/held_world_%d" % Time.get_ticks_usec()
	world.shading_settings_path = world.world_directory.path_join("settings.cfg")
	world.horizontal_distance = 32
	world.vertical_distance = 16
	world.player.get_node("Visual").model_id = &"basic_voxel"
	preload("res://test/survival/gdscript/world_fixture.gd").prepare(world)
	root.add_child(world)
	while not world.ready_to_play and not world.failed:
		await process_frame
	check(world.ready_to_play, "World starts with holding component")
	if world.failed:
		quit(1)
		return
	world.controller.set_process_unhandled_input(false)
	check(world.inventory.insert(&"astraeon:grass_item", 2) == 0, "Select block in world")
	for frame: int in range(30):
		await physics_frame
		await process_frame
	var held: Node3D = world.get_node("HeldBlock") as Node3D
	check(held.display.visible and world.controller.visual.holding_block, "World selection drives arm and block")
	world.player.get_node("CameraPivot/SpringArm").rotation.x = deg_to_rad(-40)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/held_world.png")
	world.inventory.select(1)
	for frame: int in range(12):
		await process_frame
	check(not held.display.visible and not world.controller.visual.holding_block, "World empty slot releases hold")
	await world.save_world(false)
	check(not world.failed, "Save succeeds with presentation component")
	world.queue_free()
	for frame: int in range(5):
		await process_frame
	print("WORLD_HELD_BLOCK checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
