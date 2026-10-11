extends SceneTree
var checks: int = 0
var failures: int = 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var registry: RefCounted = ClassDB.instantiate("AstraeonContentRegistry")
	var directory: String = "res://tmp/content/world_" + str(Time.get_ticks_usec())
	var contracts: Dictionary = {"astraeon:air/default": "air".sha256_text(), "astraeon:stone/default": "stone".sha256_text()}
	var first: Dictionary = registry.call("resolve", directory, contracts, PackedStringArray(["astraeon"]))
	check(not first.has("error"), "new registry")
	var expanded: Dictionary = contracts.duplicate()
	expanded["a:first/default"] = "first".sha256_text()
	var second: Dictionary = registry.call("resolve", directory, expanded, PackedStringArray(["astraeon"]))
	check(not second.has("error") and second.state_keys[1] == "astraeon:stone/default" and second.state_keys[2] == "a:first/default", "append preserves previous IDs")
	check(second.world_id == first.world_id, "identity stable")
	check(registry.call("resolve", directory, contracts, PackedStringArray(["astraeon"])).has("error"), "missing mod refused")
	var incompatible: Dictionary = expanded.duplicate()
	incompatible["astraeon:stone/default"] = "changed".sha256_text()
	check(registry.call("resolve", directory, incompatible, PackedStringArray(["astraeon"])).has("error"), "logical change refused")
	var damaged: FileAccess = FileAccess.open(directory.path_join("content_registry.0"), FileAccess.WRITE)
	damaged.store_string("interrupted")
	damaged.close()
	var recovered: Dictionary = registry.call("resolve", directory, expanded, PackedStringArray(["astraeon"]))
	check(not recovered.has("error") and recovered.state_keys == second.state_keys, "single record recovery")
	var content: AstraeonWorldContent = AstraeonWorldContent.new()
	check(content.build(PackedStringArray(["res://game/data/content/packages/astraeon.aebpack"])), "compiled world content: " + content.error)
	if content.bundle != null and content.bundle.visuals != null:
		var cache: RefCounted = content.bundle.visuals
		check(cache.configure({"visual_warm_seconds": 0}), "visual cache configured")
		var hashes: PackedStringArray = []
		for record: Dictionary in content.bundle.blocks.values():
			if not String(record.visual).is_empty() and not hashes.has(record.visual):
				hashes.append(record.visual)
		check(int(cache.get_metrics().reads) == 0, "opening metadata does not read visual payloads")
		cache.request("test", hashes)
		var deadline: int = Time.get_ticks_msec() + 10000
		while not cache.is_ready(hashes) and Time.get_ticks_msec() < deadline:
			cache.commit()
			await process_frame
		check(cache.is_ready(hashes), "asynchronous visuals become ready")
		var reads: int = int(cache.get_metrics().reads)
		var uploads: int = int(cache.get_metrics().uploads)
		cache.release("test")
		cache.request("return", hashes)
		cache.commit()
		check(int(cache.get_metrics().reads) == reads and int(cache.get_metrics().uploads) == uploads, "warm/pinned hit does not read or upload")
		check(content.item_catalog.validate().is_empty(), "compiled items accepted")
		content.bundle.shutdown()
	var mod_content: AstraeonWorldContent = AstraeonWorldContent.new()
	check(mod_content.build(PackedStringArray(["res://tmp/content/example_sdk.aebpack"])), "SDK on-demand content")
	if mod_content.library != null:
		var cache: RefCounted = mod_content.bundle.visuals
		var wanted: PackedStringArray = []
		for block: Dictionary in mod_content.bundle.blocks.values():
			if not String(block.visual).is_empty(): wanted.append(block.visual)
		check(cache.get_metrics().gpu_bytes == 0 and cache.get_metrics().reads == 0, "Unused Mod allocates no GPU or payload reads")
		cache.request("visible-a", wanted)
		cache.request("visible-b", wanted)
		await ready(cache, wanted)
		check(cache.is_ready(wanted), "On-demand first load")
		cache.configure({"visual_warm_seconds": 0})
		cache.release("visible-a")
		cache.commit()
		check(cache.is_ready(wanted), "Other section reference protects resource")
		cache.release("visible-b")
		cache.commit()
		check(cache.get_metrics().gpu_bytes == 0 and cache.get_metrics().cpu_bytes == 0, "Unreferenced texture reclaimed")
		var before: int = int(cache.get_metrics().uploads)
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = preload("res://game/shading/shaders/voxel_light.gdshader")
		material.set_shader_parameter("ambient_minimum", 0.017)
		cache.bind_material(wanted[0], material)
		cache.request("reload", wanted)
		await ready(cache, wanted)
		check(cache.is_ready(wanted) and int(cache.get_metrics().uploads) == before + wanted.size(), "Reclaimed resource loads again")
		check(is_equal_approx(material.get_shader_parameter("ambient_minimum"), 0.017) and material.get_shader_parameter("block_atlas") != null, "Reload preserves environment binding")
		cache.release("reload")
		cache.request("cancelled-world", wanted)
		mod_content.bundle.shutdown()
		check(cache.get_metrics().gpu_bytes == 0 and cache.get_metrics().pending == 0, "World shutdown drains tasks and GPU refs")
	print("CONTENT_RUNTIME_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func ready(cache: RefCounted, wanted: PackedStringArray) -> void:
	var deadline: int = Time.get_ticks_msec() + 10000
	while not cache.is_ready(wanted) and Time.get_ticks_msec() < deadline:
		cache.commit()
		await process_frame
