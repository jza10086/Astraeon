extends SceneTree
## Native mesher regression plus opt-in real renderer captures. No user settings or saves.
const Foliage: Script = preload("res://game/shading/blocks/gdscript/foliage_rendering.gd")
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
const LEAF: AstraeonBlockDefinition = preload("res://test/data/resources/block_reference/astraeon_leaves.tres")
const STONE: AstraeonBlockDefinition = preload("res://test/shading/resources/blocks/shading_test_stone.tres")
var checks: int = 0
var failures: int = 0
var report: Array[String] = []
var source: VoxelBlockyLibrary

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	report.append(("%s: " % ("PASS" if value else "FAIL")) + message)
	if not value:
		failures += 1
		push_error(message)

func faces(mesh: Mesh) -> int:
	var indices: int = 0
	if mesh != null:
		for surface: int in range(mesh.get_surface_count()):
			indices += mesh.surface_get_array_index_len(surface)
	return indices / 6

func buffer(depth: int) -> VoxelBuffer:
	var result: VoxelBuffer = VoxelBuffer.new()
	result.create(5, 5, 10)
	result.set_channel_depth(VoxelBuffer.CHANNEL_TYPE, VoxelBuffer.DEPTH_16_BIT)
	var tool: VoxelTool = result.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	tool.value = 1
	tool.do_box(Vector3i(2, 2, 2), Vector3i(2, 2, 1 + depth))
	return result

