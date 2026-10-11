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
	var content: AstraeonWorldContent = AstraeonWorldContent.new()
	check(content.build(PackedStringArray(["res://game/data/content/packages/astraeon.aebpack"])), "current compiled pack: " + content.error)
	if not content.error.is_empty():
		quit(1)
		return
	var blocks: Dictionary = content.bundle.blocks
	var common: Dictionary = blocks["astraeon:grass"].breaking
	var wood: Dictionary = blocks["astraeon:log"].breaking
	check(common.visual != wood.visual, "two distinct original groups")
	check(blocks["astraeon:dirt"].breaking.visual == common.visual and blocks["astraeon:leaves"].breaking.visual == common.visual, "shared common group")
	check(common.stages == 10 and wood.stages == 10 and common.resolution == 32, "ten 32px stages")
	var cache: RefCounted = content.bundle.visuals
	check(not cache.is_ready(PackedStringArray([common.visual, wood.visual])), "unused breaking payload is not uploaded")
	var hashes: PackedStringArray = [common.visual, wood.visual]
	var ids: PackedInt32Array = PackedInt32Array([content.grass_id, content.state_keys.find("astraeon:log/axis_y"), content.state_keys.find("astraeon:leaves/default")])
	hashes.append_array(content.bundle.state_visuals(ids))
	check(cache.request("breaking-test", hashes), "request native cached masks")
	var deadline: int = Time.get_ticks_msec() + 15000
	while not cache.is_ready(hashes) and Time.get_ticks_msec() < deadline:
		cache.commit()
		await process_frame
	check(cache.is_ready(hashes), "masks load through native visual cache")
	var reads: int = cache.get_metrics().reads
	var codec: RefCounted = ClassDB.instantiate("AstraeonContentPack")
	codec.open_pack("res://game/data/content/packages/astraeon.aebpack")
	for group: Dictionary in [common, wood]:
		var payload: PackedByteArray = codec.read_blob(group.visual)
		check(payload.size() == 16 + 320 * 32 * 4, "compiled mask dimensions")
		var pixels: Image = Image.create_from_data(320,32,false,Image.FORMAT_RGBA8,payload.slice(16))
		var monotonic: bool = true
		for stage: int in range(1,10):
			for y: int in range(32):
				for x: int in range(32):
					if pixels.get_pixel(stage*32+x,y).r < pixels.get_pixel((stage-1)*32+x,y).r:
						monotonic = false
		check(monotonic, "stage cracks never disappear")
	var visual: RefCounted = load("res://game/shading/blocks/gdscript/breaking_visual.gd").new()
	visual.configure(content)
	check(visual.prepare(ids[0]), "target presenter ready")
	var material: ShaderMaterial = content.library.models[ids[0]].get_material_override(0)
	for stage: int in range(10):
		visual.show_progress(Vector3i(-17,2,-1), float(stage)/10.0+0.001)
		check(material.get_shader_parameter("breaking_stage") == stage, "discrete stage %d" % stage)
	check(material.get_shader_parameter("breaking_target") == Vector3(-17,2,-1), "negative target coordinates")
	visual.clear()
	check(material.get_shader_parameter("breaking_stage") == -1 and material.get_shader_parameter("breaking_texture") == null, "cancel clears rendering and texture ownership")
	check(cache.get_metrics().reads == reads, "stages do not reread textures")
	# Validate malformed authoring without touching the deployed pack.
	var manifest: Resource = load("res://game/data/content/gdscript/content_manifest.gd").new()
	manifest.package_id = "breaking_test"
	var block: AstraeonBlockDefinition = AstraeonBlockDefinition.new()
	block.key = &"breaking_test:bad"
	block.appearance = AstraeonBlockAppearance.new()
	block.appearance.default_surface = AstraeonBlockSurface.new()
	block.appearance.breaking = AstraeonBreakingTextureGroup.new()
	block.appearance.breaking.stages_texture = ImageTexture.create_from_image(Image.create(32,32,false,Image.FORMAT_RGBA8))
	var asset: AstraeonBlockAsset = Fixture.add_block(manifest, block)
	var built: Dictionary = load("res://tools/content/compiler.gd").new().build(manifest,"res://tmp/content/invalid_breaking.aebpack")
	check(built.has("error"), "reject non-ten-stage strip")
	# Real shader render on native preview meshes; per-cube material copies exist only in this test.
	root.size = Vector2i(1440,900)
	var scene: Node3D = Node3D.new()
	root.add_child(scene)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12,0.16,0.2)
	scene.add_child(environment)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 11.0
	camera.cull_mask = 1
	scene.add_child(camera)
	camera.position = Vector3(4,3,18)
	camera.look_at(Vector3(0,0.5,0))
	camera.current = true
	for row: int in range(3):
		for column: int in range(5):
			var node: MeshInstance3D = MeshInstance3D.new()
			var buffer: VoxelBuffer = VoxelBuffer.new()
			buffer.create(3,3,3)
			buffer.set_voxel(ids[row],1,1,1,VoxelBuffer.CHANNEL_TYPE)
			var mesher: VoxelMesherBlocky = VoxelMesherBlocky.new()
			mesher.library = content.library
			node.mesh = mesher.build_mesh(buffer,[])
			node.position = Vector3(column*2-4,row*2-2,0)
			var mat: ShaderMaterial = content.library.models[ids[row]].get_material_override(0).duplicate() as ShaderMaterial
			mat.set_shader_parameter("ambient_minimum",1.0)
			mat.set_shader_parameter("ambient_minimum_color",Color(0.8,0.8,0.8))
			mat.set_shader_parameter("wind_enabled",false)
			mat.set_shader_parameter("breaking_texture",cache.texture(wood.visual if row==1 else common.visual))
			mat.set_shader_parameter("breaking_target",node.position)
			mat.set_shader_parameter("breaking_stage",[-1,0,3,6,9][column])
			node.material_override = mat
			scene.add_child(node)
	var caption: Label = Label.new()
	caption.text = "LEAVES / WOOD / COMMON (top to bottom)\nLeft to right: untouched, stage 0, stage 3, stage 6, stage 9"
	caption.position = Vector2(30,30)
	caption.add_theme_font_size_override("font_size",24)
	root.add_child(caption)
	for frame: int in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://tmp/content/breaking_stages.png") == OK, "save shader comparison")
	scene.queue_free()
	await process_frame
	cache.release("breaking-test")
	content.bundle.shutdown()
	print("BREAKING_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
