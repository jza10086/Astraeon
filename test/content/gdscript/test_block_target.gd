extends SceneTree
var checks: int = 0
var failures: int = 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world: Node = load("res://game/core/main.tscn").instantiate()
	var base: String = "res://tmp/content/target_world_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(base)
	world.shading_settings_path = base + "/settings.cfg"
	var created: Dictionary = load("res://game/core/gdscript/world_selection.gd").create_new(base + "/worlds/unused", world.shading_settings_path, "target")
	if created.has("error"):
		printerr(created.error)
		quit(1)
		return
	world.world_directory = created.directory
	world.horizontal_distance = 16
	world.vertical_distance = 16
	root.add_child(world)
	var deadline: int = Time.get_ticks_msec() + 60000
	while not world.ready_to_play and not world.failed and Time.get_ticks_msec() < deadline:
		await process_frame
	check(world.ready_to_play, "Main ready")
	if not world.ready_to_play:
		quit(1)
		return
	world.controller.set_physics_process(false)
	world.player.set_physics_process(false) # Keep the elevated render fixture from falling.
	world.camera.reparent(world, true) # SpringArm otherwise rewrites the test camera transform.
	world.camera.cull_mask &= ~(1 << 19)
	var target: RefCounted = world.block_target
	var cell: Vector3i = Vector3i(-1, maxi(48, floori(world.player.position.y) + 9), 3)
	world.player.global_position = Vector3(cell) + Vector3(3, 2, 5)
	deadline = Time.get_ticks_msec() + 15000
	while not world.voxel_tool.is_area_editable(AABB(Vector3(cell), Vector3.ONE)) and Time.get_ticks_msec() < deadline:
		await process_frame
	world.set_block(cell, world.content.dirt_id)
	var center: Vector3 = Vector3(cell) + Vector3.ONE * 0.5
	world.camera.global_position = center + Vector3(3, 2, 5)
	world.camera.look_at(center)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	target.refresh()
	check(target.hit != null and target.hit.position == cell, "negative coordinate native ray target")
	check(target.visual.visible and target.visual.global_position == Vector3(cell), "outline tracks target")
	check(target.state_id == world.content.dirt_id, "shared mining target state")
	var mesh: Mesh = target.visual.mesh
	for frame: int in range(4):
		target.refresh()
	check(target.visual.mesh == mesh, "moving aim does not rebuild mesh")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	target.refresh()
	check(not target.visual.visible and target.hit == null, "released mouse hides selection")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	world.controller.set("input_enabled", false)
	target.refresh()
	check(not target.visual.visible, "inventory/settings input gate hides selection")
	world.controller.set("input_enabled", true)
	target.refresh()
	paused = true
	check(not target.visual.visible, "pause clears outline immediately")
	paused = false
	world.camera.global_position = center + Vector3(0, 0, 10)
	world.camera.look_at(center)
	target.refresh()
	check(target.hit == null and not target.visual.visible, "outside eight meter reach")
	world.camera.global_position = center + Vector3(3, 2, 5)
	world.camera.look_at(center)
	world.set_block(cell, 0)
	target.refresh()
	check(target.hit == null, "removed target is cleared")
	world.set_block(cell, world.content.water_id)
	target.refresh()
	check(target.hit == null, "water has no block highlight")
	world.set_block(cell, world.content.dirt_id)
	world.camera.look_at(world.camera.global_position + Vector3.UP, Vector3.FORWARD)
	target.refresh()
	check(target.hit == null, "sky aim hides selection")
	world.camera.look_at(center)
	for frame: int in range(45):
		await process_frame
	target.refresh()
	check(target.visual.visible, "selection restored")
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://tmp/content/block_target.png") == OK, "render screenshot")
	# Capture the same view without the outline for visual comparison.
	target.visual.hide()
	world.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://tmp/content/block_target_off.png") == OK, "baseline screenshot")
	world.queue_free()
	await process_frame
	print("BLOCK_TARGET_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
