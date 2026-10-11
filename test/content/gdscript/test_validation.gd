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
	var compiler: RefCounted = load("res://tools/content/compiler.gd").new()
	var manifest: Resource = load("res://game/data/content/gdscript/content_manifest.gd").new()
	manifest.package_id = "validation"
	var block: AstraeonBlockDefinition = AstraeonBlockDefinition.new()
	block.key = &"validation:block"
	block.appearance = AstraeonBlockAppearance.new()
	block.appearance.default_surface = AstraeonBlockSurface.new()
	var asset: AstraeonBlockAsset = Fixture.add_block(manifest, block)
	var path: String = "res://tmp/content/validation.aebpack"
	check(not compiler.build(manifest,path).has("error"), "Valid base package")
	var original: PackedByteArray = FileAccess.get_file_as_bytes(path)
	manifest.package_id = "../escape"
	check(compiler.build(manifest,path).has("error") and FileAccess.get_file_as_bytes(path)==original, "Traversal package ID rejected; previous output preserved")
	manifest.package_id = "validation"
	var duplicate: AstraeonContentBundle = AstraeonContentBundle.new()
	check(not duplicate.open(PackedStringArray([path,path])), "Duplicate package refused")
	manifest.dependencies = PackedStringArray(["absent"])
	compiler.build(manifest,path)
	var missing: AstraeonContentBundle = AstraeonContentBundle.new()
	check(not missing.open(PackedStringArray([path])), "Missing dependency refused")
	manifest.dependencies = PackedStringArray(["validation"])
	compiler.build(manifest,path)
	var cycle: AstraeonContentBundle = AstraeonContentBundle.new()
	check(not cycle.open(PackedStringArray([path])), "Dependency cycle refused")
	manifest.dependencies = PackedStringArray()
	compiler.build(manifest,path)
	var directory: String = "res://tmp/content/validation_world_" + str(Time.get_ticks_usec())
	var first: AstraeonContentBundle = AstraeonContentBundle.new()
	check(first.open(PackedStringArray([path]),directory), "Create persisted ID table")
	var keys: PackedStringArray = first.state_keys.duplicate()
	first.shutdown()
	block.appearance.default_surface.base_color = Color.RED
	compiler.build(manifest,path)
	var visual: AstraeonContentBundle = AstraeonContentBundle.new()
	check(visual.open(PackedStringArray([path]),directory) and keys==visual.state_keys, "Visual-only update preserves IDs")
	visual.shutdown()
	block.light_opacity = 1
	compiler.build(manifest,path)
	var logic: AstraeonContentBundle = AstraeonContentBundle.new()
	check(not logic.open(PackedStringArray([path]),directory), "Changed logical opacity refused")
	var registry: RefCounted = ClassDB.instantiate("AstraeonContentRegistry")
	var oversized: Dictionary = {"astraeon:air/default":"air".sha256_text()}
	for index: int in range(65536): oversized["validation:block_%d/default" % index] = "block".sha256_text()
	check(registry.resolve("res://tmp/content/invalid_capacity",oversized,PackedStringArray(["validation"])).has("error"), "uint16 state overflow refused")
	var old_directory: String = directory + "_old"
	DirAccess.make_dir_recursive_absolute(old_directory)
	var old: FileAccess = FileAccess.open(old_directory.path_join("0_0_0.avr"),FileAccess.WRITE)
	old.store_string("old prototype retained")
	old.close()
	check(registry.resolve(old_directory,{"astraeon:air/default":"air".sha256_text()},PackedStringArray(["astraeon"])).has("error") and FileAccess.get_file_as_string(old_directory.path_join("0_0_0.avr"))=="old prototype retained", "Old world refused without deletion")
	print("CONTENT_VALIDATION_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
