extends SceneTree
## Functional source-project integration, no timing or performance acceptance.
const Fixture = preload("res://test/content/gdscript/authoring_fixture.gd")
const Compiler = preload("res://tools/content/compiler.gd")
const Resolver = preload("res://tools/content/project_resolver.gd")
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
	var original: AstraeonContentManifest = load("res://game/data/content/authoring/astraeon/pack.tres")
	var resolver: RefCounted = Resolver.new()
	var resolved: Dictionary = resolver.resolve(original)
	check(not resolved.has("error"), "builtin indexed sources resolve")
	if resolved.has("error"):
		printerr(resolved)
		quit(1)
		return
	check(resolved.blocks.size() == 5 and resolved.items.size() == 9 and original.fluids.size() == 1, "builtin complete resource inventory")
	check(resolver.source_hashes.size() == 7, "shared images resolve once")
	for asset: AstraeonBlockAsset in original.blocks:
		check(asset.block.appearance.breaking.stages_texture == null and asset.block.appearance.default_surface.albedo_texture == null and asset.item.block == null, "immutable authoring " + String(asset.block.key))
		var text: String = FileAccess.get_file_as_string(asset.resource_path)
		check(not text.contains('[ext_resource type="Resource"') and not text.contains('[ext_resource type="Texture2D"') and not text.contains('script/source'), "one block file embeds data, not code or pictures")
	var builtin_reader: RefCounted = ClassDB.instantiate("AstraeonContentPack")
	var builtin: Dictionary = builtin_reader.open_pack("res://game/data/content/packages/astraeon.aebpack")
	check(not builtin.has("error") and builtin.blocks.size() == 6 and builtin.items.size() == 9, "builtin package readable")
	var directory: String = "res://tmp/content/authoring_" + str(Time.get_ticks_usec())
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "isolated directory")
	var project: AstraeonContentManifest = AstraeonContentManifest.new()
	project.package_id = "authoring"
	var block: AstraeonBlockDefinition = AstraeonBlockDefinition.new()
	block.key = &"authoring:test"
	block.appearance = AstraeonBlockAppearance.new()
	block.appearance.default_surface = AstraeonBlockSurface.new()
	var asset: AstraeonBlockAsset = Fixture.add_block(project, block)
	asset.item = AstraeonItemDefinition.new()
	asset.item.key = &"authoring:test_item"
	var image: Image = Image.create(32,32,false,Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	Fixture.bind_image(project, asset, "surface/default", image)
	check(Fixture.save_project(project, directory + "/pack.tres") == OK, "save complete source project")
	var reloaded: AstraeonContentManifest = ResourceLoader.load(directory + "/pack.tres", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(reloaded.blocks[0].item != null and reloaded.blocks[0].block.appearance != null, "reload complete block")
	reloaded.blocks[0].block.hardness = 2.75
	check(ResourceSaver.save(reloaded.blocks[0], reloaded.blocks[0].resource_path) == OK, "secondary edit saves one file")
	var compiler: RefCounted = Compiler.new()
	var output: String = directory + "/test.aebpack"
	var result: Dictionary = compiler.build(reloaded, output)
	check(not result.has("error"), "build relative source: " + str(result))
	if result.has("error"):
		quit(1)
		return
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(output)
	check(not compiler.build(reloaded, output).has("error") and bytes == FileAccess.get_file_as_bytes(output), "deterministic rebuild")
	var key: StringName = reloaded.blocks[0].image_slots["surface/default"]
	var relative: String = reloaded.image_sources[key]
	var source: String = ProjectSettings.globalize_path(directory.path_join(relative))
	reloaded.image_sources[key] = source
	check(not compiler.build(reloaded, output).has("error") and bytes == FileAccess.get_file_as_bytes(output), "absolute and relative source paths produce identical binary")
	var codec: RefCounted = ClassDB.instantiate("AstraeonContentPack")
	var definition: Dictionary = codec.open_pack(output)
	check(definition.blocks[0].hardness == 2.75 and definition.items[0].block == "authoring:test", "updated logic and paired item compiled")
	check(not JSON.stringify(definition).contains(directory) and not JSON.stringify(definition).contains(source), "binary definitions contain no source paths")
	var hash: String = definition.blocks[0].visual
	check(DirAccess.remove_absolute(source) == OK, "remove isolated source picture")
	check(not codec.read_blob(hash).is_empty(), "exported texture works without its source")
	var missing: Dictionary = compiler.build(reloaded, output)
	check(missing.has("error") and source in String(missing.error) and bytes == FileAccess.get_file_as_bytes(output), "missing picture reports exact path and preserves pack")
	image.fill(Color.BLUE)
	check(image.save_png(source) == OK, "replace same indexed source")
	check(not compiler.build(reloaded, output).has("error") and bytes != FileAccess.get_file_as_bytes(output), "changed source pixels invalidate cache")
	bytes = FileAccess.get_file_as_bytes(output)
	reloaded.blocks[0].image_slots["invalid/slot"] = key
	check(compiler.build(reloaded,output).has("error") and bytes == FileAccess.get_file_as_bytes(output), "invalid slot rejected")
	reloaded.blocks[0].image_slots.erase("invalid/slot")
	reloaded.project_format = 1
	check(compiler.build(reloaded,output).has("error"), "old authoring format rejected")
	reloaded.project_format = 2
	reloaded.image_sources[key] = "user://forbidden.png"
	check(compiler.build(reloaded,output).has("error"), "implicit OS application path rejected")
	reloaded.image_sources[key] = source
	var file: FileAccess = FileAccess.open(source, FileAccess.WRITE)
	file.store_string("not an image")
	file.close()
	check(compiler.build(reloaded,output).has("error") and bytes == FileAccess.get_file_as_bytes(output), "corrupt image rejected without replacing pack")
	print("CONTENT_AUTHORING_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
