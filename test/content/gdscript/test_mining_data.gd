extends SceneTree
var checks: int = 0
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var project: AstraeonContentManifest = AstraeonContentManifest.new()
	project.package_id = "mining_test"
	var block: AstraeonBlockDefinition = AstraeonBlockDefinition.new()
	block.key = &"mining_test:block"
	block.appearance = AstraeonBlockAppearance.new()
	block.appearance.default_surface = AstraeonBlockSurface.new()
	block.hardness = 0.5
	block.required_tool_tag = &"test:dig"
	block.mining_recovery_seconds = 7.5
	var asset: AstraeonBlockAsset = AstraeonBlockAsset.new()
	asset.block = block
	project.blocks.append(asset)
	var item: AstraeonItemDefinition = AstraeonItemDefinition.new()
	item.key = &"mining_test:tool"
	item.tool_tags = PackedStringArray(["test:dig", "test:axe"])
	item.mining_speed = 4.0
	var tool: AstraeonItemAsset = AstraeonItemAsset.new()
	tool.item = item
	project.items.append(tool)
	var compiler: RefCounted = load("res://tools/content/compiler.gd").new()
	var path: String = "res://tmp/content/mining_data.aebpack"
	check(not compiler.build(project,path).has("error"), "Custom mining fields compile")
	var codec: RefCounted = ClassDB.instantiate("AstraeonContentPack")
	var data: Dictionary = codec.open_pack(path)
	check(not data.has("error"), "Native package reader accepts current schema")
	if data.has("error"):
		finish()
		return
	check(data.blocks[0].required_tool_tag == "test:dig" and data.blocks[0].mining_recovery_seconds == 7.5, "Single tag and custom recovery survive compilation")
	check(data.items[0].tool_tags.size() == 2 and data.items[0].mining_speed == 4.0, "Multiple tool tags and speed survive compilation")
	var runtime: AstraeonWorldContent = AstraeonWorldContent.new()
	check(runtime.build(PackedStringArray([path])) and runtime.item_catalog.definitions[0].tool_tags.has("test:dig") and runtime.item_catalog.definitions[0].mining_speed == 4.0, "Compiled fields reach runtime ItemDefinition")
	runtime.bundle.shutdown()
	var invalid: Dictionary = data.duplicate(true)
	invalid.items[0].erase("tool_tags")
	var writer: RefCounted = ClassDB.instantiate("AstraeonContentPack")
	check(writer.write_pack("res://tmp/content/rejected_mining.aebpack",invalid,{}).has("error"), "Old item schema rejected")
	invalid = data.duplicate(true)
	invalid.blocks[0].required_tool_tag = ["test:dig", "test:axe"]
	check(writer.write_pack("res://tmp/content/rejected_mining.aebpack",invalid,{}).has("error"), "Block requires exactly one string tag")
	invalid = data.duplicate(true)
	invalid.items[0].mining_speed = 0.0
	check(writer.write_pack("res://tmp/content/rejected_mining.aebpack",invalid,{}).has("error"), "Invalid native tool speed rejected")
	invalid = data.duplicate(true)
	invalid.items[0].tool_tags = [":dig"]
	check(writer.write_pack("res://tmp/content/rejected_mining.aebpack",invalid,{}).has("error"), "Native tag must contain a nonempty namespace")
	item.tool_tags.append("test:dig")
	check(compiler.build(project,path).has("error"), "Duplicate authoring tool tag rejected")
	item.tool_tags.remove_at(2)
	block.mining_recovery_seconds = -1.0
	check(compiler.build(project,path).has("error"), "Negative recovery rejected")
	block.mining_recovery_seconds = 30.0
	block.required_tool_tag = &"unnamespaced"
	check(compiler.build(project,path).has("error"), "Malformed block tag rejected")
	finish()
func finish() -> void:
	print("MINING_DATA_TEST ", JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