func _run() -> void:
	print("FOLIAGE_PROCESS ", JSON.stringify({"pid": OS.get_process_id(), "executable": OS.get_executable_path(), "project": ProjectSettings.globalize_path("res://"), "started": Time.get_datetime_string_from_system(), "purpose": "foliage regression/captures"}))
	DirAccess.make_dir_recursive_absolute("res://tmp/foliage")
	source = VoxelBlockyLibrary.new()
	source.models = [VoxelBlockyModelEmpty.new(), AstraeonBlockLibraryBuilder.build_block(LEAF, Basis.IDENTITY), AstraeonBlockLibraryBuilder.build_block(STONE, Basis.IDENTITY)]
	source.bake()
	check(not source.models[1].culls_neighbors, "Authoring enables internal leaves")
	check(source.models[2].culls_neighbors, "Opaque blocks still hide neighbors")
	check((source.models[1].get_material_override(0) as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_BACK, "Layered material uses back-face culling")
	var original_opacity: int = LEAF.light_opacity
	for mode: int in range(3):
		var library: VoxelBlockyLibrary = Foliage.with_mode(source, mode)
		var mesher: VoxelMesherBlocky = VoxelMesherBlocky.new()
		mesher.library = library
		check(not source.models[1].culls_neighbors, "Mode %d preserves source geometry policy" % mode)
		for depth: int in [1, 2, 4]:
			var actual: int = faces(mesher.build_mesh(buffer(depth), []))
			var expected: int = 4 * depth + 2 if mode == 0 else 6 * depth
			check(actual == expected, "Mode %d depth %d: %d faces expected %d" % [mode, depth, actual, expected])
		var neighbor: VoxelBuffer = buffer(1)
		neighbor.set_voxel(2, 2, 2, 3, VoxelBuffer.CHANNEL_TYPE)
		check(faces(mesher.build_mesh(neighbor, [])) == 11, "Opaque/leaf contact hides leaf face, retains solid behind holes")
		# Two padded sections meet at world x=0 (-16 and 0), exposing the same boundary policy.
		var total: int = 0
		for side: int in range(2):
			var section: VoxelBuffer = VoxelBuffer.new()
			section.create(18, 18, 18)
			section.set_channel_depth(VoxelBuffer.CHANNEL_TYPE, VoxelBuffer.DEPTH_16_BIT)
			section.set_voxel(1, 16 if side == 0 else 0, 3, 3, VoxelBuffer.CHANNEL_TYPE)
			section.set_voxel(1, 17 if side == 0 else 1, 3, 3, VoxelBuffer.CHANNEL_TYPE)
			total += faces(mesher.build_mesh(section, []))
		check(total == (10 if mode == 0 else 12), "Negative/positive section seam matches interior culling")
		var shader_material: ShaderMaterial = ShaderMaterial.new()
		shader_material.set_shader_parameter("base_color", Color.GREEN)
		Foliage.apply_material(shader_material, mode)
		check(shader_material.shader == (Foliage.DOUBLE if mode == 0 else Foliage.SINGLE), "Mode selects matching sidedness")
		check(shader_material.get_shader_parameter("foliage_staggered") == (mode == 2), "Mode selects stable UV staggering")
		check(shader_material.get_shader_parameter("base_color") == Color.GREEN, "Shader switch retains bound uniforms")
	check(LEAF.light_opacity == original_opacity, "Rendering never edits logical opacity")
	var invalid: AstraeonBlockAppearance = STONE.appearance.duplicate(true) as AstraeonBlockAppearance
	invalid.foliage_layers = true
	check(not invalid.validate().is_empty(), "Reject layered opaque authoring")
	var profile: Profile = Profile.new()
	profile.foliage_mode = 2
	check(profile.save_settings("res://tmp/foliage/settings.cfg") == OK, "Save foliage mode")
	var restored: Profile = Profile.new()
	check(restored.load_settings("res://tmp/foliage/settings.cfg") == OK and restored.foliage_mode == 2, "Reload foliage mode")
	check(Profile.new().foliage_mode == 1, "Default is layered without texture change")
	_world_policy_check()
	if "--visual" in OS.get_cmdline_user_args():
		await _visual()
	var file: FileAccess = FileAccess.open("res://tmp/foliage/results.md", FileAccess.WRITE)
	file.store_string("# Foliage regression\n\n" + "\n".join(report) + "\n")
	file.close()
	print("FOLIAGE_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _world_policy_check() -> void:
	# Actual production orchestration/native terrain, outside the tree: no world generation or saves.
	var world: Node3D = preload("res://game/world/gdscript/native_world.gd").new()
	var content: AstraeonWorldContent = AstraeonWorldContent.new()
	content.library = source
	world.set("content", content)
	var terrain: VoxelTerrain = VoxelTerrain.new()
	var mesher: VoxelMesherBlocky = VoxelMesherBlocky.new()
	mesher.library = source
	terrain.mesher = mesher
	world.set("terrain", terrain)
	var shading: AstraeonWorldShading = AstraeonWorldShading.new()
	shading.world = world
	var settings: Profile = Profile.new()
	shading.set("_settings", settings)
	shading.call("_apply_foliage")
	check(terrain.mesher != mesher and not content.library.models[1].culls_neighbors, "World installs fresh native mesher dependency")
	var layered_mesher: VoxelMesherBlocky = terrain.mesher as VoxelMesherBlocky
	settings.foliage_mode = 2
	shading.call("_apply_foliage")
	check(terrain.mesher == layered_mesher, "UV-only switch retains native mesher/cache")
	settings.foliage_mode = 0
	shading.call("_apply_foliage")
	check(terrain.mesher != layered_mesher and content.library.models[1].culls_neighbors, "Shell switch invalidates geometry dependency")
	settings.foliage_mode = 1
	shading.call("_apply_foliage")
	check(not content.library.models[1].culls_neighbors and terrain.mesher.library == content.library, "World restores layers and shared content library")
	check(LEAF.appearance.foliage_layers, "World policy leaves shared authoring resource intact")
	shading.free()
	terrain.free()
	world.free()

func _visual() -> void:
	root.size = Vector2i(1920, 1080)
	var packed: PackedScene = load("res://test/shading/scenes/shading_sample.tscn")
	var sample: Node3D = packed.instantiate()
	sample.set("settings_path", "res://tmp/foliage/visual_settings.cfg")
	root.add_child(sample)
	sample.call("_start")
	var settings: Profile = sample.get("_settings")
	settings.hour = 12.0
	settings.cycle_enabled = false
	settings.wind_enabled = false
	settings.max_fps = 120
	sample.call("_apply_lighting")
	var deadline: int = Time.get_ticks_msec() + 60000
	while not sample.get("_volume").is_settled() or sample.get("_sections").pending_count() > 0 or sample.get("_uploaded_revision") != sample.get("_volume").revision:
		await process_frame
		if Time.get_ticks_msec() > deadline:
			check(false, "Visual fixture settles within 60 seconds")
			sample.queue_free()
			return
	var revision: int = sample.get("_volume").revision
	sample.get("_settings_panel").show_setting(&"foliage_mode")
	# Actual UI callbacks exercise settings, persistence, and native rebuild paths.
	for mode: int in [0, 1, 2, 1, 0, 2]:
		var widget: OptionButton = sample.get("_settings_panel").widgets[&"foliage_mode"]
		widget.select(mode)
		widget.item_selected.emit(mode)
		while sample.get("_sections").pending_count() > 0:
			await process_frame
		check(sample.get("_volume").revision == revision, "Mode %d leaves lighting revision unchanged" % mode)
		check(sample.get("_sections").materials[3].shader == (Foliage.DOUBLE if mode == 0 else Foliage.SINGLE), "Sample applies mode %d shader" % mode)
		sample.call("_view", Vector3(-10, 4, -9), Vector3(-10, 3, -19))
		for frame: int in range(12):
			await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://tmp/foliage/mode_%d.png" % mode) == OK, "Capture mode %d" % mode)
	# Oblique, opposite, and moving foliage also exercise shadow render variants.
	settings.wind_enabled = true
	sample.call("_apply_lighting")
	sample.call("_view", Vector3(-23, 5, -10), Vector3(-10, 3, -20))
	for frame: int in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://tmp/foliage/oblique.png") == OK, "Capture oblique wind")
	sample.queue_free()
	await process_frame
