extends SceneTree
const Fixture = preload("res://test/content/gdscript/authoring_fixture.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var manifest: Resource = load("res://game/data/content/gdscript/content_manifest.gd").new()
	manifest.package_id = "shading_test"
	manifest.display_name = "Shading fixtures"
	var catalog: AstraeonBlockCatalog = load("res://test/shading/resources/blocks/catalog.tres")
	for block: AstraeonBlockDefinition in catalog.definitions:
		if block.appearance != null:
			var asset: AstraeonBlockAsset = Fixture.add_block(manifest, block.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as AstraeonBlockDefinition)
	var compiler: RefCounted = load("res://tools/content/compiler.gd").new()
	DirAccess.make_dir_recursive_absolute("res://test/content/resources")
	assert(Fixture.save_project(manifest, "res://test/content/resources/shading_manifest.tres") == OK)
	var result: Dictionary = compiler.build(manifest, "res://tmp/content/shading_test.aebpack")
	print("SHADING_PACK_DONE ", result)
	quit(1 if result.has("error") else 0)
