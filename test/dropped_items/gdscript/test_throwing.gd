extends SceneTree
const Settings: Script = preload("res://game/gameplay/inventory/gdscript/throw_settings.gd")
var checks: int = 0
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world: Node3D = load("res://game/core/main.tscn").instantiate()
	world.world_directory = "res://tmp/throw-test/" + str(Time.get_ticks_usec())
	world.shading_settings_path = world.world_directory + "/settings.cfg"
	preload("res://test/survival/gdscript/world_fixture.gd").prepare(world)
	root.add_child(world)
	var deadline: int = Time.get_ticks_msec() + 45000
	while not world.ready_to_play and not world.failed and Time.get_ticks_msec() < deadline:
		await process_frame
	check(world.ready_to_play, "World ready")
	if not world.ready_to_play:
		finish()
		return
	world._autosave_elapsed = -999.0
	world.dropped_items.set_physics_process(false)
	world.controller.set_physics_process(false)
	world.controller.visual.set_process(false)
	var drops: Node3D = world.dropped_items
	test_mining_launch(world)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var trajectory: Dictionary = drops.throw_trajectory()
	check(trajectory.origin.is_equal_approx(world.controller.visual.throw_origin()), "Uses animated hand position")
	check(is_equal_approx(trajectory.velocity.length(), 6.0), "Default speed is 6 m/s")
	check(trajectory.velocity.normalized().dot(trajectory.origin.direction_to(trajectory.target)) > 0.9999, "Launch converges to aim target")
	var hand: Skeleton3D = world.controller.visual.hand_skeleton
	var bone: int = world.controller.visual.hand_bone
	var old_pose: Vector3 = hand.get_bone_pose_position(bone)
	hand.set_bone_pose_position(bone, old_pose + Vector3(0.1,0,0))
	check(drops.throw_trajectory().origin.distance_to(trajectory.origin) > 0.09, "Launch point follows bone pose")
	hand.set_bone_pose_position(bone, old_pose)
	world.controller._apply_view(false)
	trajectory = drops.throw_trajectory()
	check(trajectory.origin.is_equal_approx(world.controller.visual.throw_origin()) and trajectory.velocity.normalized().dot(trajectory.origin.direction_to(trajectory.target)) > 0.9999, "Third-person converges from hand")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	root.warp_mouse(root.get_visible_rect().size * Vector2(0.75,0.35))
	await process_frame
	trajectory = drops.throw_trajectory()
	var projected: Vector2 = world.camera.unproject_position(trajectory.target)
	check(projected.distance_to(root.get_mouse_position()) < 1.0, "Free pointer chooses screen ray")
	# Actual paused-world control saves and applies the shared gameplay setting.
	var panel: VBoxContainer = world.shading.panel.category.get_parent().get_child(0) as VBoxContainer
	panel.strength.value = 11.5
	panel.mining_player_strength.value = 3.5
	(panel.get_node("SaveDropSettings") as Button).pressed.emit()
	check(is_equal_approx(drops.throw_settings.strength, 11.5), "World control applies strength")
	check(is_equal_approx(drops.throw_settings.mining_player_strength, 3.5), "World control applies mining bias")
	var loaded: Settings = Settings.new()
	check(loaded.load_settings(world.shading_settings_path) == OK and is_equal_approx(loaded.strength, 11.5), "Strength survives reload")
	check(is_equal_approx(loaded.mining_player_strength, 3.5), "Mining bias survives reload")
	trajectory = drops.throw_trajectory()
	check(is_equal_approx(trajectory.velocity.length(), 11.5), "Saved strength affects launch velocity")
	# Title settings keep changes in a draft until Save; Cancel reloads stored value.
	var title: Control = load("res://game/ui/main_menu/scenes/main_menu.tscn").instantiate()
	title.settings_path = world.shading_settings_path
	root.add_child(title)
	title._open_settings()
	check(is_equal_approx(title.throw_panel.strength.value, 11.5), "Title loads same setting")
	check(is_equal_approx(title.throw_panel.mining_player_strength.value, 3.5), "Title loads mining bias")
	title.throw_panel.mining_player_strength.value = 7.0
	title.throw_panel.strength.value = 3.0
	title._close_settings()
	title._open_settings()
	check(is_equal_approx(title.throw_panel.strength.value, 11.5), "Title cancel discards draft")
	check(is_equal_approx(title.throw_panel.mining_player_strength.value, 3.5), "Cancel discards mining draft")
	title.throw_panel.mining_player_strength.value = 2.0
	title.throw_panel.strength.value = 9.0
	title._apply_settings()
	check(loaded.load_settings(world.shading_settings_path) == OK and is_equal_approx(loaded.strength, 9.0), "Title save persists strength")
	check(is_equal_approx(loaded.mining_player_strength, 2.0), "Title saves mining bias")
	title._open_settings()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/throw-test/settings.png")
	var config: ConfigFile = ConfigFile.new()
	config.load(world.shading_settings_path)
	config.set_value("throwing", "strength", 100.0)
	config.save(world.shading_settings_path)
	check(Settings.new().load_settings(world.shading_settings_path) == ERR_INVALID_DATA, "Invalid strength rejects rather than substitutes")
	config.set_value("throwing", "strength", 6.0)
	config.set_value("mining_drops", "player_strength", -1.0)
	config.save(world.shading_settings_path)
	check(Settings.new().load_settings(world.shading_settings_path) == ERR_INVALID_DATA, "Reject negative bias")
	config.set_value("mining_drops", "player_strength", 10.5)
	config.save(world.shading_settings_path)
	check(Settings.new().load_settings(world.shading_settings_path) == ERR_INVALID_DATA, "Reject excessive bias")
	config.set_value("mining_drops", "player_strength", 0.0)
	config.set_value("mining_drops", "format", 999)
	config.save(world.shading_settings_path)
	check(Settings.new().load_settings(world.shading_settings_path) == ERR_FILE_UNRECOGNIZED, "Reject unknown mining settings format")
	finish()

