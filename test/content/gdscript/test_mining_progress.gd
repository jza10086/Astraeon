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
	var base: String = "res://tmp/content/mining_world_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(base)
	world.shading_settings_path = base + "/settings.cfg"
	var created: Dictionary = load("res://game/core/gdscript/world_selection.gd").create_new(base + "/worlds/unused", world.shading_settings_path, "mining")
	check(not created.has("error"), "create current-format test world")
	if created.has("error"):
		quit(1)
		return
	world.world_directory = created.directory
	world.horizontal_distance = 16
	world.vertical_distance = 16
	root.add_child(world)
	var deadline: int = Time.get_ticks_msec() + 60000
	while not world.ready_to_play and not world.failed and Time.get_ticks_msec() < deadline:
		await process_frame
	check(world.ready_to_play, "Main ready for timed mining: " + str(world.get("_status").text))
	if not world.ready_to_play:
		quit(1)
		return
	check(not world.player_state.is_creative(), "survival duration path")
	# Keep the production controller, but step its target directly for deterministic tests.
	var mining: RefCounted = world.mining
	world.mining = null
	var cell: Vector3i = Vector3i(world.player.position) + Vector3i(3,0,0)
	var id: int = world.content.dirt_id
	world.set_block(cell,id)
	mining.advance(0.0,cell,id)
	deadline = Time.get_ticks_msec() + 15000
	while not mining.visual.prepare(id) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(mining.visual.error.is_empty(), "native mask load succeeds")
	mining.advance(0.049,cell,id)
	check(mining.progress == 0.0, "No damage before 0.05 second tick")
	mining.advance(0.001,cell,id)
	check(is_equal_approx(mining.progress,0.05/0.75), "First tick removes 0.05 durability")
	mining.advance(0.2,cell,id)
	check(is_equal_approx(mining.progress,0.25/0.75), "Bare hand is 1 durability per second")
	check(world.voxel_tool.get_voxel(cell) == id, "Partial mining leaves authoritative voxel intact")
	var material: ShaderMaterial = world.content.library.models[id].get_material_override(0)
	check(material.get_shader_parameter("breaking_stage") == 3, "Progress uses ten crack stages")
	mining.cancel()
	check(mining.damage.has(cell) and material.get_shader_parameter("breaking_stage") == -1, "Cancel retains damage while releasing active visual")
	world.block_target.hit = world.voxel_tool.raycast(Vector3(cell) + Vector3(0.5,2,0.5), Vector3.DOWN, 4.0)
	world.block_target.state_id = id
	mining.tick(0.0)
	check(material.get_shader_parameter("breaking_stage") == 3, "Released hovered block still displays retained cracks")
	var other: Vector3i = cell + Vector3i.RIGHT
	world.set_block(other,id)
	mining.advance(0.1,other,id)
	check(is_equal_approx(mining.progress,0.1/0.75), "Second block owns independent damage")
	mining.advance(0.0,cell,id)
	check(is_equal_approx(mining.progress,0.25/0.75), "Returning resumes original block")
	world.inventory.insert(&"astraeon:shovel", 1)
	world.inventory.select(0)
	mining.advance(0.05,cell,id)
	check(is_equal_approx(mining.progress,0.35/0.75), "Matching shovel removes 0.1 per tick")
	world.inventory.insert(&"astraeon:axe", 1)
	world.inventory.select(1)
	mining.advance(0.05,cell,id)
	check(is_equal_approx(mining.progress,0.4/0.75), "Wrong tool stays at bare-hand speed")
	mining.cancel()
	var retained: Dictionary = mining.damage.duplicate(true)
	paused = true
	mining.tick(100.0)
	paused = false
	check(mining.damage == retained, "Pause does not age retained damage")
	mining.elapse(29.99)
	check(mining.damage.has(cell), "Damage survives until configured delay")
	mining.elapse(0.01)
	check(not mining.damage.has(cell), "Thirty seconds clears full damage")
	mining.tick(0.0)
	check(material.get_shader_parameter("breaking_stage") == -1, "Recovered block removes retained cracks")
	mining.advance(0.2,cell,id)
	world.mining = mining
	world.set_block(cell,id)
	world.mining = null
	check(not mining.damage.has(cell), "Replacing same state invalidates instance damage")
	# This isolated world's content is a fixture; authored resources are not edited.
	var block: Dictionary = world.content.bundle.blocks["astraeon:dirt"]
	block.mining_recovery_seconds = 0.2
	mining.advance(0.05,cell,id)
	mining.cancel()
	mining.elapse(0.2)
	check(not mining.damage.has(cell), "Custom recovery interval is honored")
	block.mining_recovery_seconds = 0.0
	mining.advance(0.05,cell,id)
	mining.cancel()
	check(not mining.damage.has(cell), "Zero delay clears immediately on release")
	block.mining_recovery_seconds = 30.0
	world.inventory.select(0)
	mining.advance(0.35,cell,id)
	check(world.voxel_tool.get_voxel(cell) == id, "Wooden shovel needs eight ticks for dirt")
	mining.advance(0.05,cell,id)
	check(world.voxel_tool.get_voxel(cell) == 0, "Final tick uses actual mining transaction")
	check(not world.failed and not mining.active and not mining.damage.has(cell), "Completion clears damage and target")
	check(material.get_shader_parameter("breaking_stage") == -1, "Completion removes cracks")
	var negative: Vector3i = Vector3i(-3, cell.y, -3)
	world.set_block(negative,id)
	mining.advance(0.05,negative,id)
	check(mining.damage.has(negative), "Negative coordinates retain distinct progress")
	mining.end_hold()
	check(not mining.held and not mining.active, "Release stops active hold")
	world.mining = mining
	check(await world.save_world(false,true), "save after mining completes")
	world.queue_free()
	await process_frame
	print("MINING_PROGRESS_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
