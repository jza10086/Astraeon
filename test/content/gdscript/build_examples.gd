extends SceneTree
const Fixture = preload("res://test/content/gdscript/authoring_fixture.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var manifest: Resource = load("res://game/data/content/gdscript/content_manifest.gd").new()
	manifest.package_id = "example"
	manifest.display_name = "Example blocks"
	for kind: String in ["stone", "leaves", "glow"]:
		var block: AstraeonBlockDefinition = AstraeonBlockDefinition.new()
		block.key = StringName("example:" + kind)
		block.display_name = kind.capitalize()
		block.load_policy = "on_demand"
		block.appearance = AstraeonBlockAppearance.new()
		var surface: AstraeonBlockSurface = AstraeonBlockSurface.new()
		block.appearance.default_surface = surface
		surface.base_color = Color(0.5, 0.6, 0.7) if kind == "stone" else Color.WHITE
		if kind == "leaves":
			surface.alpha_mode = AstraeonBlockSurface.AlphaMode.CUTOUT
			block.appearance.foliage_layers = true
			block.light_opacity = 1
			var image: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
			for y: int in range(32):
				for x: int in range(32):
					image.set_pixel(x, y, Color(0.1, 0.6, 0.15, 1.0 if (x / 4 + y / 4) % 2 == 0 else 0.0))
			surface.albedo_texture = ImageTexture.create_from_image(image)
		if kind == "glow":
			surface.emission_energy = 3.0
			block.light_emission = 15
			block.appearance.light = AstraeonBlockLightAppearance.new()
			block.appearance.light.energy = 2.0
		var asset: AstraeonBlockAsset = Fixture.add_block(manifest, block)
		var item: AstraeonItemDefinition = AstraeonItemDefinition.new()
		item.key = StringName("example:" + kind + "_item")
		item.display_name = block.display_name
		asset.item = item
		item.creative_group = &"example:blocks"
		
	DirAccess.make_dir_recursive_absolute("res://test/content/resources")
	var code: Error = Fixture.save_project(manifest, "res://test/content/resources/example_manifest.tres")
	var reloaded: Resource = ResourceLoader.load("res://test/content/resources/example_manifest.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	assert(reloaded.blocks.size() == 3 and reloaded.items.is_empty() and reloaded.blocks[0].item != null)
	assert(reloaded.blocks[1].image_slots.has("surface/default"))
	var compiler: RefCounted = load("res://tools/content/compiler.gd").new()
	var result: Dictionary = compiler.build(manifest, "res://tmp/content/example_sdk.aebpack")
	print("CONTENT_EXAMPLES_DONE save=", code, " result=", result)
	quit(1 if code != OK or result.has("error") else 0)
