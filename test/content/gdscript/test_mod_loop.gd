extends SceneTree
const Fixture = preload("res://test/content/gdscript/authoring_fixture.gd")
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
	var manifest: Resource = load("res://game/data/content/gdscript/content_manifest.gd").new()
	manifest.package_id = "example"
	var definition: AstraeonBlockDefinition = AstraeonBlockDefinition.new()
	definition.key = &"example:crystal"
	definition.display_name = "Mod Crystal"
	definition.load_policy = "on_demand"
	definition.appearance = AstraeonBlockAppearance.new()
	definition.appearance.default_surface = AstraeonBlockSurface.new()
	definition.appearance.default_surface.base_color = Color(0.3, 0.8, 0.9)
	var pixels: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.WHITE)
	pixels.fill_rect(Rect2i(0, 0, 16, 16), Color(0.8, 0.5, 0.2))
	definition.appearance.default_surface.albedo_texture = ImageTexture.create_from_image(pixels)
	var asset: AstraeonBlockAsset = Fixture.add_block(manifest, definition)
	var item: AstraeonItemDefinition = AstraeonItemDefinition.new()
	item.key = &"example:crystal_item"
	item.display_name = "Mod Crystal"
	asset.item = item
	item.creative_group = &"example:building"
	
	var compiler: RefCounted = load("res://tools/content/compiler.gd").new()
	check(not compiler.build(manifest, "res://tmp/content/example.aebpack").has("error"), "compile mod")
	var directory: String = "res://tmp/content/mod_world_" + str(Time.get_ticks_usec())
	var original: AstraeonWorldContent = AstraeonWorldContent.new()
	check(original.build(PackedStringArray(["res://game/data/content/packages/astraeon.aebpack"]), directory), "create base world registry")
	var previous: PackedStringArray = original.state_keys.duplicate()
	original.bundle.shutdown()
	var world: Node3D = load("res://game/core/main.tscn").instantiate()
	world.world_directory = directory
	world.shading_settings_path = "res://tmp/content/test_settings.cfg"
	world.content_packages = PackedStringArray(["res://tmp/content/example.aebpack", "res://game/data/content/packages/astraeon.aebpack"])
	world.horizontal_distance = 16
	world.vertical_distance = 16
	preload("res://test/survival/gdscript/world_fixture.gd").prepare(world)
	root.add_child(world)
	var deadline: int = Time.get_ticks_msec() + 45000
	while not world.ready_to_play and Time.get_ticks_msec() < deadline:
		await process_frame
	check(world.ready_to_play, "main world playable: " + str(world.get("_status").text))
	if world.ready_to_play:
		check(world.content.state_keys.slice(0, previous.size()) == previous, "mod does not reorder old IDs")
		var id: int = world.content.state_keys.find("example:crystal/default")
		var hashes: PackedStringArray = world.content.bundle.state_visuals(PackedInt32Array([id]))
		var cache: RefCounted = world.content.bundle.visuals
		check(not cache.is_ready(hashes), "unused on-demand texture remains unloaded")
		cache.request("test-placement", hashes)
		deadline = Time.get_ticks_msec() + 10000
		while not cache.is_ready(hashes) and Time.get_ticks_msec() < deadline:
			await process_frame
		check(cache.is_ready(hashes), "mod texture loads on demand")
		var position: Vector3i = Vector3i(world.player.position) + Vector3i(2, 0, 0)
		world.set_game_mode(1)
		check(world.inventory.creative_pick(&"example:crystal_item", true), "creative catalog selection")
		check(world.inventory.click_slot(0), "put selected mod item in hotbar")
		world.inventory.select(0)
		world.set_block(position, 0)
		check(world.inventory_interaction.edit(position, true), "place mod through inventory transaction")
		check(world.voxel_tool.get_voxel(position) == id, "place compiled mod state")
		check(world.inventory.items.has(&"example:crystal_item"), "mod appears in creative item registry")
		check(world.inventory_interaction.edit(position, false), "mine mod through inventory transaction")
		check(world.inventory_interaction.edit(position, true), "replace mined mod through transaction")
		check(await world.save_world(false, true), "durable mod section and inventory save")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/content/mod_world.png")
		var identity: String = world.content.bundle.world_id
		world.queue_free()
		await process_frame
		var restored: AstraeonWorldContent = AstraeonWorldContent.new()
		check(restored.build(PackedStringArray(["res://game/data/content/packages/astraeon.aebpack", "res://tmp/content/example.aebpack"]), directory), "reopen with reversed package order")
		var stream: AstraeonNativeStream = AstraeonNativeStream.new()
		check(stream.open_world(directory, 20260916, 0, restored.state_keys, identity), "open format 3 regions")
		var buffer: VoxelBuffer = VoxelBuffer.new()
		buffer.create(16, 16, 16)
		var section: Vector3i = Vector3i(floori(position.x / 16.0), floori(position.y / 16.0), floori(position.z / 16.0))
		stream.load_voxel_block(buffer, section, 0)
		check(buffer.get_voxel_v(position - section * 16) == id, "mod state survives world reopen")
		restored.bundle.shutdown()
	else:
		world.queue_free()
		await process_frame
	print("CONTENT_MOD_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