func test_mining_launch(world: Node3D) -> void:
	var drops: Node3D = world.dropped_items
	check(drops.throw_settings.mining_player_strength == 0.0, "Default mining bias is zero")
	var position: Vector3i = Vector3i(4, int(world.generator.sample_column(4, 4).height), 4)
	var center: Vector3 = Vector3(position) + Vector3(0.5, 0.5, 0.5)
	var bounded: bool = true
	var origins: Dictionary[Vector3, bool] = {}
	var velocities: Dictionary[Vector3, bool] = {}
	drops._mining_rng.seed = 20260927
	for index: int in 64:
		var launch: Dictionary = drops.mining_trajectory(position)
		var offset: Vector3 = launch.origin - center
		var velocity: Vector3 = launch.velocity
		bounded = bounded and offset.abs().x <= 0.201 and offset.abs().y <= 0.201 and offset.abs().z <= 0.201 and absf(velocity.x) <= 1.0 and absf(velocity.z) <= 1.0 and velocity.y >= 3.0 and velocity.y <= 4.0
		origins[launch.origin] = true
		velocities[velocity] = true
	check(bounded and origins.size() > 1 and velocities.size() > 1, "Random spawn stays inside cell and launch always rises")
	drops._mining_rng.seed = 41
	var neutral: Dictionary = drops.mining_trajectory(position)
	drops.throw_settings.mining_player_strength = 5.0
	drops._mining_rng.seed = 41
	var biased: Dictionary = drops.mining_trajectory(position)
	var direction: Vector3 = world.player.position - neutral.origin
	direction.y = 0.0
	check(biased.origin == neutral.origin and (biased.velocity - neutral.velocity).is_equal_approx(direction.normalized() * 5.0), "Bias is one horizontal player-directed impulse")
	check(is_equal_approx(biased.velocity.y, neutral.velocity.y), "Player height never cancels bounce")
	var player_position: Vector3 = world.player.position
	world.player.position = neutral.origin
	drops._mining_rng.seed = 41
	check(drops.mining_trajectory(position).velocity == neutral.velocity, "Coincident player stays finite with zero bias direction")
	world.player.position = player_position
	drops.throw_settings.mining_player_strength = 0.0
	drops._mining_rng.seed = 73
	var expected: Dictionary = drops.mining_trajectory(position)
	drops._mining_rng.seed = 73
	check(world.inventory_interaction.edit(position, false), "Production mining succeeds")
	var records: Array = drops.pool.call("nearby", center, 1.0, false)
	check(records.size() == 1 and records[0].position.is_equal_approx(expected.origin) and records[0].velocity.is_equal_approx(expected.velocity), "Native drop receives randomized launch")
	drops.pool.call("step", 1.0 / 60.0, world.player.position, world.voxel_tool)
	records = drops.pool.call("nearby", center, 1.0, false)
	check(records.size() == 1 and records[0].position.y > expected.origin.y, "Removed voxel allows actual upward bounce")

func finish() -> void:
	print("THROWING_TEST ", JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
